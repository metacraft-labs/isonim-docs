## Tier 3 (SSR / `renderRoute`) bootstrap suite -- C-target only.
##
## Proves `renderRoute("/")` returns status 200 and stable, normalized
## HTML built from a clean/real fixture tree (a real temp directory, not
## the checked-in `content/` dir, so this test is hermetic and doesn't
## depend on -- or corrupt -- the repo's real proof content). Also
## exercises the chronicles log-capture harness helper: `renderRoute`
## emits a real, captured, greppable log line.
##
## M1 replaced M0's single hardcoded "/" dispatch with the real
## manifest-driven `renderRoute` (see `tests/docs/test_routes_renderroute.nim`
## for the full index/nested/trailing-slash/404 coverage); this suite's
## HTML-shape assertions were updated in lockstep (M0's `docs-shell` shape
## -> M1's `docs-frame` site-frame shape; the literal "404" text in the
## not-found body -> the structurally distinct `docs-not-found` shape) so
## it keeps proving the same M0 guarantees against the new real shape
## rather than silently going stale.

when defined(js):
  {.error: "test_bootstrap_renderroute is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ../../src/components/theme_toggle
import ./helpers/fixture_dir
import ./helpers/html_normalize
import ./helpers/log_capture

suite "docs SSR renderRoute (Tier 3, C-target)":
  test "renderRoute('/') returns 200 and stable normalized HTML from a real fixture content dir":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md",
        "# Fixture Home\n\nHello from a real fixture file.")

      let (status, html) = renderRoute("/", fixtureDir, docsRouteManifest())
      check status == 200

      let normalized = normalizeHtml(html)
      check normalized.contains("<div class=\"docs-frame\">")
      check normalized.contains("<link rel=\"stylesheet\" href=\"/assets/style.css\" />")
      check normalized.contains("<h1 class=\"docs-title\">Fixture Home</h1>")
      check normalized.contains("<div class=\"docs-body\">Hello from a real fixture file.</div>")

  test "the rendered document has a well-ordered head: charset first, no element between <html> and <head>, theme bootstrap INSIDE <head>":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md",
        "# Fixture Home\n\nBody with a real em-dash — and an ellipsis …")
      let (status, html) = renderRoute("/", fixtureDir, docsRouteManifest())
      check status == 200

      let htmlAt = html.find("<html")
      let htmlEnd = html.find(">", htmlAt)  # end of the <html ...> open tag
      let headAt = html.find("<head>")
      let charsetAt = html.find("<meta charset=\"utf-8\" />")
      let titleAt = html.find("<title>")
      let bootstrapAt = html.find("id=\"" & themeBootstrapScriptId & "\"")
      let headEndAt = html.find("</head>")
      let bodyAt = html.find("<body>")

      check htmlAt >= 0
      check headAt >= 0
      # (b) NOTHING sits between the <html ...> open tag and <head> -- the
      # theme-bootstrap <script> used to be emitted here (invalid HTML).
      check headAt == htmlEnd + 1
      check not html.contains("</html><script")  # sanity: no stray leading script
      # (a) the charset <meta> is the FIRST child of <head>, before <title>.
      check charsetAt == headAt + len("<head>")
      check charsetAt < titleAt
      # (c) the no-flash theme bootstrap <script> is INSIDE <head>
      # (between <head> and </head>), not before it.
      check bootstrapAt > headAt
      check bootstrapAt < headEndAt
      # ...and the whole head precedes <body> in a well-ordered document.
      check headEndAt < bodyAt

  test "renderRoute is stable across repeated calls against the same real fixture":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Stable\n\nSame every time.")
      let first = normalizeHtml(renderRoute("/", fixtureDir, docsRouteManifest()).html)
      let second = normalizeHtml(renderRoute("/", fixtureDir, docsRouteManifest()).html)
      check first == second

  test "renderRoute for an unmatched path returns a real 404 without touching the filesystem":
    let (status, html) = renderRoute("/does-not-exist", "/nonexistent-dir-should-not-be-read", docsRouteManifest())
    check status == 404
    check html.contains("docs-not-found")

  test "chronicles log capture helper: renderRoute emits a real, captured log line":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Logged\n\nBody.")
      let captured = captureStderr(proc() =
        discard renderRoute("/", fixtureDir, docsRouteManifest())
      )
      check captured.contains("docs_route_rendered")
      check captured.len > 0
