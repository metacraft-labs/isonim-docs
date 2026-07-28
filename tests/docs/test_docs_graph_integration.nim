## Tier 1 (ViewModel / pure-helper) M3 integration suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## M3 deliverable 4: the first explicit cross-feature integration test.
## M2's content loader, M1's routing, and M3's own navigation
## (`navigation_vm.nim`) and references (`references.nim`) subsystems
## are each unit-tested against their own hand-built fixtures elsewhere
## (`test_markdown_vm.nim`, `test_routes_vm.nim`, `test_navigation_vm.nim`,
## `test_references_vm.nim`, `test_redirects_vm.nim`); none of those
## suites prove the four subsystems *agree* when driven from the exact
## same content graph at once. This suite builds one small, realistic
## multi-page graph in memory (`parseContentEntry` + a hand-built
## `RouteManifest`, mirroring the real repo's own `getting-started.md`
## content-loader/routing disagreement -- see `navigation_vm.navPage`'s
## docstring) and drives it through all four subsystems together:
## content loader -> routing -> navigation -> references, plus M3
## deliverable 3's redirect/alias bridge. No filesystem access anywhere
## (that's `test_docs_graph_integration_renderroute.nim`'s job, against
## real fixture files and the real `content/` dir), so this suite is
## Tier-1-testable on both `nim c` and `nim js`, exactly like the
## per-deliverable `_vm.nim` suites it complements.

import std/[unittest, tables, sets]
import ../../src/core/content
import ../../src/core/routes
import ../../src/core/navigation_vm
import ../../src/core/references
import ../../src/core/markdown_vm

# --- The one shared graph every test below is driven from -------------

const getStartedRaw = "# Getting Started\n\nInstall the framework.\n"
const dslRaw = "# The ui DSL\n\n## Elements\n\nBuild trees with `ui:`. See [Getting Started](../getting-started.md) first.\n"
const otherRaw = "# Other Guide\n\nSee [the DSL guide](./dsl.md) and its [elements section](./dsl.md#elements), plus [Getting Started](/guide/getting-started).\n"
const overviewRaw = "---\naliases: /editor\n---\n# Editor Overview\n\nWorkspace model.\n"

proc buildGraphEntries(): Table[string, ContentEntry] =
  ## Mirrors `content.loadContentEntries`' per-file parsing step
  ## (`parseContentEntry`), but over in-memory strings so both targets
  ## can build the exact same graph the C-target renderroute companion
  ## builds from real files.
  result = initTable[string, ContentEntry]()
  result["getting-started.md"] = parseContentEntry(getStartedRaw, "getting-started.md")
  result["guide/dsl.md"] = parseContentEntry(dslRaw, "guide/dsl.md")
  result["guide/other.md"] = parseContentEntry(otherRaw, "guide/other.md")
  result["editor/overview.md"] = parseContentEntry(overviewRaw, "editor/overview.md")

proc buildGraphManifest(): RouteManifest =
  ## Deliberately keeps the real repo's own content-loader/routing
  ## disagreement: `getting-started.md`'s own derived `routePath` is
  ## `/getting-started` (see the check below), but the manifest binds it
  ## to `/guide/getting-started` -- routing's answer wins everywhere
  ## downstream, exactly like the real site.
  newRouteManifest(@[
    newRouteEntry("/guide/getting-started", pkMarkdown,
      meta = RouteMeta(title: "Getting Started", contentPath: "getting-started.md")),
    newRouteEntry("/guide/dsl", pkMarkdown,
      meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
    newRouteEntry("/guide/other", pkMarkdown,
      meta = RouteMeta(title: "Other Guide", contentPath: "guide/other.md")),
    newRouteEntry("/editor/overview", pkMarkdown,
      meta = RouteMeta(title: "Editor Overview", contentPath: "editor/overview.md")),
  ])

suite "docs integration -- content loader and routing can disagree, navigation follows routing (Tier 1, dual-target)":
  test "content loader derives its own routePath, independent of any manifest binding":
    let entries = buildGraphEntries()
    check entries["getting-started.md"].routePath == "/getting-started"

  test "navigation follows the routing manifest's canonicalPath, not the content loader's own derived routePath":
    let entries = buildGraphEntries()
    let manifest = buildGraphManifest()
    let pages = buildNavPages(manifest, proc(contentPath: string): ContentEntry = entries[contentPath])
    var found = false
    for page in pages:
      if page.slug == "getting-started":
        found = true
        check page.routePath == "/guide/getting-started"
    check found

suite "docs integration -- navigation ViewModels agree with the routing-derived page list (Tier 1, dual-target)":
  test "sidebar and prev/next always point at real manifest canonical paths":
    let entries = buildGraphEntries()
    let manifest = buildGraphManifest()
    let pages = buildNavPages(manifest, proc(contentPath: string): ContentEntry = entries[contentPath])
    check pages.len == 4
    let nav = buildNavigationViewModel(pages, "/guide/dsl")

    var knownRoutes = initHashSet[string]()
    for entry in manifest.entries: knownRoutes.incl entry.canonicalPath

    for section in nav.sidebar.sections:
      for item in section.items:
        check item.routePath in knownRoutes
    check nav.previous.routePath.len == 0 or nav.previous.routePath in knownRoutes
    check nav.next.routePath.len == 0 or nav.next.routePath in knownRoutes

  test "breadcrumbs: the home crumb and the current-page crumb are always real routes; a section crumb is a best-effort label, not required to be one":
    # Resolves iteration 1.1's own open design note (see
    # `navigation_vm.buildBreadcrumbs`'s docstring): a section crumb
    # points at that section's own index route
    # (`deriveRoutePath(section, "index")`), which this graph -- like
    # the real `content/` dir -- never actually binds a page to (no
    # `guide/index.md` route in `buildGraphManifest`). D4 decides this
    # is intentional: the section crumb is a display-only label, exempt
    # from the "every nav link is a live route" invariant every other
    # nav surface (sidebar, prev/next, and the home/current crumbs
    # below) is held to.
    let entries = buildGraphEntries()
    let manifest = buildGraphManifest()
    let pages = buildNavPages(manifest, proc(contentPath: string): ContentEntry = entries[contentPath])
    let nav = buildNavigationViewModel(pages, "/guide/dsl")

    var knownRoutes = initHashSet[string]()
    for entry in manifest.entries: knownRoutes.incl entry.canonicalPath

    check nav.breadcrumbs.len == 3
    check nav.breadcrumbs[0].routePath == "/"
    check nav.breadcrumbs[1].routePath == "/guide" # the best-effort, non-routable section label
    check "/guide" notin knownRoutes
    check nav.breadcrumbs[2].routePath == "/guide/dsl"
    check nav.breadcrumbs[2].routePath in knownRoutes
    check nav.breadcrumbs[2].isCurrent

suite "docs integration -- references validate the same links routing/navigation resolve (Tier 1, dual-target)":
  test "a fully cross-linked graph, parsed with routing's own resolver, has no reference issues":
    let entries = buildGraphEntries()
    let manifest = buildGraphManifest()
    let resolveContentPath = makeContentPathResolver(manifest)
    let contentPathToRoute = contentPathToRouteMap(manifest)

    var knownRoutes = initHashSet[string]()
    for route in contentPathToRoute.values: knownRoutes.incl route

    var docs = initTable[string, MarkdownDoc]()
    var anchorsByRoute = initTable[string, HashSet[string]]()
    for contentPath, entry in entries:
      let doc = parseMarkdownDoc(entry.page.body, entry.source.path, resolveContentPath)
      docs[contentPathToRoute[contentPath]] = doc
      anchorsByRoute[contentPathToRoute[contentPath]] = collectAnchors(doc.headingTree)

    var issues: seq[ReferenceIssue] = @[]
    for contentPath, entry in entries:
      let route = contentPathToRoute[contentPath]
      issues.add checkPageReferences(docs[route], entry.source, route, knownRoutes, anchorsByRoute)
    check issues.len == 0

  test "the same graph's rendered link hrefs (via resolveContentPath) match routing's own canonicalPath":
    let entries = buildGraphEntries()
    let manifest = buildGraphManifest()
    let resolveContentPath = makeContentPathResolver(manifest)
    let doc = parseMarkdownDoc(entries["guide/other.md"].page.body, "guide/other.md", resolveContentPath)
    var hrefs: seq[string] = @[]
    for blk in doc.blocks:
      if blk.kind == bkParagraph:
        for span in blk.spans:
          if span.kind == ikLink: hrefs.add span.href
    check "/guide/dsl" in hrefs
    check "/guide/dsl#elements" in hrefs
    check "/guide/getting-started" in hrefs

  test "a broken cross-page reference in the same graph is caught with its own source provenance":
    let manifest = buildGraphManifest()
    let resolveContentPath = makeContentPathResolver(manifest)
    let brokenRaw = "# Other Guide\n\nSee [a missing page](./missing.md) for more.\n"
    let brokenEntry = parseContentEntry(brokenRaw, "guide/other.md")
    let doc = parseMarkdownDoc(brokenEntry.page.body, brokenEntry.source.path, resolveContentPath)

    var knownRoutes = initHashSet[string]()
    for route in contentPathToRouteMap(manifest).values: knownRoutes.incl route

    let issues = checkPageReferences(doc, brokenEntry.source, "/guide/other", knownRoutes,
      initTable[string, HashSet[string]]())
    check issues.len == 1
    check issues[0].kind == riUnknownRoute
    check issues[0].sourcePath == "guide/other.md"
    check issues[0].targetHref == "/guide/missing"

  test "findDuplicateRoutePaths flags a content-loader-level collision independent of routing's own manifest binding":
    let a = parseContentEntry("# Guide\n\nBody.", "guide.md")
    let b = parseContentEntry("# Guide Home\n\nBody.", "guide/index.md")
    let issues = findDuplicateRoutePaths(@[a, b])
    check issues.len == 1
    check issues[0].kind == riDuplicateRoute

suite "docs integration -- redirects/aliases stay consistent across routing, navigation, and references (Tier 1, dual-target)":
  test "an authored alias is routable, resolvable by references, and excluded from the navigation page list":
    let entries = buildGraphEntries()
    let manifest = buildGraphManifest()
    let contentPathToRoute = contentPathToRouteMap(manifest)

    let aliasEntries = buildAliasRouteEntries(manifest,
      proc(contentPath: string): ContentEntry = entries[contentPath])
    check aliasEntries.len == 1
    check aliasEntries[0].redirectTo == "/editor/overview"

    let extended = withAliasRedirects(manifest, aliasEntries)
    check matchRoute(extended, "/editor").entry.pageKind == pkRedirect
    check matchRoute(extended, "/editor").entry.redirectTo == "/editor/overview"
    check matchRoute(extended, "/editor/overview").entry.pageKind == pkMarkdown

    let aliasMap = buildAliasMap(@[entries["editor/overview.md"]], contentPathToRoute)
    check aliasMap["/editor"] == "/editor/overview"

    var knownRoutes = initHashSet[string]()
    for route in contentPathToRoute.values: knownRoutes.incl route
    # A relative link to the *old* "editor.md" path (moved to
    # "editor/overview.md" and aliased from "/editor") normalizes,
    # through routing's own `resolveContentPath` fallback guess, to the
    # exact alias key `aliasMap` carries -- proving references, routing,
    # and the alias bridge agree on the one graph, not three separate
    # opinions.
    let refRaw = "# Another Page\n\nSee [the editor](../editor.md) for more.\n"
    let refEntry = parseContentEntry(refRaw, "guide/another.md")
    let resolveContentPath = makeContentPathResolver(manifest)
    let doc = parseMarkdownDoc(refEntry.page.body, refEntry.source.path, resolveContentPath)
    check doc.blocks[0].spans[1].href == "/editor"
    let issues = checkPageReferences(doc, refEntry.source, "/guide/another", knownRoutes,
      initTable[string, HashSet[string]](), aliasMap)
    check issues.len == 0
    # Without the alias bridge, the exact same link is a broken
    # reference -- proving `aliasMap` is doing real work above, not
    # passing by coincidence.
    let issuesNoAlias = checkPageReferences(doc, refEntry.source, "/guide/another", knownRoutes,
      initTable[string, HashSet[string]]())
    check issuesNoAlias.len == 1
    check issuesNoAlias[0].kind == riUnknownRoute

    let navPages = buildNavPages(extended,
      proc(contentPath: string): ContentEntry =
        if contentPath.len == 0: raise newException(KeyError, "redirect entries carry no content path")
        entries[contentPath])
    check navPages.len == 4
    for page in navPages:
      check page.routePath != "/editor"
