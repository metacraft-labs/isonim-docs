## Tier 1 (ViewModel / pure-helper) M2 content-loader suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free half of the M2 content loader
## (`src/core/content.nim`): front matter parsing, slug derivation
## (explicit override and path-derived), section derivation, route-path
## binding, and draft flag parsing. All of this is exercised through
## `parseContentEntry`/`splitFrontMatter`/`parseFrontMatter`, which never
## touch the filesystem, so the exact same assertions hold on both
## targets -- the real-filesystem directory walk
## (`loadContentEntries`) is C-target-only and covered separately by
## `test_content_loader.nim`.
##
## M2 deliverable 2 (markdown-to-docs ViewModel translation) extends this
## suite below with the rest of `test_markdown_vm.nim`'s scope per
## `plan.milestones.org`'s M2 Verification table: block-level parsing
## (headings, paragraphs, lists, code fences, admonitions, tables, inline
## code), heading-tree extraction, and relative-link/asset-reference
## normalization. All of it goes through `src/core/markdown_vm.nim`'s
## pure, filesystem-free `parseMarkdownBlocks`/`parseMarkdownDoc`/
## `normalizeRelativeLink`, so it's exercisable identically on both
## targets. Anchor-ID stability itself (`src/core/anchors.nim`) has its
## own dedicated suite, `test_markdown_anchor_ids.nim`.

import std/unittest
import ../../src/core/content
import ../../src/core/markdown_vm

suite "docs content loader -- pure front matter / slug / route binding (Tier 1, dual-target)":
  test "splitFrontMatter extracts a leading '---' block and reports the body's start line":
    let (frontRaw, bodyRaw, bodyLine) = splitFrontMatter(
      "---\ntitle: Getting Started\nsection: guide\n---\n# Getting Started\n\nBody.")
    check frontRaw == "title: Getting Started\nsection: guide"
    check bodyRaw == "# Getting Started\n\nBody."
    check bodyLine == 5

  test "splitFrontMatter returns an empty front matter and line 1 when there's no leading '---'":
    let (frontRaw, bodyRaw, bodyLine) = splitFrontMatter("# Plain Page\n\nNo front matter here.")
    check frontRaw == ""
    check bodyRaw == "# Plain Page\n\nNo front matter here."
    check bodyLine == 1

  test "splitFrontMatter treats an unterminated '---' block as no front matter at all":
    let (frontRaw, bodyRaw, bodyLine) = splitFrontMatter("---\ntitle: Oops\n\n# Body without a closing marker")
    check frontRaw == ""
    check bodyRaw == "---\ntitle: Oops\n\n# Body without a closing marker"
    check bodyLine == 1

  test "parseFrontMatter parses known keys and ignores unknown ones":
    let front = parseFrontMatter(
      "title: Getting Started\ndescription: A quick tour\nsection: guide\norder: 2\nslug: gs\ndraft: true\nfuture_key: whatever")
    check front.title == "Getting Started"
    check front.description == "A quick tour"
    check front.section == "guide"
    check front.order == 2
    check front.slug == "gs"
    check front.draft == true

  test "parseFrontMatter defaults order to 0 and draft to false when absent":
    let front = parseFrontMatter("title: Only Title")
    check front.order == 0
    check front.draft == false

  test "parseFrontMatter tolerates a malformed order/draft value by falling back to the zero value":
    let front = parseFrontMatter("order: not-a-number\ndraft: not-a-bool")
    check front.order == 0
    check front.draft == false

  test "deriveSlug uses the file basename with its .md extension stripped by default":
    check deriveSlug("guide/getting-started.md", ContentFrontMatter()) == "getting-started"
    check deriveSlug("index.md", ContentFrontMatter()) == "index"

  test "deriveSlug prefers an explicit front matter slug override":
    check deriveSlug("guide/getting-started.md", ContentFrontMatter(slug: "gs")) == "gs"

  test "deriveSection derives from the parent directory when no front matter section is set":
    check deriveSection("guide/getting-started.md", ContentFrontMatter()) == "guide"
    check deriveSection("index.md", ContentFrontMatter()) == ""

  test "deriveSection prefers an explicit front matter section override":
    check deriveSection("misc/foo.md", ContentFrontMatter(section: "guide")) == "guide"

  test "deriveRoutePath binds the root index to '/'":
    check deriveRoutePath("", "index") == "/"

  test "deriveRoutePath binds a sectioned index page to its section root":
    check deriveRoutePath("guide", "index") == "/guide"

  test "deriveRoutePath binds a sectioned page to '/section/slug'":
    check deriveRoutePath("guide", "getting-started") == "/guide/getting-started"

  test "deriveRoutePath binds a section-less page to '/slug'":
    check deriveRoutePath("", "about") == "/about"

  test "parseContentEntry combines front matter, body, slug, section, and route binding for a nested page":
    let entry = parseContentEntry(
      "---\ntitle: Getting Started\nsection: guide\norder: 1\n---\n# Ignored Body Heading\n\nStart here.",
      "guide/getting-started.md")
    check entry.front.title == "Getting Started"
    check entry.front.section == "guide"
    check entry.front.order == 1
    check entry.page.title == "Getting Started"
    check entry.page.body == "Start here."
    check entry.slug == "getting-started"
    check entry.section == "guide"
    check entry.routePath == "/guide/getting-started"
    check entry.source.path == "guide/getting-started.md"
    check entry.source.line == 6

  test "parseContentEntry falls back to the body's own leading heading when front matter has no title":
    let entry = parseContentEntry("# From The Body\n\nText.", "index.md")
    check entry.page.title == "From The Body"
    check entry.routePath == "/"

  test "parseContentEntry works with no front matter at all, matching M0/M1 content files unchanged":
    let entry = parseContentEntry("# Welcome\n\nHello.", "index.md")
    check entry.front.title == ""
    check entry.front.draft == false
    check entry.page.title == "Welcome"
    check entry.slug == "index"
    check entry.routePath == "/"
    check entry.source.line == 1

  test "parseContentEntry surfaces the draft flag for callers to filter on":
    let entry = parseContentEntry("---\ndraft: true\n---\n# Unfinished\n\nWIP.", "guide/wip.md")
    check entry.front.draft == true

suite "docs markdown-to-ViewModel translation -- pure block/inline parsing (Tier 1, dual-target)":
  test "parseMarkdownBlocks translates a heading (with its stable anchor ID) and a paragraph with inline code":
    let blocks = parseMarkdownBlocks("# Getting Started\n\nRun `nimble install` first.")
    check blocks.len == 2
    check blocks[0].kind == bkHeading
    check blocks[0].level == 1
    check blocks[0].headingText == "Getting Started"
    check blocks[0].headingId == "getting-started"
    check blocks[1].kind == bkParagraph
    check blocks[1].spans.len == 3
    check blocks[1].spans[0] == InlineSpan(kind: ikText, text: "Run ")
    check blocks[1].spans[1] == InlineSpan(kind: ikCode, text: "nimble install")
    check blocks[1].spans[2] == InlineSpan(kind: ikText, text: " first.")

  test "parseMarkdownBlocks recognizes heading levels 1 through 6":
    let blocks = parseMarkdownBlocks("# One\n\n## Two\n\n###### Six")
    check blocks.len == 3
    check blocks[0].level == 1
    check blocks[1].level == 2
    check blocks[2].level == 6

  test "parseMarkdownBlocks joins soft-wrapped paragraph lines with a single space":
    let blocks = parseMarkdownBlocks("This is a paragraph\nthat wraps across\nthree lines.")
    check blocks.len == 1
    check blocks[0].kind == bkParagraph
    check spansText(blocks[0].spans) == "This is a paragraph that wraps across three lines."

  test "parseMarkdownBlocks translates an unordered list and stops at the next block":
    let blocks = parseMarkdownBlocks("- First\n- Second\n- Third\n\n# Next")
    check blocks.len == 2
    check blocks[0].kind == bkList
    check blocks[0].listKind == lkUnordered
    check blocks[0].items.len == 3
    check spansText(blocks[0].items[0]) == "First"
    check spansText(blocks[0].items[2]) == "Third"
    check blocks[1].kind == bkHeading

  test "parseMarkdownBlocks translates an ordered list distinctly from an unordered one":
    let blocks = parseMarkdownBlocks("1. Step one\n2. Step two")
    check blocks.len == 1
    check blocks[0].kind == bkList
    check blocks[0].listKind == lkOrdered
    check blocks[0].items.len == 2
    check spansText(blocks[0].items[1]) == "Step two"

  test "parseMarkdownBlocks translates a fenced code block, preserving its language and body verbatim":
    let blocks = parseMarkdownBlocks("```nim\nlet x = 1\necho x\n```")
    check blocks.len == 1
    check blocks[0].kind == bkCodeFence
    check blocks[0].lang == "nim"
    check blocks[0].code == "let x = 1\necho x"

  test "parseMarkdownBlocks translates a fenced code block with no language tag":
    let blocks = parseMarkdownBlocks("```\nplain text\n```")
    check blocks.len == 1
    check blocks[0].lang == ""
    check blocks[0].code == "plain text"

  test "parseMarkdownBlocks translates a ':::kind' admonition fence, defaulting an unrecognized kind to Note":
    let blocks = parseMarkdownBlocks(":::warning\nBack up first.\nThen proceed.\n:::")
    check blocks.len == 1
    check blocks[0].kind == bkAdmonition
    check blocks[0].admonitionKind == akWarning
    check blocks[0].bodyParagraphs.len == 1
    check spansText(blocks[0].bodyParagraphs[0]) == "Back up first. Then proceed."

    let unrecognized = parseMarkdownBlocks(":::mystery\nJust an FYI.\n:::")
    check unrecognized[0].admonitionKind == akNote

  test "parseMarkdownBlocks recognizes every admonition kind":
    check parseMarkdownBlocks(":::note\nx\n:::")[0].admonitionKind == akNote
    check parseMarkdownBlocks(":::tip\nx\n:::")[0].admonitionKind == akTip
    check parseMarkdownBlocks(":::warning\nx\n:::")[0].admonitionKind == akWarning
    check parseMarkdownBlocks(":::danger\nx\n:::")[0].admonitionKind == akDanger

  test "parseMarkdownBlocks translates a pipe table into header cells and body rows":
    let raw = "| Name | Kind |\n| --- | --- |\n| foo | bar |\n| baz | qux |"
    let blocks = parseMarkdownBlocks(raw)
    check blocks.len == 1
    check blocks[0].kind == bkTable
    check blocks[0].headers == @["Name", "Kind"]
    check blocks[0].rows.len == 2
    check blocks[0].rows[0] == @["foo", "bar"]
    check blocks[0].rows[1] == @["baz", "qux"]

  test "parseMarkdownBlocks translates a standalone image line into a single-span paragraph with a normalized asset path":
    let blocks = parseMarkdownBlocks("![Diagram](./diagram.png)", "guide/page.md")
    check blocks.len == 1
    check blocks[0].kind == bkParagraph
    check blocks[0].spans.len == 1
    check blocks[0].spans[0].kind == ikImage
    check blocks[0].spans[0].text == "Diagram"
    check blocks[0].spans[0].href == "/guide/diagram.png"
    check blocks[0].spans[0].isRelative == true

  test "parseMarkdownBlocks parses multiple blocks in document order":
    let raw = "# Title\n\nIntro paragraph.\n\n- one\n- two\n\n```sh\necho hi\n```"
    let blocks = parseMarkdownBlocks(raw)
    check blocks.len == 4
    check blocks[0].kind == bkHeading
    check blocks[1].kind == bkParagraph
    check blocks[2].kind == bkList
    check blocks[3].kind == bkCodeFence

  test "parseMarkdownDoc's heading tree nests headings by level, stopping a section at the next same-or-shallower heading":
    let doc = parseMarkdownDoc(
      "# Guide\n\n## Install\n\nBody.\n\n## Usage\n\n### Basics\n\nBody.\n\n# Reference")
    let tree = doc.headingTree
    check tree.len == 2
    check tree[0].text == "Guide"
    check tree[0].children.len == 2
    check tree[0].children[0].text == "Install"
    check tree[0].children[0].children.len == 0
    check tree[0].children[1].text == "Usage"
    check tree[0].children[1].children.len == 1
    check tree[0].children[1].children[0].text == "Basics"
    check tree[1].text == "Reference"
    check tree[1].children.len == 0

  test "parseMarkdownDoc's heading tree nests a heading that skips a level directly under the shallower one":
    let doc = parseMarkdownDoc("# Guide\n\n### Deep Note")
    let tree = doc.headingTree
    check tree.len == 1
    check tree[0].text == "Guide"
    check tree[0].children.len == 1
    check tree[0].children[0].text == "Deep Note"

  test "parseMarkdownDoc assigns deduped anchor IDs to duplicate headings across the whole document":
    let doc = parseMarkdownDoc("# Guide\n\n## Setup\n\n# Guide\n\n## Setup")
    let tree = doc.headingTree
    check tree.len == 2
    check tree[0].text == "Guide"
    check tree[0].id == "guide"
    check tree[1].text == "Guide"
    check tree[1].id == "guide-2"
    check tree[0].children[0].id == "setup"
    check tree[1].children[0].id == "setup-2"

  test "resolveRelativePath collapses './' and '../' segments against a base directory":
    check resolveRelativePath("guide", "./advanced.md") == "guide/advanced.md"
    check resolveRelativePath("guide", "../index.md") == "index.md"
    check resolveRelativePath("", "getting-started.md") == "getting-started.md"

  test "normalizeRelativeLink resolves a same-directory '.md' link against the current page's own path":
    check normalizeRelativeLink("./advanced.md", "guide/getting-started.md") ==
      ("/guide/advanced", true)

  test "normalizeRelativeLink resolves a parent-directory '.md' link, including back to the root index":
    check normalizeRelativeLink("../index.md", "guide/getting-started.md") == ("/", true)

  test "normalizeRelativeLink resolves a bare (no './') relative '.md' link from a top-level page":
    check normalizeRelativeLink("getting-started.md", "index.md") == ("/getting-started", true)

  test "normalizeRelativeLink resolves a relative non-'.md' reference into a root-relative asset path":
    check normalizeRelativeLink("./diagram.png", "guide/getting-started.md") ==
      ("/guide/diagram.png", true)
    check normalizeRelativeLink("../shared/logo.svg", "guide/getting-started.md") ==
      ("/shared/logo.svg", true)

  test "normalizeRelativeLink passes external/absolute/fragment/mailto targets through unchanged":
    for href in ["https://example.com", "http://example.com/x", "mailto:a@example.com",
                 "//cdn.example.com/x", "/already/rooted", "#section"]:
      check normalizeRelativeLink(href, "guide/getting-started.md") == (href, false)

  test "parseInlineSpans normalizes a relative markdown link's href to a route path in place":
    let spans = parseInlineSpans("See the [advanced guide](./advanced.md) for more.", "guide/page.md")
    check spans.len == 3
    check spans[1] == InlineSpan(kind: ikLink, text: "advanced guide",
      href: "/guide/advanced", isRelative: true)

  test "parseInlineSpans normalizes an inline image reference's src to an asset path":
    let spans = parseInlineSpans("See ![the diagram](./diagram.png) above.", "guide/page.md")
    check spans.len == 3
    check spans[1] == InlineSpan(kind: ikImage, text: "the diagram",
      href: "/guide/diagram.png", isRelative: true)
