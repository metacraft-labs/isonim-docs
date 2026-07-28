## Tier 1 (pure ViewModel/data) M3 authoring-edge-case suite -- dual-target.
##
## M3 deliverable 5: codifies, as executable fixtures, the four edge
## cases the milestone names by name -- duplicate slugs, missing
## anchors, circular nav placement, and stale aliases -- resolving the
## open design questions the earlier M3 iterations left behind rather
## than leaving them as prose. Duplicate slugs and missing anchors are
## already build-FAILURE modes proven pure-data-level in
## `test_references_vm.nim`; this file's own job is the two edge cases
## that were never pinned down as pass/fail either way:
##
## - Circular nav placement: `navigation_vm.buildBreadcrumbs`'s own
##   docstring (M3 deliverable 1) already notes a section's own index
##   page derives a breadcrumb trail whose section crumb and current-page
##   crumb point at the *exact same* route -- iteration 1.1/1.4's open
##   question ("does that crumb need the same broken-reference check
##   real links get?") is answered here for the self-referencing case:
##   it's an intentional, non-failing shape (`buildBreadcrumbs` never
##   raises), asserted explicitly so a future change can't silently
##   dedupe or break it without a test noticing.
## - Stale aliases: iteration 1.3's own open question ("nothing currently
##   asserts whether a stale alias's silently-tolerated shape is desired
##   or should be a build failure") is answered here: an alias authored
##   on content not bound to any manifest route is silently dropped (not
##   a build failure), and `routes.matchRoute`'s first-match-wins order
##   (`routes.withAliasRedirects` always appends alias entries *after*
##   real ones) means a stale alias can never shadow a live route even
##   if its old path happens to collide with one.

import std/[unittest, tables]
import ../../src/core/content
import ../../src/core/routes
import ../../src/core/navigation_vm
import ../../src/core/references

suite "docs authoring edge cases -- circular nav placement (Tier 1, dual-target)":
  test "a section index page's breadcrumbs self-loop: the section crumb and the current-page crumb both target the section's own route":
    let pages = @[
      NavPage(routePath: "/", title: "Welcome", section: "", order: 0, slug: "index"),
      NavPage(routePath: "/guide", title: "Guide Home", section: "guide", order: 0, slug: "index"),
      NavPage(routePath: "/guide/dsl", title: "The ui DSL", section: "guide", order: 1, slug: "dsl"),
    ]
    let crumbs = buildBreadcrumbs(pages, "/guide")
    check crumbs.len == 3
    check crumbs[0] == Breadcrumb(title: "Home", routePath: "/", isCurrent: false)
    # The section crumb ("Guide") and the current-page crumb ("Guide Home")
    # are two distinct labels pointing at the exact same routePath -- a
    # circular-looking nav shape that is intentional here, not a bug.
    check crumbs[1] == Breadcrumb(title: "Guide", routePath: "/guide", isCurrent: false)
    check crumbs[2] == Breadcrumb(title: "Guide Home", routePath: "/guide", isCurrent: true)
    check crumbs[1].routePath == crumbs[2].routePath

  test "buildNavigationViewModel does not fail or drop pages for a manifest containing a section index page":
    let pages = @[
      NavPage(routePath: "/guide", title: "Guide Home", section: "guide", order: 0, slug: "index"),
      NavPage(routePath: "/guide/dsl", title: "The ui DSL", section: "guide", order: 1, slug: "dsl"),
    ]
    let vm = buildNavigationViewModel(pages, "/guide")
    check vm.breadcrumbs[^1].routePath == "/guide"
    check vm.sidebar.sections.len == 1
    check vm.sidebar.sections[0].items.len == 2
    check vm.sidebar.sections[0].items[0].isActive # the index page itself, sorted first (slug "index" < "dsl"... )
      # sortNavPages orders by (section, order, slug); "index" (order 0) sorts before "dsl" (order 1) on order alone.

suite "docs authoring edge cases -- stale aliases (Tier 1, dual-target)":
  test "buildAliasMap silently drops an alias authored on content not bound to any manifest route":
    let entries = @[
      parseContentEntry("---\naliases: /old-draft\n---\n# Draft\n\nBody.", "guide/draft.md"),
    ]
    let contentPathToRoute = initTable[string, string]() # draft.md is not bound to any real route
    let aliasMap = buildAliasMap(entries, contentPathToRoute)
    check aliasMap.len == 0

  test "a stale alias whose old path collides with a live route's own canonical path never shadows it (real entries match first)":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
      newRedirectEntry("/guide/dsl", "/guide/other"), # a colliding, stale alias claiming a live path
    ])
    let match = matchRoute(manifest, "/guide/dsl")
    check match.entry.status == rsOk
    check match.entry.meta.contentPath == "guide/dsl.md"

  test "buildAliasRouteEntries never synthesizes a redirect for content the manifest carries no entry for":
    let manifest = newRouteManifest(@[]) # empty: no entry at all for the aliased content
    let loadEntry = proc(contentPath: string): ContentEntry =
      parseContentEntry("---\naliases: /old-draft\n---\n# Draft\n\nBody.", contentPath)
    let aliasEntries = buildAliasRouteEntries(manifest, loadEntry)
    check aliasEntries.len == 0
