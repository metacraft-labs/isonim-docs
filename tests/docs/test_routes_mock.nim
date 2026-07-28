## Tier 2 (MockRenderer) rendering-shell suite -- dual-target: both
## `nim c -r` and `nim js -r` must pass.
##
## Proves the M1 rendering shell (`src/components/shell.renderSiteFrame`
## / `renderDocumentHead`, `src/core/shell_vm`'s `SiteShellViewModel`
## builders): shell composition (header/nav/main/footer regions), title
## injection (formatted document title + plain page title), stable
## layout region IDs (`regionId`) for later navigation/search wiring,
## and a distinct not-found rendering shape -- all driven off the real
## typed route contract from `src/core/routes` (M1 deliverable 1), not a
## parallel ad hoc structure.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/routes
import ../../src/core/content
import ../../src/core/config
import ../../src/core/shell_vm
import ../../src/components/shell
import ./helpers/mock_tree

suite "docs rendering shell -- MockRenderer (Tier 2, dual-target)":
  let cfg = DocsConfig(siteTitle: "IsoNim Docs",
                        siteDescription: "Site-wide fallback description.",
                        defaultRoute: "/", stylesheetHref: "/assets/docs.css")

  test "formatPageTitle: page title composes with the site title; empty page title falls back to it":
    check formatPageTitle("Getting Started", "IsoNim Docs") == "Getting Started — IsoNim Docs"
    check formatPageTitle("", "IsoNim Docs") == "IsoNim Docs"

  test "buildDocumentHead: metadata hook -- route meta wins, falls back to site config":
    let withDescription = buildDocumentHead(
      RouteMeta(title: "Getting Started", description: "Learn the basics."), cfg)
    check withDescription.title == "Getting Started — IsoNim Docs"
    check withDescription.description == "Learn the basics."
    check withDescription.stylesheetHref == cfg.stylesheetHref

    let withoutDescription = buildDocumentHead(RouteMeta(title: "Home"), cfg)
    check withoutDescription.description == cfg.siteDescription

  test "renderDocumentHead: document head builder + asset injection produce title/meta/link":
    let head = buildDocumentHead(
      RouteMeta(title: "Getting Started", description: "Learn the basics."), cfg)
    let r = MockRenderer()
    let headNode = renderDocumentHead[MockRenderer, MockNode](r, head)

    check headNode.kind == mnkElement
    check headNode.tag == "head"

    # `<meta charset="utf-8">` is the FIRST child of <head> (UTF-8 decode
    # fix) -- in lock-step with `renderDocumentHeadHtml`. It carries a
    # `charset` attribute (not `name`), so it precedes the description meta.
    require headNode.children.len > 0
    let charsetNode = headNode.children[0]
    check charsetNode.kind == mnkElement
    check charsetNode.tag == "meta"
    check getAttribute(r, charsetNode, "charset") == "utf-8"

    let titleNode = findByTag(headNode, "title")
    require titleNode != nil
    check textContent(titleNode) == "Getting Started — IsoNim Docs"

    let metaNode = findWhere(headNode, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "meta" and getAttribute(r, n, "name") == "description")
    require metaNode != nil
    check getAttribute(r, metaNode, "content") == "Learn the basics."

    let linkNode = findByTag(headNode, "link")
    require linkNode != nil
    check getAttribute(r, linkNode, "rel") == "stylesheet"
    check getAttribute(r, linkNode, "href") == cfg.stylesheetHref

    # M6 deliverable 1 (SEO): the head now also emits a canonical link,
    # OpenGraph + Twitter card metadata, and a JSON-LD document -- the
    # tree path must stay in lock-step with `renderDocumentHeadHtml`.
    let canonical = findWhere(headNode, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "link" and getAttribute(r, n, "rel") == "canonical")
    require canonical != nil
    # No baseUrl on `cfg` here, so the canonical URL is root-relative.
    check getAttribute(r, canonical, "href") == "/"

    let ogTitle = findWhere(headNode, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "meta" and getAttribute(r, n, "property") == "og:title")
    require ogTitle != nil
    check getAttribute(r, ogTitle, "content") == "Getting Started — IsoNim Docs"

    let ogDesc = findWhere(headNode, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "meta" and getAttribute(r, n, "property") == "og:description")
    require ogDesc != nil
    check getAttribute(r, ogDesc, "content") == "Learn the basics."

    let twitterCard = findWhere(headNode, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "meta" and getAttribute(r, n, "name") == "twitter:card")
    require twitterCard != nil
    check getAttribute(r, twitterCard, "content") == "summary"

    let ld = findByTag(headNode, "script")
    require ld != nil
    check getAttribute(r, ld, "type") == "application/ld+json"
    check textContent(ld).contains("\"@type\":\"TechArticle\"")

  test "renderSiteFrame: shell composition, title injection, and stable layout region IDs for a real route":
    let entry = newRouteEntry("/guide/getting-started", pkDoc,
      meta = RouteMeta(title: "Getting Started", description: "Learn the basics."))
    let page = parseDocsPage("# Getting Started\n\nWelcome to isonim-docs.", "fixture:inline")
    let vm = siteShellViewModel(entry, page, cfg)
    let r = MockRenderer()

    let root = renderSiteFrame[MockRenderer, MockNode](r, vm)
    check root.kind == mnkElement
    check root.tag == "div"
    check getAttribute(r, root, "class") == frameClass

    let headerNode = findByTag(root, "header")
    require headerNode != nil
    check getAttribute(r, headerNode, "id") == regionId(prHeader)
    check getAttribute(r, headerNode, "class") == headerClass
    let h1 = findByTag(headerNode, "h1")
    require h1 != nil
    check textContent(h1) == "Getting Started"

    let navNode = findByTag(root, "nav")
    require navNode != nil
    check getAttribute(r, navNode, "id") == regionId(prNav)
    check getAttribute(r, navNode, "class") == navClass

    let mainNode = findByTag(root, "main")
    require mainNode != nil
    check getAttribute(r, mainNode, "id") == regionId(prMain)
    check getAttribute(r, mainNode, "class") == mainClass
    let bodyDiv = findByTag(mainNode, "div")
    require bodyDiv != nil
    check getAttribute(r, bodyDiv, "class") == bodyClass
    check textContent(bodyDiv) == "Welcome to isonim-docs."

    let footerNode = findByTag(root, "footer")
    require footerNode != nil
    check getAttribute(r, footerNode, "id") == regionId(prFooter)
    check getAttribute(r, footerNode, "class") == footerClass

    # Region IDs are stable literal anchors, not incidental to this VM.
    check regionId(prHeader) == "docs-region-header"
    check regionId(prNav) == "docs-region-nav"
    check regionId(prMain) == "docs-region-main"
    check regionId(prFooter) == "docs-region-footer"

  test "renderSiteFrame: not-found rendering shape is structurally distinct from a real page":
    let entry = notFoundEntry()
    let vm = notFoundShellViewModel(entry, cfg)
    let r = MockRenderer()

    let root = renderSiteFrame[MockRenderer, MockNode](r, vm)
    let headerNode = findByTag(root, "header")
    require headerNode != nil
    let h1 = findByTag(headerNode, "h1")
    require h1 != nil
    check textContent(h1) == "Not Found"

    let mainNode = findByTag(root, "main")
    require mainNode != nil
    check getAttribute(r, mainNode, "id") == regionId(prMain)

    # Distinct shape: a not-found block, no ordinary body-content div.
    let notFoundDiv = findByTag(mainNode, "div")
    require notFoundDiv != nil
    check getAttribute(r, notFoundDiv, "class") == notFoundClass
    check findAllByTag(mainNode, "div").len == 1

    # Regions stay present even for not-found, so nav/search wiring can
    # rely on them unconditionally.
    check findByTag(root, "nav") != nil
    check findByTag(root, "footer") != nil
