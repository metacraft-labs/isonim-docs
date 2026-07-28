---
title: Feature Index
description: A capabilities matrix of every isonim-docs framework feature, each linked to its documentation page, with its shipped status.
order: 16
---
# Feature Index

isonim-docs is a complete documentation-site framework. The matrix below maps
every shipped capability to the page that documents it. Every feature listed
is implemented and covered here; the status column reflects the actual state
of the framework, not an aspiration.

| Feature | Documentation | Status |
| --- | --- | --- |
| Isomorphic rendering (SSG / SSR / SPA + hydration) | [Introduction](./index.md) | Shipped |
| Content authoring & frontmatter | [Getting Started](./getting-started.md) | Shipped |
| File-based routing & auto-discovery | [Routing](./routing.md) | Shipped |
| Theming & design tokens | [Theming & Design Tokens](./theming.md) | Shipped |
| Extended Markdown (code, admonitions, tabs) | [Extended Markdown](./markdown.md) | Shipped |
| Navigation & client search | [Navigation & Search](./navigation-and-search.md) | Shipped |
| Server-side search (pluggable backends) | [Navigation & Search](./navigation-and-search.md) | Shipped |
| SEO artifacts & error handling | [SEO & Error Handling](./seo.md) | Shipped |
| OpenAPI REST reference (three-column) | [OpenAPI REST Reference](./api-reference.md) | Shipped |
| Library (Nim) API reference & symbol anchors | [Library API Reference](./library-reference.md) | Shipped |
| Live component embedding | [Live Component Embedding](./components.md) | Shipped |
| Interactive tutorials | [Tutorials, Versioning & i18n](./tutorials.md) | Shipped |
| Documentation versioning (`/vX.Y/`) | [Tutorials, Versioning & i18n](./tutorials.md) | Shipped |
| Internationalization (locales + hreflang) | [Tutorials, Versioning & i18n](./tutorials.md) | Shipped |
| Plugin architecture (hooks + directives) | [Plugins](./plugins.md) | Shipped |
| Dev server & live reload (HMR) | [Dev Server & Live Reload](./dev-server.md) | Shipped |
| CLI toolchain (init / dev / build / serve) | [CLI Toolchain](./cli.md) | Shipped |
| Deployment adapter (nginx SSR module) | [Deployment (nginx Adapter)](./deployment.md) | Shipped |
| Content-Security-Policy manager | [CSP & Analytics](./security.md) | Shipped |
| Privacy-respecting analytics | [CSP & Analytics](./security.md) | Shipped |

Each row's behavior is documented from the framework's real API and, wherever
it involves runnable Nim, verified by compiling the example against the
framework itself.
