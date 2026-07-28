## Tier 2 (MockRenderer) bootstrap suite -- dual-target: both `nim c -r`
## and `nim js -r` must pass.
##
## Proves the minimal docs shell (`src/components/shell.renderShell`)
## renders a title, a body slot, and a static-asset hook (a stylesheet
## `<link>` carrying the right `href`) without any browser DOM, using
## `MockRenderer`.

import std/unittest
import isonim/testing/mock_dom
import ../../src/core/content
import ../../src/core/config
import ../../src/core/shell_vm
import ../../src/components/shell
import ./helpers/mock_tree

suite "docs shell -- MockRenderer (Tier 2, dual-target)":
  test "renders title, body slot, and stylesheet asset hook":
    let page = parseDocsPage("# Getting Started\n\nWelcome to isonim-docs.", "fixture:inline")
    let cfg = DocsConfig(siteTitle: "x", siteDescription: "y", defaultRoute: "/",
                          stylesheetHref: "/assets/docs.css")
    let vm = shellViewModel(page, cfg)
    let r = MockRenderer()

    let root = renderShell[MockRenderer, MockNode](r, vm)

    check root.kind == mnkElement
    check root.tag == "div"
    check getAttribute(r, root, "class") == shellClass

    # Static-asset hook: a real stylesheet <link>, not just a placeholder.
    let link = findByTag(root, "link")
    require link != nil
    check getAttribute(r, link, "rel") == "stylesheet"
    check getAttribute(r, link, "href") == "/assets/docs.css"

    # Title
    let h1 = findByTag(root, "h1")
    require h1 != nil
    check getAttribute(r, h1, "class") == titleClass
    check textContent(h1) == "Getting Started"

    # Body slot -- the second <div> in document order (the first is the
    # shell root itself).
    let divs = findAllByTag(root, "div")
    check divs.len == 2
    check divs[0] == root
    let bodyDiv = divs[1]
    check getAttribute(r, bodyDiv, "class") == bodyClass
    check textContent(bodyDiv) == "Welcome to isonim-docs."

  test "renders an empty body slot for a title-only page without crashing":
    let page = parseDocsPage("# Solo Title", "fixture:inline-2")
    let vm = shellViewModel(page)
    let r = MockRenderer()
    let root = renderShell[MockRenderer, MockNode](r, vm)
    let h1 = findByTag(root, "h1")
    require h1 != nil
    check textContent(h1) == "Solo Title"
