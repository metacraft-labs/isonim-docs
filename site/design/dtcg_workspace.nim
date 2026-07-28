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

const DocsThemeSource* = "site/src/theme_tokens.nim"
  ## The source file the docs token layer is authored in; recorded on each
  ## FoundationTokenEntry so the editor's "open source" affordance and the
  ## M2 write-back have a real anchor.

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
          kind: skFoundation, group: "Foundations"),
        StoryItem(name: "Typography", description: "Geist font stack, sizes, line height",
          kind: skFoundation, group: "Foundations"),
        StoryItem(name: "Spacing & Radii", description: "Spacing scale + border radii vocabulary",
          kind: skFoundation, group: "Foundations")]),
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
  result = proc(story: StoryRef; platform: Platform): ProjectPreview =
    let tokens = tokensAccessor()
    proc valueOf(prop: string): string =
      for t in tokens:
        if t.property == prop or t.key == prop: return t.value
      ""
    # The --docs-* variables this particular story showcases.
    var lines: seq[string]
    for t in tokens:
      if story in t.affectedStories:
        lines.add t.key & "=" & t.value
    if lines.len == 0:
      return ProjectPreview(status: ppsUnsupportedStory, story: story)
    ProjectPreview(
      status: ppsRendered,
      story: story,
      title: story.group & " / " & story.name,
      bodyText: lines.join("; "))

# ---------------------------------------------------------------------------
# Full workspace assembly
# ---------------------------------------------------------------------------

proc metacraftEditorWorkspace*(layer: DocsTokenLayer; ts: TokenSet;
    tokensAccessor: proc(): seq[FoundationTokenEntry] {.closure.} = nil):
    EditorWorkspace =
  ## Assembles the complete Metacraft docs `EditorWorkspace`: the DTCG-derived
  ## foundation tokens + design schema, the real docs-component stories, and
  ## a live-preview hook. When `tokensAccessor` is nil (e.g. before a VM
  ## exists), a snapshot accessor over the freshly-built tokens is used.
  var tokens = dtcgFoundationTokens(layer, ts)
  wireContrastPairs(tokens)
  let schema = dtcgDesignSchema(layer, ts, tokens)
  let groups = docsStoryGroups()
  let snapshot = tokens
  let accessor =
    if tokensAccessor.isNil: (proc(): seq[FoundationTokenEntry] = snapshot)
    else: tokensAccessor
  result = newEditorWorkspace(
    title = "Metacraft Docs Design System",
    storyGroups = groups,
    id = "isonim-docs-design",
    description = "Live editor over the isonim-docs --docs-* token layer",
    canvasItems = docsCanvasItems(),
    foundationTokens = tokens,
    designSystemSchema = schema,
    initialView = evFoundationsPage,
    previewHook = docsPreviewHook(accessor),
    permissions = EditorWorkspacePermissions(
      readSource: true, writeSource: false, createStory: false,
      createVariant: false, duplicate: false, delete: false))
