## isonim-docs/site -- the Metacraft docs token layer, REBRANDED for the
## isonim-docs framework's own documentation site.
##
## This reuses the framework's own token/emitter machinery
## (`core/docs_tokens`: `DocsTokenLayer`, `literal`, `token`,
## `emitTokensCss`) exactly as the reference consumer
## (`isonim/docs/users/src/theme_tokens.nim`) does. It is the DATA half of
## the theme: it binds every `--docs-*` CSS custom property the isonim-docs
## framework components consume to a light + dark value. The RULES half --
## the structural CSS that USES these variables -- lives in
## `assets/style.css` (reused verbatim from the same Metacraft theme).
##
## Branding note: these are the framework's OWN docs, a product distinct
## from CodeTracer, so no CodeTracer logo/branding is shipped (see
## `docs_config.nim`: no `siteLogo`, an isonim-docs footer, siteTitle
## "isonim-docs"). The token VALUES themselves are neutral documentation
## colours (a warm canvas, a blue accent, severity tints) with no product
## identity, so the theme's palette is reused as-is; only the chrome
## (title/logo/footer) is rebranded via the M3 `DocsConfig` hooks.
##
## Where a docs value MATCHES a design-system primitive (the focus ring and
## the admonition severity borders are the `brand.json` .500 blue / green /
## amber / red / violet primitives) it is bound BY TOKEN (`bkToken`),
## resolved against `codetracer-design-system/{brand,alias,mapped}/*.json`,
## exactly as the reference consumer does. The emitted CSS (via
## `emitTokensCss`) is prepended onto `assets/style.css` by `src/build.nim`
## through `buildSite(docsTokensCss = ...)`.

import std/os
import core/[tokens, docs_tokens]

export docs_tokens.emitTokensCss

const siteRoot = currentSourcePath().parentDir().parentDir()
  ## `.../isonim-docs/site` (this module lives in `site/src/`).
const designSystemRoot = siteRoot / "../.." / "codetracer-design-system"
  ## `site/../..` -> the workspace root; the design system is a sibling.

proc designSystemTokens*(): TokenSet =
  ## Loads the canonical Metacraft brand/alias/mapped DTCG token set so the
  ## layer's `bkToken` bindings resolve to concrete primitives.
  loadTokens(
    designSystemRoot / "brand" / "brand.json",
    designSystemRoot / "alias" / "alias.json",
    designSystemRoot / "mapped" / "mapped.json")

const geistFontFace = """@font-face {
  font-family: "Geist";
  font-style: normal;
  font-weight: 100 900;
  font-display: swap;
  src: url(/assets/fonts/Geist-Variable.woff2) format("woff2");
}"""

proc isonimDocsTokenLayer*(): DocsTokenLayer =
  ## The full docs token layer for the isonim-docs self-docs: every
  ## `--docs-*` variable the framework consumes, ordered for a
  ## deterministic, diff-stable emit.
  result.fontFaces = geistFontFace

  # --- fonts -------------------------------------------------------------
  result.add "--docs-font-sans", literal(
    "\"Geist\", ui-sans-serif, system-ui, -apple-system, \"Segoe UI\", Roboto, sans-serif")
  result.add "--docs-font-mono", literal(
    "ui-monospace, SFMono-Regular, \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", monospace")

  # --- structural scale (identical light/dark) ---------------------------
  result.add "--docs-space-1", literal("0.25rem")
  result.add "--docs-space-2", literal("0.5rem")
  result.add "--docs-space-3", literal("0.75rem")
  result.add "--docs-space-4", literal("1rem")
  result.add "--docs-space-5", literal("1.5rem")
  result.add "--docs-space-6", literal("2rem")
  result.add "--docs-space-8", literal("3rem")

  result.add "--docs-radius-sm", literal("4px")
  result.add "--docs-radius-md", literal("8px")
  result.add "--docs-radius-lg", literal("10px")
  result.add "--docs-radius-code", literal("6px")
  result.add "--docs-radius-pill", literal("999px")

  result.add "--docs-font-size-sm", literal("0.85rem")
  result.add "--docs-font-size-base", literal("1rem")
  result.add "--docs-line-height", literal("1.5")
  result.add "--docs-max-content-width", literal("50rem")
  result.add "--docs-sidebar-width", literal("20rem")

  # --- surfaces & text ---------------------------------------------------
  result.add "--docs-bg", literal("#f0eeea", "#161719")
  result.add "--docs-bg-raised", literal("#E7E5E1", "#31343a")
  result.add "--docs-fg", literal("#111111", "#dfe0e4")
  result.add "--docs-fg-muted", literal("#7e7e7e", "#a8aab1")
  result.add "--docs-border", literal("#e5e7eb", "#3c4046")

  # --- accent / links ----------------------------------------------------
  result.add "--docs-accent", literal("#4168cc", "#88a4f2")
  result.add "--docs-accent-fg", literal("#ffffff", "#161719")
  result.add "--docs-link", literal("#4168cc", "#88a4f2")

  # --- code --------------------------------------------------------------
  result.add "--docs-code-bg", literal("#f6f8fa", "#1d1f22")
  result.add "--docs-code-inline-bg", literal("#f1f5f9", "#272a2e")
  result.add "--docs-code-fg", literal("#282A2D", "#eeeef1")

  # --- focus ring: EXACT match to brand blue.500 -> bind by token --------
  result.add "--docs-focus-ring", token("colors.blue.500", "colors.blue.500")

  result.add "--docs-shadow", literal(
    "0 14px 40px rgba(0, 0, 0, 0.13)", "0 14px 40px rgba(0, 0, 0, 0.55)")
  result.add "--docs-input-bg", literal("#ffffff", "#202124")

  # --- syntax highlight --------------------------------------------------
  result.add "--docs-tok-keyword", literal("#a626a4", "#d2a8ff")
  result.add "--docs-tok-string", literal("#22863a", "#7ee787")
  result.add "--docs-tok-comment", literal("#6a737d", "#8b949e")
  result.add "--docs-tok-number", literal("#005cc5", "#79c0ff")

  # --- admonitions: severity BORDERS are the brand .500 primitives -------
  result.add "--docs-admonition-note-border", token("colors.blue.500", "colors.blue.500")
  result.add "--docs-admonition-note-bg", literal("#eff6ff", "rgba(99, 160, 255, 0.12)")
  result.add "--docs-admonition-tip-border", token("colors.green.500", "colors.green.500")
  result.add "--docs-admonition-tip-bg", literal("#f0fdf4", "rgba(74, 222, 128, 0.12)")
  result.add "--docs-admonition-warning-border", token("colors.amber.500", "colors.amber.500")
  result.add "--docs-admonition-warning-bg", literal("#fffbeb", "rgba(251, 191, 36, 0.12)")
  result.add "--docs-admonition-danger-border", token("colors.red.500", "colors.red.500")
  result.add "--docs-admonition-danger-bg", literal("#fef2f2", "rgba(248, 113, 113, 0.12)")
  result.add "--docs-admonition-important-border", token("colors.violet.500", "colors.violet.500")
  result.add "--docs-admonition-important-bg", literal("#f5f3ff", "rgba(139, 92, 246, 0.12)")
  result.add "--docs-admonition-caution-border", token("colors.red.500", "colors.red.500")
  result.add "--docs-admonition-caution-bg", literal("#fef2f2", "rgba(248, 113, 113, 0.12)")

  # --- API reference method colours --------------------------------------
  result.add "--docs-api-get", literal("#1a8754", "#56d364")
  result.add "--docs-api-post", literal("#2f6feb", "#6ea8ff")
  result.add "--docs-api-put", literal("#b8860b", "#e3b341")
  result.add "--docs-api-patch", literal("#8250df", "#d2a8ff")
  result.add "--docs-api-delete", literal("#cc3333", "#ff7b72")
  result.add "--docs-api-other", literal("#5b6270", "#9aa2b1")
