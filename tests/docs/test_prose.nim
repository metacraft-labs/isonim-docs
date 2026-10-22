## The real shared AST crosses a Signal copy into both docs renderers on C/JS.
## MockRenderer is IsoNim's headless renderer: no browser is needed for these
## semantic tree checks; SSR assertions independently check emitted HTML.
import std/[unittest, strutils]
import isonim/core/signals
import isonim/testing/mock_dom
import isonim/content/markdown
import ../../src/components/markdown_view
import ./helpers/mock_tree

suite "shared prose in docs":
  test "nested prose survives Signal copies and renders with docs blocks":
    let source = "> outer\n>\n> > inner ~~old~~[^a]\n\n![alt](plot.png)\n*Caption & <text>*\n\n- [x] done\n- [ ] open\n\n[^a]: note `value`"
    let state = createSignal(parseMarkdownDoc(source))
    let copied = state.val
    let r = MockRenderer()
    let tree = renderMarkdownBody[MockRenderer, MockNode](r, copied.blocks)
    check findAllByTag(tree, "blockquote").len == 2
    check findAllByTag(tree, "figure").len == 1
    check findByTag(tree, "figcaption").textContent == "Caption & <text>"
    check findByTag(tree, "del").textContent == "old"
    check getAttribute(r, findByTag(tree, "sup"), "id") == "fnref-1"
    let boxes = findAllByTag(tree, "input")
    check boxes.len == 2
    check getAttribute(r, boxes[0], "checked") == "checked"
    check getAttribute(r, boxes[1], "checked") == ""
    let html = renderMarkdownBodyHtml(copied.blocks)
    check html.contains("<blockquote><p class=\"docs-md-paragraph\">outer</p><blockquote>")
    check html.contains("<del>old</del>")
    check html.contains("<figcaption>Caption &amp; &lt;text&gt;</figcaption>")
    check html.contains("href=\"#fnref-1\" role=\"doc-backlink\"")
    check html.contains("<code>value</code>")

  test "titles and repeated footnote references agree in both renderer modes":
    let blocks = parseMarkdownBlocks("[x](https://example.test \"A & B\") [^a] [^a]\n\n[^a]: body")
    let r = MockRenderer()
    let tree = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    check getAttribute(r, findByTag(tree, "a"), "title") == "A & B"
    check findAllByTag(tree, "sup").len == 2
    check getAttribute(r, findAllByTag(tree, "sup")[1], "id") == "fnref-1-2"
    check renderMarkdownBodyHtml(blocks).contains("title=\"A &amp; B\"")

  test "heading footnotes have real backlinks while existing heading text stays literal":
    let blocks = parseMarkdownBlocks("## Before[^a]\n\n## A `literal`\n\n[^a]: detail")
    let r = MockRenderer()
    let tree = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    check getAttribute(r, findByTag(tree, "sup"), "id") == "fnref-1"
    let html = renderMarkdownBodyHtml(blocks)
    check html.contains("id=\"before\">Before<sup")
    check html.contains("id=\"a-literal\">A `literal`</h2>")

  test "nested tab components in different footnotes keep distinct IDs":
    let doc = parseMarkdownDoc("Use[^a] and[^b].\n\n[^a]: :::tabs\n    @tab One\n    one\n    :::\n\n[^b]: :::tabs\n    @tab Two\n    two\n    :::")
    let r = MockRenderer()
    let tree = renderMarkdownBody[MockRenderer, MockNode](r, doc.blocks)
    let buttons = findAllByTag(tree, "button")
    check buttons.len == 2
    let first = getAttribute(r, buttons[0], "id")
    let second = getAttribute(r, buttons[1], "id")
    check first.len > 0
    check second.len > 0
    check first != second
    let html = renderMarkdownBodyHtml(doc.blocks)
    check html.count("id=\"" & first & "\"") == 1
    check html.count("id=\"" & second & "\"") == 1

  test "legacy heading link and image syntax stays literal in both renderers":
    let doc = parseMarkdownDoc("## [text](missing.md)\n\n## ![alt](missing.png)")
    let r = MockRenderer()
    let tree = renderMarkdownBody[MockRenderer, MockNode](r, doc.blocks)
    check findAllByTag(tree, "a").len == 0
    check findAllByTag(tree, "img").len == 0
    let html = renderMarkdownBodyHtml(doc.blocks)
    check html.contains(">[text](missing.md)</h2>")
    check html.contains(">![alt](missing.png)</h2>")
