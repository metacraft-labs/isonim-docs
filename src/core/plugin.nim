## isonim-docs Layer 3 — the plugin architecture (M11 deliverable 1).
##
## A content-agnostic, deterministic plugin host: a consumer (or the
## framework itself) registers `Plugin`s whose optional lifecycle hooks
## are fired, in registration order, at the fixed points the build/render
## pipeline exposes:
##
##   onConfig        (mutate the resolved `DocsConfig` once at startup)
##   preParse        (transform a page's raw markdown text before parsing)
##   postParse       (inspect/mutate the parsed `MarkdownDoc` AST)
##   onRender        (transform a page's final rendered HTML string)
##   onBuildComplete (observe the finished static build)
##
## plus custom markdown-directive registration: a plugin maps a
## `:::name args ... :::` directive name to a renderer that turns the
## directive's argument line + raw body into rendered `Block`s, spliced
## into the document exactly where the directive appeared.
##
## The parser-level part -- `preParse`, `postParse` and the directives --
## lives in IsoNim as `isonim/content/directives` (`ParseHooks`), shared
## with every other IsoNim content consumer. A `PluginHost` hands its
## plugins' parser hooks to it (`parseHooks`), so directive resolution and
## hook ordering are that module's, and only the configuration, render
## and build hooks are isonim-docs' own. `DirectiveRenderer` and
## `DirectiveRegistration` are re-exported from there unchanged.
##
## Pure data + closures, no platform imports (no `std/os`, no filesystem),
## so this module is identical under `nim c` and `nim js` and every hook
## is Tier-1-testable on both backends.

import ./config
import isonim/content/markdown
import isonim/content/directives

export DirectiveRenderer, DirectiveRegistration

type
  BuildInfo* = object
    ## The payload passed to `onBuildComplete`. Deliberately minimal and
    ## platform-free (plain fields, no `std/os` paths as anything but
    ## strings) so the hook signature stays dual-target; `build_site`
    ## fills the real numbers after a static build finishes.
    pageCount*: int
    outDir*: string

  Plugin* = object
    ## One registered plugin. Every hook is optional -- a nil closure
    ## means "not interested", so a plugin declares only the hooks it
    ## uses. `name` is for diagnostics/ordering readability only.
    name*: string
    onConfig*: proc(cfg: var DocsConfig) {.closure.}
    preParse*: proc(body: string): string {.closure.}
    postParse*: proc(doc: var MarkdownDoc) {.closure.}
    onRender*: proc(html: string): string {.closure.}
    onBuildComplete*: proc(info: BuildInfo) {.closure.}
    directives*: seq[DirectiveRegistration]
    renderers*: ContentRenderers ## Optional validated build-time math/diagrams.

  PluginHost* = object
    ## The ordered registry. Registration order IS execution order for
    ## every hook (deterministic ordering, M11 deliverable 1) -- an empty
    ## host (`PluginHost()`) is a total no-op, which is what every
    ## pipeline entry defaults to, so a plugin-free build is byte-for-byte
    ## unchanged.
    plugins*: seq[Plugin]

proc registerPlugin*(host: var PluginHost; plugin: Plugin) =
  ## Appends `plugin` to the host. The append preserves registration
  ## order, which the `apply*` procs below iterate verbatim -- so two
  ## plugins' hooks always fire in the order they were registered.
  host.plugins.add plugin

proc newPluginHost*(plugins: varargs[Plugin]): PluginHost =
  ## Builds a host from an ordered list of plugins in one call; equivalent
  ## to `registerPlugin` per plugin, left to right.
  for p in plugins:
    result.plugins.add p

# --- Hook firing (deterministic: registration order) --------------------

proc applyOnConfig*(host: PluginHost; cfg: var DocsConfig) =
  ## Fires every plugin's `onConfig` in order, threading the same `cfg`
  ## through so a later plugin sees an earlier plugin's edits. Run once at
  ## startup by the config owner (`build_site`, a server, or a test) --
  ## NOT per page render -- so an appending hook isn't applied repeatedly.
  for p in host.plugins:
    if not p.onConfig.isNil:
      p.onConfig(cfg)

proc parseHooks*(host: PluginHost): seq[ParseHooks] =
  ## The parser-level part of every plugin, in registration order: what
  ## `isonim/content/directives` runs for `preParse`, `postParse` and
  ## the directives.
  for p in host.plugins:
    result.add ParseHooks(name: p.name, preParse: p.preParse,
                          postParse: p.postParse, directives: p.directives, renderers: p.renderers)

proc hasContentRenderers*(host: PluginHost): bool =
  ## Whether this host enables optional math/diagram rendering. Established
  ## parser-only and lifecycle-only plugins retain their default build policy.
  for p in host.plugins:
    if not p.renderers.math.isNil or not p.renderers.diagram.isNil:
      return true

proc applyPreParse*(host: PluginHost; body: string): string =
  ## Threads a page's raw markdown through every `preParse` in order; each
  ## hook sees the previous hook's output (a real transform pipeline).
  host.parseHooks.applyPreParse(body)

proc applyPostParse*(host: PluginHost; doc: var MarkdownDoc) =
  ## Fires every `postParse` in order over the parsed AST. Hooks mutate
  ## `doc.blocks` in place (the AST-access deliverable); a hook that
  ## changes the heading set is responsible for `doc.headingTree` too.
  host.parseHooks.applyPostParse(doc)

proc applyOnRender*(host: PluginHost; html: string): string =
  ## Threads a page's final HTML string through every `onRender` in order;
  ## each hook sees the previous hook's output.
  result = html
  for p in host.plugins:
    if not p.onRender.isNil:
      result = p.onRender(result)

proc applyOnBuildComplete*(host: PluginHost; info: BuildInfo) =
  ## Notifies every `onBuildComplete` in order once the static build has
  ## finished. Observation-only (no return) -- a reporting/asset-emitting
  ## side effect, not a transform.
  for p in host.plugins:
    if not p.onBuildComplete.isNil:
      p.onBuildComplete(info)

# --- Custom directive resolution ----------------------------------------

proc knowsDirective*(host: PluginHost; name: string): bool =
  ## Whether any registered plugin contributes a directive named `name`.
  ## First-match semantics mean the earliest-registered plugin owns a name
  ## if two register the same one (deterministic), so this predicate and
  ## `renderDirective` below always agree.
  host.parseHooks.knowsDirective(name)

proc renderDirectiveBlocks*(host: PluginHost; name, args, body: string): seq[Block] =
  ## Runs the first registered renderer for `name` over `(args, body)`.
  ## Returns an empty block list when no plugin owns `name` (the parser
  ## gates this behind `knowsDirective`, so in practice a match exists).
  host.parseHooks.renderDirectiveBlocks(name, args, body)

# --- Plugin-aware markdown parsing --------------------------------------

proc parseMarkdownDocWithPlugins*(host: PluginHost; body: string;
    sourceRelPath: string = "";
    resolveContentPath: proc(contentRelPath: string): string {.closure.} = nil;
    resolveSymbol: proc(sym: string): string {.closure.} = nil;
    isComponentKnown: proc(name: string): bool {.closure.} = nil;
    firstLine: int = 1): MarkdownDoc =
  ## The one entry point the render pipeline uses to parse a page through
  ## the plugin host: `preParse` transforms the raw text, the host's
  ## custom directives are wired into `parseMarkdownDoc` (so a registered
  ## `:::name` renders), then `postParse` runs over the resulting AST.
  ## With an empty host this is exactly `parseMarkdownDoc(body, ...)` --
  ## the directive closures are nil and both hook loops are no-ops.
  parseMarkdownDocWithHooks(host.parseHooks, body, sourceRelPath,
    resolveContentPath, resolveSymbol, isComponentKnown, firstLine)
