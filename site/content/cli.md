---
title: CLI Toolchain
description: The isonim-docs command-line binary with init / dev / build / serve subcommands, colored output, and layered flag / .env configuration overrides.
order: 13
---
# CLI Toolchain

The `isonim-docs` binary is a thin, colored front-end over the framework's
own entry points -- it reinvents no engine. `build` runs the SSG, `dev` runs
the [live-reloading dev server](./dev-server.md), `serve` builds then serves
the static output, and `init` scaffolds a new site.

## Commands

```sh
isonim-docs init [dir]   # scaffold a new site (content + .env + starter CSS)
isonim-docs build        # statically generate the site (SSG) into the out dir
isonim-docs dev          # run the live-reloading development server
isonim-docs serve        # build, then serve the static output over HTTP
```

The whole dispatch core is pure and headless-testable: it writes human
output into an injected sink rather than straight to stdout, so a test drives
the exact same path the binary does. A bare invocation or `help` prints
usage; an unknown subcommand errors with usage and a non-zero exit:

```nim runnable
import cli

# `help` succeeds and prints usage.
var io = initCliIo(useColor = false)
doAssert runCli(io, @["help"]) == 0
doAssert io.outLines.len > 0

# An unknown subcommand is a usage error (non-zero exit).
var io2 = initCliIo(useColor = false)
doAssert runCli(io2, @["frobnicate"]) != 0
```

Colored output is gated by a `useColor` flag, so captured output (and any
non-tty pipe) stays plain while a real terminal gets ANSI color; `--no-color`
forces it off.

## Configuration precedence

Config is layered by ascending precedence: the base `DocsConfig`, then a
`.env` file, then command-line flags win. Flag names are kebab-case
(`--site-title`); the matching `.env` keys are SCREAMING_SNAKE
(`SITE_TITLE`). The argument parser and the `.env` parser are pure, so the
whole precedence contract is unit-testable off in-memory data:

```nim runnable
import std/tables
import cli

let parsed = parseArgs(@["build", "--out-dir=dist", "--no-color"])
doAssert parsed.subcommand == "build"
doAssert parsed.flags["out-dir"] == "dist"

let env = parseEnvFile("SITE_TITLE=From Env\n# a comment\nPORT=9000\n")
doAssert env["SITE_TITLE"] == "From Env"
doAssert env["PORT"] == "9000"
```

`build --target=nginx` switches the build from the static SSG to the
[nginx SSR module](./deployment.md); everything else is the same layered
config.
