## Live design-system editor SAVE server (M4b).
##
## `just design` builds the JS editor bundle and runs THIS native server, which
## turns the previously `file://`-only harness into a same-origin HTTP host so
## the editor's foundation "Save" can actually persist. It reuses the framework
## `dev_server` wholesale -- only its injectable `render` (serve the editor
## page), its `assetsDirs` (serve the JS bundle + the docs stylesheet under
## `/assets/`), and the M4b opt-in `saveHandler` (the POST route) are supplied
## here. Nothing about the three docs consumers' `dev_server` usage changes.
##
## The loop it closes:
##   1. The browser editor POSTs `{ "var", "side", "value" }` to
##      `/__isonim_save` (same-origin `fetch`, wired in `design/main.nim`).
##   2. This server's `saveHandler` runs the M4 structure-preserving writeback
##      (`applyDocsTokenEdit`) on the REAL shared docs token file.
##   3. A `just dev-docs` server (which WATCHES that file) hot-reloads the live
##      docs with the new `--docs-*` value -- no rebuild.
##
## This server deliberately does NOT watch the token file itself: reloading the
## editor page on every save would discard the editor's in-session state, and
## the editor already re-themes its own preview live (M3). Persisting the docs
## sites is the dev-docs server's job.

when defined(js):
  {.error: "design/serve.nim is the native save server; compile with `nim c`".}

import std/[os, json, strutils, asyncdispatch]
import dev_server
import core/config
import ../src/theme_tokens          # docsDesignSystemPath
import ./dtcg_workspace             # docsSaveEndpoint + (re-exported) applyDocsTokenEdit

const
  designDir = currentSourcePath().parentDir()   ## .../isonim-docs/site/design
  siteDir = designDir.parentDir()                ## .../isonim-docs/site

proc editorPageHtml(): string =
  ## The editor host page. Read from `design/index.html` (whose `<script src>`
  ## already points at `/assets/design_editor.js`, i.e. the built bundle served
  ## from `build/` under `/assets/`). The live-reload client is spliced in by
  ## `dev_server`'s `injectLiveReload` around this.
  let indexPath = designDir / "index.html"
  if fileExists(indexPath): readFile(indexPath)
  else:
    "<!doctype html><html><head><meta charset=\"utf-8\">" &
    "<title>Metacraft Docs Design System — Live Editor</title></head>" &
    "<body><script src=\"/assets/design_editor.js\"></script></body></html>"

proc renderEditor(path: string): tuple[status: int; html: string] =
  ## Serve the single-page editor for any non-asset, non-save path. `dev_server`
  ## already dispatches `/assets/*` and the `/__isonim_save` POST before this.
  (200, editorPageHtml())

proc docsSaveHandler(body: string): SaveResult =
  ## Decode `{ "var", "side", "value" }` and run the M4 docs-token writeback on
  ## the shared file. A malformed payload or a rejected edit (unknown var, bad
  ## side, token-bound side, corrupting value) returns a 4xx and, thanks to the
  ## writeback's own guards, leaves the file byte-identical.
  var parsed: JsonNode
  try:
    parsed = parseJson(body)
  except CatchableError as e:
    return SaveResult(status: 400, contentType: "application/json; charset=utf-8",
      body: """{"ok":false,"error":"invalid JSON: """ & e.msg.escapeJsonUnquoted & """"}""")
  if parsed.kind != JObject or not parsed.hasKey("var"):
    return SaveResult(status: 400, contentType: "application/json; charset=utf-8",
      body: """{"ok":false,"error":"missing 'var'"}""")
  let varName = parsed["var"].getStr
  let side = (if parsed.hasKey("side"): parsed["side"].getStr else: "light")
  let value = (if parsed.hasKey("value"): parsed["value"].getStr else: "")
  try:
    let res = applyDocsTokenEdit(docsDesignSystemPath, varName, value, side)
    SaveResult(status: 200, contentType: "application/json; charset=utf-8",
      body: """{"ok":true,"var":""" & escapeJson(varName) &
        ""","side":""" & escapeJson(side) &
        ""","value":""" & escapeJson(value) &
        ""","written":""" & (if res.written: "true" else: "false") & "}")
  except DtcgWriteError as e:
    SaveResult(status: 422, contentType: "application/json; charset=utf-8",
      body: """{"ok":false,"error":""" & escapeJson(e.msg) & "}")

proc newDesignSaveServer*(): DevServer =
  ## The `just design` editor + save server: serves the editor page, the built
  ## JS bundle and docs stylesheet under `/assets/`, and the M4b save route.
  ## Exposed so a test can drive the exact wiring without binding a socket.
  newDevServer(
    contentDir = "",                      # no content routes; render is overridden
    cfg = docsConfig(),
    render = renderEditor,
    assetsDirs = @[designDir / "build", siteDir / "assets", siteDir / "static"],
    saveHandler = docsSaveHandler,
    savePath = docsSaveEndpoint)

when isMainModule:
  let port = if paramCount() >= 1: parseInt(paramStr(1)) else: 8080
  let host =
    if paramCount() >= 2: paramStr(2)
    elif existsEnv("AH_DEV_HOST"): getEnv("AH_DEV_HOST")
    else: "127.0.0.1"
  let server = newDesignSaveServer()
  stdout.writeLine "isonim-docs design editor -> http://" & host & ":" & $port &
    "  (foundation Save persists to " & docsDesignSystemPath & ")"
  stdout.writeLine "  run `just dev-docs` in another shell to see the saved edit " &
    "hot-reload the live docs."
  stdout.flushFile()
  waitFor serve(server, port, host = host)
