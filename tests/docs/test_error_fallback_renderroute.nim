## M6 deliverable 2 (error handling & fallback UI) suite -- C-target only
## (`ssr.renderRoute`/`build_site` are C-target-only entries, exactly like
## the other `*_renderroute` suites).
##
## Proves the two SSR-facing halves of the deliverable end to end against
## real hermetic fixture content:
##   * a deliberately failing page-body render (a `pkMarkdown` route bound
##     to a content file that doesn't exist) returns a real HTTP 500
##     fallback page that RETAINS the site chrome (header/nav/footer +
##     skip link), instead of re-raising the exception; and
##   * the typed 404 page RETAINS the site navigation (real sidebar links
##     built from the content graph), not an empty nav region.
## The component-level error boundary primitive (the third half of the
## deliverable, used by M9) is unit-tested in
## `test_component_error_boundary.nim`.

when defined(js):
  {.error: "test_error_fallback_renderroute is a C-target-only suite (renderRoute is C-target-only)".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ../../src/components/shell
import ./helpers/fixture_dir
import ./helpers/html_normalize

suite "docs renderRoute error handling -- HTTP 500 fallback + 404 nav (M6 deliverable 2, C-target)":
  test "a failing body render returns status 500 with a fallback page that keeps the site chrome, never a raise":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nHome body.")
      writeFixtureFile(fixtureDir, "guide/ok.md", "# OK Guide\n\nOk body.")
      # The broken route is bound to a content file that does not exist, so
      # loading it during render raises -- the exact failure the fallback
      # must absorb rather than propagate.
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/ok", pkMarkdown,
          meta = RouteMeta(title: "OK Guide", contentPath: "guide/ok.md")),
        newRouteEntry("/guide/broken", pkMarkdown,
          meta = RouteMeta(title: "Broken", contentPath: "guide/does-not-exist.md")),
      ])

      # renderRoute must NOT raise -- it returns a real 500 instead.
      let (status, html) = renderRoute("/guide/broken", fixtureDir, manifest)
      check status == 500

      let n = normalizeHtml(html)
      # Full site chrome retained.
      check n.startsWith("<html>")
      check n.contains("</head><body>")
      check n.contains("<div class=\"docs-frame\">")
      check n.contains("<header id=\"docs-region-header\" class=\"docs-header\">")
      check n.contains("<nav id=\"docs-region-nav\" class=\"docs-nav\">")
      check n.contains("<main id=\"docs-region-main\" class=\"docs-main\" tabindex=\"-1\">")
      check n.contains("<footer id=\"docs-region-footer\" class=\"docs-footer\">")
      # The error notice stands in for the page body.
      check n.contains("<div class=\"" & errorFallbackClass & "\">")
      check n.contains(errorFallbackText)

  test "a healthy route is unaffected -- it still renders its real body at status 200":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nHome body.")
      writeFixtureFile(fixtureDir, "guide/ok.md", "# OK Guide\n\nOk body.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/ok", pkMarkdown,
          meta = RouteMeta(title: "OK Guide", contentPath: "guide/ok.md")),
      ])
      let (status, html) = renderRoute("/guide/ok", fixtureDir, manifest)
      check status == 200
      let n = normalizeHtml(html)
      check not n.contains(errorFallbackClass)
      check n.contains("Ok body.")

  test "the typed 404 page retains the site navigation (real sidebar links from the content graph)":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nHome body.")
      writeFixtureFile(fixtureDir, "guide/ok.md", "# OK Guide\n\nOk body.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/ok", pkMarkdown,
          meta = RouteMeta(title: "OK Guide", contentPath: "guide/ok.md")),
      ])
      let (status, html) = renderRoute("/does-not-exist", fixtureDir, manifest)
      check status == 404

      let n = normalizeHtml(html)
      # Still the typed not-found page.
      check n.contains("<div class=\"docs-not-found\">Page not found</div>")
      # ...but with the site navigation retained: the sidebar renders a
      # real link to the existing guide page, not an empty nav region.
      check n.contains("docs-nav-sidebar")
      check n.contains("docs-nav-item")
      check n.contains("href=\"/guide/ok\"")
