## Tier 3-ish (real filesystem) M2 content-loader suite -- C-target only,
## mirroring `test_bootstrap_renderroute.nim`/`test_routes_renderroute.nim`'s
## split: pure parsing lives in the dual-target `test_markdown_vm.nim`,
## real directory walking lives here since there's no real filesystem on
## the JS target.
##
## Proves `loadContentEntries` (`src/core/content.nim`) over a real
## hermetic fixture temp dir, never a mocked filesystem: section
## ordering, draft filtering, nested route binding, and working
## unchanged against files with no front matter at all. The equivalent
## check against the real IsoNim content corpus now lives in the
## consumer package (M1 corrective deliverable 4).

when defined(js):
  {.error: "test_content_loader is a C-target-only suite".}

import std/[unittest, sequtils]
import ../../src/core/content
import ./helpers/fixture_dir

suite "docs content loader -- real filesystem (Tier 3-ish, C-target)":
  test "loadContentEntries orders entries by section, then front matter order, then slug":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nWelcome.")
      writeFixtureFile(fixtureDir, "guide/getting-started.md",
        "---\ntitle: Getting Started\norder: 1\n---\n# Ignored\n\nStart here.")
      writeFixtureFile(fixtureDir, "guide/advanced.md",
        "---\ntitle: Advanced\norder: 2\n---\n# Ignored\n\nAdvanced stuff.")
      writeFixtureFile(fixtureDir, "about.md", "# About\n\nAbout us.")

      let entries = loadContentEntries(fixtureDir)
      check entries.len == 4
      # "" (root) sorts before "guide" alphabetically.
      check entries[0].slug == "about"
      check entries[0].routePath == "/about"
      check entries[1].slug == "index"
      check entries[1].routePath == "/"
      check entries[2].slug == "getting-started"
      check entries[2].section == "guide"
      check entries[2].routePath == "/guide/getting-started"
      check entries[3].slug == "advanced"
      check entries[3].routePath == "/guide/advanced"

  test "loadContentEntries filters out draft pages by default but can include them on request":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nWelcome.")
      writeFixtureFile(fixtureDir, "guide/wip.md",
        "---\ndraft: true\n---\n# Work In Progress\n\nNot ready yet.")

      let published = loadContentEntries(fixtureDir)
      check published.len == 1
      check published[0].slug == "index"

      let withDrafts = loadContentEntries(fixtureDir, includeDrafts = true)
      check withDrafts.len == 2
      check withDrafts.anyIt(it.slug == "wip" and it.front.draft)

  test "loadContentEntries records stable source provenance (path relative to the content root, and body line)":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/getting-started.md",
        "---\ntitle: Getting Started\n---\n# Ignored\n\nStart here.")

      let entries = loadContentEntries(fixtureDir)
      check entries.len == 1
      check entries[0].source.path == "guide/getting-started.md"
      check entries[0].source.line == 4

  test "loadContentEntries works unchanged over real content files with no front matter at all":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md",
        "# Welcome to isonim-docs\n\nNo front matter, just like M0/M1 content.")

      let entries = loadContentEntries(fixtureDir)
      check entries.len == 1
      check entries[0].front.title == ""
      check entries[0].page.title == "Welcome to isonim-docs"
      check entries[0].routePath == "/"

  # The equivalent check against the real IsoNim content corpus now lives
  # in the consumer package (M1 corrective deliverable 4:
  # ../isonim/docs/users/tests/test_content_loader.nim), since that
  # corpus is consumer content, not framework fixture data.
