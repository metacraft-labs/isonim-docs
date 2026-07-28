## Tier 3 (SSR / `renderRoute`) M3 navigation suite -- C-target only.
##
## Proves M3 deliverable 1 wired all the way into the real rendering
## shell: `renderRoute` builds the navigation ViewModel off the real
## content graph (`navigation_vm.buildNavPages`, driven by the same
## manifest/content-dir pair `matchRoute`/`loadContentEntry` already use
## -- no forked page list) and the final HTML carries real nav
## landmarks, breadcrumb links, sidebar links, a page table of contents,
## and previous/next pagination for a nested page.

when defined(js):
  {.error: "test_navigation_renderroute is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ./helpers/fixture_dir
import ./helpers/html_normalize

suite "docs SSR renderRoute -- navigation (Tier 3, C-target)":
  test "renderRoute renders real nav landmarks, breadcrumb links, sidebar links, and a page TOC for a nested page":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      writeFixtureFile(fixtureDir, "guide/signals-effects.md", """---
order: 1
---
# Signals & Effects

## Overview

Intro text.
""")
      writeFixtureFile(fixtureDir, "guide/dsl.md", """---
order: 2
---
# The ui DSL

## Elements

Body text.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/signals-effects", pkMarkdown,
          meta = RouteMeta(title: "Signals & Effects", contentPath: "guide/signals-effects.md")),
        newRouteEntry("/guide/dsl", pkMarkdown,
          meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
      ])

      let (status, html) = renderRoute("/guide/dsl", fixtureDir, manifest)
      check status == 200
      let normalized = normalizeHtml(html)

      # Nav landmarks: the shell's stable nav region, plus the distinct
      # breadcrumb/sidebar/TOC/pagination landmarks nested inside it.
      check normalized.contains("<nav id=\"docs-region-nav\" class=\"docs-nav\">")
      check normalized.contains("aria-label=\"breadcrumbs\"")
      check normalized.contains("aria-label=\"sidebar\"")
      check normalized.contains("aria-label=\"table of contents\"")
      check normalized.contains("aria-label=\"pagination\"")

      # Breadcrumbs: Home > Guide (section crumb) > current page (non-link).
      check normalized.contains("<a href=\"/\">Home</a>")
      check normalized.contains("<a href=\"/guide\">Guide</a>")
      check normalized.contains("docs-nav-breadcrumb-current")
      check normalized.contains(">The ui DSL<")

      # Sidebar: the manifest's own canonical route paths, not any
      # content-file-derived path, and the active page marked current.
      check normalized.contains("href=\"/guide/signals-effects\"")
      check normalized.contains("aria-current=\"page\"")

      # Page table of contents: the active page's own heading anchors.
      check normalized.contains("<a href=\"#elements\">Elements</a>")

      # Previous/next: "/guide/dsl" (order 2) follows "/guide/signals-effects" (order 1).
      check normalized.contains("docs-nav-prev")
      check normalized.contains(">Signals &amp; Effects<")

  test "renderRoute's sidebar follows the route manifest's own canonical path, not a mismatched content-derived one":
    withFixtureDir:
      # Mirrors the real M0/M1 manifest shape: a flat root-level content
      # file bound to a nested route pattern, so content.nim's own
      # `deriveRoutePath` (which would say "/getting-started") disagrees
      # with the manifest's actual canonical path.
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      writeFixtureFile(fixtureDir, "getting-started.md", "# Getting Started\n\nStart here.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/getting-started", pkDoc,
          meta = RouteMeta(title: "Getting Started", contentPath: "getting-started.md")),
      ])

      let (status, html) = renderRoute("/", fixtureDir, manifest)
      check status == 200
      let normalized = normalizeHtml(html)
      check normalized.contains("href=\"/guide/getting-started\"")
      check not normalized.contains("href=\"/getting-started\"")

  test "renderRoute's typed not-found page RETAINS the site navigation (M6 deliverable 2)":
    # M6 deliverable 2 reversed the pre-M6 contract: a 404 no longer
    # renders an empty nav region -- it retains the real, content-graph-
    # backed sidebar so a lost visitor can still navigate. Built from the
    # same manifest + real content dir any real 404 would have.
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\nBody.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/dsl", pkMarkdown,
          meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
      ])
      let (status, html) = renderRoute("/missing", fixtureDir, manifest)
      check status == 404
      let normalized = normalizeHtml(html)
      # Still the typed not-found page...
      check normalized.contains("<div class=\"docs-not-found\">Page not found</div>")
      # ...but the site navigation is retained: the sidebar renders a real
      # link to the existing guide page inside the nav landmark.
      check normalized.contains("<nav id=\"docs-region-nav\" class=\"docs-nav\">")
      check normalized.contains("docs-nav-sidebar")
      check normalized.contains("docs-nav-item")
      check normalized.contains("href=\"/guide/dsl\"")

  test "renderRoute's navigation is stable across repeated calls against the same real fixture":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "index.md", "# Welcome")
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\n## Elements\n\nBody.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/", pkIndex, meta = RouteMeta(contentPath: "index.md")),
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
      ])
      let first = normalizeHtml(renderRoute("/guide/dsl", fixtureDir, manifest).html)
      let second = normalizeHtml(renderRoute("/guide/dsl", fixtureDir, manifest).html)
      check first == second
