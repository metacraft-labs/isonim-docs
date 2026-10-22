## The script policy on real isonim-docs pages (C target: it renders
## through `ssr.renderRoute` and builds with `build_site.buildSite`).
##
## `DocsConfig.scriptPolicy` defaults to `spDeclared`, under which every
## page keeps the scripts it has always carried: the theme no-flash
## bootstrap in `<head>` and the image viewer at the end of `<body>` (plus
## the app bundle and analytics when configured). `spNone` is opt-in and
## must leave a page with no executable script at all, while its JSON-LD
## data block stays. The default-policy cases are the negative control:
## they show the bootstrap is still emitted, and that the checker
## (`isonim/static/scripts.executableScripts`) finds scripts when a page
## has them.
##
## No test doubles: the real mini-site fixture is rendered and built.

import std/[unittest, os, strutils]
import isonim/static/scripts
import isonim/static/csp
import ../../src/core/config
import ../../src/core/routes
import ../../src/core/analytics
import ../../src/components/theme_toggle
import ../../src/components/image_viewer
import ../../src/ssr
import ../../src/build_site

const contentDir = "tests/fixtures/mini-site"

proc noScriptsConfig(): DocsConfig =
  result = docsConfig()
  result.scriptPolicy = spNone

proc routes(): seq[string] =
  for entry in buildManifestFromContent(contentDir).entries:
    if entry.pageKind != pkRedirect: result.add entry.canonicalPath

suite "isonim-docs script policy -- rendered routes":
  test "the fixture has pages to check":
    check routes().len >= 3

  test "negative control: by default every page still emits the theme bootstrap and the image viewer":
    check docsConfig().scriptPolicy == spDeclared
    for route in routes():
      let (status, html) = renderRoute(route, contentDir)
      check status == 200
      check executableScripts(html) ==
        @["<script id=\"" & themeBootstrapScriptId & "\">",
          "<script id=\"" & imageViewerScriptId & "\">"]
      check html.contains(renderThemeBootstrapHtml())

  test "under spNone no page carries an executable script, and the JSON-LD head stays":
    for route in routes():
      let (status, html) = renderRoute(route, contentDir, cfg = noScriptsConfig())
      check status == 200
      check executableScripts(html).len == 0
      check eventHandlerAttributes(html).len == 0
      check html.contains("<script type=\"application/ld+json\">{\"@context\":\"https://schema.org\"")
      check not html.contains(themeBootstrapScriptBody())

  test "spNone also drops the app bundle a consumer configured":
    var cfg = noScriptsConfig()
    cfg.appScriptHref = "/assets/app.js"
    let (_, html) = renderRoute("/", contentDir, cfg = cfg)
    check executableScripts(html).len == 0
    var declared = docsConfig()
    declared.appScriptHref = "/assets/app.js"
    let (_, declaredHtml) = renderRoute("/", contentDir, cfg = declared)
    check "<script src=\"/assets/app.js\" defer>" in executableScripts(declaredHtml)

  test "a configured analytics snippet survives spNone, and the CSP hashes only what is emitted":
    var cfg = noScriptsConfig()
    cfg.analytics = AnalyticsConfig(provider: apBeacon, endpoint: "/collect", honorDnt: true)
    cfg.csp = strictCspConfig()
    let (_, html) = renderRoute("/", contentDir, cfg = cfg)
    check executableScripts(html) == @["<script id=\"" & analyticsScriptId & "\">"]
    check html.contains(cspHashSource(analyticsScriptBody(cfg.analytics)))
    check not html.contains(cspHashSource(themeBootstrapScriptBody()))
    check not html.contains(cspHashSource(imageViewerScriptBody()))

suite "isonim-docs script policy -- a built site":
  let scratch = getTempDir() / ("isonim-docs-test-script-policy-" & $getCurrentProcessId())

  teardown:
    removeDir(scratch)

  test "a site built under spNone has no executable script in any page; the default build does":
    let quiet = scratch / "none"
    let loud = scratch / "declared"
    check buildSite(outDir = quiet, contentDir = contentDir, cfg = noScriptsConfig()) >= 3
    check buildSite(outDir = loud, contentDir = contentDir) >= 3
    var pages = 0
    for rel in walkDirRec(quiet, relative = true):
      if rel.endsWith(".html"):
        inc pages
        let html = readFile(quiet / rel)
        check executableScripts(html).len == 0
        check html.contains("application/ld+json")
        check executableScripts(readFile(loud / rel)).len == 2
    check pages >= 3
