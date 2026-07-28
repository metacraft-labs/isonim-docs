## isonim-docs Layer 3 — server-side search integration (M12 deliverable 2).
##
## The client search box has always ranked a `search_vm.SearchIndex` in
## the browser (the "client index" path -- M4/M5). For a corpus too large
## to ship to every visitor, a site can instead flip
## `config.DocsConfig.search.mode` to `smServerApi`, which routes each
## (debounced) query to a server endpoint that runs the ranking against a
## pluggable backend (a SQLite FTS table, a proxied upstream search
## service, or -- under test -- an in-memory mock). This module holds the
## three filesystem-free, dual-target pieces that switch make honest:
##
##  1. The **backend interface** (`SearchBackend`) and its constructors --
##     `newIndexBackend` (used as the test MOCK and as a legitimate
##     in-memory backend), `newProxyBackend` (forwards to an upstream JSON
##     search service), and `newSqliteBackend` (adapts rows a real
##     `std/db_sqlite` FTS query returns -- the DB handle + SQL stay a
##     consumer concern so the framework carries no hard sqlite dep).
##  2. The **server endpoint** glue: `parseSearchQueryParams` (read
##     `q`/`limit` off a `?...` query string), `handleSearchRequest` (run
##     the backend, serialize), and the `results` wire JSON both the
##     endpoint emits and the client parses -- deliberately a DIFFERENT
##     shape from `searchIndexToJson`'s `{"entries":[...]}` (that is the
##     raw index a client ranks; this is already-ranked `{"results":[...]}`
##     the client renders as-is).
##  3. The **client dispatch**: `dispatchFor` (client-index vs server-API,
##     off the config toggle) plus a `Debouncer` -- a pure,
##     timestamp-free, generation-token coalescer the JS mount drives with
##     a real `setTimeout`, but whose "fire only the latest keystroke"
##     logic is unit-testable on both backends.
##
## Everything here is pure/data + closures (no platform imports), so the
## whole module -- backend dispatch, debounce coalescing, JSON round-trip
## -- runs identically under `nim c` and `nim js`, exactly like
## `search_vm.nim` it builds on. `test_server_search.nim` exercises both
## toggle states against a mock backend on both targets.

import std/[strutils, json]
import ./search_vm
import ./config

export SearchMode, ServerSearchConfig, defaultServerSearchConfig,
  defaultSearchEndpoint, defaultSearchDebounceMs

const
  defaultSearchLimit* = 20
    ## The default cap on results a server search returns -- a bounded page
    ## of the ranked list, not the whole corpus, so a broad query can't ask
    ## the backend (or the wire) to materialize thousands of rows.

# --- the results wire JSON --------------------------------------------------
#
# The server returns ALREADY-RANKED results, so its payload is a
# `{"results":[{routePath,title,section,summary,score}, ...]}` list --
# distinct from `search_vm.searchIndexToJson`'s `{"entries":[...]}` raw
# index (which the CLIENT ranks). Reuses `search_vm.escapeJsonString` so
# the two paths escape identically (embedded quotes, `</script>`, control
# chars) and a title/summary can never break the JSON or a `<script>`.

proc searchResultToJson*(res: SearchResult): string =
  "{\"routePath\":" & escapeJsonString(res.routePath) &
    ",\"title\":" & escapeJsonString(res.title) &
    ",\"section\":" & escapeJsonString(res.section) &
    ",\"summary\":" & escapeJsonString(res.summary) &
    ",\"score\":" & $res.score & "}"

proc searchResultsToJson*(results: seq[SearchResult]): string =
  ## The canonical server-response serialization: the ranked results
  ## wrapped in a `{"results":[...]}` envelope (an object, not a bare
  ## array, so the response can later carry sibling fields -- a total
  ## count, a "did you mean" -- without a breaking shape change).
  result = "{\"results\":["
  for i, res in results:
    if i > 0: result.add ","
    result.add searchResultToJson(res)
  result.add "]}"

proc parseSearchResultsJson*(text: string): seq[SearchResult] =
  ## The client counterpart to `searchResultsToJson`: parses a server
  ## response back into `seq[SearchResult]`. A malformed / empty / wrong-
  ## shaped payload yields an empty seq rather than raising -- a broken
  ## backend must degrade server search to "no results", never crash the
  ## page (mirrors `search_vm.parseSearchIndexJson`'s own tolerance).
  ## Iterated element-by-element (not `std/json`'s `to`) so it stays
  ## correct on both the C and JS backends.
  var root: JsonNode
  try:
    root = parseJson(text)
  except:
    ## A bare `except` (not `CatchableError`) on purpose: on the JS backend
    ## `parseJson` delegates to `JSON.parse`, whose failure surfaces as a
    ## FOREIGN JS exception a typed `except CatchableError` would let escape
    ## (and crash the page) -- the very "degrade to no results, never crash"
    ## contract this proc exists to keep. On the C backend it still catches
    ## the `JsonParsingError` the same way.
    return @[]
  if root.kind != JObject or not root.hasKey("results"):
    return @[]
  let results = root["results"]
  if results.kind != JArray:
    return @[]
  for r in results:
    if r.kind != JObject: continue
    proc str(key: string): string =
      if r.hasKey(key) and r[key].kind == JString: r[key].getStr else: ""
    var score = 0
    if r.hasKey("score"):
      # Tolerate either JInt or JFloat for the numeric score -- the JS
      # backend's `parseJson` can surface a whole number as a float.
      case r["score"].kind
      of JInt: score = int(r["score"].getInt)
      of JFloat: score = int(r["score"].getFloat)
      else: discard
    result.add SearchResult(routePath: str("routePath"), title: str("title"),
      section: str("section"), summary: str("summary"), score: score)

# --- the pluggable backend interface ---------------------------------------

type
  SearchBackendKind* = enum
    ## Which concrete backend a `SearchBackend` wraps -- carried alongside
    ## the closure purely so a server, a test, or an ops dashboard can
    ## report/branch on the active backend without unwrapping it. The
    ## framework ships `sbkMock`/`sbkIndex`/`sbkProxy`/`sbkSqlite`; a
    ## consumer's exotic backend can reuse `sbkProxy` or extend this enum.
    sbkMock = "mock"
    sbkIndex = "index"
    sbkProxy = "proxy"
    sbkSqlite = "sqlite"

  SearchQueryHandler* = proc(query: string; limit: int): seq[SearchResult] {.closure.}
    ## The one operation every backend implements: rank `query` and return
    ## at most `limit` results, best first. A closure (not a method on a
    ## `ref` hierarchy) so the interface stays dual-target-safe and a
    ## backend can be built inline from any data source -- exactly the
    ## injected-closure seam `search_vm.buildSearchIndex`'s own `loadEntry`
    ## parameter already uses.

  SearchBackend* = object
    ## A pluggable server search backend: its `kind` tag plus the ranking
    ## closure. Constructed by one of the `new*Backend` procs below; run
    ## via `query` / `handleSearchRequest`.
    kind*: SearchBackendKind
    handle*: SearchQueryHandler

  SearchRow* = object
    ## One row a real SQLite FTS query (or any tabular store) yields, in
    ## the columns a search result needs -- the adapter boundary
    ## `newSqliteBackend` maps into `SearchResult`. Deliberately a plain
    ## flat record (no DB types) so the framework depends on no database
    ## library: the consumer runs the SELECT and hands rows back.
    routePath*: string
    title*: string
    section*: string
    summary*: string
    score*: int

proc query*(backend: SearchBackend; q: string; limit: int = defaultSearchLimit): seq[SearchResult] =
  ## Runs `q` through `backend`, tolerating an unset handler (the zero-
  ## value `SearchBackend`) as "no results" rather than a nil-call crash --
  ## so a mis-wired server degrades to empty search, never a 500.
  if backend.handle == nil: return @[]
  backend.handle(q, limit)

proc newIndexBackend*(index: SearchIndex; kind = sbkIndex): SearchBackend =
  ## A backend that ranks an in-memory `search_vm.SearchIndex` with the
  ## exact same `searchIndex` scorer the client-index path uses -- so a
  ## site flipping to server mode gets identical ranking, just computed
  ## server-side. This is BOTH the test MOCK (`newMockBackend`, `kind =
  ## sbkMock`) and a legitimate small-corpus production backend (`kind =
  ## sbkIndex`): the corpus is loaded once at server start rather than
  ## shipped to every client.
  result.kind = kind
  let idx = index
  result.handle = proc(q: string; limit: int): seq[SearchResult] =
    let ranked = searchIndex(idx, q)
    if limit >= 0 and ranked.len > limit: ranked[0 ..< limit] else: ranked

proc newMockBackend*(index: SearchIndex): SearchBackend =
  ## The test double M12 deliverable 2 requires "a mock backend under
  ## test": an `newIndexBackend` tagged `sbkMock`, so a test can assert it
  ## was the mock (not a real SQLite/proxy) that answered while exercising
  ## the exact same ranking + wire path a real backend takes.
  newIndexBackend(index, sbkMock)

proc newProxyBackend*(forward: proc(query: string; limit: int): string {.closure.}): SearchBackend =
  ## A backend that PROXIES to an upstream JSON search service: `forward`
  ## performs the real upstream request (an HTTP GET the consumer wires --
  ## kept injected so the framework needs no HTTP client) and returns its
  ## raw response body, which this parses via `parseSearchResultsJson`. A
  ## `forward` that returns a malformed / empty body degrades to no
  ## results, never a crash. Proves the interface accommodates the
  ## "proxy" backend the deliverable names, testable with an in-memory
  ## `forward` stub.
  result.kind = sbkProxy
  result.handle = proc(q: string; limit: int): seq[SearchResult] =
    parseSearchResultsJson(forward(q, limit))

proc rowToResult(row: SearchRow): SearchResult =
  SearchResult(routePath: row.routePath, title: row.title,
    section: row.section, summary: row.summary, score: row.score)

proc newSqliteBackend*(loadRows: proc(query: string; limit: int): seq[SearchRow] {.closure.}): SearchBackend =
  ## A backend that adapts a SQLite (FTS5) table -- or any tabular store --
  ## to the interface. `loadRows` is the one consumer-supplied seam: it
  ## runs the parameterized query (e.g.
  ## `SELECT route_path, title, section, summary, rank
  ##    FROM docs_fts WHERE docs_fts MATCH ? ORDER BY rank LIMIT ?`
  ## via `std/db_sqlite`) and returns the rows; this maps them to
  ## `SearchResult`s. Keeping the DB handle + SQL in the consumer's
  ## `loadRows` is why the framework carries no `db_sqlite` dependency yet
  ## still ships a genuinely SQLite-shaped backend -- its contract
  ## (rows in -> ranked results out, `sbkSqlite`-tagged) is asserted in
  ## `test_server_search.nim` against a fake row loader.
  result.kind = sbkSqlite
  result.handle = proc(q: string; limit: int): seq[SearchResult] =
    for row in loadRows(q, limit):
      result.add rowToResult(row)

# --- the server endpoint glue ----------------------------------------------

proc urlDecode(s: string): string =
  ## Minimal `application/x-www-form-urlencoded` decode (`+` -> space,
  ## `%XX` -> byte) -- enough to read a search query out of a `?q=...`
  ## string without pulling in `std/uri` (whose `decodeUrl` is fine on C
  ## but keeps this module import-light and dual-target-obvious). A stray
  ## `%` without two hex digits is passed through literally rather than
  ## raising.
  var i = 0
  while i < s.len:
    case s[i]
    of '+':
      result.add ' '
      inc i
    of '%':
      if i + 2 < s.len and s[i+1] in HexDigits and s[i+2] in HexDigits:
        result.add chr(parseHexInt(s[i+1 .. i+2]))
        inc i, 3
      else:
        result.add '%'
        inc i
    else:
      result.add s[i]
      inc i

proc parseSearchQueryParams*(rawQuery: string): tuple[q: string, limit: int] =
  ## Parses a server search request's query string (the part after `?`,
  ## e.g. `q=signals%20effects&limit=5`) into the `q` text and `limit`.
  ## A leading `?` is tolerated. An absent/blank/non-numeric `limit` falls
  ## back to `defaultSearchLimit`, so a bare `?q=...` is always valid.
  result = (q: "", limit: defaultSearchLimit)
  var raw = rawQuery
  if raw.len > 0 and raw[0] == '?': raw = raw[1 .. ^1]
  for pair in raw.split('&'):
    if pair.len == 0: continue
    let eq = pair.find('=')
    let (key, val) =
      if eq < 0: (pair, "")
      else: (pair[0 ..< eq], pair[eq+1 .. ^1])
    case key
    of "q", "query": result.q = urlDecode(val)
    of "limit":
      try: result.limit = parseInt(val.strip())
      except ValueError: discard
    else: discard

proc handleSearchRequest*(backend: SearchBackend; rawQuery: string): string =
  ## The server endpoint's whole body: parse the request's `?q=...&limit=`,
  ## run the backend, and serialize the ranked results to the `results`
  ## wire JSON the client parses. A blank query yields an empty result set
  ## (never touches the backend) -- the same "no query, no results"
  ## invariant `search_vm.searchIndex` holds. Returns the JSON body; the
  ## HTTP status/headers are the host server's concern (the dev server or
  ## the consumer's real server), keeping this transport-agnostic.
  let params = parseSearchQueryParams(rawQuery)
  if params.q.strip().len == 0:
    return searchResultsToJson(@[])
  searchResultsToJson(query(backend, params.q, params.limit))

# --- the client dispatch: client-index vs server-API -----------------------

type
  SearchDispatch* = enum
    ## Which path a keystroke takes, resolved from the config toggle by
    ## `dispatchFor` -- the single branch point the client mount reads to
    ## decide "rank the local index now" vs "debounce, then fetch the
    ## server".
    sdClientIndex
    sdServerApi

proc dispatchFor*(config: ServerSearchConfig): SearchDispatch =
  ## Maps the config toggle to the client's dispatch path. `smServerApi`
  ## only actually takes the server path when an `endpoint` is configured
  ## -- an empty endpoint (a misconfigured site) safely falls back to the
  ## client-index path rather than firing requests at "".
  if config.mode == smServerApi and config.endpoint.len > 0: sdServerApi
  else: sdClientIndex

proc buildSearchRequestUrl*(endpoint, query: string; limit = defaultSearchLimit): string =
  ## Builds the URL the client `fetch`es in server mode:
  ## `<endpoint>?q=<url-encoded query>&limit=<n>`. Percent-encodes the
  ## query so spaces/`&`/`#`/etc. in what the user typed can't corrupt the
  ## query string. Pure string work (no `std/uri`) so it is identical on
  ## both targets and the server's `parseSearchQueryParams` round-trips it.
  result = endpoint & "?q="
  for c in query:
    if c in {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', '.', '~'}:
      result.add c
    else:
      result.add '%'
      result.add toHex(ord(c), 2)
  result.add "&limit="
  result.add $limit

type
  Debouncer* = object
    ## A pure, timestamp-free keystroke coalescer for server-mode search.
    ## Rather than track wall-clock times (which would make it un-unit-
    ## testable and drag a clock dependency across both backends), it uses
    ## the classic generation-token model: every keystroke bumps `gen` and
    ## captures the new value; the JS mount schedules a `setTimeout`
    ## (`intervalMs`) capturing that token; when the timer fires it calls
    ## `shouldFire` with the captured token, which is true ONLY if no newer
    ## keystroke has since bumped `gen`. So a burst of N fast keystrokes
    ## schedules N timers but fires exactly ONE request -- the last one --
    ## and the coalescing logic is a pure function of integers, asserted
    ## directly in the tests. `intervalMs` is carried here (from
    ## `ServerSearchConfig.debounceMs`) purely so the mount reads its
    ## `setTimeout` delay off the same object.
    gen*: int
    intervalMs*: int

proc newDebouncer*(intervalMs = defaultSearchDebounceMs): Debouncer =
  Debouncer(gen: 0, intervalMs: max(0, intervalMs))

proc onInput*(d: var Debouncer): int =
  ## Records a keystroke: bumps the generation and returns the token the
  ## caller must capture and later hand to `shouldFire`. Monotonic, so two
  ## keystrokes never share a token.
  inc d.gen
  d.gen

proc shouldFire*(d: Debouncer; token: int): bool =
  ## Whether the scheduled callback holding `token` should actually fire
  ## its query: true iff it is still the latest keystroke (no newer
  ## `onInput` has bumped `gen` since). This is the whole debounce
  ## decision -- see `Debouncer`'s docstring.
  token == d.gen

proc setResultsFromServer*(vm: SearchViewModel; query: string;
                           results: seq[SearchResult]): SearchViewModel =
  ## The server-mode counterpart to `search_vm.setQuery`: instead of
  ## ranking a local index, it installs the server's already-ranked
  ## `results` verbatim and resets the keyboard cursor to the top result
  ## (or "nothing selected" for an empty list) -- the exact same cursor
  ## convention `setQuery` uses, so every downstream reducer
  ## (`moveCursor`/`selectedResult`) and both result renderers work
  ## unchanged regardless of which path produced the results.
  SearchViewModel(query: query, results: results,
    cursor: (if results.len > 0: 0 else: -1), isOpen: vm.isOpen)
