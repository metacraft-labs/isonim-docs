## Tier 2/3 content-image viewer suite -- dual-target (C + JS).
##
## Proves the framework's full-viewport image viewer end to end, at every
## layer that is testable without a real browser:
##
##   * the MARKUP a content image renders to, on BOTH renderer backends
##     (the SSR string builder and the MockRenderer tree builder) -- an
##     inline `docs-md-figure` wrapper carrying the `<img>` plus an
##     affordance `<a>` that, with no JS at all, is a plain working link
##     to the image file itself (progressive enhancement);
##   * that SSR NEVER guesses `data-zoomable`: "is this image downscaled"
##     is a rendered-size fact (natural vs displayed width), so only the
##     client may assert it, and the CSS treats "attribute absent" as the
##     no-JS state;
##   * that non-content images (a `:::cards` icon) are untouched -- the
##     affordance must not leak onto chrome images;
##   * the client script the framework emits: that the `<script>` body a
##     browser hashes is byte-identical to the body the CSP manager hashes,
##     that it is whitelisted by a strict CSP, and that it really implements
##     the behaviours this feature promises (measure natural vs rendered
##     width, re-measure on resize, dialog semantics, Escape, focus
##     restore, background-scroll lock);
##   * (C target) the real `renderRoute` SSR wiring, and a real `buildSite`
##     SSG build proving the runtime-only overlay CSS survives the class
##     purge -- the overlay is created by the client, so its classes appear
##     in no static page and an unsafelisted purge would silently ship an
##     unstyled overlay.
##
## Live behaviour of the script itself (open/close/focus/scroll) is verified
## by driving a real browser against a real SSG build: a Node DOM shim cannot
## answer "is this image actually being displayed smaller than it is", which
## is the whole premise of the feature, so the suites below assert everything
## that IS decidable without layout and stop there.

import std/[unittest, strutils, tables]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/core/config
import ../../src/core/csp
import ../../src/components/markdown_view
import ../../src/components/image_viewer
import ../../src/components/shell
import ./helpers/mock_tree

const wideImageMd = "![A wide diagram](/img/wide.png)"

proc firstScriptBody(html: string): string =
  ## The exact text between the emitted `<script ...>` and `</script>` --
  ## the bytes a browser hashes for a CSP `'sha256-...'` source. Mirrors
  ## `test_csp_analytics.innerScript`.
  let open = html.find(">")
  let close = html.find("</script>")
  doAssert open >= 0 and close > open
  html[open + 1 ..< close]

suite "content image markup -- SSR string mode (Tier 2, dual-target)":

  test "a content image renders inside a figure wrapper with a full-size affordance":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(wideImageMd))
    check html.contains("<span class=\"" & imageFigureClass & "\">")
    check html.contains("<img class=\"" & imageClass &
      "\" src=\"/img/wide.png\" alt=\"A wide diagram\" />")
    # The affordance is a REAL link to the image file: with JS it opens the
    # in-page viewer, without JS it still opens the full-size image.
    check html.contains("<a class=\"" & imageExpandClass & "\" href=\"/img/wide.png\"")
    check html.contains("target=\"_blank\"")
    check html.contains("rel=\"noopener noreferrer\"")
    check html.contains("aria-label=\"" & imageExpandLabel("A wide diagram") & "\"")

  test "SSR never asserts data-zoomable -- downscaling is a client-measured fact":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(wideImageMd))
    check not html.contains(imageZoomableAttr)

  test "an image with no alt text still gets a labelled affordance":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks("![](/img/plain.png)"))
    check html.contains("alt=\"\"")
    check html.contains("aria-label=\"" & imageExpandLabel("") & "\"")

  test "a hostile alt cannot break out of the alt attribute or the aria-label":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks("![\"><b>bad](/x.png)"))
    ## The quote that would end an attribute is escaped in BOTH places the
    ## alt is interpolated (the `<img>`'s own `alt` and the affordance's
    ## `aria-label`). `<`/`>` inside a quoted attribute value are inert, and
    ## the framework's `escapeAttr` deliberately leaves them (see
    ## `isonim/ssr/escape`), so this asserts the framework's real contract.
    check not html.contains("\"><b>bad")
    check html.contains("alt=\"&quot;><b>bad\"")
    check html.contains("aria-label=\"" & imageExpandLabelBase & ": &quot;><b>bad\"")

  test "a card icon (chrome, not content) keeps its plain img -- no affordance":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(
      ":::cards\n:::card title=\"Start\" icon=\"/img/s.svg\" href=\"start.md\"\nFirst steps.\n:::"))
    check html.contains("<img src=\"/img/s.svg\" alt=\"\" />")
    check not html.contains(imageFigureClass)
    check not html.contains(imageExpandClass)

suite "content image markup -- MockRenderer tree mode (Tier 2, dual-target)":

  test "the tree backend builds the same figure/img/affordance shape as SSR":
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, parseMarkdownBlocks(wideImageMd))
    let fig = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "span" and
      n.attributes.getOrDefault("class") == imageFigureClass)
    require fig != nil
    check fig.children.len == 2

    let img = fig.children[0]
    check img.tag == "img"
    check getAttribute(r, img, "class") == imageClass
    check getAttribute(r, img, "src") == "/img/wide.png"
    check getAttribute(r, img, "alt") == "A wide diagram"

    let expand = fig.children[1]
    check expand.tag == "a"
    check getAttribute(r, expand, "class") == imageExpandClass
    check getAttribute(r, expand, "href") == "/img/wide.png"
    check getAttribute(r, expand, "target") == "_blank"
    check getAttribute(r, expand, "rel") == "noopener noreferrer"
    check getAttribute(r, expand, "aria-label") == imageExpandLabel("A wide diagram")

  test "the tree backend leaves data-zoomable to the client too (hydration parity)":
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, parseMarkdownBlocks(wideImageMd))
    let fig = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "span" and
      n.attributes.getOrDefault("class") == imageFigureClass)
    require fig != nil
    check getAttribute(r, fig, imageZoomableAttr) == ""

suite "the image-viewer client script (Tier 2, dual-target)":

  test "the emitted script body is byte-identical to the body the CSP hashes":
    let html = renderImageViewerScriptHtml()
    check html.startsWith("<script id=\"" & imageViewerScriptId & "\">")
    check html.endsWith("</script>")
    check firstScriptBody(html) == imageViewerScriptBody()

  test "the script can never break out of its own <script> element":
    check not imageViewerScriptBody().contains("</script")

  test "the script decides 'downscaled' from natural vs rendered width":
    let body = imageViewerScriptBody()
    check body.contains("naturalWidth")
    check body.contains("clientWidth")
    check body.contains(imageZoomableAttr)

  test "the script re-measures on viewport resize and on image load":
    let body = imageViewerScriptBody()
    check body.contains("'resize'")
    check body.contains("'load'")

  test "the overlay is a labelled modal dialog closed by Escape, and restores focus":
    let body = imageViewerScriptBody()
    check body.contains("'dialog'")
    check body.contains("aria-modal")
    check body.contains("Escape")
    check body.contains("activeElement")
    check body.contains("'Tab'")            ## focus trap
    check body.contains(imageOverlayCloseClass)
    check body.contains(imageViewerRootOpenAttr) ## background-scroll lock
    ## Closing must put the reader back exactly where they were: refocusing the
    ## affordance would scroll it into view, and releasing an `overflow:hidden`
    ## scroll lock drops the document scroll offset on some engines -- both are
    ## undone explicitly. The end-to-end outcome (scroll preserved across
    ## open+close on a scrolled page) is asserted in a real browser.
    check body.contains("preventScroll")
    check body.contains("window.scrollTo(savedScrollX,savedScrollY)")

  test "a strict CSP whitelists the image-viewer script by hash":
    var cfg = docsConfig()
    cfg.csp = strictCspConfig()
    let top = renderHeadSecurityTop(cfg)
    check top.contains(cspHashSource(imageViewerScriptBody()))

  test "the runtime-only overlay classes are exported for the CSS-purge safelist":
    ## The overlay is built by the client, so its classes appear in no
    ## static page -- without this safelist the SSG purge would strip the
    ## overlay's styling and ship an unstyled viewer.
    check imageViewerRuntimeClasses.len > 0
    for cls in imageViewerRuntimeClasses:
      check cls.startsWith("docs-image-overlay")

when not defined(js):
  import std/[os, sets]
  import ../../src/ssr
  import ../../src/build_site
  import ../../src/core/asset_pipeline
  import ./helpers/fixture_dir

  const fixtureCfg = DocsConfig(siteTitle: "Fixture Docs",
                                 siteDescription: "Fixture docs site.",
                                 defaultRoute: "/", stylesheetHref: "/assets/style.css")

  suite "image viewer SSR wiring -- real renderRoute (Tier 3, C-target)":

    test "a rendered page carries the figure markup and exactly one viewer script":
      withFixtureDir:
        writeFixtureFile(fixtureDir, "guide/shot.md", """---
title: Screenshot Page
description: A page with a big screenshot.
---
Here it is.

![A wide diagram](/img/wide.png)
""")
        let (status, html) = renderRoute("/guide/shot", fixtureDir, cfg = fixtureCfg)
        check status == 200
        check html.contains("class=\"" & imageFigureClass & "\"")
        check html.contains("class=\"" & imageExpandClass & "\"")
        check html.count("id=\"" & imageViewerScriptId & "\"") == 1
        # The script is emitted at the END of <body>, so the DOM it measures
        # is already parsed when it runs.
        check html.find("id=\"" & imageViewerScriptId & "\"") < html.find("</body>")
        check html.find("class=\"" & imageFigureClass & "\"") <
          html.find("id=\"" & imageViewerScriptId & "\"")

    test "a page with no image carries the viewer script too (SPA route swaps)":
      withFixtureDir:
        writeFixtureFile(fixtureDir, "guide/text.md", """---
title: Text Page
description: No images here.
---
Just words.
""")
        let (status, html) = renderRoute("/guide/text", fixtureDir, cfg = fixtureCfg)
        check status == 200
        check not html.contains("class=\"" & imageFigureClass & "\"")
        check html.count("id=\"" & imageViewerScriptId & "\"") == 1

  suite "image viewer SSG wiring -- real buildSite over the real stylesheet (Tier 3, C-target)":

    test "the purged, hashed stylesheet keeps the runtime-only overlay rules":
      withFixtureDir:
        writeFixtureFile(fixtureDir, "content" / "index.md", """---
title: Home
description: Home page.
---

A screenshot:

![A wide diagram](/img/wide.png)
""")
        let outDir = fixtureDir / "out"
        # `assetsDir` defaults to the framework's OWN `assets/` (tests run
        # from the repo root), i.e. the real stylesheet a consumer ships.
        let pages = buildSite(outDir = outDir, contentDir = fixtureDir / "content",
                              cfg = fixtureCfg)
        check pages > 0

        var css = ""
        for path in walkDirRec(outDir / "assets"):
          if path.endsWith(".css"): css = readFile(path)
        check css.len > 0
        check css.contains("." & imageFigureClass)
        check css.contains("." & imageExpandClass)
        # Runtime-only: never present in any static page's HTML.
        check css.contains("." & imageOverlayClass)
        check css.contains("." & imageOverlayImageClass)

    test "without the safelist the purge WOULD strip the overlay rules (the hazard is real)":
      let pageHtml = renderMarkdownBodyHtml(parseMarkdownBlocks(wideImageMd))
      let purged = purgeCss(readFile("assets" / "style.css"), extractUsedClasses(pageHtml))
      check not purged.contains("." & imageOverlayClass)
      var safelisted = extractUsedClasses(pageHtml)
      for cls in imageViewerRuntimeClasses:
        safelisted.incl cls
      check purgeCss(readFile("assets" / "style.css"), safelisted).contains("." & imageOverlayClass)
