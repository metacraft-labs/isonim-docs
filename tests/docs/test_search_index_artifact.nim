## Tier 3-ish (real filesystem + real SSG build) M5 deliverable 2 suite --
## C-target only, mirroring `test_asset_pipeline.nim`'s split: `build_site.
## nim` is a C-target-only entry (the SSG has no meaning on the JS/SPA
## target), so this suite runs a real `buildSite` over hermetic fixtures.
##
## Proves the deferred/lazy search index end to end: the build emits the
## search index as a SEPARATE, content-hashed `search-index.<hash>.json`
## artifact at the site root (round-tripping via the client's own
## `parseSearchIndexJson`), it is NOT inlined into any served page's HTML,
## and every page's search overlay references the hashed artifact via
## `data-search-index-url` (the build-time `/search-index.json` placeholder
## having been rewritten to the hashed path exactly like the M2 asset-href
## rewrite). Together with `test_search_shortcuts_browser_mount.nim` (which
## proves the overlay fetches this lazily on first open) this closes the
## "index served as a separate hashed artifact, fetched on first open, not
## inlined" deliverable requirement.

when defined(js):
  {.error: "test_search_index_artifact is a C-target-only suite (build_site.nim is C-target-only)".}

import std/[unittest, os, strutils]
import ../../src/build_site
import ../../src/core/routes
import ../../src/core/search_vm
import ../../src/components/search_view
import ./helpers/fixture_dir

suite "docs deferred search index artifact -- real SSG build (Tier 3-ish, C-target)":
  test "buildSite emits a separate content-hashed search-index.<hash>.json, not inlined, and points the overlay at it":
    withFixtureDir:
      let assetsDir = fixtureDir / "assets"
      let outDir = fixtureDir / "out"
      writeFixtureFile(fixtureDir, "assets" / "style.css", ".docs-frame { color: red; }\n")

      let pageCount = buildSite(outDir = outDir, contentDir = "tests/fixtures/mini-site",
                                 assetsDir = assetsDir)
      check pageCount > 0

      # A single, content-hashed search-index artifact exists at the site
      # root -- its filename carries a hash between "search-index." and
      # ".json", so it is not the plain unhashed name.
      var hashedNames: seq[string] = @[]
      for kind, path in walkDir(outDir):
        let name = path.extractFilename
        if name.startsWith("search-index.") and name.endsWith(".json"):
          hashedNames.add name
      check hashedNames.len == 1
      let hashedName = hashedNames[0]
      check hashedName != "search-index.json"
      let hashPart = hashedName["search-index.".len ..< hashedName.len - ".json".len]
      check hashPart.len >= 8
      let artifactPath = outDir / hashedName
      check fileExists(artifactPath)

      # The plain, unhashed filename is never a served artifact.
      check not fileExists(outDir / "search-index.json")

      # The artifact round-trips through the client's own parser and
      # actually covers the real content graph's routes.
      let onDisk = readFile(artifactPath)
      let parsed = parseSearchIndexJson(onDisk)
      check parsed.entries.len > 0
      var routes: seq[string] = @[]
      for e in parsed.entries: routes.add e.routePath
      check "/" in routes
      check "/guide/alpha" in routes

      # Every rendered page's overlay references the HASHED artifact, and
      # the index JSON is NOT inlined into the page HTML.
      for pageRel in ["index.html", "guide/alpha/index.html"]:
        let pageHtml = readFile(outDir / pageRel)
        check (searchIndexUrlAttr & "=\"/" & hashedName & "\"") in pageHtml
        check "/search-index.json\"" notin pageHtml  # placeholder rewritten away
        check "{\"entries\":[" notin pageHtml         # the index is not inlined
        check "\"routePath\":" notin pageHtml         # no per-entry index JSON inline

  test "the emitted artifact is byte-identical to the client-serialized real index":
    withFixtureDir:
      let assetsDir = fixtureDir / "assets"
      let outDir = fixtureDir / "out"
      writeFixtureFile(fixtureDir, "assets" / "style.css", ".docs-frame { color: red; }\n")
      discard buildSite(outDir = outDir, contentDir = "tests/fixtures/mini-site",
                         assetsDir = assetsDir)

      var artifactPath = ""
      for kind, path in walkDir(outDir):
        let name = path.extractFilename
        if name.startsWith("search-index.") and name.endsWith(".json"):
          artifactPath = path
      require artifactPath.len > 0
      let manifest = buildManifestFromContent("tests/fixtures/mini-site")
      check readFile(artifactPath) ==
        searchIndexToJson(buildRealSearchIndex("tests/fixtures/mini-site", manifest))
