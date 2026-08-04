# isonim-docs Self-Docs — working on the SSG framework's own documentation

This is the **documentation site for the [isonim-docs](../) framework itself**
(the Nim static-site generator that builds all the CodeTracer/IsoNim docs). It is
built with isonim-docs — i.e. the framework documents itself — and it also
**hosts the shared design-system editor** under [`design/`](design/README.md).

> Sibling sites, so you know which one you want:
> - **this** (`isonim-docs/site/`) documents the **isonim-docs SSG**;
> - [`isonim/docs/users/`](../../isonim/docs/users/README.md) documents the **IsoNim UI framework**;
> - [`codetracer/docs/book-isonim/`](../../codetracer/docs/book-isonim/README.md) is the **CodeTracer product** book.

## Prerequisites

Every task runs inside **isonim-docs's own Nix dev shell**. isonim is a
declared dependency of this repo's flake (`../flake.nix`), whose dev shell —
Nim, nimble, nodejs, yarn, esbuild, `just` — is reused verbatim, so you never
have to `nix develop ../../isonim`.

With **direnv** the shell activates automatically on `cd` (see `../.envrc`):

```bash
cd isonim-docs/site
just dev-docs
```

Without direnv, enter the repo's own dev shell once…

```bash
cd isonim-docs
nix develop        # this repo's flake; pulls isonim in as a dependency
cd site && just dev-docs
```

…or prefix a single recipe from the repo root:

```bash
nix develop -c just --working-directory site dev-docs
```

All commands below assume you are in `isonim-docs/site/` and in the dev shell.

## Live preview (hot reload)

```bash
just dev-docs                 # http://127.0.0.1:8000  (loopback only)
just dev-docs-lan             # same, reachable on your private LAN
just open-docs                # open the running server in a browser
```

## Build, one-shot preview, tests

```bash
just build         # static build into build/
just serve-docs    # one-shot SSR preview (no live reload)
just test          # site-builds, feature-coverage, doc-links, doc-examples, dev tests
```

## Design-system editor

This site hosts the live **design-system editor** — an IsoNim editor instance
over the shared `codetracer-docs.tokens.json`:

```bash
just design                   # builds + serves the editor at http://127.0.0.1:8080
just design 8080 0.0.0.0      # reachable on the LAN
just design-build             # build the editor JS bundle only (no server)
```

Editing a color/typography/spacing token and clicking **Save** POSTs to the
editor's server, which writes the shared
`codetracer-design-system/docs/codetracer-docs.tokens.json` via a
structure-preserving patch. Any running `just dev-docs` server (this site, the
IsoNim user docs, or the CodeTracer book) **hot-reloads the new value with no
rebuild** — one editor themes all three sites. See
[`design/README.md`](design/README.md) for details.

## Where things live

| Path | What |
|------|------|
| `content/*.md` | The framework's self-documentation (dev-server, deployment, CLI, components, …) |
| `src/{build,dev,ssr}.nim` | Build/serve entry points |
| `design/` | The design-system editor harness (see its README) |
| `tests/` | Site-build, feature-coverage, link/example, dev tests |

The framework source itself lives one level up in [`../src`](../src); this
`site/` directory is only the framework's *documentation* consumer.
