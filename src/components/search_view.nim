## isonim-docs Layer 2 — rendering for the search ViewModel
## (`src/core/search_vm.nim`, M4 deliverable 1).
##
## Mirrors `navigation_view.nim`'s own split: a purely structural
## rendering of whatever `SearchViewModel` state it's handed --
## search box, ranked result list, and the distinct empty-state shape
## -- with no event wiring of its own. Real keystroke/keyboard-cursor
## interactivity is a platform-specific concern (reading a live input
## element's `.value`, a `KeyboardEvent`'s `.key`) that belongs to the
## JS-target-only mount entry (`src/main_web.nim`), not this
## generic-over-renderer Layer 2 module -- exactly the same "generic
## rendering here, live wiring at the Layer 4 shell" split
## `components/shell.nim`'s own docstring calls out.
##
## `renderSearchResultsContent`/`renderSearchResultsContentHtml` are
## exported separately from `renderSearchBox`/`renderSearchBoxHtml` so
## a live mount can re-render *just* the result list in place after a
## keystroke (`WebRenderer.clearChildren` + a fresh
## `renderSearchResultsContent` call) without tearing down and
## recreating the `<input>` itself -- which would drop browser focus.

import isonim/ssr/escape
import ../core/search_vm
import ../core/config

const
  searchRegionClass* = "docs-search"
  searchInputClass* = "docs-search-input"
  searchInputId* = "docs-search-input"
  searchResultsWrapperId* = "docs-search-results-wrapper"
  searchResultsClass* = "docs-search-results"
  searchResultItemClass* = "docs-search-result"
  searchResultActiveClass* = "docs-search-result-active"
  searchResultLinkClass* = "docs-search-result-link"
  searchResultSectionClass* = "docs-search-result-section"
  searchEmptyClass* = "docs-search-empty"
  searchBootstrapScriptId* = "docs-search-index"
  searchResultSnippetClass* = "docs-search-result-snippet"
  searchMarkClass* = "docs-search-mark"

  # --- M5 deliverable 2: the keyboard-triggered search overlay ----------
  searchOverlayClass* = "docs-search-overlay"
  searchOverlayId* = "docs-search-overlay"
  searchOverlayDialogClass* = "docs-search-overlay-dialog"
  searchOverlayInputId* = "docs-search-overlay-input"
  searchOverlayInputClass* = "docs-search-overlay-input"
  searchOverlayResultsId* = "docs-search-overlay-results"
  searchOverlayHintClass* = "docs-search-overlay-hint"
  searchIndexUrlAttr* = "data-search-index-url"
  searchModeAttr* = "data-search-mode"
    ## M12 deliverable 2: the resolved search mode (`config.SearchMode`'s
    ## string value -- "client"/"server") the SSR emits onto the overlay so
    ## the client mount knows, without any inline config, which path to take
    ## for each keystroke. Absent/"client" keeps the pre-M12 client-index
    ## behaviour; "server" switches to the debounced server-API path.
  searchEndpointAttr* = "data-search-endpoint"
    ## The server search endpoint the client `fetch`es in server mode
    ## (`ServerSearchConfig.endpoint`). Emitted only when server mode is on.
  searchDebounceAttr* = "data-search-debounce"
    ## The keystroke-coalescing window (ms) the client reads for its
    ## `setTimeout` in server mode (`ServerSearchConfig.debounceMs`).
  searchOpenAttr* = "data-open"
  defaultSearchIndexUrl* = "/search-index.json"
    ## The build-time placeholder the SSG rewrites to the real content-
    ## hashed `/search-index.<hash>.json` (mirroring the M2 asset-hash
    ## href rewrite), so the overlay references the cache-busted artifact
    ## without any renderer needing to know the hash.

# --- MockRenderer / browser tree mode -----------------------------------

proc renderSearchResultsContent*[R, E](r: R; vm: SearchViewModel): E =
  ## The ranked result list, or the distinct empty-state shape when
  ## the query has text but matched nothing -- an untouched (empty
  ## query) search box renders an empty `<ul>` with no empty-state
  ## message, since "no query yet" and "query with zero matches" are
  ## different states a reader shouldn't confuse.
  if vm.query.len > 0 and vm.results.len == 0:
    let empty = r.createElement("div")
    r.setAttribute(empty, "class", searchEmptyClass)
    r.appendChild(empty, r.createTextNode("No results for \"" & vm.query & "\""))
    return empty
  let list = r.createElement("ul")
  r.setAttribute(list, "class", searchResultsClass)
  r.setAttribute(list, "role", "listbox")
  for i, res in vm.results:
    let li = r.createElement("li")
    let isActive = i == vm.cursor
    r.setAttribute(li, "class",
      if isActive: searchResultItemClass & " " & searchResultActiveClass
      else: searchResultItemClass)
    r.setAttribute(li, "role", "option")
    if isActive:
      r.setAttribute(li, "aria-selected", "true")
    let a = r.createElement("a")
    r.setAttribute(a, "class", searchResultLinkClass)
    r.setAttribute(a, "href", res.routePath)
    r.appendChild(a, r.createTextNode(res.title))
    r.appendChild(li, a)
    if res.section.len > 0:
      let sectionEl = r.createElement("span")
      r.setAttribute(sectionEl, "class", searchResultSectionClass)
      r.appendChild(sectionEl, r.createTextNode(res.section))
      r.appendChild(li, sectionEl)
    r.appendChild(list, li)
  list

proc renderSearchBox*[R, E](r: R; vm: SearchViewModel): E =
  ## The full search landmark: a text input seeded with the current
  ## query, plus its results wrapper (stable `searchResultsWrapperId`,
  ## the seam a live mount clears and refills in place).
  let container = r.createElement("div")
  r.setAttribute(container, "class", searchRegionClass)
  r.setAttribute(container, "role", "search")

  let inputEl = r.createElement("input")
  r.setAttribute(inputEl, "type", "text")
  r.setAttribute(inputEl, "id", searchInputId)
  r.setAttribute(inputEl, "class", searchInputClass)
  r.setAttribute(inputEl, "placeholder", "Search docs…")
  r.setAttribute(inputEl, "aria-label", "Search documentation")
  r.setAttribute(inputEl, "value", vm.query)
  r.appendChild(container, inputEl)

  let resultsWrapper = r.createElement("div")
  r.setAttribute(resultsWrapper, "id", searchResultsWrapperId)
  r.appendChild(resultsWrapper, renderSearchResultsContent[R, E](r, vm))
  r.appendChild(container, resultsWrapper)

  container

# --- SSR string mode ------------------------------------------------------

proc renderSearchResultsContentHtml*(vm: SearchViewModel): string =
  if vm.query.len > 0 and vm.results.len == 0:
    return "<div class=\"" & searchEmptyClass & "\">No results for \"" &
      escapeHtml(vm.query) & "\"</div>"
  result = "<ul class=\"" & searchResultsClass & "\" role=\"listbox\">"
  for i, res in vm.results:
    let isActive = i == vm.cursor
    let itemClass =
      if isActive: searchResultItemClass & " " & searchResultActiveClass
      else: searchResultItemClass
    let selectedAttr = if isActive: " aria-selected=\"true\"" else: ""
    result.add "<li class=\"" & itemClass & "\" role=\"option\"" & selectedAttr & ">"
    result.add "<a class=\"" & searchResultLinkClass & "\" href=\"" &
      escapeAttr(res.routePath) & "\">" & escapeHtml(res.title) & "</a>"
    if res.section.len > 0:
      result.add "<span class=\"" & searchResultSectionClass & "\">" &
        escapeHtml(res.section) & "</span>"
    result.add "</li>"
  result.add "</ul>"

proc renderSearchBoxHtml*(vm: SearchViewModel): string =
  "<div class=\"" & searchRegionClass & "\" role=\"search\">" &
    "<input type=\"text\" id=\"" & searchInputId & "\" class=\"" & searchInputClass &
      "\" placeholder=\"Search docs…\" aria-label=\"Search documentation\" value=\"" &
      escapeAttr(vm.query) & "\">" &
    "<div id=\"" & searchResultsWrapperId & "\">" & renderSearchResultsContentHtml(vm) & "</div>" &
  "</div>"

# --- M5 deliverable 2: the keyboard-triggered search overlay ------------
##
## A separate, keyboard-triggered modal (Cmd/Ctrl+K or `/`), distinct
## from the always-visible inline `renderSearchBox` above. Its result
## snippets highlight the matched query terms as real `<mark>` elements
## (tree path) / `<mark>...</mark>` (SSR path), both built from the exact
## same `search_vm.highlightMatches` segmentation so the two backends
## stay in lock-step (dual-target parity). Unlike the inline box, the
## overlay's index is NOT inlined into the page: it carries the build-
## time `defaultSearchIndexUrl` placeholder in `searchIndexUrlAttr`, which
## the SSG rewrites to the content-hashed `/search-index.<hash>.json`
## artifact the client fetches lazily on first open (see `build_site.nim`
## and `main_web.wireSearchOverlay`). The SSR render therefore only ever
## emits an EMPTY result list (no query yet, nothing fetched); the live
## client re-renders it, with highlighting, once the user types.

proc renderSearchOverlayResultsContent*[R, E](r: R; vm: SearchViewModel): E =
  ## The overlay's ranked result list -- same shape/roles as
  ## `renderSearchResultsContent` but each result additionally carries a
  ## matched-term-highlighted snippet of its summary, built from
  ## `highlightMatches` into `searchMarkClass`-tagged `<mark>` elements.
  if vm.query.len > 0 and vm.results.len == 0:
    let empty = r.createElement("div")
    r.setAttribute(empty, "class", searchEmptyClass)
    r.appendChild(empty, r.createTextNode("No results for \"" & vm.query & "\""))
    return empty
  let queryTokens = tokenize(vm.query)
  let list = r.createElement("ul")
  r.setAttribute(list, "class", searchResultsClass)
  r.setAttribute(list, "role", "listbox")
  for i, res in vm.results:
    let li = r.createElement("li")
    let isActive = i == vm.cursor
    r.setAttribute(li, "class",
      if isActive: searchResultItemClass & " " & searchResultActiveClass
      else: searchResultItemClass)
    r.setAttribute(li, "role", "option")
    if isActive:
      r.setAttribute(li, "aria-selected", "true")
    let a = r.createElement("a")
    r.setAttribute(a, "class", searchResultLinkClass)
    r.setAttribute(a, "href", res.routePath)
    r.appendChild(a, r.createTextNode(res.title))
    r.appendChild(li, a)
    if res.section.len > 0:
      let sectionEl = r.createElement("span")
      r.setAttribute(sectionEl, "class", searchResultSectionClass)
      r.appendChild(sectionEl, r.createTextNode(res.section))
      r.appendChild(li, sectionEl)
    if res.summary.len > 0:
      let snippet = r.createElement("span")
      r.setAttribute(snippet, "class", searchResultSnippetClass)
      for seg in highlightMatches(res.summary, queryTokens):
        if seg.marked:
          let mark = r.createElement("mark")
          r.setAttribute(mark, "class", searchMarkClass)
          r.appendChild(mark, r.createTextNode(seg.text))
          r.appendChild(snippet, mark)
        else:
          r.appendChild(snippet, r.createTextNode(seg.text))
      r.appendChild(li, snippet)
    r.appendChild(list, li)
  list

proc renderSearchOverlayResultsContentHtml*(vm: SearchViewModel): string =
  ## SSR string-mode rendering -- same shape as
  ## `renderSearchOverlayResultsContent` (matched terms wrapped in
  ## `<mark>...</mark>`, built from the same `highlightMatches`
  ## segmentation, so the two paths stay byte-parity in structure).
  if vm.query.len > 0 and vm.results.len == 0:
    return "<div class=\"" & searchEmptyClass & "\">No results for \"" &
      escapeHtml(vm.query) & "\"</div>"
  let queryTokens = tokenize(vm.query)
  result = "<ul class=\"" & searchResultsClass & "\" role=\"listbox\">"
  for i, res in vm.results:
    let isActive = i == vm.cursor
    let itemClass =
      if isActive: searchResultItemClass & " " & searchResultActiveClass
      else: searchResultItemClass
    let selectedAttr = if isActive: " aria-selected=\"true\"" else: ""
    result.add "<li class=\"" & itemClass & "\" role=\"option\"" & selectedAttr & ">"
    result.add "<a class=\"" & searchResultLinkClass & "\" href=\"" &
      escapeAttr(res.routePath) & "\">" & escapeHtml(res.title) & "</a>"
    if res.section.len > 0:
      result.add "<span class=\"" & searchResultSectionClass & "\">" &
        escapeHtml(res.section) & "</span>"
    if res.summary.len > 0:
      result.add "<span class=\"" & searchResultSnippetClass & "\">"
      for seg in highlightMatches(res.summary, queryTokens):
        if seg.marked:
          result.add "<mark class=\"" & searchMarkClass & "\">" & escapeHtml(seg.text) & "</mark>"
        else:
          result.add escapeHtml(seg.text)
      result.add "</span>"
    result.add "</li>"
  result.add "</ul>"

proc renderSearchOverlay*[R, E](r: R; vm: SearchViewModel;
                                 indexUrl: string = defaultSearchIndexUrl;
                                 search: ServerSearchConfig = defaultServerSearchConfig()): E =
  ## The keyboard-triggered overlay's full markup: a `role="dialog"`
  ## container carrying the (build-time-rewritten) `searchIndexUrlAttr`
  ## the client fetches its index from, a `searchOpenAttr` open/closed
  ## flag (starts closed + `hidden`), an input, a results wrapper (stable
  ## `searchOverlayResultsId`, the seam the live mount clears/refills),
  ## and a keyboard hint.
  ##
  ## M12 deliverable 2: `search` carries the client-index-vs-server-API
  ## toggle. The `searchModeAttr` is always emitted (so the client reads a
  ## definite mode); the `searchEndpointAttr`/`searchDebounceAttr` are
  ## emitted only in server mode, so a default (client) overlay's markup is
  ## otherwise unchanged from pre-M12.
  let overlay = r.createElement("div")
  r.setAttribute(overlay, "class", searchOverlayClass)
  r.setAttribute(overlay, "id", searchOverlayId)
  r.setAttribute(overlay, "role", "dialog")
  r.setAttribute(overlay, "aria-modal", "true")
  r.setAttribute(overlay, "aria-label", "Search documentation")
  r.setAttribute(overlay, searchIndexUrlAttr, indexUrl)
  r.setAttribute(overlay, searchModeAttr, $search.mode)
  if search.mode == smServerApi:
    r.setAttribute(overlay, searchEndpointAttr, search.endpoint)
    r.setAttribute(overlay, searchDebounceAttr, $search.debounceMs)
  r.setAttribute(overlay, searchOpenAttr, "false")
  r.setAttribute(overlay, "hidden", "hidden")

  let dialog = r.createElement("div")
  r.setAttribute(dialog, "class", searchOverlayDialogClass)

  let inputEl = r.createElement("input")
  r.setAttribute(inputEl, "type", "text")
  r.setAttribute(inputEl, "id", searchOverlayInputId)
  r.setAttribute(inputEl, "class", searchOverlayInputClass)
  r.setAttribute(inputEl, "placeholder", "Search docs…")
  r.setAttribute(inputEl, "aria-label", "Search documentation")
  r.setAttribute(inputEl, "value", vm.query)
  r.appendChild(dialog, inputEl)

  let resultsWrapper = r.createElement("div")
  r.setAttribute(resultsWrapper, "id", searchOverlayResultsId)
  r.appendChild(resultsWrapper, renderSearchOverlayResultsContent[R, E](r, vm))
  r.appendChild(dialog, resultsWrapper)

  let hint = r.createElement("div")
  r.setAttribute(hint, "class", searchOverlayHintClass)
  r.appendChild(hint, r.createTextNode("Press Esc to close"))
  r.appendChild(dialog, hint)

  r.appendChild(overlay, dialog)
  overlay

proc renderSearchOverlayHtml*(vm: SearchViewModel;
                               indexUrl: string = defaultSearchIndexUrl;
                               search: ServerSearchConfig = defaultServerSearchConfig()): string =
  ## SSR string-mode rendering -- same shape as `renderSearchOverlay`.
  let serverAttrs =
    if search.mode == smServerApi:
      " " & searchEndpointAttr & "=\"" & escapeAttr(search.endpoint) & "\" " &
        searchDebounceAttr & "=\"" & $search.debounceMs & "\""
    else: ""
  "<div class=\"" & searchOverlayClass & "\" id=\"" & searchOverlayId &
    "\" role=\"dialog\" aria-modal=\"true\" aria-label=\"Search documentation\" " &
    searchIndexUrlAttr & "=\"" & escapeAttr(indexUrl) & "\" " &
    searchModeAttr & "=\"" & $search.mode & "\"" & serverAttrs & " " &
    searchOpenAttr & "=\"false\" hidden>" &
    "<div class=\"" & searchOverlayDialogClass & "\">" &
      "<input type=\"text\" id=\"" & searchOverlayInputId & "\" class=\"" &
        searchOverlayInputClass & "\" placeholder=\"Search docs…\" " &
        "aria-label=\"Search documentation\" value=\"" & escapeAttr(vm.query) & "\">" &
      "<div id=\"" & searchOverlayResultsId & "\">" &
        renderSearchOverlayResultsContentHtml(vm) & "</div>" &
      "<div class=\"" & searchOverlayHintClass & "\">Press Esc to close</div>" &
    "</div>" &
  "</div>"

proc renderSearchBootstrapHtml*(index: SearchIndex): string =
  ## The client search hydration payload: the real, build-time search
  ## index serialized as JSON inside a stable-id `<script>` tag (never
  ## executed -- `type="application/json"` -- just a data island), so a
  ## client mount (or any future non-Nim consumer) can read the exact
  ## same index this page's `<html>` was rendered against without a
  ## separate network round trip.
  "<script id=\"" & searchBootstrapScriptId & "\" type=\"application/json\">" &
    searchIndexToJson(index) & "</script>"
