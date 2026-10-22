## The Markdown AST is one type on both import paths -- dual-target:
## `nim c -r` and `nim js -r` must pass.
##
## isonim-email reads its Markdown bodies through `core/markdown_vm`, the
## module that moved to IsoNim as `isonim/content/markdown` and that
## isonim-docs now re-exports. This suite proves that move is invisible to
## such a consumer:
##
## 1. **Same types.** The AST types reached through `core/markdown_vm` and
##    through `isonim/content/markdown` are the same types (checked at
##    compile time), and so is the `Block` an email-shaped consumer
##    compiled against each path sees.
## 2. **Same results.** `compat/email_shaped_consumer.nim` -- a consumer
##    written the way isonim-email's `mailMarkdown` consumes the AST, with
##    exhaustive `case`s over `BlockKind`, `AdmonitionKind` and
##    `InlineKind` -- is compiled once against each path
##    (`compat/via_reexport.nim`, `compat/via_content.nim`). Both parse
##    every fixture to the same outline.
## 3. **Reviewed results.** That outline equals the one recorded in
##    `fixtures/email-markdown/<name>.outline`, which was produced by the
##    same consumer compiled against isonim-docs' own parser at `465a170`,
##    before the move. So the shared parser reads these bodies exactly as
##    the parser isonim-email pinned did, except the explicit prose changes
##    below.
##
## The fixtures (`fixtures/email-markdown/*.md`) are isonim-email's
## Markdown-body story set (`tests/stories/seed_markdown.nim` in that
## repository: Minimal, Maximal, Rtl, ImagesOff, Dark, InContext,
## ListsTables), copied as files. Two values there are computed at run
## time and are literals here: the long unbreakable word, and the image
## path. They are excluded from the rewriting pre-commit hooks so their
## bytes stay what is tested.
##
## Prose expectations update only maximal (strike, autolink, separate title,
## quote), rtl (quote) and dark (quote). The other four recorded outlines are
## byte-identical to the extraction baseline. These are AST expectations;
## site-build HTML goldens are not regenerated.
##
## No test doubles: both paths are the real modules.

import std/[unittest, strutils]
import ../src/core/markdown_vm as reexportPath
import isonim/content/markdown as contentPath
import ./compat/via_reexport as viaReexport
import ./compat/via_content as viaContent

const fixtureNames = ["minimal", "maximal", "rtl", "images-off", "dark",
                      "in-context", "lists-tables"]

proc fixtures(): seq[tuple[name, src, expected: string]] =
  ## Embedded at compile time, so the suite needs no filesystem and runs
  ## on the JS target too.
  const dir = "fixtures/email-markdown/"
  const embedded = block:
    var all: seq[tuple[name, src, expected: string]]
    for name in fixtureNames:
      all.add((name, staticRead(dir & name & ".md"),
               staticRead(dir & name & ".outline")))
    all
  @embedded

# 1. Same types, checked when this file compiles.
static:
  doAssert reexportPath.Block is contentPath.Block
  doAssert reexportPath.InlineSpan is contentPath.InlineSpan
  doAssert reexportPath.BlockKind is contentPath.BlockKind
  doAssert reexportPath.InlineKind is contentPath.InlineKind
  doAssert reexportPath.AdmonitionKind is contentPath.AdmonitionKind
  doAssert reexportPath.MarkdownDoc is contentPath.MarkdownDoc
  doAssert viaReexport.ConsumerBlock is viaContent.ConsumerBlock
  doAssert viaReexport.ConsumerBlock is contentPath.Block
  doAssert viaReexport.ConsumerInlineSpan is viaContent.ConsumerInlineSpan
  # The checks above are not vacuous: an unrelated type is told apart.
  doAssert not (contentPath.Block is contentPath.InlineSpan)

suite "Markdown AST compatibility (re-export path vs isonim/content)":
  test "the fixture set is the whole isonim-email story set and none is empty":
    let fx = fixtures()
    check fx.len == 7
    for f in fx:
      check f.src.strip().len > 0
      check f.expected.strip().len > 0

  test "a value built through one path is accepted by the other path's procs":
    let blocks: seq[contentPath.Block] = reexportPath.parseMarkdownBlocks("# A\n\ntext")
    check reexportPath.spansText(blocks[1].spans) == "text"
    let doc: reexportPath.MarkdownDoc = contentPath.parseMarkdownDoc("# A\n\n## B")
    check doc.headingTree[0].children[0].id == "b"

  for f in fixtures():
    test "fixture " & f.name & ": both paths parse to the reviewed outline":
      let viaOld = viaReexport.outline(f.src)
      let viaNew = viaContent.outline(f.src)
      check viaOld == viaNew
      check viaNew == f.expected
