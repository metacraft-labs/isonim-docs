## Tier 1 + Tier 2 M3 deliverable 2 suite -- dual-target: both `nim c -r`
## and `nim js -r` must pass.
##
## Proves the real syntax-highlighting tokenizer (`src/core/syntax_highlight.nim`):
## `tokenize` classifies keywords/strings/comments/numbers into typed
## spans for at least nim/bash/json/typescript, an unknown language
## degrades to a single plain token instead of crashing, and
## `markdown_view`'s code-fence renderers (MockRenderer + SSR string)
## emit the highlighted `<span class="tok-*">` markup built on those
## tokens -- not merely a bare `language-*` class on `<code>`.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/core/syntax_highlight
import ../../src/components/markdown_view
import ./helpers/mock_tree

suite "syntax_highlight.tokenize -- pure tokenizer (Tier 1, dual-target)":
  test "nim: classifies a keyword, a string, and a line comment as distinct typed tokens":
    let tokens = tokenize("nim", "let x = \"hi\" # note")
    let kinds = block:
      var ks: seq[TokenKind] = @[]
      for t in tokens: ks.add t.kind
      ks
    check tkKeyword in kinds
    check tkString in kinds
    check tkComment in kinds

    let keywordTok = block:
      var found = Token(kind: tkPlain, text: "")
      for t in tokens:
        if t.kind == tkKeyword: found = t
      found
    check keywordTok.text == "let"

    let stringTok = block:
      var found = Token(kind: tkPlain, text: "")
      for t in tokens:
        if t.kind == tkString: found = t
      found
    check stringTok.text == "\"hi\""

    let commentTok = block:
      var found = Token(kind: tkPlain, text: "")
      for t in tokens:
        if t.kind == tkComment: found = t
      found
    check commentTok.text == "# note"

  test "nim: reassembling every token's text round-trips the original source exactly":
    let src = "proc add(a, b: int): int =\n  # sum two ints\n  result = a + b"
    let tokens = tokenize("nim", src)
    var rebuilt = ""
    for t in tokens: rebuilt.add t.text
    check rebuilt == src

  test "json: classifies object-key/value strings, numbers, and the null/true/false keywords":
    let tokens = tokenize("json", "{\"a\": 1, \"b\": true, \"c\": null}")
    var sawString, sawNumber, sawKeyword = false
    for t in tokens:
      case t.kind
      of tkString: sawString = true
      of tkNumber: sawNumber = true
      of tkKeyword: sawKeyword = true
      else: discard
    check sawString and sawNumber and sawKeyword

  test "bash: classifies control-flow keywords and a double-quoted string, ignores plain command words":
    let tokens = tokenize("bash", "if [ -f x ]; then\n  echo \"hi\"\nfi")
    var keywords: seq[string] = @[]
    var sawString = false
    for t in tokens:
      if t.kind == tkKeyword: keywords.add t.text
      if t.kind == tkString: sawString = true
    check "if" in keywords
    check "then" in keywords
    check "fi" in keywords
    check sawString

  test "typescript: classifies keywords, a string, and both line and block comments":
    let tokens = tokenize("typescript", "// leading\nconst x: string = \"hi\"; /* trailing */")
    var sawLineComment, sawBlockComment, sawKeyword, sawString = false
    for t in tokens:
      if t.kind == tkComment and t.text.startsWith("//"): sawLineComment = true
      if t.kind == tkComment and t.text.startsWith("/*"): sawBlockComment = true
      if t.kind == tkKeyword and t.text == "const": sawKeyword = true
      if t.kind == tkString: sawString = true
    check sawLineComment
    check sawBlockComment
    check sawKeyword
    check sawString

  test "an unrecognized language degrades to a single plain token, never crashes, and preserves the text":
    let src = "some <weird> & unknown syntax"
    let tokens = tokenize("cobol", src)
    check tokens.len == 1
    check tokens[0].kind == tkPlain
    check tokens[0].text == src

  test "an empty fence body tokenizes to no tokens, for both a known and an unknown language":
    check tokenize("nim", "").len == 0
    check tokenize("cobol", "").len == 0

  test "an unterminated string in a known language does not crash and consumes to end of input":
    let tokens = tokenize("nim", "let x = \"never closed")
    check tokens.len > 0
    check tokens[^1].kind == tkString
    check tokens[^1].text == "\"never closed"

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
