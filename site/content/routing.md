---
title: Routing
description: How isonim-docs resolves routes -- auto-discovery from content, or an explicit hand-authored manifest.
order: 2
---
# Routing

A **route manifest** is the single source of truth for route resolution: a
typed list of entries (pattern, canonical path, page kind, status, and
metadata) plus a typed not-found entry. Both the SSR entry and the SPA mount
entry resolve routes through the exact same manifest, so routing never forks
per target.

There are two ways to obtain a manifest: let the framework **auto-discover**
it from your `content/` dir (the default), or hand-author an **explicit**
one.

## Auto-discovery from content

`buildManifestFromContent` walks the content directory and produces one
`pkMarkdown` entry per Markdown file, bound to that file's own derived
route, plus one `pkRedirect` entry per `aliases:` frontmatter value. This is
the framework default: `buildSite`, `renderRoute`, and the SPA mount entry
all fall back to it when no manifest is passed, so a file-based site never
has to maintain a route table by hand.

The pure, in-memory half is `buildManifestFromEntries`, which turns an
already-loaded content graph into a manifest. It applies exactly one rule --
each entry's canonical path is the content file's own derived `routePath` --
so routing and navigation can never disagree:

```nim runnable
import core/content
import core/routes

let entries = @[
  parseContentEntry("---\ntitle: Home\n---\n# Home\n\nWelcome.", "index.md"),
  parseContentEntry("---\ntitle: Intro\nsection: guide\n---\n# Intro\n\nText.",
                    "guide/intro.md"),
  parseContentEntry("---\ntitle: Old\naliases: /legacy-intro\n---\n# Old\n\nX.",
                    "guide/old.md"),
]

let manifest = buildManifestFromEntries(entries)
# One real page entry per file, plus one redirect entry per alias.
doAssert manifest.entries.len == 4

# Every content page is a pkMarkdown route bound to its own file.
let home = manifest.entries[0]
doAssert home.pageKind == pkMarkdown
doAssert home.canonicalPath == "/"
doAssert home.meta.contentPath == "index.md"

# The alias became a pkRedirect entry (HTTP 301) pointing at the real route.
var redirects = 0
for e in manifest.entries:
  if e.pageKind == pkRedirect:
    inc redirects
    doAssert e.status == rsRedirect
    doAssert statusCode(e.status) == 301
doAssert redirects == 1
```

## Explicit manifests

For full control -- custom patterns, a specific page kind, or a route whose
canonical path differs from the file's derived one -- hand-author a
`RouteManifest`. `newRouteEntry` derives the canonical path and status for
you, so every entry agrees on the same normalization rules:

```nim runnable
import core/routes

let manifest = newRouteManifest(@[
  newRouteEntry("/", pkMarkdown, meta = RouteMeta(contentPath: "index.md")),
  newRouteEntry("/guide/intro", pkMarkdown,
    meta = RouteMeta(title: "Intro", contentPath: "guide/intro.md")),
])
doAssert manifest.entries.len == 2
```

Pass an explicit manifest to `buildSite` (or `renderRoute`) to override
auto-discovery entirely:

```nim runnable
import build_site
import core/config
import core/routes

let manifest = newRouteManifest(@[
  newRouteEntry("/", pkMarkdown, meta = RouteMeta(contentPath: "index.md")),
])

proc buildWithExplicitRoutes(): int =
  buildSite(contentDir = "content", manifest = manifest, cfg = docsConfig())

when isMainModule:
  discard buildWithExplicitRoutes()
```

## Matching and normalization

`matchRoute` resolves a path against the manifest, falling back to the typed
not-found entry -- it never raises and never returns a zero-value entry.
Trailing slashes and a missing leading slash are normalized away, so
`/guide/intro`, `guide/intro`, and `/guide/intro/` all match the same entry:

```nim runnable
import core/routes

let manifest = newRouteManifest(@[
  newRouteEntry("/guide/intro", pkMarkdown,
    meta = RouteMeta(title: "Intro", contentPath: "guide/intro.md")),
])

# Trailing slash + missing leading slash both normalize to the same route.
doAssert matchRoute(manifest, "/guide/intro/").entry.canonicalPath == "/guide/intro"
doAssert matchRoute(manifest, "guide/intro").entry.canonicalPath == "/guide/intro"

# An unknown path falls back to the typed not-found entry (HTTP 404).
let miss = matchRoute(manifest, "/does/not/exist")
doAssert miss.entry.pageKind == pkNotFound
doAssert statusCode(miss.entry.status) == 404
```
