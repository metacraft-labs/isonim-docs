---
title: Introduction
description: isonim-docs is a Nim documentation-site framework built on IsoNim, with one component codebase driving SSG, SSR, and SPA rendering.
order: 0
---
# Introduction

**isonim-docs** is a documentation-site framework written in Nim and built
on top of [IsoNim](https://github.com/metacraft-labs), the isomorphic
reactive UI framework for Nim. It turns a directory of Markdown files into a
themed documentation site with auto-discovered routing, a token-driven
theme, extended Markdown (tabs, admonitions, syntax highlighting), search,
and SEO artifacts (sitemap + robots) -- all from a single component
codebase.

This site is itself built with isonim-docs: it documents the framework by
dogfooding it. Every page you are reading is a Markdown file under
`content/`, rendered through the same shell the framework ships.

## One codebase, three render targets

The defining property of isonim-docs is that the *same* component code
resolves and renders a route on every target:

- **SSG** (static site generation) -- `build_site.buildSite` walks the
  route manifest and writes clean-URL `<route>/index.html` files. This is
  the production build (what `just build` runs).
- **SSR** (server-side rendering) -- `ssr.renderRoute` renders one route to
  `(status, html)` on demand, for a server or a smoke test.
- **SPA** (single-page app) -- the browser (JS target) mount entry hydrates
  the same components client-side.

Routing (`core/routes`), content loading (`core/content`), the Markdown
engine (`core/markdown_vm`), and site configuration (`core/config`) are all
pure, platform-free modules, so SSG, SSR, and SPA resolve the exact same
route against the exact same content rather than forking logic per target.

## Site configuration is plain data

A site is configured with a `DocsConfig` value -- pure data, no platform
imports. The framework ships a content-agnostic default; a real site passes
its own. Here is the framework default, which every field of a real config
overrides:

```nim runnable
import core/config

let cfg = docsConfig()
doAssert cfg.siteTitle.len > 0
doAssert cfg.defaultRoute == "/"
doAssert cfg.stylesheetHref == "/assets/style.css"
# Search defaults to the client-side index; CSP and analytics are off until
# a consumer opts in, so an unconfigured site's <head> is unchanged.
doAssert cfg.search.mode == smClientIndex
doAssert cfg.csp.enabled == false
doAssert cfg.analytics.provider == apNone
```

## What to read next

- [Getting Started](./getting-started.md) -- scaffold a consumer, write
  `content/`, build and serve.
- [Routing](./routing.md) -- auto-discovery vs. an explicit manifest.
- [Theming & Design Tokens](./theming.md) -- the `--docs-*` contract and the
  token machinery.
- [Extended Markdown](./markdown.md) -- tabs, admonitions, syntax
  highlighting, and the copy button.
