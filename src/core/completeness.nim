## isonim-docs Layer 3 — machine-checkable documentation completeness
## matrix + checker.
##
## `CompletenessRequirement` names one topic, the one real, addressable
## route that topic's page must resolve at, and the minimum real-content
## signal (required heading text(s), plus a floor on body word count)
## that page must carry to count as complete for that topic -- a stub
## page bound to the right route still fails.
##
## `requiredCompletenessMatrix()` is the framework's own content-agnostic
## default: an empty matrix, since the framework has no fixed notion of
## what topics a site must document (M1 corrective deliverable 3). A
## real site supplies its own matrix -- `../isonim/docs/users/src/docs_config.isonimCompletenessMatrix()`
## carries the current isonim-docs site's own topic list (the one M4's
## deliverable-2 text originally named: install/setup, reactive core, DSL
## and components, routing/SSR, testing strategy, editor workspace model,
## browser mount contract, consumer integration guides) -- and passes it
## to `checkCompleteness` explicitly; this proc is only ever the fallback
## when no such override is given.
##
## Pure data + a pure checker (`checkCompleteness`), built the same
## dependency-injection way `references.checkPageReferences` and
## `navigation_vm.buildNavPages` are: the caller supplies `matrix`,
## `manifest`, and a `loadEntry` closure, so this whole module is
## Tier-1-testable on both `nim c` and `nim js` against hand-built
## fixtures. The real, real-content-dir check (against
## `docsRouteManifest()`, `content.loadContentEntry`, and
## `../isonim/docs/users/src/docs_config.isonimCompletenessMatrix()`) is
## the consumer package's own `tests/test_completeness.nim`'s job,
## C-target only, exactly like `references.validateContentGraph`.

import std/strutils
import ./content
import ./routes
import ./markdown_vm

type
  CompletenessRequirement* = object
    topic*: string             ## Stable machine key, e.g. "install-setup".
    deliverableText*: string   ## The exact M4 deliverable-2 topic phrase this requirement covers.
    routePath*: string         ## The one real, addressable route this topic's page must resolve at.
    requiredHeadings*: seq[string] ## Heading text(s) (case-insensitive substring match against the page's own heading tree) the page must carry.
    minWordCount*: int         ## Floor on the page body's real word count -- catches a stub page bound to the right route.

proc requiredCompletenessMatrix*(): seq[CompletenessRequirement] =
  ## The framework's own default: no required topics. A real site's
  ## required-topic matrix (e.g. `../isonim/docs/users/src/docs_config.isonimCompletenessMatrix()`)
  ## is a consumer-supplied override, never framework-baked data.
  @[]

proc countWords(text: string): int =
  text.splitWhitespace().len

proc flattenHeadingText(nodes: seq[HeadingNode]; acc: var seq[string]) =
  for node in nodes:
    acc.add node.text.toLowerAscii()
    flattenHeadingText(node.children, acc)

proc hasHeadingContaining(headingTexts: seq[string]; needle: string): bool =
  for text in headingTexts:
    if text.contains(needle):
      return true
  false

proc checkCompleteness*(matrix: seq[CompletenessRequirement]; manifest: RouteManifest;
                         loadEntry: proc(contentPath: string): ContentEntry {.closure.}): seq[string] =
  ## Checks every requirement in `matrix` against `manifest`/`loadEntry`
  ## and returns one actionable issue string per failure ("topic '...'
  ## (...): ..."). An empty result means the proof site is complete
  ## against the matrix. Never raises -- a requirement whose route isn't
  ## even in the manifest, or whose bound content file fails to load, is
  ## reported the same actionable way as a thin page, not a crash.
  for req in matrix:
    var matchedEntry: RouteEntry
    var found = false
    for entry in manifest.entries:
      if entry.status == rsOk and entry.canonicalPath == req.routePath:
        matchedEntry = entry
        found = true
        break
    if not found:
      result.add "topic '" & req.topic & "' (" & req.deliverableText &
        "): no route bound at " & req.routePath
      continue

    var content: ContentEntry
    try:
      content = loadEntry(matchedEntry.meta.contentPath)
    except CatchableError as e:
      result.add "topic '" & req.topic & "' (" & req.deliverableText &
        "): failed to load " & matchedEntry.meta.contentPath & ": " & e.msg
      continue

    let wordCount = countWords(content.page.body)
    if wordCount < req.minWordCount:
      result.add "topic '" & req.topic & "' (" & req.deliverableText & "): " & req.routePath &
        " has only " & $wordCount & " body words (need >= " & $req.minWordCount & ")"

    let doc = parseMarkdownDoc(content.page.body, matchedEntry.meta.contentPath)
    var headingTexts: seq[string] = @[]
    flattenHeadingText(doc.headingTree, headingTexts)
    for needed in req.requiredHeadings:
      if not hasHeadingContaining(headingTexts, needed.toLowerAscii()):
        result.add "topic '" & req.topic & "' (" & req.deliverableText & "): " & req.routePath &
          " is missing required heading '" & needed & "'"
