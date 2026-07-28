## Tier 2 (MockRenderer + SSR string) M3 navigation ViewModel rendering
## suite -- dual-target: both `nim c -r` and `nim js -r` must pass.
##
## Proves `src/components/navigation_view.nim` renders the navigation
## ViewModel from `src/core/navigation_vm.nim` (M3 deliverable 1)
## identically on the MockRenderer/browser tree side and the SSR string
## side: breadcrumb links, the sidebar tree (section grouping, active-nav
## selection), the page table of contents, and previous/next pagination
## links.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/core/navigation_vm
import ../../src/components/navigation_view
import ./helpers/mock_tree

proc fixtureVm(): NavigationViewModel =
  let pages = @[
    NavPage(routePath: "/", title: "Welcome", section: "", order: 0, slug: "index"),
    NavPage(routePath: "/guide/signals-effects", title: "Signals & Effects",
      section: "guide", order: 0, slug: "signals-effects"),
    NavPage(routePath: "/guide/dsl", title: "The ui DSL", section: "guide", order: 1, slug: "dsl"),
  ]
  let toc = @[
    HeadingNode(level: 2, text: "Overview", id: "overview", children: @[
      HeadingNode(level: 3, text: "Basics", id: "basics"),
    ]),
  ]
  buildNavigationViewModel(pages, "/guide/dsl", toc)

suite "docs navigation ViewModel rendering -- MockRenderer (Tier 2, dual-target)":
  test "renderNavigation: the breadcrumb trail renders Home > Section > current page, current page as a non-link span":
    let r = MockRenderer()
    let root = renderNavigation[MockRenderer, MockNode](r, fixtureVm())
    check getAttribute(r, root, "class") == navRegionClass

    let breadcrumbNav = findByTag(root, "nav")
    require breadcrumbNav != nil
    check getAttribute(r, breadcrumbNav, "aria-label") == "breadcrumbs"

    let links = findAllByTag(breadcrumbNav, "a")
    check links.len == 2
    check getAttribute(r, links[0], "href") == "/"
    check textContent(links[0]) == "Home"
    check getAttribute(r, links[1], "href") == "/guide"
    check textContent(links[1]) == "Guide"

    let current = findByTag(breadcrumbNav, "span")
    require current != nil
    check getAttribute(r, current, "aria-current") == "page"
    check textContent(current) == "The ui DSL"

  test "renderNavigation: the sidebar groups pages by section and marks the active page":
    let r = MockRenderer()
    let root = renderNavigation[MockRenderer, MockNode](r, fixtureVm())

    let navs = findAllByTag(root, "nav")
    var sidebarNav: MockNode = nil
    for n in navs:
      if getAttribute(r, n, "aria-label") == "sidebar": sidebarNav = n
    require sidebarNav != nil

    let sectionTitles = findAllByTag(sidebarNav, "button")
    check sectionTitles.len == 1 # only "guide" has a non-empty title; "" stays untitled
    check textContent(sectionTitles[0]) == "Guide"
    check getAttribute(r, sectionTitles[0], "aria-expanded") == "true" # contains the active page

    let items = findAllByTag(sidebarNav, "li")
    check items.len == 3
    let dslLink = findAllByTag(sidebarNav, "a")[2]
    check textContent(dslLink) == "The ui DSL"
    check getAttribute(r, dslLink, "aria-current") == "page"
    check getAttribute(r, dslLink.parent, "class").contains("docs-nav-item-active")

  test "renderNavigation: the table of contents renders nested anchors matching the page's own heading IDs":
    let r = MockRenderer()
    let root = renderNavigation[MockRenderer, MockNode](r, fixtureVm())

    let navs = findAllByTag(root, "nav")
    var tocNav: MockNode = nil
    for n in navs:
      if getAttribute(r, n, "aria-label") == "table of contents": tocNav = n
    require tocNav != nil

    let anchors = findAllByTag(tocNav, "a")
    check anchors.len == 2
    check getAttribute(r, anchors[0], "href") == "#overview"
    check textContent(anchors[0]) == "Overview"
    check getAttribute(r, anchors[1], "href") == "#basics"
    check textContent(anchors[1]) == "Basics"

  test "renderNavigation: the nav region carries NO pagination (it moved to the bottom of .docs-main)":
    # The prev/next pagination is deliberately no longer part of the nav
    # region -- each page frame renders it via `renderAdjacent` as a sibling
    # after `.docs-main`, so it reads at the end of the article, not above the
    # H1, and is never trapped in the mobile off-canvas nav drawer.
    let r = MockRenderer()
    let root = renderNavigation[MockRenderer, MockNode](r, fixtureVm())
    for n in findAllByTag(root, "nav"):
      check getAttribute(r, n, "aria-label") != "pagination"

  test "renderAdjacent: pagination renders only the sides that have a neighbor":
    let r = MockRenderer()
    let vm = fixtureVm()
    let adjacentNav = renderAdjacent[MockRenderer, MockNode](r, vm.previous, vm.next)
    check getAttribute(r, adjacentNav, "class") == adjacentNavClass
    check getAttribute(r, adjacentNav, "aria-label") == "pagination"

    # "/guide/dsl" is the last page in reading order: a previous link, no next link.
    let links = findAllByTag(adjacentNav, "a")
    check links.len == 1
    check getAttribute(r, links[0], "class") == prevLinkClass
    check textContent(links[0]) == "Signals & Effects"

suite "docs navigation ViewModel rendering -- SSR string (Tier 2, dual-target)":
  test "renderNavigationHtml: breadcrumbs, sidebar, and table of contents serialize (pagination is NOT part of the nav region)":
    let html = renderNavigationHtml(fixtureVm())
    check html.startsWith("<div class=\"" & navRegionClass & "\">")
    check html.contains("aria-label=\"breadcrumbs\"")
    check html.contains("<a href=\"/\">Home</a>")
    check html.contains("<a href=\"/guide\">Guide</a>")
    check html.contains("<span class=\"" & breadcrumbCurrentClass & "\" aria-current=\"page\">The ui DSL</span>")
    check html.contains("aria-label=\"sidebar\"")
    check html.contains("<button type=\"button\" class=\"" & sidebarSectionTitleClass &
      "\" aria-expanded=\"true\">Guide</button>")
    check html.contains("aria-label=\"table of contents\"")
    check html.contains("<a href=\"#overview\">Overview</a>")
    check html.contains("<a href=\"#basics\">Basics</a>")
    # The pagination moved out of the nav region (it now renders after
    # `.docs-main`), so the nav region must NOT serialize it.
    check not html.contains("aria-label=\"pagination\"")
    check html.endsWith("</div>")

  test "renderAdjacentHtml: previous/next pagination serializes on its own (rendered after .docs-main)":
    let vm = fixtureVm()
    let html = renderAdjacentHtml(vm.previous, vm.next)
    check html.startsWith("<nav class=\"" & adjacentNavClass & "\" aria-label=\"pagination\">")
    check html.contains("class=\"" & prevLinkClass & "\"")
    check html.contains(">Signals &amp; Effects<")
    check html.endsWith("</nav>")

  test "renderNavigationHtml: link targets and titles are HTML-escaped":
    let pages = @[NavPage(routePath: "/a&b", title: "A & B", section: "", order: 0, slug: "a-b")]
    let html = renderNavigationHtml(buildNavigationViewModel(pages, "/nowhere"))
    check html.contains("A &amp; B")
    check html.contains("href=\"/a&amp;b\"")
