## Tier 3 (SSR / `renderRoute`) M2 markdown suite -- C-target only.
##
## Proves M2 deliverable 4 (wiring markdown pages into the M1
## route/rendering core): a real markdown fixture file round-trips
## through the content loader (`content.loadContentEntry`), the
## markdown-to-ViewModel translation (`markdown_vm.parseMarkdownBlocks`),
## and `src/ssr.renderRoute` into stable, structurally-correct HTML --
## the same `renderRoute`/`docsRouteManifest` surface
## `test_routes_renderroute.nim` already proves for M0/M1's
## `pkIndex`/`pkDoc` routes, now exercised for a `pkMarkdown` route
## against a real hermetic fixture content dir (never the checked-in
## `content/` dir, and never a mocked filesystem).

when defined(js):
  {.error: "test_markdown_renderroute is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ../../src/core/config
import ./helpers/fixture_dir
import ./helpers/html_normalize

const fixtureCfg = DocsConfig(siteTitle: "Fixture Docs", siteDescription: "Fixture docs site.",
                               defaultRoute: "/", stylesheetHref: "/assets/style.css")

suite "docs SSR renderRoute -- markdown pages (Tier 3, C-target)":
  test "renderRoute renders a real markdown fixture file end to end: heading anchor, admonition, table, list, code fence":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/example.md", """---
title: Example Guide
description: A fixture markdown page.
---
# Ignored Body Heading

## Overview

Run `nimble install` first.

- one
- two

```nim
echo "hi"
```

:::tip
Read the docs.
:::

| A | B |
| --- | --- |
| 1 | 2 |

See [Home](../index.md).
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/example", pkMarkdown,
          meta = RouteMeta(title: "Example Guide", contentPath: "guide/example.md")),
      ])

      let (status, html) = renderRoute("/guide/example", fixtureDir, manifest, fixtureCfg)
      check status == 200

      let normalized = normalizeHtml(html)
      # The corrected framework head: <html> opens straight into <head>
      # (no element between them), whose FIRST child is the charset <meta>
      # (UTF-8 decode fix), and the theme no-flash bootstrap <script> sits
      # INSIDE <head>, before <title>.
      check normalized.startsWith("<html><head><meta charset=\"utf-8\" />")
      check normalized.contains("<title>Example Guide — Fixture Docs</title>")
      let charsetAt = normalized.find("<meta charset=\"utf-8\" />")
      let bootstrapAt = normalized.find("id=\"docs-theme-bootstrap\"")
      let titleAt = normalized.find("<title>")
      let headEndAt = normalized.find("</head>")
      check charsetAt < bootstrapAt      # charset precedes the bootstrap script
      check bootstrapAt < titleAt        # bootstrap before <title>, still in <head>
      check bootstrapAt < headEndAt      # ...and the script is inside <head>
      check normalized.contains("<div class=\"docs-frame\">")
      check normalized.contains("<h1 class=\"docs-title\">Example Guide</h1>")
      check normalized.contains("<div class=\"docs-md-body\">")
      check normalized.contains("<h2 class=\"docs-md-heading\" id=\"overview\">Overview</h2>")
      check normalized.contains("<code>nimble install</code>")
      check normalized.contains("<ul class=\"docs-md-list\"><li>one</li><li>two</li></ul>")
      # `normalizeHtml` strips whitespace touching a tag boundary, so the
      # space between "echo" and the highlighted string's <span> is gone
      # here even though the raw SSR output keeps it (see the SSR-string
      # assertion in test_markdown_mock.nim, which checks the raw string).
      check normalized.contains(
        "<pre class=\"docs-md-code-fence\"><code class=\"language-nim\">echo<span class=\"tok-string\">\"hi\"</span></code></pre>")
      check normalized.contains("docs-md-admonition-tip")
      check normalized.contains("<table class=\"docs-md-table\">")
      # The relative link to "../index.md" from "guide/example.md" resolves
      # to the real root route, proving relative-link normalization ran.
      check normalized.contains("href=\"/\"")

  test "renderRoute for a markdown page falls back to the route's own meta title when the file has no front matter title":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/plain.md", "# Plain\n\nJust a paragraph.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/plain", pkMarkdown,
          meta = RouteMeta(title: "Plain Fallback Title", contentPath: "guide/plain.md")),
      ])

      let (status, html) = renderRoute("/guide/plain", fixtureDir, manifest)
      check status == 200
      let normalized = normalizeHtml(html)
      # The body's own leading "# Plain" heading becomes the page title,
      # exactly like the M0/M1 pkDoc/pkIndex content pipeline.
      check normalized.contains("<h1 class=\"docs-title\">Plain</h1>")
      check normalized.contains("<p class=\"docs-md-paragraph\">Just a paragraph.</p>")

  test "renderRoute is stable across repeated calls against the same markdown fixture":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/stable.md", "# Stable\n\n## Section\n\nBody text.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/stable", pkMarkdown,
          meta = RouteMeta(title: "Stable", contentPath: "guide/stable.md")),
      ])
      let first = normalizeHtml(renderRoute("/guide/stable", fixtureDir, manifest).html)
      let second = normalizeHtml(renderRoute("/guide/stable", fixtureDir, manifest).html)
      check first == second

  test "renderRoute keeps the typed not-found page unchanged for an unmatched path against a markdown manifest":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/example", pkMarkdown,
        meta = RouteMeta(title: "Example Guide", contentPath: "guide/example.md")),
    ])
    let (status, html) = renderRoute("/missing", "/nonexistent-dir-should-not-be-read", manifest)
    check status == 404
    let normalized = normalizeHtml(html)
    check normalized.contains("<h1 class=\"docs-title\">Not Found</h1>")
    check normalized.contains("<div class=\"docs-not-found\">Page not found</div>")
