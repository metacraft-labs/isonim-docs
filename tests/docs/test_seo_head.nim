## M6 deliverable 1 (SEO / metadata generation) suite -- DUAL-TARGET:
## both `nim c -r` and `nim js -r` must pass.
##
## The head-emission half (OpenGraph + Twitter card + canonical link +
## JSON-LD, all derived from `RouteMeta`/`DocsConfig`) is pure ViewModel +
## string rendering, so it is exercised on BOTH targets. The SSG half --
## `buildSite` writing `sitemap.xml` (every route) + a default
## `robots.txt`, and surfacing a page missing a description as a CAPTURED
## build warning -- is real-filesystem work (`std/os`/`build_site.nim` are
## C-target-only), so it is guarded under `when not defined(js)` and never
## pulls `os` into the JS build.

import std/[unittest, strutils]
import ../../src/core/routes
import ../../src/core/config
import ../../src/core/shell_vm
import ../../src/components/shell

when not defined(js):
  import std/[os, sequtils]
  import ../../src/build_site
  import ./helpers/fixture_dir

suite "docs SEO head emission -- OG/Twitter/canonical/JSON-LD (M6 deliverable 1, dual-target)":
  let cfg = DocsConfig(siteTitle: "IsoNim Docs",
                        siteDescription: "Site-wide fallback description.",
                        defaultRoute: "/", stylesheetHref: "/assets/style.css",
                        baseUrl: "https://docs.example.com")

  test "renderDocumentHeadHtml emits OpenGraph, Twitter card, an absolute canonical link, and JSON-LD":
    let head = buildDocumentHead(
      RouteMeta(title: "Getting Started", description: "Learn the basics."),
      cfg, "/guide/getting-started")
    let html = renderDocumentHeadHtml(head)

    # Canonical <link>, absolute from the consumer-supplied baseUrl.
    check html.contains(
      "<link rel=\"canonical\" href=\"https://docs.example.com/guide/getting-started\" />")

    # OpenGraph.
    check html.contains(
      "<meta property=\"og:title\" content=\"Getting Started — IsoNim Docs\" />")
    check html.contains("<meta property=\"og:description\" content=\"Learn the basics.\" />")
    check html.contains("<meta property=\"og:type\" content=\"article\" />")
    check html.contains(
      "<meta property=\"og:url\" content=\"https://docs.example.com/guide/getting-started\" />")
    check html.contains("<meta property=\"og:site_name\" content=\"IsoNim Docs\" />")

    # Twitter card.
    check html.contains("<meta name=\"twitter:card\" content=\"summary\" />")
    check html.contains(
      "<meta name=\"twitter:title\" content=\"Getting Started — IsoNim Docs\" />")
    check html.contains("<meta name=\"twitter:description\" content=\"Learn the basics.\" />")

    # JSON-LD document.
    check html.contains("<script type=\"application/ld+json\">")
    check html.contains("\"@context\":\"https://schema.org\"")
    check html.contains("\"@type\":\"TechArticle\"")
    check html.contains("\"headline\":\"Getting Started — IsoNim Docs\"")
    check html.contains("\"description\":\"Learn the basics.\"")
    check html.contains("\"url\":\"https://docs.example.com/guide/getting-started\"")

    # The pre-M6 description meta + stylesheet link are still the first of
    # their kind, unchanged.
    check html.contains("<meta name=\"description\" content=\"Learn the basics.\" />")
    check html.contains("<link rel=\"stylesheet\" href=\"/assets/style.css\" />")

  test "the charset meta is the FIRST child of <head>, before <title> (UTF-8 decode fix)":
    let head = buildDocumentHead(
      RouteMeta(title: "Getting Started", description: "Learn the basics."),
      cfg, "/guide/getting-started")
    let html = renderDocumentHeadHtml(head)
    # (a) the charset declaration is present at all...
    check html.contains("<meta charset=\"utf-8\" />")
    let headAt = html.find("<head>")
    let charsetAt = html.find("<meta charset=\"utf-8\" />")
    let titleAt = html.find("<title>")
    check headAt >= 0
    # ...(b) it is the very first child of <head> (immediately after `<head>`),
    check charsetAt == headAt + len("<head>")
    # ...and (c) it comes before <title> so the encoding is declared first.
    check charsetAt < titleAt

  test "charset stays the first head child even when a headTop prelude is injected":
    # The CSP/analytics/theme-bootstrap prelude is injected AFTER the charset
    # meta, never before it -- the encoding declaration must remain first.
    let head = buildDocumentHead(RouteMeta(title: "X", description: "Y"), cfg, "/x")
    let html = renderDocumentHeadHtml(head, "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self'\" />")
    let charsetAt = html.find("<meta charset=\"utf-8\" />")
    let cspAt = html.find("http-equiv=\"Content-Security-Policy\"")
    check charsetAt == html.find("<head>") + len("<head>")
    check charsetAt < cspAt

  test "description falls back to the site config when the route has none":
    let head = buildDocumentHead(RouteMeta(title: "Home"), cfg, "/")
    let html = renderDocumentHeadHtml(head)
    check html.contains("<meta name=\"description\" content=\"Site-wide fallback description.\" />")
    check html.contains(
      "<meta property=\"og:description\" content=\"Site-wide fallback description.\" />")

  test "canonical/og:url fall back to a root-relative path when no baseUrl is configured":
    let cfg2 = DocsConfig(siteTitle: "Docs", siteDescription: "D", stylesheetHref: "/s.css")
    let head = buildDocumentHead(RouteMeta(title: "X", description: "Y"), cfg2, "/guide/x")
    let html = renderDocumentHeadHtml(head)
    check html.contains("<link rel=\"canonical\" href=\"/guide/x\" />")
    check html.contains("<meta property=\"og:url\" content=\"/guide/x\" />")

  test "jsonLdString escapes '<' so a value can't break out of the <script> block":
    check jsonLdString("</script><b>x").contains("\\u003c/script")
    check not jsonLdString("</script>").contains("</script>")

when not defined(js):
  suite "docs SSG SEO artifacts -- sitemap.xml + robots.txt + captured warnings (M6 deliverable 1, C-target)":
    test "buildSite writes sitemap.xml with every route (absolute URLs) and a default robots.txt":
      withFixtureDir:
        let assetsDir = fixtureDir / "assets"
        writeFixtureFile(fixtureDir, "assets" / "style.css", ".docs-frame { color: red; }\n")
        writeFixtureFile(fixtureDir, "content" / "index.md",
          "---\ndescription: The home page.\n---\n# Home\n\nBody.")
        writeFixtureFile(fixtureDir, "content" / "guide" / "dsl.md",
          "---\ndescription: The DSL guide.\n---\n# The DSL\n\nBody.")
        let contentDir = fixtureDir / "content"
        let outDir = fixtureDir / "out"
        let cfg = DocsConfig(siteTitle: "T", siteDescription: "D",
                              stylesheetHref: "/assets/style.css",
                              baseUrl: "https://example.com")

        let n = buildSite(outDir = outDir, contentDir = contentDir, cfg = cfg,
                          assetsDir = assetsDir)
        check n > 0

        check fileExists(outDir / "sitemap.xml")
        let sitemap = readFile(outDir / "sitemap.xml")
        check sitemap.contains("<urlset")
        check sitemap.contains("<loc>https://example.com/</loc>")
        check sitemap.contains("<loc>https://example.com/guide/dsl</loc>")

        check fileExists(outDir / "robots.txt")
        let robots = readFile(outDir / "robots.txt")
        check robots.contains("User-agent: *")
        check robots.contains("Allow: /")
        check robots.contains("Sitemap: https://example.com/sitemap.xml")

    test "a consumer-supplied robots.txt (publicDir) is never overwritten":
      withFixtureDir:
        let assetsDir = fixtureDir / "assets"
        let publicDir = fixtureDir / "public"
        writeFixtureFile(fixtureDir, "assets" / "style.css", ".docs-frame { color: red; }\n")
        writeFixtureFile(fixtureDir, "public" / "robots.txt", "User-agent: consumer\n")
        writeFixtureFile(fixtureDir, "content" / "index.md",
          "---\ndescription: Home.\n---\n# Home\n\nBody.")
        let outDir = fixtureDir / "out"
        discard buildSite(outDir = outDir, contentDir = fixtureDir / "content",
                          assetsDir = assetsDir, publicDir = publicDir)
        check readFile(outDir / "robots.txt") == "User-agent: consumer\n"
        # sitemap is still emitted alongside the consumer robots.txt.
        check fileExists(outDir / "sitemap.xml")

    test "a page missing a description triggers a CAPTURED build warning -- not silent, not a failure":
      withFixtureDir:
        let assetsDir = fixtureDir / "assets"
        writeFixtureFile(fixtureDir, "assets" / "style.css", ".docs-frame { color: red; }\n")
        # index.md HAS a description; the guide page deliberately has none.
        writeFixtureFile(fixtureDir, "content" / "index.md",
          "---\ndescription: Home.\n---\n# Home\n\nBody.")
        writeFixtureFile(fixtureDir, "content" / "guide" / "nodesc.md",
          "# No Description Here\n\nBody with no front-matter description.")
        let outDir = fixtureDir / "out"
        let warnings = new(seq[string])
        let n = buildSite(outDir = outDir, contentDir = fixtureDir / "content",
                          assetsDir = assetsDir, warnings = warnings)
        # The build still succeeded -- a warning, never a hard failure.
        check n > 0
        # The missing-description page is captured, observably.
        check warnings[].len > 0
        check warnings[].anyIt(it.contains("/guide/nodesc") and it.contains("description"))
        # The page that HAS a description did not warn about one.
        check not warnings[].anyIt(it.contains("'/'") and it.contains("description"))
