## VBIND-M7 (docs pilot): variable-binding sidecar persistence, native half.
##
## PART A of VBIND-M7 closes the loop for the docs design editor: a bind/detach
## POSTs the collected binding metadata to a NEW dev-server route
## (``/__isonim_bindings``), parallel to the M4b ``/__isonim_save`` foundation
## route, which writes ``design/.isonim/bindings.json`` server-side; and on
## reload the server embeds that sidecar into the editor page so the
## filesystem-less JS client rehydrates its chips. This suite proves that
## HEADLESSLY (mirroring ``test_design_save_server.nim``), on a TEMP sidecar so
## the checked-in tree is never written, with three guarantees throughout:
##
##   1. SAVE ROUTE: a POST through the opt-in ``bindingsHandler`` writes a
##      sidecar that round-trips through ``parseBindingSidecar``; a malformed /
##      hostile payload is REJECTED (4xx) without crashing AND without clobbering
##      an existing good sidecar (mirrors the M4b save route's reject-untouched
##      contract); a ``nil`` handler (every other docs consumer's default) 404s.
##   2. LOAD: building the docs workspace + loading an existing sidecar
##      rehydrates the bindings into ``InspectorVM.propertyBindings``; a
##      malformed sidecar rehydrates to empty; the page-embed injection carries
##      the JSON to the client (and is a no-op for an absent sidecar).
##   3. DTCG UNTOUCHED: the real ``codetracer-docs.tokens.json`` DTCG token
##      source is byte-identical before and after the whole exercise — binding
##      metadata never touches it.
##
## C target only (real fs I/O + the C-target editor VM the guardrail suite uses).

import std/[os, strutils, tables, tempfiles, unittest]

import dev_server
import isonim/core/signals
import isonim/editor
import ../dtcg_workspace           # metacraftEditorWorkspace, docsBindingsEndpoint/Global
import ../serve                    # writeBindingsSidecar, injectBindingsGlobal
import ../../src/theme_tokens      # docsDesignSystemPath, designSystemTokens, isonimDocsTokenLayer

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

proc tempSidecar(): string =
  ## A sidecar path under a throwaway temp dir — NEVER the checked-in
  ## design/.isonim/bindings.json.
  let dir = createTempDir("design_bindings_", "_fixture")
  dir / bindingSidecarRelPath

proc bindingsServerOver(path: string): DevServer =
  ## A dev_server whose opt-in bindingsHandler writes the sidecar to `path`
  ## (mirrors design/serve.nim's handler, aimed at the temp copy).
  proc handler(body: string): SaveResult = writeBindingsSidecar(path, body)
  newDevServer(contentDir = "", bindingsHandler = handler,
    bindingsPath = docsBindingsEndpoint)

const SamplePayload = """
{"version":1,
 "variableBindings":[
   {"elementId":"frame-1","propertyName":"border-color","variableKey":"--docs-accent"}],
 "variableBindingHistory":[
   {"elementId":"frame-1","propertyName":"border-color",
    "variableKeys":["--docs-accent","--docs-link"]}]}
"""

# ---------------------------------------------------------------------------
# 1. Save route
# ---------------------------------------------------------------------------

suite "VBIND-M7 docs: bindings route writes the sidecar (DTCG untouched)":

  test "a valid POST writes design/.isonim/bindings.json that round-trips":
    let sidecar = tempSidecar()
    defer: removeDir(sidecar.parentDir.parentDir)
    let dtcgBefore = readFile(docsDesignSystemPath)
    let server = bindingsServerOver(sidecar)

    let res = handleBindings(server, SamplePayload)
    check res.status == 200
    check res.body.contains("\"ok\":true")

    check fileExists(sidecar)
    let parsed = parseBindingSidecar(readFile(sidecar))
    check parsed.bindings.len == 1
    check parsed.bindings[0].elementId == "frame-1"
    check parsed.bindings[0].propertyName == "border-color"
    check parsed.bindings[0].variableKey == "--docs-accent"
    check parsed.history.len == 1
    check parsed.history[0].variableKeys == @["--docs-accent", "--docs-link"]

    # The DTCG token source is byte-identical — bindings never touch it.
    check readFile(docsDesignSystemPath) == dtcgBefore

  test "a malformed payload is rejected without clobbering a good sidecar (no crash)":
    let sidecar = tempSidecar()
    defer: removeDir(sidecar.parentDir.parentDir)
    let dtcgBefore = readFile(docsDesignSystemPath)
    let server = bindingsServerOver(sidecar)

    # First persist a GOOD sidecar (a normal bind save).
    check handleBindings(server, SamplePayload).status == 200
    let good = readFile(sidecar)
    check parseBindingSidecar(good).bindings.len == 1

    # A malformed / hostile POST must not crash AND must not overwrite the good
    # sidecar with an empty one — `parseBindingSidecar` degrades corrupt input to
    # empty, so a write-anyway handler would silently lose the persisted bindings
    # (data loss). Mirrors M4b's "malformed JSON is rejected, file byte-identical".
    let res = handleBindings(server, "{ this is not json")
    check res.status == 400
    check readFile(sidecar) == good                                # not clobbered
    check parseBindingSidecar(readFile(sidecar)).bindings.len == 1
    check readFile(docsDesignSystemPath) == dtcgBefore

  test "backward-compatible: with no bindingsHandler wired the route 404s":
    # Every other docs consumer constructs its dev server with no bindingsHandler,
    # so a stray POST to the bindings route is inert and mutates nothing.
    let server = newDevServer(contentDir = "")
    let res = handleBindings(server, SamplePayload)
    check res.status == 404
    check server.bindingsHandler.isNil

# ---------------------------------------------------------------------------
# 2. Load: building the workspace rehydrates from an existing sidecar
# ---------------------------------------------------------------------------

suite "VBIND-M7 docs: building the workspace loads an existing sidecar":

  test "an existing sidecar rehydrates propertyBindings on the docs workspace":
    let dtcgBefore = readFile(docsDesignSystemPath)
    # Build the REAL docs workspace, then load a sidecar the way design/main.nim
    # does (from the server-injected global) before mounting.
    var ws = metacraftEditorWorkspace(isonimDocsTokenLayer(), designSystemTokens())
    # Pick a real --docs-* variable that exists in the docs foundations so the
    # rehydrated binding resolves to vbsBound.
    var realVar = ""
    for t in ws.foundationTokens:
      if t.key.startsWith("--docs-") and t.kind == ftkColorPalette:
        realVar = t.key
        break
    check realVar.len > 0

    ws.loadBindingSidecar(
      "{\"version\":1,\"variableBindings\":[{\"elementId\":\"frame-1\"," &
      "\"propertyName\":\"border-color\",\"variableKey\":\"" & realVar &
      "\"}],\"variableBindingHistory\":[]}")
    check ws.variableBindings.len == 1

    let vm = createEditorVM(ws)
    let key = PropertyBindingKey(elementId: "frame-1",
      propertyName: "border-color")
    let bound = vm.propertyBindingFor(key)
    check bound.isSome
    check bound.get.variableKey == realVar
    check bound.get.state == vbsBound

    check readFile(docsDesignSystemPath) == dtcgBefore

  test "a malformed sidecar rehydrates to empty (no crash), DTCG untouched":
    let dtcgBefore = readFile(docsDesignSystemPath)
    var ws = metacraftEditorWorkspace(isonimDocsTokenLayer(), designSystemTokens())
    ws.loadBindingSidecar("{ not valid json")
    check ws.variableBindings.len == 0
    let vm = createEditorVM(ws)
    check vm.inspector.propertyBindings.val.len == 0
    check readFile(docsDesignSystemPath) == dtcgBefore

  test "page-embed injection carries the sidecar JSON; empty is a no-op":
    let page = "<!doctype html><html><body>" &
      "<script src=\"/assets/design_editor.js\"></script></body></html>"
    # Empty sidecar leaves the page byte-identical.
    check injectBindingsGlobal(page, "") == page
    check injectBindingsGlobal(page, "   ") == page
    # A real sidecar injects the global BEFORE the editor bundle so the client
    # reads it synchronously at startup.
    let injected = injectBindingsGlobal(page, SamplePayload)
    check injected.contains("window." & docsBindingsGlobal & "=")
    let g = injected.find("window." & docsBindingsGlobal)
    let s = injected.find("/assets/design_editor.js")
    check g >= 0 and s >= 0 and g < s
