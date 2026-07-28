## M11 deliverable 3 (CLI toolchain) suite — C-target only.
##
## `cli.nim` is a C-target entry point (it drives the SSG and the dev
## server), so this suite exercises the pure, headless-testable CORE of the
## CLI over REAL fixture dirs: argument/`.env` parsing, layered config
## resolution (defaults < `.env` < flags), usage text, and the `init` /
## `build` / unknown-command dispatch paths — every behaviour the milestone
## declares:
##
##   * `build` produces output (a real `buildSite` run emits index.html);
##   * `init` scaffolds a site (content + a `.env` config land on disk);
##   * an unknown subcommand errors (non-zero exit) WITH the usage text;
##   * flags override config (unit precedence + an end-to-end build whose
##     emitted HTML carries the flag-supplied site title, beating `.env`).
##
## The long-running `dev`/`serve` loops are the binary's job (`when
## isMainModule`); the core returns after reporting startup so the whole
## suite stays synchronous.

when defined(js):
  {.error: "test_cli is a C-target-only suite (cli.nim is a server/SSG entry point)".}

import std/[unittest, os, strutils, tables]
import ../../src/cli
import ../../src/core/config
import ./helpers/fixture_dir

proc writeMiniSite(dir: string) =
  writeFixtureFile(dir, "index.md", "# Fixture Home\n\nHello from the CLI build.")
  writeFixtureFile(dir, "guide/alpha.md",
    "---\ntitle: Alpha\nnav_order: 1\n---\n# Alpha\n\nAlpha body.")

suite "docs CLI toolchain -- pure core over real fixtures (M11 deliverable 3, C-target)":

  test "parseArgs: subcommand, --k=v, --k v, and bare boolean flags":
    let p = parseArgs(@["build", "--content-dir=content", "--port", "9",
                        "--no-color", "extra"])
    check p.subcommand == "build"
    check p.flags["content-dir"] == "content"
    check p.flags["port"] == "9"
    check p.flags["no-color"] == "true"
    check p.positionals == @["extra"]

  test "parseArgs: no subcommand yields empty subcommand":
    check parseArgs(@[]).subcommand == ""
    check parseArgs(@["--help"]).subcommand == ""

  test "parseEnvFile: comments, blanks, export, and quoted values":
    let env = parseEnvFile("""
# a comment
export SITE_TITLE="Quoted Title"
PORT=1234

BASE_URL='https://x.example'
bad line without eq
""")
    check env["SITE_TITLE"] == "Quoted Title"
    check env["PORT"] == "1234"
    check env["BASE_URL"] == "https://x.example"
    check not env.hasKey("bad line without eq")

  test "resolveConfig: precedence is defaults < .env < flags":
    var base = docsConfig()
    base.siteTitle = "Default Title"
    let env = {"SITE_TITLE": "Env Title", "PORT": "7000",
               "CONTENT_DIR": "envcontent"}.toTable
    let flags = {"site-title": "Flag Title", "port": "9999"}.toTable

    # No override anywhere -> base default retained.
    let none = resolveConfig(base, initTable[string, string](),
                             initTable[string, string]())
    check none.cfg.siteTitle == "Default Title"
    check none.port == 8000

    # Env overrides base; flag overrides env.
    let r = resolveConfig(base, env, flags)
    check r.cfg.siteTitle == "Flag Title"    # flag beats env
    check r.port == 9999                      # flag beats env
    check r.contentDir == "envcontent"        # env beats default (no flag)

  test "usageText lists every subcommand":
    let u = usageText()
    for cmd in ["init", "build", "dev", "serve"]:
      check u.contains(cmd)

  test "init scaffolds a site: content pages + a .env config land on disk":
    withFixtureDir:
      let siteDir = fixtureDir / "newsite"
      var io = initCliIo()
      let code = runCli(io, @["init", siteDir])
      check code == 0
      check fileExists(siteDir / "content" / "index.md")
      check fileExists(siteDir / "content" / "getting-started.md")
      check fileExists(siteDir / ".env")
      check fileExists(siteDir / "assets" / "style.css")   # buildable out of the box
      check readFile(siteDir / ".env").contains("SITE_TITLE")
      # Reports what it created.
      check io.outLines.join("\n").contains("content/index.md")

  test "a freshly-scaffolded site builds from its own root (self-sufficient)":
    withFixtureDir:
      let siteDir = fixtureDir / "site"
      var io1 = initCliIo()
      check runCli(io1, @["init", siteDir]) == 0
      # Build from WITHIN the scaffolded dir: `buildSite`'s cwd-relative
      # `assets/` must resolve to the scaffolded stylesheet, proving init
      # produced an immediately-buildable site (no "stylesheetHref dangles").
      let prev = getCurrentDir()
      setCurrentDir(siteDir)
      try:
        var io2 = initCliIo()
        check runCli(io2, @["build"]) == 0
        check fileExists(siteDir / "public" / "index.html")
      finally:
        setCurrentDir(prev)

  test "build produces output: a real buildSite run emits index.html":
    withFixtureDir:
      let contentDir = fixtureDir / "content"
      let outDir = fixtureDir / "out"
      writeMiniSite(contentDir)
      var io = initCliIo()
      let code = runCli(io, @["build",
                              "--content-dir=" & contentDir,
                              "--out-dir=" & outDir])
      check code == 0
      check fileExists(outDir / "index.html")
      check fileExists(outDir / "guide" / "alpha" / "index.html")
      check io.outLines.join("\n").contains("Built")

  test "build errors cleanly (exit 1) when the content dir is missing":
    withFixtureDir:
      var io = initCliIo()
      let code = runCli(io, @["build",
                              "--content-dir=" & (fixtureDir / "does-not-exist"),
                              "--out-dir=" & (fixtureDir / "out")])
      check code == 1
      check io.errLines.join("\n").contains("content dir not found")

  test "unknown subcommand errors (non-zero) WITH the usage text":
    var io = initCliIo()
    let code = runCli(io, @["frobnicate"])
    check code != 0
    let err = io.errLines.join("\n")
    check err.contains("unknown command 'frobnicate'")
    check err.contains("Usage:")          # the usage text is included
    check err.contains("build")

  test "bare invocation prints usage and exits non-zero":
    var io = initCliIo()
    let code = runCli(io, @[])
    check code != 0
    check io.outLines.join("\n").contains("Usage:")

  test "explicit help exits zero with usage":
    var io = initCliIo()
    check runCli(io, @["help"]) == 0
    check io.outLines.join("\n").contains("Usage:")

  test "flags override config END-TO-END: emitted HTML carries the flag title":
    withFixtureDir:
      let contentDir = fixtureDir / "content"
      let outDir = fixtureDir / "out"
      writeMiniSite(contentDir)
      # A .env in the content-dir's parent that the flag must beat.
      writeFixtureFile(fixtureDir, ".env", "SITE_TITLE=EnvOnlyTitle\n")
      var io = initCliIo()
      let code = runCli(io, @["build",
                              "--content-dir=" & contentDir,
                              "--out-dir=" & outDir,
                              "--site-title=ZZUniqueFlagTitle"])
      check code == 0
      let html = readFile(outDir / "index.html")
      check html.contains("ZZUniqueFlagTitle")     # flag-supplied title rendered
      check not html.contains("EnvOnlyTitle")

  test "--no-color keeps output plain (no ANSI escapes)":
    withFixtureDir:
      let siteDir = fixtureDir / "s"
      var io = initCliIo(useColor = true)
      discard runCli(io, @["init", siteDir, "--no-color"])
      check not io.outLines.join("\n").contains("\e[")

  test "color is applied when enabled (ANSI escapes present)":
    withFixtureDir:
      let siteDir = fixtureDir / "s"
      var io = initCliIo(useColor = true)
      discard runCli(io, @["init", siteDir])
      check io.outLines.join("\n").contains("\e[")
