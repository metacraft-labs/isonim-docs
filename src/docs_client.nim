## isonim-docs -- shared progressive-enhancement client for static MPA sites.
##
## Wires interactive behaviour onto SSR/SSG-rendered markup without replacing
## the server-rendered DOM:
##   1. `:::tabs` switching (click + ArrowLeft/ArrowRight/Home/End ARIA keys)
##   2. `Copy code` clipboard button (`navigator.clipboard.writeText` + reset)
##   3. Collapsible sidebar sections persisted in `localStorage`
##   4. `<768px` mobile hamburger navigation drawer with focus trap + `Escape`
##   5. `#docs-theme-toggle` dark/light mode switch persisted in `localStorage`
##   6. `#docs-search-input` live search + `/` or `Cmd/Ctrl+K` focus + `Escape`
##
## A consumer's `src/main.nim` becomes:
##   import docs_client
##   when isMainModule:
##     mountStaticDocsClient(siteSearchIndex())

when not defined(js):
  {.error: "docs_client.nim requires the JS backend: nim js".}

import std/strutils
import isonim/web/dom_api
import isonim/web/web_renderer
import ./core/search_vm
import ./core/theme_vm
import ./components/markdown_view
import ./components/navigation_view
import ./components/search_view
import ./components/theme_toggle

export WebRenderer

proc isNodeNil*(n: Node): bool {.importcpp: "(# == null)".}
proc elemIsNil(e: Element): bool {.importcpp: "(# == null)".}
proc attrOrEmpty(e: Element; name: cstring): cstring {.importcpp: "(#.getAttribute(#) || '')".}
proc removeAttrSafe(e: Element; name: cstring) {.importcpp:
  "(function(el, n){if(el && el.removeAttribute) el.removeAttribute(n);})(#, #)".}
proc focusElement(e: Element) {.importcpp:
  "(function(el){if(el && el.focus) el.focus();})(#)".}
proc getInputValue(e: Element): cstring {.importcpp: "(#.value || '')".}
proc eventKey(e: Event): cstring {.importcpp: "(#.key || '')".}
proc eventShiftKey(e: Event): bool {.importcpp: "(!!#.shiftKey)".}
proc eventMetaOrCtrl(e: Event): bool {.importcpp:
  "(function(ev){return !!(ev && (ev.metaKey || ev.ctrlKey));})(#)".}
proc eventPreventDefault(e: Event) {.importcpp:
  "(function(ev){if(ev && ev.preventDefault) ev.preventDefault();})(#)".}
proc navigateTo(path: cstring) {.importcpp:
  "(typeof window !== 'undefined' && window.location && (window.location.href = #))".}
proc documentElement(d: Document): Element {.importcpp: "#.documentElement".}
proc documentBody*(d: Document): Element {.importcpp: "#.body".}
proc documentActiveElement(): Element {.importcpp:
  "((typeof document !== 'undefined' && document.activeElement) ? document.activeElement : null)".}
proc sameNode(a, b: Node): bool {.importcpp: "(# === #)".}
proc localStorageGetItem(key: cstring): cstring {.importcpp:
  "(function(){try{var v=localStorage.getItem(#);return (v===null||v===undefined)?'':v;}catch(e){return '';}})()".}
proc localStorageSetItem(key, value: cstring) {.importcpp:
  "(function(){try{localStorage.setItem(#, #);}catch(e){}})()".}
proc prefersDarkColorScheme(): bool {.importcpp:
  "(function(){try{return typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches === true;}catch(e){return false;}})()".}
proc writeClipboardText(text: cstring) {.importcpp:
  "(function(){try{if(typeof navigator!=='undefined'&&navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(#).catch(function(){});}}catch(e){}})()".}
proc scheduleTimeout(cb: proc() {.closure.}; ms: int) {.importcpp:
  "(function(){try{setTimeout(#, #);}catch(e){}})()".}

proc hasExactClass*(e: Element; cls: cstring): bool {.importcpp: """
(function(el, c){
  var raw = (el.getAttribute && el.getAttribute('class')) || el.className || '';
  var parts = String(raw).split(/\s+/);
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] === c) return true;
  }
  return false;
})(#, #)""".}

proc findAllElementsByClass*(root: Node; cls: cstring): seq[Element] =
  if root.isNodeNil: return
  if root.nodeType == 1:
    let el = Element(root)
    if hasExactClass(el, cls):
      result.add el
  for child in root.childNodes:
    result.add findAllElementsByClass(child, cls)

# --- 1. :::tabs (click + ArrowLeft/ArrowRight/Home/End) --------------------

proc wireTabs[R](r: R; tabsWrapper: Element) =
  let tabs = findAllElementsByClass(Node(tabsWrapper), cstring(tabClass))
  let panels = findAllElementsByClass(Node(tabsWrapper), cstring(tabpanelClass))
  if tabs.len == 0 or panels.len != tabs.len: return

  proc activate(idx: int; moveFocus: bool) =
    for i in 0 ..< tabs.len:
      let selected = i == idx
      setAttribute(tabs[i], "aria-selected", cstring(if selected: "true" else: "false"))
      setAttribute(tabs[i], "tabindex", cstring(if selected: "0" else: "-1"))
      if selected: removeAttrSafe(panels[i], "hidden")
      else: setAttribute(panels[i], "hidden", "hidden")
    if moveFocus: focusElement(tabs[idx])

  for i in 0 ..< tabs.len:
    let idx = i
    proc onClick(ev: Event) = activate(idx, false)
    proc onKeydown(ev: Event) =
      case $eventKey(ev)
      of "ArrowRight":
        eventPreventDefault(ev)
        activate((idx + 1) mod tabs.len, true)
      of "ArrowLeft":
        eventPreventDefault(ev)
        activate((idx - 1 + tabs.len) mod tabs.len, true)
      of "Home":
        eventPreventDefault(ev)
        activate(0, true)
      of "End":
        eventPreventDefault(ev)
        activate(tabs.len - 1, true)
      else: discard
    r.addEventListener(tabs[idx], "click", onClick)
    r.addEventListener(tabs[idx], "keydown", onKeydown)

proc wireTabsInteractivity*[R](r: R; root: Node) =
  for tabsWrapper in findAllElementsByClass(root, cstring(tabsClass)):
    wireTabs(r, tabsWrapper)

# --- 2. Copy code button ---------------------------------------------------

const codeCopyResetDelayMs = 1500

proc wireCodeCopyButton[R](r: R; wrapper: Element) =
  let btnNode = Node(wrapper).firstChild
  if btnNode.isNodeNil: return
  let preNode = btnNode.nextSibling
  if preNode.isNodeNil: return
  let codeNode = preNode.firstChild
  if codeNode.isNodeNil: return
  let btn = Element(btnNode)

  proc resetLabel() =
    setAttribute(btn, "data-copied", "false")
    setAttribute(btn, "aria-label", cstring(codeCopyIdleLabel))
    btnNode.textContent = cstring(codeCopyIdleLabel)

  proc onClick(ev: Event) =
    let text = codeNode.textContent
    writeClipboardText(text)
    setAttribute(btn, "data-copied", "true")
    setAttribute(btn, "aria-label", cstring(codeCopyCopiedLabel))
    btnNode.textContent = cstring(codeCopyCopiedLabel)
    scheduleTimeout(resetLabel, codeCopyResetDelayMs)

  r.addEventListener(btn, "click", onClick)

proc wireCodeCopyInteractivity*[R](r: R; root: Node) =
  for wrapper in findAllElementsByClass(root, cstring(codeBlockClass)):
    wireCodeCopyButton(r, wrapper)

# --- 3. Sidebar section collapse with localStorage persistence -------------

const navExpandedStoragePrefix = "docs-nav-expanded:"

proc wireSidebarSectionToggle[R](r: R; toggle: Element) =
  let sectionNode = Node(toggle).parentNode
  if sectionNode.isNodeNil: return
  let sectionEl = Element(sectionNode)
  let navKey = $attrOrEmpty(sectionEl, "data-nav-key")
  let storageKey = cstring(navExpandedStoragePrefix & navKey)

  proc applyOpen(open: bool) =
    setAttribute(sectionEl, "class",
      cstring(if open: sidebarSectionClass & " " & sidebarSectionExpandedClass else: sidebarSectionClass))
    setAttribute(toggle, "aria-expanded", cstring(if open: "true" else: "false"))

  if navKey.len > 0:
    let stored = $localStorageGetItem(storageKey)
    if stored == "true": applyOpen(true)
    elif stored == "false": applyOpen(false)

  proc onClick(ev: Event) =
    let wasOpen = ($attrOrEmpty(toggle, "aria-expanded")) == "true"
    let open = not wasOpen
    applyOpen(open)
    if navKey.len > 0:
      localStorageSetItem(storageKey, cstring(if open: "true" else: "false"))

  r.addEventListener(toggle, "click", onClick)

proc wireSidebarCollapse*[R](r: R; root: Node) =
  for toggle in findAllElementsByClass(root, cstring(sidebarSectionTitleClass)):
    wireSidebarSectionToggle(r, toggle)

# --- 4. <768px mobile hamburger navigation drawer -------------------------

proc isFocusableTag(el: Element): bool =
  let tag = ($el.tagName).toLowerAscii
  tag == "a" or tag == "button"

proc findFocusableElements(root: Node): seq[Element] =
  if root.isNodeNil: return
  if root.nodeType == 1:
    let el = Element(root)
    if isFocusableTag(el): result.add el
  for child in root.childNodes:
    result.add findFocusableElements(child)

proc wireNavDrawer*[R](r: R; root: Node) =
  let toggles = findAllElementsByClass(root, cstring(navDrawerToggleClass))
  let bodies = findAllElementsByClass(root, cstring(navDrawerBodyClass))
  if toggles.len == 0 or bodies.len == 0: return
  let toggleEl = toggles[0]
  let bodyEl = bodies[0]

  proc isOpen(): bool =
    ($attrOrEmpty(bodyEl, "data-open")) == "true"

  proc setOpen(open: bool) =
    setAttribute(bodyEl, "data-open", cstring(if open: "true" else: "false"))
    setAttribute(toggleEl, "aria-expanded", cstring(if open: "true" else: "false"))
    if open:
      let focusables = findFocusableElements(Node(bodyEl))
      if focusables.len > 0: focusElement(focusables[0])
    else:
      focusElement(toggleEl)

  proc onToggleClick(ev: Event) = setOpen(not isOpen())
  proc onBodyKeydown(ev: Event) =
    case $eventKey(ev)
    of "Escape": setOpen(false)
    of "Tab":
      let focusables = findFocusableElements(Node(bodyEl))
      if focusables.len == 0: return
      let first = focusables[0]
      let last = focusables[^1]
      let active = documentActiveElement()
      if not elemIsNil(active):
        if eventShiftKey(ev) and sameNode(Node(active), Node(first)):
          eventPreventDefault(ev)
          focusElement(last)
        elif (not eventShiftKey(ev)) and sameNode(Node(active), Node(last)):
          eventPreventDefault(ev)
          focusElement(first)
    else: discard

  r.addEventListener(toggleEl, "click", onToggleClick)
  r.addEventListener(bodyEl, "keydown", onBodyKeydown)

# --- 5. Theme toggle (#docs-theme-toggle) ----------------------------------

proc wireThemeToggleById*(r: WebRenderer) =
  let btn = getElementById(document, cstring(themeToggleId))
  if elemIsNil(btn): return
  let docEl = documentElement(document)
  var vm = newThemeViewModel($localStorageGetItem(cstring(themeStorageKey)), prefersDarkColorScheme())

  proc applyTheme() =
    let themeStr = themeToString(vm.theme)
    let otherStr = themeToString(otherTheme(vm.theme))
    if not elemIsNil(docEl):
      setAttribute(docEl, cstring(themeAttrName), cstring(themeStr))
    localStorageSetItem(cstring(themeStorageKey), cstring(themeStr))
    setAttribute(btn, "data-theme", cstring(themeStr))
    setAttribute(btn, "aria-pressed", cstring(if vm.theme == thDark: "true" else: "false"))
    setAttribute(btn, "aria-label", cstring("Switch to " & otherStr & " theme"))

  applyTheme()
  proc onClick(ev: Event) =
    vm = toggle(vm)
    applyTheme()
  r.addEventListener(btn, "click", onClick)

# --- 6. Live search (#docs-search-input + `/` and Cmd/Ctrl+K shortcut) ----

proc wireGlobalSearchShortcut(inputEl: Element) {.importcpp: """
(function(inp){
  try {
    if (typeof document === 'undefined' || !document.addEventListener) return;
    document.addEventListener('keydown', function(ev) {
      var k = ev.key || '';
      var active = document.activeElement;
      var inField = active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable);
      if ((k === 'k' || k === 'K') && (ev.metaKey || ev.ctrlKey)) {
        if (ev.preventDefault) ev.preventDefault();
        if (inp && inp.focus) inp.focus();
      } else if (k === '/' && !inField && !ev.metaKey && !ev.ctrlKey && !ev.altKey) {
        if (ev.preventDefault) ev.preventDefault();
        if (inp && inp.focus) inp.focus();
      }
    });
  } catch (e) {}
})(#)""".}

proc clearInputValue(e: Element) {.importcpp: "(#.value = '')".}

proc wireSearchById*(r: WebRenderer; index: SearchIndex) =
  let inputEl = getElementById(document, cstring(searchInputId))
  if elemIsNil(inputEl): return
  let wrapperEl = getElementById(document, cstring(searchResultsWrapperId))
  if elemIsNil(wrapperEl): return

  var vm = newSearchViewModel()

  proc rerenderResults() =
    r.clearChildren(wrapperEl)
    r.appendChild(wrapperEl, renderSearchResultsContent[WebRenderer, Node](r, vm))

  proc onInput(ev: Event) =
    vm = setQuery(vm, index, $getInputValue(inputEl))
    rerenderResults()

  proc onKeydown(ev: Event) =
    case $eventKey(ev)
    of "ArrowDown":
      eventPreventDefault(ev)
      vm = moveCursor(vm, 1)
      rerenderResults()
    of "ArrowUp":
      eventPreventDefault(ev)
      vm = moveCursor(vm, -1)
      rerenderResults()
    of "Enter":
      let selected = selectedResult(vm)
      if selected.routePath.len > 0:
        navigateTo(cstring(selected.routePath))
    of "Escape":
      clearInputValue(inputEl)
      vm = setQuery(vm, index, "")
      rerenderResults()
    else:
      discard

  r.addEventListener(inputEl, "input", onInput)
  r.addEventListener(inputEl, "keydown", onKeydown)
  wireGlobalSearchShortcut(inputEl)

# --- All-in-one entry point for static MPA docs sites ----------------------

proc mountStaticDocsClient*(index: SearchIndex = SearchIndex()) =
  ## Wires search, theme toggle, sidebar collapse, mobile nav drawer,
  ## `:::tabs`, and `Copy code` onto `document.body`.
  let r = WebRenderer()
  let bodyEl = documentBody(document)
  if elemIsNil(bodyEl): return
  let root = Node(bodyEl)
  wireSearchById(r, index)
  wireThemeToggleById(r)
  wireSidebarCollapse(r, root)
  wireNavDrawer(r, root)
  wireTabsInteractivity(r, root)
  wireCodeCopyInteractivity(r, root)
