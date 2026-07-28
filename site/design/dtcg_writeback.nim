## DTCG source write-back for the live Metacraft docs design-system editor.
##
## This is the ROUND-TRIP half of the "live design-system editor" track
## (design-system-editor.milestones.org M2). M1 read the DTCG token set into
## an `EditorWorkspace` and previewed edits; this module persists an edit
## back to the `codetracer-design-system/*.json` DTCG source, closing the
## loop so a saved edit -> reload (`core/tokens`) -> re-emit
## (`core/docs_tokens.emitTokensCss`) restyles the site.
##
## Design (how it locates + patches the token):
##   * A DTCG token is addressed by its dotted path (`colors.grey.50`), the
##     same key `core/tokens` flattens to. The `FoundationTokenEntry.aliasOf`
##     the M1 adapter records IS that dotted key, so a `SourceEditPlan` the
##     editor emits maps straight onto a write target (`dtcgKeyForPlan`).
##   * The write is a STRUCTURE-PRESERVING RAW-TEXT PATCH, not a
##     parse -> mutate -> re-serialize. `std/json` re-serialization would
##     reflow the whole file (indentation/number formatting) and, although
##     Nim's `JObject` keeps insertion order, it would still rewrite every
##     sibling token's bytes. Instead we scan the raw text structurally
##     (string/brace aware), locate EXACTLY the target leaf's `$value` span,
##     and splice in the new value. Every other byte -- `$type`,
##     `$extensions`, sibling tokens, whitespace, key order -- is preserved
##     verbatim. (Formatting caveat: only the replacement value is
##     re-encoded, via `escapeJson`; the surrounding document is untouched.)
##
## Corruption guards (deliverable 2):
##   * Before a write commits, the patched document set is re-parsed and the
##     WHOLE token graph re-resolved (`core/tokens`). A parse failure, a
##     dangling `{alias}`, or a reference cycle ABORTS the write -- the file
##     on disk is never touched -- and surfaces a clear `DtcgWriteError`.
##   * A dry-run / export mode returns the would-be-written content without
##     touching disk.

import std/[json, strutils, os]

import core/tokens
import isonim/editor  # FoundationTokenEntry, SourceEditPlan (plan bridge)

type
  DtcgWriteError* = object of CatchableError
    ## Raised when a write cannot be located or would corrupt the token
    ## graph. When raised from `applyDtcgEdit`/`writeDtcgTokenValue`, the
    ## file on disk is guaranteed untouched.

  DtcgFile* = object
    ## One DTCG document in a layered set (brand / alias / mapped), carried
    ## by path + its current raw text so the writer can patch text in place.
    path*: string
    text*: string

  DtcgWriteResult* = object
    ## Outcome of an edit. `newText` is the patched content of the file that
    ## held the key (the export/dry-run payload); `changed` is whether the
    ## value actually differs; `written` is whether it was flushed to disk.
    targetPath*: string
    newText*: string
    oldValue*: string
    newValue*: string
    changed*: bool
    written*: bool
    dryRun*: bool

# ---------------------------------------------------------------------------
# Structural raw-text scanner (string/brace aware, position-tracking)
# ---------------------------------------------------------------------------

const Ws = {' ', '\t', '\n', '\r'}

func skipWs(text: string; i: int): int =
  result = i
  while result < text.len and text[result] in Ws:
    inc result

func scanString(text: string; i: int): int =
  ## `i` at the opening quote; returns the index just past the closing quote,
  ## honouring backslash escapes.
  var j = i + 1
  while j < text.len:
    if text[j] == '\\':
      j += 2
      continue
    if text[j] == '"':
      return j + 1
    inc j
  j

func scanValue(text: string; i: int): int =
  ## `i` at the first char of a JSON value; returns the index just past it.
  ## Handles strings, objects, arrays, and primitives.
  if i >= text.len: return i
  case text[i]
  of '"':
    scanString(text, i)
  of '{', '[':
    var depth = 0
    var j = i
    while j < text.len:
      let ch = text[j]
      if ch == '"':
        j = scanString(text, j)
        continue
      elif ch == '{' or ch == '[':
        inc depth
      elif ch == '}' or ch == ']':
        dec depth
        if depth == 0:
          return j + 1
      inc j
    j
  else:
    var j = i
    while j < text.len and text[j] notin (Ws + {',', '}', ']'}):
      inc j
    j

func keyBody(text: string; quoteStart, quoteEnd: int): string =
  ## The literal member key between the quotes. DTCG keys used here
  ## (`$value`, `$type`, `grey`, `50`, ...) carry no escapes, so a plain
  ## slice is exact.
  text[quoteStart + 1 ..< quoteEnd - 1]

func findMemberValue(text: string; objBrace: int; key: string):
    tuple[valStart, valEnd: int] =
  ## Within the object whose `{` is at `objBrace`, find the member named
  ## `key` and return the [valStart, valEnd) span of its value (whitespace
  ## already skipped at valStart). Returns (-1, -1) if absent.
  var i = objBrace + 1
  while true:
    i = skipWs(text, i)
    if i >= text.len or text[i] == '}':
      return (-1, -1)
    if text[i] != '"':
      # malformed / unexpected; bail out defensively
      return (-1, -1)
    let keyEnd = scanString(text, i)
    let k = keyBody(text, i, keyEnd)
    var j = skipWs(text, keyEnd)
    if j >= text.len or text[j] != ':':
      return (-1, -1)
    j = skipWs(text, j + 1)
    let vStart = j
    let vEnd = scanValue(text, j)
    if k == key:
      return (vStart, vEnd)
    j = skipWs(text, vEnd)
    if j < text.len and text[j] == ',':
      inc j
    i = j

# ---------------------------------------------------------------------------
# The patch: locate a dotted token's $value and splice a new value in
# ---------------------------------------------------------------------------

proc patchDtcgValue*(text: string; dottedKey, newValue: string):
    tuple[newText, oldValue: string] =
  ## Returns `text` with the `$value` of the DTCG token at `dottedKey`
  ## replaced by `newValue` (JSON-string encoded), plus the old raw value
  ## span for reporting. Only the value bytes change; everything else is
  ## byte-preserved. Raises `DtcgWriteError` if the path does not resolve to
  ## a token leaf (an object carrying `$value`).
  if dottedKey.len == 0:
    raise newException(DtcgWriteError, "empty DTCG token key")
  let segs = dottedKey.split('.')
  var brace = skipWs(text, 0)
  if brace >= text.len or text[brace] != '{':
    raise newException(DtcgWriteError, "DTCG document root is not a JSON object")
  # Descend through every path segment; each must name a nested object.
  for depth, seg in segs:
    let (vs, ve) = findMemberValue(text, brace, seg)
    if vs < 0:
      raise newException(DtcgWriteError,
        "DTCG key '" & dottedKey & "' not found: missing segment '" & seg &
        "' (matched " & $depth & " of " & $segs.len & ")")
    discard ve
    let inner = skipWs(text, vs)
    if inner >= text.len or text[inner] != '{':
      raise newException(DtcgWriteError,
        "DTCG key '" & dottedKey & "' segment '" & seg &
        "' is not an object (cannot descend)")
    brace = inner
  # `brace` is now the leaf object; it must carry a `$value` to be a token.
  let (valStart, valEnd) = findMemberValue(text, brace, "$value")
  if valStart < 0:
    raise newException(DtcgWriteError,
      "DTCG key '" & dottedKey & "' is a group, not a token (no $value)")
  let oldValue = text[valStart ..< valEnd]
  let encoded = escapeJson(newValue)
  result = (text[0 ..< valStart] & encoded & text[valEnd ..< text.len], oldValue)

# ---------------------------------------------------------------------------
# Validation guard: re-parse + re-resolve the whole token graph
# ---------------------------------------------------------------------------

proc validateTokenSet(files: openArray[DtcgFile]) =
  ## Builds the merged `TokenSet` from `files` and resolves EVERY token,
  ## forcing a `TokenError` for any dangling `{alias}` or reference cycle.
  ## Also surfaces a JSON parse failure. Raises `DtcgWriteError` on any
  ## corruption so the caller can abort before touching disk.
  var texts: seq[string]
  for f in files: texts.add f.text
  var ts: TokenSet
  try:
    ts = loadTokensFromStrings(texts)
  except JsonParsingError as e:
    raise newException(DtcgWriteError, "patched DTCG is not valid JSON: " & e.msg)
  except CatchableError as e:
    raise newException(DtcgWriteError, "patched DTCG failed to load: " & e.msg)
  for k in ts.keys:
    try:
      discard ts.resolve(k)
    except TokenError as e:
      raise newException(DtcgWriteError,
        "patched DTCG corrupts the token graph: " & e.msg)

# ---------------------------------------------------------------------------
# Public API: apply an edit over a layered DTCG file set
# ---------------------------------------------------------------------------

proc fileHoldingKey(files: openArray[DtcgFile]; dottedKey: string): int =
  ## Index of the file whose document defines `dottedKey`, or -1.
  for i, f in files:
    var ts: TokenSet
    try:
      ts = loadTokensFromStrings([f.text])
    except CatchableError:
      continue
    if ts.contains(dottedKey):
      return i
  -1

proc applyDtcgEdit*(files: openArray[DtcgFile]; dottedKey, newValue: string;
    dryRun = false): DtcgWriteResult =
  ## Applies `dottedKey := newValue` to whichever file in the layered set
  ## defines that token, VALIDATES the patched merged graph (re-parse +
  ## re-resolve), and -- unless `dryRun` -- flushes the patched file to disk.
  ##
  ## On any validation failure NOTHING is written and a `DtcgWriteError` is
  ## raised (the caller's files stay byte-for-byte intact). In dry-run mode
  ## the patched content is returned in `result.newText` without touching
  ## disk (the export mode).
  let idx = fileHoldingKey(files, dottedKey)
  if idx < 0:
    raise newException(DtcgWriteError,
      "no DTCG file in the set defines token '" & dottedKey & "'")
  let (patched, oldValue) = patchDtcgValue(files[idx].text, dottedKey, newValue)

  # Build the candidate set (target file replaced by its patched text) and
  # validate the WHOLE merged graph before committing.
  var candidate: seq[DtcgFile]
  for i, f in files:
    if i == idx: candidate.add DtcgFile(path: f.path, text: patched)
    else: candidate.add f
  validateTokenSet(candidate)

  result = DtcgWriteResult(
    targetPath: files[idx].path,
    newText: patched,
    oldValue: oldValue,
    newValue: escapeJson(newValue),
    changed: patched != files[idx].text,
    written: false,
    dryRun: dryRun)
  if not dryRun:
    writeFile(files[idx].path, patched)
    result.written = true

proc writeDtcgTokenValue*(path, dottedKey, newValue: string;
    dryRun = false): DtcgWriteResult =
  ## Convenience over `applyDtcgEdit` for a single self-contained DTCG file
  ## on disk: reads `path`, patches `dottedKey`, validates that file's own
  ## graph, and (unless `dryRun`) writes it back. Use `applyDtcgEdit` with
  ## the full layer set when the token's alias chain crosses files.
  let text = readFile(path)
  applyDtcgEdit([DtcgFile(path: path, text: text)], dottedKey, newValue, dryRun)

# ---------------------------------------------------------------------------
# SourceEditPlan bridge: editor edit -> DTCG dotted key
# ---------------------------------------------------------------------------

proc dtcgKeyForPlan*(plan: SourceEditPlan;
    tokens: seq[FoundationTokenEntry]): string =
  ## The DTCG dotted key a foundation-token `SourceEditPlan` should write to:
  ## the `aliasOf` head of the `FoundationTokenEntry` the plan names. Empty
  ## when the edited `--docs-*` variable is a docs-layer LITERAL (not backed
  ## by any DTCG token) -- such an edit has no DTCG write target.
  for t in tokens:
    if t.key == plan.tokenName or t.property == plan.property or
       t.schemaKey == plan.schemaKey:
      return t.aliasOf
  ""

proc applyDtcgEdit*(files: openArray[DtcgFile]; plan: SourceEditPlan;
    tokens: seq[FoundationTokenEntry]; dryRun = false): DtcgWriteResult =
  ## Persists an editor `SourceEditPlan` (from `editFoundationToken`) to the
  ## DTCG source: resolves the plan to its DTCG dotted key via the workspace
  ## `tokens` (their `aliasOf` chain heads), then delegates to the validated
  ## `applyDtcgEdit`. Raises `DtcgWriteError` if the plan targets a literal
  ## docs-layer binding with no DTCG backing.
  let key = dtcgKeyForPlan(plan, tokens)
  if key.len == 0:
    raise newException(DtcgWriteError,
      "SourceEditPlan for '" & plan.tokenName &
      "' is a docs-layer literal with no DTCG token to write")
  applyDtcgEdit(files, key, plan.newValue, dryRun)
