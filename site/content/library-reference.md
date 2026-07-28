---
title: Library API Reference
description: Nim source/docstring ingestion into a symbol reference model, stable per-symbol anchors, and the [[sym:...]] cross-reference syntax resolved by the reference checker.
order: 8
---
# Library API Reference

For documenting a Nim library, isonim-docs renders a source file as a
two-column symbol reference (`pkSymbolReference`): a left symbol index and a
center per-symbol reference (signature, docstring, pragmas, generics). The
documented `.nim` source is consumer-supplied and bound to a route -- the
framework parses it at build time.

## Parsing Nim source

`core/nimdoc.parseNimDoc` ingests Nim **source text** into a typed reference
model: the module doc, every exported type/proc/func/template/macro/iterator/
converter/method, their `##` docstrings, `{.pragmas.}`, generic parameters,
and signatures. It is a focused hand-written lexer over the source (not the
C-only Nim compiler API), so it runs on both backends, and -- like the
OpenAPI ingest -- it is tolerant: unparseable source yields `ok = false` with
errors rather than crashing.

A routine whose first parameter's base type is one of the module's own
exported types is grouped under that type (Nim's UFCS "method-like"
grouping), so `proc len2*(v: Vec2[T])` renders and anchors under `Vec2`:

```nim runnable
import std/[strutils, tables]
import core/nimdoc
import core/symbol_reference_vm

const source = """## Vector math.

type
  Vec2*[T] = object  ## A 2-D vector.
    x*, y*: T

proc len2*[T](v: Vec2[T]): T =
  ## The squared length of the vector.
  v.x * v.x + v.y * v.y
"""

let ingest = parseNimDoc(source, "vecmath")
doAssert ingest.ok
doAssert ingest.module.symbols.len == 2

let vm = buildSymbolReferenceViewModel(ingest)
# The proc is grouped under the type it operates on.
doAssert vm.symbols[1].displayName == "Vec2.len2"
```

## Symbol anchors and `[[sym:...]]` cross-references

Every exported symbol gets a stable, deep-linkable anchor (`sym-Vec2`,
`sym-Vec2.len2`) minted through the same anchor registry used for headings
and OpenAPI operations. Those anchors feed a global symbol index mapping
every query form -- the bare name, the dotted `Type.proc` form, and the
module-qualified `module.Type.proc` form -- to a `route#anchor` href:

```nim runnable
import std/[strutils, tables]
import core/nimdoc
import core/symbol_reference_vm

const source = """type
  Vec2*[T] = object
    x*, y*: T

proc len2*[T](v: Vec2[T]): T = v.x * v.x + v.y * v.y
"""

let ingest = parseNimDoc(source, "vecmath")
var index = initTable[string, string]()
addSymbolIndexEntries(index, ingest.module, "/api/vecmath")

doAssert index.hasKey("Vec2")               # bare name
doAssert index.hasKey("Vec2.len2")          # dotted form
doAssert index.hasKey("vecmath.Vec2.len2")  # module-qualified
doAssert index["Vec2"].startsWith("/api/vecmath#sym-")
```

A short cross-reference syntax lets prose link to a code symbol by name --
written as a `sym:` reference inside double brackets:

```markdown
See [[sym:Vec2.len2]] for the squared-length helper, or the
[[sym:vecmath.Vec2]] type it operates on.
```

The reference checker (`references.validateContentGraph`, described under
[Routing](./routing.md)) resolves every such reference against the symbol
index built from all `pkSymbolReference` pages. A reference to a symbol that
no page exports is flagged with its source file and line -- a broken symbol
link fails the build exactly like a broken page link, so the docs never ship
a dangling cross-reference. (This site declares no symbol-reference pages of
its own, so it shows the syntax above only as a code sample rather than a
live link.)
