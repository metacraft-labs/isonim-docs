## Tier 3-ish (real filesystem) companion to `test_manifest_from_content.nim`
## -- C-target only, mirroring `test_content_loader.nim`'s own split: pure
## assembly logic lives in the dual-target suite, real directory walking
## lives here since there's no real filesystem on the JS target.
##
## Proves `buildManifestFromContent` (`src/core/routes.nim`) over a real
## fixture directory (nested pages + an index + an alias). The equivalent
## check against the real IsoNim content corpus now lives in the consumer
## package (M1 corrective deliverable 4).

when defined(js):
  {.error: "test_manifest_from_content_renderroute is a C-target-only suite".}

import std/[unittest]
import ../../src/core/content
import ../../src/core/routes
import ./helpers/fixture_dir

suite "buildManifestFromContent -- real filesystem (Tier 3-ish, C-target)":
  test "walks a real content dir and yields one pkMarkdown entry per file plus alias redirects":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nWelcome.")
      writeFixtureFile(fixtureDir, "guide/getting-started.md",
        "---\ntitle: Getting Started\norder: 1\n---\n# Ignored\n\nStart here.")
      writeFixtureFile(fixtureDir, "about.md",
        "---\naliases: /old-about\n---\n# About\n\nAbout us.")

      let manifest = buildManifestFromContent(fixtureDir)
      var byRoute: seq[(string, RouteEntry)] = @[]
      for entry in manifest.entries: byRoute.add (entry.canonicalPath, entry)

      var indexEntry, guideEntry, aboutEntry, redirectEntry: RouteEntry
      var foundIndex, foundGuide, foundAbout, foundRedirect = false
      for (path, entry) in byRoute:
        if path == "/":
          indexEntry = entry
          foundIndex = true
        elif path == "/guide/getting-started":
          guideEntry = entry
          foundGuide = true
        elif path == "/about":
          aboutEntry = entry
          foundAbout = true
        elif path == "/old-about":
          redirectEntry = entry
          foundRedirect = true
      check foundIndex and foundGuide and foundAbout and foundRedirect

      check indexEntry.meta.contentPath == "index.md"
      check guideEntry.meta.contentPath == "guide/getting-started.md"
      check guideEntry.meta.title == "Getting Started"
      check aboutEntry.meta.contentPath == "about.md"
      check redirectEntry.pageKind == pkRedirect
      check redirectEntry.redirectTo == "/about"

  test "drafts are excluded by default, exactly like loadContentEntries":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nWelcome.")
      writeFixtureFile(fixtureDir, "wip.md", "---\ndraft: true\n---\n# WIP\n\nNot ready.")

      let manifest = buildManifestFromContent(fixtureDir)
      check manifest.entries.len == 1

      let withDrafts = buildManifestFromContent(fixtureDir, includeDrafts = true)
      check withDrafts.entries.len == 2

  # The equivalent check against the real IsoNim content corpus now
  # lives in the consumer package (M1 corrective deliverable 4:
  # ../isonim/docs/users/tests/test_manifest_from_content.nim), since
  # that corpus is consumer content, not framework fixture data.
