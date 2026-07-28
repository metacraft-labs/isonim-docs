## Tier 1 + Tier 2 M3 deliverable 1 suite -- dual-target: both `nim c -r`
## and `nim js -r` must pass.
##
## Proves the `:::tabs` / `@tab Title` markdown block: `parseMarkdownBlocks`
## (`src/core/markdown_vm.nim`) turns it into a `bkTabs` block carrying
## ordered `TabPanel`s (each panel's own body re-parsed as a full nested
## block list, exactly like a top-level document -- not just paragraphs),
## and `markdown_view.renderTabs`/`renderTabsHtml` render a valid ARIA
## `tablist`/`tab`/`tabpanel` structure with a default-active first tab
## (roving `tabindex`, `aria-selected`, `hidden` on inactive panels) on
## both the MockRenderer/browser tree side and the SSR string side.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/components/markdown_view
import ./helpers/mock_tree

suite "docs markdown tabs -- pure parsing (Tier 1, dual-target)":
  test "parseMarkdownBlocks translates ':::tabs' / '@tab Title' into an ordered bkTabs block":
    let raw = ":::tabs\n@tab Nim\nSee `echo 1`.\n@tab Bash\necho 1\n:::"
    let blocks = parseMarkdownBlocks(raw)
    check blocks.len == 1
    check blocks[0].kind == bkTabs
    check blocks[0].tabs.len == 2
    check blocks[0].tabs[0].title == "Nim"
    check blocks[0].tabs[1].title == "Bash"

  test "parseMarkdownBlocks re-parses each tab panel's body as a full nested block list":
    let raw = ":::tabs\n@tab Nim\n```nim\nlet x = 1\n```\n@tab JSON\n```json\n{}\n```\n:::"
    let blocks = parseMarkdownBlocks(raw)
    let tabs = blocks[0].tabs
    check tabs[0].blocks.len == 1
    check tabs[0].blocks[0].kind == bkCodeFence
    check tabs[0].blocks[0].lang == "nim"
    check tabs[1].blocks[0].lang == "json"

  test "parseMarkdownBlocks preserves panel order exactly as authored":
    let raw = ":::tabs\n@tab First\nOne.\n@tab Second\nTwo.\n@tab Third\nThree.\n:::"
    let tabs = parseMarkdownBlocks(raw)[0].tabs
    check tabs.len == 3
    check tabs[0].title == "First"
    check tabs[1].title == "Second"
    check tabs[2].title == "Third"
    check spansText(tabs[0].blocks[0].spans) == "One."
    check spansText(tabs[2].blocks[0].spans) == "Three."

  test "parseMarkdownBlocks parses tabs alongside other blocks in document order":
    let raw = "# Title\n\n:::tabs\n@tab A\nBody A.\n:::\n\nAfter."
    let blocks = parseMarkdownBlocks(raw)
    check blocks.len == 3
    check blocks[0].kind == bkHeading
    check blocks[1].kind == bkTabs
    check blocks[2].kind == bkParagraph

suite "docs markdown tabs rendering -- MockRenderer (Tier 2, dual-target)":
  test "renderMarkdownBody: a tabs block renders a tablist with one tab button per panel":
    let blocks = parseMarkdownBlocks(":::tabs\n@tab Nim\nA.\n@tab Bash\nB.\n:::")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let tabsWrapper = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "div" and getAttribute(r, n, "class") == tabsClass)
    require tabsWrapper != nil

    let tablistEl = findWhere(tabsWrapper, proc(n: MockNode): bool =
      getAttribute(r, n, "role") == "tablist")
    require tablistEl != nil
    check getAttribute(r, tablistEl, "class") == tablistClass

    let tabButtons = findAllByTag(tablistEl, "button")
    check tabButtons.len == 2
    check textContent(tabButtons[0]) == "Nim"
    check textContent(tabButtons[1]) == "Bash"
    for btn in tabButtons:
      check getAttribute(r, btn, "role") == "tab"

  test "renderMarkdownBody: the first tab is selected/focusable by default, the rest are not":
    let blocks = parseMarkdownBlocks(":::tabs\n@tab Nim\nA.\n@tab Bash\nB.\n@tab JSON\nC.\n:::")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    let tabButtons = findAllByTag(root, "button")
    check tabButtons.len == 3

    check getAttribute(r, tabButtons[0], "aria-selected") == "true"
    check getAttribute(r, tabButtons[0], "tabindex") == "0"
    for btn in tabButtons[1 .. ^1]:
      check getAttribute(r, btn, "aria-selected") == "false"
      check getAttribute(r, btn, "tabindex") == "-1"

  test "renderMarkdownBody: each tabpanel is ARIA-linked to its tab and only the default panel is visible":
    let blocks = parseMarkdownBlocks(":::tabs\n@tab Nim\nNim body.\n@tab Bash\nBash body.\n:::")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let tabButtons = findAllByTag(root, "button")
    let panels = findWhere(root, proc(n: MockNode): bool =
        n.kind == mnkElement and n.tag == "div" and getAttribute(r, n, "class") == tabsClass)
      .children
    let panelEls = block:
      var found: seq[MockNode] = @[]
      for n in panels:
        if getAttribute(r, n, "role") == "tabpanel": found.add n
      found
    check panelEls.len == 2

    check getAttribute(r, panelEls[0], "aria-labelledby") == getAttribute(r, tabButtons[0], "id")
    check getAttribute(r, panelEls[1], "aria-labelledby") == getAttribute(r, tabButtons[1], "id")
    check getAttribute(r, tabButtons[0], "aria-controls") == getAttribute(r, panelEls[0], "id")

    check getAttribute(r, panelEls[0], "hidden") == ""
    check getAttribute(r, panelEls[1], "hidden") == "hidden"
    check textContent(panelEls[0]).contains("Nim body.")
    check textContent(panelEls[1]).contains("Bash body.")

  test "renderMarkdownBody: two tabs blocks on one page get distinct, non-colliding element ids":
    let blocks = parseMarkdownBlocks(
      ":::tabs\n@tab A\nOne.\n:::\n\n:::tabs\n@tab B\nTwo.\n:::")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    let tabButtons = findAllByTag(root, "button")
    check tabButtons.len == 2
    check getAttribute(r, tabButtons[0], "id") != getAttribute(r, tabButtons[1], "id")

suite "docs markdown tabs rendering -- SSR string (Tier 2, dual-target)":
  test "renderMarkdownBodyHtml: a tabs block serializes a tablist and tabpanels with matching ARIA ids":
    let raw = ":::tabs\n@tab Nim\nNim body.\n@tab Bash\nBash body.\n:::"
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(raw))

    check html.contains("class=\"" & tabsClass & "\"")
    check html.contains("role=\"tablist\"")
    check html.contains("role=\"tab\"")
    check html.contains("role=\"tabpanel\"")
    check html.contains(">Nim</button>")
    check html.contains(">Bash</button>")
    check html.contains("Nim body.")
    check html.contains("Bash body.")

  test "renderMarkdownBodyHtml: the first tab/panel is the default-active one, the rest start hidden":
    let raw = ":::tabs\n@tab Nim\nA.\n@tab Bash\nB.\n:::"
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(raw))

    check html.contains("aria-selected=\"true\"")
    check html.contains("aria-selected=\"false\"")
    check html.contains("tabindex=\"0\"")
    check html.contains("tabindex=\"-1\"")
    check html.contains(" hidden>")
    # The default-active panel's own <div ...> tag must NOT carry `hidden`
    # right before its content -- i.e. exactly one panel is hidden, not both.
    check html.count(" hidden>") == 1

  test "renderMarkdownBodyHtml: tab titles and panel content are HTML-escaped":
    let raw = ":::tabs\n@tab A & B\nUse `<x>` & `y`.\n:::"
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(raw))
    check html.contains("A &amp; B")
    check html.contains("&amp;")
