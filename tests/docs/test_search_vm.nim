## Tier 1 (ViewModel / pure-helper) M4 search suite -- dual-target: both
## `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free half of `src/core/search_vm.nim`
## (M4 deliverable 1): tokenization, deterministic ranking (title over
## alias over heading over summary, exact over prefix), alias matching,
## the index builder's `RouteEntry`/`ContentEntry` pairing, and the
## keyboard-cursor ViewModel reducers. All of it is exercised through
## in-memory `SearchEntry`/`RouteEntry`/`ContentEntry` values -- no
## filesystem access anywhere -- so the exact same assertions hold on
## both targets.

import std/[unittest, strutils]
import ../../src/core/content
import ../../src/core/routes
import ../../src/core/markdown_vm
import ../../src/core/search_vm

suite "docs search ViewModel -- tokenize (Tier 1, dual-target)":
  test "tokenize lowercases and splits on non-alphanumeric runs":
    check tokenize("Signals & Effects!") == @["signals", "effects"]

  test "tokenize splits a route-path-shaped alias on '/' and '-'":
    check tokenize("/old-guide") == @["old", "guide"]

  test "tokenize of empty/whitespace-only text is an empty seq":
    check tokenize("").len == 0
    check tokenize("   ").len == 0

suite "docs search ViewModel -- scoreEntry ranking (Tier 1, dual-target)":
  let entry = SearchEntry(routePath: "/guide/dsl", title: "The ui DSL", section: "guide",
    summary: "An overview of the reactive ui DSL.",
    headings: @["Elements", "Signals"], aliases: @["/old-dsl-guide"])

  test "an empty query scores 0":
    check scoreEntry(entry, @[]) == 0

  test "a title exact match outranks a summary-only match":
    let titleHit = scoreEntry(entry, @["dsl"])
    let summaryOnly = SearchEntry(title: "Unrelated", summary: "mentions dsl in passing")
    check titleHit > scoreEntry(summaryOnly, @["dsl"])

  test "an alias match scores between a title match and a heading match":
    let aliasEntry = SearchEntry(title: "Renamed Page", aliases: @["/old-dsl-guide"])
    let headingEntry = SearchEntry(title: "Other Page", headings: @["dsl basics"])
    let titleEntry = SearchEntry(title: "dsl")
    let aliasScore = scoreEntry(aliasEntry, @["dsl"])
    let headingScore = scoreEntry(headingEntry, @["dsl"])
    let titleScore = scoreEntry(titleEntry, @["dsl"])
    check aliasScore > 0
    check titleScore > aliasScore
    check aliasScore > headingScore

  test "a prefix match scores lower than an exact match in the same field":
    let exact = SearchEntry(title: "dsl")
    let prefixOnly = SearchEntry(title: "dsleditor")
    check scoreEntry(exact, @["dsl"]) > scoreEntry(prefixOnly, @["dsl"])

  test "every query token must match something (AND semantics) or the entry scores 0":
    check scoreEntry(entry, @["dsl", "nonexistentword"]) == 0
    check scoreEntry(entry, @["dsl", "elements"]) > 0

suite "docs search ViewModel -- searchIndex ranking + determinism (Tier 1, dual-target)":
  let index = SearchIndex(entries: @[
    SearchEntry(routePath: "/guide/dsl", title: "The ui DSL", section: "guide",
      summary: "DSL overview.", headings: @["Elements"]),
    SearchEntry(routePath: "/guide/signals-effects", title: "Signals & Effects", section: "guide",
      summary: "Reactive signals and effects.", headings: @["Overview"]),
    SearchEntry(routePath: "/editor/overview", title: "Editor Overview", section: "editor",
      summary: "The editor also supports signals internally.", headings: @[]),
    SearchEntry(routePath: "/", title: "Welcome", section: "",
      summary: "Documentation home.", headings: @[]),
  ])

  test "searchIndex ranks a title match above a summary-only match for the same query":
    let results = searchIndex(index, "signals")
    check results.len == 2
    check results[0].routePath == "/guide/signals-effects" # title match
    check results[1].routePath == "/editor/overview"        # summary-only match

  test "searchIndex ranks a multi-term query by summed field-weighted score (pinned ordering)":
    ## M5 deliverable 2 (scoring): the KEEP-the-weighted-scorer decision
    ## (documented in `scoreEntry`'s docstring) is pinned here for a
    ## representative MULTI-TERM query -- the per-token field weights sum,
    ## so a page with BOTH terms in its title outranks one with a title +
    ## heading hit, which outranks one where both terms are summary-only.
    let multi = SearchIndex(entries: @[
      SearchEntry(routePath: "/guide/signals-effects", title: "Signals and Effects",
        section: "guide", summary: "Reactive programming primitives.", headings: @[]),
      SearchEntry(routePath: "/guide/effects", title: "Effects",
        section: "guide", summary: "Composed asynchronous work.", headings: @["Signals"]),
      SearchEntry(routePath: "/reference/api", title: "API Reference",
        section: "reference", summary: "Mentions signals and effects in passing.", headings: @[]),
    ])
    let results = searchIndex(multi, "signals effects")
    check results.len == 3
    check results[0].routePath == "/guide/signals-effects" # both terms in title
    check results[1].routePath == "/guide/effects"          # title + heading hit
    check results[2].routePath == "/reference/api"          # both terms summary-only
    check results[0].score > results[1].score
    check results[1].score > results[2].score

  test "searchIndex excludes entries that match no query token":
    let results = searchIndex(index, "signals")
    for r in results:
      check r.routePath != "/guide/dsl"
      check r.routePath != "/"

  test "searchIndex ties break deterministically by routePath ascending":
    let tied = SearchIndex(entries: @[
      SearchEntry(routePath: "/z-page", title: "Zeta"),
      SearchEntry(routePath: "/a-page", title: "Zeta"),
    ])
    let results = searchIndex(tied, "zeta")
    check results.len == 2
    check results[0].routePath == "/a-page"
    check results[1].routePath == "/z-page"

  test "searchIndex is stable across repeated calls with the same query":
    let first = searchIndex(index, "editor overview")
    let second = searchIndex(index, "editor overview")
    check first == second

  test "an empty query returns no results":
    check searchIndex(index, "").len == 0

  test "a query with no matches returns no results":
    check searchIndex(index, "xyznonexistent").len == 0

suite "docs search ViewModel -- buildSearchIndex / searchEntry (Tier 1, dual-target)":
  test "searchEntry indexes routing's own canonical path, headings, and front matter aliases":
    let routeEntry = newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(title: "Fallback"))
    let content = parseContentEntry("""---
aliases: /old-dsl
---
# The ui DSL

## Elements

Body text about elements.
""", "guide/dsl.md")
    let doc = parseMarkdownDoc(content.page.body, content.source.path)
    let entry = searchEntry(routeEntry, content, doc)
    check entry.routePath == "/guide/dsl"
    check entry.title == "The ui DSL"
    check entry.headings == @["Elements"]
    check entry.aliases == @["/old-dsl"]
    check entry.summary == "Body text about elements."

  test "searchEntry falls back to the route's own meta title when the content has none":
    let routeEntry = newRouteEntry("/guide/plain", pkMarkdown, meta = RouteMeta(title: "Fallback Title"))
    let content = parseContentEntry("", "guide/plain.md")
    let doc = parseMarkdownDoc(content.page.body, content.source.path)
    check searchEntry(routeEntry, content, doc).title == "Fallback Title"

  test "searchSummary prefers an explicit front matter description over the first paragraph":
    let content = parseContentEntry("""---
description: Explicit summary.
---
# Title

First paragraph text.
""", "page.md")
    let doc = parseMarkdownDoc(content.page.body, content.source.path)
    check searchSummary(content.front, doc) == "Explicit summary."

  test "buildSearchIndex pairs every non-redirect manifest entry with its own loaded content":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
      newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
      newRedirectEntry("/old-dsl", "/guide/dsl"),
    ])
    proc loader(contentPath: string): ContentEntry =
      case contentPath
      of "index.md": parseContentEntry("# Welcome", "index.md")
      of "guide/dsl.md": parseContentEntry("# The ui DSL\n\n## Elements\n\nBody.", "guide/dsl.md")
      else: raise newException(IOError, "unexpected path")
    let index = buildSearchIndex(manifest, loader)
    check index.entries.len == 2 # the redirect entry contributes no content of its own
    var routes: seq[string] = @[]
    for e in index.entries: routes.add e.routePath
    check "/guide/dsl" in routes
    check "/" in routes

  test "buildSearchIndex skips entries whose content fails to load, keeping the rest":
    let manifest = newRouteManifest(@[
      newRouteEntry("/a", pkMarkdown, meta = RouteMeta(contentPath: "a.md")),
      newRouteEntry("/missing", pkMarkdown, meta = RouteMeta(contentPath: "missing.md")),
    ])
    proc loader(contentPath: string): ContentEntry =
      if contentPath == "missing.md": raise newException(IOError, "no such file")
      parseContentEntry("# " & contentPath, contentPath)
    let index = buildSearchIndex(manifest, loader)
    check index.entries.len == 1
    check index.entries[0].routePath == "/a"

suite "docs search ViewModel -- keyboard cursor + query reducers (Tier 1, dual-target)":
  let index = SearchIndex(entries: @[
    SearchEntry(routePath: "/a", title: "Alpha DSL"),
    SearchEntry(routePath: "/b", title: "Beta DSL"),
    SearchEntry(routePath: "/c", title: "Gamma DSL"),
  ])

  test "setQuery ranks results and selects the top result by default":
    let vm = setQuery(newSearchViewModel(), index, "dsl")
    check vm.query == "dsl"
    check vm.results.len == 3
    check vm.cursor == 0
    check selectedResult(vm).routePath == "/a"

  test "setQuery selects nothing when there are no results":
    let vm = setQuery(newSearchViewModel(), index, "xyz")
    check vm.results.len == 0
    check vm.cursor == -1
    check selectedResult(vm).routePath == ""

  test "moveCursor advances the cursor forward and backward":
    var vm = setQuery(newSearchViewModel(), index, "dsl")
    vm = moveCursor(vm, 1)
    check vm.cursor == 1
    check selectedResult(vm).routePath == "/b"
    vm = moveCursor(vm, 1)
    check selectedResult(vm).routePath == "/c"
    vm = moveCursor(vm, -1)
    check selectedResult(vm).routePath == "/b"

  test "moveCursor clamps at the bounds instead of wrapping":
    var vm = setQuery(newSearchViewModel(), index, "dsl")
    vm = moveCursor(vm, -5)
    check vm.cursor == 0
    vm = moveCursor(vm, 50)
    check vm.cursor == 2
    vm = moveCursor(vm, 1)
    check vm.cursor == 2 # already at the end, stays put

  test "moveCursor on an empty result list is a no-op":
    let vm = moveCursor(newSearchViewModel(), 1)
    check vm.cursor == -1

  test "openSearch/closeSearch toggle isOpen, and closing resets query and results":
    var vm = openSearch(newSearchViewModel())
    check vm.isOpen == true
    vm = setQuery(vm, index, "dsl")
    vm = closeSearch(vm)
    check vm.isOpen == false
    check vm.query == ""
    check vm.results.len == 0
    check vm.cursor == -1

suite "docs search ViewModel -- JSON serialization (Tier 1, dual-target)":
  test "searchIndexToJson round-trips the indexed facts as valid-shaped JSON text":
    let index = SearchIndex(entries: @[
      SearchEntry(routePath: "/guide/dsl", title: "The \"ui\" DSL", section: "guide",
        summary: "A </script> guide.", headings: @["Elements"], aliases: @["/old-dsl"]),
    ])
    let json = searchIndexToJson(index)
    check json.startsWith("{\"entries\":[")
    check json.endsWith("]}")
    check json.contains("\"routePath\":\"/guide/dsl\"")
    check json.contains("\\\"ui\\\"")     # embedded quote escaped
    check json.contains("<\\/script>")    # "</" broken up so it can't close a real <script> tag
    check json.contains("\"headings\":[\"Elements\"]")
    check json.contains("\"aliases\":[\"/old-dsl\"]")

  test "searchIndexToJson of an empty index is an empty entries array":
    check searchIndexToJson(SearchIndex()) == "{\"entries\":[]}"
