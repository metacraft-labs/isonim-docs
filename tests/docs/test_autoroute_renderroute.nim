## Tier 3 (SSR / `renderRoute`) M1 corrective deliverable 2 suite --
## C-target only.
##
## Proves the "framework default" routing model: `renderRoute` called
## with NO explicit `manifest` argument auto-discovers its route table
## from `contentDir` via `routes.buildManifestFromContent` (M1 corrective
## deliverable 1), rather than falling back to the hand-authored
## `docsRouteManifest()`. Also proves the *other* routing model still
## works unchanged: an explicit `manifest` argument overrides the
## auto-discovery default, exactly like it always has for the existing
## `docsRouteManifest()`-based suites (`test_routes_renderroute.nim` and
## friends, which all now pass `docsRouteManifest()` explicitly so their
## M0/M1-specific coverage -- the hand-authored `/guide/getting-started`
## nesting that legitimately disagrees with `content.deriveRoutePath` --
## keeps exercising that exact manifest rather than silently switching
## to auto-discovery underneath them).

when defined(js):
  {.error: "test_autoroute_renderroute is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ./helpers/fixture_dir
import ./helpers/html_normalize

suite "docs SSR renderRoute -- auto-discovery default manifest (M1 corrective, C-target)":
  test "renderRoute('/') with no explicit manifest auto-discovers the fixture's index page":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Fixture Home\n\nHello from auto-discovery.")

      let (status, html) = renderRoute("/", fixtureDir)
      check status == 200

      let normalized = normalizeHtml(html)
      check normalized.contains("<div class=\"docs-frame\">")
      check normalized.contains("<h1 class=\"docs-title\">Fixture Home</h1>")

  test "renderRoute for a nested file auto-discovers its dir-derived route, with no manifest passed":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nWelcome.")
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The DSL\n\nDSL body text.")

      let (status, html) = renderRoute("/guide/dsl", fixtureDir)
      check status == 200

      let normalized = normalizeHtml(html)
      check normalized.contains("<h1 class=\"docs-title\">The DSL</h1>")

  test "a flat file's auto-discovered route is its own dir-derived path, not a hand-authored nesting":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nWelcome.")
      writeFixtureFile(fixtureDir, "getting-started.md", "# Getting Started\n\nStart here.")

      # Auto-discovery derives "/getting-started" (content.deriveRoutePath's
      # one rule) for a flat file -- unlike docsRouteManifest()'s own
      # hand-authored "/guide/getting-started" binding for the exact same
      # flat filename.
      let (flatStatus, flatHtml) = renderRoute("/getting-started", fixtureDir)
      check flatStatus == 200
      check normalizeHtml(flatHtml).contains("<h1 class=\"docs-title\">Getting Started</h1>")

      let (nestedStatus, _) = renderRoute("/guide/getting-started", fixtureDir)
      check nestedStatus == 404

  test "an explicit manifest still overrides the auto-discovery default":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nWelcome.")
      writeFixtureFile(fixtureDir, "getting-started.md", "# Getting Started\n\nStart here.")

      # Passing docsRouteManifest() explicitly resolves the same fixture's
      # flat file at ITS hand-authored nested path instead of the
      # auto-discovery default's own "/getting-started" -- proving the
      # explicit-manifest routing model still fully works, unchanged.
      let (status, html) = renderRoute("/guide/getting-started", fixtureDir, docsRouteManifest())
      check status == 200
      check normalizeHtml(html).contains("<h1 class=\"docs-title\">Getting Started</h1>")

  test "renderRoute('/missing') with no explicit manifest still renders the typed not-found page":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nWelcome.")

      let (status, html) = renderRoute("/missing", fixtureDir)
      check status == 404
      check normalizeHtml(html).contains("docs-not-found")
