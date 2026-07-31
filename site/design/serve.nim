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
import isonim/editor                 # bindingSidecarRelPath, parseBindingSidecar
import ../src/theme_tokens          # docsDesignSystemPath
import ./dtcg_workspace             # docsSaveEndpoint + docsBindingsEndpoint/Global + applyDocsTokenEdit

const
  designDir = currentSourcePath().parentDir()   ## .../isonim-docs/site/design
  siteDir = designDir.parentDir()                ## .../isonim-docs/site
  bindingsSidecarPath = designDir / bindingSidecarRelPath
    ## VBIND-M7: `.../isonim-docs/site/design/.isonim/bindings.json` -- the
    ## design pilot's binding sidecar. Explicitly NOT the DTCG token source.

proc readDesignBindingsSidecar(): string =
  ## VBIND-M7 LOAD (server side): read the design pilot's binding sidecar if it
  ## exists, else "". The bytes are embedded verbatim into the editor page so
  ## the filesystem-less JS client can rehydrate its bindings.
  if fileExists(bindingsSidecarPath): readFile(bindingsSidecarPath) else: ""

proc injectBindingsGlobal*(html, sidecarJson: string): string =
  ## VBIND-M7: splice `window.__ISONIM_BINDINGS__ = <json>;` in just before the
  ## editor bundle `<script src>` (falling back to before `</body>`), so the
  ## client can read it synchronously at startup, ahead of building the
  ## workspace. An empty sidecar injects nothing (byte-unchanged page). The JSON
  ## is embedded as a JS string literal (via std/json's `escapeJson`) and read
  ## back through `JSON.parse`-free `loadBindingSidecar`, so `</script>` in the
  ## payload cannot break out of the script element.
  if sidecarJson.strip().len == 0:
    return html
  let script = "<script>window." & docsBindingsGlobal & "=JSON.parse(" &
    escapeJson(sidecarJson) & ");</script>"
  let marker = "<script src=\"/assets/design_editor.js\">"
  let idx = html.find(marker)
  if idx >= 0:
    html[0 ..< idx] & script & html[idx .. ^1]
  else:
    let bidx = html.rfind("</body>")
    if bidx >= 0: html[0 ..< bidx] & script & html[bidx .. ^1]
    else: html & script

proc editorPageHtml(): string =
  ## The editor host page. Read from `design/index.html` (whose `<script src>`
  ## already points at `/assets/design_editor.js`, i.e. the built bundle served
  ## from `build/` under `/assets/`). The live-reload client is spliced in by
  ## `dev_server`'s `injectLiveReload` around this.
  let indexPath = designDir / "index.html"
  let base =
    if fileExists(indexPath): readFile(indexPath)
    else:
      "<!doctype html><html><head><meta charset=\"utf-8\">" &
      "<title>Metacraft Docs Design System — Live Editor</title></head>" &
      "<body><script src=\"/assets/design_editor.js\"></script></body></html>"
  # VBIND-M7: embed the persisted binding sidecar so the JS client rehydrates.
  injectBindingsGlobal(base, readDesignBindingsSidecar())

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

proc writeBindingsSidecar*(sidecarPath, body: string): SaveResult =
  ## VBIND-M7 SAVE: persist the POSTed binding sidecar JSON to `sidecarPath`.
  ## A malformed / non-object payload is REJECTED with a 4xx and the sidecar left
  ## BYTE-IDENTICAL -- mirroring the M4b save route (`docsSaveHandler`), which
  ## never lets a bad payload touch the token file. This matters: `parseBindingSidecar`
  ## degrades corrupt input to *empty*, so writing its result unconditionally would
  ## let a single stray/hostile POST silently CLOBBER an existing good sidecar with
  ## an empty one (data loss). A well-formed payload -- including a legitimately
  ## EMPTY one (the user cleared every binding) -- is re-serialized through the
  ## framework's own `parseBindingSidecar`/`bindingSidecarJson` and only the
  ## canonical bytes are written. The DTCG token source is never in this path.
  ## Creates the `.isonim/` dir on demand.
  var doc: JsonNode
  try:
    doc = parseJson(body)
  except CatchableError as e:
    return SaveResult(status: 400, contentType: "application/json; charset=utf-8",
      body: """{"ok":false,"error":"invalid JSON: """ & e.msg.escapeJsonUnquoted & """"}""")
  if doc.kind != JObject:
    return SaveResult(status: 400, contentType: "application/json; charset=utf-8",
      body: """{"ok":false,"error":"sidecar must be a JSON object"}""")
  let parsed = parseBindingSidecar(body)
  let canonical = bindingSidecarJson(parsed.bindings, parsed.history)
  createDir(sidecarPath.parentDir)
  writeFile(sidecarPath, canonical)
  SaveResult(status: 200, contentType: "application/json; charset=utf-8",
    body: """{"ok":true,"bindings":""" & $parsed.bindings.len & "}")

proc docsBindingsHandler(body: string): SaveResult =
  ## The `just design` server's bindings route: write the editor's binding
  ## sidecar to `design/.isonim/bindings.json`.
  writeBindingsSidecar(bindingsSidecarPath, body)

proc newDesignSaveServer*(): DevServer =
  ## The `just design` editor + save server: serves the editor page, the built
  ## JS bundle and docs stylesheet under `/assets/`, the M4b save route, and the
  ## VBIND-M7 bindings-sidecar route.
  ## Exposed so a test can drive the exact wiring without binding a socket.
  newDevServer(
    contentDir = "",                      # no content routes; render is overridden
    cfg = docsConfig(),
    render = renderEditor,
    assetsDirs = @[designDir / "build", siteDir / "assets", siteDir / "static"],
    saveHandler = docsSaveHandler,
    savePath = docsSaveEndpoint,
    bindingsHandler = docsBindingsHandler,
    bindingsPath = docsBindingsEndpoint)

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
