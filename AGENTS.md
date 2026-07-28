# isonim-docs — agent build & test guide

You are building `isonim-docs`, an IsoNim-based documentation-site framework.
See `README.md` for the vision and feature map. Work **test-first** (extreme TDD):
for each deliverable, write the failing test, then the code that makes it pass.

## Environment

- Toolchain comes from the **IsoNim dev shell** (Nim ≥ 2.0, nimble, nodejs, yarn,
  esbuild, tailwind). Enter it with `direnv allow` (uses `.envrc` → `use flake
  ../isonim`) or run commands via `nix develop ../isonim -c <cmd>`.
- The `isonim` framework source is the sibling checkout `../isonim`
  (`../isonim/src`). Shared deps: `../nim-everywhere/src`, `../nim-faststreams`.
  Study these templates before writing code:
  - Component/DSL model: `../isonim/src/isonim/dsl/ui.nim`,
    `../isonim/examples/wanderlust/components/views.nim`
  - Routing / SSR / server functions: `../isonim/src/isonim/routing/`,
    `../isonim/src/isonim/ssr/`, `../isonim/src/isonim/server/`
  - Docs-site precedent (closest template): `../isonim-website/` (SSR + hydration
    site fully built in IsoNim).
  - Styling: `../isonim/src/isonim/theming/theme.nim`, Tailwind via
    `../isonim/tools/tailwind-extract.mjs`.
  - Embedding / editor stories contract: `../isonim/src/isonim/editor.nim`,
    `../isonim/examples/wanderlust/stories.nim`.

## Architecture rules (from IsoNim cross-platform architecture)

- **Layer 3 ViewModels** (`src/core/`): pure reactive state (`Signal`/`Memo`),
  zero platform/CSS imports — fully headless-testable (Tier 1).
- **Layer 2 views** (`src/components/`): generic `proc renderX*[R,E](r: R; …): E`
  using the `ui(r)` DSL, domain vocabulary, embeddable/reusable.
- **Layer 1 leaf** components: one impl per target where needed.
- **Layer 4 shells**: `src/main_web.nim` (SPA), `src/ssr.nim` (SSR/SSG entry).

## Testing (three-tier pyramid — the gate)

- **Tier 1** — ViewModel unit tests, no renderer, `std/unittest`, use
  `TestClock`/`withFakeTime` for determinism (`../isonim/src/isonim/core/clock.nim`).
- **Tier 2** — component tests via **MockRenderer**
  (`../isonim/src/isonim/testing/mock_dom.nim`, `fireEvent`).
- **Tier 3** — SSR/E2E: render routes with `renderToString`/`renderRoute` and
  assert HTML; browser E2E where warranted.
- Run on **both** backends: `nim c -r tests/…` and `nim js -r tests/…`. Provide a
  `Justfile` with `test-c` / `test-js` / `test` (mirror `../isonim/Justfile`).

## M0 (first milestone) — establish a green build

Reproducible build + test framework BEFORE feature work:
- `isonim_docs.nimble` (requires `isonim`, `nim_everywhere`, `faststreams`,
  `chronicles`), `config.nims` path-switching to `../isonim/src` and
  `../nim-everywhere/src` (mirror `../isonim/demos/config.nims`), a `Justfile`,
  and one trivial passing ViewModel test proving `nim c -r` + `nim js -r` work.

Do not weaken, delete, or trivially-pass tests to make a milestone green.
