## isonim-docs Layer 3 — build-time search indexing and the client
## search ViewModel (M4 deliverable 1), built on the same real content
## graph M3's navigation/reference modules already use:
## `content.ContentEntry` (front matter, section, provenance),
## `routes.RouteEntry`/`RouteManifest` (the authoritative canonical
## route path a page actually serves at), and `markdown_vm.MarkdownDoc`
## (the already-parsed heading tree a page's own body produces).
##
## Mirrors `navigation_vm.nim`'s own split: pure data + pure builders
## (tokenization, ranking, the index builder, the keyboard-driven
## ViewModel reducers) are filesystem-free and Tier-1-testable on both
## `nim c` and `nim js`; only the real corpus walk
## (`buildRealSearchIndex`/`writeSearchIndexArtifact`) touches a real
## filesystem and is guarded to the C target, exactly like
## `content.loadContentEntries`.
##
## Ranking is a small, hand-rolled, deterministic scorer -- not TF-IDF/
## BM25 -- on purpose: the M4 verification suite (`test_search_vm.nim`)
## asserts exact result ordering for fixture queries, which a corpus-
## statistics-dependent scorer would make needlessly fragile to reason
## about by hand. Every query token must match *something* in a page
## (title, heading, alias, or summary) for that page to be included at
## all (AND semantics across tokens) -- a page that only shares one of
## two query words is noise, not a result.

import std/[algorithm, strutils, json]
import ./content
import ./routes
import ./markdown_vm

type
  SearchEntry* = object
    ## One page's flattened search-relevant facts -- everything
    ## `scoreEntry` ranks against, with no further coupling to
    ## `RouteEntry`/`ContentEntry` themselves (mirrors `navigation_vm.
    ## NavPage`'s own flattening).
    routePath*: string
    title*: string
    section*: string
    summary*: string
    headings*: seq[string]
    aliases*: seq[string] ## Old route paths (`ContentFrontMatter.aliases`)
                          ## that used to address this page -- indexed so
                          ## a search for a renamed page's old slug still
                          ## finds it.

  SearchIndex* = object
    entries*: seq[SearchEntry]

  SearchResult* = object
    routePath*: string
    title*: string
    section*: string
    summary*: string
    score*: int

  HighlightSegment* = object
    ## One run of a result snippet, tagged with whether it is a matched
    ## query term (`marked`) that a renderer should wrap in `<mark>`.
    ## Splitting the snippet into typed segments -- rather than emitting
    ## raw `<mark>` HTML -- keeps matched-term highlighting renderer-
    ## agnostic: the SSR string path concatenates `<mark>...</mark>`
    ## while the live browser/mock tree path builds real `<mark>`
    ## elements + text nodes, from the exact same segmentation.
    text*: string
    marked*: bool

  SearchViewModel* = object
    ## The client search box's full state: the raw query text, the
    ## current (already-ranked) result list, a keyboard cursor into
    ## that list (-1 when nothing is selected -- the zero-value default
    ## `cursor == 0` would otherwise misreport "first result selected"
    ## for an empty result list), and whether the search UI is open.
    query*: string
    results*: seq[SearchResult]
    cursor*: int
    isOpen*: bool

const
  weightTitleExact = 100
  weightAliasExact = 90
  weightTitlePrefix = 60
  weightHeadingExact = 40
  weightHeadingPrefix = 20
  weightSummaryExact = 10
  weightSummaryPrefix = 5

proc isWordChar(c: char): bool =
  c in {'a'..'z', 'A'..'Z', '0'..'9'}

proc tokenize*(text: string): seq[string] =
  ## Splits `text` into lowercase alphanumeric runs -- the one
  ## tokenizer both index-building and query-scoring share, so a
  ## query and the corpus it's matched against always agree on what
  ## counts as a "word". Punctuation (including a route path's own
  ## "/" and "-" separators) is treated purely as a word boundary, so
  ## an alias like "/old-guide" tokenizes to ["old", "guide"] exactly
  ## like the prose "the old guide" would.
  var current = ""
  for c in text:
    if isWordChar(c):
      current.add toLowerAscii(c)
    elif current.len > 0:
      result.add current
      current = ""
  if current.len > 0:
    result.add current

proc bestFieldWeight(tokens: seq[string]; queryToken: string;
                      exactWeight, prefixWeight: int): int =
  ## The best (highest) weight `queryToken` earns against one field's
  ## own token list: an exact word match wins outright, a prefix match
  ## (the field word starts with the shorter query token) still counts
  ## but for less -- so typing "sig" finds "Signals & Effects" without
  ## an exact match ranking no higher than a mere prefix hit elsewhere.
  for t in tokens:
    if t == queryToken:
      return exactWeight
    elif prefixWeight > 0 and t.len > queryToken.len and t.startsWith(queryToken):
      result = max(result, prefixWeight)

proc scoreEntry*(entry: SearchEntry; queryTokens: seq[string]): int =
  ## Deterministic relevance score for `entry` against `queryTokens`:
  ## every query token must earn a nonzero weight against *some* field
  ## (title, alias, heading, or summary) or the whole entry scores 0
  ## (AND semantics -- see the module docstring). Title matches
  ## outrank alias matches, which outrank heading matches, which
  ## outrank summary matches, mirroring how a reader would expect a
  ## page whose *title* contains the word to surface above one that
  ## only mentions it in passing.
  ##
  ## M5 deliverable 2 (scoring) deliberately KEEPS this hand-rolled
  ## field-weighted scorer rather than upgrading to BM25, and this is a
  ## considered choice, not an omission:
  ##  1. BM25's discriminating power comes from corpus statistics -- an
  ##     inverse-document-frequency term that down-weights words common
  ##     across the corpus, and a document-length normalization term.
  ##     A docs site's search corpus is tiny (tens to low-hundreds of
  ##     short pages) and, more importantly, the fields we index are
  ##     already curated *labels* (title, headings, aliases), not free
  ##     prose -- so term rarity carries far less signal than *which
  ##     field* a term appears in. "the word is in the page's title"
  ##     is a stronger, more predictable relevance signal for a reader
  ##     than "the word is statistically rare across the corpus", and
  ##     this field-tier weighting encodes exactly that.
  ##  2. Length normalization actively hurts here: a terse page with a
  ##     one-line summary should not outrank a thorough page just for
  ##     being shorter.
  ##  3. Determinism: the ordering is a pure function of one entry's own
  ##     fields, independent of the rest of the corpus, so a page's rank
  ##     for a query never silently shifts when an unrelated page is
  ##     added or edited -- which is why the ranking tests
  ##     (`test_search_vm.nim`'s "scoreEntry ranking" + the multi-term
  ##     ordering test) can pin exact expected orderings by hand.
  ## `highlightMatches` below shares this module's exact-vs-prefix match
  ## rule, so the terms a result is *ranked* on are exactly the terms it
  ## *highlights* in the snippet.
  if queryTokens.len == 0:
    return 0
  let titleTokens = tokenize(entry.title)
  var headingTokens: seq[string] = @[]
  for h in entry.headings:
    headingTokens.add tokenize(h)
  var aliasTokens: seq[string] = @[]
  for a in entry.aliases:
    aliasTokens.add tokenize(a)
  let summaryTokens = tokenize(entry.summary)

  for qt in queryTokens:
    var best = bestFieldWeight(titleTokens, qt, weightTitleExact, weightTitlePrefix)
    best = max(best, bestFieldWeight(aliasTokens, qt, weightAliasExact, 0))
    best = max(best, bestFieldWeight(headingTokens, qt, weightHeadingExact, weightHeadingPrefix))
    best = max(best, bestFieldWeight(summaryTokens, qt, weightSummaryExact, weightSummaryPrefix))
    if best == 0:
      return 0
    result += best

proc tokenMatchesWord(word, queryToken: string): bool =
  ## The one exact-or-prefix rule `scoreEntry`'s `bestFieldWeight` and
  ## `highlightMatches` share (see `scoreEntry`'s docstring): `word` is
  ## already lowercased; a match is an exact equality or the field word
  ## having the shorter query token as a strict prefix.
  word == queryToken or
    (queryToken.len > 0 and word.len > queryToken.len and word.startsWith(queryToken))

proc highlightMatches*(text: string; queryTokens: seq[string]): seq[HighlightSegment] =
  ## Segments `text` into matched (`marked`) and unmatched runs for
  ## result-snippet highlighting (M5 deliverable 2), preserving the
  ## original characters (and their exact spacing/punctuation) verbatim
  ## so a renderer can escape and re-emit the snippet without loss. A
  ## whole word is marked when it matches any query token under the same
  ## exact-or-prefix rule the scorer ranks on (`tokenMatchesWord`), so
  ## the highlighted terms are exactly the terms the result was ranked
  ## for. Adjacent unmatched characters (whitespace + punctuation +
  ## non-matching words) coalesce into one segment; each matched word is
  ## its own segment. An empty query yields a single unmarked segment
  ## (the whole text), never any `<mark>`s.
  if text.len == 0:
    return @[]
  ## The pending-run flush is inlined (rather than a nested `proc`) on
  ## purpose: a closure capturing this proc's `result` seq is rejected by
  ## the JS backend ("cannot be captured as it would violate memory
  ## safety"), and `highlightMatches` has to run on both targets (the SSR
  ## snippet path and the live overlay's client re-render both call it).
  var pending = ""
  var i = 0
  while i < text.len:
    if isWordChar(text[i]):
      var j = i
      while j < text.len and isWordChar(text[j]): inc j
      let word = text[i ..< j]
      var marked = false
      let lower = word.toLowerAscii
      for qt in queryTokens:
        if tokenMatchesWord(lower, qt):
          marked = true
          break
      if marked:
        if pending.len > 0:
          result.add HighlightSegment(text: pending, marked: false)
          pending = ""
        result.add HighlightSegment(text: word, marked: true)
      else:
        pending.add word
      i = j
    else:
      pending.add text[i]
      inc i
  if pending.len > 0:
    result.add HighlightSegment(text: pending, marked: false)

proc searchIndex*(index: SearchIndex; query: string): seq[SearchResult] =
  ## Ranks every entry of `index` against `query`, dropping non-matches
  ## and sorting by score descending, tie-broken by `routePath`
  ## ascending -- so two entries with the same score (including two
  ## unrelated queries that both happen to score everything 0) always
  ## come back in the exact same order, never in the input's or a
  ## table's incidental iteration order.
  let queryTokens = tokenize(query)
  if queryTokens.len == 0:
    return @[]
  for entry in index.entries:
    let score = scoreEntry(entry, queryTokens)
    if score > 0:
      result.add SearchResult(routePath: entry.routePath, title: entry.title,
        section: entry.section, summary: entry.summary, score: score)
  result.sort(proc(a, b: SearchResult): int =
    if a.score != b.score: return cmp(b.score, a.score)
    cmp(a.routePath, b.routePath))

proc newSearchViewModel*(): SearchViewModel =
  SearchViewModel(cursor: -1)

proc setQuery*(vm: SearchViewModel; index: SearchIndex; query: string): SearchViewModel =
  ## Re-runs the ranked search for `query` and resets the keyboard
  ## cursor to the top result (or to "nothing selected" when the query
  ## has no results) -- typing a new character always starts from the
  ## best match rather than preserving a cursor position that may no
  ## longer even be in range.
  let results = searchIndex(index, query)
  SearchViewModel(query: query, results: results,
    cursor: (if results.len > 0: 0 else: -1), isOpen: vm.isOpen)

proc moveCursor*(vm: SearchViewModel; delta: int): SearchViewModel =
  ## Moves the keyboard cursor by `delta`, clamped to the result
  ## list's bounds (no wraparound -- pressing "up" at the first result
  ## simply stays there, exactly like a native `<select>`). A no-op on
  ## an empty result list.
  result = vm
  if vm.results.len == 0:
    return
  var next = vm.cursor + delta
  if next < 0: next = 0
  if next > vm.results.len - 1: next = vm.results.len - 1
  result.cursor = next

proc selectedResult*(vm: SearchViewModel): SearchResult =
  ## The result the keyboard cursor currently points at, or a
  ## zero-value `SearchResult` (`routePath == ""`) when nothing is
  ## selected -- the same empty-string-sentinel convention
  ## `navigation_vm.AdjacentPage` already uses.
  if vm.cursor >= 0 and vm.cursor < vm.results.len: vm.results[vm.cursor]
  else: SearchResult()

proc openSearch*(vm: SearchViewModel): SearchViewModel =
  result = vm
  result.isOpen = true

proc closeSearch*(vm: SearchViewModel): SearchViewModel =
  ## Closing always resets to a blank search, not just the open flag --
  ## reopening the search box should never resurface a stale query/
  ## result list from a previous session.
  SearchViewModel(cursor: -1, isOpen: false)

proc collectHeadingTexts(node: HeadingNode; acc: var seq[string]) =
  acc.add node.text
  for child in node.children:
    collectHeadingTexts(child, acc)

proc searchSummary*(front: ContentFrontMatter; doc: MarkdownDoc): string =
  ## The text a result's preview snippet (and its own summary-field
  ## ranking weight) is drawn from: an explicit front matter
  ## `description:` wins, otherwise the page's own first paragraph --
  ## mirrors `shell_vm.buildDocumentHead`'s same "front matter
  ## description, falling back to derived text" precedence.
  if front.description.len > 0:
    return front.description
  for blk in doc.blocks:
    if blk.kind == bkParagraph:
      return spansText(blk.spans)
  ""

proc searchEntry*(entry: RouteEntry; content: ContentEntry; doc: MarkdownDoc): SearchEntry =
  ## Builds one page's `SearchEntry` off the same real content graph
  ## `navigation_vm.navPage` pairs -- `entry.canonicalPath`, not
  ## `content.routePath`, is the indexed link target, for the exact
  ## same reason `navPage`'s own docstring gives (routing's answer is
  ## authoritative; the two can legitimately disagree).
  let title = if content.page.title.len > 0: content.page.title else: entry.meta.title
  var headings: seq[string] = @[]
  for h in doc.headingTree:
    collectHeadingTexts(h, headings)
  SearchEntry(routePath: entry.canonicalPath, title: title, section: content.section,
    summary: searchSummary(content.front, doc), headings: headings, aliases: content.front.aliases)

proc buildSearchIndex*(manifest: RouteManifest;
                        loadEntry: proc(contentPath: string): ContentEntry {.closure.}): SearchIndex =
  ## Builds the real site-wide search index: every real, addressable
  ## (non-redirect) manifest entry paired with its own loaded content
  ## and parsed markdown doc. `pkRedirect` alias entries are skipped --
  ## they carry no content of their own to index, and their own old
  ## route path is already indexed as one of their *target* page's
  ## `aliases` (see `searchEntry`), so skipping them here doesn't lose
  ## alias searchability. Mirrors `navigation_vm.buildNavPages`'s exact
  ## tolerance policy: an entry whose content fails to load is left out
  ## of the index rather than failing the whole build.
  var entries: seq[SearchEntry] = @[]
  for entry in manifest.entries:
    if entry.pageKind == pkRedirect:
      continue
    try:
      let content = loadEntry(entry.meta.contentPath)
      let doc = parseMarkdownDoc(content.page.body, content.source.path)
      entries.add searchEntry(entry, content, doc)
    except CatchableError:
      discard
  SearchIndex(entries: entries)

proc escapeJsonString*(s: string): string =
  ## Minimal, dependency-free JSON string escaping (mirrors
  ## `isonim/ssr/escape.escapeHtml`'s own hand-rolled style rather than
  ## pulling in `std/json`, which isn't a dual-target-safe dependency
  ## to lean on here). Escapes the JSON-mandatory characters plus
  ## `</` -- the latter so a page whose title/summary happens to
  ## contain a literal `</script>` can never prematurely close the
  ## bootstrap `<script>` tag this feeds into.
  result.add '"'
  for c in s:
    case c
    of '"': result.add "\\\""
    of '\\': result.add "\\\\"
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    of '/':
      if result.len > 0 and result[^1] == '<': result.add "\\/"
      else: result.add '/'
    else:
      if ord(c) < 0x20:
        result.add "\\u" & toHex(ord(c), 4)
      else:
        result.add c
  result.add '"'

proc jsonStringArray(items: seq[string]): string =
  result = "["
  for i, item in items:
    if i > 0: result.add ","
    result.add escapeJsonString(item)
  result.add "]"

proc searchEntryToJson*(entry: SearchEntry): string =
  "{\"routePath\":" & escapeJsonString(entry.routePath) &
    ",\"title\":" & escapeJsonString(entry.title) &
    ",\"section\":" & escapeJsonString(entry.section) &
    ",\"summary\":" & escapeJsonString(entry.summary) &
    ",\"headings\":" & jsonStringArray(entry.headings) &
    ",\"aliases\":" & jsonStringArray(entry.aliases) & "}"

proc searchIndexToJson*(index: SearchIndex): string =
  ## The one canonical serialization real build artifacts
  ## (`writeSearchIndexArtifact`) and the SSR bootstrap payload
  ## (`components/search_view.renderSearchBootstrapHtml`) both use, so
  ## the on-disk index and the one embedded in a served page are always
  ## byte-for-byte the same shape.
  result = "{\"entries\":["
  for i, entry in index.entries:
    if i > 0: result.add ","
    result.add searchEntryToJson(entry)
  result.add "]}"

proc jsonStrSeq(node: JsonNode): seq[string] =
  ## Reads a JSON array of strings into a `seq[string]`, tolerating a
  ## missing/non-array field as an empty seq -- iterated element-by-
  ## element (not `std/json`'s `to`) so it stays correct on both the C
  ## and JS backends.
  if node != nil and node.kind == JArray:
    for item in node:
      if item.kind == JString:
        result.add item.getStr

proc parseSearchIndexJson*(text: string): SearchIndex =
  ## Parses a serialized search index (the exact `searchIndexToJson`
  ## shape the build's hashed `search-index.<hash>.json` artifact holds)
  ## back into a `SearchIndex` -- the client counterpart to
  ## `searchIndexToJson`, used by `main_web.nim`'s overlay to turn the
  ## lazily-fetched `search-index.<hash>.json` artifact text into the
  ## same in-memory index the ViewModel ranks against, and by
  ## `test_search_index_artifact.nim` to round-trip-verify the on-disk
  ## artifact. A malformed payload yields an empty index rather than
  ## raising -- a broken/absent index must degrade search to "no
  ## results", never crash the page.
  var root: JsonNode
  try:
    root = parseJson(text)
  except CatchableError:
    return SearchIndex()
  if root.kind != JObject or not root.hasKey("entries"):
    return SearchIndex()
  let entries = root["entries"]
  if entries.kind != JArray:
    return SearchIndex()
  for e in entries:
    if e.kind != JObject: continue
    proc str(key: string): string =
      if e.hasKey(key) and e[key].kind == JString: e[key].getStr else: ""
    result.entries.add SearchEntry(
      routePath: str("routePath"), title: str("title"), section: str("section"),
      summary: str("summary"),
      headings: (if e.hasKey("headings"): jsonStrSeq(e["headings"]) else: @[]),
      aliases: (if e.hasKey("aliases"): jsonStrSeq(e["aliases"]) else: @[]))

when not defined(js):
  import std/os

  proc buildRealSearchIndex*(contentDir: string; manifest: RouteManifest): SearchIndex =
    ## The real-filesystem counterpart to `buildSearchIndex`: loads
    ## every manifest entry's bound content file from the real
    ## `contentDir` (a hermetic fixture temp dir in tests, the real
    ## `content/` dir in production) via `content.loadContentEntry`,
    ## exactly like `ssr.renderRoute`'s own navigation-building already
    ## does for `navigation_vm.buildNavPages`.
    buildSearchIndex(manifest, proc(contentPath: string): ContentEntry =
      loadContentEntry(contentDir, contentPath))

  proc writeSearchIndexArtifact*(contentDir: string; manifest: RouteManifest;
                                  outDir: string): string =
    ## Writes the real search index as a build artifact
    ## (`<outDir>/search-index.json`) and returns the path written --
    ## the "build-time search indexing" half of M4 deliverable 1: a
    ## real, on-disk JSON artifact a release build (and later M4
    ## deliverable 4's release gate) can point at, independent of any
    ## one served page's own embedded bootstrap payload.
    let index = buildRealSearchIndex(contentDir, manifest)
    createDir(outDir)
    let outPath = outDir / "search-index.json"
    writeFile(outPath, searchIndexToJson(index))
    outPath
