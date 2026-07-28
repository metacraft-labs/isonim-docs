## isonim-docs Layer 4 — the `isonim-docs` command-line toolchain
## (M11 deliverable 3).
##
## A single binary that drives the whole framework: `init` scaffolds a new
## site, `build` runs the SSG (`build_site.buildSite`), `dev` runs the
## live-reloading dev server (`dev_server`), and `serve` builds then serves
## the static output over HTTP. The CLI reinvents none of the engine — it
## is a thin, colored front-end over the existing `buildSite`/`DevServer`
## entry points.
##
## Architecture (mirrors `build_site`/`dev_server`): a pure, headless-
## testable CORE — flag/`.env` parsing, layered config resolution
## (defaults < `.env` < flags), usage text, and command dispatch that
## writes into an injected `CliIo` sink — plus a thin `when isMainModule`
## driver that binds the sink to the real stdout/stderr and process args.
## Everything the `test_cli.nim` suite asserts (build produces output, init
## scaffolds a site, an unknown subcommand errors with usage, flags
## override config) exercises that pure core over real fixture dirs, never
## a live server.

when defined(js):
  {.error: "cli.nim is a C-target entry point (it drives the SSG and the dev server); it has no meaning on the JS/SPA target".}

import std/[os, strutils, tables, terminal, asyncdispatch, asynchttpserver,
            osproc]
import ./core/config
import ./core/build_target
import ./build_site
import ./dev_server

# ---------------------------------------------------------------------------
# CliIo — the output sink. Tests capture into the buffers; the binary binds
# them to stdout/stderr. `useColor` gates ANSI so captured output (and any
# non-tty pipe) stays plain, per the colored-output deliverable.
# ---------------------------------------------------------------------------

type
  CliIo* = object
    useColor*: bool
    outLines*: seq[string]
    errLines*: seq[string]

proc initCliIo*(useColor = false): CliIo =
  CliIo(useColor: useColor, outLines: @[], errLines: @[])

const
  ansiReset = "\e[0m"
  ansiBold = "1"
  fgRed = "31"
  fgGreen = "32"
  fgYellow = "33"
  fgCyan = "36"

proc paint(io: CliIo; s, code: string): string =
  ## Wraps `s` in an ANSI SGR code when color is enabled, otherwise returns
  ## it untouched — so the exact same dispatch path is byte-comparable in
  ## tests (`useColor = false`) and pretty on a real terminal.
  if io.useColor and code.len > 0: "\e[" & code & "m" & s & ansiReset else: s

proc emitOut(io: var CliIo; line: string) =
  io.outLines.add line

proc emitErr(io: var CliIo; line: string) =
  io.errLines.add line

# ---------------------------------------------------------------------------
# Pure parsing + config resolution.
# ---------------------------------------------------------------------------

type
  ParsedArgs* = object
    subcommand*: string          ## "" when none was given
    positionals*: seq[string]    ## non-flag args after the subcommand
    flags*: Table[string, string] ## `--k=v` / `--k v` / bare `--k` (-> "true")

  ResolvedConfig* = object
    ## The fully-layered runtime config a subcommand acts on.
    cfg*: DocsConfig
    contentDir*: string
    outDir*: string
    publicDir*: string
    port*: int
    target*: BuildTarget          ## `build --target=` (default: static SSG)
    targetRaw*: string            ## the raw `--target` value, for a precise error
    nginxOut*: string             ## `--nginx-out=` artifact path for `--target=nginx`

const booleanFlags* = ["no-color", "help", "h"]
  ## Flags that never take a value, so a following positional is NEVER
  ## swallowed as their argument (`isonim-docs build --no-color extra`
  ## keeps `extra` a positional). Every other `--key` uses `--key=value`
  ## or the `--key value` form.

proc parseArgs*(args: seq[string]): ParsedArgs =
  ## Splits raw argv (already stripped of the program name) into a
  ## subcommand, positionals, and a flag table. Accepts `--key=value`,
  ## `--key value`, and bare boolean `--key` (value "true"; see
  ## `booleanFlags`). The first non-flag token is the subcommand; the rest
  ## are positionals. Pure.
  result.flags = initTable[string, string]()
  var i = 0
  while i < args.len:
    let a = args[i]
    if a.startsWith("--"):
      let body = a[2 .. ^1]
      let eq = body.find('=')
      if eq >= 0:
        result.flags[body[0 ..< eq]] = body[eq + 1 .. ^1]
      elif body notin booleanFlags and i + 1 < args.len and
           not args[i + 1].startsWith("--"):
        result.flags[body] = args[i + 1]
        inc i
      else:
        result.flags[body] = "true"
    elif result.subcommand.len == 0:
      result.subcommand = a
    else:
      result.positionals.add a
    inc i

proc parseEnvFile*(content: string): Table[string, string] =
  ## Parses a `.env` file body into a key->value table. Blank lines and
  ## `#` comment lines are ignored; an optional leading `export ` and
  ## surrounding single/double quotes on the value are stripped. Pure, so
  ## the resolution precedence is testable without touching the disk.
  result = initTable[string, string]()
  for rawLine in content.splitLines:
    var line = rawLine.strip
    if line.len == 0 or line.startsWith("#"):
      continue
    if line.startsWith("export "):
      line = line[7 .. ^1].strip
    let eq = line.find('=')
    if eq <= 0:
      continue
    let key = line[0 ..< eq].strip
    var val = line[eq + 1 .. ^1].strip
    if val.len >= 2 and ((val[0] == '"' and val[^1] == '"') or
                         (val[0] == '\'' and val[^1] == '\'')):
      val = val[1 ..< val.len - 1]
    result[key] = val

proc firstOf(a, b: Table[string, string]; keys: varargs[string]): string =
  ## Returns the highest-precedence present value for any of `keys`,
  ## checking `a` (flags) before `b` (env). "" when neither has it.
  for k in keys:
    if a.hasKey(k): return a[k]
  for k in keys:
    if b.hasKey(k): return b[k]
  ""

proc resolveConfig*(base: DocsConfig; env, flags: Table[string, string]):
    ResolvedConfig =
  ## Layers config sources by ascending precedence: the framework/consumer
  ## `base` `DocsConfig`, then `.env` values, then command-line flags win.
  ## Flag names are kebab-case (`--site-title`); the matching `.env` keys
  ## are SCREAMING_SNAKE (`SITE_TITLE`). A field the user overrode nowhere
  ## keeps its `base`/built-in default. Pure — the whole precedence contract
  ## is unit-testable off in-memory tables.
  result.cfg = base
  result.contentDir = "content"
  result.outDir = "public"
  result.publicDir = ""
  result.port = 8000
  result.target = btStatic
  result.nginxOut = defaultNginxArtifact

  template ov(field: untyped; envKeys: varargs[string]) =
    let v = firstOf(flags, env, envKeys)
    if v.len > 0: field = v

  ov(result.cfg.siteTitle, "site-title", "SITE_TITLE")
  ov(result.cfg.siteDescription, "site-description", "SITE_DESCRIPTION")
  ov(result.cfg.defaultRoute, "default-route", "DEFAULT_ROUTE")
  ov(result.cfg.stylesheetHref, "stylesheet-href", "STYLESHEET_HREF")
  ov(result.cfg.baseUrl, "base-url", "BASE_URL")
  ov(result.contentDir, "content-dir", "CONTENT_DIR")
  ov(result.outDir, "out-dir", "OUT_DIR")
  ov(result.publicDir, "public-dir", "PUBLIC_DIR")

  let portStr = firstOf(flags, env, "port", "PORT")
  if portStr.len > 0:
    try: result.port = parseInt(portStr)
    except ValueError: discard

  result.targetRaw = firstOf(flags, env, "target", "TARGET")
  # An unknown target is a config error `cmdBuild` surfaces at dispatch;
  # keep resolution total by falling back to the default here.
  try: result.target = parseBuildTarget(result.targetRaw)
  except ValueError: result.target = btStatic

  ov(result.nginxOut, "nginx-out", "NGINX_OUT")

proc loadEnv(dir: string; flags: Table[string, string]): Table[string, string] =
  ## Reads the `.env` file for a run: `--env-file=PATH` when given, else a
  ## `.env` in `dir`. A missing file is not an error (returns an empty
  ## table) — `.env` is purely an override source.
  let path =
    if flags.hasKey("env-file"): flags["env-file"]
    else: dir / ".env"
  if fileExists(path): parseEnvFile(readFile(path))
  else: initTable[string, string]()

# ---------------------------------------------------------------------------
# Usage / help.
# ---------------------------------------------------------------------------

const usageBody = """isonim-docs — the isonim documentation framework toolchain

Usage:
  isonim-docs <command> [options]

Commands:
  init [dir]     Scaffold a new documentation site (content + .env config)
  build          Statically generate the site (SSG) into the output dir
  dev            Run the live-reloading development server
  serve          Build, then serve the static output over HTTP

Options (override .env, which overrides built-in defaults):
  --content-dir=DIR      Content source dir            (default: content)
  --out-dir=DIR          Build output dir              (default: public)
  --public-dir=DIR       Verbatim passthrough dir      (default: none)
  --target=NAME          Build target: static | nginx  (default: static)
  --nginx-out=PATH       nginx module .so path         (default: ngx_isonim_docs.so)
  --port=N               Dev/serve HTTP port           (default: 8000)
  --site-title=STR       Site title
  --site-description=STR Site description
  --base-url=URL         Absolute base URL for SEO/sitemap
  --env-file=PATH        Explicit .env path            (default: ./.env)
  --no-color             Disable colored output"""

proc usageText*(): string = usageBody

# ---------------------------------------------------------------------------
# Subcommands.
# ---------------------------------------------------------------------------

proc scaffoldSite*(dir: string): seq[string] =
  ## Writes a minimal starter site under `dir` and returns the list of
  ## created files (relative to `dir`). Idempotent per-file via plain
  ## overwrite; creates intermediate dirs. Kept separate from `cmdInit` so
  ## the scaffold is assertable without going through argv/IO.
  let files = {
    "content/index.md": """---
title: Home
nav_order: 0
---
# Welcome

This site was scaffolded by `isonim-docs init`. Edit the markdown in
`content/` and run `isonim-docs dev` to preview with live reload.
""",
    "content/getting-started.md": """---
title: Getting Started
nav_order: 1
---
# Getting Started

Add pages as markdown files under `content/`. Nested directories become
nested navigation sections automatically.
""",
    ".env": """# isonim-docs site config — flags override these, these override defaults.
SITE_TITLE=My Docs
SITE_DESCRIPTION=Documentation built with isonim-docs.
CONTENT_DIR=content
OUT_DIR=public
PORT=8000
""",
    # A minimal starter stylesheet so a freshly-scaffolded site `build`s
    # (and thus `dev`/`serve`s) immediately: `buildSite` requires a
    # non-empty `assets/style.css` so `stylesheetHref` never dangles.
    # Replace this with a real Tailwind/token build for production.
    "assets/style.css": """:root { color-scheme: light dark; }
body { font-family: system-ui, sans-serif; margin: 0; line-height: 1.6; }
main { max-width: 48rem; margin: 0 auto; padding: 2rem 1rem; }
""",
  }.toTable
  for rel, body in files:
    let full = dir / rel
    createDir(full.parentDir)
    writeFile(full, body)
    result.add rel

proc cmdInit(io: var CliIo; parsed: ParsedArgs): int =
  let dir = if parsed.positionals.len > 0: parsed.positionals[0] else: "."
  createDir(dir)
  let created = scaffoldSite(dir)
  io.emitOut io.paint("Scaffolded a new isonim-docs site in " & dir, fgGreen)
  for rel in created:
    io.emitOut "  " & io.paint("create", fgCyan) & "  " & (dir / rel)
  io.emitOut "Next: cd " & dir & " && isonim-docs dev"
  0

proc cmdBuildNginx(io: var CliIo; rc: ResolvedConfig): int =
  ## `build --target=nginx`: compile the nginx-link-function SSR module into
  ## a shared object via the shared `nginxBuildRecipe` (the exact same recipe
  ## `test_nginx_target.nim` compiles from). Runs the real Nim→C→`.so` build
  ## through `nim` on PATH (the dev shell provides it) and reports the
  ## produced artifact, or the compiler's own error on failure.
  let entry = defaultNginxEntry
  if not fileExists(entry):
    io.emitErr io.paint("error: nginx target entry not found: " & entry, fgRed)
    return 1
  let recipe = nginxBuildRecipe(entry = entry, outSo = rc.nginxOut)
  io.emitOut io.paint("Building nginx SSR module: nim " & recipe.join(" "), fgCyan)
  let (output, code) = execCmdEx("nim " & quoteShellCommand(recipe))
  if code != 0 or not fileExists(rc.nginxOut):
    io.emitErr io.paint("error: nginx module build failed", fgRed)
    for line in output.strip.splitLines:
      if line.len > 0: io.emitErr "  " & line
    return 1
  io.emitOut io.paint("Built nginx SSR module -> " & rc.nginxOut, fgGreen)
  io.emitOut "  load it in nginx.conf via nginx-link-function " &
    "(ngx_link_func_call \"isonim_docs_ssr\";)"
  0

proc cmdBuild(io: var CliIo; rc: ResolvedConfig): int =
  ## Dispatches on the resolved build target. `static` (default) runs the
  ## SSG; `nginx` compiles the SSR module. An unparseable `--target` is a
  ## hard usage error here (resolution kept itself total by defaulting).
  var target: BuildTarget
  try:
    target = parseBuildTarget(rc.targetRaw)
  except ValueError as e:
    io.emitErr io.paint("error: " & e.msg, fgRed)
    return 1
  case target
  of btNginx:
    return cmdBuildNginx(io, rc)
  of btStatic:
    if not dirExists(rc.contentDir):
      io.emitErr io.paint("error: content dir not found: " & rc.contentDir, fgRed)
      return 1
    let n = buildSite(outDir = rc.outDir, contentDir = rc.contentDir,
                      cfg = rc.cfg, publicDir = rc.publicDir)
    io.emitOut io.paint("Built " & $n & " page(s) into " & rc.outDir, fgGreen)
    0

proc cmdDev(io: var CliIo; rc: ResolvedConfig): int =
  ## Live-reloading dev server. Startup is reported through `io`; the
  ## blocking `serve` loop only runs from the real binary (the return path
  ## below is what tests exercise when they pass `runServer = false`).
  if not dirExists(rc.contentDir):
    io.emitErr io.paint("error: content dir not found: " & rc.contentDir, fgRed)
    return 1
  io.emitOut io.paint("isonim-docs dev server", ansiBold) &
    " on " & io.paint("http://localhost:" & $rc.port, fgCyan) &
    " (watching " & rc.contentDir & ")"
  0

proc cmdServe(io: var CliIo; rc: ResolvedConfig): int =
  ## Production preview: build once, then report the serve endpoint. The
  ## actual static serving is driven by the binary; the build here is real
  ## so `serve` never serves stale/missing output.
  let bc = cmdBuild(io, rc)
  if bc != 0: return bc
  io.emitOut io.paint("Serving " & rc.outDir, ansiBold) &
    " on " & io.paint("http://localhost:" & $rc.port, fgCyan)
  0

# ---------------------------------------------------------------------------
# Dispatch — the pure core the whole test suite drives.
# ---------------------------------------------------------------------------

proc runCli*(io: var CliIo; args: seq[string];
             baseCfg: DocsConfig = docsConfig()): int =
  ## Parses `args`, resolves config, and dispatches to the subcommand,
  ## writing all human output into `io`. Returns the process exit code.
  ## Does NOT start any long-running server — `dev`/`serve` report their
  ## startup and return so the core stays synchronously testable; the
  ## binary calls `serve`/`dev_server.serve` after a 0 return.
  let parsed = parseArgs(args)
  if parsed.flags.getOrDefault("no-color", "") == "true":
    io.useColor = false
  if parsed.flags.hasKey("help") or parsed.flags.hasKey("h") or
     parsed.subcommand in ["help", ""]:
    io.emitOut usageText()
    # A bare invocation with no subcommand is a usage error (exit 1); an
    # explicit `help`/`--help` is a success.
    return if parsed.subcommand == "" and not parsed.flags.hasKey("help") and
              not parsed.flags.hasKey("h"): 1 else: 0

  let baseDir =
    if parsed.subcommand == "init" and parsed.positionals.len > 0:
      parsed.positionals[0]
    else: "."
  let env = loadEnv(baseDir, parsed.flags)
  let rc = resolveConfig(baseCfg, env, parsed.flags)

  case parsed.subcommand
  of "init": cmdInit(io, parsed)
  of "build": cmdBuild(io, rc)
  of "dev": cmdDev(io, rc)
  of "serve": cmdServe(io, rc)
  else:
    io.emitErr io.paint("error: unknown command '" & parsed.subcommand & "'",
                        fgRed)
    io.emitErr usageText()
    2

# ---------------------------------------------------------------------------
# Static file server — the `serve` subcommand's runtime (production preview
# of the already-built `outDir`, no live-reload injection or watcher, unlike
# `dev`). Serves clean-URL routes the way `build_site.outputPathFor` emits
# them: "/" -> index.html, "/guide/x" -> guide/x/index.html.
# ---------------------------------------------------------------------------

proc staticPathFor(outDir, urlPath: string): string =
  let trimmed = urlPath.strip(chars = {'/'})
  if trimmed.len == 0: outDir / "index.html"
  elif trimmed.contains('.'): outDir / trimmed          # a real asset file
  else: outDir / trimmed / "index.html"

proc serveStatic(outDir: string; port: int) {.async.} =
  ## Serves the static `outDir` over HTTP until cancelled. Kept tiny and
  ## dependency-free (no file watcher, no WS) — that is exactly the
  ## dev/serve distinction the CLI draws.
  var http = newAsyncHttpServer()
  http.listen(Port(port))
  while true:
    if http.shouldAcceptRequest():
      await http.acceptRequest(proc(req: Request) {.async, gcsafe.} =
        let f = staticPathFor(outDir, req.url.path)
        if fileExists(f):
          let ct = if f.endsWith(".css"): "text/css"
                   elif f.endsWith(".js"): "application/javascript"
                   elif f.endsWith(".json"): "application/json"
                   else: "text/html; charset=utf-8"
          await req.respond(Http200, readFile(f),
            newHttpHeaders({"Content-Type": ct}))
        else:
          await req.respond(Http404, "404 Not Found",
            newHttpHeaders({"Content-Type": "text/html; charset=utf-8"})))
    else:
      await sleepAsync(20)

# ---------------------------------------------------------------------------
# Binary entry — binds the sink to real stdout/stderr and, for `dev`/`serve`,
# hands off to the blocking async server after the synchronous phase returns.
# ---------------------------------------------------------------------------

when isMainModule:
  let raw = commandLineParams()
  var io = initCliIo(useColor = isatty(stdout))
  let code = runCli(io, raw)
  for line in io.outLines: stdout.writeLine line
  for line in io.errLines: stderr.writeLine line
  flushFile stdout
  flushFile stderr

  if code == 0:
    let parsed = parseArgs(raw)
    let env = loadEnv(".", parsed.flags)
    let rc = resolveConfig(docsConfig(), env, parsed.flags)
    case parsed.subcommand
    of "dev":
      let ds = newDevServer(rc.contentDir, rc.cfg)
      waitFor serve(ds, rc.port)
    of "serve":
      waitFor serveStatic(rc.outDir, rc.port)
    else: discard
  quit(code)
