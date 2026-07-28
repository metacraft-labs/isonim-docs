---
title: SEO & Error Handling
description: Build-time SEO artifacts (canonical/OpenGraph/Twitter/JSON-LD, sitemap.xml, robots.txt) and the resilient 404/500 fallback pages that always retain site chrome.
order: 6
---
# SEO & Error Handling

Two cross-cutting concerns round out the render pipeline: the SEO metadata
and artifacts every page needs to be discoverable, and the error-handling
that keeps a broken render from ever serving a blank page.

## SEO artifacts

The document head carries OpenGraph and Twitter-card meta, a canonical URL
tag, and JSON-LD where it makes sense. The build also writes a `sitemap.xml`
listing every route and a `robots.txt`, both derived from the manifest -- you
saw them emitted in the [Getting Started](./getting-started.md) build output.
A page missing a `description` or `title` triggers a build **warning** (not a
silent omission), so a metadata gap is visible in the build log.

Absolute URLs (canonical, OpenGraph, the sitemap `<loc>`) are built from the
consumer's `baseUrl`. The framework never invents a host it wasn't given --
with no `baseUrl` configured, these fall back to root-relative paths:

```nim runnable
import core/config

# With a baseUrl, canonical / OpenGraph / sitemap URLs are absolute.
doAssert joinSiteUrl("https://isonim-docs.dev", "/routing") ==
  "https://isonim-docs.dev/routing"

# With none, the framework emits a root-relative path rather than a fake host.
doAssert joinSiteUrl("", "/routing") == "/routing"
```

This site sets `baseUrl: "https://isonim-docs.dev"` in its `DocsConfig`, so
its sitemap and canonical tags are absolute.

## Error handling

Route resolution never raises. An unknown path resolves to the manifest's
typed not-found entry (HTTP 404), and the rendered 404 page **retains the
site navigation** so a reader is never stranded on a chrome-less page:

```nim runnable
import core/routes

let manifest = newRouteManifest(@[
  newRouteEntry("/", pkMarkdown, meta = RouteMeta(contentPath: "index.md")),
])

# An unknown path resolves to the typed not-found entry -- never a raise.
let miss = matchRoute(manifest, "/does/not/exist")
doAssert miss.entry.pageKind == pkNotFound
doAssert statusCode(miss.entry.status) == 404
```

A render that *fails* is handled the same way: `renderRoute` returns a real
500 fallback page that retains the chrome instead of re-raising, and embedded
components are wrapped in a component-level error boundary (see
[Live Components](./components.md)) so a single throwing embed shows a
fallback while the rest of the page keeps working.
