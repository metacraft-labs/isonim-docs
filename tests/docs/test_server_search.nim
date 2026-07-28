## Tier 1 (ViewModel / pure-helper) M12 deliverable-2 suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## Proves the server-side search integration (`src/core/server_search.nim`)
## and its config toggle, entirely through in-memory values -- no
## filesystem, no real network, no real timers -- so the exact same
## assertions hold on both backends:
##
##  * the config TOGGLE (`dispatchFor`): server mode routes queries to the
##    API, and toggled OFF (or a blank endpoint) the client-index path is
##    what runs -- the deliverable's "when toggled off, the existing client
##    index path must still work";
##  * the pluggable BACKEND interface exercised through the MOCK backend
##    (`newMockBackend`), plus the proxy + sqlite adapters' contracts;
##  * DEBOUNCING (`Debouncer`): a burst of keystrokes fires exactly one
##    query -- the last;
##  * the request/response WIRE (URL build, query-string parse, results
##    JSON round-trip) the client and server agree on;
##  * the SSR overlay carrying the resolved mode/endpoint onto the page so
##    the client can read the toggle without inline config.

import std/[unittest, strutils]
import ../../src/core/search_vm
import ../../src/core/server_search
import ../../src/core/config
import ../../src/components/search_view

# A small, fixed corpus every mock/index/sqlite backend below ranks, so
# the tests assert ordering by hand exactly like `test_search_vm.nim` does.
let corpus = SearchIndex(entries: @[
  SearchEntry(routePath: "/guide/signals-effects", title: "Signals and Effects",
    section: "guide", summary: "Reactive programming primitives.", headings: @[]),
  SearchEntry(routePath: "/guide/effects", title: "Effects",
    section: "guide", summary: "Composed asynchronous work.", headings: @["Signals"]),
  SearchEntry(routePath: "/reference/api", title: "API Reference",
    section: "reference", summary: "Mentions signals and effects in passing.", headings: @[]),
])

suite "server search -- config toggle / dispatch (Tier 1, dual-target)":
  test "the framework default is the client-index path (server toggled off)":
    check defaultServerSearchConfig().mode == smClientIndex
    check dispatchFor(defaultServerSearchConfig()) == sdClientIndex

  test "flipping mode to smServerApi routes queries to the server API":
    let cfg = ServerSearchConfig(mode: smServerApi, endpoint: "/api/search", debounceMs: 200)
    check dispatchFor(cfg) == sdServerApi

  test "server mode with a blank endpoint safely falls back to the client path":
    let cfg = ServerSearchConfig(mode: smServerApi, endpoint: "", debounceMs: 200)
    check dispatchFor(cfg) == sdClientIndex

  test "toggled off, the existing client index path still ranks locally":
    ## The deliverable's explicit "when toggled off, the client index path
    ## must still work": with the client-index dispatch, ranking is the
    ## unchanged `search_vm.searchIndex` over the local index -- no backend,
    ## no network involved at all.
    check dispatchFor(defaultServerSearchConfig()) == sdClientIndex
    let results = searchIndex(corpus, "signals effects")
    check results.len == 3
    check results[0].routePath == "/guide/signals-effects"

suite "server search -- mock backend + endpoint (Tier 1, dual-target)":
  let backend = newMockBackend(corpus)

  test "the mock backend is tagged sbkMock (not a real sqlite/proxy)":
    check backend.kind == sbkMock

  test "a query hits the mock backend and returns the ranked results":
    let results = query(backend, "signals effects")
    check results.len == 3
    check results[0].routePath == "/guide/signals-effects" # both terms in title
    check results[1].routePath == "/guide/effects"          # title + heading
    check results[2].routePath == "/reference/api"          # summary-only
    check results[0].score > results[1].score

  test "the mock backend ranks identically to the client-index path (parity)":
    ## Server mode must not change relevance -- flipping the toggle moves
    ## WHERE ranking happens, not the order it produces.
    check query(backend, "signals effects") == searchIndex(corpus, "signals effects")

  test "limit caps the number of results the backend returns":
    check query(backend, "signals effects", limit = 1).len == 1
    check query(backend, "signals effects", limit = 1)[0].routePath == "/guide/signals-effects"

  test "handleSearchRequest parses the query string, ranks, and serializes":
    let body = handleSearchRequest(backend, "?q=signals%20effects&limit=2")
    check body.startsWith("{\"results\":[")
    let parsed = parseSearchResultsJson(body)
    check parsed.len == 2
    check parsed[0].routePath == "/guide/signals-effects"

  test "handleSearchRequest on a blank query returns an empty result set":
    check handleSearchRequest(backend, "?q=") == "{\"results\":[]}"
    check handleSearchRequest(backend, "") == "{\"results\":[]}"

  test "the zero-value backend degrades to no results instead of crashing":
    check query(SearchBackend(), "signals").len == 0

suite "server search -- pluggable proxy + sqlite backends (Tier 1, dual-target)":
  test "the proxy backend forwards the query and parses the upstream JSON":
    var seenQuery = ""
    let upstream = newProxyBackend(proc(q: string; limit: int): string =
      seenQuery = q
      searchResultsToJson(@[SearchResult(routePath: "/x", title: "X", score: 42)]))
    let results = query(upstream, "hello")
    check upstream.kind == sbkProxy
    check seenQuery == "hello"
    check results.len == 1
    check results[0].routePath == "/x"
    check results[0].score == 42

  test "a proxy backend whose upstream returns garbage degrades to no results":
    let broken = newProxyBackend(proc(q: string; limit: int): string = "not json{")
    check query(broken, "hello").len == 0

  test "the sqlite backend adapts rows a real FTS query would return":
    ## The interface's SQLite contract: `loadRows` (the consumer's real
    ## `std/db_sqlite` SELECT) yields rows; the backend maps them to ranked
    ## results and is tagged `sbkSqlite`. Asserted against a fake row loader
    ## so the framework needs no sqlite dependency (same "tested shim whose
    ## contract is asserted" standard the nginx adapter used).
    var seenLimit = 0
    let db = newSqliteBackend(proc(q: string; limit: int): seq[SearchRow] =
      seenLimit = limit
      @[SearchRow(routePath: "/db/hit", title: "DB Hit", section: "s",
        summary: "from sqlite", score: 7)])
    let results = query(db, "anything", limit = 5)
    check db.kind == sbkSqlite
    check seenLimit == 5
    check results.len == 1
    check results[0].routePath == "/db/hit"
    check results[0].summary == "from sqlite"
    check results[0].score == 7

suite "server search -- debounce coalescing (Tier 1, dual-target)":
  test "a burst of keystrokes fires exactly the last query, not the earlier ones":
    var d = newDebouncer(200)
    let t1 = onInput(d) # user types "s"
    let t2 = onInput(d) # "si"
    let t3 = onInput(d) # "sig"
    check shouldFire(d, t1) == false # superseded
    check shouldFire(d, t2) == false # superseded
    check shouldFire(d, t3) == true  # the latest -- the only one that fires

  test "a settled keystroke (no newer input) fires":
    var d = newDebouncer()
    let t = onInput(d)
    check shouldFire(d, t) == true

  test "the debouncer carries the configured interval for the client's timer":
    check newDebouncer(350).intervalMs == 350
    check newDebouncer().intervalMs == defaultSearchDebounceMs
    check newDebouncer(-5).intervalMs == 0 # clamped, never a negative delay

suite "server search -- request/response wire (Tier 1, dual-target)":
  test "buildSearchRequestUrl percent-encodes the query and round-trips through the parser":
    let url = buildSearchRequestUrl("/api/search", "signals & effects", limit = 5)
    check url.startsWith("/api/search?q=")
    check url.contains("%20") # space encoded
    check url.contains("%26") # '&' encoded so it can't split the query string
    check url.contains("&limit=5")
    let qs = url[url.find('?') .. ^1]
    let params = parseSearchQueryParams(qs)
    check params.q == "signals & effects"
    check params.limit == 5

  test "parseSearchQueryParams tolerates a missing/blank/non-numeric limit":
    check parseSearchQueryParams("?q=hello").limit == defaultSearchLimit
    check parseSearchQueryParams("q=hello").q == "hello" # leading '?' optional
    check parseSearchQueryParams("?q=hi&limit=abc").limit == defaultSearchLimit
    check parseSearchQueryParams("?q=a+b").q == "a b" # '+' decodes to space

  test "the results JSON round-trips (and escapes a </script>-bearing title)":
    let results = @[
      SearchResult(routePath: "/guide/dsl", title: "The </script> DSL",
        section: "guide", summary: "A \"quoted\" summary.", score: 90),
      SearchResult(routePath: "/other", title: "Other", section: "", summary: "", score: 10),
    ]
    let json = searchResultsToJson(results)
    check json.contains("<\\/script>") # broken so it can't close a real <script>
    check parseSearchResultsJson(json) == results

  test "parseSearchResultsJson tolerates a malformed/empty payload":
    check parseSearchResultsJson("").len == 0
    check parseSearchResultsJson("{}").len == 0
    check parseSearchResultsJson("{\"results\":\"nope\"}").len == 0

suite "server search -- ViewModel + SSR toggle integration (Tier 1, dual-target)":
  test "setResultsFromServer installs already-ranked results and selects the top":
    let ranked = query(newMockBackend(corpus), "signals effects")
    let vm = setResultsFromServer(newSearchViewModel(), "signals effects", ranked)
    check vm.query == "signals effects"
    check vm.results == ranked
    check vm.cursor == 0
    check selectedResult(vm).routePath == "/guide/signals-effects"

  test "setResultsFromServer selects nothing for an empty result list":
    let vm = setResultsFromServer(newSearchViewModel(), "xyz", @[])
    check vm.cursor == -1
    check selectedResult(vm).routePath == ""

  test "the SSR overlay emits client mode with NO endpoint attr by default":
    let html = renderSearchOverlayHtml(SearchViewModel())
    check html.contains(searchModeAttr & "=\"client\"")
    check not html.contains(searchEndpointAttr)

  test "the SSR overlay emits the server mode + endpoint + debounce when toggled on":
    let cfg = ServerSearchConfig(mode: smServerApi, endpoint: "/api/search", debounceMs: 300)
    let html = renderSearchOverlayHtml(SearchViewModel(), search = cfg)
    check html.contains(searchModeAttr & "=\"server\"")
    check html.contains(searchEndpointAttr & "=\"/api/search\"")
    check html.contains(searchDebounceAttr & "=\"300\"")
