# isonim-docs

A feature-rich **documentation-site framework** built on Metacraft Labs'
[IsoNim](../isonim) isomorphic reactive UI framework for Nim.

`isonim-docs` lets you author documentation sites that combine the best of
**mdBook**, **MkDocs (Material)**, the **Stripe** docs, **Docusaurus**, dedicated
**REST API reference** systems (OpenAPI/Swagger, Redoc), and **programming-library
reference** systems (rustdoc, Doxygen, Sphinx/autodoc). Because it is built on
IsoNim, every site gets **static site generation (SSG)**, **server-side rendering
(SSR)** (including the nginx-native module), and **single-page-app (SPA)
hydration** modes for free from one component codebase.

## Why IsoNim

- Documentation UIs are **embeddable IsoNim components** (`proc renderX*[R,E](r: R; …): E`),
  so any doc-site chrome (sidebar, TOC, search, code block, API table) can be
  reused across projects — and a doc site can **embed custom IsoNim components**
  inline in its pages for live, interactive examples.
- One component codebase → SSG (build-time route crawl), SSR (C target / nginx),
  SPA (JS target + hydration). No second implementation.
- Fine-grained reactivity (Signals/Memos) powers instant client-side search,
  filtering, and interactive reference tables with no virtual DOM.

## Feature map (target)

**Authoring & content**
- Multi-page sites with nested sections, ordered navigation (a `SUMMARY`-style
  book structure like mdBook + MkDocs `nav`).
- Markdown content with frontmatter, admonitions/callouts, tabs, code blocks
  with syntax highlighting + copy button, line highlighting, and includes.
- **Embeddable live IsoNim components** inside pages (interactive examples,
  playgrounds) — the differentiator vs. static generators.
- Tutorials / guided multi-step content with prev/next and progress.
- Versioned docs and localization-ready structure.

**Reference documentation**
- **REST API reference** from OpenAPI: endpoints, params, schemas, try-it,
  three-column Stripe-style layout (prose + endpoint + sample code).
- **Programming-library reference**: modules, types, procs/functions, symbol
  index, cross-links — a rustdoc/Sphinx-class API browser (first target: Nim).

**Search (first-class)**
- Fast client-side full-text search (SSG-friendly prebuilt index) with instant
  results, keyboard navigation, highlighting, and section-scoped ranking.
- Optional server-side search for large corpora (SSR mode).

**Rendering & delivery**
- SSG (static HTML + hydration bundle), SSR (dynamic / nginx-native), SPA.
- Theming via Tailwind + IsoNim theme tokens; light/dark; responsive; a11y.

**Dogfood deliverable**
- A production-quality example site: **the end-user documentation of IsoNim and
  the IsoNim editor**, exercising every feature above.

## Development model

This project is developed by dogfooding **agent-harbor**'s long-horizon task
execution — `ah research` → `ah plan` → `ah implement` — under **extreme
test-driven development** (see `AGENTS.md`). Build/test uses the IsoNim dev shell
(`nix develop ../isonim` / direnv) and the three-tier IsoNim test pyramid
(ViewModel unit tests → MockRenderer component tests → SSR/E2E).

## Layout (target)

```
src/core/         # Layer 3 ViewModels (nav, TOC, search) — pure, headless-tested
src/components/   # Layer 2 embeddable doc components (generic over renderer)
src/theme/        # design tokens
pages/            # file-based routes
src/server/       # {.server.} content/search functions
src/ssr.nim       # route handler → HTML (SSR + SSG entry)
src/main_web.nim  # SPA shell
content/          # the docs themselves (markdown)
tests/            # tier 1/2/3 tests
```
