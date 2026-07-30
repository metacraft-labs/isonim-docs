## M4b verification (server side): the live in-browser save loop, native half.
##
## This suite proves the WHOLE click-to-save loop HEADLESSLY -- no browser, per
## isonim's Layer-3 rule that ViewModels are pure and headless-testable
## (isonim/AGENTS.md: "prefer headless ViewModel tests first"). Clicking Save in
## the browser IS `vm.runEditorCommand(eckSave)`: the SolidJS-port view is a thin
## binding over the VM, so driving the VM is the faithful e2e for the interaction
## logic. Three levels of coverage, tightest last:
##
##   1. SERVER ENDPOINT: a POST body dispatched through `dev_server`'s opt-in
##      `saveHandler` patches a TEMP COPY of the real docs token file via the M4
##      `applyDocsTokenEdit` writeback -- exactly one side-leaf changes, the file
##      still loads as a docs token layer, and a malformed / rejected payload
##      returns an error while leaving the file BYTE-IDENTICAL. A `nil` handler
##      (every docs consumer's default) 404s -- backward-compatible.
##
##   2. SAVE BUTTON -> BROKER -> PERSIST: driving the real editor VM
##      (`editFoundationToken` then `runEditorCommand(eckSave)`) over the docs
##      workspace routes the edit through the framework's `WorkspaceEditAdapter`
##      broker into the project `persist` closure -- the exact path whose JS
##      `persist` is a `fetch`. The default (no `foundationSave`) workspace stays
##      read-only with no adapter (the RED before-state).
##
##   3. FULL LOOP, END TO END, HEADLESS: the real editor VM Save drives the REAL
##      `applyDocsTokenEdit` writeback (the same proc the server's `saveHandler`
##      calls) onto a temp copy of the token file, and the file CHANGES ON DISK --
##      user gesture -> VM command -> broker -> persist -> writeback -> file. The
##      only step not exercised here is the literal DOM click + the `fetch`
##      network transport that carries (2)'s call to (1)'s handler; that thin
##      transport is unit-tested in `test_editor_save_post.nim` (POST URL +
##      payload). There is no meaningful "e2e gap" left: the interaction logic and
##      the disk write are both covered without a browser.
##
## C target only (real fs I/O + the C-target editor VM the guardrail suite uses).

import std/[json, os, strutils, tempfiles, unittest]

import dev_server
import core/docs_tokens
import isonim/core/signals
import isonim/editor
import ../dtcg_workspace           # metacraftEditorWorkspace, docsWorkspaceEditAdapter, docsSaveEndpoint
import ../dtcg_writeback          # applyDocsTokenEdit, DtcgWriteError
import ../../src/theme_tokens      # docsDesignSystemPath, designSystemTokens, isonimDocsTokenLayer

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

proc mkDocsCopy(): string =
  ## Copy the real shared docs token file into a temp dir so the tests patch a
  ## COPY, never the checked-in source.
  let dir = createTempDir("design_save_", "_fixture")
  result = dir / "codetracer-docs.tokens.json"
  copyFile(docsDesignSystemPath, result)

proc saveServerOver(path: string): DevServer =
  ## A `dev_server` whose opt-in `saveHandler` runs the docs writeback against
  ## `path` (mirrors `design/serve.nim`'s handler, aimed at the temp copy).
  proc handler(body: string): SaveResult =
    var parsed: JsonNode
    try:
      parsed = parseJson(body)
    except CatchableError as e:
      return SaveResult(status: 400,
        contentType: "application/json; charset=utf-8",
        body: """{"ok":false,"error":""" & escapeJson(e.msg) & "}")
    if parsed.kind != JObject or not parsed.hasKey("var"):
      return SaveResult(status: 400,
        contentType: "application/json; charset=utf-8",
        body: """{"ok":false,"error":"missing var"}""")
    let varName = parsed["var"].getStr
    let side = (if parsed.hasKey("side"): parsed["side"].getStr else: "light")
    let value = (if parsed.hasKey("value"): parsed["value"].getStr else: "")
    try:
      let res = applyDocsTokenEdit(path, varName, value, side)
      SaveResult(status: 200, contentType: "application/json; charset=utf-8",
        body: """{"ok":true,"written":""" &
          (if res.written: "true" else: "false") & "}")
    except DtcgWriteError as e:
      SaveResult(status: 422, contentType: "application/json; charset=utf-8",
        body: """{"ok":false,"error":""" & escapeJson(e.msg) & "}")

  newDevServer(contentDir = "", saveHandler = handler, savePath = docsSaveEndpoint)

proc sideLiteral(text, varName, side: string): string =
  let s = parseJson(text)["vars"][varName][side]
  if s.hasKey("literal"): s["literal"].getStr else: ""

# ---------------------------------------------------------------------------
# 1. Server endpoint
# ---------------------------------------------------------------------------

suite "M4b: dev-server save endpoint patches the docs token file":

  test "a valid POST patches exactly one leaf via the M4 writeback":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    let server = saveServerOver(path)

    let res = handleSave(server,
      """{"var":"--docs-accent","side":"light","value":"#123456"}""")
    check res.status == 200
    check res.body.contains("\"ok\":true")

    # exactly the target side-leaf changed; the file still loads as a layer.
    let patched = readFile(path)
    check patched != orig
    check sideLiteral(patched, "--docs-accent", "light") == "#123456"
    check sideLiteral(patched, "--docs-accent", "dark") ==
          sideLiteral(orig, "--docs-accent", "dark")
    let layer = loadDocsTokenLayer(patched)
    var found = false
    for (name, binding) in layer.vars:
      if name == "--docs-accent":
        check binding.light == "#123456"
        found = true
    check found

    # the re-emitted CSS (what the dev-docs hot-reload serves) shows the edit.
    let css = emitTokensCss(loadDocsTokenLayer(readFile(path)), designSystemTokens())
    check css.contains("--docs-accent: #123456;")

  test "malformed JSON is rejected and the file is byte-identical":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    let server = saveServerOver(path)

    let res = handleSave(server, "{ this is not json")
    check res.status == 400
    check res.body.contains("\"ok\":false")
    check readFile(path) == orig            # untouched on disk

  test "an unknown var is rejected and the file is byte-identical":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    let server = saveServerOver(path)

    let res = handleSave(server,
      """{"var":"--docs-does-not-exist","side":"light","value":"#000000"}""")
    check res.status == 422
    check res.body.contains("\"ok\":false")
    check readFile(path) == orig

  test "a token-bound side (no literal) is rejected, file byte-identical":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    let server = saveServerOver(path)
    # --docs-focus-ring binds by {"token": ...}, not an editable literal.
    let res = handleSave(server,
      """{"var":"--docs-focus-ring","side":"light","value":"#000000"}""")
    check res.status == 422
    check readFile(path) == orig

  test "backward-compatible: with no saveHandler wired the endpoint 404s":
    # The three docs consumers construct their dev server with no saveHandler,
    # so a stray POST is inert and can never mutate anything.
    let server = newDevServer(contentDir = "")
    let res = handleSave(server, """{"var":"--docs-accent","value":"#123456"}""")
    check res.status == 404
    check server.saveHandler.isNil

# ---------------------------------------------------------------------------
# 2. Save button -> WorkspaceEditAdapter broker -> persist closure
# ---------------------------------------------------------------------------

suite "M4b: the editor Save button drives the broker into persist":

  test "editFoundationToken + eckSave routes the edit through persist":
    let layer = isonimDocsTokenLayer()
    let ts = designSystemTokens()

    # Capture what the broker hands the project persist closure.
    var captured: seq[tuple[varName, side, value: string]] = @[]
    let persist: DocsFoundationPersist =
      proc(varName, side, value: string): bool =
        captured.add (varName, side, value)
        true

    var vm: EditorVM
    let ws = metacraftEditorWorkspace(layer, ts,
      tokensAccessor = proc(): seq[FoundationTokenEntry] =
        if vm.isNil: @[] else: vm.foundations.tokens.val,
      foundationSave = persist)
    # The adapter is live and the workspace is now writable.
    check not ws.editAdapter.isNil
    check ws.permissions.writeSource

    vm = createEditorVM(ws)
    check vm.sourceAdapterReady.val

    check vm.editFoundationToken("--docs-accent", "#123456").status == pesAccepted
    check vm.inspector.pendingSourceEdits.val.len == 1
    check vm.workspaceEditStage.val == wesDirty

    let saved = vm.runEditorCommand(eckSave)
    check saved.status == ecsSucceeded
    check vm.workspaceEditStage.val == wesClean
    check vm.inspector.pendingSourceEdits.val.len == 0

    # The broker handed the persist closure exactly the edited var + value.
    check captured.len == 1
    check captured[0].varName == "--docs-accent"
    check captured[0].side == "light"
    check captured[0].value == "#123456"

  test "a rejected persist fails the save transaction (surfaced to the editor)":
    let layer = isonimDocsTokenLayer()
    let ts = designSystemTokens()
    let persist: DocsFoundationPersist =
      proc(varName, side, value: string): bool = false   # server rejected it

    var vm: EditorVM
    let ws = metacraftEditorWorkspace(layer, ts, foundationSave = persist)
    vm = createEditorVM(ws)
    check vm.editFoundationToken("--docs-accent", "#123456").status == pesAccepted
    let saved = vm.runEditorCommand(eckSave)
    check saved.status != ecsSucceeded
    check vm.workspaceEditStage.val != wesClean

  test "RED before-state: default docs workspace is read-only with no adapter":
    # Without `foundationSave` the workspace is byte-identical to M1--M4: no
    # edit adapter, source read-only, so the Save button is inert. This is the
    # gap M4b closes.
    let ws = metacraftEditorWorkspace(isonimDocsTokenLayer(), designSystemTokens())
    check ws.editAdapter.isNil
    check not ws.permissions.writeSource
    let vm = createEditorVM(ws)
    check not vm.sourceAdapterReady.val
    discard vm.editFoundationToken("--docs-accent", "#123456")
    # eckSave is unavailable: no adapter + read-only source.
    check vm.evaluateCommand(eckSave).status == ecsDisabled

# ---------------------------------------------------------------------------
# 3. Full loop, headless: VM Save -> real writeback -> file changes on disk
# ---------------------------------------------------------------------------

suite "M4b: clicking Save persists to disk (full headless loop)":

  test "editFoundationToken + eckSave writes the real token file":
    # The `persist` closure is NOT a mock: it runs the SAME `applyDocsTokenEdit`
    # writeback the dev-server `saveHandler` runs, aimed at a temp copy. So the
    # whole loop -- user edit -> VM Save command -> WorkspaceEditAdapter broker ->
    # persist -> structure-preserving writeback -> file on disk -- runs headlessly
    # with the real editor VM. This is "click to save" expressed as a ViewModel
    # test, minus only the fetch transport (unit-tested separately).
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)

    let persist: DocsFoundationPersist =
      proc(varName, side, value: string): bool =
        try:
          discard applyDocsTokenEdit(path, varName, value, side)
          true
        except DtcgWriteError:
          false

    var vm: EditorVM
    let ws = metacraftEditorWorkspace(isonimDocsTokenLayer(), designSystemTokens(),
      foundationSave = persist)
    vm = createEditorVM(ws)
    check vm.sourceAdapterReady.val

    # Nothing on disk yet after the in-editor edit -- only the save commits it.
    check vm.editFoundationToken("--docs-accent", "#123456").status == pesAccepted
    check readFile(path) == orig

    let saved = vm.runEditorCommand(eckSave)
    check saved.status == ecsSucceeded
    check vm.workspaceEditStage.val == wesClean

    # The file changed on disk, structure-preserved: only the target side-leaf.
    let patched = readFile(path)
    check patched != orig
    check sideLiteral(patched, "--docs-accent", "light") == "#123456"
    check sideLiteral(patched, "--docs-accent", "dark") ==
          sideLiteral(orig, "--docs-accent", "dark")
    # A sibling token is untouched -> the writeback did not rewrite the file.
    check sideLiteral(patched, "--docs-link", "light") ==
          sideLiteral(orig, "--docs-link", "light")
    # It re-loads cleanly as a docs token layer carrying the new value.
    var found = false
    for (name, binding) in loadDocsTokenLayer(patched).vars:
      if name == "--docs-accent":
        check binding.light == "#123456"
        found = true
    check found

  test "a writeback-rejected Save leaves the file byte-identical and stays dirty":
    # If the real writeback rejects the edit (persist returns false), the VM
    # surfaces a failed save and the file is never touched -- same guarantee the
    # server gives, proven through the VM.
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)

    let persist: DocsFoundationPersist =
      proc(varName, side, value: string): bool =
        try:
          discard applyDocsTokenEdit(path, "--docs-does-not-exist", value, side)
          true
        except DtcgWriteError:
          false

    var vm: EditorVM
    let ws = metacraftEditorWorkspace(isonimDocsTokenLayer(), designSystemTokens(),
      foundationSave = persist)
    vm = createEditorVM(ws)
    check vm.editFoundationToken("--docs-accent", "#123456").status == pesAccepted
    let saved = vm.runEditorCommand(eckSave)
    check saved.status != ecsSucceeded
    check vm.workspaceEditStage.val != wesClean
    check readFile(path) == orig
