## M1 verification (adapter): DTCG -> EditorWorkspace.
##
## Proves the `dtcg_workspace` adapter turns a fixture brand/alias/mapped
## DTCG set + a docs token layer into an `EditorWorkspace` whose
## `foundationTokens`:
##   * preserve the alias-chain head (`aliasOf`) for token-bound vars,
##   * carry the correct `kind` mapped from the DTCG `$type`,
##   * expose light/dark `modeValues` on the design-schema nodes, and
##   * resolve to EXACTLY the values `docs_tokens.emitTokensCss` emits
##     (a genuine cross-check against the token->CSS emitter).
##
## Target-agnostic (pure data): runs on both `nim c -r` and `nim js -r`.

import std/[strutils, unittest]

import core/[tokens, docs_tokens]
import isonim/editor
import ../dtcg_workspace

# ---------------------------------------------------------------------------
# Fixture: a real 3-hop brand -> alias -> mapped chain, mirroring the shape
# of codetracer-design-system/{brand,alias,mapped}/*.json.
# ---------------------------------------------------------------------------

const brandJson = """
{
  "colors": {
    "grey":  { "50":  { "$type": "color", "$value": "#f3f3f3" } },
    "blue":  { "500": { "$type": "color", "$value": "#4168cc" } },
    "green": { "500": { "$type": "color", "$value": "#3fb950" } }
  },
  "space": { "card": { "$type": "dimension", "$value": "16px" } }
}
"""

const aliasJson = """
{
  "colors": {
    "neutral": { "50": { "$type": "color", "$value": "{colors.grey.50}" } }
  }
}
"""

const mappedJson = """
{
  "colors": {
    "ui": { "text": { "body": { "$type": "color", "$value": "{colors.neutral.50}" } } }
  }
}
"""

proc fixtureTokens(): TokenSet =
  loadTokensFromStrings([brandJson, aliasJson, mappedJson])

proc fixtureLayer(): DocsTokenLayer =
  ## A docs token layer mixing:
  ##   * a 3-hop token binding (--docs-fg -> mapped.colors.ui.text.body ->
  ##     alias.colors.neutral.50 -> brand.colors.grey.50 -> #f3f3f3),
  ##   * a 1-hop token binding differing per mode (--docs-focus-ring),
  ##   * an accent + accent-fg literal pair (contrast wiring), and
  ##   * a literal radius + a literal font stack.
  result.add "--docs-fg", token("colors.ui.text.body", "colors.ui.text.body")
  result.add "--docs-accent", token("colors.blue.500", "colors.green.500")
  result.add "--docs-accent-fg", literal("#ffffff", "#161719")
  result.add "--docs-radius-lg", literal("10px")
  result.add "--docs-font-sans", literal("\"Geist\", sans-serif")

suite "DTCG -> EditorWorkspace adapter (M1)":
  let ts = fixtureTokens()
  let layer = fixtureLayer()

  test "foundationTokens preserve alias-chain head + resolved value":
    let tokens = dtcgFoundationTokens(layer, ts)
    check tokens.len == 5

    # --docs-fg follows the full 3-hop chain down to the brand primitive.
    let fg = tokens[0]
    check fg.key == "--docs-fg"
    check fg.aliasOf == "colors.ui.text.body"   # alias-chain head preserved
    check fg.value == "#f3f3f3"                  # fully resolved primitive
    check fg.kind == ftkSemanticColor            # aliased colour -> semantic

    # --docs-accent is token-bound (blue.500 in light).
    let accent = tokens[1]
    check accent.aliasOf == "colors.blue.500"
    check accent.value == "#4168cc"
    check accent.kind == ftkSemanticColor

  test "kind maps from DTCG $type (token) and var name (literal)":
    let tokens = dtcgFoundationTokens(layer, ts)
    check tokens[2].kind == ftkColorPalette   # --docs-accent-fg literal colour
    check tokens[2].aliasOf == ""             # literal -> no alias
    check tokens[3].kind == ftkRadiusScale    # --docs-radius-lg literal
    check tokens[4].kind == ftkTypographyScale # --docs-font-sans literal

  test "design-schema nodes carry light + dark modeValues":
    var tokens = dtcgFoundationTokens(layer, ts)
    let schema = dtcgDesignSchema(layer, ts, tokens)
    check schema.nodes.len == 5

    # --docs-accent differs per mode: blue.500 (light) / green.500 (dark).
    let accentNode = schema.nodes[1]
    check accentNode.modeValues.len == 2
    check accentNode.modeValues[0].kind == dtmkLight
    check accentNode.modeValues[0].value == "#4168cc"
    check accentNode.modeValues[1].kind == dtmkDark
    check accentNode.modeValues[1].value == "#3fb950"

  test "resolved values match emitTokensCss output exactly":
    var tokens = dtcgFoundationTokens(layer, ts)
    let schema = dtcgDesignSchema(layer, ts, tokens)
    let css = emitTokensCss(layer, ts)

    # Parse the :root (light) and [data-theme="dark"] declaration blocks.
    proc blockDecls(css, opener: string): seq[(string, string)] =
      let start = css.find(opener)
      check start >= 0
      let braceOpen = css.find('{', start)
      let braceClose = css.find('}', braceOpen)
      for line in css[braceOpen + 1 ..< braceClose].splitLines:
        let s = line.strip
        if s.len == 0 or not s.startsWith("--"): continue
        let colon = s.find(':')
        result.add (s[0 ..< colon].strip, s[colon + 1 .. ^1].strip.strip(chars = {';'}))

    let light = blockDecls(css, ":root {")
    let dark = blockDecls(css, "[data-theme=\"dark\"] {")
    check light.len == 5
    check dark.len == 5

    # Every foundation token's value == the emitter's :root value, and every
    # schema node's dark modeValue == the emitter's dark-block value.
    for i, (name, lightVal) in light:
      check tokens[i].key == name
      check tokens[i].value == lightVal
      check schema.nodes[i].modeValues[0].value == lightVal
    for i, (name, darkVal) in dark:
      check schema.nodes[i].modeValues[1].value == darkVal

  test "workspace assembles with docs stories + contrast wiring":
    let ws = metacraftEditorWorkspace(layer, ts)
    check ws.foundationTokens.len == 5
    check ws.storyGroups.len == 6                 # Foundations..Search
    check ws.designSystemSchema.nodes.len == 5
    check ws.initialView == evFoundationsPage

    # accent/accent-fg pair produced a real contrast constraint.
    var accent: FoundationTokenEntry
    for t in ws.foundationTokens:
      if t.key == "--docs-accent": accent = t
    check accent.background == "#4168cc"
    check accent.foreground == "#ffffff"
    check accent.minContrast == 4.5

    # affectedStories were populated (drives impact analysis).
    check accent.affectedStories.len > 0
