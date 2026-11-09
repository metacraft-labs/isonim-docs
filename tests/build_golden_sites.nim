## Builds the fixture sites whose output `just docs-build-golden-check`
## compares byte for byte with `tests/golden/` (the mini-site itself is
## `just docs-build`'s own output in `./public`).
##
## `tests/fixtures/content-site/` exercises what the content libraries
## decide about the output: heading anchors (punctuation, duplicates,
## non-ASCII, punctuation-only), relative `.md` links with fragments,
## images, symbol references, tables, lists, a code fence in every
## built-in language and its aliases plus an unknown one, every admonition
## kind, tabs, the content directives, front matter overrides, a draft that
## must not be built, and -- through a plugin -- a custom `:::rating`
## directive and a `preParse` transform. The mini-site has one heading, so
## on its own it would not notice, say, a change of the slug separator.
##
## Usage (from the repository root): build_golden_sites <out-dir>
## writes `<out-dir>/content-site/`.

when defined(js):
  {.error: "build_golden_sites.nim builds static sites; it is a C-target program".}

import std/[os, strutils]
import ../src/build_site
import ../src/core/plugin
import isonim/content/markdown

proc ratingPlugin(): Plugin =
  ## A `:::rating N` directive (N stars) and a `preParse` that expands a
  ## placeholder, so the plugin path of the parser shapes the output too.
  result.name = "golden-fixture"
  result.preParse = proc(body: string): string =
    body.replace("{{site}}", "Content Site")
  let rating = proc(args, body: string): seq[Block] =
    let n = try: args.strip().parseInt() except ValueError: 0
    @[Block(kind: bkParagraph,
      spans: @[InlineSpan(kind: ikText, text: "Rated " & "*".repeat(n))])]
  result.directives = @[DirectiveRegistration(name: "rating", render: rating)]

when isMainModule:
  if paramCount() != 1:
    quit("usage: build_golden_sites <out-dir>", 2)
  let outRoot = paramStr(1)
  let pages = buildSite(outDir = outRoot / "content-site",
                        contentDir = "tests/fixtures/content-site",
                        host = newPluginHost(ratingPlugin()))
  echo "golden: built ", pages, " pages into ", outRoot / "content-site"
