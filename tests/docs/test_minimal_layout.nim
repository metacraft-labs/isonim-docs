## Tier 2 test for the minimal-chrome (auth-style) page layout variant.
##
## A page can opt into a MINIMAL layout (via `layout: minimal` front matter,
## threaded through by `ssr.renderRoute` / `main_web.buildRouteApp`): a logo-only
## top bar and a single centered card holding the page `<h1>` + the markdown
## body, with NO sidebar, header nav, TOC, prev/next pager, footer, or search
## overlay. This pins that:
##   * a minimal page OMITS the docs chrome (nav region, header nav, footer,
##     search overlay) and centers its content in a `docs-minimal-card`;
##   * a normal (default) page KEEPS the full chrome -- byte-for-byte the
##     pre-existing behaviour, so the layout switch is additive.
## Both the SSR-string path and the MockRenderer tree path are exercised.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/core/shell_vm
import ../../src/core/config
import ../../src/components/shell
import ../../src/components/markdown_page
import ./helpers/mock_tree

const body = "Sign in to your account.\n\n" &
  ":::form action=\"/sign-in\" submit=\"Sign in\"\n" &
  "@field name=\"Email\" label=\"Email address\" type=email required\n" &
  "@field name=\"Password\" label=\"Password\" type=password required\n" &
  "@field name=\"remember\" label=\"Remember me\" type=checkbox\n" &
  ":::"

suite "minimal-chrome page layout (SSR string)":
  let blocks = parseMarkdownBlocks(body)

  test "a minimal page omits sidebar/header-nav/footer/overlay and centers content":
    let html = renderMarkdownPageHtml("Sign In", blocks,
      siteLogo = "/assets/img/logo.svg", logoHref = "/",
      chrome = DocsChrome(headerLinks: @[(label: "FAQ", href: "/faq")]),
      minimal = true)
    # The minimal frame + centered card + logo-only nav are present.
    check html.contains(frameMinimalClass)
    check html.contains("class=\"" & minimalNavClass & "\"")
    check html.contains("class=\"" & minimalCardClass & "\"")
    check html.contains("class=\"" & mainClass & " " & mainMinimalClass & "\"")
    check html.contains("<img class=\"" & logoClass & "\" src=\"/assets/img/logo.svg\"")
    # The page title is the card's own <h1>, and the form is inside.
    check html.contains("class=\"" & contentTitleClass & "\">Sign In</h1>")
    check html.contains("class=\"docs-md-form\"")
    # NONE of the full docs chrome is emitted.
    check not html.contains("id=\"" & regionId(prNav) & "\"")
    check not html.contains("id=\"" & regionId(prHeader) & "\"")
    check not html.contains("class=\"" & footerClass & "\"")
    check not html.contains(headerNavClass)          # no header nav buttons
    check not html.contains("docs-search-overlay")   # no search overlay

  test "a normal (default) page keeps the full chrome -- sidebar/header/footer":
    let html = renderMarkdownPageHtml("Sign In", blocks,
      siteLogo = "/assets/img/logo.svg", logoHref = "/",
      chrome = DocsChrome(headerLinks: @[(label: "FAQ", href: "/faq")]))
    # Full chrome present...
    check html.contains("id=\"" & regionId(prHeader) & "\"")
    check html.contains("id=\"" & regionId(prNav) & "\"")
    check html.contains("class=\"" & footerClass & "\"")
    check html.contains(headerNavClass)
    # ...and NOT the minimal frame.
    check not html.contains(frameMinimalClass)
    check not html.contains(minimalCardClass)

suite "minimal-chrome page layout (MockRenderer tree)":
  let blocks = parseMarkdownBlocks(body)

  test "the minimal tree has a centered card + logo and no nav region":
    let r = MockRenderer()
    let root = renderMarkdownPage[MockRenderer, MockNode](r, "Sign In", blocks,
      siteLogo = "/assets/img/logo.svg", logoHref = "/", minimal = true)
    let card = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class") == minimalCardClass)
    require card != nil
    check findByTag(card, "form") != nil
    let img = findByTag(root, "img")
    require img != nil
    check getAttribute(r, img, "src") == "/assets/img/logo.svg"
    # No full-chrome nav region in the minimal tree.
    check findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "id") == regionId(prNav)) == nil
