## Tier 1 + Tier 2 M3 deliverable 2 suite -- dual-target: both `nim c -r`
## and `nim js -r` must pass.
##
## Proves syntax highlighting renders: the tokenizer is IsoNim's
## (`isonim/content/highlight`; its pure tokenizer cases moved there with
## it), and `markdown_view`'s code-fence renderers (MockRenderer + SSR string)
## emit the highlighted `<span class="tok-*">` markup built on those
## tokens -- not merely a bare `language-*` class on `<code>`.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/core/syntax_highlight
import ../../src/components/markdown_view
import ./helpers/mock_tree

suite "code-fence highlighting -- MockRenderer (Tier 2, dual-target)":
  test "renderMarkdownBody: a nim code fence's keyword and string tokens render as classified <span> children":
    let blocks = parseMarkdownBlocks("```nim\nlet x = \"hi\"\n```")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let code = findByTag(root, "code")
    require code != nil
    check getAttribute(r, code, "class") == "language-nim"

    let spans = findAllByTag(code, "span")
    check spans.len == 2

    var sawKeywordSpan, sawStringSpan = false
    for s in spans:
      let cls = getAttribute(r, s, "class")
      if cls == "tok-keyword" and textContent(s) == "let": sawKeywordSpan = true
      if cls == "tok-string" and textContent(s) == "\"hi\"": sawStringSpan = true
    check sawKeywordSpan
    check sawStringSpan
    check textContent(code) == "let x = \"hi\""

  test "renderMarkdownBody: a code fence with an unrecognized language renders plain text, no <span>s, and never crashes":
    let blocks = parseMarkdownBlocks("```cobol\nDISPLAY 'HI'.\n```")
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks)

    let code = findByTag(root, "code")
    require code != nil
    check findAllByTag(code, "span").len == 0
    check textContent(code) == "DISPLAY 'HI'."

suite "code-fence highlighting -- SSR string (Tier 2, dual-target)":
  test "renderMarkdownBodyHtml: a nim code fence emits classified <span> markup for its keyword and string":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks("```nim\nlet x = \"hi\"\n```"))
    check html.contains("<span class=\"tok-keyword\">let</span>")
    check html.contains("<span class=\"tok-string\">&quot;hi&quot;</span>") or
      html.contains("<span class=\"tok-string\">\"hi\"</span>")

  test "renderMarkdownBodyHtml: a bash code fence emits classified spans for its keywords and string":
    let raw = "```bash\nif [ -f x ]; then\n  echo \"hi\"\nfi\n```"
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks(raw))
    check html.contains("<span class=\"tok-keyword\">if</span>")
    check html.contains("<span class=\"tok-keyword\">then</span>")
    check html.contains("<span class=\"tok-keyword\">fi</span>")

  test "renderMarkdownBodyHtml: a json code fence emits classified spans for strings, numbers, and keywords":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks("```json\n{\"a\": 1, \"b\": true}\n```"))
    check html.contains("<span class=\"tok-number\">1</span>")
    check html.contains("<span class=\"tok-keyword\">true</span>")

  test "renderMarkdownBodyHtml: a typescript code fence emits classified spans for keywords, strings, and comments":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks("```typescript\n// hi\nconst x = \"y\";\n```"))
    check html.contains("<span class=\"tok-comment\">// hi</span>")
    check html.contains("<span class=\"tok-keyword\">const</span>")

  test "renderMarkdownBodyHtml: an unrecognized language degrades to escaped plain text with no <span> markup":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks("```cobol\nDISPLAY <HI> & 'bye'.\n```"))
    check not html.contains("<span")
    check html.contains("DISPLAY &lt;HI&gt; &amp; 'bye'.")

  test "renderMarkdownBodyHtml: a comment token's own '<'/'&' characters are still HTML-escaped inside its span":
    let html = renderMarkdownBodyHtml(parseMarkdownBlocks("```nim\n# a < b & c\ndiscard\n```"))
    check html.contains("<span class=\"tok-comment\">")
    check html.contains("a &lt; b &amp; c")
