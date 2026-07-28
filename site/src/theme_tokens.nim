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

const docsDesignSystemJson = staticRead(
  designSystemRoot / "docs" / "codetracer-docs.tokens.json")
  ## The shared CodeTracer docs design system, embedded at compile time -- the
  ## SINGLE source of truth for the --docs-* tokens, consumed identically by
  ## every Metacraft docs site and the design-system editor. Edit the tokens
  ## THERE (or via the editor), not here. See that repo's DESIGN-DIVERGENCES.md.

proc isonimDocsTokenLayer*(): DocsTokenLayer =
  ## The CodeTracer docs token layer, loaded from the shared design system
  ## (codetracer-design-system/docs/codetracer-docs.tokens.json).
  loadDocsTokenLayer(docsDesignSystemJson)
