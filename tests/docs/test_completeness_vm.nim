## Tier 1 (ViewModel/pure-helper) M4 deliverable 2 suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## Proves `completeness.checkCompleteness` itself is machine-checkable
## against hand-built, in-memory fixtures (no filesystem access, exactly
## like `references.checkPageReferences`'s own Tier-1 suite): a topic
## missing its route, a topic whose page is too thin, and a topic whose
## page is missing a required heading each produce their own actionable
## issue string, and a fixture graph that satisfies every requirement
## produces none. Also proves `completeness.requiredCompletenessMatrix()`
## (the framework's own default) is empty and content-agnostic (M1
## corrective deliverable 3) -- a real site's own topic list (e.g.
## `../isonim/docs/users/src/docs_config.isonimCompletenessMatrix()`,
## M1 corrective deliverable 4) is a consumer-supplied override, entirely
## outside the framework.

import std/[unittest, tables, strutils]
import ../../src/core/content
import ../../src/core/routes
import ../../src/core/completeness

proc oneRequirement(routePath: string; requiredHeadings: seq[string] = @[];
                     minWordCount: int = 0): CompletenessRequirement =
  CompletenessRequirement(topic: "topic", deliverableText: "a topic",
                           routePath: routePath, requiredHeadings: requiredHeadings,
                           minWordCount: minWordCount)

suite "completeness -- checkCompleteness flags each failure kind with an actionable issue (Tier 1, dual-target)":
  test "a requirement whose route isn't bound in the manifest is flagged":
    let manifest = newRouteManifest(@[])
    let issues = checkCompleteness(@[oneRequirement("/guide/missing")], manifest,
      proc(contentPath: string): ContentEntry = ContentEntry())
    check issues.len == 1
    check issues[0].contains("no route bound at /guide/missing")

  test "a requirement whose bound page is too thin is flagged with its actual word count":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/thin", pkMarkdown, meta = RouteMeta(contentPath: "thin.md"))])
    let entries = {"thin.md": parseContentEntry("# Thin\n\nOnly a few words here.", "thin.md")}.toTable
    let issues = checkCompleteness(@[oneRequirement("/guide/thin", minWordCount = 50)], manifest,
      proc(contentPath: string): ContentEntry = entries[contentPath])
    check issues.len == 1
    check issues[0].contains("has only")
    check issues[0].contains("need >= 50")

  test "a requirement whose bound page is missing a required heading is flagged by name":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/topic", pkMarkdown, meta = RouteMeta(contentPath: "topic.md"))])
    let entries = {"topic.md": parseContentEntry(
      "# Topic\n\n## Something Else\n\nBody text with enough words to clear any word floor easily today.",
      "topic.md")}.toTable
    let issues = checkCompleteness(
      @[oneRequirement("/guide/topic", requiredHeadings = @["Prerequisites"])],
      manifest, proc(contentPath: string): ContentEntry = entries[contentPath])
    check issues.len == 1
    check issues[0].contains("missing required heading 'Prerequisites'")

  test "required heading match is case-insensitive and substring-based":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/topic", pkMarkdown, meta = RouteMeta(contentPath: "topic.md"))])
    let entries = {"topic.md": parseContentEntry(
      "# Topic\n\n## Sibling dev shell workflow\n\nBody text with enough words to clear any word floor easily today.",
      "topic.md")}.toTable
    let issues = checkCompleteness(
      @[oneRequirement("/guide/topic", requiredHeadings = @["sibling DEV shell"])],
      manifest, proc(contentPath: string): ContentEntry = entries[contentPath])
    check issues.len == 0

  test "a fixture graph satisfying every requirement in a multi-topic matrix produces no issues":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/a", pkMarkdown, meta = RouteMeta(contentPath: "a.md")),
      newRouteEntry("/guide/b", pkMarkdown, meta = RouteMeta(contentPath: "b.md")),
    ])
    let entries = {
      "a.md": parseContentEntry(
        "# A\n\n## Heading One\n\nBody text with enough words to clear any word floor easily today, really.",
        "a.md"),
      "b.md": parseContentEntry(
        "# B\n\n## Heading Two\n\nBody text with enough words to clear any word floor easily today, really.",
        "b.md"),
    }.toTable
    let matrix = @[
      oneRequirement("/guide/a", requiredHeadings = @["Heading One"], minWordCount = 5),
      oneRequirement("/guide/b", requiredHeadings = @["Heading Two"], minWordCount = 5),
    ]
    let issues = checkCompleteness(matrix, manifest,
      proc(contentPath: string): ContentEntry = entries[contentPath])
    check issues.len == 0

suite "completeness -- requiredCompletenessMatrix is the framework's content-agnostic default (Tier 1, dual-target)":
  test "the framework default matrix is empty -- a real site's topic list is a consumer-supplied override":
    check requiredCompletenessMatrix().len == 0
