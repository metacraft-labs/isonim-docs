## Tier 3 (SSR / `renderRoute`) M4 search suite -- C-target only.
##
## Proves M4 deliverable 1 wired all the way into the real rendering
## shell and the real build: `renderRoute` embeds a real search
## bootstrap payload (the real, site-wide search index, serialized as
## JSON) into every served page -- real routes, `pkMarkdown` routes,
## and the typed not-found page alike -- built off the exact same real
## content graph (`RouteManifest` + real `contentDir`) every other M2/
## M3 real-content-graph builder above it uses; and
## `writeSearchIndexArtifact` writes that same index out as a real,
## on-disk build artifact.

when defined(js):
  {.error: "test_search_renderroute is a C-target-only suite".}

import std/[unittest, strutils, os]
import ../../src/ssr
import ../../src/core/routes
import ../../src/core/search_vm
import ../../src/components/search_view
import ./helpers/fixture_dir
import ./helpers/html_normalize

suite "docs SSR renderRoute -- deferred search overlay, NOT an inline index (Tier 3, C-target)":
  ## M5 deliverable 2 superseded M4's inline JSON bootstrap island: the
  ## served page now carries only the keyboard-triggered search overlay
  ## (with the build-time `defaultSearchIndexUrl` placeholder the SSG
  ## rewrites to the hashed `/search-index.<hash>.json` artifact), never
  ## the index itself. The index-not-inlined half is proven end to end
  ## (through a real `buildSite` + hashed artifact) in
  ## `test_search_index_artifact.nim`; here we pin what `renderRoute`
  ## itself emits.
  test "renderRoute renders the search overlay with the deferred index URL placeholder, and NO inline index, for a pkMarkdown page":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      writeFixtureFile(fixtureDir, "guide/dsl.md", """# The ui DSL

## Elements

Body text about elements.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/dsl", pkMarkdown,
          meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
      ])
      let (status, html) = renderRoute("/guide/dsl", fixtureDir, manifest)
      check status == 200
      let normalized = normalizeHtml(html)
      # the keyboard overlay is present and points at the deferred artifact
      # via the build-time placeholder URL the SSG rewrites to the hash.
      check normalized.contains("class=\"" & searchOverlayClass & "\"")
      check normalized.contains(searchIndexUrlAttr & "=\"" & defaultSearchIndexUrl & "\"")
      # the index is NOT inlined: no M4 bootstrap island, no per-entry JSON.
      check not normalized.contains("id=\"" & searchBootstrapScriptId & "\"")
      check not normalized.contains("{\"entries\":[")
      check not normalized.contains("\"routePath\":")
      check normalized.endsWith("</body></html>")

  test "renderRoute renders the deferred search overlay for a non-pkMarkdown (M0/M1-shape) page too":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
      ])
      let (status, html) = renderRoute("/", fixtureDir, manifest)
      check status == 200
      let normalized = normalizeHtml(html)
      check normalized.contains("class=\"" & searchOverlayClass & "\"")
      check normalized.contains(searchIndexUrlAttr & "=\"" & defaultSearchIndexUrl & "\"")
      check not normalized.contains("{\"entries\":[")

  test "renderRoute renders the deferred search overlay for the typed not-found page too, without crashing on a nonexistent contentDir":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/example", pkMarkdown,
        meta = RouteMeta(title: "Example Guide", contentPath: "guide/example.md")),
    ])
    let (status, html) = renderRoute("/missing", "/nonexistent-dir-should-not-be-read", manifest)
    check status == 404
    let normalized = normalizeHtml(html)
    check normalized.contains("class=\"" & searchOverlayClass & "\"")
    check normalized.contains(searchIndexUrlAttr & "=\"" & defaultSearchIndexUrl & "\"")
    check not normalized.contains("{\"entries\":[") # never an inline index, even on the 404

  test "the deferred index artifact indexes an authored page's front matter aliases":
    ## Alias searchability now lives in the separate artifact, not an
    ## inline payload -- assert it on the exact serialization the SSG
    ## writes to `search-index.<hash>.json`.
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      writeFixtureFile(fixtureDir, "guide/dsl.md", """---
aliases: /old-dsl-guide
---
# The ui DSL

Body.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/dsl", pkMarkdown,
          meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
      ])
      let indexJson = searchIndexToJson(buildRealSearchIndex(fixtureDir, manifest))
      check indexJson.contains("\"aliases\":[\"/old-dsl-guide\"]")
      # and it never leaks into the served page's HTML.
      let (_, html) = renderRoute("/guide/dsl", fixtureDir, manifest)
      check not normalizeHtml(html).contains("/old-dsl-guide")

suite "docs search build artifact -- writeSearchIndexArtifact (Tier 3, C-target)":
  test "writeSearchIndexArtifact writes a real, on-disk search-index.json built off the real content graph":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\n## Elements\n\nBody.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/dsl", pkMarkdown,
          meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
      ])
      let outDir = fixtureDir / "build-out"
      let artifactPath = writeSearchIndexArtifact(fixtureDir, manifest, outDir)
      check artifactPath == outDir / "search-index.json"
      check fileExists(artifactPath)
      let onDisk = readFile(artifactPath)
      check onDisk == searchIndexToJson(buildRealSearchIndex(fixtureDir, manifest))
      check onDisk.contains("\"routePath\":\"/guide/dsl\"")
      check onDisk.contains("\"headings\":[\"Elements\"]")

  test "writeSearchIndexArtifact creates the output directory if it doesn't already exist":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
      ])
      let outDir = fixtureDir / "nested" / "out"
      check not dirExists(outDir)
      discard writeSearchIndexArtifact(fixtureDir, manifest, outDir)
      check dirExists(outDir)
