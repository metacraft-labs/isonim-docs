## M2 verification: DTCG source write-back round-trip + corruption guards.
##
## Proves the `dtcg_writeback` writer:
##   * changes EXACTLY the target token's `$value` (a parsed-JSON deep diff
##     shows exactly one leaf, and only its `$value`, changed),
##   * preserves `$type` / `$extensions` / alias refs and every sibling token
##     (byte-preserving raw-text patch),
##   * re-parses + re-resolves cleanly (the built-in write guard), and
##   * ROUND-TRIPS: emit -> edit -> write -> reload -> emit yields the edited
##     value in the regenerated CSS,
## plus the guards:
##   * a dangling `{alias}` edit is REJECTED and leaves the file unchanged,
##   * a cyclic edit is REJECTED and leaves the file unchanged,
##   * dry-run returns the would-be content WITHOUT touching disk.
##
## The test copies FIXTURE DTCG documents into a temp dir; it never mutates
## the real `codetracer-design-system/*.json`. C target only (real fs I/O).

import std/[json, os, strutils, tables, tempfiles, unittest]

import core/[tokens, docs_tokens]
import isonim/editor
import ../dtcg_workspace
import ../dtcg_writeback
import ../../src/theme_tokens  # docsDesignSystemPath + designSystemTokens (M4)

# ---------------------------------------------------------------------------
# Fixture: a brand -> alias -> mapped chain WITH $extensions (Figma metadata)
# and $type siblings, mirroring the real codetracer-design-system shape.
# ---------------------------------------------------------------------------

const brandJson = """{
  "colors": {
    "grey": {
      "50": {
        "$extensions": {
          "com.figma.scopes": ["ALL_SCOPES"],
          "com.figma.hiddenFromPublishing": false
        },
        "$type": "color",
        "$value": "#f3f3f3"
      },
      "900": {
        "$type": "color",
        "$value": "#111111"
      }
    },
    "blue": { "500": { "$type": "color", "$value": "#4168cc" } },
    "green": { "500": { "$type": "color", "$value": "#3fb950" } }
  },
  "space": { "card": { "$type": "dimension", "$value": "16px" } }
}
"""

const aliasJson = """{
  "colors": {
    "neutral": {
      "50": {
        "$extensions": { "com.figma.hiddenFromPublishing": false },
        "$type": "color",
        "$value": "{colors.grey.50}"
      }
    }
  }
}
"""

const mappedJson = """{
  "colors": {
    "ui": {
      "text": {
        "body": {
          "$type": "color",
          "$value": "{colors.neutral.50}"
        }
      }
    }
  }
}
"""

proc fixtureLayer(): DocsTokenLayer =
  ## `--docs-fg` follows the full 3-hop chain
  ## (mapped ui.text.body -> alias neutral.50 -> brand grey.50 -> #f3f3f3);
  ## `--docs-accent` binds the brand blue primitive directly; a literal too.
  result.add "--docs-fg", token("colors.ui.text.body", "colors.ui.text.body")
  result.add "--docs-accent", token("colors.blue.500", "colors.blue.500")
  result.add "--docs-radius-lg", literal("10px")

# ---------------------------------------------------------------------------
# Temp-dir fixture helpers (never touch the real design-system files)
# ---------------------------------------------------------------------------

proc mkFixtureDir(): string =
  result = createTempDir("dtcg_wb_", "_fixture")
  writeFile(result / "brand.json", brandJson)
  writeFile(result / "alias.json", aliasJson)
  writeFile(result / "mapped.json", mappedJson)

proc readFiles(dir: string): seq[DtcgFile] =
  @[DtcgFile(path: dir / "brand.json", text: readFile(dir / "brand.json")),
    DtcgFile(path: dir / "alias.json", text: readFile(dir / "alias.json")),
    DtcgFile(path: dir / "mapped.json", text: readFile(dir / "mapped.json"))]

## Flatten a DTCG doc to {dotted.path -> compact JSON of the whole leaf node}
## so a diff can show precisely which leaf (and which of its keys) changed.
proc collectLeaves(node: JsonNode; prefix: string; tbl: var Table[string, JsonNode]) =
  if node.kind != JObject: return
  if node.hasKey("$value"):
    tbl[prefix] = node
    return
  for k, child in node:
    if k.startsWith("$"): continue
    let p = if prefix.len == 0: k else: prefix & "." & k
    collectLeaves(child, p, tbl)

proc leavesOf(text: string): Table[string, JsonNode] =
  result = initTable[string, JsonNode]()
  collectLeaves(parseJson(text), "", result)

suite "DTCG write-back round-trip + guards (M2)":

  test "writeDtcgTokenValue changes exactly the target $value, preserves the rest":
    let dir = mkFixtureDir()
    defer: removeDir(dir)
    let brandPath = dir / "brand.json"
    let before = leavesOf(readFile(brandPath))

    let res = writeDtcgTokenValue(brandPath, "colors.grey.50", "#ff0000")
    check res.written
    check res.changed
    check res.targetPath == brandPath

    let after = leavesOf(readFile(brandPath))

    # (a) exactly the target leaf differs; every other leaf is byte-identical.
    check before.len == after.len
    var changedKeys: seq[string]
    for k, v in before:
      if $after[k] != $v: changedKeys.add k
    check changedKeys == @["colors.grey.50"]

    # (b) on the changed leaf, ONLY $value changed; $type + $extensions kept.
    let b = before["colors.grey.50"]
    let a = after["colors.grey.50"]
    check b["$value"].getStr == "#f3f3f3"
    check a["$value"].getStr == "#ff0000"
    check a["$type"].getStr == "color"
    check a.hasKey("$extensions")
    check $a["$extensions"] == $b["$extensions"]      # extensions untouched

    # (c) alias siblings + refs intact: neutral.50 still {colors.grey.50}.
    let aliasLeaves = leavesOf(readFile(dir / "alias.json"))
    check aliasLeaves["colors.neutral.50"]["$value"].getStr == "{colors.grey.50}"

    # (d) re-parses + resolves cleanly, with the new value flowing through.
    let ts = loadTokensFromStrings(
      [readFile(brandPath), readFile(dir / "alias.json"), readFile(dir / "mapped.json")])
    check ts.resolve("colors.ui.text.body") == "#ff0000"   # 3-hop -> new primitive

  test "raw-text patch preserves surrounding formatting (byte diff is minimal)":
    let dir = mkFixtureDir()
    defer: removeDir(dir)
    let brandPath = dir / "brand.json"
    let orig = readFile(brandPath)
    discard writeDtcgTokenValue(brandPath, "colors.grey.900", "#222222")
    let patched = readFile(brandPath)
    # The ONLY textual change is "#111111" -> "#222222"; everything else,
    # including indentation and $extensions blocks, is byte-identical.
    check orig.replace("\"#111111\"", "\"#222222\"") == patched

  test "round-trip: emit -> edit -> write -> reload -> emit reflects the edit":
    let dir = mkFixtureDir()
    defer: removeDir(dir)
    let layer = fixtureLayer()

    proc emitNow(): string =
      let ts = loadTokensFromStrings(
        [readFile(dir / "brand.json"), readFile(dir / "alias.json"),
         readFile(dir / "mapped.json")])
      emitTokensCss(layer, ts)

    check "--docs-fg: #f3f3f3;" in emitNow()

    # Edit the tail primitive the --docs-fg chain resolves to.
    let res = applyDtcgEdit(readFiles(dir), "colors.grey.50", "#0a0a0a")
    check res.written
    check "--docs-fg: #0a0a0a;" in emitNow()          # regenerated CSS restyled
    check "--docs-accent: #4168cc;" in emitNow()      # untouched token stable

  test "round-trip via a SourceEditPlan (editor edit path)":
    let dir = mkFixtureDir()
    defer: removeDir(dir)
    let layer = fixtureLayer()
    let ts0 = loadTokensFromStrings(
      [readFile(dir / "brand.json"), readFile(dir / "alias.json"),
       readFile(dir / "mapped.json")])
    let tokens = dtcgFoundationTokens(layer, ts0)

    # A plan as `editFoundationToken` would emit for --docs-fg (its aliasOf
    # head is the DTCG semantic token colors.ui.text.body).
    let plan = SourceEditPlan(
      property: "--docs-fg", tokenName: "--docs-fg",
      newValue: "#00ff00", planKind: cspTokenUpdate)
    check dtcgKeyForPlan(plan, tokens) == "colors.ui.text.body"

    let res = applyDtcgEdit(readFiles(dir), plan, tokens)
    check res.targetPath == dir / "mapped.json"
    check res.written

    let ts = loadTokensFromStrings(
      [readFile(dir / "brand.json"), readFile(dir / "alias.json"),
       readFile(dir / "mapped.json")])
    check ts.resolve("colors.ui.text.body") == "#00ff00"
    check emitTokensCss(layer, ts).contains("--docs-fg: #00ff00;")

  test "guard: a dangling {alias} edit is rejected and the file is unchanged":
    let dir = mkFixtureDir()
    defer: removeDir(dir)
    let files = readFiles(dir)
    let aliasBefore = readFile(dir / "alias.json")

    var raised = false
    try:
      discard applyDtcgEdit(files, "colors.neutral.50", "{colors.does.not.exist}")
    except DtcgWriteError:
      raised = true
    check raised
    check readFile(dir / "alias.json") == aliasBefore    # untouched on disk

  test "guard: a cyclic edit is rejected and the file is unchanged":
    let dir = mkFixtureDir()
    defer: removeDir(dir)
    let files = readFiles(dir)
    let brandBefore = readFile(dir / "brand.json")

    # grey.50 -> {colors.neutral.50}, while neutral.50 -> {colors.grey.50}: a cycle.
    var raised = false
    try:
      discard applyDtcgEdit(files, "colors.grey.50", "{colors.neutral.50}")
    except DtcgWriteError:
      raised = true
    check raised
    check readFile(dir / "brand.json") == brandBefore    # untouched on disk

  test "dry-run / export returns content without writing":
    let dir = mkFixtureDir()
    defer: removeDir(dir)
    let files = readFiles(dir)
    let brandBefore = readFile(dir / "brand.json")

    let res = applyDtcgEdit(files, "colors.grey.50", "#abcabc", dryRun = true)
    check res.dryRun
    check not res.written
    check res.changed
    check "\"#abcabc\"" in res.newText                   # would-be content
    check readFile(dir / "brand.json") == brandBefore    # disk untouched

  test "writing an unknown key raises and touches nothing":
    let dir = mkFixtureDir()
    defer: removeDir(dir)
    let files = readFiles(dir)
    var raised = false
    try:
      discard applyDtcgEdit(files, "colors.grey.999", "#000000")
    except DtcgWriteError:
      raised = true
    check raised

# ---------------------------------------------------------------------------
# M4: docs-tokens-layer write-back (codetracer-docs.tokens.json)
# ---------------------------------------------------------------------------
#
# The docs editor mounts over the FLATTER `loadDocsTokenLayer` file, not the
# brand/alias/mapped DTCG graph. These tests operate on a TEMP COPY of the
# real `codetracer-docs.tokens.json` (never the checked-in file) and prove the
# M4 writer: a foundation-token edit persists to that file as a structure-
# preserving patch of exactly one `{"<side>":{"literal":...}}` leaf, the file
# still loads via `loadDocsTokenLayer` (so `just dev-docs`'s token hot-reload
# re-emits the new value), and a bad target is rejected without corrupting the
# file.

proc mkDocsCopy(): string =
  ## Copy the real shared docs token file into a temp dir so the tests can
  ## patch it without ever mutating the checked-in source.
  let dir = createTempDir("docs_wb_", "_fixture")
  result = dir / "codetracer-docs.tokens.json"
  copyFile(docsDesignSystemPath, result)

## Flatten a docs token layer JSON to {"--docs-x.light" -> compact side JSON}
## so a deep diff shows precisely which var + side (and its literal) changed.
proc docsSideLeaves(text: string): Table[string, string] =
  result = initTable[string, string]()
  let doc = parseJson(text)
  for name, spec in doc["vars"]:
    for side in ["light", "dark"]:
      if spec.hasKey(side):
        result[name & "." & side] = $spec[side]

proc sideLiteral(text, varName, side: string): string =
  ## The `literal` string of `vars[varName][side]`, or "" if it is a token side.
  let s = parseJson(text)["vars"][varName][side]
  if s.hasKey("literal"): s["literal"].getStr else: ""

suite "docs-tokens write-back (M4)":

  test "a colour edit changes exactly one side-leaf and preserves the rest":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    let before = docsSideLeaves(orig)

    let res = applyDocsTokenEdit(path, "--docs-accent", "#123456", side = "light")
    check res.written
    check res.changed
    check res.targetPath == path

    let after = docsSideLeaves(readFile(path))

    # (a) exactly the target side-leaf differs; every other var + side is intact.
    check before.len == after.len
    var changedKeys: seq[string]
    for k, v in before:
      if after[k] != v: changedKeys.add k
    check changedKeys == @["--docs-accent.light"]

    # (b) only the literal changed; the dark side of the SAME var is untouched.
    check sideLiteral(readFile(path), "--docs-accent", "light") == "#123456"
    check sideLiteral(readFile(path), "--docs-accent", "dark") ==
          sideLiteral(orig, "--docs-accent", "dark")

    # (c) the file still loads via loadDocsTokenLayer with the new value.
    let layer = loadDocsTokenLayer(readFile(path))
    var found = false
    for (name, binding) in layer.vars:
      if name == "--docs-accent":
        check binding.light == "#123456"
        found = true
    check found

    # (d) $description + fontFaces prelude are byte-preserved.
    let od = parseJson(orig); let nd = parseJson(readFile(path))
    check nd["$description"] == od["$description"]
    check nd["fontFaces"] == od["fontFaces"]

  test "raw-text patch preserves formatting: exactly one text line changes":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    discard applyDocsTokenEdit(path, "--docs-accent", "#123456", side = "light")
    let patched = readFile(path)

    let origLines = orig.splitLines
    let patchedLines = patched.splitLines
    check origLines.len == patchedLines.len
    var diffLines: seq[int]
    for i in 0 ..< origLines.len:
      if origLines[i] != patchedLines[i]: diffLines.add i
    check diffLines.len == 1
    check patchedLines[diffLines[0]].contains("--docs-accent")
    check patchedLines[diffLines[0]].contains("#123456")
    # A sibling that ALSO happened to be #4168cc (--docs-link) is untouched.
    check sideLiteral(patched, "--docs-link", "light") == "#4168cc"

  test "a size/spacing edit round-trips the same way":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let before = docsSideLeaves(readFile(path))

    let res = applyDocsTokenEdit(path, "--docs-space-4", "1.25rem", side = "light")
    check res.written

    let after = docsSideLeaves(readFile(path))
    var changedKeys: seq[string]
    for k, v in before:
      if after[k] != v: changedKeys.add k
    check changedKeys == @["--docs-space-4.light"]
    check sideLiteral(readFile(path), "--docs-space-4", "light") == "1.25rem"

  test "a dark-side edit patches only the dark literal":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let before = docsSideLeaves(readFile(path))
    discard applyDocsTokenEdit(path, "--docs-accent", "#654321", side = "dark")
    let after = docsSideLeaves(readFile(path))
    var changedKeys: seq[string]
    for k, v in before:
      if after[k] != v: changedKeys.add k
    check changedKeys == @["--docs-accent.dark"]
    check sideLiteral(readFile(path), "--docs-accent", "dark") == "#654321"

  test "hot-reload content: emitTokensCss over the reloaded file shows the edit":
    # This is exactly what the dev server's tokensCssProvider (docsTokensCssLive)
    # runs per request + on file change -- reload the file, re-emit its CSS.
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    discard applyDocsTokenEdit(path, "--docs-accent", "#123456", side = "light")
    let ts = designSystemTokens()
    let css = emitTokensCss(loadDocsTokenLayer(readFile(path)), ts)
    check css.contains("--docs-accent: #123456;")

  test "editor edit path: a SourceEditPlan persists to the docs token file":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let tokens = dtcgFoundationTokens(isonimDocsTokenLayer(), designSystemTokens())
    # A plan as `editFoundationToken` emits for --docs-accent (a literal var).
    let plan = SourceEditPlan(
      property: "--docs-accent", tokenName: "--docs-accent",
      newValue: "#0f0f0f", planKind: cspTokenUpdate)
    check docsVarForPlan(plan) == "--docs-accent"

    let res = applyDocsTokenEdit(path, plan)
    check res.written
    check sideLiteral(readFile(path), "--docs-accent", "light") == "#0f0f0f"
    let css = emitTokensCss(loadDocsTokenLayer(readFile(path)), designSystemTokens())
    check css.contains("--docs-accent: #0f0f0f;")

  test "guard: a non-existent var is rejected and the file is byte-identical":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    var raised = false
    try:
      discard applyDocsTokenEdit(path, "--docs-does-not-exist", "#000000")
    except DtcgWriteError:
      raised = true
    check raised
    check readFile(path) == orig                       # untouched on disk

  test "guard: a bad side is rejected and the file is byte-identical":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    var raised = false
    try:
      discard applyDocsTokenEdit(path, "--docs-accent", "#000000", side = "sepia")
    except DtcgWriteError:
      raised = true
    check raised
    check readFile(path) == orig

  test "guard: a token-bound side (no literal) is rejected, file byte-identical":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    # --docs-focus-ring binds by {"token": "colors.blue.500"}, not a literal.
    var raised = false
    try:
      discard applyDocsTokenEdit(path, "--docs-focus-ring", "#000000")
    except DtcgWriteError:
      raised = true
    check raised
    check readFile(path) == orig

  test "dry-run / export returns content without writing":
    let path = mkDocsCopy()
    defer: removeDir(path.parentDir)
    let orig = readFile(path)
    let res = applyDocsTokenEdit(path, "--docs-accent", "#abcabc", dryRun = true)
    check res.dryRun
    check not res.written
    check res.changed
    check "\"#abcabc\"" in res.newText
    check readFile(path) == orig                       # disk untouched
