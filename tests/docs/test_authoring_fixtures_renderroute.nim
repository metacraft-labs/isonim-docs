## Tier 3 (SSR / `renderRoute` + build-gate) M3 authoring-edge-case suite
## -- C-target only.
##
## M3 deliverable 5: real, on-disk authoring fixtures (never a mocked
## filesystem, per the M0 harness rule -- `helpers/fixture_dir.nim`) for
## the four edge cases the milestone names by name, each driven through
## the real build gate (`references.checkContentGraph`/
## `validateContentGraph`, the same `src/check_links.nim` wires into
## `just docs-smoke`) and/or the real rendering shell (`ssr.renderRoute`)
## rather than the pure in-memory data `test_authoring_fixtures.nim` and
## the earlier M3 iterations' own suites already cover:
##
## - Duplicate slugs and missing anchors are already-implemented build
##   FAILURE modes (M3 deliverable 2); this file's job is to prove they
##   fail a real, file-backed build with actionable `file:line`
##   provenance, not just a hand-built in-memory fixture.
## - Circular nav placement and stale aliases are *not* build failures by
##   design (see `test_authoring_fixtures.nim`'s own docstring for the
##   design decision and the M3 iteration notes it closes) -- this file
##   proves that tolerance holds through the real rendering shell too:
##   a self-looping breadcrumb still renders correctly, and a stale alias
##   never breaks or hijacks a real route's own page.

when defined(js):
  {.error: "test_authoring_fixtures_renderroute is a C-target-only suite".}

import std/[unittest, os, strutils]
import ../../src/ssr
import ../../src/core/routes
import ../../src/core/references
import ./helpers/fixture_dir
import ./helpers/html_normalize

suite "docs authoring edge cases -- duplicate slugs fail the build (Tier 3, C-target)":
  test "validateContentGraph fails the build for two real content files whose authored slug: front matter collides":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/alpha.md", """---
slug: shared
---
# Alpha

Body.
""")
      writeFixtureFile(fixtureDir, "guide/beta.md", """---
slug: shared
---
# Beta

Body.
""")
      let manifest = newRouteManifest(@[])
      let issues = checkContentGraph(fixtureDir, manifest)
      check issues.len == 1
      check issues[0].kind == riDuplicateRoute
      check issues[0].targetHref == "/guide/shared"
      check issues[0].sourcePath in ["guide/alpha.md", "guide/beta.md"]

      expect(BrokenReferenceError):
        validateContentGraph(fixtureDir, manifest)
      try:
        validateContentGraph(fixtureDir, manifest)
        fail()
      except BrokenReferenceError as e:
        check e.issues.len == 1
        check e.msg.contains(".md:")
        check e.msg.contains("/guide/shared")

suite "docs authoring edge cases -- missing anchors fail the build (Tier 3, C-target)":
  test "validateContentGraph fails the build for a real content file linking to its own missing same-page anchor":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", """# The ui DSL

See [the elements section](#elements) below.

## Basics

Body.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
      ])
      let issues = checkContentGraph(fixtureDir, manifest)
      check issues.len == 1
      check issues[0].kind == riUnknownAnchor
      check issues[0].sourcePath == "guide/dsl.md"
      check issues[0].targetHref == "#elements"

      try:
        validateContentGraph(fixtureDir, manifest)
        fail()
      except BrokenReferenceError as e:
        check e.msg.contains("guide/dsl.md:")
        check e.msg.contains("#elements")

suite "docs authoring edge cases -- circular nav placement renders correctly (Tier 3, C-target)":
  test "renderRoute for a real section index page produces a self-referencing breadcrumb without crashing, looping, or dropping either nav landmark":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/index.md", "# Guide Home\n\nBody.")
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\nBody.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide", pkMarkdown, meta = RouteMeta(title: "Guide Home", contentPath: "guide/index.md")),
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
      ])

      let (status, html) = renderRoute("/guide", fixtureDir, manifest)
      check status == 200
      let normalized = normalizeHtml(html)
      # The section crumb ("Guide") is a live link back to the very page
      # being rendered -- the intentional self-loop.
      check normalized.contains("<a href=\"/guide\">Guide</a>")
      # The current-page crumb ("Guide Home") renders as the non-link
      # aria-current marker, not a second copy of the same link.
      check normalized.contains("aria-current=\"page\">Guide Home</span>")
      # The sidebar independently agrees this same route is the active page.
      check normalized.contains("aria-current=\"page\">Guide Home</a>")

suite "docs authoring edge cases -- stale aliases never break or hijack a route (Tier 3, C-target)":
  test "renderRoute 404s a stale alias authored on content the manifest carries no entry for, instead of crashing":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\nBody.")
      writeFixtureFile(fixtureDir, "guide/draft.md", """---
aliases: /old-draft
---
# Draft

Body.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
        # deliberately no entry for guide/draft.md: its alias is stale/unbound
      ])
      let (status, _) = renderRoute("/old-draft", fixtureDir, manifest)
      check status == 404

  test "renderRoute never lets a stale alias whose old path collides with a live route hijack that route":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\nBody.")
      writeFixtureFile(fixtureDir, "guide/other.md", """---
aliases: /guide/dsl
---
# Other Guide

Body.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(contentPath: "guide/other.md")),
      ])
      let (status, html) = renderRoute("/guide/dsl", fixtureDir, manifest)
      check status == 200
      check normalizeHtml(html).contains("The ui DSL")

      let (otherStatus, otherHtml) = renderRoute("/guide/other", fixtureDir, manifest)
      check otherStatus == 200
      check normalizeHtml(otherHtml).contains("Other Guide")

      check checkContentGraph(fixtureDir, manifest).len == 0
