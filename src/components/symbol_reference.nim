## isonim-docs Layer 2 — rendering for the symbol reference ViewModel
## (`src/core/symbol_reference_vm.nim`, M8 deliverable 1).
##
## A two-column library API reference layout: LEFT symbol index nav (every
## exported symbol, kind-tagged), CENTER per-symbol reference (signature,
## docstring, pragmas), each center section carrying its stable deep-link
## anchor id (M8 deliverable 2). Like `api_reference.nim`/`markdown_view.nim`,
## the tree is variable-length and can't be a static `ui(...)` DSL tree, so
## every renderer below is written directly against the generic backend API
## (`createElement`/`appendChild`/`setAttribute`/`createTextNode`) for the
## Mock/browser side and plain escaped string building (`isonim/ssr/escape`)
## for the SSR side -- the two kept byte-for-byte in lock-step (dual-target
## parity, a HARD CONSTRAINT of M8), exactly as every other component pairs
## its `renderX`/`renderXHtml`.

import std/strutils
import isonim/ssr/escape
import ../core/symbol_reference_vm

const
  symLayoutClass* = "docs-sym-layout"
  symNavClass* = "docs-sym-nav"
  symNavListClass* = "docs-sym-nav-list"
  symNavLinkClass* = "docs-sym-nav-link"
  symNavKindClass* = "docs-sym-nav-kind"
  symContentClass* = "docs-sym-content"
  symModuleDocClass* = "docs-sym-module-doc"
  symEntryClass* = "docs-sym-entry"
  symEntryTitleClass* = "docs-sym-entry-title"
  symKindClass* = "docs-sym-kind"
  symNameClass* = "docs-sym-name"
  symSignatureClass* = "docs-sym-signature"
  symDocClass* = "docs-sym-doc"
  symPragmasClass* = "docs-sym-pragmas"
  symErrorClass* = "docs-sym-errors"
  symAnchorAttr* = "data-sym-anchor"   ## on each center section
  symTargetAttr* = "data-sym-target"   ## on each left-nav link

# --- MockRenderer / browser tree mode -----------------------------------

proc renderSymNav[R, E](r: R; vm: SymbolReferenceViewModel): E =
  let navEl = r.createElement("nav")
  r.setAttribute(navEl, "class", symNavClass)
  r.setAttribute(navEl, "aria-label", "Symbols")
  let list = r.createElement("ul")
  r.setAttribute(list, "class", symNavListClass)
  for e in vm.navEntries:
    let li = r.createElement("li")
    let a = r.createElement("a")
    r.setAttribute(a, "class", symNavLinkClass)
    r.setAttribute(a, "href", "#" & e.anchorId)
    r.setAttribute(a, symTargetAttr, e.anchorId)
    let kindSpan = r.createElement("span")
    r.setAttribute(kindSpan, "class", symNavKindClass)
    r.appendChild(kindSpan, r.createTextNode(e.kindLabel))
    r.appendChild(a, kindSpan)
    let nameSpan = r.createElement("span")
    r.setAttribute(nameSpan, "class", symNameClass)
    r.appendChild(nameSpan, r.createTextNode(e.displayName))
    r.appendChild(a, nameSpan)
    r.appendChild(li, a)
    r.appendChild(list, li)
  r.appendChild(navEl, list)
  navEl

proc renderSymEntry[R, E](r: R; sym: SymbolEntryViewModel): E =
  let section = r.createElement("section")
  r.setAttribute(section, "class", symEntryClass)
  r.setAttribute(section, "id", sym.anchorId)
  r.setAttribute(section, symAnchorAttr, sym.anchorId)

  let h2 = r.createElement("h2")
  r.setAttribute(h2, "class", symEntryTitleClass)
  let kindSpan = r.createElement("span")
  r.setAttribute(kindSpan, "class", symKindClass)
  r.appendChild(kindSpan, r.createTextNode(sym.kindLabel))
  r.appendChild(h2, kindSpan)
  let nameSpan = r.createElement("span")
  r.setAttribute(nameSpan, "class", symNameClass)
  r.appendChild(nameSpan, r.createTextNode(sym.displayName))
  r.appendChild(h2, nameSpan)
  r.appendChild(section, h2)

  let pre = r.createElement("pre")
  r.setAttribute(pre, "class", symSignatureClass)
  let code = r.createElement("code")
  r.setAttribute(code, "class", "language-nim")
  r.appendChild(code, r.createTextNode(sym.signature))
  r.appendChild(pre, code)
  r.appendChild(section, pre)

  if sym.pragmas.len > 0:
    let p = r.createElement("p")
    r.setAttribute(p, "class", symPragmasClass)
    r.appendChild(p, r.createTextNode("Pragmas: " & sym.pragmas.join(", ")))
    r.appendChild(section, p)

  if sym.docstring.len > 0:
    let doc = r.createElement("p")
    r.setAttribute(doc, "class", symDocClass)
    r.appendChild(doc, r.createTextNode(sym.docstring))
    r.appendChild(section, doc)
  section

proc renderSymbolReference*[R, E](r: R; vm: SymbolReferenceViewModel): E =
  ## The full two-column symbol reference tree: one `docs-sym-layout`
  ## container holding the left symbol-index nav and the center content
  ## column (one `<section>` per symbol, each carrying its stable anchor id).
  let layout = r.createElement("div")
  r.setAttribute(layout, "class", symLayoutClass)

  if vm.errors.len > 0:
    let errBox = r.createElement("div")
    r.setAttribute(errBox, "class", symErrorClass)
    r.appendChild(errBox, r.createTextNode("This Nim source could not be fully parsed: " &
      vm.errors.join("; ")))
    r.appendChild(layout, errBox)

  r.appendChild(layout, renderSymNav[R, E](r, vm))

  let content = r.createElement("div")
  r.setAttribute(content, "class", symContentClass)
  if vm.moduleDoc.len > 0:
    let md = r.createElement("p")
    r.setAttribute(md, "class", symModuleDocClass)
    r.appendChild(md, r.createTextNode(vm.moduleDoc))
    r.appendChild(content, md)
  for sym in vm.symbols:
    r.appendChild(content, renderSymEntry[R, E](r, sym))
  r.appendChild(layout, content)
  layout

# --- SSR string mode ------------------------------------------------------

proc symNavHtml(vm: SymbolReferenceViewModel): string =
  result = "<nav class=\"" & symNavClass & "\" aria-label=\"Symbols\"><ul class=\"" &
    symNavListClass & "\">"
  for e in vm.navEntries:
    result.add "<li><a class=\"" & symNavLinkClass & "\" href=\"#" & escapeAttr(e.anchorId) &
      "\" " & symTargetAttr & "=\"" & escapeAttr(e.anchorId) & "\">" &
      "<span class=\"" & symNavKindClass & "\">" & escapeHtml(e.kindLabel) & "</span>" &
      "<span class=\"" & symNameClass & "\">" & escapeHtml(e.displayName) & "</span></a></li>"
  result.add "</ul></nav>"

proc symEntryHtml(sym: SymbolEntryViewModel): string =
  result = "<section class=\"" & symEntryClass & "\" id=\"" & escapeAttr(sym.anchorId) &
    "\" " & symAnchorAttr & "=\"" & escapeAttr(sym.anchorId) & "\">"
  result.add "<h2 class=\"" & symEntryTitleClass & "\">" &
    "<span class=\"" & symKindClass & "\">" & escapeHtml(sym.kindLabel) & "</span>" &
    "<span class=\"" & symNameClass & "\">" & escapeHtml(sym.displayName) & "</span></h2>"
  result.add "<pre class=\"" & symSignatureClass & "\"><code class=\"language-nim\">" &
    escapeHtml(sym.signature) & "</code></pre>"
  if sym.pragmas.len > 0:
    result.add "<p class=\"" & symPragmasClass & "\">Pragmas: " &
      escapeHtml(sym.pragmas.join(", ")) & "</p>"
  if sym.docstring.len > 0:
    result.add "<p class=\"" & symDocClass & "\">" & escapeHtml(sym.docstring) & "</p>"
  result.add "</section>"

proc renderSymbolReferenceHtml*(vm: SymbolReferenceViewModel): string =
  ## SSR string-mode rendering -- byte-for-byte the same shape/order as
  ## `renderSymbolReference`.
  result = "<div class=\"" & symLayoutClass & "\">"
  if vm.errors.len > 0:
    result.add "<div class=\"" & symErrorClass & "\">This Nim source could not be fully parsed: " &
      escapeHtml(vm.errors.join("; ")) & "</div>"
  result.add symNavHtml(vm)
  result.add "<div class=\"" & symContentClass & "\">"
  if vm.moduleDoc.len > 0:
    result.add "<p class=\"" & symModuleDocClass & "\">" & escapeHtml(vm.moduleDoc) & "</p>"
  for sym in vm.symbols:
    result.add symEntryHtml(sym)
  result.add "</div>"
  result.add "</div>"
