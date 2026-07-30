## Tier 1 + Tier 2 metacraft-theme-parity M2 suite -- dual-target: both
## `nim c -r` and `nim js -r` must pass.
##
## Proves the four content-agnostic markdown content components added to
## the framework markdown engine (`src/core/markdown_vm.nim` parsing +
## `src/components/markdown_view.nim` rendering):
##
##   * `:::cards` / `:::card title icon href`  -> a `bkCardGrid` of `<a>` cards
##   * `:::hero`  (title/subtitle + `:::button`s) -> a `bkHero`
##   * `:::button href variant`                -> a standalone `bkButton`
##   * `:::faq`   / `:::q title`               -> a `bkFaq` of `<details>`
##
## The suite asserts (a) each directive parses to the right AST node, (b)
## both the MockRenderer/browser-tree renderer AND the SSR-string renderer
## emit the expected structure (dual-target parity), and (c) the framework
## default is UNCHANGED: a plain markdown page containing none of these
## directives emits none of their markup.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/components/markdown_view
import ./helpers/mock_tree

# --- Pure parsing (Tier 1, dual-target) ---------------------------------

suite "docs content components -- parsing (Tier 1, dual-target)":
  test ":::cards / :::card parses into a bkCardGrid with title/icon/href + description":
    let raw = ":::cards\n" &
      ":::card title=\"Getting Started\" icon=\"/img/start.svg\" href=\"guide/start.md\"\n" &
      "Install and record your first trace.\n" &
      ":::card title=\"Reference\" icon=\"/img/ref.svg\" href=\"reference.md\"\n" &
      "The full API surface.\n" &
      ":::"
    let blocks = parseMarkdownBlocks(raw)
    check blocks.len == 1
    check blocks[0].kind == bkCardGrid
    check blocks[0].cards.len == 2
    check blocks[0].cards[0].title == "Getting Started"
    check blocks[0].cards[0].icon == "/img/start.svg"
    check blocks[0].cards[0].href == "guide/start.md"
    check spansText(blocks[0].cards[0].body[0]) == "Install and record your first trace."
    check blocks[0].cards[1].title == "Reference"
    check spansText(blocks[0].cards[1].body[0]) == "The full API surface."
    # M6: a plain `:::cards` grid has NO variant, so it keeps the default
    # (category-card) look byte-for-byte.
    check blocks[0].gridVariant == ""

  test "M6: :::cards variant=\"compact\" parses gridVariant, unknown/absent normalizes to \"\"":
    let compact = parseMarkdownBlocks(
      ":::cards variant=\"compact\"\n:::card title=\"Introduction\" href=\"a.md\"\nGetting Started\n:::")
    check compact.len == 1
    check compact[0].kind == bkCardGrid
    check compact[0].gridVariant == "compact"
    # An unrecognized value falls back to the default (empty) variant, so a
    # typo can never silently change an existing grid's look.
    let bogus = parseMarkdownBlocks(":::cards variant=\"wide\"\n:::card title=\"X\" href=\"x.md\"\nY\n:::")
    check bogus[0].gridVariant == ""

  test "M6: pageHasHero detects a landing (hero present) vs a normal article":
    check pageHasHero(parseMarkdownBlocks(":::hero title=\"Welcome\"\n:::"))
    check not pageHasHero(parseMarkdownBlocks("## Heading\n\nA paragraph.\n"))

  test ":::hero parses title/subtitle attrs and its :::button action list":
    let raw = ":::hero title=\"Welcome\" subtitle=\"Docs for everyone\"\n" &
      ":::button href=\"start.md\" variant=\"primary\"\n" &
      "Get Started\n" &
      ":::button href=\"support.md\" variant=\"secondary\"\n" &
      "Support\n" &
      ":::"
    let blocks = parseMarkdownBlocks(raw)
    check blocks.len == 1
    check blocks[0].kind == bkHero
    check blocks[0].heroTitle == "Welcome"
    check blocks[0].heroSubtitle == "Docs for everyone"
    check blocks[0].heroButtons.len == 2
    check blocks[0].heroButtons[0].label == "Get Started"
    check blocks[0].heroButtons[0].href == "start.md"
    check blocks[0].heroButtons[0].variant == "primary"
    check blocks[0].heroButtons[1].label == "Support"
    check blocks[0].heroButtons[1].variant == "secondary"

  test ":::button parses into a standalone bkButton (variant defaults to primary)":
    let raw = ":::button href=\"start.md\"\nGet Started\n:::"
    let blocks = parseMarkdownBlocks(raw)
    check blocks.len == 1
    check blocks[0].kind == bkButton
    check blocks[0].button.label == "Get Started"
    check blocks[0].button.href == "start.md"
    check blocks[0].button.variant == "primary"

  test ":::faq / :::q parses into a bkFaq with question + answer paragraphs":
    let raw = ":::faq\n" &
      ":::q title=\"What is it?\"\n" &
      "A time-traveling debugger.\n" &
      ":::q title=\"Which languages?\"\n" &
      "Noir, Ruby and more.\n" &
      ":::"
    let blocks = parseMarkdownBlocks(raw)
    check blocks.len == 1
    check blocks[0].kind == bkFaq
    check blocks[0].faqItems.len == 2
    check blocks[0].faqItems[0].question == "What is it?"
    check spansText(blocks[0].faqItems[0].answer[0]) == "A time-traveling debugger."
    check blocks[0].faqItems[1].question == "Which languages?"
    check spansText(blocks[0].faqItems[1].answer[0]) == "Noir, Ruby and more."

  test "components parse alongside other blocks in document order":
    let raw = "Intro paragraph.\n\n:::button href=\"x.md\"\nGo\n:::\n\nAfter."
    let blocks = parseMarkdownBlocks(raw)
    check blocks.len == 3
    check blocks[0].kind == bkParagraph
    check blocks[1].kind == bkButton
    check blocks[2].kind == bkParagraph

# --- Framework default unchanged (Tier 1, dual-target) ------------------

suite "docs content components -- framework default is unchanged (Tier 1, dual-target)":
  test "a plain markdown page parses to NONE of the new component block kinds":
    let raw = "## Heading\n\nA paragraph with `code` and a [link](other.md).\n\n" &
      "- one\n- two\n\n:::note\nAn admonition.\n:::\n\n" &
      "```nim\nlet x = 1\n```\n"
    for blk in parseMarkdownBlocks(raw):
      check blk.kind notin {bkCardGrid, bkHero, bkButton, bkFaq}

  test "a plain markdown page renders NONE of the component markup (SSR)":
    let raw = "## Heading\n\nA paragraph.\n\n- one\n- two\n\n:::tip\nTip.\n:::\n"
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(raw))
    check not html.contains("docs-md-card")
    check not html.contains("docs-md-hero")
    check not html.contains("docs-md-faq")
    check not html.contains("docs-md-button")

  test "a plain markdown page renders NONE of the component markup (MockRenderer)":
    let raw = "## Heading\n\nA paragraph.\n\n:::warning\nCareful.\n:::\n"
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, parseMarkdownBlocks(raw))
    check findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class").contains("docs-md-card")) == nil
    check findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class").contains("docs-md-hero")) == nil
    check findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "details") == nil

# --- MockRenderer / browser tree (Tier 2, dual-target) ------------------

suite "docs content components -- MockRenderer rendering (Tier 2, dual-target)":
  test "card grid renders each card as a focusable <a> with icon, title, description":
    let raw = ":::cards\n" &
      ":::card title=\"Start\" icon=\"/img/s.svg\" href=\"start.md\"\nFirst steps.\n:::"
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, parseMarkdownBlocks(raw))

    let grid = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class") == cardGridClass)
    require grid != nil

    let cards = findAllByTag(grid, "a")
    check cards.len == 1
    check getAttribute(r, cards[0], "class") == cardClass
    check getAttribute(r, cards[0], "href") == "start.md"

    let img = findByTag(cards[0], "img")
    require img != nil
    check getAttribute(r, img, "src") == "/img/s.svg"
    check textContent(cards[0]).contains("Start")
    check textContent(cards[0]).contains("First steps.")

  test "M6: a compact card grid tags grid + cards with the --compact modifier (MockRenderer)":
    let raw = ":::cards variant=\"compact\"\n:::card title=\"Introduction\" href=\"a.md\"\nGetting Started\n:::"
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, parseMarkdownBlocks(raw))
    let grid = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and
      getAttribute(r, n, "class") == cardGridClass & " " & cardGridCompactClass)
    require grid != nil
    let cards = findAllByTag(grid, "a")
    check cards.len == 1
    check getAttribute(r, cards[0], "class") == cardClass & " " & cardCompactClass

  test "hero renders an <h1> title, a subtitle, and its action buttons":
    let raw = ":::hero title=\"Welcome\" subtitle=\"Sub\"\n" &
      ":::button href=\"a.md\" variant=\"primary\"\nGet Started\n" &
      ":::button href=\"b.md\" variant=\"secondary\"\nSupport\n:::"
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, parseMarkdownBlocks(raw))

    let hero = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class") == heroClass)
    require hero != nil
    let h1 = findByTag(hero, "h1")
    require h1 != nil
    check textContent(h1) == "Welcome"

    let buttons = findAllByTag(hero, "a")
    check buttons.len == 2
    check getAttribute(r, buttons[0], "class") == buttonClass
    check getAttribute(r, buttons[0], "href") == "a.md"
    check textContent(buttons[0]) == "Get Started"
    check getAttribute(r, buttons[1], "class") == buttonClass & " " & buttonSecondaryClass

  test "standalone button renders a single <a> action link":
    let raw = ":::button href=\"a.md\" variant=\"secondary\"\nSupport\n:::"
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, parseMarkdownBlocks(raw))
    let a = findByTag(root, "a")
    require a != nil
    check getAttribute(r, a, "class") == buttonClass & " " & buttonSecondaryClass
    check getAttribute(r, a, "href") == "a.md"
    check textContent(a) == "Support"

  test "faq renders each item as a native <details>/<summary> disclosure":
    let raw = ":::faq\n:::q title=\"Q one?\"\nAnswer one.\n:::q title=\"Q two?\"\nAnswer two.\n:::"
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, parseMarkdownBlocks(raw))

    let faq = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class") == faqClass)
    require faq != nil

    let details = findAllByTag(faq, "details")
    check details.len == 2
    let summaries = findAllByTag(faq, "summary")
    check summaries.len == 2
    check textContent(summaries[0]) == "Q one?"
    check textContent(details[0]).contains("Answer one.")
    check textContent(summaries[1]) == "Q two?"

# --- SSR string (Tier 2, dual-target) -----------------------------------

suite "docs content components -- SSR string rendering (Tier 2, dual-target)":
  test "card grid serializes <a> cards with icon, title, and description":
    let raw = ":::cards\n:::card title=\"Start\" icon=\"/img/s.svg\" href=\"start.md\"\nFirst steps.\n:::"
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(raw))
    check html.contains("class=\"" & cardGridClass & "\"")
    check html.contains("<a class=\"" & cardClass & "\" href=\"start.md\">")
    check html.contains("<img src=\"/img/s.svg\" alt=\"\" />")
    check html.contains(">Start</div>")
    check html.contains("First steps.")

  test "M6: a compact card grid serializes the --compact modifier; a default grid does not":
    let compactHtml = renderMarkdownBodyHtml(parseMarkdownBlocks(
      ":::cards variant=\"compact\"\n:::card title=\"Introduction\" href=\"a.md\"\nGetting Started\n:::"))
    check compactHtml.contains("<div class=\"" & cardGridClass & " " & cardGridCompactClass & "\">")
    check compactHtml.contains("<a class=\"" & cardClass & " " & cardCompactClass & "\" href=\"a.md\">")
    # Backward-compat: a plain `:::cards` grid still emits exactly the pre-M6
    # classes -- no `--compact` modifier leaks onto a default grid.
    let defaultHtml = renderMarkdownBodyHtml(parseMarkdownBlocks(
      ":::cards\n:::card title=\"Introduction\" href=\"a.md\"\nGetting Started\n:::"))
    check defaultHtml.contains("<div class=\"" & cardGridClass & "\">")
    check defaultHtml.contains("<a class=\"" & cardClass & "\" href=\"a.md\">")
    check not defaultHtml.contains(cardGridCompactClass)
    check not defaultHtml.contains(cardCompactClass)

  test "hero serializes an <h1>, a subtitle, and primary/secondary buttons":
    let raw = ":::hero title=\"Welcome\" subtitle=\"Sub\"\n" &
      ":::button href=\"a.md\" variant=\"primary\"\nGet Started\n" &
      ":::button href=\"b.md\" variant=\"secondary\"\nSupport\n:::"
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(raw))
    check html.contains("<section class=\"" & heroClass & "\">")
    check html.contains("<h1 class=\"" & heroTitleClass & "\">Welcome</h1>")
    check html.contains("<p class=\"" & heroSubtitleClass & "\">Sub</p>")
    check html.contains("<a class=\"" & buttonClass & "\" href=\"a.md\">Get Started</a>")
    check html.contains("<a class=\"" & buttonClass & " " & buttonSecondaryClass &
      "\" href=\"b.md\">Support</a>")

  test "faq serializes native <details>/<summary> items (JS-free accordion)":
    let raw = ":::faq\n:::q title=\"Q one?\"\nAnswer one.\n:::"
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(raw))
    check html.contains("<div class=\"" & faqClass & "\">")
    check html.contains("<details class=\"" & faqItemClass & "\">")
    check html.contains("<summary class=\"" & faqQuestionClass & "\">Q one?</summary>")
    check html.contains("Answer one.")

  test "card title, hero title and faq question are HTML-escaped":
    let cardsHtml = renderMarkdownBodyHtml(parseMarkdownBlocks(
      ":::cards\n:::card title=\"A & B\" href=\"x.md\"\nUse `<x>` & `y`.\n:::"))
    check cardsHtml.contains("A &amp; B")
    let faqHtml = renderMarkdownBodyHtml(parseMarkdownBlocks(
      ":::faq\n:::q title=\"A < B?\"\nBecause 1 < 2.\n:::"))
    check faqHtml.contains("A &lt; B?")

# --- Dual-target parity: MockRenderer <-> SSR ---------------------------

suite "docs content components -- MockRenderer <-> SSR parity":
  test "both targets agree on card count, hero button count, and faq item count":
    let raw = ":::cards\n" &
      ":::card title=\"A\" icon=\"/i.svg\" href=\"a.md\"\nDesc A.\n" &
      ":::card title=\"B\" icon=\"/j.svg\" href=\"b.md\"\nDesc B.\n:::\n\n" &
      ":::hero title=\"H\"\n:::button href=\"g.md\"\nGo\n:::button href=\"s.md\" variant=\"secondary\"\nSupport\n:::\n\n" &
      ":::faq\n:::q title=\"Q1\"\nA1.\n:::q title=\"Q2\"\nA2.\n:::q title=\"Q3\"\nA3.\n:::"
    let blocks = parseMarkdownBlocks(raw)

    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)
    let html = renderMarkdownBodyHtml(blocks)

    # Card grid: 2 cards on both targets.
    let grid = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class") == cardGridClass)
    require grid != nil
    check findAllByTag(grid, "a").len == 2
    check html.count("class=\"" & cardClass & "\"") == 2

    # Hero: 2 action buttons on both targets.
    let hero = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class") == heroClass)
    require hero != nil
    check findAllByTag(hero, "a").len == 2

    # FAQ: 3 <details> on both targets.
    let faq = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class") == faqClass)
    require faq != nil
    check findAllByTag(faq, "details").len == 3
    check html.count("<details ") == 3
