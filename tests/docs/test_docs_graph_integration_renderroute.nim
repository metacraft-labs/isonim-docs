## Tier 3 (SSR / `renderRoute` + build-gate) M3 integration suite --
## C-target only.
##
## The companion to `test_docs_graph_integration.nim`'s pure, in-memory
## proof: here the same four subsystems (M2's content loader, M1's
## routing, and M3's own navigation/references) are driven together
## against *real* fixture files on a *real* filesystem (never a mocked
## one, per the M0 harness rule), through the *real* `renderRoute` shell
## entry point and the *real* `validateContentGraph` build gate --
## exactly the two real serving/build paths `src/ssr.nim` and
## `src/check_links.nim` use in production. The equivalent suite against
## the real IsoNim content corpus + `docsRouteManifest()` now lives in
## the consumer package (M1 corrective deliverable 4:
## `../isonim/docs/users/tests/test_docs_graph_integration.nim`), since
## that corpus is consumer content, not framework fixture data.

when defined(js):
  {.error: "test_docs_graph_integration_renderroute is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/content
import ../../src/core/routes
import ../../src/core/navigation_vm
import ../../src/core/references
import ./helpers/fixture_dir
import ./helpers/html_normalize

suite "docs integration -- content loader, routing, navigation, and references agree on one real fixture graph (Tier 3, C-target)":
  test "a small real multi-section fixture site: content loader count, build-gate, and rendered nav/reference links all agree":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      # Kept flat on purpose, exactly like the real content/ dir's own
      # `getting-started.md`: the content loader's own derived route
      # ("/getting-started") disagrees with the manifest's actual
      # canonical path ("/guide/getting-started") -- routing's answer
      # must be what navigation and references both follow.
      writeFixtureFile(fixtureDir, "getting-started.md", "# Getting Started\n\nInstall the framework.")
      writeFixtureFile(fixtureDir, "guide/dsl.md", """---
order: 1
---
# The ui DSL

## Elements

Build trees with `ui:`. See [Getting Started](../getting-started.md) first.
""")
      writeFixtureFile(fixtureDir, "guide/other.md", """---
order: 2
---
# Other Guide

See [the DSL guide](./dsl.md) and its [elements section](./dsl.md#elements) directly.
""")
      writeFixtureFile(fixtureDir, "editor/overview.md", """---
aliases: /editor
---
# Editor Overview

Workspace model.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/getting-started", pkDoc,
          meta = RouteMeta(title: "Getting Started", contentPath: "getting-started.md")),
        newRouteEntry("/guide/dsl", pkMarkdown,
          meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
        newRouteEntry("/guide/other", pkMarkdown,
          meta = RouteMeta(title: "Other Guide", contentPath: "guide/other.md")),
        newRouteEntry("/editor/overview", pkMarkdown,
          meta = RouteMeta(title: "Editor Overview", contentPath: "editor/overview.md")),
      ])

      # Content loader: every real file on disk is discovered, none
      # silently dropped.
      check loadContentEntries(fixtureDir).len == 5

      # References build gate: the whole real graph has no broken
      # cross-references or anchors.
      validateContentGraph(fixtureDir, manifest)

      # Navigation: every manifest-bound page loads into the real nav
      # page list (none silently dropped by a fixture/manifest mismatch).
      let navPages = buildNavPages(manifest,
        proc(contentPath: string): ContentEntry = loadContentEntry(fixtureDir, contentPath))
      check navPages.len == 5

      # Rendering: the cross-page link and the anchor-fragment link in
      # "guide/other.md" resolve to routing's own canonical paths in the
      # final HTML, and the flat "getting-started.md" file's relative
      # link resolves to the manifest's nested canonical path, not
      # content.nim's own flat derived guess.
      let (dslStatus, dslHtml) = renderRoute("/guide/dsl", fixtureDir, manifest)
      check dslStatus == 200
      let dslNormalized = normalizeHtml(dslHtml)
      check dslNormalized.contains("href=\"/guide/getting-started\"")
      check not dslNormalized.contains("href=\"/getting-started\"")

      let (otherStatus, otherHtml) = renderRoute("/guide/other", fixtureDir, manifest)
      check otherStatus == 200
      let otherNormalized = normalizeHtml(otherHtml)
      check otherNormalized.contains("href=\"/guide/dsl\"")
      check otherNormalized.contains("href=\"/guide/dsl#elements\"")

      # Sidebar: every other real page is reachable from "guide/other"'s
      # own nav, using routing's canonical paths.
      check otherNormalized.contains("<nav id=\"docs-region-nav\" class=\"docs-nav\">")
      check otherNormalized.contains("href=\"/guide/getting-started\"")
      check otherNormalized.contains("href=\"/editor/overview\"")

      # Redirects/aliases: `renderRoute` extends `manifest` with the
      # real authored `aliases:` front matter itself (see `ssr.nim`),
      # so the old "/editor" path resolves to a real 301 with no extra
      # wiring from this test.
      let (redirectStatus, _) = renderRoute("/editor", fixtureDir, manifest)
      check redirectStatus == 301

  test "the build gate (validateContentGraph) fails the whole graph while renderRoute keeps serving individual pages -- two distinct real gates over the one real graph":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\nBody.")
      writeFixtureFile(fixtureDir, "guide/other.md",
        "# Other Guide\n\nSee [a missing page](./missing.md) for more.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(contentPath: "guide/other.md")),
      ])
      # The real build gate catches it, citing the offending page's own
      # real file:line -- never a silent runtime degradation.
      try:
        validateContentGraph(fixtureDir, manifest)
        fail()
      except BrokenReferenceError as e:
        check e.msg.contains("guide/other.md:")
        check e.msg.contains("/guide/missing")
      # Rendering the broken page itself still succeeds -- the broken
      # *outgoing* link doesn't stop this page (or any other real page)
      # from being served; only the explicit build-gate step
      # (`validateContentGraph`/`src/check_links.nim`, wired into `just
      # docs-smoke`) is the one place a broken reference fails a build.
      let (status, _) = renderRoute("/guide/other", fixtureDir, manifest)
      check status == 200
