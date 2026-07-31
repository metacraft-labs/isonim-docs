## Tier 2 (MockRenderer + SSR string) M4 search ViewModel rendering
## suite -- dual-target: both `nim c -r` and `nim js -r` must pass.
##
## Proves `src/components/search_view.nim` renders the search
## ViewModel from `src/core/search_vm.nim` (M4 deliverable 1)
## identically on the MockRenderer/browser tree side and the SSR
## string side: the search box itself, the ranked result list with the
## keyboard cursor's selection marked, and the distinct empty-state
## shape -- all as a pure function of a given `SearchViewModel`, with
## no live event simulation (that's `test_search_browser_mount.nim`'s
## job).

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/search_vm
import ../../src/components/search_view
import ./helpers/mock_tree

proc fixtureResults(): seq[SearchResult] =
  @[
    SearchResult(routePath: "/guide/dsl", title: "The ui DSL", section: "guide", score: 100),
    SearchResult(routePath: "/guide/signals-effects", title: "Signals & Effects", section: "guide", score: 40),
  ]

suite "docs search ViewModel rendering -- MockRenderer (Tier 2, dual-target)":
  test "renderSearchBox: an untouched (empty query) search box has no results and no empty-state message":
    let r = MockRenderer()
    let root = renderSearchBox[MockRenderer, MockNode](r, newSearchViewModel())
    check getAttribute(r, root, "class") == searchRegionClass
    check getAttribute(r, root, "role") == "search"

    let input = findByTag(root, "input")
    require input != nil
    check getAttribute(r, input, "id") == searchInputId
    check getAttribute(r, input, "value") == ""

    check findByTag(root, "ul") != nil
    check findAllByTag(root, "li").len == 0
    # no empty-state div for an untouched (empty-query) box
    check findWhere(root, proc(n: MockNode): bool = getAttribute(r, n, "class") == searchEmptyClass) == nil

  test "renderSearchBox: the input's value reflects the current query":
    let r = MockRenderer()
    let vm = setQuery(newSearchViewModel(), SearchIndex(), "dsl")
    let root = renderSearchBox[MockRenderer, MockNode](r, vm)
    let input = findByTag(root, "input")
    require input != nil
    check getAttribute(r, input, "value") == "dsl"

  test "renderSearchResultsContent: renders one <li> per result, each linking to its route":
    let r = MockRenderer()
    let vm = SearchViewModel(query: "dsl", results: fixtureResults(), cursor: 0)
    let root = renderSearchResultsContent[MockRenderer, MockNode](r, vm)
    check getAttribute(r, root, "class") == searchResultsClass

    let items = findAllByTag(root, "li")
    check items.len == 2
    let links = findAllByTag(root, "a")
    check links.len == 2
    check getAttribute(r, links[0], "href") == "/guide/dsl"
    check textContent(links[0]) == "The ui DSL"
    check getAttribute(r, links[1], "href") == "/guide/signals-effects"

    # WebFlow parity: section labels are HUMANIZED (raw key -> display label,
    # `_`/`-`/`/` -> space, title-cased) via `navigation_vm.humanizeKey`, so a
    # raw "guide" key renders as "Guide" (WebFlow shows "Usage Guide", not
    # "usage_guide").
    let sections = findAllByTag(root, "span")
    check sections.len == 2
    check textContent(sections[0]) == "Guide"

  test "renderSearchResultsContent: marks exactly the keyboard cursor's result as selected":
    let r = MockRenderer()
    let vm = SearchViewModel(query: "dsl", results: fixtureResults(), cursor: 1)
    let root = renderSearchResultsContent[MockRenderer, MockNode](r, vm)
    let items = findAllByTag(root, "li")
    check getAttribute(r, items[0], "class") == searchResultItemClass
    check getAttribute(r, items[0], "aria-selected") == ""
    check getAttribute(r, items[1], "class").contains(searchResultActiveClass)
    check getAttribute(r, items[1], "aria-selected") == "true"

  test "renderSearchResultsContent: a query with zero results renders the no-results message INSIDE the styled results container":
    let r = MockRenderer()
    let vm = SearchViewModel(query: "xyz", results: @[], cursor: -1)
    let root = renderSearchResultsContent[MockRenderer, MockNode](r, vm)
    # WebFlow parity: the "No results" message is an <li class="docs-search-empty">
    # nested INSIDE the `.docs-search-results` dropdown container (so it inherits
    # the container's border/shadow/positioning card -- WebFlow `.ct-result-empty`
    # inside `.ct-search-results`), NOT a bare floating sibling <div>.
    check getAttribute(r, root, "class") == searchResultsClass
    let empties = findAllByTag(root, "li")
    check empties.len == 1
    check getAttribute(r, empties[0], "class") == searchEmptyClass
    check textContent(empties[0]) == "No results for \"xyz\""

suite "docs search ViewModel rendering -- SSR string (Tier 2, dual-target)":
  test "renderSearchBoxHtml: an untouched search box serializes an empty input and an empty result list":
    let html = renderSearchBoxHtml(newSearchViewModel())
    check html.startsWith("<div class=\"" & searchRegionClass & "\" role=\"search\">")
    check html.contains("id=\"" & searchInputId & "\"")
    check html.contains("value=\"\"")
    check html.contains("<ul class=\"" & searchResultsClass & "\" role=\"listbox\"></ul>")
    check html.endsWith("</div>")

  test "renderSearchBoxHtml: the query is HTML-attribute-escaped into the input's value":
    let vm = SearchViewModel(query: "a & b\"")
    let html = renderSearchBoxHtml(vm)
    check html.contains("value=\"a &amp; b&quot;\"")

  test "renderSearchResultsContentHtml: renders results with the cursor's selection marked":
    let vm = SearchViewModel(query: "dsl", results: fixtureResults(), cursor: 0)
    let html = renderSearchResultsContentHtml(vm)
    check html.contains("aria-selected=\"true\"")
    check html.contains(searchResultActiveClass)
    check html.contains("<a class=\"" & searchResultLinkClass & "\" href=\"/guide/dsl\">The ui DSL</a>")
    # WebFlow parity: humanized section label ("guide" -> "Guide").
    check html.contains("<span class=\"" & searchResultSectionClass & "\">Guide</span>")

  test "renderSearchResultsContentHtml: an empty-result query nests the escaped no-results message inside the results container":
    let vm = SearchViewModel(query: "<script>", results: @[])
    let html = renderSearchResultsContentHtml(vm)
    # WebFlow parity: the escaped "No results" message is an <li> INSIDE the
    # `.docs-search-results` <ul> (styled dropdown card), not a bare <div>.
    check html == "<ul class=\"" & searchResultsClass & "\" role=\"listbox\">" &
      "<li class=\"" & searchEmptyClass & "\">No results for \"&lt;script&gt;\"</li></ul>"

  test "renderSearchResultsContentHtml: a raw multi-word section key is humanized into a display label":
    # WebFlow parity: "usage_guide" -> "Usage Guide" (title-cased, `_` -> space).
    let vm = SearchViewModel(query: "cli", results: @[
      SearchResult(routePath: "/usage_guide/cli", title: "CLI",
        section: "usage_guide", score: 100)])
    let html = renderSearchResultsContentHtml(vm)
    check html.contains("<span class=\"" & searchResultSectionClass & "\">Usage Guide</span>")
    check not html.contains(">usage_guide<")

  test "renderSearchBootstrapHtml: embeds the real search index as a stable-id JSON script tag":
    let index = SearchIndex(entries: @[
      SearchEntry(routePath: "/guide/dsl", title: "The ui DSL", section: "guide"),
    ])
    let html = renderSearchBootstrapHtml(index)
    check html.startsWith("<script id=\"" & searchBootstrapScriptId & "\" type=\"application/json\">")
    check html.contains("\"routePath\":\"/guide/dsl\"")
    check html.endsWith("</script>")
