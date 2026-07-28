## isonim-docs Layer 3 — Nim source/docstring ingestion (M8 deliverable 1).
##
## Parses Nim SOURCE text into a typed, filesystem-free reference model
## (module doc, exported type/proc/func/template/macro/iterator/converter
## definitions, their `##`/`##[ ]##` docstrings, `{.pragma.}`s, generic
## parameters `[T]`, and signatures) with TOLERANT error reporting: a
## malformed / unparseable source yields a typed `NimDocIngest` carrying
## `ok = false` and an `errors` seq, NEVER an unhandled raise that would
## abort a consumer's build (the exact contract `core/openapi.ingestOpenApi`
## follows for OpenAPI specs, M7 deliverable 1).
##
## DUAL-TARGET APPROACH (critical constraint, mirrors M7's YAML-subset
## parser): the Nim compiler API (`compiler/parser`, `compiler/ast`) is
## C-only and heavy, so it is NOT used here. Instead this is a focused,
## hand-rolled line/character lexer over the source text built purely on
## `std/strutils` (+ `std/[tables, sets]`), so BOTH the model AND the
## parsing compile and run identically under `nim c` and `nim js`. No
## `std/os`, no `staticRead`, no C-only import anywhere in this module --
## exactly like `core/openapi`, so `test_nimdoc_parse.nim` can exercise it
## on both backends against an embedded `const` fixture source.

import std/[strutils, sets]

type
  NimSymbolKind* = enum
    nskType
    nskProc
    nskFunc
    nskTemplate
    nskMacro
    nskIterator
    nskConverter
    nskMethod

  NimSymbol* = object
    ## One exported symbol extracted from the source. `signature` is the
    ## rendered declaration line (keyword..return type/pragmas, body
    ## stripped) a reference page shows verbatim; `ownerType` groups a
    ## routine under a type when its first parameter's base type is one of
    ## the module's own exported types (Nim's UFCS "method-like" grouping),
    ## so a `proc len2*(v: Vec2[T])` renders (and anchors) under `Vec2`.
    name*: string
    kind*: NimSymbolKind
    generics*: string        ## "[T]" including brackets, or "" if none
    signature*: string       ## full rendered declaration, body stripped
    docstring*: string       ## joined `##`/`##[ ]##` doc, or ""
    pragmas*: seq[string]    ## split contents of a trailing `{. ... .}`
    returnType*: string      ## after `):` for a routine, or ""
    ownerType*: string       ## grouping type name, or "" for a free symbol
    firstParamType*: string  ## base type of the first parameter (internal
                             ## seam for `ownerType` assignment; retained
                             ## for callers that want the raw value)

  NimModule* = object
    name*: string
    moduleDoc*: string
    symbols*: seq[NimSymbol]

  NimDocIngest* = object
    ## The tolerant result of ingesting a Nim source: `ok` is false and
    ## `errors` non-empty when parsing failed outright; `module` is still a
    ## well-formed (possibly empty) value either way, so a consumer can
    ## render an error notice without crashing.
    ok*: bool
    module*: NimModule
    errors*: seq[string]

const routineKeywords = ["proc", "func", "template", "macro", "iterator",
                          "converter", "method"]

proc moduleNameFromPath*(contentPath: string): string =
  ## The Nim module name a content path documents -- its final path
  ## segment with any `.nim` extension stripped (`api/vecmath.nim` ->
  ## `vecmath`), so a `[[sym:vecmath.Vec2]]` module-qualified cross-ref
  ## resolves. Pure string work (no `std/os`), dual-target by construction.
  var name = contentPath
  let slash = name.rfind('/')
  if slash >= 0: name = name[slash + 1 .. ^1]
  if name.endsWith(".nim"): name = name[0 ..< name.len - 4]
  name

# --- low-level lexing helpers --------------------------------------------

proc indentOf(line: string): int =
  var n = 0
  while n < line.len and line[n] == ' ': inc n
  n

proc routineKindOf(word: string): NimSymbolKind =
  case word
  of "func": nskFunc
  of "template": nskTemplate
  of "macro": nskMacro
  of "iterator": nskIterator
  of "converter": nskConverter
  of "method": nskMethod
  else: nskProc

proc codeOf(line: string): string =
  ## Returns `line` with any trailing/inline `#`/`##` comment removed,
  ## respecting `"..."` string and `'.'` char literals so a `#` inside a
  ## string (e.g. `"#/x"`) is NOT treated as a comment start. Backslash
  ## escapes inside a string are passed through so an escaped quote doesn't
  ## prematurely close the literal.
  var inStr = false
  var inChar = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if inStr:
      result.add c
      if c == '\\' and i + 1 < line.len:
        result.add line[i + 1]
        i += 2
        continue
      if c == '"': inStr = false
      inc i
    elif inChar:
      result.add c
      if c == '\\' and i + 1 < line.len:
        result.add line[i + 1]
        i += 2
        continue
      if c == '\'': inChar = false
      inc i
    else:
      if c == '#': break
      if c == '"': inStr = true
      elif c == '\'': inChar = true
      result.add c
      inc i

proc bracketDelta(code: string): int =
  for c in code:
    case c
    of '(', '[', '{': inc result
    of ')', ']', '}': dec result
    else: discard

proc docCommentText(stripped: string): string =
  ## `stripped` starts with `##` (a plain doc-comment line). Drops the
  ## marker and one following space.
  var s = stripped[2 .. ^1]
  if s.len > 0 and s[0] == ' ': s = s[1 .. ^1]
  s

proc collectDoc(lines: seq[string]; i: var int; minIndent: int; allowBlank: bool): string =
  ## Collects a run of consecutive doc-comment lines (`## ...` and
  ## `##[ ... ]##` blocks) at indent >= `minIndent`, starting at `lines[i]`
  ## and advancing `i` past them. With `allowBlank`, blank lines between
  ## doc paragraphs are tolerated (module docs); without it, the first
  ## blank or non-doc line ends the run (symbol docs are contiguous).
  var parts: seq[string] = @[]
  while i < lines.len:
    let raw = lines[i]
    let stripped = raw.strip()
    if stripped.len == 0:
      if allowBlank:
        parts.add ""
        inc i
        continue
      else:
        break
    if indentOf(raw) < minIndent: break
    if stripped.startsWith("##["):
      var head = stripped[3 .. ^1]
      let idx = head.find("]##")
      if idx >= 0:
        parts.add head[0 ..< idx].strip()
        inc i
      else:
        parts.add head.strip()
        inc i
        while i < lines.len and not lines[i].contains("]##"):
          parts.add lines[i].strip()
          inc i
        if i < lines.len:
          let l = lines[i]
          parts.add l[0 ..< l.find("]##")].strip()
          inc i
    elif stripped.startsWith("##"):
      parts.add docCommentText(stripped)
      inc i
    else:
      break
  while parts.len > 0 and parts[0].len == 0: parts.delete(0)
  while parts.len > 0 and parts[^1].len == 0: parts.setLen(parts.len - 1)
  parts.join("\n")

proc inlineDoc(rawLine: string): string =
  ## The `## ...` doc comment appended to the end of a declaration line
  ## (`Direction* = enum   ## Cardinal directions.`), or "" if none. Uses
  ## `codeOf` to find where the code ends without being fooled by a `#`
  ## inside a string literal.
  let code = codeOf(rawLine)
  if code.len >= rawLine.len: return ""
  let rest = rawLine[code.len .. ^1].strip()
  if rest.startsWith("##"): docCommentText(rest) else: ""

# --- identifier / type helpers -------------------------------------------

proc readIdent(s: string; i: var int): string =
  ## Reads a (possibly backtick-quoted operator) identifier from `s`
  ## starting at `i`, advancing `i` past it.
  while i < s.len and s[i] == ' ': inc i
  if i < s.len and s[i] == '`':
    inc i
    while i < s.len and s[i] != '`':
      result.add s[i]
      inc i
    if i < s.len: inc i
    return result
  while i < s.len and (s[i] in IdentChars):
    result.add s[i]
    inc i

proc readBalanced(s: string; i: var int; opening, closing: char): string =
  ## Reads a balanced `opening..closing` region (INCLUDING the delimiters)
  ## from `s` starting at the `opening` char, advancing `i` past it.
  if i >= s.len or s[i] != opening: return ""
  var depth = 0
  while i < s.len:
    let c = s[i]
    result.add c
    if c == opening: inc depth
    elif c == closing:
      dec depth
      if depth == 0:
        inc i
        break
    inc i

proc baseTypeName(t: string): string =
  ## The bare type identifier of a parameter type: strips a leading
  ## `var`/`ptr`/`ref`/`lent`/`sink`, any generic `[...]` args, and takes
  ## the leading identifier run -- so `var Vec2[T]` -> `Vec2`.
  var s = t.strip()
  for kw in ["var ", "ptr ", "ref ", "lent ", "sink "]:
    if s.startsWith(kw):
      s = s[kw.len .. ^1].strip()
  let br = s.find('[')
  if br >= 0: s = s[0 ..< br]
  for c in s:
    if c in IdentChars: result.add c
    else: break

proc splitTopLevel(s: string; seps: set[char]): seq[string] =
  ## Splits `s` on any separator in `seps` that sits at bracket depth 0.
  var depth = 0
  var cur = ""
  for c in s:
    case c
    of '(', '[', '{': inc depth; cur.add c
    of ')', ']', '}': dec depth; cur.add c
    else:
      if depth == 0 and c in seps:
        result.add cur
        cur = ""
      else:
        cur.add c
  result.add cur

proc firstParamBaseType(paramsStr: string): string =
  ## The base type of the first parameter, from a `(...)`-stripped param
  ## string like `a, b: Vec2[T]; scale: float = 1.0`.
  var inner = paramsStr.strip()
  if inner.len >= 2 and inner[0] == '(' and inner[^1] == ')':
    inner = inner[1 ..< inner.len - 1]
  if inner.strip().len == 0: return ""
  let firstGroup = splitTopLevel(inner, {';'})[0]
  let colon = firstGroup.find(':')
  if colon < 0: return ""
  var typePart = firstGroup[colon + 1 .. ^1]
  let eq = typePart.find('=')
  if eq >= 0: typePart = typePart[0 ..< eq]
  baseTypeName(typePart)

# --- signature parsing ----------------------------------------------------

proc parseRoutineSignature(sig: string): tuple[ok: bool, sym: NimSymbol] =
  ## Parses a body-stripped routine declaration
  ## (`proc name*[G](params): Ret {.prag.}`) into a `NimSymbol`. Returns
  ## `ok = false` when the routine isn't exported (no trailing `*` on the
  ## name) -- unexported symbols are intentionally excluded from the model.
  var s = sig.strip()
  var i = 0
  let keyword = readIdent(s, i)
  if keyword notin routineKeywords: return (false, NimSymbol())
  var sym = NimSymbol(kind: routineKindOf(keyword))
  sym.name = readIdent(s, i)
  if sym.name.len == 0: return (false, NimSymbol())
  # exported iff a '*' immediately follows the name
  while i < s.len and s[i] == ' ': inc i
  if i < s.len and s[i] == '*':
    inc i
  else:
    return (false, NimSymbol())   # not exported
  # generics [..]
  while i < s.len and s[i] == ' ': inc i
  if i < s.len and s[i] == '[':
    sym.generics = readBalanced(s, i, '[', ']')
  # params (..)
  while i < s.len and s[i] == ' ': inc i
  var paramsStr = ""
  if i < s.len and s[i] == '(':
    paramsStr = readBalanced(s, i, '(', ')')
  sym.firstParamType = firstParamBaseType(paramsStr)
  # return type: after ')' up to a '{' pragma
  while i < s.len and s[i] == ' ': inc i
  if i < s.len and s[i] == ':':
    inc i
    var ret = ""
    while i < s.len and s[i] != '{':
      ret.add s[i]
      inc i
    sym.returnType = ret.strip()
  # pragmas {. .}
  let pragBrace = s.find("{.")
  if pragBrace >= 0:
    let pragEnd = s.find(".}", pragBrace)
    if pragEnd >= 0:
      let inner = s[pragBrace + 2 ..< pragEnd]
      for p in inner.split(','):
        let t = p.strip()
        if t.len > 0: sym.pragmas.add t
  sym.signature = sig.strip()
  (true, sym)

proc parseTypeDef(defText: string): tuple[ok: bool, sym: NimSymbol] =
  ## Parses a single type definition (`Vec2*[T] = object`,
  ## `Direction* = enum`, `Id* = distinct int`) into a `NimSymbol`. Returns
  ## `ok = false` for an unexported type.
  var s = defText.strip()
  var i = 0
  var sym = NimSymbol(kind: nskType)
  sym.name = readIdent(s, i)
  if sym.name.len == 0: return (false, NimSymbol())
  while i < s.len and s[i] == ' ': inc i
  if i < s.len and s[i] == '*':
    inc i
  else:
    return (false, NimSymbol())
  # optional pragma right after the name, e.g. `Foo* {.pure.} = enum`
  while i < s.len and s[i] == ' ': inc i
  if i + 1 < s.len and s[i] == '{' and s[i + 1] == '.':
    let pragEnd = s.find(".}", i)
    if pragEnd >= 0:
      let inner = s[i + 2 ..< pragEnd]
      for p in inner.split(','):
        let t = p.strip()
        if t.len > 0: sym.pragmas.add t
      i = pragEnd + 2
  while i < s.len and s[i] == ' ': inc i
  if i < s.len and s[i] == '[':
    sym.generics = readBalanced(s, i, '[', ']')
  # rhs head (after '='): object/enum/tuple/... -- a short display hint
  let eq = s.find('=')
  var rhs = if eq >= 0: s[eq + 1 .. ^1].strip() else: ""
  sym.signature = "type " & sym.name & sym.generics &
    (if rhs.len > 0: " = " & rhs else: "")
  (true, sym)

# --- top-level parse ------------------------------------------------------

proc looksLikeTypeDef(code: string): bool =
  ## A `type`-section member line that opens a new type definition (has a
  ## top-level `=`), as opposed to a field/enum-value continuation line.
  let s = code.strip()
  if s.len == 0: return false
  if not (s[0] in {'a'..'z', 'A'..'Z', '_', '`'}): return false
  var depth = 0
  for c in s:
    case c
    of '(', '[', '{': inc depth
    of ')', ']', '}': dec depth
    of '=':
      if depth == 0: return true
    else: discard
  false

proc parseNimDoc*(source: string; moduleName: string = ""): NimDocIngest =
  ## Ingests Nim `source` into the typed reference model. Tolerant by
  ## contract: any failure yields `ok = false` with a populated `errors`
  ## seq -- this proc NEVER lets an exception escape, so unparseable source
  ## flags the build instead of aborting it.
  var module = NimModule(name: moduleName)
  var errors: seq[string] = @[]
  try:
    let lines = source.splitLines()
    var i = 0
    # module doc: the leading `##`/`##[ ]##` block before any code.
    while i < lines.len and lines[i].strip().len == 0: inc i
    if i < lines.len and lines[i].strip().startsWith("##"):
      module.moduleDoc = collectDoc(lines, i, 0, true)

    i = 0
    while i < lines.len:
      let raw = lines[i]
      let code = codeOf(raw)
      let stripped = code.strip()
      if stripped.len == 0:
        inc i
        continue

      # --- type block(s) ---
      if stripped == "type" or stripped.startsWith("type "):
        let typeIndent = indentOf(raw)
        if stripped.startsWith("type ") and looksLikeTypeDef(stripped[5 .. ^1]):
          # single-line `type Foo* = ...`
          let (ok, sym) = parseTypeDef(stripped[5 .. ^1])
          if ok:
            var s = sym
            let inl = inlineDoc(raw)
            if inl.len > 0: s.docstring = inl
            module.symbols.add s
          inc i
          continue
        # block `type` on its own line
        inc i
        var memberIndent = -1
        while i < lines.len:
          let mraw = lines[i]
          let mcode = codeOf(mraw)
          let mstripped = mcode.strip()
          if mstripped.len == 0:
            inc i
            continue
          let ind = indentOf(mraw)
          if ind <= typeIndent: break        # left the type block
          if memberIndent < 0: memberIndent = ind
          if ind == memberIndent and looksLikeTypeDef(mstripped):
            let (ok, sym) = parseTypeDef(mstripped)
            if ok:
              var s = sym
              let inl = inlineDoc(mraw)
              if inl.len > 0:
                s.docstring = inl
                inc i
              else:
                inc i
                s.docstring = collectDoc(lines, i, memberIndent + 1, false)
              module.symbols.add s
            else:
              inc i
          else:
            inc i                            # a field / enum-value line
        continue

      # --- routine ---
      var firstWordEnd = 0
      while firstWordEnd < stripped.len and stripped[firstWordEnd] in IdentChars:
        inc firstWordEnd
      let firstWord = stripped[0 ..< firstWordEnd]
      if firstWord in routineKeywords:
        let declIndent = indentOf(raw)
        # gather the (possibly multi-line) header up to the body `=`
        var headerParts: seq[string] = @[]
        var depth = 0
        var j = i
        while j < lines.len:
          let jcode = codeOf(lines[j])
          headerParts.add jcode.strip()
          depth += bracketDelta(jcode)
          let trimmed = jcode.strip()
          if depth <= 0 and not trimmed.endsWith(",") and not trimmed.endsWith("("):
            break
          inc j
        var header = headerParts.join(" ").strip()
        # cut the body: the first top-level '=' that begins the routine body
        var bodyEq = -1
        var d = 0
        var k = 0
        while k < header.len:
          let c = header[k]
          case c
          of '(', '[', '{': inc d
          of ')', ']', '}': dec d
          of '=':
            if d == 0 and (k + 1 >= header.len or header[k + 1] != '='):
              if k == 0 or header[k - 1] notin {'=', '<', '>', '!'}:
                bodyEq = k
          else: discard
          if bodyEq >= 0: break
          inc k
        let sig = if bodyEq >= 0: header[0 ..< bodyEq].strip() else: header
        let (ok, sym) = parseRoutineSignature(sig)
        i = j + 1
        if ok:
          var s = sym
          # doc: inline on the header line, else the body's leading `##`
          let inl = inlineDoc(lines[j])
          if inl.len > 0:
            s.docstring = inl
          else:
            s.docstring = collectDoc(lines, i, declIndent + 1, false)
          module.symbols.add s
        continue

      inc i

    # second pass: group routines under a matching exported type
    var typeNames = initHashSet[string]()
    for s in module.symbols:
      if s.kind == nskType: typeNames.incl s.name
    for idx in 0 ..< module.symbols.len:
      if module.symbols[idx].kind != nskType:
        let ft = module.symbols[idx].firstParamType
        if ft.len > 0 and ft in typeNames:
          module.symbols[idx].ownerType = ft

    result = NimDocIngest(ok: true, module: module, errors: @[])
  except CatchableError as e:
    result = NimDocIngest(ok: false, module: module,
                          errors: @["failed to parse Nim source: " & e.msg])
  except:
    result = NimDocIngest(ok: false, module: module,
                          errors: @["failed to parse Nim source: " & getCurrentExceptionMsg()])
