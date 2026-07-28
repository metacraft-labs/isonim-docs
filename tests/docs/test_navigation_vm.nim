## Tier 1 (ViewModel / pure-helper) M3 navigation suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free half of `src/core/navigation_vm.nim`
## (M3 deliverable 1): sidebar tree construction (section grouping,
## reading order, section-expansion-state defaults), breadcrumb
## derivation, previous/next ordering, active-nav selection, and the
## `RouteEntry`/`ContentEntry` pairing (`navPage`/`buildNavPages`) that
## makes navigation follow routing's own canonical link target rather
## than forking a second one. All of it is exercised through in-memory
## `NavPage`/`RouteEntry`/`ContentEntry` values -- no filesystem access
## anywhere -- so the exact same assertions hold on both targets.

import std/unittest
import ../../src/core/content
import ../../src/core/routes
import ../../src/core/markdown_vm
import ../../src/core/navigation_vm

suite "docs navigation ViewModel -- humanizeKey (Tier 1, dual-target)":
  test "humanizeKey title-cases '-'-separated words":
    check humanizeKey("getting-started") == "Getting Started"
    check humanizeKey("guide") == "Guide"

  test "humanizeKey title-cases each '/'-separated segment too":
    check humanizeKey("guide/advanced") == "Guide Advanced"

  test "humanizeKey leaves the ungrouped top-level key (empty string) empty":
    check humanizeKey("") == ""

suite "docs navigation ViewModel -- navPage / buildNavPages (Tier 1, dual-target)":
  test "navPage prefers the RouteEntry's own canonical path over the content entry's derived route path":
    # `getting-started.md` lives at the content root, so content.nim's own
    # `deriveRoutePath` binds it to "/getting-started" -- but the real M0/M1
    # manifest binds this exact file to "/guide/getting-started". Navigation
    # must follow routing's answer, not fork a second one.
    let entry = newRouteEntry("/guide/getting-started", pkDoc,
      meta = RouteMeta(title: "Getting Started"))
    let content = parseContentEntry("# Getting Started\n\nBody.", "getting-started.md")
    check content.routePath == "/getting-started"
    let page = navPage(entry, content)
    check page.routePath == "/guide/getting-started"
    check page.title == "Getting Started"
    check page.section == ""
    check page.slug == "getting-started"

  test "navPage falls back to the route's own meta title when the content has none":
    let entry = newRouteEntry("/guide/plain", pkMarkdown, meta = RouteMeta(title: "Fallback Title"))
    let content = parseContentEntry("", "guide/plain.md")
    check content.page.title == ""
    check navPage(entry, content).title == "Fallback Title"

  test "buildNavPages pairs every manifest entry with its own loaded content, sorted by section/order/slug":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
      newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
      newRouteEntry("/guide/signals-effects", pkMarkdown, meta = RouteMeta(contentPath: "guide/signals-effects.md")),
    ])
    proc loader(contentPath: string): ContentEntry =
      case contentPath
      of "index.md": parseContentEntry("# Welcome", "index.md")
      of "guide/dsl.md": parseContentEntry("---\norder: 2\n---\n# The ui DSL", "guide/dsl.md")
      of "guide/signals-effects.md": parseContentEntry("---\norder: 1\n---\n# Signals & Effects", "guide/signals-effects.md")
      else: raise newException(IOError, "unexpected path")
    let pages = buildNavPages(manifest, loader)
    check pages.len == 3
    check pages[0].routePath == "/"
    check pages[1].routePath == "/guide/signals-effects"
    check pages[2].routePath == "/guide/dsl"

  test "buildNavPages skips entries whose content fails to load, keeping the rest of the real content graph":
    let manifest = newRouteManifest(@[
      newRouteEntry("/a", pkMarkdown, meta = RouteMeta(contentPath: "a.md")),
      newRouteEntry("/missing", pkMarkdown, meta = RouteMeta(contentPath: "missing.md")),
      newRouteEntry("/b", pkMarkdown, meta = RouteMeta(contentPath: "b.md")),
    ])
    proc loader(contentPath: string): ContentEntry =
      if contentPath == "missing.md":
        raise newException(IOError, "no such file")
      parseContentEntry("# " & contentPath, contentPath)
    let pages = buildNavPages(manifest, loader)
    check pages.len == 2
    check pages[0].routePath == "/a"
    check pages[1].routePath == "/b"

suite "docs navigation ViewModel -- buildSidebar (Tier 1, dual-target)":
  let pages = @[
    NavPage(routePath: "/guide/dsl", title: "The ui DSL", section: "guide", order: 2, slug: "dsl"),
    NavPage(routePath: "/editor/overview", title: "Editor Overview", section: "editor", order: 0, slug: "overview"),
    NavPage(routePath: "/", title: "Welcome", section: "", order: 0, slug: "index"),
    NavPage(routePath: "/guide/signals-effects", title: "Signals & Effects", section: "guide", order: 1, slug: "signals-effects"),
    NavPage(routePath: "/getting-started", title: "Getting Started", section: "", order: 1, slug: "getting-started"),
  ]

  test "buildSidebar groups pages into sections, sorted (section, order, slug), regardless of input order":
    let sidebar = buildSidebar(pages, "/guide/dsl")
    check sidebar.sections.len == 3
    check sidebar.sections[0].key == "" # root sorts before "editor"/"guide" alphabetically
    check sidebar.sections[0].title == ""
    check sidebar.sections[0].items.len == 2
    check sidebar.sections[0].items[0].title == "Welcome"
    check sidebar.sections[0].items[1].title == "Getting Started"

    check sidebar.sections[1].key == "editor"
    check sidebar.sections[1].title == "Editor"
    check sidebar.sections[1].items.len == 1

    check sidebar.sections[2].key == "guide"
    check sidebar.sections[2].title == "Guide"
    check sidebar.sections[2].items.len == 2
    # order 1 (signals-effects) before order 2 (dsl).
    check sidebar.sections[2].items[0].title == "Signals & Effects"
    check sidebar.sections[2].items[1].title == "The ui DSL"

  test "buildSidebar marks exactly the active page's item as active":
    let sidebar = buildSidebar(pages, "/guide/dsl")
    check sidebar.sections[2].items[1].isActive == true
    check sidebar.sections[2].items[0].isActive == false
    check sidebar.sections[0].items[0].isActive == false

  test "buildSidebar expands the ungrouped top-level section and the section containing the active page":
    let sidebar = buildSidebar(pages, "/guide/dsl")
    check sidebar.sections[0].isExpanded == true # ungrouped top level, always open
    check sidebar.sections[1].isExpanded == false # "editor" has no active page
    check sidebar.sections[2].isExpanded == true # "guide" contains "/guide/dsl"

  test "buildSidebar collapses every non-root section when there's no active page":
    let sidebar = buildSidebar(pages, "/nowhere")
    check sidebar.sections[0].isExpanded == true
    check sidebar.sections[1].isExpanded == false
    check sidebar.sections[2].isExpanded == false

suite "docs navigation ViewModel -- buildBreadcrumbs (Tier 1, dual-target)":
  let pages = @[
    NavPage(routePath: "/", title: "Welcome", section: "", order: 0, slug: "index"),
    NavPage(routePath: "/guide/dsl", title: "The ui DSL", section: "guide", order: 1, slug: "dsl"),
  ]

  test "buildBreadcrumbs for the site root is a single, current Home crumb":
    let crumbs = buildBreadcrumbs(pages, "/")
    check crumbs.len == 1
    check crumbs[0].title == "Home"
    check crumbs[0].routePath == "/"
    check crumbs[0].isCurrent == true

  test "buildBreadcrumbs for a sectioned page is Home > Section > Page":
    let crumbs = buildBreadcrumbs(pages, "/guide/dsl")
    check crumbs.len == 3
    check crumbs[0] == Breadcrumb(title: "Home", routePath: "/", isCurrent: false)
    check crumbs[1] == Breadcrumb(title: "Guide", routePath: "/guide", isCurrent: false)
    check crumbs[2] == Breadcrumb(title: "The ui DSL", routePath: "/guide/dsl", isCurrent: true)

  test "buildBreadcrumbs falls back to a single, non-current Home crumb for an unresolvable active route":
    let crumbs = buildBreadcrumbs(pages, "/does-not-exist")
    check crumbs.len == 1
    check crumbs[0] == Breadcrumb(title: "Home", routePath: "/", isCurrent: false)

suite "docs navigation ViewModel -- buildAdjacentPages (Tier 1, dual-target)":
  let pages = @[
    NavPage(routePath: "/guide/dsl", title: "The ui DSL", section: "guide", order: 2, slug: "dsl"),
    NavPage(routePath: "/editor/overview", title: "Editor Overview", section: "editor", order: 0, slug: "overview"),
    NavPage(routePath: "/", title: "Welcome", section: "", order: 0, slug: "index"),
    NavPage(routePath: "/guide/signals-effects", title: "Signals & Effects", section: "guide", order: 1, slug: "signals-effects"),
    NavPage(routePath: "/getting-started", title: "Getting Started", section: "", order: 1, slug: "getting-started"),
  ]
  # Flattened reading order: "/" , "/getting-started", "/editor/overview",
  # "/guide/signals-effects", "/guide/dsl".

  test "buildAdjacentPages returns both neighbors for a page in the middle of the reading order":
    let (previous, next) = buildAdjacentPages(pages, "/editor/overview")
    check previous == AdjacentPage(title: "Getting Started", routePath: "/getting-started")
    check next == AdjacentPage(title: "Signals & Effects", routePath: "/guide/signals-effects")

  test "buildAdjacentPages has no previous page at the start of the reading order":
    let (previous, next) = buildAdjacentPages(pages, "/")
    check previous == AdjacentPage()
    check next == AdjacentPage(title: "Getting Started", routePath: "/getting-started")

  test "buildAdjacentPages has no next page at the end of the reading order":
    let (previous, next) = buildAdjacentPages(pages, "/guide/dsl")
    check previous == AdjacentPage(title: "Signals & Effects", routePath: "/guide/signals-effects")
    check next == AdjacentPage()

  test "buildAdjacentPages returns no neighbors at all for an unresolvable active route":
    let (previous, next) = buildAdjacentPages(pages, "/nowhere")
    check previous == AdjacentPage()
    check next == AdjacentPage()

suite "docs navigation ViewModel -- buildNavigationViewModel (Tier 1, dual-target)":
  test "buildNavigationViewModel combines sidebar, breadcrumbs, adjacent pages, and the passed-through page TOC":
    let pages = @[
      NavPage(routePath: "/", title: "Welcome", section: "", order: 0, slug: "index"),
      NavPage(routePath: "/guide/dsl", title: "The ui DSL", section: "guide", order: 0, slug: "dsl"),
    ]
    let toc = @[HeadingNode(level: 2, text: "Overview", id: "overview")]
    let vm = buildNavigationViewModel(pages, "/guide/dsl", toc)
    check vm.sidebar == buildSidebar(pages, "/guide/dsl")
    check vm.breadcrumbs == buildBreadcrumbs(pages, "/guide/dsl")
    let (previous, next) = buildAdjacentPages(pages, "/guide/dsl")
    check vm.previous == previous
    check vm.next == next
    check vm.toc == toc

  test "buildNavigationViewModel defaults the page TOC to empty when not given one":
    let pages = @[NavPage(routePath: "/", title: "Welcome")]
    check buildNavigationViewModel(pages, "/").toc.len == 0
