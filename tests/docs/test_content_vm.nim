## Tier 1 (ViewModel / pure-helper) M2 content-loader suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free half of the M2 content loader
## (`src/core/content.nim`): front matter parsing, slug derivation
## (explicit override and path-derived), section derivation, route-path
## binding, and draft flag parsing. All of this is exercised through
## `parseContentEntry`/`parseFrontMatter`, which never touch the
## filesystem, so the exact same assertions hold on both targets -- the
## real-filesystem directory walk (`loadContentEntries`) is C-target-only
## and covered separately by `test_content_loader.nim`.
##
## The Markdown parser cases that used to follow here moved to IsoNim
## with the parser (`isonim/content/markdown`, its
## `tests/test_content_markdown.nim`), and the `splitFrontMatter` cases
## moved with that function (`isonim/content/frontmatter`).

import std/unittest
import ../../src/core/content

suite "docs content loader -- pure front matter / slug / route binding (Tier 1, dual-target)":
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
