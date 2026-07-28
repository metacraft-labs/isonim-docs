## isonim-docs Layer 3 -- generic compile-time content-dir embed.
##
## M1 corrective deliverable 3: a JS-target shell (`main_web.nim`) has no
## real filesystem, so every content file it can serve has to be baked
## into the compiled bundle at compile time. Before this module, that
## embed was a hand-maintained `staticRead` call per file -- one that had
## to be updated by hand for every page added/renamed/removed, and could
## silently drift out of sync with the real content dir. `embedContentDir`
## replaces that hand list with a real compile-time directory walk: any
## content dir (the framework's own fixtures today, a consumer's real
## content dir once one exists) can be embedded by pointing this macro at
## it, with zero per-file registration.
##
## The walk itself is done via `staticExec("find ...")` rather than
## `std/os`'s `walkDirRec`/`relativePath`: those pick their real
## implementation based on the *target* backend's active defines
## (`-d:nodejs` for `nim js`), and their `nodejs` branch emits raw JS
## calling into `require("path")` -- code the compile-time VM this macro
## runs in can't execute (there is no JS host during compilation, only
## during `nim js -r`'s later `node` step). `staticExec` always runs a
## real host shell command at compile time regardless of the target
## being compiled for, so it works identically for `nim c` and `nim js`.

import std/[macros, os, strutils, algorithm, tables]

macro embedContentDir*(dirPath: static string; ext: static string = ".md"): untyped =
  ## Expands to `{relPath: staticRead(absPath), ...}.toTable`, one entry
  ## per real file under `dirPath` (recursive) whose name ends in `ext`.
  ## `relPath` uses forward slashes regardless of host OS, matching
  ## `content.deriveRoutePath`'s own path convention, so a key here looks
  ## up the exact same way a real filesystem content path would.
  let dir = dirPath.strip(leading = false, chars = {'/'})
  let listing = staticExec("find " & dir.quoteShellPosix & " -type f -name " & ("*" & ext).quoteShellPosix)
  var relPaths: seq[string] = @[]
  var absByRel = initTable[string, string]()
  for rawLine in listing.splitLines():
    let path = rawLine.strip()
    if path.len == 0: continue
    var rel = path
    if rel.startsWith(dir & "/"):
      rel = rel[(dir.len + 1) .. ^1]
    relPaths.add rel
    absByRel[rel] = path
  relPaths.sort()
  if relPaths.len == 0:
    ## No matching files (e.g. a content dir with no `.yaml` spec): emit a
    ## properly-typed empty `Table[string, string]` rather than an untyped
    ## empty `{}` table constructor, which `toTable` can't instantiate.
    return newCall(nnkBracketExpr.newTree(bindSym"initTable", ident"string", ident"string"))
  var tbl = newNimNode(nnkTableConstr)
  for rel in relPaths:
    tbl.add newTree(nnkExprColonExpr, newLit(rel),
      newCall(bindSym"staticRead", newLit(absByRel[rel])))
  result = newCall(bindSym"toTable", tbl)
