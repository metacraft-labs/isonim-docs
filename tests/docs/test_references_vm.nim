## Tier 1 (ViewModel / pure-helper) M3 references suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free half of `src/core/references.nim`
## (M3 deliverable 2): anchor-set flattening, page-vs-asset href
## classification, same-page and cross-page reference checking (unknown
## route, unknown anchor, redirect/alias mapping), and duplicate-route
## detection. All of it is exercised through in-memory `MarkdownDoc`/
## `ContentEntry` values built via `markdown_vm.parseMarkdownDoc`/
## `content.parseContentEntry` -- no filesystem access anywhere -- so the
## exact same assertions hold on both targets. The real, whole-content-
## graph build check (`checkContentGraph`/`validateContentGraph`) is
## C-target-only and covered separately by `test_references_renderroute.nim`.

import std/[unittest, tables, sets, strutils]
import ../../src/core/content
import ../../src/core/markdown_vm
import ../../src/core/references

suite "docs references -- collectAnchors / isPageHref (Tier 1, dual-target)":
  test "collectAnchors flattens a nested heading tree into a flat anchor-ID set":
    # `parseMarkdownDoc` parses already-body-only text (the M0/M1 leading
    # "# Title" stripping is `content.parseDocsPage`'s job, upstream of
    # this), so the leading "# Guide" here is itself a body-level H1
    # heading with its own anchor, exactly like any other heading.
    let doc = parseMarkdownDoc("# Guide\n\n## Install\n\n### Basics\n\nBody.\n\n## Usage\n\nBody.")
    let anchors = collectAnchors(doc.headingTree)
    check anchors == ["guide", "install", "basics", "usage"].toHashSet()

  test "collectAnchors returns an empty set for a page with no headings":
    let doc = parseMarkdownDoc("Just a paragraph, no headings at all.")
    check collectAnchors(doc.headingTree).len == 0

suite "docs references -- checkPageReferences (Tier 1, dual-target)":
  test "a same-page fragment link to an existing anchor is not flagged":
    let doc = parseMarkdownDoc("# Guide\n\n## Setup\n\nSee [setup](#setup) above.")
    let source = ContentSource(path: "guide/dsl.md", line: 3)
    let anchorsByRoute = {"/guide/dsl": collectAnchors(doc.headingTree)}.toTable
    let issues = checkPageReferences(doc, source, "/guide/dsl", initHashSet[string](), anchorsByRoute)
    check issues.len == 0

  test "a same-page fragment link to a missing anchor is flagged with the page's own source provenance":
    let doc = parseMarkdownDoc("# Guide\n\n## Setup\n\nSee [teardown](#teardown) above.")
    let source = ContentSource(path: "guide/dsl.md", line: 3)
    let anchorsByRoute = {"/guide/dsl": collectAnchors(doc.headingTree)}.toTable
    let issues = checkPageReferences(doc, source, "/guide/dsl", initHashSet[string](), anchorsByRoute)
    check issues.len == 1
    check issues[0].kind == riUnknownAnchor
    check issues[0].sourcePath == "guide/dsl.md"
    check issues[0].sourceLine == 3
    check issues[0].targetHref == "#teardown"

  test "a cross-page link to a known route is not flagged":
    # A relative "./dsl.md" target, exactly what an author writes -- a
    # pre-absolute path like "/guide/dsl" written directly in markdown is
    # `isExternalOrAbsoluteLink`'s job to treat as out-of-graph-scope
    # (see `markdown_vm.normalizeRelativeLink`'s docstring), so it's
    # deliberately never exercised here.
    let doc = parseMarkdownDoc("See [the DSL guide](./dsl.md) for more.", "guide/other.md")
    let source = ContentSource(path: "guide/other.md", line: 1)
    let knownRoutes = ["/guide/dsl", "/guide/other"].toHashSet()
    let issues = checkPageReferences(doc, source, "/guide/other", knownRoutes, initTable[string, HashSet[string]]())
    check issues.len == 0

  test "a cross-page link to an unknown route is flagged as riUnknownRoute":
    let doc = parseMarkdownDoc("See [the missing page](./missing.md) for more.", "guide/other.md")
    let source = ContentSource(path: "guide/other.md", line: 1)
    let knownRoutes = ["/guide/dsl", "/guide/other"].toHashSet()
    let issues = checkPageReferences(doc, source, "/guide/other", knownRoutes, initTable[string, HashSet[string]]())
    check issues.len == 1
    check issues[0].kind == riUnknownRoute
    check issues[0].targetHref == "/guide/missing"

  test "a cross-page link with a fragment resolves the fragment against the destination page's own anchors":
    let dslDoc = parseMarkdownDoc("# The DSL\n\n## Elements\n\nBody.")
    let doc = parseMarkdownDoc("See [elements](./dsl.md#elements) for more.", "guide/other.md")
    let source = ContentSource(path: "guide/other.md", line: 1)
    let knownRoutes = ["/guide/dsl", "/guide/other"].toHashSet()
    let anchorsByRoute = {"/guide/dsl": collectAnchors(dslDoc.headingTree)}.toTable
    let issues = checkPageReferences(doc, source, "/guide/other", knownRoutes, anchorsByRoute)
    check issues.len == 0

  test "a cross-page link with an unknown fragment on a known destination page is flagged as riUnknownAnchor":
    let dslDoc = parseMarkdownDoc("# The DSL\n\n## Elements\n\nBody.")
    let doc = parseMarkdownDoc("See [signals](./dsl.md#signals) for more.", "guide/other.md")
    let source = ContentSource(path: "guide/other.md", line: 1)
    let knownRoutes = ["/guide/dsl", "/guide/other"].toHashSet()
    let anchorsByRoute = {"/guide/dsl": collectAnchors(dslDoc.headingTree)}.toTable
    let issues = checkPageReferences(doc, source, "/guide/other", knownRoutes, anchorsByRoute)
    check issues.len == 1
    check issues[0].kind == riUnknownAnchor
    check issues[0].targetHref == "/guide/dsl#signals"

  test "an asset reference (a relative target with a file extension) is never flagged":
    let doc = parseMarkdownDoc("![a diagram](./diagram.png)", "guide/other.md")
    let source = ContentSource(path: "guide/other.md", line: 1)
    let issues = checkPageReferences(doc, source, "/guide/other", initHashSet[string](), initTable[string, HashSet[string]]())
    check issues.len == 0

  test "an external absolute link is never flagged":
    let doc = parseMarkdownDoc("See [the Nim manual](https://nim-lang.org/docs/manual.html).", "guide/other.md")
    let source = ContentSource(path: "guide/other.md", line: 1)
    let issues = checkPageReferences(doc, source, "/guide/other", initHashSet[string](), initTable[string, HashSet[string]]())
    check issues.len == 0

  test "a link to a redirect/alias source that maps to a known route is not flagged (redirect mapping)":
    let doc = parseMarkdownDoc("See [the old guide](./old-dsl.md) for more.", "guide/other.md")
    let source = ContentSource(path: "guide/other.md", line: 1)
    let knownRoutes = ["/guide/dsl", "/guide/other"].toHashSet()
    let aliases = {"/guide/old-dsl": "/guide/dsl"}.toTable
    let issues = checkPageReferences(doc, source, "/guide/other", knownRoutes,
      initTable[string, HashSet[string]](), aliases)
    check issues.len == 0

  test "a link to an alias whose own destination is itself unknown is still flagged":
    let doc = parseMarkdownDoc("See [the old guide](./old-dsl.md) for more.", "guide/other.md")
    let source = ContentSource(path: "guide/other.md", line: 1)
    let knownRoutes = ["/guide/other"].toHashSet()
    let aliases = {"/guide/old-dsl": "/guide/dsl"}.toTable
    let issues = checkPageReferences(doc, source, "/guide/other", knownRoutes,
      initTable[string, HashSet[string]](), aliases)
    check issues.len == 1
    check issues[0].kind == riUnknownRoute

suite "docs references -- findDuplicateRoutePaths (Tier 1, dual-target)":
  test "two content entries deriving the same route path are both flagged as riDuplicateRoute":
    let entries = @[
      parseContentEntry("# Guide\n\nBody.", "guide.md"),
      parseContentEntry("# Guide Home\n\nBody.", "guide/index.md"),
    ]
    check entries[0].routePath == "/guide"
    check entries[1].routePath == "/guide"
    let issues = findDuplicateRoutePaths(entries)
    check issues.len == 1
    check issues[0].kind == riDuplicateRoute
    check issues[0].sourcePath == "guide/index.md"

  test "entries with distinct route paths are never flagged":
    let entries = @[
      parseContentEntry("# Guide\n\nBody.", "guide.md"),
      parseContentEntry("# Editor\n\nBody.", "editor.md"),
    ]
    check findDuplicateRoutePaths(entries).len == 0

suite "docs references -- formatReferenceIssue (Tier 1, dual-target)":
  test "formats an actionable file:line message citing the broken target and reason":
    let issue = ReferenceIssue(kind: riUnknownRoute, sourcePath: "guide/dsl.md",
                                sourceLine: 12, targetHref: "/guide/missing")
    let msg = formatReferenceIssue(issue)
    check msg.contains("guide/dsl.md:12")
    check msg.contains("/guide/missing")
