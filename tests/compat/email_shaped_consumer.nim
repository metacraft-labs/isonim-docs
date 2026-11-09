## An HTML-email-shaped consumer of the Markdown AST, written to be
## `include`d by a module that has imported the AST from ONE of its two
## import paths (`via_reexport.nim`: isonim-docs' `core/markdown_vm`;
## `via_content.nim`: IsoNim's `isonim/content/markdown`). Every name below
## is resolved through whichever import the including module made, so the
## same source compiles once against each path.
##
## It consumes the AST the way isonim-email's `mailMarkdown` does (its
## `content/markdown.nim`, which imports `core/markdown_vm`): it calls
## `parseMarkdownBlocks`, maps every block with an exhaustive `case` over
## `BlockKind` (no `else`, so a kind added, removed or renamed on either
## path is a compile error, as it would be there), maps admonitions with an
## exhaustive `case` over `AdmonitionKind`, re-reads heading text and table
## cells with `parseInlineSpans` and `spansText`, and reads every
## `InlineKind`. Instead of building email nodes it writes a compact
## outline, so two parse results compare as strings.

type ConsumerBlock* = Block
  ## The `Block` type this consumer was compiled against, exported so the
  ## test can assert that both paths name one type.
type ConsumerInlineSpan* = InlineSpan

proc outlineSpans(spans: seq[InlineSpan]): string =
  for s in spans:
    case s.kind
    of ikText: result.add "t(" & s.text & ")"
    of ikCode: result.add "c(" & s.text & ")"
    of ikLink: result.add "a(" & s.text & "|" & s.href & "|" & $s.isRelative &
      (if s.title.len > 0: "|title=" & s.title else: "") & ")"
    of ikImage: result.add "img(" & s.text & "|" & s.href & "|" & $s.isRelative & ")"
    of ikStrike: result.add "strike(" & outlineSpans(s.children) & ")"
    of ikFootnoteRef: result.add "note(" & s.text & ")"
    of ikSymRef: result.add "sym(" & s.text & "|" & s.href & ")"

proc admonitionTone(k: AdmonitionKind): string =
  ## The callout tone `mailMarkdown` gives each admonition kind.
  case k
  of akNote: "info"
  of akTip: "success"
  of akImportant: "primary"
  of akWarning: "warning"
  of akCaution: "danger"
  of akDanger: "danger"

proc outlineBlock(b: Block; indent: string): string =
  case b.kind
  of bkHeading:
    result = indent & "h" & $b.level & "#" & b.headingId & " " &
      outlineSpans(parseInlineSpans(b.headingText)) & "\n"
  of bkParagraph:
    result = indent & "p " & outlineSpans(b.spans) & "\n"
  of bkList:
    result = indent & (if b.listKind == lkOrdered: "ol" else: "ul") & "\n"
    for item in b.items:
      result.add indent & "  li " & outlineSpans(item) & "\n"
  of bkCodeFence:
    result = indent & "code[" & b.lang & "] " & b.code.escape & "\n"
  of bkTable:
    var labels: seq[string]
    for h in b.headers:
      labels.add spansText(parseInlineSpans(h))
    result = indent & "table " & labels.join("|") & "\n"
    for row in b.rows:
      var cells: seq[string]
      for cell in row:
        cells.add outlineSpans(parseInlineSpans(cell))
      result.add indent & "  tr " & cells.join(" | ") & "\n"
  of bkAdmonition:
    result = indent & "callout(" & admonitionTone(b.admonitionKind) & ")\n"
    for para in b.bodyParagraphs:
      result.add indent & "  p " & outlineSpans(para) & "\n"
  of bkButton:
    result = indent & "button(" & b.button.variant & "|" & b.button.href &
      ") " & b.button.label & "\n"
  of bkTabs:
    result = indent & "refused tabs\n"
    for tab in b.tabs:
      result.add indent & "  tab " & tab.title & "\n"
      for inner in tab.blocks:
        result.add outlineBlock(inner, indent & "    ")
  of bkCardGrid: result = indent & "refused cards " & $b.cards.len & "\n"
  of bkHero: result = indent & "refused hero " & b.heroTitle & "\n"
  of bkFaq: result = indent & "refused faq " & $b.faqItems.len & "\n"
  of bkVideo: result = indent & "refused video " & b.videoId & "\n"
  of bkForm: result = indent & "refused form " & $b.formFields.len & "\n"
  of bkBlockquote:
    result = indent & "quote\n"
    for child in b.quoteBlocks: result.add outlineBlock(child, indent & "  ")
  of bkFigure: result = indent & "figure " & outlineSpans(@[b.figureImage]) & " " & outlineSpans(b.caption) & "\n"
  of bkFootnotes: result = indent & "notes " & $b.footnotes.len & "\n"
  of bkExcerptBreak: result = indent & "excerpt-break\n"
  of bkComponent: result = indent & "refused component <" & b.componentName & ">\n"

proc outline*(src: string): string =
  ## The outline of `src` as this consumer reads it.
  for b in parseMarkdownBlocks(src):
    result.add outlineBlock(b, "")
