## Tier 2 (MockRenderer + SSR string) M2 markdown ViewModel rendering
## suite -- dual-target: both `nim c -r` and `nim js -r` must pass.
##
## Proves `src/components/markdown_view.nim` renders the block ViewModel
## from `src/core/markdown_vm.nim` (M2 deliverable 2) identically on the
## MockRenderer/browser tree side and the SSR string side: headings
## (with stable anchor IDs), paragraphs with inline code/links/images,
## lists, code fences, admonitions, and tables.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/components/markdown_view
import ./helpers/mock_tree

suite "docs markdown ViewModel rendering -- MockRenderer (Tier 2, dual-target)":
  test "renderMarkdownBody: a heading carries its stable anchor ID and text":
    let blocks = parseMarkdownBlocks("# Getting Started")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    check getAttribute(r, root, "class") == markdownBodyClass

    let h1 = findByTag(root, "h1")
    require h1 != nil
    check getAttribute(r, h1, "id") == "getting-started"
    check textContent(h1) == "Getting Started"

  test "renderMarkdownBody: a paragraph renders inline code as a nested <code> element":
    let blocks = parseMarkdownBlocks("Run `nimble install` first.")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let p = findByTag(root, "p")
    require p != nil
    let code = findByTag(p, "code")
    require code != nil
    check textContent(code) == "nimble install"
    check textContent(p) == "Run nimble install first."

  test "renderMarkdownBody: a paragraph link/image render href/src and visible text/alt":
    let blocks = parseMarkdownBlocks(
      "See [the guide](./guide.md) and ![a diagram](./diagram.png).", "top.md")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let a = findByTag(root, "a")
    require a != nil
    check getAttribute(r, a, "href") == "/guide"
    check textContent(a) == "the guide"

    let img = findByTag(root, "img")
    require img != nil
    check getAttribute(r, img, "src") == "/diagram.png"
    check getAttribute(r, img, "alt") == "a diagram"

  test "renderMarkdownBody: an unordered list renders one <li> per item":
    let blocks = parseMarkdownBlocks("- First\n- Second")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let list = findByTag(root, "ul")
    require list != nil
    let items = findAllByTag(list, "li")
    check items.len == 2
    check textContent(items[0]) == "First"
    check textContent(items[1]) == "Second"

  test "renderMarkdownBody: an ordered list renders as <ol>":
    let blocks = parseMarkdownBlocks("1. Step one\n2. Step two")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    check findByTag(root, "ol") != nil
    check findByTag(root, "ul") == nil

  test "renderMarkdownBody: a code fence renders a language-tagged <code> nested in <pre>":
    let blocks = parseMarkdownBlocks("```nim\nlet x = 1\n```")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let pre = findByTag(root, "pre")
    require pre != nil
    let code = findByTag(pre, "code")
    require code != nil
    check getAttribute(r, code, "class") == "language-nim"
    check textContent(code) == "let x = 1"

  test "renderMarkdownBody: an admonition renders its kind label and body paragraphs":
    let blocks = parseMarkdownBlocks(":::warning\nBack up first.\n\nThen proceed.\n:::")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let divs = findAllByTag(root, "div")
    check divs.len == 2 # the body wrapper itself, plus the admonition's div
    let admonitionDiv = divs[1]
    check getAttribute(r, admonitionDiv, "class") == admonitionBaseClass & " " & admonitionBaseClass & "-warning"

    let label = findByTag(admonitionDiv, "strong")
    require label != nil
    check textContent(label) == "Warning"

    let paragraphs = findAllByTag(admonitionDiv, "p")
    check paragraphs.len == 2
    check textContent(paragraphs[0]) == "Back up first."
    check textContent(paragraphs[1]) == "Then proceed."

  test "renderMarkdownBody: a table renders header cells and body rows in order":
    let raw = "| Name | Kind |\n| --- | --- |\n| foo | bar |\n| baz | qux |"
    let blocks = parseMarkdownBlocks(raw)
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let table = findByTag(root, "table")
    require table != nil
    let headers = findAllByTag(table, "th")
    check headers.len == 2
    check textContent(headers[0]) == "Name"
    check textContent(headers[1]) == "Kind"

    let rows = findAllByTag(table, "tr")
    check rows.len == 3 # 1 header row + 2 body rows
    let cells = findAllByTag(table, "td")
    check cells.len == 4
    check textContent(cells[0]) == "foo"
    check textContent(cells[3]) == "qux"

suite "docs markdown ViewModel rendering -- SSR string (Tier 2, dual-target)":
  test "renderMarkdownBodyHtml: heading, paragraph, list, code fence, admonition, and table all serialize":
    let raw = "# Guide\n\nRun `nimble install`.\n\n- one\n- two\n\n```nim\necho 1\n```\n\n" &
      ":::tip\nUse the CLI.\n:::\n\n| A | B |\n| --- | --- |\n| 1 | 2 |"
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(raw))

    check html.startsWith("<div class=\"" & markdownBodyClass & "\">")
    check html.contains("<h1 class=\"" & headingClass & "\" id=\"guide\">Guide</h1>")
    check html.contains("<code>nimble install</code>")
    check html.contains("<ul class=\"" & listClass & "\"><li>one</li><li>two</li></ul>")
    check html.contains("<pre class=\"" & codeFenceClass &
      "\"><code class=\"language-nim\">echo <span class=\"tok-number\">1</span></code></pre>")
    check html.contains(admonitionBaseClass & "-tip")
    check html.contains("<table class=\"" & tableClass & "\">")
    check html.endsWith("</div>")

  test "renderMarkdownBodyHtml: link/image hrefs and text content are HTML-escaped":
    let html = renderMarkdownBodyHtml(
      parseMarkdownBlocks("[A & B](./a-and-b.md)", "top.md"))
    check html.contains("A &amp; B")
    check html.contains("href=\"/a-and-b\"")
