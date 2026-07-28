---
title: Theming & Design Tokens
description: The --docs-* CSS custom-property contract and the token layer that binds each variable to a light + dark value.
order: 3
---
# Theming & Design Tokens

The isonim-docs theme has two halves. The **rules** half is
`assets/style.css`: structural CSS that reads a fixed set of ~40 `--docs-*`
CSS custom properties (`--docs-bg`, `--docs-fg`, `--docs-accent`,
`--docs-admonition-tip-border`, ...). The **data** half is a *docs token
layer*: the values that bind each of those variables, for both light and
dark mode.

The framework ships no token layer, so its default output is unchanged. A
consumer supplies one -- in Nim or loaded from JSON -- and feeds the emitted
CSS into its build. This site's own layer lives in `src/theme_tokens.nim`.

## The `--docs-*` contract

Because the stylesheet only ever reads variables, re-theming a site is
purely a matter of changing their values -- you never touch the CSS rules.
A binding is either a **literal** (a hex, a font stack, a shadow -- values
the design system doesn't carry) or a **token** (a dotted design-system key,
resolved to a concrete primitive). Both light and dark values are supplied
per variable.

## Building a token layer

`core/docs_tokens` is the machinery. Add `(--docs-var, binding)` pairs to a
`DocsTokenLayer` in order, then emit CSS with `emitTokensCss`. A purely
literal layer needs no `TokenSet`:

```nim runnable
import std/strutils
import core/docs_tokens

var layer: DocsTokenLayer
layer.add "--docs-bg", literal("#f0eeea", "#161719")
layer.add "--docs-fg", literal("#111111", "#dfe0e4")
layer.add "--docs-accent", literal("#4168cc", "#88a4f2")

let css = emitTokensCss(layer)
# The emitter produces the exact three-block shape style.css expects: a
# :root light block, an explicit [data-theme="dark"] block, and a
# prefers-color-scheme dark block for the system default.
doAssert css.contains(":root {")
doAssert css.contains("--docs-bg: #f0eeea;")
doAssert css.contains("[data-theme=\"dark\"] {")
doAssert css.contains("--docs-bg: #161719;")
doAssert css.contains("@media (prefers-color-scheme: dark) {")
```

## Binding to design-system tokens

When a `--docs-*` value should track a design-system primitive rather than a
loose literal, bind it by token. The emitter resolves the dotted key against
a `TokenSet` loaded from DTCG (W3C Design Tokens) JSON, following any
`{alias}` chain across the loaded layers:

```nim runnable
import std/strutils
import core/docs_tokens
import core/tokens

# A minimal DTCG document; a real site loads brand/alias/mapped files.
let ts = loadTokensFromStrings(@["""
{ "colors": { "blue": { "500": { "$type": "color", "$value": "#4168cc" } } } }
"""])

var layer: DocsTokenLayer
layer.add "--docs-accent", token("colors.blue.500", "colors.blue.500")

let css = emitTokensCss(layer, ts)
# The dotted key resolved to its concrete primitive value.
doAssert css.contains("--docs-accent: #4168cc;")
```

`@font-face` declarations for self-hosted fonts ride along as a prelude on
the layer, emitted verbatim ahead of the variable blocks:

```nim runnable
import std/strutils
import core/docs_tokens

var layer: DocsTokenLayer
layer.fontFaces = "@font-face { font-family: \"Geist\"; src: url(/assets/fonts/Geist-Variable.woff2) format(\"woff2\"); }"
layer.add "--docs-font-sans", literal("\"Geist\", system-ui, sans-serif")

let css = emitTokensCss(layer)
doAssert css.contains("@font-face")
doAssert css.contains("--docs-font-sans")
```

## Wiring the layer into the build

The emitted CSS is not a separate asset. `buildSite` accepts a
`docsTokensCss` argument and **prepends** it onto `assets/style.css` before
the hash-and-purge step, so the token layer rides the existing single,
content-hashed stylesheet the pages already reference -- no extra request,
no `@import` for the hasher to break. A consumer build entry looks like:

```nim runnable
import build_site
import core/docs_tokens
import core/config

proc buildThemed(): int =
  var layer: DocsTokenLayer
  layer.add "--docs-accent", literal("#4168cc", "#88a4f2")
  let tokensCss = emitTokensCss(layer)
  buildSite(contentDir = "content", cfg = docsConfig(), docsTokensCss = tokensCss)

when isMainModule:
  discard buildThemed()
```

## Branding hooks

The site title, an optional logo, and a footer are set on `DocsConfig`
rather than in CSS, so re-branding needs no stylesheet edit. This site sets
`siteTitle` and `footerHtml` and ships *no* logo:

```nim runnable
import core/config

let cfg = DocsConfig(
  siteTitle: "isonim-docs",
  siteDescription: "The framework's own docs.",
  defaultRoute: "/",
  stylesheetHref: "/assets/style.css",
  footerHtml: "Built with isonim-docs.",
)
doAssert cfg.siteTitle == "isonim-docs"
doAssert cfg.siteLogo.len == 0   # no logo: the header shows the plain title
doAssert cfg.footerHtml.len > 0
```
