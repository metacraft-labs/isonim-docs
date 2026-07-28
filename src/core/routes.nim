## isonim-docs Layer 3 — typed route contract for docs pages.
##
## Single source of truth for route resolution: a manifest of typed
## entries (pattern, canonical path, page kind, layout, status,
## metadata) plus a typed not-found entry. Pure data + pure matching
## logic (reuses isonim's `isonim/routing/match` pattern engine, itself
## std/strutils-only) -- zero platform/CSS imports per the AGENTS.md
## Layer 3 rule, so both the SSR entry (`src/ssr.nim`) and the JS mount
## entry (`src/main_web.nim`) can resolve routes through the exact same
## code path instead of forking routing logic per target.

import isonim/routing/match
import ./content

type
  PageKind* = enum
    pkIndex
    pkDoc
    pkNotFound
    pkMarkdown ## A real markdown page rendered through the M2 content
               ## loader + markdown-to-ViewModel pipeline (M2 deliverable
               ## 4), as opposed to `pkDoc`/`pkIndex`'s M0/M1
               ## plain-text-body rendering. Kept distinct rather than
               ## repurposing `pkDoc` so the existing M0/M1 routes/tests
               ## keep their exact original rendering behavior unchanged.
    pkRedirect ## M3 deliverable 3's alias entries: an old, renamed page's
               ## route path, kept resolvable rather than going 404. Never
               ## bound to a `meta.contentPath` -- there is no content to
               ## load, only `RouteEntry.redirectTo` to follow.
    pkApiReference ## M7 deliverable 2: a Stripe-style three-column OpenAPI
                   ## REST reference page. Its `meta.contentPath` binds to a
                   ## consumer-supplied OpenAPI v3 spec file (YAML or JSON,
                   ## `core/openapi.ingestOpenApi`), not a markdown page --
                   ## the framework itself ships no spec, the content is
                   ## consumer-supplied like every other page kind. Added at
                   ## the END of the enum so every existing entry keeps its
                   ## ordinal (several router tests compare `pageKind`s).
    pkSymbolReference ## M8 deliverable 1: a library (Nim) API reference
                      ## page. Its `meta.contentPath` binds to a
                      ## consumer-supplied Nim SOURCE file (`.nim`,
                      ## `core/nimdoc.parseNimDoc`), rendered as a two-column
                      ## symbol index + per-symbol reference. Like
                      ## `pkApiReference`, the framework ships no source of
                      ## its own -- the documented code is consumer-supplied.
                      ## Added at the END of the enum so every existing
                      ## entry keeps its ordinal.
    pkTutorial ## M10 deliverable 1: an interactive tutorial page. Its
               ## `meta.contentPath` binds to a consumer-supplied markdown
               ## file whose H2 (`##`) sections are the tutorial's ordered
               ## STEPS; the page renders the markdown body plus the
               ## `tutorial_vm`-driven step-progress rail (checkmarks +
               ## localStorage completion + reset), with prev/next links to
               ## the sibling tutorials of the same series. Like the other
               ## specialised kinds, added at the END of the enum so every
               ## existing entry keeps its ordinal.

  LayoutKind* = enum
    lkDefault

  RouteStatus* = enum
    rsOk
    rsNotFound
    rsRedirect ## `pkRedirect` entries resolve to this status -- a real
               ## HTTP 301 ("moved permanently"), the correct code for a
               ## renamed docs page, not a 404 or a silent 200.

  RouteMeta* = object
    title*: string
    description*: string
    contentPath*: string ## Real content file this route's page loads from,
                         ## relative to the content dir (e.g. "index.md").
                         ## Unused by `notFoundEntry`/`newRedirectEntry` --
                         ## there is no file to load for either.

  RouteEntry* = object
    pattern*: string
    canonicalPath*: string
    pageKind*: PageKind
    layout*: LayoutKind
    status*: RouteStatus
    meta*: RouteMeta
    redirectTo*: string ## For `pkRedirect` entries only: the canonical
                        ## route path (already-normalized) this alias
                        ## resolves to. Empty for every other page kind.

  RouteManifest* = object
    entries*: seq[RouteEntry]
    notFound*: RouteEntry

  RouteMatch* = object
    entry*: RouteEntry
    params*: seq[(string, string)]

proc normalizeRoutePath*(path: string): string =
  ## Normalizes a route path: ensures a leading "/" and strips any
  ## trailing "/" except for the root path itself, so "guide",
  ## "/guide/", and "/guide//" all normalize to the same "/guide".
  var p = path
  if p.len == 0 or p[0] != '/':
    p = "/" & p
  while p.len > 1 and p[^1] == '/':
    p = p[0 ..< p.len - 1]
  result = p

proc statusCode*(status: RouteStatus): int =
  ## Maps a typed `RouteStatus` to the real HTTP status code it stands
  ## for -- the one place that mapping lives, so SSR and JS agree.
  case status
  of rsOk: 200
  of rsNotFound: 404
  of rsRedirect: 301

proc newRouteEntry*(pattern: string; pageKind: PageKind;
                     layout: LayoutKind = lkDefault;
                     meta: RouteMeta = RouteMeta()): RouteEntry =
  ## Builds a real (matchable) manifest entry. `canonicalPath` and
  ## `status` are derived, not caller-supplied, so every entry in a
  ## manifest agrees on the same normalization and status rules.
  RouteEntry(pattern: pattern, canonicalPath: normalizeRoutePath(pattern),
             pageKind: pageKind, layout: layout, status: rsOk, meta: meta)

proc notFoundEntry*(meta: RouteMeta = RouteMeta(title: "Not Found")): RouteEntry =
  ## The typed not-found entry a manifest falls back to. It isn't
  ## addressable by its own pattern -- it's only ever reached when no
  ## real entry matches -- so it deliberately carries no canonical path
  ## of its own.
  RouteEntry(pattern: "", canonicalPath: "", pageKind: pkNotFound,
             layout: lkDefault, status: rsNotFound, meta: meta)

proc newRedirectEntry*(pattern: string; redirectTo: string;
                        meta: RouteMeta = RouteMeta()): RouteEntry =
  ## Builds a real (matchable) alias entry: `pattern` is the old, renamed
  ## page's route path, `redirectTo` the canonical route path it now
  ## resolves to. Mirrors `newRouteEntry`'s own normalization so an
  ## alias's `canonicalPath` and its eventual target are never compared
  ## in two different shapes.
  RouteEntry(pattern: pattern, canonicalPath: normalizeRoutePath(pattern),
             pageKind: pkRedirect, layout: lkDefault, status: rsRedirect,
             meta: meta, redirectTo: normalizeRoutePath(redirectTo))

proc newRouteManifest*(entries: seq[RouteEntry];
                        notFound: RouteEntry = notFoundEntry()): RouteManifest =
  RouteManifest(entries: entries, notFound: notFound)

proc matchRoute*(manifest: RouteManifest; path: string): RouteMatch =
  ## Resolves `path` against the manifest. Trailing-slash normalization
  ## falls out of `matchPath` itself (it splits both the pattern and
  ## the path into non-empty segments before comparing, so "/guide/"
  ## and "/guide" match identically) rather than needing a separate
  ## pre-normalization step here. Falls back to the manifest's typed
  ## not-found entry -- never raises, never returns a zero-value
  ## `RouteEntry`.
  for entry in manifest.entries:
    let m = matchPath(parsePattern(entry.pattern), path)
    if m.matched:
      return RouteMatch(entry: entry, params: m.params)
  result = RouteMatch(entry: manifest.notFound, params: @[])

proc docsRouteManifest*(): RouteManifest =
  ## The real docs site's route manifest -- every real, addressable page
  ## bound to the real content file under `content/` it renders from via
  ## `RouteMeta.contentPath`. The one place route-to-content bindings
  ## live, so both the SSR entry (`src/ssr.nim`) and the JS mount entry
  ## (`src/main_web.nim`) resolve the exact same routes against the exact
  ## same content instead of forking the binding per target.
  ##
  ## The `/` and `/guide/getting-started` entries are M0/M1's original
  ## `pkIndex`/`pkDoc` routes, kept byte-for-byte unchanged -- several
  ## M0/M1 tests resolve them through this exact manifest (via each
  ## test's own hermetic fixture content) and assert on their original
  ## plain-text-body rendering shape. The `pkMarkdown` entries below are
  ## M2 deliverable 4's real markdown pages, added to this same manifest
  ## (not a separate one) so route matching itself never forks.
  newRouteManifest(@[
    newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
    newRouteEntry("/guide/getting-started", pkDoc,
      meta = RouteMeta(title: "Getting Started", contentPath: "getting-started.md")),
    newRouteEntry("/guide/install-setup", pkMarkdown,
      meta = RouteMeta(title: "Install & Setup", contentPath: "guide/install-setup.md")),
    newRouteEntry("/guide/signals-effects", pkMarkdown,
      meta = RouteMeta(title: "Signals & Effects", contentPath: "guide/signals-effects.md")),
    newRouteEntry("/guide/dsl", pkMarkdown,
      meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
    newRouteEntry("/guide/ssr-basics", pkMarkdown,
      meta = RouteMeta(title: "SSR Basics", contentPath: "guide/ssr-basics.md")),
    newRouteEntry("/guide/testing-strategy", pkMarkdown,
      meta = RouteMeta(title: "Testing Strategy", contentPath: "guide/testing-strategy.md")),
    newRouteEntry("/editor/overview", pkMarkdown,
      meta = RouteMeta(title: "Editor Overview", contentPath: "editor/overview.md")),
    newRouteEntry("/editor/workspace", pkMarkdown,
      meta = RouteMeta(title: "Editor Workspace Model", contentPath: "editor/workspace.md")),
    newRouteEntry("/editor/browser-mount", pkMarkdown,
      meta = RouteMeta(title: "Editor Browser Mount Contract", contentPath: "editor/browser-mount.md")),
    newRouteEntry("/editor/integration", pkMarkdown,
      meta = RouteMeta(title: "Editor Consumer Integration", contentPath: "editor/integration.md")),
    newRouteEntry("/faq", pkMarkdown,
      meta = RouteMeta(title: "FAQ", contentPath: "faq.md")),
  ])

# --- M1 (corrective) deliverable 1: auto-discovered manifests ----------
##
## `docsRouteManifest()` above hand-lists every route with its own
## literal pattern string, which is how it was able to bind the flat
## `getting-started.md` file to a nested `/guide/getting-started`
## pattern -- a canonical path that disagrees with this same file's own
## `content.deriveRoutePath`-derived route (`/getting-started`; see
## `navigation_vm`'s module docstring for the M0/M1 history of that
## disagreement). `buildManifestFromEntries`/`buildManifestFromContent`
## below are the reconciled alternative for a framework-default,
## file-based site: every entry's `canonicalPath` is set directly from
## `ContentEntry.routePath`, i.e. `content.deriveRoutePath(section,
## slug)` -- the *one* place a content file's route is decided. Because
## `canonicalPath` (not a second, independently-derived path) is also
## what `navigation_vm.navPage` links every sidebar/breadcrumb/prev-next
## entry to, routing and navigation can no longer disagree for a manifest
## built this way -- there is only the one rule left to apply.

proc buildManifestFromEntries*(entries: seq[ContentEntry]): RouteManifest =
  ## Pure assembly step: turns an already-loaded content graph (typically
  ## `content.loadContentEntries`'s output, but any hand-built
  ## `seq[ContentEntry]` works -- this proc never touches a filesystem)
  ## into a `RouteManifest` with one `pkMarkdown` entry per content file,
  ## bound to that file's own `routePath`/`source.path`, plus one
  ## `pkRedirect` entry per authored `aliases:` front matter value
  ## (mirrors `references.buildAliasRouteEntries`'s own
  ## `newRedirectEntry(alias, canonicalPath)` call, so a statically-baked
  ## alias entry and a dynamically-built one always agree on shape).
  ## Every entry renders through the markdown pipeline (`pkMarkdown`),
  ## including what `docsRouteManifest()` still special-cases as
  ## `pkIndex`/`pkDoc` -- a content-agnostic framework has no page that
  ## is a priori special, index pages included.
  var routeEntries: seq[RouteEntry] = @[]
  for entry in entries:
    let meta = RouteMeta(title: entry.page.title, description: entry.front.description,
                          contentPath: entry.source.path)
    routeEntries.add newRouteEntry(entry.routePath, pkMarkdown, meta = meta)
    for alias in entry.front.aliases:
      routeEntries.add newRedirectEntry(alias, entry.routePath)
  newRouteManifest(routeEntries)

when not defined(js):
  proc buildManifestFromContent*(contentDir: string; includeDrafts: bool = false): RouteManifest =
    ## The real-filesystem counterpart to `buildManifestFromEntries`:
    ## walks `contentDir` via `content.loadContentEntries` (itself built
    ## on `discoverContentSlugs`/`deriveSection`/`deriveRoutePath`) and
    ## assembles the result the exact same way. C-target only, for the
    ## same reason `loadContentEntries` is -- there is no real filesystem
    ## to walk on the JS target.
    buildManifestFromEntries(loadContentEntries(contentDir, includeDrafts))
