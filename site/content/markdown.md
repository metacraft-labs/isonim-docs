---
title: Extended Markdown
description: The isonim-docs Markdown engine -- code fences with syntax highlighting and a copy button, tabs, and six admonition severities.
order: 4
---
# Extended Markdown

isonim-docs parses Markdown into a typed block tree (`core/markdown_vm`)
that the same components render on every target. Beyond standard headings,
paragraphs, lists, links, and tables, the engine adds three authoring
features documented here: fenced code with highlighting and a copy button,
tabbed panels, and admonitions.

## Code fences

A fenced code block opens and closes with a line of three backticks; the
text after the opening fence is the language tag. The renderer wraps every
fence in a container whose first child is a **copy button** (idle label
"Copy code", "Copied!" after a click) and whose second child is the
highlighted `<pre>`. Syntax highlighting is built in for `nim`, `bash`
(aliases `sh`, `shell`), `json`, and `typescript` (aliases `ts`, `tsx`,
`js`, `jsx`, `javascript`).

The parser records each fence's language tag verbatim, which is how a
build-time test can single out examples that must compile:

```nim runnable
import core/markdown_vm
const bt = "\x60\x60\x60"   # three backticks, kept out of the source line
let src = "# Demo\n\n" & bt & "nim\nlet x = 1\n" & bt & "\n"
let doc = parseMarkdownDoc(src, "demo.md")
var fences = 0
for blk in doc.blocks:
  if blk.kind == bkCodeFence:
    inc fences
    doAssert blk.lang == "nim"
doAssert fences == 1
```

Fences tagged `nim runnable` are the convention this very site uses for
examples that are extracted and compiled by `tests/test_doc_examples_compile.nim`
-- the language tag survives parsing untouched, so a test can select on it.

## Admonitions

An admonition is a `:::severity` block closed by a bare `:::`. There are six
severities, each rendered with its own token-driven border and tint:
`note`, `tip`, `important`, `warning`, `caution`, and `danger`. An
unrecognized severity name falls back to `note`. Live examples:

:::note
`note` -- neutral, blue-bordered. The default severity.
:::

:::tip
`tip` -- green. For a helpful suggestion or shortcut.
:::

:::important
`important` -- violet. For something the reader must not miss.
:::

:::warning
`warning` -- amber. For a caveat that can bite.
:::

:::caution
`caution` -- red-bordered, distinct from `danger`.
:::

:::danger
`danger` -- red. For a destructive or irreversible action.
:::

All six severities parse to distinct `AdmonitionKind` values:

```nim runnable
import core/markdown_vm
const src = """
:::note
n
:::

:::tip
t
:::

:::important
i
:::

:::warning
w
:::

:::caution
c
:::

:::danger
d
:::
"""
let doc = parseMarkdownDoc(src, "adm.md")
var kinds: set[AdmonitionKind]
for blk in doc.blocks:
  if blk.kind == bkAdmonition:
    kinds.incl blk.admonitionKind
doAssert kinds == {akNote, akTip, akImportant, akWarning, akCaution, akDanger}
```

## Tabs

A `:::tabs` block groups alternative content behind labeled panels; each
`@tab Title` line starts a new panel, and a panel's body is re-parsed as a
full nested block list (so a panel can hold code fences, lists, even nested
admonitions -- not just paragraphs):

:::tabs
@tab Nim
This panel holds Nim content.

@tab Shell
This panel holds a shell transcript.
:::

The parser exposes each panel's title and its nested blocks:

```nim runnable
import core/markdown_vm
const src = """
:::tabs
@tab Nim
Nim panel body.

@tab Shell
Shell panel body.
:::
"""
let doc = parseMarkdownDoc(src, "tabs.md")
var panels = 0
for blk in doc.blocks:
  if blk.kind == bkTabs:
    panels = blk.tabs.len
    doAssert blk.tabs[0].title == "Nim"
    doAssert blk.tabs[1].title == "Shell"
doAssert panels == 2
```

## Headings and anchors

Every heading is parsed with a stable, slug-derived id, so the heading tree
(used by the on-page table of contents and by deep links) is trivially
derivable from the flat block list:

```nim runnable
import core/markdown_vm
let doc = parseMarkdownDoc("# Title\n\n## A Section\n\nText.", "h.md")
var headings = 0
for blk in doc.blocks:
  if blk.kind == bkHeading:
    inc headings
    doAssert blk.headingId.len > 0
doAssert headings == 2
```
