## DTCG -> EditorWorkspace adapter for the live Metacraft docs design system.
##
## This is the READ/PREVIEW half of the "live design-system editor" track
## (design-system-editor.milestones.org M1). It takes the *resolved docs
## token layer* -- a `core/docs_tokens.DocsTokenLayer` (the `--docs-*`
## variable bindings) plus the `core/tokens.TokenSet` its `bkToken`
## bindings resolve against -- and turns it into an
## `isonim/editor.EditorWorkspace` the mature isonim editor can mount over.
##
## Nothing here forks the editor: it only produces the project-owned data
## contract (`EditorWorkspace`) the editor package already consumes
## (`foundationTokens`, `designSystemSchema`, `storyGroups`, `canvasItems`,
## `previewHook`). It is pure data + string work, so it compiles and runs
## identically on the C and JS targets.
##
## Mapping summary (per `--docs-*` variable):
##   * FoundationTokenEntry.value       = the resolved LIGHT value
##                                        (== emitTokensCss `:root` block)
##   * FoundationTokenEntry.aliasOf      = the DTCG dotted key a `bkToken`
##                                        binding points at (alias chain
##                                        head); empty for `bkLiteral`.
##   * FoundationTokenEntry.kind         = mapped from the DTCG `$type`
##                                        category (bkToken) or inferred
##                                        from the variable name (bkLiteral).
##   * DesignSchemaNode.modeValues       = light (dtmkLight) + dark (dtmkDark)
##                                        resolved values (== the `:root`
##                                        and `[data-theme="dark"]` blocks).

import std/strutils

import isonim/editor
import core/[tokens, docs_tokens]

# The real isonim-docs components (SSR-string renderers) + their view
# models. These are the SAME modules the live docs site (`src/main_web.nim`,
# `src/ssr.nim`) renders through, so the editor's per-story preview shows
# the ACTUAL docs shell / nav / markdown / admonitions / search chrome --
# themed by the live `--docs-*` tokens -- rather than mock HTML. Every
# `*Html` proc used below is a pure string builder that compiles and runs
# on both the C and JS targets.
import core/[markdown_vm, navigation_vm, search_vm, theme_vm, config]
import components/[markdown_view, navigation_view, search_view, shell,
                   markdown_page]

const DocsThemeSource* = "site/src/theme_tokens.nim"
  ## The source file the docs token layer is authored in; recorded on each
  ## FoundationTokenEntry so the editor's "open source" affordance and the
  ## M2 write-back have a real anchor.

const docsBindingsEndpoint* = "/__isonim_bindings"
  ## VBIND-M7: the dev-server POST route the live editor persists its
  ## variable-binding SIDECAR to, PARALLEL to `docsSaveEndpoint`. The JS mount
  ## harness (`design/main.nim`) POSTs the collected binding metadata here on
  ## every bind/detach; the native save server (`design/serve.nim`) mounts a
  ## `bindingsHandler` there that writes `design/.isonim/bindings.json`. The DTCG
  ## token source (`codetracer-docs.tokens.json`) is NEVER written on this route.

const docsBindingsGlobal* = "__ISONIM_BINDINGS__"
  ## VBIND-M7: the `window` global the save server injects the sidecar JSON into
  ## (the JS client has no filesystem, so LOADING the sidecar is the server's
  ## job). `design/serve.nim` reads `design/.isonim/bindings.json` and embeds it
  ## as `window.__ISONIM_BINDINGS__ = <json>` ahead of the editor bundle;
  ## `design/main.nim` reads it back and `loadBindingSidecar`s it into the
  ## workspace BEFORE mounting, so a reload rehydrates the chips.

const docsSaveEndpoint* = "/__isonim_save"
  ## The dev-server POST route the live editor persists a foundation edit to
  ## (M4b). Shared by the JS mount harness (`design/main.nim`, which `fetch`es it
  ## same-origin) and the native design save server (`design/serve.nim`, which
  ## mounts a `saveHandler` there). Kept in step with `dev_server.defaultSavePath`
  ## but declared here so both the JS and native halves import it from one place
  ## without the JS build touching the native-only `dev_server`.

# ---------------------------------------------------------------------------
# $type / name -> FoundationTokenKind
# ---------------------------------------------------------------------------

func kindForCategory*(cat: TokenCategory; aliased: bool): FoundationTokenKind =
  ## Maps a resolved DTCG `$type` category to the editor's foundation-token
  ## kind. An aliased colour is a *semantic* colour (it references another
  ## token), a bare colour is a palette primitive.
  case cat
  of tcColor:
    if aliased: ftkSemanticColor else: ftkColorPalette
  of tcDimension:
    ftkSpacingScale
  of tcShadow:
    ftkShadow
  of tcFontSize, tcFontFamily, tcFontWeight, tcLineHeight, tcLetterSpacing,
     tcParagraphSpacing, tcTypography, tcText, tcTextCase, tcTextDecoration:
    ftkTypographyScale
  of tcNumber:
    ftkSpacingScale
  of tcOther:
    ftkColorPalette

func kindForVarName*(name: string): FoundationTokenKind =
  ## For a `bkLiteral` binding there is no DTCG `$type`, so the kind is
  ## inferred from the `--docs-*` variable's own name. The docs theme's
  ## vocabulary (radius / space / shadow / motion / breakpoint / font /
  ## colour surfaces) maps cleanly onto the editor's foundation categories.
  let n = name.toLowerAscii
  if "radius" in n:
    ftkRadiusScale
  elif "space" in n:
    ftkSpacingScale
  elif "shadow" in n:
    ftkShadow
  elif "motion" in n or "transition" in n or "duration" in n:
    ftkMotion
  elif "breakpoint" in n or "width" in n or "sidebar" in n:
    ftkBreakpoint
  elif "line-height" in n or "font-size" in n or "font" in n:
    ftkTypographyScale
  else:
    # bg / fg / accent / link / border / code / focus-ring / admonition /
    # syntax token / api-method colours: all colour surfaces.
    ftkColorPalette

# ---------------------------------------------------------------------------
# --docs-* -> story association (drives impact analysis + live preview)
# ---------------------------------------------------------------------------

const
  StoryShell* = StoryRef(group: "Docs Shell", name: "Full page", kind: skPage, index: 0)
  StoryNavSidebar* = StoryRef(group: "Navigation", name: "Sidebar nav", kind: skComponent, index: 0)
  StoryNavTop* = StoryRef(group: "Navigation", name: "Top nav", kind: skComponent, index: 1)
  StoryProse* = StoryRef(group: "Markdown Body", name: "Prose", kind: skComponent, index: 0)
  StoryCode* = StoryRef(group: "Markdown Body", name: "Code block", kind: skComponent, index: 1)
  StoryAdNote* = StoryRef(group: "Admonitions", name: "Note", kind: skComponent, index: 0)
  StoryAdTip* = StoryRef(group: "Admonitions", name: "Tip", kind: skComponent, index: 1)
  StoryAdWarn* = StoryRef(group: "Admonitions", name: "Warning", kind: skComponent, index: 2)
  StoryAdDanger* = StoryRef(group: "Admonitions", name: "Danger", kind: skComponent, index: 3)
  StorySearch* = StoryRef(group: "Search", name: "Search field", kind: skComponent, index: 0)
  StoryFoundColors* = StoryRef(group: "Foundations", name: "Colors", kind: skFoundation, index: 0)
  StoryFoundType* = StoryRef(group: "Foundations", name: "Typography", kind: skFoundation, index: 1)
  StoryFoundSpace* = StoryRef(group: "Foundations", name: "Spacing & Radii", kind: skFoundation, index: 2)

func storiesForVar*(name: string): seq[StoryRef] =
  ## Which docs-component stories actually consume a given `--docs-*`
  ## variable. Drives both the editor's impact analysis
  ## (`FoundationTokenEntry.affectedStories`) and the live-preview hook, so
  ## editing a token lights up exactly the surfaces it themes.
  let n = name.toLowerAscii
  if "admonition-note" in n or "admonition-important" in n:
    @[StoryAdNote]
  elif "admonition-tip" in n:
    @[StoryAdTip]
  elif "admonition-warning" in n:
    @[StoryAdWarn]
  elif "admonition-danger" in n or "admonition-caution" in n:
    @[StoryAdDanger]
  elif "code" in n or "tok-" in n:
    @[StoryCode]
  elif "api-" in n:
    @[StoryProse]
  elif "input" in n or "search" in n:
    @[StorySearch]
  elif "accent" in n or "link" in n or "focus" in n:
    @[StoryNavTop, StoryProse]
  elif "radius" in n or "shadow" in n:
    @[StoryFoundSpace]
  elif "space" in n:
    @[StoryFoundSpace]
  elif "font" in n or "line-height" in n:
    @[StoryFoundType]
  elif "bg" in n or "fg" in n or "border" in n:
    @[StoryShell, StoryNavSidebar, StoryProse]
  else:
    @[StoryShell]

# ---------------------------------------------------------------------------
# Adapter core: DocsTokenLayer + TokenSet -> foundation tokens / schema
# ---------------------------------------------------------------------------

func schemaKeyFor(name: string): string =
  ## A stable dotted schema key for a `--docs-*` variable
  ## (`--docs-accent-fg` -> `docs.theme.accent.fg`).
  "docs.theme." & name.strip(chars = {'-'}).replace("docs-", "").replace("-", ".")

proc resolveSide(ts: TokenSet; b: Binding; dark: bool): string =
  ## The resolved CSS value for one binding side, matching
  ## `docs_tokens.emitTokensCss` exactly: literals verbatim, token keys
  ## resolved through the DTCG `TokenSet`.
  let raw = if dark: b.dark else: b.light
  case b.kind
  of bkLiteral: raw
  of bkToken: ts.resolve(raw)

proc dtcgFoundationTokens*(layer: DocsTokenLayer; ts: TokenSet = TokenSet()):
    seq[FoundationTokenEntry] =
  ## Turns each `--docs-*` binding into a `FoundationTokenEntry` whose
  ## `value` is the resolved LIGHT value, `aliasOf` is the DTCG dotted key
  ## for a `bkToken` binding (preserving the alias-chain head), and `kind`
  ## is derived from the DTCG `$type` (bkToken) or the variable name
  ## (bkLiteral).
  for i, (name, binding) in layer.vars:
    let aliased = binding.kind == bkToken
    var kind: FoundationTokenKind
    if aliased:
      # The category of the *referenced* DTCG token drives the kind.
      let cat =
        if ts.contains(binding.light): ts.categoryOf(binding.light)
        else: tcOther
      kind = kindForCategory(cat, aliased = true)
    else:
      kind = kindForVarName(name)

    result.add FoundationTokenEntry(
      key: name,
      kind: kind,
      value: resolveSide(ts, binding, dark = false),
      aliasOf: (if aliased: binding.light else: ""),
      sourceFile: DocsThemeSource,
      sourceLine: i + 1,
      schemaKey: schemaKeyFor(name),
      property: name,
      affectedStories: storiesForVar(name))

proc wireContrastPairs*(tokens: var seq[FoundationTokenEntry]) =
  ## Pairs every `--docs-<x>` colour with its `--docs-<x>-fg` companion so
  ## the editor can surface a real WCAG contrast diagnostic: the base is the
  ## background, the `-fg` value is the foreground text, minContrast 4.5
  ## (WCAG AA body text). Applied to accent/link surfaces the docs theme
  ## actually pairs.
  # Snapshot the base values so the -fg lookup does not alias the mutated seq.
  var values: seq[(string, string)]
  for t in tokens:
    values.add (t.key, t.value)
  proc valueOf(name: string; vals: seq[(string, string)]): string =
    for (k, v) in vals:
      if k == name: return v
    ""
  for i in 0 ..< tokens.len:
    let name = tokens[i].key
    if name.endsWith("-fg"): continue
    let fgName = name & "-fg"
    let fg = valueOf(fgName, values)
    if fg.len > 0 and tokens[i].kind in {ftkColorPalette, ftkSemanticColor}:
      tokens[i].background = tokens[i].value
      tokens[i].foreground = fg
      tokens[i].minContrast = 4.5

proc dtcgDesignSchema*(layer: DocsTokenLayer; ts: TokenSet = TokenSet();
    tokens: seq[FoundationTokenEntry]): DesignSystemSchema =
  ## Builds the versioned design-system schema: one node per `--docs-*`
  ## variable carrying its light (dtmkLight) + dark (dtmkDark) mode values
  ## (== the `:root` and `[data-theme="dark"]` blocks of emitTokensCss).
  result = DesignSystemSchema(
    schemaVersion: 1,
    projectId: "isonim-docs-design",
    ownerPackage: "isonim-docs",
    frameworkContract: "isonim-editor-design-schema-v1")
  for i, (name, binding) in layer.vars:
    let lightVal = resolveSide(ts, binding, dark = false)
    let darkVal = resolveSide(ts, binding, dark = true)
    let tok = tokens[i]
    result.nodes.add DesignSchemaNode(
      key: tok.schemaKey,
      kind: (if tok.aliasOf.len > 0: dsnSemanticToken else: dsnFoundation),
      name: name,
      property: name,
      value: lightVal,
      modeValues: @[
        DesignTokenModeValue(kind: dtmkLight, name: "Light", value: lightVal,
          schemaKey: tok.schemaKey),
        DesignTokenModeValue(kind: dtmkDark, name: "Dark", value: darkVal,
          schemaKey: tok.schemaKey)],
      stories: tok.affectedStories,
      usageCount: tok.affectedStories.len)

# ---------------------------------------------------------------------------
# Docs components as editor stories
# ---------------------------------------------------------------------------

proc docsStoryGroups*(): seq[StoryGroup] =
  ## The real isonim-docs UI surfaces, registered as editor story groups so
  ## the editor's storyboard + impact analysis operate on actual docs
  ## components (the shell, nav, markdown body, admonitions, search) rather
  ## than the wanderlust travel demo.
  @[
    StoryGroup(name: "Foundations", kind: skFoundation, expanded: true,
      description: "Docs design tokens (--docs-*): colours, type, spacing",
      items: @[
        StoryItem(name: "Colors", description: "Surface, text, accent & severity colours",
          kind: skFoundation, group: "Foundations",
          # bg/fg/border/accent/link/code/tok/api + admonition colours
          # (ftkColorPalette), the aliased severity/focus colours
          # (ftkSemanticColor) and the surface shadow (ftkShadow).
          foundationCategories: {ftkColorPalette, ftkSemanticColor, ftkShadow}),
        StoryItem(name: "Typography", description: "Geist font stack, sizes, line height",
          kind: skFoundation, group: "Foundations",
          # font-sans/mono, font-size-*, line-height (ftkTypographyScale).
          foundationCategories: {ftkTypographyScale}),
        StoryItem(name: "Spacing & Radii", description: "Spacing scale + border radii vocabulary",
          kind: skFoundation, group: "Foundations",
          # space-* (ftkSpacingScale), radius-* (ftkRadiusScale) and the
          # sidebar/content widths (ftkBreakpoint).
          foundationCategories: {ftkSpacingScale, ftkRadiusScale, ftkBreakpoint})]),
    StoryGroup(name: "Docs Shell", kind: skPage, expanded: true,
      description: "The full documentation page frame (header + nav + main + footer)",
      items: @[
        StoryItem(name: "Full page", description: "Header, sidebar nav, markdown main, footer",
          kind: skPage, group: "Docs Shell")]),
    StoryGroup(name: "Navigation", kind: skComponent, expanded: false,
      description: "Sidebar tree + top navigation, themed by --docs-accent/link",
      items: @[
        StoryItem(name: "Sidebar nav", description: "Collapsible section tree",
          kind: skComponent, group: "Navigation"),
        StoryItem(name: "Top nav", description: "Header bar with active link accent",
          kind: skComponent, group: "Navigation")]),
    StoryGroup(name: "Markdown Body", kind: skComponent, expanded: false,
      description: "Rendered prose + fenced code blocks",
      items: @[
        StoryItem(name: "Prose", description: "Headings, paragraphs, links, lists",
          kind: skComponent, group: "Markdown Body"),
        StoryItem(name: "Code block", description: "Fenced code with syntax highlight tokens",
          kind: skComponent, group: "Markdown Body")]),
    StoryGroup(name: "Admonitions", kind: skComponent, expanded: false,
      description: "Note / Tip / Warning / Danger callouts (severity borders = brand .500)",
      items: @[
        StoryItem(name: "Note", description: "Informational callout (blue.500 border)",
          kind: skComponent, group: "Admonitions"),
        StoryItem(name: "Tip", description: "Success callout (green.500 border)",
          kind: skComponent, group: "Admonitions"),
        StoryItem(name: "Warning", description: "Caution callout (amber.500 border)",
          kind: skComponent, group: "Admonitions"),
        StoryItem(name: "Danger", description: "Error callout (red.500 border)",
          kind: skComponent, group: "Admonitions")]),
    StoryGroup(name: "Search", kind: skComponent, expanded: false,
      description: "Search field + results dropdown",
      items: @[
        StoryItem(name: "Search field", description: "White input, rounded, focus ring",
          kind: skComponent, group: "Search")])
  ]

proc docsCanvasItems*(): seq[CanvasItem] =
  ## Storyboard canvas thumbnails for the docs page surfaces.
  @[
    CanvasItem(storyRef: StoryShell, x: 0, y: 0, width: 360, height: 240,
      label: "Docs Shell"),
    CanvasItem(storyRef: StoryProse, x: 400, y: 0, width: 360, height: 240,
      label: "Markdown Body"),
    CanvasItem(storyRef: StoryAdNote, x: 0, y: 280, width: 360, height: 160,
      label: "Admonitions"),
    CanvasItem(storyRef: StorySearch, x: 400, y: 280, width: 360, height: 160,
      label: "Search")
  ]

# ---------------------------------------------------------------------------
# Story -> real docs-component HTML (the pbWeb preview `documentHtml` seam)
# ---------------------------------------------------------------------------
#
# ROOT CAUSE of the blank previews (M3): the editor's Web preview path
# (`views/page_preview.nim` for the skPage "Full page", `views/
# component_detail.nim` for the skComponent stories) mounts the project's
# HTML in an iframe via `srcdoc`, and it renders EXCLUSIVELY from
# `ProjectPreview.documentHtml`. The previous hook only ever populated
# `bodyText` (a `--docs-*=value` token dump), never `documentHtml`, so
# `showProject`/the srcdoc branch was always false: component stories fell
# back to the generic empty "Project-owned component state" surface and the
# full page fell back to the whitish empty-state panel. Supplying real
# `documentHtml` per story is the fix -- and it lives entirely harness-side,
# so no other editor pilot changes.

const docsPreviewStylesheet = staticRead("../assets/style.css")
  ## The live docs site stylesheet (the same `site/assets/style.css` the
  ## framework serves), embedded so each preview's real docs-component
  ## markup is styled exactly like production. Its baked `:root {--docs-*}`
  ## block is overridden below by a `:root` block built from the LIVE
  ## foundation-token values, so an in-editor edit re-themes the preview.

const docsPreviewBaseCss =
  "html,body{margin:0;padding:0}" &
  "body{background:var(--docs-bg);color:var(--docs-fg);" &
  "font-family:var(--docs-font-sans,system-ui,sans-serif)}"

proc docsPreviewRootVars(tokens: seq[FoundationTokenEntry]): string =
  ## A `:root { --docs-*: <live value>; }` block built from the CURRENT
  ## foundation tokens. Emitted AFTER the embedded stylesheet so the live
  ## (as-edited) values win over the stylesheet's build-time defaults.
  result = ":root{"
  for t in tokens:
    if t.key.len > 2 and t.key[0] == '-' and t.key[1] == '-':
      result.add t.key & ":" & t.value & ";"
  result.add "}"

proc wrapDocsPreviewDocument(bodyHtml: string;
    tokens: seq[FoundationTokenEntry]): string =
  ## Wraps a component's rendered markup in a full themed HTML document for
  ## the editor's iframe `srcdoc`.
  "<!doctype html><html><head><meta charset=\"utf-8\">" &
  "<style>\n" & docsPreviewBaseCss & "\n" & docsPreviewStylesheet & "\n" &
    docsPreviewRootVars(tokens) & "\n</style>" &
  "</head><body>" & bodyHtml & "</body></html>"

proc docsSampleNavigation(): NavigationViewModel =
  ## A representative docs sidebar tree (the real `NavigationViewModel`
  ## shape) so the Navigation + Docs Shell stories render genuine nav links.
  let gettingStarted = NavSection(
    key: "getting-started", title: "Getting Started", isExpanded: true,
    items: @[
      NavItem(routePath: "/introduction", title: "Introduction", isActive: true),
      NavItem(routePath: "/installation", title: "Installation")])
  let usageGuide = NavSection(
    key: "guide", title: "Usage Guide", isExpanded: true,
    items: @[
      NavItem(routePath: "/guide/tracepoints", title: "Tracepoints"),
      NavItem(routePath: "/guide/interface", title: "Graphical interface"),
      NavItem(routePath: "/guide/cli", title: "Command-line interface")])
  let reference = NavSection(
    key: "reference", title: "Reference", isExpanded: false,
    items: @[
      NavItem(routePath: "/reference/build-systems", title: "Build systems")])
  NavigationViewModel(sidebar: SidebarViewModel(
    sections: @[gettingStarted, usageGuide, reference]))

const
  docsProseMarkdown = """
## Introduction

CodeTracer records your program's whole execution so you can step
**backward** and forward through time. See the
[tracepoints guide](/guide/tracepoints) for the full workflow.

- Deterministic, replayable traces
- Omniscient debugging across the entire run
- Works from the CLI or the graphical interface
"""

  docsCodeMarkdown = """
## Recording a trace

Wrap the entry point you want to record and run it under the tracer:

```nim
proc main() =
  let trace = startTrace("demo")
  echo "hello, time-travel"
  trace.finish()

main()
```
"""

  docsNoteMarkdown = """
:::note
Traces are stored under `.codetracer/` next to your project. Commit the
directory to share a reproducible recording with your team.
:::
"""

  docsTipMarkdown = """
:::tip
Press **F5** to jump straight to the next tracepoint hit instead of
stepping line by line.
:::
"""

  docsWarningMarkdown = """
:::warning
Recording a long-running process can produce large traces. Scope the
recording to the function under investigation where possible.
:::
"""

  docsDangerMarkdown = """
:::danger
Deleting the trace database while the debugger is attached will corrupt the
active session. Detach first.
:::
"""

  docsFullPageMarkdown = """
## Welcome to CodeTracer Docs

CodeTracer is a time-travelling debugger. This page is composed from the
real documentation shell -- header, sidebar navigation, markdown body and
footer -- exactly as the live site renders it.

### Start here

- [Introduction](/introduction)
- [Installation](/installation)
- [Tracepoints](/guide/tracepoints)

```nim
echo "step backward and forward through time"
```
"""

proc docsStoryBodyHtml(story: StoryRef; nav: NavigationViewModel;
    search: SearchViewModel; theme: ThemeViewModel): string =
  ## Renders the REAL isonim-docs component for `story` to an HTML string.
  ## Returns "" for stories with no component surface (e.g. the Foundations
  ## token stories, which the editor's foundations view renders itself).
  case story.group
  of "Docs Shell":
    renderMarkdownPageHtml("CodeTracer Documentation",
      parseMarkdownBlocks(docsFullPageMarkdown), nav, search, theme)
  of "Navigation":
    if story.name == "Top nav":
      renderDocsHeaderHtml("CodeTracer Docs", search, theme,
        chrome = DocsChrome(headerLinks: @[
          (label: "Docs", href: "/"),
          (label: "Reference", href: "/reference"),
          (label: "GitHub", href: "https://github.com/metacraft-labs/codetracer")]))
    else:
      renderNavigationHtml(nav)
  of "Markdown Body":
    if story.name == "Code block":
      renderMarkdownBodyHtml(parseMarkdownBlocks(docsCodeMarkdown))
    else:
      renderMarkdownBodyHtml(parseMarkdownBlocks(docsProseMarkdown))
  of "Admonitions":
    let md =
      case story.name
      of "Tip": docsTipMarkdown
      of "Warning": docsWarningMarkdown
      of "Danger": docsDangerMarkdown
      else: docsNoteMarkdown
    renderMarkdownBodyHtml(parseMarkdownBlocks(md))
  of "Search":
    renderSearchBoxHtml(search)
  else:
    ""

# ---------------------------------------------------------------------------
# Live-preview hook: re-resolves --docs-* from the live foundation tokens
# ---------------------------------------------------------------------------

proc docsPreviewHook*(tokensAccessor: proc(): seq[FoundationTokenEntry] {.closure.}):
    ProjectPreviewHook =
  ## A preview hook that renders each docs story from the CURRENT foundation
  ## token values, supplied lazily by `tokensAccessor` (typically
  ## `() => vm.foundations.tokens.val`). Because it re-reads the live tokens
  ## on every call, editing a token via the editor VM and re-rendering the
  ## bound story reflects the new value -- the "VariableBinding re-resolves"
  ## contract, exercised headlessly by the mount/preview test.
  ##
  ## M3: in addition to the `bodyText` token dump (kept for the impact/
  ## re-resolution contract the M1 test asserts), each story now also
  ## produces `documentHtml` -- the real docs-component markup themed by the
  ## live tokens. `documentHtml` is the Web preview seam the editor mounts
  ## in-iframe via `srcdoc`; supplying it is what makes the previously-blank
  ## component + full-page previews render.
  result = proc(story: StoryRef; platform: Platform): ProjectPreview =
    let tokens = tokensAccessor()
    # The --docs-* variables this particular story showcases.
    var lines: seq[string]
    for t in tokens:
      if story in t.affectedStories:
        lines.add t.key & "=" & t.value
    # The real docs-component HTML for this story, themed by the live tokens.
    let body = docsStoryBodyHtml(story, docsSampleNavigation(),
      SearchViewModel(), ThemeViewModel())
    let documentHtml =
      if body.len > 0: wrapDocsPreviewDocument(body, tokens) else: ""
    if lines.len == 0 and documentHtml.len == 0:
      return ProjectPreview(status: ppsUnsupportedStory, story: story)
    ProjectPreview(
      status: ppsRendered,
      story: story,
      title: story.group & " / " & story.name,
      bodyText: lines.join("; "),
      documentHtml: documentHtml)

# ---------------------------------------------------------------------------
# M4b: live save broker -- a WorkspaceEditAdapter that routes the editor's
# foundation "Save" through a project-owned `persist` closure.
# ---------------------------------------------------------------------------
#
# The editor's Save button (eckSave -> applyWorkspaceFileEdits) drives the
# framework's existing broker seam, `WorkspaceEditAdapter`. The docs workspace
# had no adapter (so Save was inert). This builds one whose ONLY side effect is
# to call `persist(varName, side, value)` -- the JS harness supplies a `persist`
# that `fetch`es the dev-server save route; a native test supplies a capturing
# one and drives the FULL transaction on the C target. The adapter never patches
# text itself (the server owns the structure-preserving M4 writeback); it holds
# a placeholder document so the transaction's read/patch/write steps have
# non-empty content to move through, and `allowMissingExpectedOldValue` so a
# resolved token value that is not literally present in the placeholder does not
# trip the source-conflict guard.

type DocsFoundationPersist* = proc(varName, side, value: string): bool {.closure.}
  ## Project-owned persistence of one foundation edit. Returns whether the save
  ## succeeded. Pure interface: no filesystem / network types leak here, so the
  ## adapter compiles on both the C and JS targets.

const docsAdapterPlaceholder = "docs-token-layer"
  ## Non-empty stand-in `readFile` content: the docs adapter defers the real
  ## patch to the server, so the transaction only needs SOME non-empty document
  ## to carry through read -> patch -> write.

proc docsWorkspaceEditAdapter*(tokens: seq[FoundationTokenEntry];
    persist: DocsFoundationPersist; side = "light"): WorkspaceEditAdapter =
  ## A `WorkspaceEditAdapter` over the docs foundation tokens whose `writeFile`
  ## flushes each pending foundation edit through `persist`. `patchFile` records
  ## the edit's `--docs-*` variable + new value (resolved from the plan exactly
  ## as `docsVarForPlan` does); `writeFile` replays them through `persist`. One
  ## schema entry per token maps the editor's `SourceEditPlan` back onto a
  ## write target.
  var schema: seq[WorkspaceEditableSchemaEntry]
  for t in tokens:
    schema.add WorkspaceEditableSchemaEntry(
      key: t.schemaKey,
      kind: wskToken,
      file: DocsThemeSource,
      path: t.key,
      story: (if t.affectedStories.len > 0: t.affectedStories[0]
              else: StoryFoundColors),
      property: t.property)
  result = WorkspaceEditAdapter(schema: schema,
    allowMissingExpectedOldValue: true)
  let pending = new(seq[tuple[varName, side, value: string]])
  pending[] = @[]
  let capturedSide = side
  let capturedPersist = persist
  result.readFile = proc(file: string): WorkspaceReadResult =
    WorkspaceReadResult(ok: true, content: docsAdapterPlaceholder)
  result.patchFile = proc(plan: SourceEditPlan; content: string;
      entry: WorkspaceEditableSchemaEntry): WorkspacePatchResult =
    let varName = if plan.property.len > 0: plan.property else: plan.tokenName
    pending[].add (varName, capturedSide, plan.newValue)
    WorkspacePatchResult(ok: true, patch: WorkspaceFilePatch(
      file: DocsThemeSource,
      afterContent: content,          # server owns the real patch; keep non-empty
      affectedStory: entry.story,
      fullReload: false))
  result.writeFile = proc(file, content: string): WorkspaceOperationResult =
    var ok = true
    for edit in pending[]:
      if not capturedPersist(edit.varName, edit.side, edit.value):
        ok = false
    pending[] = @[]
    if ok: WorkspaceOperationResult(ok: true)
    else: WorkspaceOperationResult(ok: false,
      message: "docs foundation save failed",
      diagnostics: @[WorkspaceEditDiagnostic(kind: wedWriteFailed,
        message: "The docs save endpoint rejected the edit.",
        file: DocsThemeSource)])

when defined(js):
  # JS-target persistence: POST the edit to the dev-server save route. The
  # editor runs in the browser with no filesystem, so this is the ONLY way an
  # in-editor edit reaches disk. `fetch` is fire-and-forget (the editor already
  # re-themes its own preview live via the M3 hook); the server does the
  # structure-preserving write + the docs sites hot-reload from the file change.
  proc jsPostJson(url, body: cstring) =
    {.emit: """
    try {
      fetch(`url`, { method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: `body` });
    } catch (e) {}
    """.}

  proc jsonQuote(s: string): string =
    ## Minimal JSON string encoder (avoids pulling std/json into the JS bundle).
    result = "\""
    for c in s:
      case c
      of '"': result.add "\\\""
      of '\\': result.add "\\\\"
      of '\n': result.add "\\n"
      of '\r': result.add "\\r"
      of '\t': result.add "\\t"
      else: result.add c
    result.add "\""

  proc postDocsFoundationSave*(endpoint, varName, side, value: string): bool
      {.discardable.} =
    ## Issue the foundation-save POST `{"var":..,"side":..,"value":..}` to
    ## `endpoint`. Returns true (the POST is dispatched fire-and-forget; the
    ## server's response drives the file write + hot-reload, not this call).
    let payload = "{" & jsonQuote("var") & ":" & jsonQuote(varName) & "," &
      jsonQuote("side") & ":" & jsonQuote(side) & "," &
      jsonQuote("value") & ":" & jsonQuote(value) & "}"
    jsPostJson(endpoint.cstring, payload.cstring)
    true

  proc docsFetchPersist*(endpoint = docsSaveEndpoint): DocsFoundationPersist =
    ## The JS harness's `persist`: every foundation Save POSTs to `endpoint`.
    (proc(varName, side, value: string): bool =
      postDocsFoundationSave(endpoint, varName, side, value))

  proc postDocsBindingsSave*(endpoint, sidecarJson: string) =
    ## VBIND-M7 SAVE: POST the serialized binding sidecar JSON to `endpoint`
    ## (fire-and-forget, same as the foundation-save POST). The server writes it
    ## to `design/.isonim/bindings.json`; a reload rehydrates from that file.
    jsPostJson(endpoint.cstring, sidecarJson.cstring)

  proc readInjectedBindingsSidecar*(): string =
    ## VBIND-M7 LOAD (client side): read the sidecar JSON the save server
    ## embedded as `window.__ISONIM_BINDINGS__`. Returns "" when absent (no
    ## sidecar on the server, or the page was opened `file://` without the
    ## server), which `loadBindingSidecar` treats as a no-op load.
    var raw: cstring = ""
    {.emit: """
    try {
      if (typeof window !== 'undefined' && window.__ISONIM_BINDINGS__) {
        `raw` = window.__ISONIM_BINDINGS__;
      }
    } catch (e) {}
    """.}
    $raw

# ---------------------------------------------------------------------------
# Full workspace assembly
# ---------------------------------------------------------------------------

proc metacraftEditorWorkspace*(layer: DocsTokenLayer; ts: TokenSet;
    tokensAccessor: proc(): seq[FoundationTokenEntry] {.closure.} = nil;
    foundationSave: DocsFoundationPersist = nil; saveSide = "light"):
    EditorWorkspace =
  ## Assembles the complete Metacraft docs `EditorWorkspace`: the DTCG-derived
  ## foundation tokens + design schema, the real docs-component stories, and
  ## a live-preview hook. When `tokensAccessor` is nil (e.g. before a VM
  ## exists), a snapshot accessor over the freshly-built tokens is used.
  ## When `foundationSave` is supplied (the live-save wiring, M4b) the workspace
  ## gains a `WorkspaceEditAdapter` that routes the editor's Save through it and
  ## flips `writeSource` on, so the Save button is live. When it is nil (the
  ## default, and every M1--M4 test) the workspace is byte-identical to before:
  ## no adapter, read-only source, Save inert.
  var tokens = dtcgFoundationTokens(layer, ts)
  wireContrastPairs(tokens)
  let schema = dtcgDesignSchema(layer, ts, tokens)
  let groups = docsStoryGroups()
  let snapshot = tokens
  let accessor =
    if tokensAccessor.isNil: (proc(): seq[FoundationTokenEntry] = snapshot)
    else: tokensAccessor
  let editAdapter =
    if foundationSave.isNil: nil
    else: docsWorkspaceEditAdapter(tokens, foundationSave, saveSide)
  let permissions = EditorWorkspacePermissions(
    readSource: true, writeSource: not foundationSave.isNil,
    createStory: false, createVariant: false, duplicate: false, delete: false)
  result = newEditorWorkspace(
    title = "Metacraft Docs Design System",
    storyGroups = groups,
    id = "isonim-docs-design",
    description = "Live editor over the isonim-docs --docs-* token layer",
    canvasItems = docsCanvasItems(),
    foundationTokens = tokens,
    designSystemSchema = schema,
    initialView = evFoundationsPage,
    allowedPlatforms = {pbWeb},
    previewHook = docsPreviewHook(accessor),
    editAdapter = editAdapter,
    permissions = permissions)

# ---------------------------------------------------------------------------
# M4: native save seam -- persist a foundation-token edit to the docs token
# file (codetracer-docs.tokens.json) so `just dev-docs` hot-reloads the sites.
# ---------------------------------------------------------------------------
#
# The JS mount harness (`design/main.nim`) has NO filesystem, so persistence
# of an in-editor edit is a native operation (a `just dev-docs` / CLI save
# host round-trips the editor's `SourceEditPlan` to disk). This seam maps an
# `editFoundationToken` plan onto the M4 docs-tokens write-back. It is
# native-only (`dtcg_writeback` uses `std/os`), so the JS build of this module
# -- and every editor pilot -- is byte-unchanged.
when not defined(js):
  import ./dtcg_writeback
  export dtcg_writeback

  proc persistDocsFoundationEdit*(docsTokenFile: string; plan: SourceEditPlan;
      side = "light"; dryRun = false): DtcgWriteResult =
    ## Persist a docs foundation-token `SourceEditPlan` (the plan
    ## `editFoundationToken` emits, carried on its `FoundationEditResult`) to
    ## the shared docs token file as a structure-preserving, validated
    ## raw-text patch. `docsTokenFile` is the workspace's
    ## `theme_tokens.docsDesignSystemPath`. On any failure NOTHING is written
    ## and a `DtcgWriteError` is raised.
    applyDocsTokenEdit(docsTokenFile, plan, side, dryRun)
