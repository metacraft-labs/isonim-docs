## Tier 2 M3 deliverable 3 suite -- dual-target: both `nim c -r` and
## `nim js -r` must pass.
##
## Proves `markdown_view.renderCodeFence`/`renderCodeFenceHtml` wrap
## every code block in a `codeBlockClass` div carrying an SSR-rendered
## `<button>` with a stable `aria-label` and a `data-copied="false"`
## idle state -- the structural contract `main_web.wireCodeCopyButton`
## (JS-target only, covered by `test_code_copy_browser_mount.nim`) walks
## to find the button/code pair and wire the real clipboard copy +
## "copied" toggle. This suite only proves the static markup: it never
## touches `navigator.clipboard` or click wiring, since neither exists
## on the MockRenderer/SSR-string side.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/components/markdown_view
import ./helpers/mock_tree

proc findCodeBlockWrapper(r: MockRenderer; root: MockNode): MockNode =
  ## `root` itself (`docs-md-body`) is also a `<div>`, so a plain
  ## `findByTag(root, "div")` would match it instead of the nested
  ## code-block wrapper -- search by class instead.
  findWhere(root, proc(n: MockNode): bool =
    n.kind == mnkElement and n.tag == "div" and getAttribute(r, n, "class") == codeBlockClass)

suite "docs code-copy button -- MockRenderer (Tier 2, dual-target)":
  test "renderMarkdownBody: a code fence is wrapped with a copy button carrying an aria-label":
    let blocks = parseMarkdownBlocks("```nim\necho 1\n```")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let btn = findByTag(root, "button")
    require btn != nil
    check getAttribute(r, btn, "type") == "button"
    check getAttribute(r, btn, "class") == codeCopyButtonClass
    check getAttribute(r, btn, "aria-label") == codeCopyIdleLabel
    check getAttribute(r, btn, "data-copied") == "false"
    check textContent(btn) == codeCopyIdleLabel

    let pre = findByTag(root, "pre")
    require pre != nil
    check getAttribute(r, pre, "class") == codeFenceClass

  test "renderMarkdownBody: the copy button is the code block wrapper's first child, the fence its second":
    let blocks = parseMarkdownBlocks("```nim\necho 1\n```")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let wrapper = findCodeBlockWrapper(r, root)
    require wrapper != nil
    require wrapper.children.len == 2
    check wrapper.children[0].tag == "button"
    check wrapper.children[1].tag == "pre"

  test "renderMarkdownBody: every code block in a multi-fence document gets its own copy button":
    let blocks = parseMarkdownBlocks("```nim\necho 1\n```\n\n```json\n{}\n```")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let buttons = findAllByTag(root, "button")
    check buttons.len == 2
    for btn in buttons:
      check getAttribute(r, btn, "aria-label") == codeCopyIdleLabel

suite "docs code-copy button -- SSR string (Tier 2, dual-target)":
  test "renderCodeFenceHtml: emits a copy button with aria-label before the fence":
    let blocks = parseMarkdownBlocks("```nim\necho 1\n```")
    let html = renderMarkdownBodyHtml(blocks)
    check html.contains(
      "<div class=\"" & codeBlockClass & "\">" &
      "<button type=\"button\" class=\"" & codeCopyButtonClass &
      "\" aria-label=\"" & codeCopyIdleLabel &
      "\" data-copied=\"false\">" & codeCopyIdleLabel & "</button>" &
      "<pre class=\"" & codeFenceClass & "\">")

  test "renderMarkdownBodyHtml: every code block in a multi-fence document gets its own copy button":
    let blocks = parseMarkdownBlocks("```nim\necho 1\n```\n\n```json\n{}\n```")
    let html = renderMarkdownBodyHtml(blocks)
    check html.count("<button type=\"button\" class=\"" & codeCopyButtonClass & "\"") == 2
