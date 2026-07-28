## isonim-docs Layer 3 — symbol reference ViewModel (M8 deliverables 1 & 2).
##
## Pure, dual-target transform from the ingested `nimdoc.NimModule` into a
## render-ready ViewModel for a library API reference page: a left symbol
## index (nav) + a center per-symbol reference (signature, docstring,
## pragmas, generics). Every exported symbol gets a stable, deep-linkable
## anchor id (M8 deliverable 2) minted through the shared
## `anchors.AnchorIdRegistry` (via `nextRawId`, which preserves the
## case-sensitive `sym-Type.proc` form) -- the exact same registry the
## markdown heading anchors (M2) and OpenAPI operation anchors (M7) use, so
## a symbol anchor dedups identically and plugs into the same cross-link /
## anchor resolution. `symbolIndexEntries`/`addSymbolIndexEntries` expose
## the `query -> href` map the reference checker resolves `[[sym:...]]`
## cross-references against.
##
## No platform/CSS imports (only `std/[strutils, tables]`, `core/nimdoc`,
## `core/anchors`), so it is headless-testable on both `nim c` and
## `nim js`, exactly like `api_reference_vm.nim`.

import std/tables
import ./nimdoc
import ./anchors

type
  SymbolNavEntry* = object
    anchorId*: string
    displayName*: string
    kindLabel*: string

  SymbolEntryViewModel* = object
    anchorId*: string
    displayName*: string   ## "Vec2" for a type, "Vec2.len2" for a grouped routine
    name*: string          ## the bare symbol name
    kindLabel*: string     ## "proc" / "func" / "type" / ...
    signature*: string
    generics*: string
    docstring*: string
    pragmas*: seq[string]
    ownerType*: string

  SymbolReferenceViewModel* = object
    title*: string
    moduleName*: string
    moduleDoc*: string
    navEntries*: seq[SymbolNavEntry]
    symbols*: seq[SymbolEntryViewModel]
    errors*: seq[string]

proc kindLabel*(kind: NimSymbolKind): string =
  case kind
  of nskType: "type"
  of nskProc: "proc"
  of nskFunc: "func"
  of nskTemplate: "template"
  of nskMacro: "macro"
  of nskIterator: "iterator"
  of nskConverter: "converter"
  of nskMethod: "method"

proc symbolDisplayName*(sym: NimSymbol): string =
  ## The dotted display name a reference page shows and a `[[sym:...]]`
  ## cross-reference targets: `Owner.name` for a routine grouped under a
  ## type, the bare `name` otherwise.
  if sym.ownerType.len > 0: sym.ownerType & "." & sym.name else: sym.name

proc symbolBaseId*(sym: NimSymbol): string =
  ## The base (pre-dedup) anchor id for `sym`: `sym-Vec2` for a type,
  ## `sym-Vec2.len2` for a routine grouped under `Vec2`, `sym-freeProc`
  ## otherwise -- case preserved (see `anchors.nextRawId`).
  "sym-" & symbolDisplayName(sym)

proc symbolAnchorIds*(module: NimModule): seq[string] =
  ## The deep-link anchor ids a symbol-reference page exposes, in symbol
  ## order -- rebuilt with a fresh registry, matching
  ## `buildSymbolReferenceViewModel` exactly (mirrors
  ## `api_reference_vm.operationAnchorIds`).
  var reg = newAnchorIdRegistry()
  for sym in module.symbols:
    result.add reg.nextRawId(symbolBaseId(sym))

proc queryKeysFor*(sym: NimSymbol; moduleName: string): seq[string] =
  ## Every `[[sym:...]]` query form that should resolve to `sym`: the
  ## dotted display name and, when a module name is known, its
  ## module-qualified form -- so `[[sym:Vec2.len2]]`, `[[sym:Vec2]]`, and
  ## `[[sym:mymodule.Vec2]]` all resolve.
  let disp = symbolDisplayName(sym)
  result.add disp
  if moduleName.len > 0:
    result.add moduleName & "." & disp

proc addSymbolIndexEntries*(index: var Table[string, string]; module: NimModule;
                            routePath: string) =
  ## Adds `module`'s `query -> href` cross-reference entries (href =
  ## `routePath#anchorId`) into `index`. Anchor ids are minted in the exact
  ## same order/registry `buildSymbolReferenceViewModel` uses, so a link's
  ## resolved href matches the page's real anchor. First writer wins on a
  ## key collision, so an earlier module's symbol isn't clobbered by a
  ## later module's same-named one (the module-qualified key stays unique
  ## either way).
  var reg = newAnchorIdRegistry()
  for sym in module.symbols:
    let anchor = reg.nextRawId(symbolBaseId(sym))
    let href = routePath & "#" & anchor
    for key in queryKeysFor(sym, module.name):
      if not index.hasKey(key): index[key] = href

proc buildSymbolReferenceViewModel*(ingest: NimDocIngest; fallbackTitle: string = ""):
    SymbolReferenceViewModel =
  ## Assembles the render-ready ViewModel from an ingested Nim module.
  ## Tolerant: `ingest.errors` are carried through so the page can show an
  ## error notice for unparseable source instead of the caller crashing.
  let module = ingest.module
  result.moduleName = module.name
  result.moduleDoc = module.moduleDoc
  result.errors = ingest.errors
  result.title =
    if module.name.len > 0: module.name
    else: fallbackTitle

  var reg = newAnchorIdRegistry()
  for sym in module.symbols:
    let anchorId = reg.nextRawId(symbolBaseId(sym))
    let disp = symbolDisplayName(sym)
    result.symbols.add SymbolEntryViewModel(
      anchorId: anchorId,
      displayName: disp,
      name: sym.name,
      kindLabel: kindLabel(sym.kind),
      signature: sym.signature,
      generics: sym.generics,
      docstring: sym.docstring,
      pragmas: sym.pragmas,
      ownerType: sym.ownerType)
    result.navEntries.add SymbolNavEntry(
      anchorId: anchorId, displayName: disp, kindLabel: kindLabel(sym.kind))
