## Tier 3-ish (real filesystem + real SSG build) M2 asset-pipeline
## suite -- C-target only, mirroring `test_content_loader.nim`'s split:
## `build_site.nim` itself is a C-target-only entry (the SSG has no
## meaning on the JS/SPA target), so this suite runs a real `buildSite`
## over hermetic fixtures rather than mocking any of it.
##
## Proves M2 corrective deliverable 3 end to end: the emitted stylesheet
## is content-hashed and Tailwind-purged against the classes the
## rendered pages actually use, `asset-manifest.json` maps the logical
## name to the hashed one, a consumer `public/` dir is copied verbatim
## (unhashed), and every rendered page's stylesheet href is rewritten to
## the hashed name -- the plain, unhashed filename is not a served
## artifact. Deliverable 1's "missing stylesheet is impossible" guard is
## exercised, unchanged, by every one of these real builds.

when defined(js):
  {.error: "test_asset_pipeline is a C-target-only suite (build_site.nim is C-target-only)".}

import std/[unittest, os, json, strutils]
import ../../src/build_site
import ./helpers/fixture_dir

suite "docs static-asset pipeline -- real SSG build (Tier 3-ish, C-target)":
  test "build_site content-hashes style.css, purges unused classes, emits a manifest, copies public/ verbatim, and rewrites HTML hrefs to the hashed name":
    withFixtureDir:
      let assetsDir = fixtureDir / "assets"
      let publicDir = fixtureDir / "public"
      let outDir = fixtureDir / "out"
      writeFixtureFile(fixtureDir, "assets" / "style.css",
        ".docs-frame { color: red; }\n" &
        ".totally-unused-test-only-class { color: blue; }\n")
      writeFixtureFile(fixtureDir, "public" / "robots.txt", "User-agent: *\n")

      let pageCount = buildSite(outDir = outDir, contentDir = "tests/fixtures/mini-site",
                                 assetsDir = assetsDir, publicDir = publicDir)
      check pageCount > 0

      # asset-manifest.json maps the logical asset path to the hashed one.
      let manifestPath = outDir / "asset-manifest.json"
      check fileExists(manifestPath)
      let manifest = parseFile(manifestPath)
      check manifest.hasKey("assets/style.css")
      let hashedRel = manifest["assets/style.css"].getStr()
      check hashedRel != "assets/style.css"
      check hashedRel.startsWith("assets" / "style.")
      check hashedRel.endsWith(".css")

      # The hashed stylesheet exists, is non-empty, kept the class a
      # rendered page uses, and dropped the one none of them do.
      let hashedCssPath = outDir / hashedRel
      check fileExists(hashedCssPath)
      let cssContent = readFile(hashedCssPath)
      check cssContent.len > 0
      check ".docs-frame" in cssContent
      check "totally-unused-test-only-class" notin cssContent

      # The plain, unhashed filename is never a served artifact.
      check not fileExists(outDir / "assets" / "style.css")

      # A consumer public/ dir is copied verbatim, unhashed.
      check fileExists(outDir / "robots.txt")
      check readFile(outDir / "robots.txt") == "User-agent: *\n"

      # Every rendered page references the hashed name, not the plain one.
      let indexHtml = readFile(outDir / "index.html")
      check ("/assets/" & hashedRel.extractFilename) in indexHtml
      check "/assets/style.css\"" notin indexHtml

  test "a missing style.css can never dangle: buildSite provisions the bundled default and still hashes+manifests it":
    withFixtureDir:
      let assetsDir = fixtureDir / "assets" # created but left empty: no style.css
      createDir(assetsDir)
      let outDir = fixtureDir / "out"
      # M1 corrective deliverable 1 (commit 15473bb): a missing/empty
      # style.css no longer aborts the build -- buildSite provisions the
      # framework's own bundled default so `stylesheetHref` is made
      # structurally unable to dangle. The build must therefore SUCCEED
      # and route the provisioned stylesheet through the same hashing +
      # manifest + purge pipeline as a consumer-supplied one.
      let pageCount = buildSite(outDir = outDir, contentDir = "tests/fixtures/mini-site",
                                 assetsDir = assetsDir)
      check pageCount > 0

      # The manifest maps the logical stylesheet to a hashed name even
      # though the consumer shipped none.
      let manifestPath = outDir / "asset-manifest.json"
      check fileExists(manifestPath)
      let manifest = parseFile(manifestPath)
      check manifest.hasKey("assets/style.css")
      let hashedRel = manifest["assets/style.css"].getStr()
      check hashedRel != "assets/style.css"
      check hashedRel.startsWith("assets" / "style.")
      check hashedRel.endsWith(".css")

      # The provisioned, hashed stylesheet exists on disk and is
      # non-empty -- the stylesheetHref never dangles.
      let hashedCssPath = outDir / hashedRel
      check fileExists(hashedCssPath)
      check readFile(hashedCssPath).len > 0

      # The plain, unhashed filename is never a served artifact.
      check not fileExists(outDir / "assets" / "style.css")

      # Every rendered page references the provisioned hashed stylesheet.
      let indexHtml = readFile(outDir / "index.html")
      check ("/assets/" & hashedRel.extractFilename) in indexHtml
      check "/assets/style.css\"" notin indexHtml
