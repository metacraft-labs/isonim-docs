## Docs token layer + token->CSS emitter.
##
## The isonim-docs framework theme contract is a fixed set of ~30
## `--docs-*` CSS custom properties (see `assets/style.css`'s `:root`
## block). A *docs token layer* is the DATA that binds each of those
## variables -- for both light and dark mode -- to EITHER a resolved
## design-system token (by dotted key, resolved via `core/tokens`) OR a
## docs-specific literal (a warm canvas hex, a blue accent, a font stack
## the brand tokens don't carry). Per the project's divergence decision,
## docs-specific literals are first-class and legitimate here.
##
## This binding is consumer-suppliable data, NOT baked into the framework:
## the framework ships no docs token layer, so its default output is
## unchanged. A consumer defines one (in Nim, or loaded from JSON) and
## feeds the emitted CSS into its build.
##
## The emitter turns a docs token layer into the exact CSS shape the
## framework already uses: a `:root{ --docs-*: ... }` light block, a
## `[data-theme="dark"]` dark block, and a
## `@media (prefers-color-scheme: dark) :root:not([data-theme="light"])`
## dark block. Pure string work; identical on the C and JS targets.

import std/[json, strutils]
import ./tokens

type
  BindingKind* = enum
    ## How one `--docs-*` variable's value is produced.
    bkLiteral   ## a docs-specific literal (hex, font stack, shadow, ...)
    bkToken     ## a dotted design-system token key, resolved via a TokenSet

  Binding* = object
    ## The light + dark source for one `--docs-*` variable. For a
    ## `bkLiteral` binding, `light`/`dark` are the CSS values verbatim; for
    ## a `bkToken` binding, they are dotted token keys resolved against the
    ## `TokenSet` handed to the emitter.
    kind*: BindingKind
    light*: string
    dark*: string

  DocsTokenLayer* = object
    ## A whole docs token layer: an optional block of prelude CSS
    ## (`@font-face` declarations for docs-specific self-hosted fonts) plus
    ## the ordered list of `(--docs-var, binding)` pairs. Ordered so the
    ## emitted CSS is deterministic and diff-stable.
    fontFaces*: string
    vars*: seq[tuple[name: string, binding: Binding]]

proc literal*(light, dark: string): Binding =
  ## A docs-specific literal binding (same or differing light/dark values).
  Binding(kind: bkLiteral, light: light, dark: dark)

proc literal*(value: string): Binding =
  ## A literal that is identical in light and dark (e.g. a font stack).
  Binding(kind: bkLiteral, light: value, dark: value)

proc token*(lightKey, darkKey: string): Binding =
  ## A binding to design-system token keys, one per mode, resolved by the
  ## emitter against its `TokenSet`.
  Binding(kind: bkToken, light: lightKey, dark: darkKey)

proc add*(layer: var DocsTokenLayer, name: string, binding: Binding) =
  ## Appends one `--docs-*` binding, preserving insertion order.
  layer.vars.add (name, binding)

proc parseBindingSide(node: JsonNode): string =
  ## One side ("light"/"dark") of a JSON binding is either
  ## `{"literal": "..."}` or `{"token": "dotted.key"}`.
  if node.hasKey("literal"): node["literal"].getStr
  elif node.hasKey("token"): node["token"].getStr
  else: raise newException(ValueError,
    "docs token layer: a binding side must have a 'literal' or 'token' key")

proc loadDocsTokenLayer*(jsonText: string): DocsTokenLayer =
  ## Loads a docs token layer from JSON so it can be consumer-supplied
  ## data rather than Nim code. Shape:
  ##
  ## ```json
  ## {
  ##   "fontFaces": "@font-face{ ... }",
  ##   "vars": {
  ##     "--docs-bg":     { "light": {"literal":"#f0eeea"}, "dark": {"literal":"#161719"} },
  ##     "--docs-fg":     { "light": {"token":"colors.ui.text.body"},
  ##                        "dark":  {"token":"colors.ui.text.body-dark"} }
  ##   }
  ## }
  ## ```
  ##
  ## `vars` is a JSON object; Nim's `std/json` preserves object key order,
  ## so the emitted CSS variable order matches the document.
  let doc = parseJson(jsonText)
  if doc.hasKey("fontFaces"):
    result.fontFaces = doc["fontFaces"].getStr
  if not doc.hasKey("vars"):
    raise newException(ValueError, "docs token layer: missing 'vars'")
  for name, spec in doc["vars"]:
    let kindLight = spec["light"].hasKey("token")
    let b =
      if kindLight:
        token(parseBindingSide(spec["light"]), parseBindingSide(spec["dark"]))
      else:
        literal(parseBindingSide(spec["light"]), parseBindingSide(spec["dark"]))
    result.vars.add (name, b)

proc valueFor(ts: TokenSet, b: Binding, dark: bool): string =
  ## The resolved CSS value for one binding in the requested mode.
  let raw = if dark: b.dark else: b.light
  case b.kind
  of bkLiteral: raw
  of bkToken: ts.resolve(raw)

proc emitBlock(layer: DocsTokenLayer, ts: TokenSet, dark: bool,
               indent: string): string =
  ## The `--docs-*: value;` declaration lines for one mode.
  for (name, binding) in layer.vars:
    result.add indent & name & ": " & valueFor(ts, binding, dark) & ";\n"

proc emitTokensCss*(layer: DocsTokenLayer, ts: TokenSet = TokenSet()): string =
  ## Emits the docs token layer as CSS in the exact shape the framework's
  ## `assets/style.css` already uses:
  ##
  ## * any `@font-face` prelude verbatim,
  ## * a `:root { --docs-*: <light> }` block,
  ## * a `[data-theme="dark"] { --docs-*: <dark> }` block, and
  ## * a `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --docs-*: <dark> } }`
  ##   block,
  ##
  ## so the system-preference default and the explicit toggle behave
  ## exactly like the framework default. `ts` supplies the values for any
  ## `bkToken` bindings; a purely-literal layer may pass the empty
  ## default. The output contains no class selectors, so the build's CSS
  ## purge step preserves every rule (see `core/asset_pipeline.purgeCss`).
  if layer.fontFaces.len > 0:
    result.add layer.fontFaces.strip(leading = false) & "\n\n"

  result.add ":root {\n"
  result.add emitBlock(layer, ts, dark = false, indent = "  ")
  result.add "}\n\n"

  result.add "[data-theme=\"dark\"] {\n"
  result.add emitBlock(layer, ts, dark = true, indent = "  ")
  result.add "}\n\n"

  result.add "@media (prefers-color-scheme: dark) {\n"
  result.add "  :root:not([data-theme=\"light\"]) {\n"
  result.add emitBlock(layer, ts, dark = true, indent = "    ")
  result.add "  }\n"
  result.add "}\n"

proc fixtureDocsTokenLayer*(): DocsTokenLayer =
  ## A small, self-contained example docs token layer (deliverable 2's
  ## "a fixture instance is fine for M1"). It mixes docs-specific literals
  ## -- a warm `#f0eeea` canvas, a blue accent, a Geist font stack, and an
  ## `@font-face` prelude -- with the framework's neutral values, each with
  ## a light and a dark value. The real Metacraft/CodeTracer values (bound
  ## partly to resolved design-system tokens) are applied in M2; this
  ## fixture is what M1's emitter test exercises.
  result.fontFaces =
    "@font-face {\n" &
    "  font-family: \"Geist\";\n" &
    "  font-style: normal;\n" &
    "  font-weight: 400;\n" &
    "  font-display: swap;\n" &
    "  src: url(/assets/fonts/Geist-Regular.woff2) format(\"woff2\");\n" &
    "}"
  result.add "--docs-font-sans", literal("\"Geist\", ui-sans-serif, system-ui, sans-serif")
  result.add "--docs-bg", literal("#f0eeea", "#161719")
  result.add "--docs-bg-raised", literal("#e7e5e1", "#1c1f26")
  result.add "--docs-fg", literal("#1a1d23", "#e7e9ee")
  result.add "--docs-fg-muted", literal("#5b6270", "#9aa2b1")
  result.add "--docs-border", literal("#e2e5ea", "#2c313c")
  result.add "--docs-accent", literal("#2f6feb", "#6ea8ff")
  result.add "--docs-accent-fg", literal("#ffffff", "#0b1220")
  result.add "--docs-link", literal("#2f6feb", "#6ea8ff")
  result.add "--docs-code-bg", literal("#f6f8fa", "#1c1f26")
  result.add "--docs-code-fg", literal("#282a2d", "#ff9d8a")
  result.add "--docs-focus-ring", literal("#2f6feb", "#6ea8ff")
  result.add "--docs-admonition-note-border", literal("#2f6feb", "#2f6feb")
  result.add "--docs-admonition-note-bg", literal("#eef4ff", "#16233d")
  result.add "--docs-admonition-tip-border", literal("#1a8754", "#1a8754")
  result.add "--docs-admonition-tip-bg", literal("#eafaf1", "#113321")
  result.add "--docs-admonition-warning-border", literal("#b8860b", "#b8860b")
  result.add "--docs-admonition-warning-bg", literal("#fff8e6", "#332a10")
  result.add "--docs-admonition-danger-border", literal("#cc3333", "#cc3333")
  result.add "--docs-admonition-danger-bg", literal("#fdeeee", "#3a1717")
