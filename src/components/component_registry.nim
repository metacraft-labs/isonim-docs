## isonim-docs Layer 2 — consumer-facing component registry (M9 deliverable 3).
##
## The framework ships NO components of its own (it stays content-agnostic,
## exactly like `main_web`'s empty `embeddedApiSpecs`/`embeddedNimSources`
## defaults): this module is only the registration seam a *consumer* uses to
## bind its own components -- by name -- to the `<MyButton .../>` tags the
## markdown extractor turned into `bkComponent` AST nodes
## (`core/markdown_vm.nim`, M9 deliverable 1). The renderer
## (`components/markdown_view.renderComponent`/`renderComponentHtml`)
## resolves each `bkComponent` node against a registry, wraps the resolved
## component's render in the M6 error boundary, and hands it a
## `ComponentInstance` carrying a UNIQUE `instanceId` -- which is how two
## embeds of the same component get strictly isolated state (each render
## closure allocates its own locals/signals, keyed off its own instance id;
## see `test_component_embed_browser_mount.nim`).
##
## Dual-target by construction, mirroring every other `components/*`
## renderer's split: `ComponentRegistry[R, E]` is generic over the renderer
## backend for the MockRenderer/browser tree path (one closure per
## component that both builds the element AND wires its own interactivity +
## per-instance reactive state), and `HtmlComponentRegistry` is the SSR
## string-path counterpart producing the initial hydratable markup. Neither
## touches `std/os`, so both compile on `nim c` and `nim js`.

import std/tables
import ../core/markdown_vm

type
  ComponentInstance* = object
    ## Everything a consumer's render/hydrate closure needs to render ONE
    ## embed: the resolved component `name`, a page-unique `instanceId`
    ## (scope any DOM ids / reactive state off this so sibling embeds never
    ## collide), the parsed `props` (`markdown_vm.getStr`/`getInt`/`getBool`
    ## read them by name+type), and the paired form's raw inner `children`
    ## text ("" for a self-closing tag).
    name*: string
    instanceId*: string
    props*: seq[ComponentProp]
    children*: string

  ComponentRender*[R, E] = proc(r: R; inst: ComponentInstance): E {.closure.}
    ## A consumer component on the tree/browser path: builds (and, on a live
    ## `WebRenderer`, wires) one embed's element. Called exactly once per
    ## embed with that embed's own `ComponentInstance`, so any state it
    ## closes over is private to that embed.

  ComponentRegistry*[R, E] = ref object
    ## Name -> tree/browser component. A `ref` so a `= nil` default (an
    ## empty registry) threads cleanly through `renderMarkdownBody`'s
    ## existing callers without them passing anything.
    defs: Table[string, ComponentRender[R, E]]

  HtmlComponentRender* = proc(inst: ComponentInstance): string {.closure.}
    ## The SSR string-path counterpart: returns one embed's initial
    ## (hydratable) markup as a string.

  HtmlComponentRegistry* = ref object
    defs: Table[string, HtmlComponentRender]

proc newComponentRegistry*[R, E](): ComponentRegistry[R, E] =
  ComponentRegistry[R, E](defs: initTable[string, ComponentRender[R, E]]())

proc register*[R, E](reg: ComponentRegistry[R, E]; name: string;
                     render: ComponentRender[R, E]) =
  ## Binds `name` to a tree/browser component. Re-registering a name
  ## replaces it (last registration wins), so a consumer can override a
  ## default.
  reg.defs[name] = render

proc hasComponent*[R, E](reg: ComponentRegistry[R, E]; name: string): bool =
  reg != nil and reg.defs.hasKey(name)

proc getRender*[R, E](reg: ComponentRegistry[R, E]; name: string): ComponentRender[R, E] =
  reg.defs[name]

proc knownPredicate*[R, E](reg: ComponentRegistry[R, E]): proc(name: string): bool {.closure.} =
  ## The `isComponentKnown` predicate to hand `parseMarkdownBlocks`/
  ## `parseMarkdownDoc` so an unregistered tag is extracted as a TYPED
  ## error node at parse time (rather than only failing at render).
  (proc(name: string): bool = reg.hasComponent(name))

proc newHtmlComponentRegistry*(): HtmlComponentRegistry =
  HtmlComponentRegistry(defs: initTable[string, HtmlComponentRender]())

proc register*(reg: HtmlComponentRegistry; name: string; render: HtmlComponentRender) =
  reg.defs[name] = render

proc hasComponent*(reg: HtmlComponentRegistry; name: string): bool =
  reg != nil and reg.defs.hasKey(name)

proc getRender*(reg: HtmlComponentRegistry; name: string): HtmlComponentRender =
  reg.defs[name]

proc knownPredicate*(reg: HtmlComponentRegistry): proc(name: string): bool {.closure.} =
  (proc(name: string): bool = reg.hasComponent(name))
