## Tier 1/3 M4 corrective deliverable 2 companion -- dual-target: both
## `nim c -r` and `nim js -r` must pass.
##
## Proves the client-side route-resolution path soft nav uses --
## `routes.buildManifestFromEntries` fed by an in-memory content graph,
## exactly how `main_web.defaultEmbeddedManifest`/`buildRouteApp` build
## their manifest from compile-time-embedded content -- resolves the
## exact same `canonicalPath`/`pageKind`/`status`/`redirectTo`
## `matchRoute` returns as `routes.buildManifestFromContent`'s real-
## filesystem SSR manifest (`src/ssr.nim`/`src/build_site.nim`'s own
## default), for the same underlying content, across a representative
## set of paths (index, a nested doc, an alias redirect, not-found).
##
## `buildManifestFromContent` is C-target-only (no real filesystem on
## JS -- see its own docstring in `src/core/routes.nim`), so the real-
## filesystem half of this parity check is C-target-only, mirroring
## `test_manifest_from_content_renderroute.nim`'s own dual/C-only split.
## The `buildManifestFromEntries` half below it runs on both targets
## unconditionally, proving client route resolution itself -- the exact
## code path `main_web.nim`'s soft nav re-runs on every route swap --
## has no platform-specific fork and never silently 404s a real page.

import std/unittest
import ../../src/core/content
import ../../src/core/routes
when not defined(js):
  import ./helpers/fixture_dir

const fixtureRaw = @[
  ("index.md", "# Home\n\nWelcome."),
  ("guide/getting-started.md", "---\ntitle: Getting Started\n---\n# Ignored\n\nStart here."),
  ("about.md", "---\naliases: /old-about\n---\n# About\n\nAbout us."),
]

proc buildClientManifest(): RouteManifest =
  ## The exact assembly `main_web.defaultEmbeddedManifest`/`buildRouteApp`
  ## use on the JS side: an in-memory `seq[ContentEntry]` (there is no
  ## real filesystem in the browser) through `buildManifestFromEntries`.
  var entries: seq[ContentEntry] = @[]
  for (path, raw) in fixtureRaw:
    entries.add parseContentEntry(raw, path)
  buildManifestFromEntries(entries)

const representativePaths = @["/", "/guide/getting-started", "/about", "/old-about", "/missing"]

suite "client route resolution (Tier 1, dual-target)":
  test "buildManifestFromEntries resolves every representative path with a real entry, not a silent fall-through":
    let manifest = buildClientManifest()
    for path in representativePaths:
      let m = matchRoute(manifest, path)
      if path == "/missing":
        check m.entry.status == rsNotFound
      else:
        check m.entry.status != rsNotFound
    check matchRoute(manifest, "/about").entry.status == rsOk
    check matchRoute(manifest, "/old-about").entry.status == rsRedirect
    check matchRoute(manifest, "/old-about").entry.redirectTo == "/about"

when not defined(js):
  proc summarize(m: RouteMatch): tuple[canonicalPath: string, pageKind: PageKind,
                                        status: RouteStatus, redirectTo: string] =
    (m.entry.canonicalPath, m.entry.pageKind, m.entry.status, m.entry.redirectTo)

  suite "client route resolution matches the SSR manifest (Tier 3-ish, C-target)":
    test "buildManifestFromContent (SSR's real-fs manifest) and buildManifestFromEntries (client mount's manifest) resolve identically for representative paths":
      withFixtureDir:
        for (path, raw) in fixtureRaw:
          writeFixtureFile(fixtureDir, path, raw)
        let ssrManifest = buildManifestFromContent(fixtureDir)
        let clientManifest = buildClientManifest()
        for path in representativePaths:
          check summarize(matchRoute(ssrManifest, path)) == summarize(matchRoute(clientManifest, path))
