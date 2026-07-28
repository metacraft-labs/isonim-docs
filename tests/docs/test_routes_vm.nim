## Tier 1 (ViewModel / pure route-contract) suite -- dual-target: both
## `nim c -r` and `nim js -r` must pass.
##
## Proves the M1 typed route contract (`src/core/routes.nim`):
##   * path normalization -- leading slash enforced, trailing slash
##     stripped except for the root itself;
##   * canonical path derivation on constructed route entries, even
##     when the caller-supplied pattern has a stray trailing slash;
##   * nested manifest lookup -- `matchRoute` resolves index and
##     nested patterns, and rejects a partial (prefix-only) match;
##   * trailing-slash normalization falls out of matching itself, not
##     just of `normalizeRoutePath` in isolation;
##   * typed not-found selection -- an unmatched path resolves to the
##     manifest's typed `notFound` entry with `rsNotFound`/404, never
##     a zero-value `RouteEntry` or a raised exception.
##
## Pure data + pure matching logic (reuses isonim's std/strutils-only
## `isonim/routing/match`), so this is exercisable identically on both
## backends without any platform/CSS imports -- see AGENTS.md's Layer 3
## rule.

import std/unittest
import ../../src/core/routes

suite "docs route contract -- typed manifest / matching (Tier 1, dual-target)":
  test "normalizeRoutePath enforces a leading slash and strips trailing slashes except the root":
    check normalizeRoutePath("/") == "/"
    check normalizeRoutePath("") == "/"
    check normalizeRoutePath("guide") == "/guide"
    check normalizeRoutePath("/guide") == "/guide"
    check normalizeRoutePath("/guide/") == "/guide"
    check normalizeRoutePath("/guide//") == "/guide"
    check normalizeRoutePath("/guide/getting-started/") == "/guide/getting-started"

  test "statusCode maps typed RouteStatus to the real HTTP status codes":
    check statusCode(rsOk) == 200
    check statusCode(rsNotFound) == 404

  test "newRouteEntry derives canonicalPath from pattern and defaults to rsOk":
    let entry = newRouteEntry("/guide/getting-started/", pkDoc)
    check entry.pattern == "/guide/getting-started/"
    check entry.canonicalPath == "/guide/getting-started"
    check entry.pageKind == pkDoc
    check entry.layout == lkDefault
    check entry.status == rsOk

  test "newRouteEntry carries caller-supplied layout and metadata through untouched":
    let meta = RouteMeta(title: "Getting Started", description: "Start here.")
    let entry = newRouteEntry("/guide/getting-started", pkDoc, lkDefault, meta)
    check entry.meta.title == "Getting Started"
    check entry.meta.description == "Start here."

  test "notFoundEntry is typed pkNotFound/rsNotFound and carries its own metadata":
    let nf = notFoundEntry()
    check nf.pageKind == pkNotFound
    check nf.status == rsNotFound
    check statusCode(nf.status) == 404
    check nf.meta.title == "Not Found"

  test "matchRoute resolves the index entry for '/'":
    let manifest = newRouteManifest(@[
      newRouteEntry("/", pkIndex),
      newRouteEntry("/guide/getting-started", pkDoc),
    ])
    let m = matchRoute(manifest, "/")
    check m.entry.pageKind == pkIndex
    check m.entry.status == rsOk
    check statusCode(m.entry.status) == 200

  test "matchRoute resolves a nested route by its full pattern":
    let manifest = newRouteManifest(@[
      newRouteEntry("/", pkIndex),
      newRouteEntry("/guide/getting-started", pkDoc),
    ])
    let m = matchRoute(manifest, "/guide/getting-started")
    check m.entry.pageKind == pkDoc
    check m.entry.canonicalPath == "/guide/getting-started"
    check m.entry.status == rsOk

  test "matchRoute normalizes a trailing slash to the same nested match":
    let manifest = newRouteManifest(@[
      newRouteEntry("/", pkIndex),
      newRouteEntry("/guide/getting-started", pkDoc),
    ])
    let withSlash = matchRoute(manifest, "/guide/getting-started/")
    let withoutSlash = matchRoute(manifest, "/guide/getting-started")
    check withSlash.entry.pageKind == withoutSlash.entry.pageKind
    check withSlash.entry.canonicalPath == withoutSlash.entry.canonicalPath
    check withSlash.entry.status == rsOk

  test "matchRoute rejects a partial (prefix-only) match against a nested pattern":
    let manifest = newRouteManifest(@[
      newRouteEntry("/", pkIndex),
      newRouteEntry("/guide/getting-started", pkDoc),
    ])
    let m = matchRoute(manifest, "/guide")
    check m.entry.pageKind == pkNotFound
    check m.entry.status == rsNotFound

  test "matchRoute falls back to the manifest's typed not-found entry for an unmatched path":
    let manifest = newRouteManifest(@[
      newRouteEntry("/", pkIndex),
      newRouteEntry("/guide/getting-started", pkDoc),
    ])
    let m = matchRoute(manifest, "/does-not-exist")
    check m.entry.pageKind == pkNotFound
    check m.entry.status == rsNotFound
    check statusCode(m.entry.status) == 404
    check m.params.len == 0

  test "matchRoute uses a caller-supplied notFound entry instead of the default":
    let customNotFound = notFoundEntry(RouteMeta(title: "Nothing Here"))
    let manifest = newRouteManifest(@[newRouteEntry("/", pkIndex)], customNotFound)
    let m = matchRoute(manifest, "/missing")
    check m.entry.meta.title == "Nothing Here"
