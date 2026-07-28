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
## Pure data + closures, no platform imports (no `std/os`, no filesystem),
## so this module is identical under `nim c` and `nim js` and every hook
## is Tier-1-testable on both backends -- the same cross-platform rule
## `config.nim`/`markdown_vm.nim` already follow. `markdown_vm.nim` never
## imports this module (it takes bare directive closures instead), so
## there is no import cycle: `plugin.nim` depends on `markdown_vm.nim`,
## not the reverse.

import ./config
import ./markdown_vm

type
  BuildInfo* = object
    ## The payload passed to `onBuildComplete`. Deliberately minimal and
    ## platform-free (plain fields, no `std/os` paths as anything but
    ## strings) so the hook signature stays dual-target; `build_site`
    ## fills the real numbers after a static build finishes.
    pageCount*: int
    outDir*: string

  DirectiveRenderer* = proc(args: string; body: string): seq[Block] {.closure.}
    ## Renders one custom `:::name args ... :::` block. `args` is the rest
    ## of the opening `:::name` line (trimmed); `body` is the raw inner
    ## text between the opening line and the closing `:::` (verbatim, so a
    ## directive can re-parse it, treat it as data, etc.). The returned
    ## blocks are spliced into the document in place of the directive.

  DirectiveRegistration* = object
    ## One `name -> renderer` mapping a plugin contributes. A directive
    ## `name` is matched case-sensitively against the first token after
    ## `:::` (e.g. `youtube` matches `:::youtube dQw4w9WgXcQ`).
    name*: string
    render*: DirectiveRenderer

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

proc applyPreParse*(host: PluginHost; body: string): string =
  ## Threads a page's raw markdown through every `preParse` in order; each
  ## hook sees the previous hook's output (a real transform pipeline).
  result = body
  for p in host.plugins:
    if not p.preParse.isNil:
      result = p.preParse(result)

proc applyPostParse*(host: PluginHost; doc: var MarkdownDoc) =
  ## Fires every `postParse` in order over the parsed AST. Hooks mutate
  ## `doc.blocks` in place (the AST-access deliverable); a hook that
  ## changes the heading set is responsible for `doc.headingTree` too.
  for p in host.plugins:
    if not p.postParse.isNil:
      p.postParse(doc)

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
  for p in host.plugins:
    for d in p.directives:
      if d.name == name:
        return true
  false

proc renderDirectiveBlocks*(host: PluginHost; name, args, body: string): seq[Block] =
  ## Runs the first registered renderer for `name` over `(args, body)`.
  ## Returns an empty block list when no plugin owns `name` (the parser
  ## gates this behind `knowsDirective`, so in practice a match exists).
  for p in host.plugins:
    for d in p.directives:
      if d.name == name and not d.render.isNil:
        return d.render(args, body)
  @[]

# --- Plugin-aware markdown parsing --------------------------------------

proc parseMarkdownDocWithPlugins*(host: PluginHost; body: string;
    sourceRelPath: string = "";
    resolveContentPath: proc(contentRelPath: string): string {.closure.} = nil;
    resolveSymbol: proc(sym: string): string {.closure.} = nil;
    isComponentKnown: proc(name: string): bool {.closure.} = nil): MarkdownDoc =
  ## The one entry point the render pipeline uses to parse a page through
  ## the plugin host: `preParse` transforms the raw text, the host's
  ## custom directives are wired into `parseMarkdownDoc` (so a registered
  ## `:::name` renders), then `postParse` runs over the resulting AST.
  ## With an empty host this is exactly `parseMarkdownDoc(body, ...)` --
  ## the directive closures are nil and both hook loops are no-ops.
  let transformed = host.applyPreParse(body)
  let known = proc(name: string): bool = host.knowsDirective(name)
  let render = proc(name, args, dbody: string): seq[Block] =
    host.renderDirectiveBlocks(name, args, dbody)
  result = parseMarkdownDoc(transformed, sourceRelPath, resolveContentPath,
    resolveSymbol, isComponentKnown,
    knownDirective = known, renderDirective = render)
  host.applyPostParse(result)
