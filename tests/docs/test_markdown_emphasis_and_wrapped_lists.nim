## Dual-target (`nim c -r` and `nim js -r`) suite for:
## 1. Indented multi-line list item continuations in `isonim/content/markdown`.
## 2. Inline emphasis (`**strong**`, `*em*`, `***strong+em***`, cross-span
##    emphasis over `<code>`/`<a>`, escaped `\*`, and untouched `snake_case` /
##    spaced arithmetic `*`) in `components/markdown_view` across both
##    MockRenderer tree mode and SSR string mode.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import isonim/content/markdown
import ../../src/components/markdown_view
import ./helpers/mock_tree

suite "wrapped list item continuations (dual-target)":
  test "unordered list merges indented continuation lines instead of splitting into a paragraph":
    let md =
      "- First item wrapped across\n" &
      "  two source lines.\n" &
      "- Second item stays separate."
    let blocks = parseMarkdownBlocks(md)
    check blocks.len == 1
    check blocks[0].kind == bkList

    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    let items = findAllByTag(root, "li")
    check items.len == 2
    check textContent(items[0]) == "First item wrapped across two source lines."
    check textContent(items[1]) == "Second item stays separate."
    check findAllByTag(root, "p").len == 0

  test "ordered list merges indented continuation lines while keeping nested lists separate":
    let md =
      "1. Install the binary from\n" &
      "   the official repository.\n" &
      "   - Sub-bullet stays its own list\n" &
      "2. Run the check."
    let blocks = parseMarkdownBlocks(md)
    check blocks.len == 3
    check blocks[0].kind == bkList
    check blocks[0].listKind == lkOrdered
    check spansText(blocks[0].items[0]) == "Install the binary from the official repository."
    check blocks[1].kind == bkList
    check blocks[1].listKind == lkUnordered

suite "inline emphasis in docs markdown_view (MockRenderer + SSR, dual-target)":
  test "renders **strong**, *em*, and ***both*** identically in tree and SSR modes":
    let blocks = parseMarkdownBlocks("Use **strong**, *italic*, and ***both*** here.")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let strongs = findAllByTag(root, "strong")
    let ems = findAllByTag(root, "em")
    check strongs.len == 2
    check ems.len == 2
    check textContent(strongs[0]) == "strong"
    check textContent(ems[0]) == "italic"
    check textContent(strongs[1]) == "both"

    let html = renderMarkdownBodyHtml(blocks)
    check html.contains("<strong>strong</strong>")
    check html.contains("<em>italic</em>")
    check html.contains("<strong><em>both</em></strong>")

  test "renders cross-span emphasis wrapping inline code and links":
    let blocks = parseMarkdownBlocks("Read **the `repro.nim` [guide](/guide)** carefully.")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    let strongEl = findByTag(root, "strong")
    require strongEl != nil
    check findByTag(strongEl, "code") != nil
    check findByTag(strongEl, "a") != nil

    let html = renderMarkdownBodyHtml(blocks)
    check html.contains("<strong>the <code>repro.nim</code> <a href=\"/guide\">guide</a></strong>")

  test "leaves escaped asterisks, spaced multiplication, and snake_case_identifiers literal":
    let blocks = parseMarkdownBlocks("Keep \\*BSD, 2 * 3 * 4, and my_var_name literal.")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    check findAllByTag(root, "em").len == 0
    check findAllByTag(root, "strong").len == 0

    let html = renderMarkdownBodyHtml(blocks)
    check html.contains("Keep *BSD, 2 * 3 * 4, and my_var_name literal.")
