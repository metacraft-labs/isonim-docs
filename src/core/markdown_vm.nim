## isonim-docs `core/markdown_vm` -- kept for compatibility: the Markdown
## AST and parser moved to IsoNim itself, as `isonim/content/markdown`.
##
## This module re-exports that module unchanged, so every existing
## import keeps compiling and sees the very same types (`Block`,
## `InlineSpan`, `MarkdownDoc`, ...) and procs (`parseMarkdownBlocks`,
## `parseInlineSpans`, `parseMarkdownDoc`, `normalizeRelativeLink`, ...).
## New code should import `isonim/content/markdown` directly.

{.deprecated: "isonim-docs' core/markdown_vm moved to IsoNim: import isonim/content/markdown instead".}

import isonim/content/markdown as contentMarkdown
export contentMarkdown
