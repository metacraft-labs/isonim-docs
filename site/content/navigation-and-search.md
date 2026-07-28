---
title: Navigation & Search
description: The recursive sidebar, breadcrumbs, and prev/next navigation, the in-browser client search index, and the optional server-side search path with pluggable backends.
order: 5
---
# Navigation & Search

isonim-docs derives a site's whole navigation surface -- a recursive
sidebar, breadcrumbs, and prev/next links -- from the same route manifest
that resolves routes, and it ships two interchangeable search paths: an
in-browser client index (the default) and an optional server API for
corpora too large to ship to every visitor.

## Navigation

`core/navigation_vm` turns the manifest's pages into an infinitely-nested
sidebar tree, breadcrumbs, and adjacent-page links. Nested content
directories become nested sections; a section auto-expands when it holds the
active page, and its expansion state is a pure value the layout persists.
External links (an absolute `http(s)://` route) are detected and rendered
with a `target=_blank rel=noopener` icon rather than treated as an in-site
route.

The navigation ViewModels are fed the same `NavPage` list built from the
manifest, so a page's sidebar entry, its breadcrumb, and its prev/next link
all point at the one canonical route path -- routing and navigation can never
disagree (see [Routing](./routing.md)).

## Client search

The default search path ranks a `search_vm.SearchIndex` entirely in the
browser. The index is one `SearchEntry` per page -- route, title, section,
summary, headings, and any `aliases:` -- built at SSG time and emitted as a
separate content-hashed `search-index.<hash>.json` artifact that the overlay
fetches on first open, not inlined into every page.

The scorer and the ViewModel are pure, so ranking is identical on the server
and in the browser:

```nim runnable
import core/search_vm

var idx: SearchIndex
idx.entries.add SearchEntry(routePath: "/routing", title: "Routing",
  summary: "Auto-discovery vs an explicit manifest.",
  headings: @["Matching and normalization"])
idx.entries.add SearchEntry(routePath: "/theming", title: "Theming",
  summary: "Design tokens.", headings: @[])

let hits = searchIndex(idx, "routing")
doAssert hits.len >= 1
doAssert hits[0].routePath == "/routing"   # ranked best-first
```

The search box itself is a small state machine -- open/close, the current
result list, and a keyboard cursor into it -- driven by pure reducers:

```nim runnable
import core/search_vm

var idx: SearchIndex
idx.entries.add SearchEntry(routePath: "/routing", title: "Routing",
  summary: "Auto-discovery.", headings: @["Matching"])

var vm = newSearchViewModel().openSearch().setQuery(idx, "routing")
doAssert vm.isOpen
doAssert vm.results.len >= 1
doAssert vm.selectedResult().routePath == "/routing"

vm = vm.closeSearch()
doAssert not vm.isOpen
```

The browser mount binds `Cmd/Ctrl+K` and `/` to open the overlay, `Esc` to
close, arrow keys to move the cursor, and `Enter` to navigate, and it
highlights matched terms in each result snippet.

## Server-side search

For a corpus too large to ship as a client index, a consumer flips
`DocsConfig.search.mode` to `smServerApi`. Each debounced query is then sent
to a server endpoint that ranks against a **pluggable backend** and returns
already-ranked results the client renders as-is. The framework ships the
backend interface plus an in-memory index backend (also used as the test
mock), a proxy backend (forwarding to an upstream JSON search service), and a
SQLite-shaped backend (the consumer runs the `SELECT`, the framework maps the
rows -- so no hard `db_sqlite` dependency).

The config toggle, the endpoint glue, and the mock backend are all pure and
dual-target:

```nim runnable
import std/strutils
import core/config
import core/search_vm
import core/server_search

# The default is the client-index path; a consumer opts into the server path.
doAssert dispatchFor(defaultServerSearchConfig()) == sdClientIndex
let serverCfg = ServerSearchConfig(mode: smServerApi,
  endpoint: "/api/search", debounceMs: 200)
doAssert dispatchFor(serverCfg) == sdServerApi

# A pluggable backend ranks a query; the mock wraps an in-memory index.
var idx: SearchIndex
idx.entries.add SearchEntry(routePath: "/routing", title: "Routing",
  summary: "x", headings: @[])
let backend = newMockBackend(idx)
doAssert backend.kind == sbkMock

# The endpoint parses ?q=...&limit= and serializes ranked results as JSON.
let body = handleSearchRequest(backend, "?q=routing&limit=5")
doAssert body.contains("\"results\"")
doAssert body.contains("/routing")
```

Keystrokes are coalesced by a pure, timestamp-free debouncer: a burst of
fast keystrokes schedules many timers but fires exactly one request -- the
last one.

```nim runnable
import core/server_search

var d = newDebouncer(200)
let firstToken = d.onInput()
let latestToken = d.onInput()
# Only the latest keystroke's token is allowed to fire.
doAssert not d.shouldFire(firstToken)
doAssert d.shouldFire(latestToken)
```

Flipping the toggle off restores the exact client-index behavior, so server
search is strictly additive.
