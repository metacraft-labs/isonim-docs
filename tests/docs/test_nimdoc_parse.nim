## Tier 1 (pure parser/model) M8 Nim-doc ingestion suite -- DUAL-TARGET
## (`nim c -r` AND `nim js -r`).
##
## Proves M8 deliverable 1: `core/nimdoc.parseNimDoc` parses Nim SOURCE
## into a typed module/type/proc reference model -- extracting docstrings
## (`##` line docs), pragmas (`{.….}`), type definitions, and
## proc/func signatures INCLUDING generics (`[T]`) and return types,
## keeping only EXPORTED (trailing `*`) symbols -- and
## `core/symbol_reference_vm` builds a symbol index (query -> anchor href)
## over it, all reporting a malformed source as a typed error rather than
## crashing.
##
## DUAL-TARGET NOTE: the fixture Nim source is embedded as a `const` string
## (no `std/os` file read), so the exact same parsing runs on BOTH the C
## and JS backends -- `core/nimdoc` is pure `std/[strutils, sets]`, both
## dual-target, so there is no C-only split to guard. (The renderRoute
## suite, `test_symbol_reference_renderroute.nim`, exercises the real
## filesystem Nim-source read on the C target.)

import std/[unittest, tables, strutils]
import ../../src/core/nimdoc
import ../../src/core/symbol_reference_vm

const vecmathSource = """
## Vector math utilities.
##
## A small module for demonstration purposes.

import std/math

type
  Vec2*[T] = object   ## A 2D vector generic over its component type.
    x*: T
    y*: T

  Direction* = enum   ## Cardinal compass directions.
    dNorth
    dSouth

  Meters* = distinct float   ## A distance in meters.

proc len2*[T](v: Vec2[T]): T =
  ## Returns the squared length of the vector.
  v.x * v.x + v.y * v.y

func add*[T](a, b: Vec2[T]): Vec2[T] {.inline.} =
  ## Adds two vectors component-wise.
  Vec2[T](x: a.x + b.x, y: a.y + b.y)

proc origin*(): Vec2[float] =
  ## Returns the zero vector. A free function (no owner type).
  Vec2[float](x: 0.0, y: 0.0)

proc internalHelper(x: int): int =
  ## Not exported; must be excluded from the model.
  x + 1
"""

proc findSym(module: NimModule; name: string): NimSymbol =
  for s in module.symbols:
    if s.name == name: return s
  raise newException(ValueError, "symbol not found: " & name)

suite "Nim source/docstring ingestion (Tier 1, dual-target)":
  test "parses the module doc, types, and routines from a fixture source":
    let ingest = parseNimDoc(vecmathSource, "vecmath")
    check ingest.ok
    check ingest.errors.len == 0
    let m = ingest.module
    check m.name == "vecmath"
    check m.moduleDoc.contains("Vector math utilities.")
    check m.moduleDoc.contains("A small module for demonstration purposes.")

    # exported symbols only -- internalHelper (no trailing '*') is excluded
    var names: seq[string] = @[]
    for s in m.symbols: names.add s.name
    check "internalHelper" notin names
    check names == @["Vec2", "Direction", "Meters", "len2", "add", "origin"]

  test "extracts type definitions with their docstrings and generics":
    let m = parseNimDoc(vecmathSource, "vecmath").module
    let vec2 = findSym(m, "Vec2")
    check vec2.kind == nskType
    check vec2.generics == "[T]"
    check vec2.docstring == "A 2D vector generic over its component type."
    check vec2.signature.contains("object")

    let dir = findSym(m, "Direction")
    check dir.kind == nskType
    check dir.docstring == "Cardinal compass directions."

    let meters = findSym(m, "Meters")
    check meters.signature.contains("distinct float")

  test "extracts a GENERIC proc's signature, docstring, and return type":
    let m = parseNimDoc(vecmathSource, "vecmath").module
    let len2 = findSym(m, "len2")
    check len2.kind == nskProc
    check len2.generics == "[T]"           # generic proc, per the milestone
    check len2.returnType == "T"
    check len2.docstring == "Returns the squared length of the vector."
    check len2.signature == "proc len2*[T](v: Vec2[T]): T"
    # grouped under its first-parameter type
    check len2.ownerType == "Vec2"

  test "extracts pragmas and groups a func under its owner type":
    let m = parseNimDoc(vecmathSource, "vecmath").module
    let add = findSym(m, "add")
    check add.kind == nskFunc
    check add.generics == "[T]"
    check add.pragmas == @["inline"]
    check add.ownerType == "Vec2"

  test "a free routine (no matching first-param type) has no owner":
    let m = parseNimDoc(vecmathSource, "vecmath").module
    let origin = findSym(m, "origin")
    check origin.ownerType == ""
    check origin.returnType == "Vec2[float]"

  test "builds a symbol index of query -> anchor href for cross-references":
    let ingest = parseNimDoc(vecmathSource, "vecmath")
    var index = initTable[string, string]()
    addSymbolIndexEntries(index, ingest.module, "/api/vecmath")

    # bare and module-qualified type/proc queries all resolve
    check index.hasKey("Vec2")
    check index["Vec2"] == "/api/vecmath#sym-Vec2"
    check index.hasKey("vecmath.Vec2")
    check index.hasKey("Vec2.len2")
    check index["Vec2.len2"] == "/api/vecmath#sym-Vec2.len2"
    check index.hasKey("vecmath.Vec2.len2")
    check index.hasKey("origin")
    # an unexported symbol never appears in the index
    check (not index.hasKey("internalHelper"))

  test "symbolAnchorIds preserves symbol case and dotted owner form":
    let m = parseNimDoc(vecmathSource, "vecmath").module
    let ids = symbolAnchorIds(m)
    check "sym-Vec2" in ids
    check "sym-Vec2.len2" in ids
    check "sym-Vec2.add" in ids
    check "sym-origin" in ids

  test "malformed / empty source is tolerant: never crashes, still ok-typed":
    # a stray unterminated construct must not raise
    let weird = parseNimDoc("proc (((", "broken")
    check weird.ok               # parser degrades gracefully, no raise
    let empty = parseNimDoc("", "empty")
    check empty.ok
    check empty.module.symbols.len == 0
