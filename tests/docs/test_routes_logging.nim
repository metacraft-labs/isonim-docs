## Tier 3 (SSR / `renderRoute`) structured-logging suite -- C-target only.
##
## M1's final deliverable: route resolution and render failures must emit
## greppable chronicles events, so a route bug is diagnosable from a CI
## log first, not from a manual local reproduction. Builds on the
## already-proven `docs_route_rendered` success-path event
## (`test_bootstrap_renderroute.nim`) and the already-proven
## `captureStderr` capture helper -- no new capture mechanism, only new
## events and new coverage of the two failure shapes `renderRoute` can
## hit: an unmatched path (route *resolution* failure, handled, no
## exception) and a matched route whose bound content file can't be
## loaded (a render-time failure). M6 deliverable 2 changed the latter's
## contract: `renderRoute` no longer re-raises -- it logs
## `docs_render_error` and returns a real HTTP 500 fallback page (with
## chrome) instead, per `error "docs_render_error"` in `src/ssr.nim`.

when defined(js):
  {.error: "test_routes_logging is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ./helpers/fixture_dir
import ./helpers/log_capture

suite "docs SSR renderRoute -- structured logging (Tier 3, C-target)":
  test "renderRoute emits a greppable docs_route_not_found event for an unmatched path, without raising":
    let captured = captureStderr(proc() =
      let (status, _) = renderRoute("/missing", "/nonexistent-dir-should-not-be-read", docsRouteManifest())
      check status == 404
    )
    check captured.contains("docs_route_not_found")
    check captured.contains("path=/missing")

  test "renderRoute emits a greppable docs_render_error event and returns a 500 fallback (never raising) when a matched route's content file is missing":
    withFixtureDir:
      # `fixtureDir` is real but deliberately left empty -- "/" matches a
      # real route entry, but its bound `index.md` doesn't exist, so
      # `loadDocsPage`'s `readFile` raises internally. M6 deliverable 2:
      # `renderRoute` catches it, logs the structured event, and returns a
      # real HTTP 500 fallback page (with chrome) instead of propagating.
      var status = -1
      let captured = captureStderr(proc() =
        let (s, html) = renderRoute("/", fixtureDir, docsRouteManifest())
        status = s
        # a real fallback page, not an empty string.
        check html.contains("docs-frame")
        check html.contains("docs-error-fallback")
      )
      check status == 500
      check captured.contains("docs_render_error")
      check captured.contains("path=/")
      check captured.contains("contentPath=index.md")

  test "a render failure doesn't corrupt logging for a subsequent successful renderRoute call":
    withFixtureDir:
      var status = -1
      discard captureStderr(proc() =
        let (s, _) = renderRoute("/", fixtureDir, docsRouteManifest())
        status = s
      )
      check status == 500

      writeFixtureFile(fixtureDir, "index.md", "# Recovered\n\nBody.")
      let captured = captureStderr(proc() =
        let (status, _) = renderRoute("/", fixtureDir, docsRouteManifest())
        check status == 200
      )
      check captured.contains("docs_route_rendered")
      check not captured.contains("docs_render_error")

  test "docs_route_not_found and docs_route_rendered are logged at different, distinguishable severities":
    let notFoundCapture = captureStderr(proc() =
      discard renderRoute("/missing", "/nonexistent-dir-should-not-be-read", docsRouteManifest())
    )
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Home\n\nBody.")
      let renderedCapture = captureStderr(proc() =
        discard renderRoute("/", fixtureDir, docsRouteManifest())
      )
      # chronicles' textlines sink prefixes each record with a level
      # marker (e.g. "WRN"/"INF") -- proves the not-found event is
      # distinguishable from a normal render in a raw grep, not just by
      # event name.
      check notFoundCapture.contains("WRN")
      check renderedCapture.contains("INF")
