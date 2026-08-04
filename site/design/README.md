# Design-System Editor — visually editing the shared docs tokens

This directory is an **IsoNim editor instance** wired over the shared
**CodeTracer docs design system**
(`../../../codetracer-design-system/docs/codetracer-docs.tokens.json`). It lets
you edit design tokens — colors, typography, spacing & radii — in a live editor
and **persist** them back to that JSON file, which re-themes **all three docs
sites** (the CodeTracer book, the IsoNim user docs, and the isonim-docs
self-docs).

## Launch

From `isonim-docs/site/` (inside isonim-docs's own dev shell — activated by
direnv, or `nix develop` from the `isonim-docs` repo root; isonim is a declared
dependency of that shell, so there is no need to `nix develop ../../isonim`):

```bash
just design                   # build the editor JS + serve at http://127.0.0.1:8080
just design 8080 0.0.0.0      # reachable on the LAN
```

You can also launch it straight from a docs site you're working on — the book or
the IsoNim user docs both have a `just design` that delegates here:

```bash
# from codetracer/docs/book-isonim  OR  isonim/docs/users
just design
```

To see your edits land live, run a docs server in another shell:

```bash
# e.g. from codetracer/docs/book-isonim
just dev-docs                 # then edit + Save in the editor → the book hot-reloads
```

Build just the editor JS bundle (no server) with `just design-build`.

## How the save loop works

1. The editor runs in the browser (`design/main.nim`, compiled with `nim js`).
2. The three foundation views (**Colors / Typography / Spacing & Radii**) show
   only their own `--docs-*` tokens; the component previews render the real docs
   components themed by the current tokens.
3. Editing a token updates the preview instantly. Clicking **Save** issues a
   same-origin `POST /__isonim_save` to `design/serve.nim`, which runs a
   structure-preserving text patch on
   `codetracer-docs.tokens.json` (only the edited light/dark literal changes;
   siblings, order and formatting are preserved; malformed/unknown edits are
   rejected without corrupting the file).
4. A running `just dev-docs` server watches that file and hot-reloads the new
   `--docs-*` value into every open tab — **no rebuild**.

The editor is served over HTTP (not opened as a `file://`) specifically so the
save `fetch` reaches the server same-origin — that's why `just design` runs a
server instead of just opening `index.html`.

## Files

| File | What |
|------|------|
| `main.nim` | The `nim js` editor client (mounts the editor, wires the Save `fetch`) |
| `serve.nim` | The native host server: serves the editor + the `/__isonim_save` writeback route |
| `dtcg_workspace.nim` | Builds the editor workspace: foundation tokens, component stories, live-preview hook, web-only platform |
| `dtcg_writeback.nim` | The structure-preserving writeback to `codetracer-docs.tokens.json` |
| `config.nims` | Sibling-checkout paths the editor build needs |
| `index.html` | The editor host page |
| `tests/` | Headless view-model tests incl. the full click-to-save loop |

## Platforms

The docs target only the **web** platform, so the editor's backend/platform
toolbar shows web only (other IsoNim editor pilots that target native backends
show the full set). This is configured via the workspace's `allowedPlatforms` in
`dtcg_workspace.nim`.
