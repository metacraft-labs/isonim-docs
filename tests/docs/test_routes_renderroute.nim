## Tier 3 (SSR / `renderRoute`) M1 routing suite -- C-target only.
##
## Proves `renderRoute` is the real, manifest-driven M1 framework surface
## (`src/core/routes.docsRouteManifest`, not a single hardcoded pattern):
## the index page, a nested route bound to its own content file,
## trailing-slash normalization, and the typed not-found page -- each
## against a real hermetic fixture content dir (a real temp directory,
## not the checked-in `content/` dir) with stable normalized-HTML
## snapshots. `test_bootstrap_renderroute.nim` still covers M0's base
## guarantees (stability, filesystem-untouched 404) against the same
## `renderRoute`; this suite is the M1-specific coverage the milestone's
## deliverable calls out explicitly.

when defined(js):
  {.error: "test_routes_renderroute is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ./helpers/fixture_dir
import ./helpers/html_normalize

suite "docs SSR renderRoute -- manifest-driven routing (Tier 3, C-target)":
  test "renderRoute('/') renders the index page through the real rendering shell":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md",
        "# Fixture Home\n\nHello from a real fixture file.")
      writeFixtureFile(fixtureDir, "getting-started.md",
        "# Getting Started\n\nStart here.")

      let (status, html) = renderRoute("/", fixtureDir, docsRouteManifest())
      check status == 200

      let normalized = normalizeHtml(html)
      check normalized.startsWith("<html>")
      check normalized.contains("</head><body>")
      check not normalized.contains("<head><head>")
      check normalized.contains("<div class=\"docs-frame\">")
      check normalized.contains("<header id=\"docs-region-header\" class=\"docs-header\">")
      check normalized.contains("<h1 class=\"docs-title\">Fixture Home</h1>")
      check normalized.contains("<nav id=\"docs-region-nav\" class=\"docs-nav\">")
      check normalized.contains("<main id=\"docs-region-main\" class=\"docs-main\" tabindex=\"-1\">")
      check normalized.contains("<div class=\"docs-body\">Hello from a real fixture file.</div>")
      check normalized.contains("<footer id=\"docs-region-footer\" class=\"docs-footer\">")

  test "renderRoute('/guide/getting-started') renders the nested route from its own bound content file":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nHome body.")
      writeFixtureFile(fixtureDir, "getting-started.md",
        "# Getting Started\n\nStart here.")

      let (status, html) = renderRoute("/guide/getting-started", fixtureDir, docsRouteManifest())
      check status == 200

      let normalized = normalizeHtml(html)
      check normalized.contains("<h1 class=\"docs-title\">Getting Started</h1>")
      check normalized.contains("<div class=\"docs-body\">Start here.</div>")
      # Proves the nested route loaded its own bound file, not the index's,
      # by checking the page's own body region specifically -- not a bare
      # whole-page substring check, since M4's site-wide search bootstrap
      # payload (`components/search_view.renderSearchBootstrapHtml`)
      # legitimately embeds every real page's own summary (including the
      # index's "Home body.") into every response by design.
      check not normalized.contains("<div class=\"docs-body\">Home body.")

  test "renderRoute normalizes a trailing slash to the same nested-route match":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nHome body.")
      writeFixtureFile(fixtureDir, "getting-started.md",
        "# Getting Started\n\nStart here.")

      let withSlash = renderRoute("/guide/getting-started/", fixtureDir, docsRouteManifest())
      let withoutSlash = renderRoute("/guide/getting-started", fixtureDir, docsRouteManifest())
      check withSlash.status == withoutSlash.status
      check normalizeHtml(withSlash.html) == normalizeHtml(withoutSlash.html)

  test "renderRoute('/missing') renders the typed not-found page without touching the filesystem":
    let (status, html) = renderRoute("/missing", "/nonexistent-dir-should-not-be-read", docsRouteManifest())
    check status == 404

    let normalized = normalizeHtml(html)
    check normalized.contains("<h1 class=\"docs-title\">Not Found</h1>")
    check normalized.contains("<main id=\"docs-region-main\" class=\"docs-main\" tabindex=\"-1\">")
    check normalized.contains("<div class=\"docs-not-found\">Page not found</div>")
    # Structurally distinct from a real page: no ordinary body-content div.
    check not normalized.contains("docs-body")

  test "renderRoute is stable across repeated calls against the same real fixture":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Stable\n\nSame every time.")
      writeFixtureFile(fixtureDir, "getting-started.md", "# GS\n\nGS body.")
      let first = normalizeHtml(renderRoute("/", fixtureDir, docsRouteManifest()).html)
      let second = normalizeHtml(renderRoute("/", fixtureDir, docsRouteManifest()).html)
      check first == second
