## Tier 3 (SSR / `renderRoute` + build-gate) M3 references suite --
## C-target only.
##
## Proves M3 deliverable 2 wired all the way into the real rendering
## shell and a real build-time gate: `renderRoute` emits correctly
## resolved cross-page/anchor-fragment links in the final HTML (the same
## `references.makeContentPathResolver` both rendering and validation
## share, so a rendered href and its own validation target never
## disagree -- see `src/ssr.nim`'s `renderRoute` and
## `references.nim`'s module docstring), and `checkContentGraph`/
## `validateContentGraph` -- the whole-graph build gate `src/check_links.nim`
## wires into `just docs-smoke` -- flag every broken internal reference
## (missing page, missing anchor, duplicate route) with the referencing
## page's own real `file:line` source provenance instead of letting it
## degrade silently at runtime.

when defined(js):
  {.error: "test_references_renderroute is a C-target-only suite".}

import std/[unittest, tables, strutils]
import ../../src/ssr
import ../../src/core/routes
import ../../src/core/references
import ./helpers/fixture_dir
import ./helpers/html_normalize

suite "docs SSR renderRoute -- reference links (Tier 3, C-target)":
  test "renderRoute emits a correctly resolved cross-page link and an anchor-fragment link in the final HTML":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", """# The ui DSL

## Elements

Body text.
""")
      writeFixtureFile(fixtureDir, "guide/other.md", """# Other Guide

See [the DSL guide](./dsl.md) and its [elements section](./dsl.md#elements) directly.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(title: "Other Guide", contentPath: "guide/other.md")),
      ])

      let (status, html) = renderRoute("/guide/other", fixtureDir, manifest)
      check status == 200
      let normalized = normalizeHtml(html)
      check normalized.contains("href=\"/guide/dsl\"")
      check normalized.contains("href=\"/guide/dsl#elements\"")

suite "docs references -- checkContentGraph over a real fixture content dir (Tier 3, C-target)":
  test "a fully cross-linked real fixture graph has no reference issues":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\n## Elements\n\nBody.")
      writeFixtureFile(fixtureDir, "guide/other.md",
        "# Other Guide\n\nSee [the DSL guide](./dsl.md#elements) for more.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(contentPath: "guide/other.md")),
      ])
      check checkContentGraph(fixtureDir, manifest).len == 0

  test "checkContentGraph flags a broken page reference with the referencing file's own source location":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/other.md",
        "# Other Guide\n\nSee [a missing page](./missing.md) for more.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(contentPath: "guide/other.md")),
      ])
      let issues = checkContentGraph(fixtureDir, manifest)
      check issues.len == 1
      check issues[0].kind == riUnknownRoute
      check issues[0].sourcePath == "guide/other.md"
      check issues[0].targetHref == "/guide/missing"

  test "checkContentGraph flags a broken anchor fragment with the referencing file's own source location":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\n## Elements\n\nBody.")
      writeFixtureFile(fixtureDir, "guide/other.md",
        "# Other Guide\n\nSee [signals](./dsl.md#signals) for more.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(contentPath: "guide/other.md")),
      ])
      let issues = checkContentGraph(fixtureDir, manifest)
      check issues.len == 1
      check issues[0].kind == riUnknownAnchor
      check issues[0].sourcePath == "guide/other.md"
      check issues[0].targetHref == "/guide/dsl#signals"

  test "checkContentGraph flags two content files that derive the exact same route path":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide.md", "# Guide\n\nBody.")
      writeFixtureFile(fixtureDir, "guide/index.md", "# Guide Home\n\nBody.")
      let manifest = newRouteManifest(@[])
      let issues = checkContentGraph(fixtureDir, manifest)
      check issues.len == 1
      check issues[0].kind == riDuplicateRoute

  test "a link to a redirect/alias source resolves through the alias table instead of being flagged (redirect mapping)":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\nBody.")
      writeFixtureFile(fixtureDir, "guide/other.md",
        "# Other Guide\n\nSee [the renamed guide](./old-dsl.md) for more.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(contentPath: "guide/other.md")),
      ])
      let aliases = {"/guide/old-dsl": "/guide/dsl"}.toTable
      check checkContentGraph(fixtureDir, manifest, aliases = aliases).len == 0

suite "docs references -- validateContentGraph fails the build with actionable source locations (Tier 3, C-target)":
  test "validateContentGraph raises BrokenReferenceError citing file:line for a broken reference, never degrading silently":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/other.md",
        "# Other Guide\n\nSee [a missing page](./missing.md) for more.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(contentPath: "guide/other.md")),
      ])
      expect(BrokenReferenceError):
        validateContentGraph(fixtureDir, manifest)
      try:
        validateContentGraph(fixtureDir, manifest)
        fail()
      except BrokenReferenceError as e:
        check e.issues.len == 1
        check e.msg.contains("guide/other.md:")
        check e.msg.contains("/guide/missing")

  test "validateContentGraph does not raise for a fixture graph with no broken references":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\nBody.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
      ])
      validateContentGraph(fixtureDir, manifest)

# The equivalent check against the real IsoNim content corpus +
# docsRouteManifest() now lives in the consumer package (M1 corrective
# deliverable 4: ../isonim/docs/users/tests/test_references.nim), since
# that corpus is consumer content, not framework fixture data.
