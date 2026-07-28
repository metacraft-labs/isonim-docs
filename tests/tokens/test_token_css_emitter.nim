## metacraft-theme M1 deliverables 2 + 3 verification: the docs token
## layer (`src/core/docs_tokens.nim`) and its token->CSS emitter.
##
## Proves the emitter (a) produces a `:root` block carrying the expected
## `--docs-*` variables with the docs-layer LIGHT values, (b) produces a
## `[data-theme="dark"]` block with the DARK values, (c) produces the
## `@media (prefers-color-scheme: dark) :root:not([data-theme="light"])`
## dark block in the framework's exact shape, (d) resolves `bkToken`
## bindings through a real `TokenSet`, and (e) emits CSS the build's purge
## step preserves in full (`@font-face` + every `--docs-*` var kept),
## since the emitted rules carry no class selectors.

import std/[unittest, strutils, sets]
import ../../src/core/[tokens, docs_tokens]
import ../../src/core/asset_pipeline

suite "docs token layer + token->CSS emitter (metacraft-theme M1 d2/d3)":

  test "the fixture docs layer emits :root light + dark blocks with the docs literal values":
    let css = emitTokensCss(fixtureDocsTokenLayer())

    # An @font-face prelude rides ahead of the variable blocks.
    check "@font-face" in css
    check "Geist-Regular.woff2" in css

    # A :root light block exists and carries the docs-specific LIGHT
    # literals: the warm canvas, the blue accent, the code/admonition vars.
    check ":root {" in css
    check "--docs-bg: #f0eeea;" in css
    check "--docs-accent: #2f6feb;" in css
    check "--docs-code-bg: #f6f8fa;" in css
    check "--docs-admonition-danger-bg: #fdeeee;" in css
    check "\"Geist\"" in css   # docs-specific font literal

    # A [data-theme="dark"] block exists and carries the DARK values.
    check "[data-theme=\"dark\"] {" in css
    check "--docs-bg: #161719;" in css
    check "--docs-accent: #6ea8ff;" in css
    check "--docs-code-bg: #1c1f26;" in css

    # The system-preference dark block is present in the framework's exact
    # shape: @media (prefers-color-scheme: dark) wrapping the
    # :root:not([data-theme="light"]) selector.
    check "@media (prefers-color-scheme: dark) {" in css
    check ":root:not([data-theme=\"light\"]) {" in css

    # The dark value #161719 must appear in BOTH dark blocks (the explicit
    # toggle block and the media-query block), never in the light :root.
    check css.count("--docs-bg: #161719;") == 2
    check css.count("--docs-bg: #f0eeea;") == 1

  test "light values land under :root and dark values only under the dark selectors":
    let css = emitTokensCss(fixtureDocsTokenLayer())
    let rootStart = css.find(":root {")
    let darkStart = css.find("[data-theme=\"dark\"]")
    check rootStart >= 0
    check darkStart > rootStart
    # The light :root block (before the dark selector) has the light bg and
    # not the dark bg.
    let rootBlock = css[rootStart ..< darkStart]
    check "--docs-bg: #f0eeea;" in rootBlock
    check "--docs-bg: #161719;" notin rootBlock

  test "bkToken bindings resolve through a real TokenSet":
    # A tiny two-layer DTCG set: alias -> brand.
    let ts = loadTokensFromStrings([
      """{ "colors": { "grey": { "50": {"$type":"color","$value":"#f3f3f3"} },
                       "ink":  {"$type":"color","$value":"#101114"} } }""",
      """{ "colors": { "surface": {"$type":"color","$value":"{colors.grey.50}"} } }"""
    ])
    var layer: DocsTokenLayer
    # --docs-bg bound to a resolved token (alias -> brand) in light, and a
    # different resolved token in dark.
    layer.add "--docs-bg", token("colors.surface", "colors.ink")
    # --docs-accent kept as a docs-specific literal alongside it.
    layer.add "--docs-accent", literal("#2f6feb", "#6ea8ff")

    let css = emitTokensCss(layer, ts)
    # The token binding resolved to the brand primitive in the light block.
    check "--docs-bg: #f3f3f3;" in css
    # ...and to the other token in the dark blocks (toggle + media query).
    check css.count("--docs-bg: #101114;") == 2
    # The literal binding rode through untouched.
    check "--docs-accent: #2f6feb;" in css
    check "--docs-accent: #6ea8ff;" in css

  test "loads a docs token layer from JSON data (consumer-suppliable)":
    let layerJson = """
    {
      "fontFaces": "@font-face { font-family: \"Geist\"; src: url(/assets/fonts/Geist.woff2); }",
      "vars": {
        "--docs-bg":     { "light": {"literal":"#f0eeea"}, "dark": {"literal":"#161719"} },
        "--docs-accent": { "light": {"literal":"#2f6feb"}, "dark": {"literal":"#6ea8ff"} }
      }
    }
    """
    let layer = loadDocsTokenLayer(layerJson)
    check layer.vars.len == 2
    let css = emitTokensCss(layer)
    check "@font-face" in css
    check "--docs-bg: #f0eeea;" in css
    check "--docs-bg: #161719;" in css
    check "--docs-accent: #2f6feb;" in css

  test "the emitted CSS is valid and the build's purge step preserves it in full":
    let css = emitTokensCss(fixtureDocsTokenLayer())

    # The purge keeps rules whose selectors reference an in-use class and
    # always keeps class-free rules. The emitted CSS has NO class selectors
    # (only :root, [data-theme], @media, @font-face), so even a purge run
    # with a completely unrelated used-class set must keep every var.
    var used = initHashSet[string]()
    used.incl "docs-frame"   # some unrelated class the "pages" used
    let purged = purgeCss(css, used)

    # @font-face survives (an unrecognized at-rule is kept verbatim).
    check "@font-face" in purged
    check "Geist-Regular.woff2" in purged
    # Every representative --docs-* var survives, in both light and dark.
    check "--docs-bg: #f0eeea;" in purged
    check "--docs-bg: #161719;" in purged
    check "--docs-accent: #2f6feb;" in purged
    check "--docs-accent: #6ea8ff;" in purged
    check "--docs-admonition-note-bg: #eef4ff;" in purged
    # The dark selectors themselves survive.
    check "[data-theme=\"dark\"]" in purged
    check ":root:not([data-theme=\"light\"])" in purged

    # Nothing was dropped: the fixture defines 20 --docs-* variables, each
    # emitted three times (light :root + dark toggle + dark media query).
    let expectedVarCount = fixtureDocsTokenLayer().vars.len
    check purged.count("--docs-") == expectedVarCount * 3
