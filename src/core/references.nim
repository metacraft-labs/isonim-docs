## isonim-docs Layer 3 — cross-reference resolution for internal docs
## links and anchor fragments (M3 deliverable 2), built on the same real
## content graph M3 deliverable 1's navigation ViewModels use:
## `content.ContentEntry` (source provenance, derived route path),
## `routes.RouteManifest` (the authoritative `contentPath ->
## canonicalPath` binding), and `markdown_vm.MarkdownDoc` (already-parsed
## links and the already-stable heading-anchor IDs).
##
## The one canonical content graph is never forked here: this module
## reuses `markdown_vm.parseMarkdownDoc`'s existing link normalization
## (now given a `resolveContentPath` closure built from the real route
## manifest, so a rendered link's href and this module's validation of
## that same href always agree -- see `markdown_vm.normalizeRelativeLink`'s
## docstring) rather than re-deriving link targets a second, possibly
## disagreeing way.
##
## Pure data + pure checking logic (`checkPageReferences`,
## `collectAnchors`, `findDuplicateRoutePaths`) is Tier-1-testable on both
## `nim c` and `nim js`, exactly like `navigation_vm.nim`. The real
## directory walk (`checkContentGraph`/`validateContentGraph`) is
## C-target-only, for the same reason `content.loadContentEntries` is.

import std/[tables, sets, strutils]
import ./content
import ./routes
import ./markdown_vm

type
  ReferenceIssueKind* = enum
    riUnknownRoute   ## A link's route part matches no known, addressable
                     ## page (and no alias that itself resolves to one).
    riUnknownAnchor  ## A link's `#fragment` matches no heading anchor ID
                     ## on its destination page (same page, for a
                     ## same-page fragment link).
    riDuplicateRoute ## Two content entries derive the exact same route
                     ## path -- an authoring collision (e.g.
                     ## `guide/index.md` and `guide.md`), not a broken
                     ## link, but exactly the kind of silent-at-runtime
                     ## failure this module exists to catch at build time.
    riUnknownSymbol  ## M8 deliverable 2: a `[[sym:...]]` code-symbol
                     ## cross-reference whose query resolves to no exported
                     ## symbol in any `pkSymbolReference` page's parsed
                     ## source -- flagged with source provenance, closing
                     ## cross-link-resolution acceptance criteria 3-4.

  ReferenceIssue* = object
    kind*: ReferenceIssueKind
    sourcePath*: string ## `ContentEntry.source.path` -- the authored file
                        ## the broken reference lives in.
    sourceLine*: int    ## `ContentEntry.source.line` -- the line the
                        ## file's own body starts at. Reference tracking
                        ## is page-granular, not per-link, so every issue
                        ## found in one page cites that page's own body
                        ## start line.
    targetHref*: string ## The (already-normalized) link target the issue
                        ## is about.

proc formatReferenceIssue*(issue: ReferenceIssue): string =
  ## The actionable "file:line: ..." message broken-reference reporting
  ## cites -- pure string formatting, so it's usable from both the
  ## dual-target unit suite and the C-target build-failure path.
  let reason =
    case issue.kind
    of riUnknownRoute: "no known route serves this target"
    of riUnknownAnchor: "target page has no such anchor"
    of riDuplicateRoute: "another content file already resolves to this same route"
    of riUnknownSymbol: "no exported symbol matches this [[sym:...]] reference"
  issue.sourcePath & ":" & $issue.sourceLine & ": broken reference to \"" &
    issue.targetHref & "\" (" & reason & ")"

proc collectAnchorsInto(nodes: seq[HeadingNode]; acc: var HashSet[string]) =
  for node in nodes:
    acc.incl node.id
    collectAnchorsInto(node.children, acc)

proc collectAnchors*(nodes: seq[HeadingNode]): HashSet[string] =
  ## Flattens a page's heading tree (`markdown_vm.MarkdownDoc.headingTree`)
  ## into the flat set of anchor IDs deep links/fragments may target.
  result = initHashSet[string]()
  collectAnchorsInto(nodes, result)

proc isPageHref(routePart: string): bool =
  ## Whether `routePart` (the part of a normalized href before any
  ## `#fragment`) looks like a docs page route rather than a static
  ## asset reference -- routes never carry a file extension on their
  ## final segment, assets (images, downloads, ...) always do. Asset
  ## references are out of this module's scope (there is no asset graph
  ## to validate them against yet), so this is the one place that
  ## distinction is drawn rather than threading a second field through
  ## `InlineSpan`.
  if routePart.len == 0: return false
  if routePart == "/": return true
  let lastSlash = routePart.rfind('/')
  let lastSeg = if lastSlash >= 0: routePart[lastSlash + 1 .. ^1] else: routePart
  '.' notin lastSeg

proc linkSpans(blocks: seq[Block]): seq[InlineSpan] =
  ## Every `ikLink` inline span reachable from a page's parsed block
  ## list -- paragraphs, list items, and admonition body paragraphs are
  ## the only block kinds `markdown_vm` gives inline spans to directly;
  ## `bkTabs` panels recurse (each panel's own `blocks` is a full nested
  ## block list, so a link inside a tab panel is just as reachable as one
  ## at the top level). `ikImage` spans are asset references, not page
  ## links, so they're never collected here.
  for blk in blocks:
    case blk.kind
    of bkParagraph:
      for s in blk.spans:
        if s.kind == ikLink: result.add s
    of bkList:
      for item in blk.items:
        for s in item:
          if s.kind == ikLink: result.add s
    of bkAdmonition:
      for para in blk.bodyParagraphs:
        for s in para:
          if s.kind == ikLink: result.add s
    of bkTabs:
      for panel in blk.tabs:
        result.add linkSpans(panel.blocks)
    of bkHeading, bkCodeFence, bkTable, bkComponent,
       bkCardGrid, bkHero, bkButton, bkFaq, bkVideo, bkForm:
      ## M2 content components carry their hrefs as plain-string card/button
      ## targets rather than `ikLink` inline spans, so they're out of scope
      ## for inline-link reference checking (like `bkComponent`).
      discard

proc symRefSpans(blocks: seq[Block]): seq[InlineSpan] =
  ## Every `ikSymRef` inline span (`[[sym:...]]`, M8 deliverable 2)
  ## reachable from a page's parsed block list -- the same block kinds
  ## `linkSpans` reaches, recursing into `bkTabs` panels identically.
  for blk in blocks:
    case blk.kind
    of bkParagraph:
      for s in blk.spans:
        if s.kind == ikSymRef: result.add s
    of bkList:
      for item in blk.items:
        for s in item:
          if s.kind == ikSymRef: result.add s
    of bkAdmonition:
      for para in blk.bodyParagraphs:
        for s in para:
          if s.kind == ikSymRef: result.add s
    of bkTabs:
      for panel in blk.tabs:
        result.add symRefSpans(panel.blocks)
    of bkHeading, bkCodeFence, bkTable, bkComponent,
       bkCardGrid, bkHero, bkButton, bkFaq, bkVideo, bkForm:
      ## M2 content components carry their hrefs as plain-string card/button
      ## targets rather than `ikLink` inline spans, so they're out of scope
      ## for inline-link reference checking (like `bkComponent`).
      discard

proc checkPageReferences*(doc: MarkdownDoc; source: ContentSource; ownRoutePath: string;
                           knownRoutes: HashSet[string];
                           anchorsByRoute: Table[string, HashSet[string]];
                           aliases: Table[string, string] = initTable[string, string]();
                           symbolIndex: Table[string, string] = initTable[string, string]()):
    seq[ReferenceIssue] =
  ## Checks every internal link `doc` carries against the rest of the
  ## content graph: a same-page `#fragment` must name one of this page's
  ## own anchors; a cross-page link's route part must be a known,
  ## addressable route (directly, or via `aliases` -- a redirect source
  ## mapping to a known route counts as known, the hook M3 deliverable
  ## 3's redirect table plugs into without this module forking a second
  ## notion of "known route"), and if it also carries a `#fragment`, that
  ## fragment must be one of the *destination* page's own anchors.
  ## Static-asset references (`isPageHref` false) and external/absolute
  ## links (`isRelative` false, besides same-page fragments) are out of
  ## scope and never flagged.
  for span in linkSpans(doc.blocks):
    let href = span.href
    if href.len == 0: continue
    if href[0] == '#':
      let anchor = href[1 .. ^1]
      let ownAnchors = anchorsByRoute.getOrDefault(ownRoutePath, initHashSet[string]())
      if anchor notin ownAnchors:
        result.add ReferenceIssue(kind: riUnknownAnchor, sourcePath: source.path,
          sourceLine: source.line, targetHref: href)
      continue
    if not span.isRelative: continue
    let hashIdx = href.find('#')
    let routePart = if hashIdx >= 0: href[0 ..< hashIdx] else: href
    let fragPart = if hashIdx >= 0: href[hashIdx + 1 .. ^1] else: ""
    if not isPageHref(routePart): continue
    let resolvedRoute =
      if routePart in knownRoutes: routePart
      elif routePart in aliases and aliases[routePart] in knownRoutes: aliases[routePart]
      else: ""
    if resolvedRoute.len == 0:
      result.add ReferenceIssue(kind: riUnknownRoute, sourcePath: source.path,
        sourceLine: source.line, targetHref: href)
    elif fragPart.len > 0:
      let targetAnchors = anchorsByRoute.getOrDefault(resolvedRoute, initHashSet[string]())
      if fragPart notin targetAnchors:
        result.add ReferenceIssue(kind: riUnknownAnchor, sourcePath: source.path,
          sourceLine: source.line, targetHref: href)

  ## M8 deliverable 2: every `[[sym:...]]` code-symbol cross-reference is
  ## resolved against the global `symbolIndex` (query -> anchor href, built
  ## from every `pkSymbolReference` page's parsed source). A query that
  ## matches no exported symbol is flagged with this page's own source
  ## provenance -- the same file:line pair every other issue kind cites.
  for span in symRefSpans(doc.blocks):
    if span.text notin symbolIndex:
      result.add ReferenceIssue(kind: riUnknownSymbol, sourcePath: source.path,
        sourceLine: source.line, targetHref: "[[sym:" & span.text & "]]")

proc findDuplicateRoutePaths*(entries: seq[ContentEntry]): seq[ReferenceIssue] =
  ## Flags content entries whose own derived `routePath` collides with an
  ## earlier entry's -- two authored files that would resolve to the
  ## same servable route (e.g. `guide/index.md` and `guide.md` both
  ## deriving to `/guide`). Pure `ContentEntry` data, no manifest or
  ## filesystem access needed, so it's exercisable with hand-built
  ## fixture entries on both targets.
  var seenAt = initTable[string, string]()
  for entry in entries:
    if seenAt.hasKey(entry.routePath):
      result.add ReferenceIssue(kind: riDuplicateRoute, sourcePath: entry.source.path,
        sourceLine: entry.source.line, targetHref: entry.routePath)
    else:
      seenAt[entry.routePath] = entry.source.path

proc contentPathToRouteMap*(manifest: RouteManifest): Table[string, string] =
  ## The real route manifest's own `contentPath -> canonicalPath`
  ## binding -- the one table both rendering (`normalizeRelativeLink`'s
  ## `resolveContentPath`) and this module's own `knownRoutes` set are
  ## built from, so a link's rendered href and its validation target
  ## never disagree. `pkRedirect` alias entries (M3 deliverable 3) carry
  ## no `meta.contentPath` of their own -- they're excluded here the same
  ## way `rsNotFound` is, so an alias never pollutes this map with a
  ## spurious `"" -> aliasTarget` binding.
  result = initTable[string, string]()
  for entry in manifest.entries:
    if entry.status != rsNotFound and entry.pageKind != pkRedirect:
      result[entry.meta.contentPath] = entry.canonicalPath

proc buildAliasMap*(entries: seq[ContentEntry];
                     contentPathToRoute: Table[string, string]): Table[string, string] =
  ## M3 deliverable 3's authoring-to-validation bridge: flattens every
  ## content entry's own front matter `aliases:` list (old, pre-rename
  ## route paths, `content.ContentFrontMatter.aliases`) into the
  ## `oldRoutePath -> currentRoutePath` table `checkPageReferences`'s own
  ## `aliases` parameter already knew how to consume (added in M3
  ## deliverable 2, before this table had anything real to build it
  ## from). Resolves the target through `contentPathToRoute` (the same
  ## manifest-derived table `knownRoutes` itself comes from) rather than
  ## `ContentEntry.routePath` -- M3 deliverable 1's own navigation ViewModel
  ## docstring already proved those two can disagree (see
  ## `navigation_vm.navPage`), so an alias's mapped target must agree with
  ## the exact same canonical path `knownRoutes` checks against. Content
  ## not bound to any real manifest route is skipped -- there's no
  ## canonical path for its own aliases to resolve to, mirroring
  ## `checkContentGraph`'s own "bound" filter. Pure data, no filesystem
  ## access, so it's exercisable on both targets with hand-built fixture
  ## entries, exactly like `findDuplicateRoutePaths`.
  result = initTable[string, string]()
  for entry in entries:
    if not contentPathToRoute.hasKey(entry.source.path): continue
    let route = contentPathToRoute[entry.source.path]
    for alias in entry.front.aliases:
      result[normalizeRoutePath(alias)] = route

proc buildAliasRouteEntries*(manifest: RouteManifest;
                              loadEntry: proc(contentPath: string): ContentEntry {.closure.}):
    seq[RouteEntry] =
  ## The routing-side counterpart to `buildAliasMap`: one real,
  ## matchable `pkRedirect` entry (`routes.newRedirectEntry`) per authored
  ## alias, so an old inbound link to a renamed page's previous route
  ## actually resolves (a real 301, not a 404) instead of only being
  ## tolerated by `checkPageReferences`' validation. Mirrors
  ## `navigation_vm.buildNavPages`'s own tolerance policy exactly: an
  ## entry whose content fails to load under `loadEntry` (a hermetic
  ## fixture manifest/content mismatch) is silently left out rather than
  ## failing the whole build -- broken references failing the build is
  ## `validateContentGraph`'s job, not this one's.
  for entry in manifest.entries:
    try:
      let content = loadEntry(entry.meta.contentPath)
      for alias in content.front.aliases:
        result.add newRedirectEntry(alias, entry.canonicalPath)
    except CatchableError:
      discard

proc withAliasRedirects*(manifest: RouteManifest; aliasEntries: seq[RouteEntry]): RouteManifest =
  ## Appends `aliasEntries` (typically `buildAliasRouteEntries`'s own
  ## output) to `manifest`'s real entries -- the one canonical content
  ## graph M3's own integration constraint requires, extended rather than
  ## forked, so `matchRoute` sees old alias paths alongside every real
  ## route in the exact same list. Real entries come first, so an alias
  ## can never shadow a still-live route of the same path.
  RouteManifest(entries: manifest.entries & aliasEntries, notFound: manifest.notFound)

proc makeContentPathResolver*(manifest: RouteManifest): proc(contentRelPath: string): string {.closure.} =
  ## The one `resolveContentPath` closure both the SSR entry
  ## (`src/ssr.nim`), the JS mount entry (`src/main_web.nim`), and this
  ## module's own `checkContentGraph` build off `manifest` and pass into
  ## `markdown_vm.parseMarkdownDoc` -- so a page's rendered link hrefs and
  ## this module's validation of those same hrefs are always the exact
  ## same resolution, never two independently-derived opinions. Falls
  ## back to `content.nim`'s own `deriveSlug`/`deriveSection`/
  ## `deriveRoutePath` guess for a content path with no manifest route
  ## (content not yet wired into a route, e.g. mid-authoring).
  let contentPathToRoute = contentPathToRouteMap(manifest)
  result = proc(p: string): string =
    if contentPathToRoute.hasKey(p): contentPathToRoute[p]
    else:
      let slug = deriveSlug(p, ContentFrontMatter())
      let section = deriveSection(p, ContentFrontMatter())
      deriveRoutePath(section, slug)

when not defined(js):
  import ./openapi
  import ./api_reference_vm
  import ./nimdoc
  import ./symbol_reference_vm

  proc buildSymbolIndex*(contentDir: string; manifest: RouteManifest): Table[string, string] =
    ## M8 deliverable 2: the global `[[sym:...]]` query -> anchor-href map,
    ## built by parsing every `pkSymbolReference` page's bound Nim source
    ## (`nimdoc.parseNimDoc`) and adding its `query -> routePath#anchor`
    ## entries (`symbol_reference_vm.addSymbolIndexEntries`). The one place
    ## the SSR render path (`ssr.renderRoute`, so a valid symref rewrites to
    ## a real link) and this module's own reference check both resolve
    ## symrefs from, so a rendered symref's href and its validation always
    ## agree. Tolerant: a source that can't be read/parsed simply
    ## contributes no entries (the "never fail the whole build on a load
    ## error" policy `checkContentGraph`'s OpenAPI branch already follows).
    result = initTable[string, string]()
    for entry in manifest.entries:
      if entry.pageKind == pkSymbolReference:
        try:
          let srcPath = contentDir & "/" & entry.meta.contentPath
          let ingest = parseNimDoc(readFile(srcPath), moduleNameFromPath(entry.meta.contentPath))
          addSymbolIndexEntries(result, ingest.module, entry.canonicalPath)
        except CatchableError:
          discard

  type
    BrokenReferenceError* = object of CatchableError
      issues*: seq[ReferenceIssue] ## The full list of issues found, for
                                  ## callers that want to inspect/report
                                  ## structured data rather than just the
                                  ## joined `.msg`.

  proc checkContentGraph*(contentDir: string; manifest: RouteManifest;
                           includeDrafts: bool = false;
                           aliases: Table[string, string] = initTable[string, string]()):
      seq[ReferenceIssue] =
    ## Loads every real content file under `contentDir` (never a mocked
    ## filesystem, per the M0 harness rule) and checks the *whole* graph's
    ## cross-references and anchor fragments together, so a broken
    ## reference anywhere fails the whole build rather than only the one
    ## page that happens to get rendered. Content not bound to any real
    ## manifest route is outside the addressable graph and isn't checked
    ## for outgoing references (there is no serving route to validate its
    ## links' destinations against) -- `findDuplicateRoutePaths` still
    ## covers it, since a route collision is a property of the content
    ## files themselves, independent of manifest wiring.
    let contentPathToRoute = contentPathToRouteMap(manifest)
    let resolveContentPath = makeContentPathResolver(manifest)

    let entries = loadContentEntries(contentDir, includeDrafts)
    result.add findDuplicateRoutePaths(entries)

    var allAliases = buildAliasMap(entries, contentPathToRoute) ## M3 deliverable 3: every
      ## authored front matter `aliases:` entry counts as known on its
      ## own, without a caller having to rebuild this table by hand --
      ## `aliases` below still layers on top (and wins on key collision)
      ## for callers (e.g. redirects not yet expressed in content) that
      ## need to widen the table further.
    for k, v in aliases:
      allAliases[k] = v

    var bound: seq[tuple[route: string, source: ContentSource, doc: MarkdownDoc]] = @[]
    for entry in entries:
      if not contentPathToRoute.hasKey(entry.source.path): continue
      let route = contentPathToRoute[entry.source.path]
      let doc = parseMarkdownDoc(entry.page.body, entry.source.path, resolveContentPath)
      bound.add (route, entry.source, doc)

    var knownRoutes = initHashSet[string]()
    for route in contentPathToRoute.values:
      knownRoutes.incl route

    var anchorsByRoute = initTable[string, HashSet[string]]()
    for b in bound:
      anchorsByRoute[b.route] = collectAnchors(b.doc.headingTree)

    ## M7 deliverable 3: an OpenAPI reference page's per-operation anchors
    ## (`api_reference_vm.operationAnchorIds`) are added to the same
    ## `anchorsByRoute` table markdown heading anchors go into, so an
    ## in-site link to `<api-route>#operation-...` resolves through the
    ## exact same `checkPageReferences` path a heading-anchor link does --
    ## and a genuine typo in an operation anchor is still caught. Tolerant:
    ## a spec that can't be read/parsed simply contributes no anchors here
    ## (the same "never fail the whole build on a load error" policy
    ## `buildNavPages`/`buildAliasRouteEntries` follow), rather than
    ## crashing the reference check.
    for entry in manifest.entries:
      if entry.pageKind == pkApiReference and contentPathToRoute.hasKey(entry.meta.contentPath):
        try:
          let specPath = contentDir & "/" & entry.meta.contentPath
          let ingest = ingestOpenApi(readFile(specPath), entry.meta.contentPath)
          var apiAnchors = initHashSet[string]()
          for a in operationAnchorIds(ingest.spec): apiAnchors.incl a
          anchorsByRoute[contentPathToRoute[entry.meta.contentPath]] = apiAnchors
        except CatchableError:
          discard

    ## M8 deliverable 2: a `pkSymbolReference` page's per-symbol anchors
    ## (`symbol_reference_vm.symbolAnchorIds`) are added to the same
    ## `anchorsByRoute` table, so a plain in-site link to
    ## `<sym-route>#sym-Type.proc` validates through the exact same path a
    ## heading-anchor link does -- and the `[[sym:...]]` shorthand resolves
    ## through `symbolIndex` below (built once, shared with the SSR render).
    for entry in manifest.entries:
      if entry.pageKind == pkSymbolReference and contentPathToRoute.hasKey(entry.meta.contentPath):
        try:
          let srcPath = contentDir & "/" & entry.meta.contentPath
          let ingest = parseNimDoc(readFile(srcPath), moduleNameFromPath(entry.meta.contentPath))
          var symAnchors = initHashSet[string]()
          for a in symbolAnchorIds(ingest.module): symAnchors.incl a
          anchorsByRoute[contentPathToRoute[entry.meta.contentPath]] = symAnchors
        except CatchableError:
          discard

    let symbolIndex = buildSymbolIndex(contentDir, manifest)

    for b in bound:
      result.add checkPageReferences(b.doc, b.source, b.route, knownRoutes,
                                      anchorsByRoute, allAliases, symbolIndex)

  proc validateContentGraph*(contentDir: string; manifest: RouteManifest;
                              includeDrafts: bool = false;
                              aliases: Table[string, string] = initTable[string, string]()) =
    ## The enforcing form `checkContentGraph`'s query form feeds: raises a
    ## typed `BrokenReferenceError` (never a silent return) the instant
    ## the content graph carries any broken reference, so a caller that
    ## simply calls this and doesn't catch it gets exactly the "fail the
    ## build" behavior M3 deliverable 2 requires. `../check_links.nim` is
    ## the CI-facing entry point that does exactly that.
    let issues = checkContentGraph(contentDir, manifest, includeDrafts, aliases)
    if issues.len > 0:
      var msg = "broken internal references found:\n"
      for issue in issues:
        msg.add "  " & formatReferenceIssue(issue) & "\n"
      var e = newException(BrokenReferenceError, msg)
      e.issues = issues
      raise e
