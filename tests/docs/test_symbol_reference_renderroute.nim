## Tier 3 (SSR / `renderRoute`) M8 symbol-reference suite -- C-target only.
##
## Proves M8 deliverables 1 & 2:
##  * a `pkSymbolReference` route, bound to a real Nim SOURCE file,
##    round-trips through `src/ssr.renderRoute` into the two-column symbol
##    reference layout (left symbol index nav, center per-symbol
##    signature/docstring), each symbol carrying a stable deep-link anchor;
##  * a `[[sym:...]]` cross-reference in a markdown page resolves, through
##    the shared symbol index, to a link to that symbol's anchor;
##  * an UNKNOWN `[[sym:...]]` symbol is flagged by
##    `references.validateContentGraph` with source provenance (file:line).
##
## Uses real hermetic fixture files (never a mocked filesystem), exactly
## like `test_api_reference_renderroute.nim`.

when defined(js):
  {.error: "test_symbol_reference_renderroute is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ../../src/core/config
import ../../src/core/references
import ./helpers/fixture_dir
import ./helpers/html_normalize

const fixtureCfg = DocsConfig(siteTitle: "Fixture Docs", siteDescription: "Fixture docs site.",
                               defaultRoute: "/", stylesheetHref: "/assets/style.css")

const vecmathSource = """
## Vector math utilities.

type
  Vec2*[T] = object   ## A 2D vector generic over its component type.
    x*: T
    y*: T

proc len2*[T](v: Vec2[T]): T =
  ## Returns the squared length of the vector.
  v.x * v.x + v.y * v.y

func add*[T](a, b: Vec2[T]): Vec2[T] {.inline.} =
  ## Adds two vectors component-wise.
  Vec2[T](x: a.x + b.x, y: a.y + b.y)
"""

suite "docs SSR renderRoute -- symbol reference pages (Tier 3, C-target)":
  test "renderRoute renders a pkSymbolReference module page's symbols":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "api/vecmath.nim", vecmathSource)
      let manifest = newRouteManifest(@[
        newRouteEntry("/api/vecmath", pkSymbolReference,
          meta = RouteMeta(title: "Vector Math", contentPath: "api/vecmath.nim")),
      ])

      let (status, html) = renderRoute("/api/vecmath", fixtureDir, manifest, fixtureCfg)
      check status == 200
      let normalized = normalizeHtml(html)

      # The corrected framework head: <html> opens straight into <head>,
      # whose first child is the charset <meta> (UTF-8 decode fix).
      check normalized.startsWith("<html><head><meta charset=\"utf-8\" />")
      check normalized.contains("<title>Vector Math — Fixture Docs</title>")
      check normalized.find("<meta charset=\"utf-8\" />") < normalized.find("<title>")
      check normalized.contains("<h1 class=\"docs-title\">Vector Math</h1>")

      # two-column layout: the layout container + its columns
      check normalized.contains("<div class=\"docs-sym-layout\">")
      check normalized.contains("<nav class=\"docs-sym-nav\"")
      check normalized.contains("<div class=\"docs-sym-content\">")

      # module doc
      check normalized.contains("Vector math utilities.")

      # per-symbol deep-link anchors (case preserved, dotted owner form)
      check normalized.contains("id=\"sym-Vec2\"")
      check normalized.contains("id=\"sym-Vec2.len2\"")
      check normalized.contains("id=\"sym-Vec2.add\"")
      check normalized.contains("href=\"#sym-Vec2.len2\"")
      check normalized.contains("data-sym-target=\"sym-Vec2.len2\"")

      # signatures (incl. a generic) + docstrings rendered
      check normalized.contains("proc len2*[T](v: Vec2[T]): T")
      check normalized.contains("Returns the squared length of the vector.")
      check normalized.contains("Adds two vectors component-wise.")
      # a pragma surfaced
      check normalized.contains("inline")

  test "a [[sym:...]] cross-reference resolves to a link to the symbol anchor":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "api/vecmath.nim", vecmathSource)
      writeFixtureFile(fixtureDir, "guide/usage.md",
        "# Usage\n\nSee [[sym:Vec2.len2]] and [[sym:Vec2]] for the math API.\n")
      let manifest = newRouteManifest(@[
        newRouteEntry("/api/vecmath", pkSymbolReference,
          meta = RouteMeta(title: "Vector Math", contentPath: "api/vecmath.nim")),
        newRouteEntry("/guide/usage", pkMarkdown,
          meta = RouteMeta(title: "Usage", contentPath: "guide/usage.md")),
      ])

      let (status, html) = renderRoute("/guide/usage", fixtureDir, manifest, fixtureCfg)
      check status == 200
      let normalized = normalizeHtml(html)

      # a valid [[sym:...]] rewrites to a real link to the symbol anchor on
      # the symbol-reference route
      check normalized.contains(
        "<a class=\"docs-md-symref\" href=\"/api/vecmath#sym-Vec2.len2\"><code>Vec2.len2</code></a>")
      check normalized.contains("href=\"/api/vecmath#sym-Vec2\"")

  test "an unknown [[sym:...]] is flagged by validateContentGraph with provenance":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "api/vecmath.nim", vecmathSource)
      writeFixtureFile(fixtureDir, "guide/broken.md",
        "# Broken\n\nThis references [[sym:NoSuchSymbol]] which does not exist.\n")
      let manifest = newRouteManifest(@[
        newRouteEntry("/api/vecmath", pkSymbolReference,
          meta = RouteMeta(title: "Vector Math", contentPath: "api/vecmath.nim")),
        newRouteEntry("/guide/broken", pkMarkdown,
          meta = RouteMeta(title: "Broken", contentPath: "guide/broken.md")),
      ])

      # query form is tolerant/pure; the enforcing form raises
      let issues = checkContentGraph(fixtureDir, manifest)
      var unknown: seq[ReferenceIssue] = @[]
      for i in issues:
        if i.kind == riUnknownSymbol: unknown.add i
      check unknown.len == 1
      check unknown[0].sourcePath == "guide/broken.md"   # SOURCE PROVENANCE
      check unknown[0].sourceLine > 0
      check unknown[0].targetHref.contains("NoSuchSymbol")

      var raised = false
      try:
        validateContentGraph(fixtureDir, manifest)
      except BrokenReferenceError as e:
        raised = true
        check e.msg.contains("guide/broken.md")
        check e.msg.contains("NoSuchSymbol")
      check raised

  test "a valid [[sym:...]] page passes validateContentGraph cleanly":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "api/vecmath.nim", vecmathSource)
      writeFixtureFile(fixtureDir, "guide/usage.md",
        "# Usage\n\nSee [[sym:Vec2.len2]] for details.\n")
      let manifest = newRouteManifest(@[
        newRouteEntry("/api/vecmath", pkSymbolReference,
          meta = RouteMeta(title: "Vector Math", contentPath: "api/vecmath.nim")),
        newRouteEntry("/guide/usage", pkMarkdown,
          meta = RouteMeta(title: "Usage", contentPath: "guide/usage.md")),
      ])
      let issues = checkContentGraph(fixtureDir, manifest)
      for i in issues:
        check i.kind != riUnknownSymbol
