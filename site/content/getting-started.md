---
title: Getting Started
description: Scaffold an isonim-docs consumer, author content with frontmatter, and build or serve the site.
order: 1
---
# Getting Started

An isonim-docs *consumer* is a small Nim package that supplies its own
`content/`, its own `DocsConfig`, and a thin build entry that calls the
framework. isonim-docs itself ships no content -- it is content-agnostic --
so every site (including this one) is a consumer.

## Anatomy of a consumer

A minimal consumer mirrors the layout of this site:

```text
my-docs/
  config.nims          # sibling --path switches to reach the framework
  my_docs.nimble       # package metadata (requires ../path/to/isonim-docs)
  Justfile             # build / serve / test task entry points
  content/             # your Markdown pages
    index.md
    guide/intro.md
  assets/
    style.css          # the theme stylesheet (rules half)
  src/
    docs_config.nim    # your DocsConfig (branding)
    build.nim          # thin SSG entry that calls buildSite
```

## Authoring content

Every page is a Markdown file under `content/`. An optional leading
frontmatter block (delimited by `---`) sets per-page metadata. The
recognized keys are `title`, `description`, `section`, `order`, `slug`,
`draft`, and `aliases`; unknown keys are ignored, so plain Markdown with no
frontmatter at all also works.

The content loader is a pure function you can call directly. It parses the
frontmatter, derives the page's slug and section, and binds the route:

```nim runnable
import core/content

const raw = """---
title: Introduction
description: What this guide covers.
section: guide
order: 2
aliases: /old-intro, /legacy/intro
---
# Introduction

Body text starts after the first blank line."""

let entry = parseContentEntry(raw, "guide/intro.md")
# A frontmatter `title:` overrides the body's own leading heading.
doAssert entry.page.title == "Introduction"
doAssert entry.section == "guide"
doAssert entry.front.order == 2
# The route is derived from (section, slug): /<section>/<slug>.
doAssert entry.routePath == "/guide/intro"
# Old paths listed in `aliases:` stay resolvable after a rename.
doAssert entry.front.aliases == @["/old-intro", "/legacy/intro"]
```

Route derivation follows three rules: a root `index.md` (no section) is the
site root `/`; an `index.md` inside a section is that section's root; every
other page is `/<section>/<slug>` (or `/<slug>` with no section). The slug
defaults to the filename without its `.md` extension, and the section
defaults to the file's parent directory -- so a nested `guide/intro.md`
needs no explicit `section:` at all:

```nim runnable
import core/content

# section/slug are derived from the path when frontmatter omits them.
let e = parseContentEntry("# Signals\n\nReactive primitives.", "guide/signals.md")
doAssert e.slug == "signals"
doAssert e.section == "guide"
doAssert e.routePath == "/guide/signals"

# A root index.md maps to "/".
let home = parseContentEntry("# Home\n\nWelcome.", "index.md")
doAssert home.routePath == "/"

# A draft page is flagged so the loader can filter it out of a build.
let draft = parseContentEntry("---\ndraft: true\n---\n# WIP", "wip.md")
doAssert draft.front.draft
```

## Building and serving

A consumer's `src/build.nim` is a thin entry that hands its own `content/`
dir and `DocsConfig` to the framework's `buildSite`. Passing no explicit
manifest lets the framework auto-discover the routes from `content/`:

```nim runnable
import build_site
import core/config

proc buildMyDocs(): int =
  ## The exact shape of a consumer build entry: framework SSG, this
  ## site's content dir + config, framework-default (auto-discovered)
  ## routing. Returns the rendered page count.
  buildSite(contentDir = "content", cfg = docsConfig())

when isMainModule:
  echo "rendered ", buildMyDocs(), " pages"
```

With the IsoNim dev shell active, the task recipes are:

```sh
nix develop ../../isonim -c just build   # SSG -> ./public/
nix develop ../../isonim -c just serve   # SSR smoke render of "/"
nix develop ../../isonim -c just test    # build + examples-compile checks
```

The build writes clean-URL pages, a content-hashed stylesheet, a
`search-index.<hash>.json`, a `sitemap.xml`, and a `robots.txt` into
`public/`.
