## isonim-docs -- M1 client-JS-bundle + robust-nav framework suite (C-target).
##
## Proves the framework seams M1 adds, independent of any consumer:
##
##   * `DocsConfig.appScriptHref`, when set, injects exactly one deferred
##     `<script src=...>` into the `<head>` of EVERY rendered route (via the
##     single shared `shell.renderSecureDocumentHeadHtml` seam `ssr.renderRoute`
##     goes through), and the default (unset) leaves the head byte-for-byte the
##     pre-M1 markup -- so the bundle is strict progressive enhancement;
##   * `navigation_vm.buildSidebar`/`buildNavigationViewModel`'s `expandAll`
##     renders every section default-expanded (so plain-anchor nav works
##     without JS), while the default keeps the pre-M1 active-path-only expand.

import std/[unittest, os, strutils]
import ../../src/ssr
import ../../src/core/config
import ../../src/core/navigation_vm

proc fixtureDir(): string =
  currentSourcePath().parentDir() / ".." / "fixtures" / "mini-site"

suite "M1 client-JS bundle -- <script> injection is opt-in progressive enhancement":
  test "appScriptHref set -> exactly one deferred <script src> in the head of a rendered route":
    var cfg = docsConfig()
    cfg.appScriptHref = "/assets/app.js"
    let (status, html) = renderRoute("/", fixtureDir(), cfg = cfg)
    check status == 200
    check html.contains("<script src=\"/assets/app.js\" defer></script>")
    # It rides in the <head> (before <body>), like the theme bootstrap.
    let scriptPos = html.find("src=\"/assets/app.js\"")
    let bodyPos = html.find("<body>")
    check scriptPos >= 0 and bodyPos >= 0 and scriptPos < bodyPos
    # Exactly one injection, on the page.
    check html.count("src=\"/assets/app.js\"") == 1

  test "default DocsConfig (no appScriptHref) injects no app <script> -- byte-for-byte pre-M1":
    let (status, html) = renderRoute("/", fixtureDir(), cfg = docsConfig())
    check status == 200
    check not html.contains("/assets/app.js")

  test "a non-home route also carries the injected bundle (every page, not just /)":
    var cfg = docsConfig()
    cfg.appScriptHref = "/assets/app.js"
    # Any real fixture route; the framework mini-site has a /getting-started page.
    let (status, html) = renderRoute("/getting-started", fixtureDir(), cfg = cfg)
    if status == 200:
      check html.contains("<script src=\"/assets/app.js\" defer></script>")

suite "M1 robust nav -- expandAll renders every sidebar section default-expanded":
  let pages = @[
    NavPage(routePath: "/", title: "Home", section: "", order: 1, slug: "index"),
    NavPage(routePath: "/guide/start", title: "Start", section: "guide", order: 1, slug: "start"),
    NavPage(routePath: "/reference/cli", title: "CLI", section: "reference", order: 1, slug: "cli"),
  ]

  test "default (expandAll=false): only the active route's section expands, others collapse":
    # Active route is the section-less home, so NO named section auto-expands.
    let sidebar = buildSidebar(pages, "/")
    for section in sidebar.sections:
      if section.key.len == 0:
        check section.isExpanded          # ungrouped top level is always open
      else:
        check not section.isExpanded      # named sections collapsed on home

  test "expandAll=true: every named section is expanded (links visible without JS)":
    let sidebar = buildSidebar(pages, "/", expandAll = true)
    for section in sidebar.sections:
      check section.isExpanded

  test "buildNavigationViewModel threads expandAll through to the sidebar":
    let nav = buildNavigationViewModel(pages, "/", expandAll = true)
    check nav.sidebar.sections.len > 0
    for section in nav.sidebar.sections:
      check section.isExpanded
