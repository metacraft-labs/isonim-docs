## isonim-docs Layer 4 shell — browser mount entry.
##
## `createApp`/`createRouteApp` are plain tree-builders (generic over
## the renderer, via `buildApp`/`buildRouteApp`) -- a `WebRenderer`
## instantiation always creates a fresh DOM tree, kept for the existing
## MockRenderer-parity tests. `hydrateApp`/`hydrateRouteApp` (M4
## corrective deliverable 1) are the real production mount path: they
## instantiate `./hydrating_renderer.HydratingRenderer` instead, which
## reuses `#root`'s already-parsed SSR HTML in place (real DOM node
## identity preserved) rather than discarding it for a full fresh
## render -- see `hydrating_renderer.nim` for how a plain structural
## walk lines reused nodes up with client-side construction, and why
## that's the right match for this framework's dual SSR-string/client-
## tree DSL backends.
##
## `createApp`/`mountedPage` are M0's single-page proof route, kept
## byte-for-byte as-is so `test_bootstrap_browser_mount.nim` stays
## green. `createRouteApp`/`hydrateRouteApp` resolve a path against a
## manifest (by default `defaultEmbeddedManifest()`, the M1 corrective
## deliverable 2 auto-discovery default -- an explicit manifest, e.g.
## `docsRouteManifest()`, still overrides it) and `buildShellViewModel`
## the exact same way the SSR entry (`src/ssr.nim`'s `renderRoute`) does
## -- no route-specific forking of routing logic. The docs content
## itself can't be read from a real filesystem in the browser, so every
## content file under `../content` is embedded at *compile* time via
## `core/content_embed.embedContentDir` (M1 corrective deliverable 3: a
## real, generic compile-time directory walk + `staticRead`, not a
## hand-maintained per-file list) into `embeddedContent` below, and
## parsed with the exact same `parseDocsPage` the SSR path uses, so JS
## mount and SSR agree on the same content pipeline end to end. That
## compile-time lookup table is the one platform-specific seam
## `buildShellViewModel` takes as `loadPage` -- route resolution and
## ViewModel construction are 100% shared with SSR.

when not defined(js):
  {.error: "main_web.nim requires the JS backend: nim js -r/nim js main_web.nim".}

import std/[os, tables, strutils]
import isonim/web/dom_api
import isonim/web/web_renderer
import isonim/core/owner
import ./hydrating_renderer
import ./core/content
import ./core/content_embed
import ./core/config
import ./core/routes
import ./core/shell_vm
import ./core/markdown_vm
import ./core/navigation_vm
import ./core/references
import ./core/search_vm
import ./core/server_search
import ./core/theme_vm
import ./core/openapi
import ./core/api_reference_vm
import ./core/nimdoc
import ./core/symbol_reference_vm
import ./components/shell
import ./components/markdown_page
import ./components/markdown_view
import ./components/navigation_view
import ./components/search_view
import ./components/theme_toggle
import ./components/api_reference
import ./components/api_reference_page
import ./components/symbol_reference
import ./components/symbol_reference_page

const embeddedContent = embedContentDir(currentSourcePath().parentDir() / "../tests/fixtures/mini-site")
const embeddedApiSpecs = embedContentDir(currentSourcePath().parentDir() / "../tests/fixtures/mini-site", ".yaml")
  ## M7 deliverable 2: the JS-target counterpart to the SSR entry's real
  ## spec-file read -- OpenAPI spec files (`.yaml`) embedded at compile
  ## time, exactly like `embeddedContent` embeds markdown. The framework's
  ## own fixture ships no spec, so this is empty here; a consumer points
  ## its own copy of this macro call at its own spec dir. A `pkApiReference`
  ## route whose spec isn't embedded ingests an empty string -> a tolerant
  ## typed error rendered as an inline notice, never a crash.
  ## M1 corrective deliverable 3: a generic compile-time embed of every
  ## `.md` file under a content dir, replacing a hand-maintained
  ## `staticRead` list. M1 corrective deliverable 5 points this at the
  ## framework's own checked-in `tests/fixtures/mini-site/` -- the
  ## framework carries no real content of its own -- a consumer (e.g.
  ## `../isonim/docs/users/src/main.nim`) points its own copy of this
  ## macro call at its own content dir instead.

const embeddedNimSources = embedContentDir(currentSourcePath().parentDir() / "../tests/fixtures/mini-site", ".nim")
  ## M8 deliverable 1: the JS-target counterpart to the SSR entry's real
  ## Nim-source read -- `.nim` source files embedded at compile time,
  ## exactly like `embeddedApiSpecs` embeds OpenAPI specs. The framework's
  ## own fixture ships no library source, so this is empty here; a consumer
  ## points its own copy of this macro call at its own source dir. A
  ## `pkSymbolReference` route whose source isn't embedded ingests an empty
  ## string -> a tolerant typed error rendered as an inline notice, never a
  ## crash.

proc mountedPage*(): DocsPage =
  ## Exposed for tests: the exact page JS mount renders, parsed from the
  ## exact same compile-time-embedded real content file.
  parseDocsPage(embeddedContent["index.md"], "content/index.md")

proc buildApp[R](r: R): Node =
  let vm = shellViewModel(mountedPage())
  renderShell[R, Node](r, vm)

proc createApp*(): Node =
  buildApp(WebRenderer())

proc hydrateApp*(rootEl: Element): Node =
  ## M4 corrective deliverable 1: `createApp`'s hydrating counterpart --
  ## attaches to `rootEl`'s existing (SSR-rendered) children via
  ## `hydrating_renderer.HydratingRenderer` instead of always building a
  ## fresh tree, so real node identity is preserved wherever the SSR and
  ## client trees line up structurally. `createRoot` matches `isonim/
  ## web/client.render`'s own wrapping (`createRenderEffect` calls inside
  ## `renderShell`'s `ui(r):` body register against *some* owner; without
  ## one they'd just run once and never get cleaned up on unmount, fine
  ## for a page-lifetime mount but kept for parity) -- unlike `render`,
  ## nothing here routes through `insertExpression`'s own insert/replace
  ## reconciliation, which is exactly the "full fresh render" this
  ## deliverable replaces.
  let r = newHydratingRenderer(rootEl)
  var built: Node
  createRoot proc(dispose: proc()) =
    built = buildApp(r)
  discard dom_api.appendChild(Node(rootEl), built)
  built

proc loadEmbeddedPage(contentPath: string): DocsPage =
  ## JS's platform-specific content-loading seam passed to
  ## `buildShellViewModel` as `loadPage` -- looks up the compile-time
  ## embedded raw text for `contentPath` instead of reading it from a
  ## runtime filesystem the browser doesn't have.
  parseDocsPage(embeddedContent[contentPath], "content/" & contentPath)

proc loadEmbeddedContentEntry(contentPath: string): ContentEntry =
  ## The `pkMarkdown` counterpart to `loadEmbeddedPage`: parses the same
  ## compile-time-embedded raw text as a full `ContentEntry` (front
  ## matter + body) via `parseContentEntry`, exactly as
  ## `content.loadContentEntry` does from a real file on the SSR side.
  parseContentEntry(embeddedContent[contentPath], contentPath)

proc defaultEmbeddedManifest(): RouteManifest =
  ## The JS mount entry's own framework-default manifest (M1 corrective
  ## deliverable 2's "both routing models" for `main_web` specifically):
  ## there's no real filesystem to walk in the browser, so this is the
  ## JS-target counterpart to `ssr.renderRoute`/`build_site.buildSite`'s
  ## `buildManifestFromContent(contentDir)` default -- same assembly step
  ## (`routes.buildManifestFromEntries`), just fed from the compile-time
  ## `embeddedContent` table already parsed into full `ContentEntry`s
  ## instead of a runtime directory walk. Passing an explicit `manifest`
  ## to `createRouteApp` (e.g. the hand-authored `docsRouteManifest()`)
  ## still fully overrides this default, unchanged.
  var entries: seq[ContentEntry] = @[]
  for contentPath, raw in embeddedContent:
    let entry = parseContentEntry(raw, contentPath)
    if not entry.front.draft:
      entries.add entry
  sortContentEntries(entries)
  buildManifestFromEntries(entries)

proc mountedRoutePage*(contentPath: string): DocsPage =
  ## Exposed for tests: the exact page `createRouteApp` renders for a
  ## manifest entry bound to `contentPath`, parsed from the same
  ## compile-time-embedded content `loadEmbeddedPage` looks up.
  loadEmbeddedPage(contentPath)

proc mountedMarkdownPage*(contentPath: string): tuple[title: string, blocks: seq[Block]] =
  ## Exposed for tests: the exact title/block tree `createRouteApp`
  ## renders for a `pkMarkdown` manifest entry bound to `contentPath`.
  let entry = loadEmbeddedContentEntry(contentPath)
  (entry.page.title, parseMarkdownBlocks(entry.page.body, entry.source.path))

# --- M4 deliverable 1: real, live client search --------------------------
##
## Reading a real, *live* `<input>` value or a `KeyboardEvent`'s `.key`
## needs a real browser property, which `isonim/web/dom_api` doesn't
## expose (its `Element`/`Event` bindings only cover what M0-M3 needed)
## -- so these three bindings are the one place this module reaches past
## `dom_api` with its own `importcpp` property-access glue, exactly the
## same idiom `dom_api.nim` itself uses throughout (`"#.value"`/
## `"#.value = #"` are property get/set, not calls -- the JS backend
## treats a paren-less `importcpp` pattern as a bare expression).
proc getInputValue(e: Element): cstring {.importcpp: "#.value".}
proc eventKey(e: Event): cstring {.importcpp: "#.key".}
proc navigateTo(path: cstring) {.importcpp:
  "(typeof window !== 'undefined' && window.location) && (window.location.href = #)".}
  ## Defensive against a headless test host with no real `window.location`
  ## (this repo's own `nim js -r` test harness runs under Node.js, not a
  ## browser) -- a real browser always has both, so this is a no-op
  ## fallback, never a real-world behavior change.

proc eventShiftKey(e: Event): bool {.importcpp: "(!!(#.shiftKey))".}
proc eventPreventDefault(e: Event) {.importcpp: "#.preventDefault()".}

proc hasAttribute(e: Element; name: cstring): bool {.importcpp: "#.hasAttribute(#)".}
  ## `getAttribute` returns JS `null` for a missing attribute, and
  ## converting that straight to a Nim string crashes reading `.length`
  ## off it (see `hasExactClass`'s own comment below) -- checking
  ## presence first, the same way, avoids it everywhere an `href`/
  ## `target`/`rel`/`data-*` attribute gets read in this module. Declared
  ## here (rather than down in the M4 corrective deliverable 2 section
  ## that originally introduced it, alongside `eventShiftKey`/
  ## `eventPreventDefault` above) so M5 corrective deliverable 1's
  ## sidebar-collapse/nav-drawer wiring -- which needs all three and is
  ## wired earlier in this file, from `buildRouteApp` -- can use them too,
  ## without a forward declaration.

# --- M2 deliverable 2: real, live theme toggle ----------------------------
##
## `dom_api` has no `documentElement`/`localStorage`/`matchMedia` bindings
## (nothing before M2 needed the document root or persistence), so these
## four are this module's own `importcpp` glue, exactly the same idiom as
## `getInputValue`/`eventKey`/`navigateTo` above. `localStorage`/
## `matchMedia` access is wrapped in `try`/guarded with `typeof` checks the
## same way `theme_toggle.renderThemeBootstrapHtml`'s hand-written JS is --
## this repo's own JS-target test harness (`test_routes_browser_mount.nim`
## and friends) stubs a minimal `document`/`window` with neither, so a
## real crash here would take down every existing browser-mount suite, not
## just add a new one.
proc documentElement(d: Document): Element {.importcpp: "#.documentElement".}
proc localStorageGetItem(key: cstring): cstring {.importcpp:
  "(function(){try{var v=localStorage.getItem(#);return (v===null||v===undefined)?'':v;}catch(e){return '';}})()".}
proc localStorageSetItem(key, value: cstring) {.importcpp:
  "(function(){try{localStorage.setItem(#, #);}catch(e){}})()".}
proc prefersDarkColorScheme(): bool {.importcpp:
  "(typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches === true)".}

proc wireThemeToggle[R](r: R; frame: Node) =
  ## Finds the theme toggle `<button>` at the same structural path
  ## `components/shell.renderSiteFrame`/`components/markdown_page.
  ## renderMarkdownPage` always build it at (frame -> [skip link, header]
  ## -> header -> [title h1, search box, toggle button]) -- the same
  ## structural-traversal idiom `wireSearchInteractivity` above already
  ## uses. Recomputes the real
  ## initial theme via the exact same `theme_vm.resolveInitialTheme`
  ## precedence the SSR bootstrap script's hand-written JS restates, then
  ## applies it (idempotent with whatever the bootstrap script already
  ## set on `document.documentElement`) and wires a click to flip it,
  ## persist it, and re-sync the button's own `data-theme`/`aria-pressed`/
  ## `aria-label` attributes.
  let headerNode = frame.firstChild.nextSibling ## skip link is frame's real first child
  if headerNode.isNodeNil: return
  let titleNode = headerNode.firstChild
  if titleNode.isNodeNil: return
  let searchBoxNode = titleNode.nextSibling
  if searchBoxNode.isNodeNil: return
  let toggleNode = searchBoxNode.nextSibling
  if toggleNode.isNodeNil: return
  let toggleEl = Element(toggleNode)
  let docEl = documentElement(document)

  var vm = newThemeViewModel($localStorageGetItem(cstring(themeStorageKey)), prefersDarkColorScheme())

  proc applyTheme() =
    setAttribute(docEl, cstring(themeAttrName), cstring(themeToString(vm.theme)))
    localStorageSetItem(cstring(themeStorageKey), cstring(themeToString(vm.theme)))
    setAttribute(toggleEl, "data-theme", cstring(themeToString(vm.theme)))
    setAttribute(toggleEl, "aria-pressed", cstring(if vm.theme == thDark: "true" else: "false"))
    setAttribute(toggleEl, "aria-label",
      cstring("Switch to " & themeToString(otherTheme(vm.theme)) & " theme"))

  applyTheme()

  proc onClick(ev: Event) =
    vm = toggle(vm)
    applyTheme()

  r.addEventListener(toggleEl, "click", onClick)

## --- M3 deliverable 1: real, live keyboard-navigable tabs ---------------
##
## `dom_api` has no `.focus()` binding (nothing before M3 needed to move
## focus programmatically) -- this module's own `importcpp` glue, same
## idiom as `getInputValue`/`eventKey`/`navigateTo` above.
proc focusElement(e: Element) {.importcpp: "#.focus()".}

proc hasExactClass(e: Element; cls: cstring): bool {.importcpp:
  "(#.getAttribute('class') === #)".}
  ## A real `Element.getAttribute` returns JS `null`, not an empty
  ## string, when the attribute is absent (every element with no
  ## `class` at all, e.g. `<html>`/`<body>`) -- converting that `null`
  ## to a Nim string (`$getAttribute(...)`) crashes reading `.length`
  ## off it in the JS runtime's cstring-to-nimstr conversion, so this
  ## comparison stays entirely on the JS side instead.

proc findAllElementsByClass(root: Node; cls: cstring): seq[Element] =
  ## Depth-first collection of every descendant element (INCLUDING
  ## `root` itself) whose `class` attribute is exactly `cls` -- mirrors
  ## `tests/docs/helpers/mock_tree.findAllByTag`'s idiom, just walking a
  ## real DOM `Node` tree (`childNodes`) instead of a `MockNode`, since
  ## every `bkTabs` block's tablist/tab/tabpanel elements carry exactly
  ## one class each (see `components/markdown_view.nim`).
  if root.isNodeNil: return
  if root.nodeType == 1:
    let el = Element(root)
    if hasExactClass(el, cls):
      result.add el
  for child in root.childNodes:
    result.add findAllElementsByClass(child, cls)

proc wireTabs[R](r: R; tabsWrapper: Element) =
  ## Wires one `:::tabs` block's tablist for the WAI-ARIA APG "tabs"
  ## pattern: click or Enter/Space (native `<button>` behaviour, no
  ## wiring needed) activates a tab; ArrowLeft/ArrowRight/Home/End move
  ## both the roving `tabindex` and real focus, activating the newly
  ## focused tab (automatic activation) -- searched only within this one
  ## wrapper's own subtree, so multiple `:::tabs` blocks on one page (or
  ## nested tabs inside a panel) wire independently.
  let tabs = findAllElementsByClass(Node(tabsWrapper), cstring(tabClass))
  let panels = findAllElementsByClass(Node(tabsWrapper), cstring(tabpanelClass))
  if tabs.len == 0 or panels.len != tabs.len: return

  proc activate(idx: int; moveFocus: bool) =
    for i in 0 ..< tabs.len:
      let selected = i == idx
      setAttribute(tabs[i], "aria-selected", cstring(if selected: "true" else: "false"))
      setAttribute(tabs[i], "tabindex", cstring(if selected: "0" else: "-1"))
      if selected: removeAttribute(panels[i], "hidden")
      else: setAttribute(panels[i], "hidden", "hidden")
    if moveFocus: focusElement(tabs[idx])

  for i in 0 ..< tabs.len:
    let idx = i
    proc onClick(ev: Event) = activate(idx, false)
    proc onKeydown(ev: Event) =
      case $eventKey(ev)
      of "ArrowRight": activate((idx + 1) mod tabs.len, true)
      of "ArrowLeft": activate((idx - 1 + tabs.len) mod tabs.len, true)
      of "Home": activate(0, true)
      of "End": activate(tabs.len - 1, true)
      else: discard
    r.addEventListener(tabs[idx], "click", onClick)
    r.addEventListener(tabs[idx], "keydown", onKeydown)

proc wireTabsInteractivity[R](r: R; root: Node) =
  for tabsWrapper in findAllElementsByClass(root, cstring(tabsClass)):
    wireTabs(r, tabsWrapper)

## --- M3 deliverable 3: real, live copy-to-clipboard code buttons ---------
##
## `dom_api` has no `navigator.clipboard`/`setTimeout` bindings (nothing
## before M3 needed either) -- this module's own `importcpp` glue, same
## defensive try/catch + `typeof` guard idiom as `localStorageGetItem`/
## `prefersDarkColorScheme` above: this repo's own JS-target test harness
## stubs a minimal `document`/`window` with neither a real
## `navigator.clipboard` nor (in some suites) `setTimeout`, so a real
## crash here would take down every existing browser-mount suite.
proc writeClipboardText(text: cstring) {.importcpp:
  "(function(){try{if(typeof navigator!=='undefined'&&navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(#).catch(function(){});}}catch(e){}})()".}

proc scheduleTimeout(cb: proc() {.closure.}; ms: int) {.importcpp:
  "(function(){try{setTimeout(#, #);}catch(e){}})()".}

const codeCopyResetDelayMs = 1500

proc wireCodeCopyButton[R](r: R; wrapper: Element) =
  ## Walks the exact structural contract `markdown_view.renderCodeFence`
  ## builds (wrapper -> [button, pre -> code]) rather than an id lookup --
  ## same idiom as `wireTabs`'s class-scoped traversal, just narrower
  ## since each wrapper holds exactly one button/code pair.
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
    ## `let text = ...` matters here, not just style: `writeClipboardText`'s
    ## importcpp pattern is an IIFE (`(function(){...})()`), and splicing
    ## `codeNode.textContent` straight into its `#` placeholder would
    ## resolve inside that IIFE's own `this`, not this closure's captured
    ## `codeNode` (JS backend closures reach captured vars via
    ## `this.<name>`) -- binding to a local first sidesteps that: locals
    ## stay reachable through the IIFE's normal lexical closure over
    ## `text`, only `this` is IIFE-local.
    let text = codeNode.textContent
    writeClipboardText(text)
    setAttribute(btn, "data-copied", "true")
    setAttribute(btn, "aria-label", cstring(codeCopyCopiedLabel))
    btnNode.textContent = cstring(codeCopyCopiedLabel)
    scheduleTimeout(resetLabel, codeCopyResetDelayMs)

  r.addEventListener(btn, "click", onClick)

proc wireCodeCopyInteractivity*[R](r: R; root: Node) =
  ## Exported (unlike `wireTabsInteractivity`/`wireThemeToggle` above) so
  ## `test_code_copy_browser_mount.nim` can wire a hand-built mounted
  ## tree directly, without needing a fixture content file with a code
  ## fence routed through `createRouteApp`.
  for wrapper in findAllElementsByClass(root, cstring(codeBlockClass)):
    wireCodeCopyButton(r, wrapper)

## --- M5 corrective deliverable 1: real, live sidebar click-to-collapse ---
##
## Each `sidebarSectionTitleClass` `<button>` (`navigation_view.
## renderSidebarSection`'s per-node toggle) flips its own section's
## `sidebarSectionExpandedClass` + `aria-expanded` on click, and persists
## the choice to `localStorage` (same `try`/`catch`-guarded
## `localStorageGetItem`/`localStorageSetItem` glue M2's theme toggle
## already uses) keyed by that section's own `data-nav-key` -- so
## collapsing a deeply-nested node survives a reload, independent of
## `navigation_vm.buildSidebar`'s own SSR-time "active path auto-expands"
## default, which only ever runs again on the next full route swap.

const navExpandedStoragePrefix = "docs-nav-expanded:"

proc attrOrEmpty(e: Element; name: cstring): cstring {.importcpp: "(#.getAttribute(#) || '')".}
  ## A `hasAttribute`-free, null-safe attribute read: unlike
  ## `main_web.hasAttribute` + `getAttribute` (which needs a real
  ## `Element.hasAttribute` method -- several of this repo's own
  ## browser-mount test DOM shims, e.g. `test_markdown_browser_mount.
  ## nim`'s, only implement `getAttribute`, not `hasAttribute`, and this
  ## proc's callers below run unconditionally from `buildRouteApp`, on
  ## every `createRouteApp` mount those suites use, not just
  ## `hydrateRouteApp`), this stays entirely on the JS side: `||` folds
  ## a missing attribute's `null` (or an already-empty value) to `''`
  ## before it ever reaches Nim's cstring-to-nimstr conversion, the same
  ## way `hasExactClass` keeps its own null comparison JS-side.

proc sidebarSectionKey(el: Element): string =
  $attrOrEmpty(el, "data-nav-key")

proc wireSidebarSectionToggle[R](r: R; toggle: Element) =
  let sectionNode = Node(toggle).parentNode
  if sectionNode.isNodeNil: return
  let sectionEl = Element(sectionNode)
  let storageKey = cstring(navExpandedStoragePrefix & sidebarSectionKey(sectionEl))

  proc applyOpen(open: bool) =
    setAttribute(sectionEl, "class",
      cstring(if open: sidebarSectionClass & " " & sidebarSectionExpandedClass else: sidebarSectionClass))
    setAttribute(toggle, "aria-expanded", cstring(if open: "true" else: "false"))

  let stored = $localStorageGetItem(storageKey)
  if stored == "true": applyOpen(true)
  elif stored == "false": applyOpen(false)
  ## Any other value (nothing stored yet) leaves the SSR-computed
  ## default (active-path auto-expand) exactly as rendered.

  proc onClick(ev: Event) =
    let wasOpen = ($attrOrEmpty(toggle, "aria-expanded")) == "true"
    let open = not wasOpen
    applyOpen(open)
    localStorageSetItem(storageKey, cstring(if open: "true" else: "false"))

  r.addEventListener(toggle, "click", onClick)

proc wireSidebarCollapse[R](r: R; frame: Node) =
  for toggle in findAllElementsByClass(frame, cstring(sidebarSectionTitleClass)):
    wireSidebarSectionToggle(r, toggle)

## --- M5 corrective deliverable 1: real, live <768px hamburger drawer ----
##
## `dom_api` has no `document.activeElement` binding (nothing before this
## needed to read live focus) -- this module's own `importcpp` glue, same
## defensive `typeof`-guarded idiom as `localStorageGetItem`/
## `prefersDarkColorScheme` above. `sameNode` compares two `Node`s by real
## DOM identity (`===`) rather than Nim's own `==`, since `Node`/`Element`
## are opaque `{.importc.}` refs the JS backend doesn't give a meaningful
## structural `==` for.
proc documentActiveElement(): Element {.importcpp:
  "((typeof document !== 'undefined' && document.activeElement) ? document.activeElement : null)".}
proc sameNode(a, b: Node): bool {.importcpp: "(# === #)".}

proc isFocusableTag(el: Element): bool =
  let tag = ($el.tagName).toLowerAscii
  tag == "a" or tag == "button"

proc findFocusableElements(root: Node): seq[Element] =
  ## Depth-first, DOM-order collection of every focusable descendant
  ## (`<a>`/`<button>`, the only two kinds of focusable element this
  ## framework's own chrome ever renders inside the drawer body: nav
  ## links, section-collapse toggles, breadcrumb/TOC/pagination links) --
  ## the Tab sequence `wireNavDrawer`'s focus trap wraps between.
  if root.isNodeNil: return
  if root.nodeType == 1:
    let el = Element(root)
    if isFocusableTag(el): result.add el
  for child in root.childNodes:
    result.add findFocusableElements(child)

proc wireNavDrawer[R](r: R; frame: Node) =
  ## Wires `navigation_view.renderNavDrawerToggle`'s hamburger `<button>`
  ## to open/close `renderNavigation`'s `navDrawerBodyClass` panel (a
  ## real off-canvas drawer only below the 768px CSS breakpoint --
  ## `[data-open]` is toggled unconditionally here regardless of viewport
  ## width, same as every other piece of chrome this module wires; it's
  ## simply visually inert above the breakpoint, see `assets/style.css`).
  ## Opening moves focus to the panel's first focusable element and traps
  ## Tab/Shift+Tab between its first and last focusable elements (WAI-ARIA
  ## APG dialog focus-trap pattern) via a single `keydown` listener on the
  ## panel itself -- real Tab presses bubble up to it from whichever
  ## descendant is actually focused, and this repo's own browser-mount
  ## test shim (see `test_nav_drawer_browser_mount.nim`) can dispatch
  ## synthetic ones directly on the panel the same way (per the
  ## direct-listener idiom `wireSoftNavLink`/`wireTabs` already use --
  ## document-level delegation never fires in that shim). Escape closes
  ## and returns focus to the toggle button.
  let toggles = findAllElementsByClass(frame, cstring(navDrawerToggleClass))
  let bodies = findAllElementsByClass(frame, cstring(navDrawerBodyClass))
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

  proc onToggleClick(ev: Event) =
    setOpen(not isOpen())

  proc onBodyKeydown(ev: Event) =
    case $eventKey(ev)
    of "Escape":
      setOpen(false)
    of "Tab":
      let focusables = findFocusableElements(Node(bodyEl))
      if focusables.len == 0: return
      let first = focusables[0]
      let last = focusables[^1]
      let active = documentActiveElement()
      if eventShiftKey(ev):
        if sameNode(Node(active), Node(first)):
          eventPreventDefault(ev)
          focusElement(last)
      else:
        if sameNode(Node(active), Node(last)):
          eventPreventDefault(ev)
          focusElement(first)
    else: discard

  r.addEventListener(toggleEl, "click", onToggleClick)
  r.addEventListener(bodyEl, "keydown", onBodyKeydown)

proc wireSearchInteractivity[R](r: R; frame: Node; index: SearchIndex) =
  ## Finds the search box's own `<input>`/results-wrapper inside `frame`
  ## by the exact same structural path `components/shell.renderSiteFrame`
  ## / `components/markdown_page.renderMarkdownPage` always build it at
  ## (header -> [title h1, search box] -> search box -> [input, results
  ## wrapper]) -- the same structural-traversal idiom this module's own
  ## test suite (`test_routes_browser_mount.nim`) already uses to find
  ## mounted nodes, rather than `getElementById` (real browsers key that
  ## off a live document-wide id index; nothing here needs one, and it
  ## wouldn't help before `frame` is even inserted into the document
  ## anyway). Wires real keystroke-driven search against `index` (the
  ## real, compile-time-embedded content graph's own search index, built
  ## the exact same way `ssr.renderRoute`'s SSR bootstrap payload is) --
  ## re-rendering only the results wrapper in place
  ## (`search_view.renderSearchResultsContent`) on every keystroke/arrow
  ## press, so the `<input>` itself, and its focus, never gets torn down.
  let headerNode = frame.firstChild.nextSibling ## skip link is frame's real first child
  if headerNode.isNodeNil: return
  let titleNode = headerNode.firstChild
  if titleNode.isNodeNil: return
  let searchBoxNode = titleNode.nextSibling
  if searchBoxNode.isNodeNil: return
  let inputNode = searchBoxNode.firstChild
  if inputNode.isNodeNil: return
  let resultsWrapperNode = inputNode.nextSibling
  if resultsWrapperNode.isNodeNil: return
  let resultsWrapperEl = Element(resultsWrapperNode)
  let inputEl = Element(inputNode)

  var vm = newSearchViewModel()

  proc rerenderResults() =
    r.clearChildren(resultsWrapperEl)
    r.appendChild(resultsWrapperEl, renderSearchResultsContent[R, Node](r, vm))

  proc onInput(ev: Event) =
    vm = setQuery(vm, index, $getInputValue(inputEl))
    rerenderResults()

  proc onKeydown(ev: Event) =
    case $eventKey(ev)
    of "ArrowDown":
      vm = moveCursor(vm, 1)
      rerenderResults()
    of "ArrowUp":
      vm = moveCursor(vm, -1)
      rerenderResults()
    of "Enter":
      let selected = selectedResult(vm)
      if selected.routePath.len > 0:
        navigateTo(cstring(selected.routePath))
    else:
      discard

  r.addEventListener(inputEl, "input", onInput)
  r.addEventListener(inputEl, "keydown", onKeydown)

## --- M5 deliverable 2: real, live keyboard-triggered search overlay ------
##
## The overlay (`components/search_view.renderSearchOverlay`, rendered as
## the site frame's last child) is opened by a global `Cmd/Ctrl+K` (and
## `/`, but only when focus is NOT already in a text input/textarea/
## contenteditable), closed by `Esc`, arrow-key-navigable, and
## `Enter`-selectable -- reusing the exact same `SearchViewModel` reducers
## (`setQuery`/`moveCursor`/`selectedResult`) the inline box does. Unlike
## the inline box's compile-time-embedded index, the overlay's index is
## fetched LAZILY, once, on first open, from the content-hashed
## `data-search-index-url` artifact the SSG emitted (see `build_site.nim`)
## -- never at page load, and never inlined into the page. Every DOM/
## `fetch` touch below is `typeof`-guarded the same defensive way the rest
## of this module's `importcpp` glue is, so the other browser-mount suites
## (whose shims have no `document.addEventListener`/`fetch`/`activeElement`)
## silently no-op instead of crashing.
proc setInputValue(e: Element; v: cstring) {.importcpp: "#.value = #".}

proc documentAddKeydownListener(handler: proc(ev: Event) {.closure.}) {.importcpp:
  "(typeof document !== 'undefined' && document.addEventListener) && document.addEventListener('keydown', #)".}
  ## The one genuinely document-global listener this framework wires (the
  ## overlay's open shortcut has to fire regardless of what's focused) --
  ## guarded so a shim without `document.addEventListener` no-ops.

proc eventIsCmdK(e: Event): bool {.importcpp:
  "(function(ev){return (!!(ev.metaKey)||!!(ev.ctrlKey))&&(ev.key==='k'||ev.key==='K');})(#)".}
  ## Wrapped in an IIFE taking one JS-local param so the body can read
  ## `ev` several times -- Nim's JS backend maps each `#` to the NEXT
  ## formal param, so a bare `#.metaKey ... #.key` would consume three
  ## params for one (see `observeForViewportPrefetch`'s own note).

proc activeElementIsTextEntry(): bool {.importcpp:
  "(function(){if(typeof document==='undefined'||!document.activeElement)return false;var el=document.activeElement;var tag=((el.tagName||'')+'').toLowerCase();if(tag==='input'||tag==='textarea'||tag==='select')return true;return el.isContentEditable===true;})()".}
  ## True when a text-entry element currently holds focus -- so the bare
  ## `/` shortcut doesn't hijack a keystroke the user meant to type into a
  ## field (including the overlay's own input once it's open).

proc fetchSearchIndex(url: cstring; onLoaded: proc(text: cstring) {.closure.}) {.importcpp:
  "(function(u,cb){try{if(typeof fetch==='undefined'){return;}fetch(u).then(function(resp){return resp.text();}).then(function(t){cb(t);}).catch(function(){});}catch(e){}})(#, #)".}
  ## Lazily fetches the hashed search-index artifact and hands its raw
  ## text to `cb` -- guarded so a `fetch`-less host (this repo's Node test
  ## shims, unless they provide one) silently no-ops. Wrapped as an IIFE
  ## over its own JS-local params for the same reason as `eventIsCmdK`.

proc fetchSearchResults(url: cstring; onLoaded: proc(text: cstring) {.closure.}) {.importcpp:
  "(function(u,cb){try{if(typeof fetch==='undefined'){return;}fetch(u).then(function(resp){return resp.text();}).then(function(t){cb(t);}).catch(function(){});}catch(e){}})(#, #)".}
  ## M12 deliverable 2: fetches the server search endpoint's JSON response
  ## body for one debounced query and hands its raw text to `cb` (parsed by
  ## `server_search.parseSearchResultsJson`). Same guarded fetch-text shape
  ## as `fetchSearchIndex`; a distinct name because it hits the live search
  ## API per keystroke-burst, not the one-shot index artifact.

proc setTimeoutMs(cb: proc() {.closure.}; ms: int) {.importcpp:
  "(function(f,d){if(typeof setTimeout!=='undefined'){setTimeout(f,d);}else{f();}})(#, #)".}
  ## M12 deliverable 2 (server search): schedules the debounced server
  ## request. Wrapped so a host without `setTimeout` (a bare test shim)
  ## invokes the callback synchronously instead of dropping it -- the
  ## `Debouncer` generation-token check inside still guarantees only the
  ## latest keystroke actually fetches, so a synchronous host just fires
  ## every callback and coalesces to the same single request.

proc wireSearchOverlay[R](r: R; frame: Node) =
  ## Finds the overlay (`searchOverlayClass`) inside `frame` by class --
  ## it's the frame's last child, off the front-anchored header/nav/main
  ## traversal path the inline `wireSearchInteractivity` uses -- then
  ## wires the global open shortcut plus the overlay input's own
  ## Esc/Arrow/Enter/typing behaviour against a lazily-fetched index.
  let overlays = findAllElementsByClass(frame, cstring(searchOverlayClass))
  if overlays.len == 0: return
  let overlayEl = overlays[0]
  let dialogNode = Node(overlayEl).firstChild
  if dialogNode.isNodeNil: return
  let inputNode = dialogNode.firstChild
  if inputNode.isNodeNil: return
  let resultsNode = inputNode.nextSibling
  if resultsNode.isNodeNil: return
  let inputEl = Element(inputNode)
  let resultsEl = Element(resultsNode)
  let indexUrl = attrOrEmpty(overlayEl, cstring(searchIndexUrlAttr))

  ## M12 deliverable 2: the config toggle the SSR emitted onto the overlay
  ## decides, per keystroke, between the client-index path (rank the
  ## lazily-fetched index in the browser, exactly as before) and the
  ## server-API path (debounce, then fetch already-ranked results from the
  ## endpoint). An empty/"client"/unknown mode falls back to the client
  ## path -- `server_search.dispatchFor` is the single source of that
  ## decision, so the client and any server share it.
  let searchCfg = ServerSearchConfig(
    mode: (if $attrOrEmpty(overlayEl, cstring(searchModeAttr)) == $smServerApi:
             smServerApi else: smClientIndex),
    endpoint: $attrOrEmpty(overlayEl, cstring(searchEndpointAttr)),
    debounceMs: (block:
      let raw = $attrOrEmpty(overlayEl, cstring(searchDebounceAttr))
      try: parseInt(raw) except ValueError: defaultSearchDebounceMs))
  let isServerMode = dispatchFor(searchCfg) == sdServerApi

  var vm = newSearchViewModel()
  var index = SearchIndex()
  var indexFetchStarted = false
  var debouncer = newDebouncer(searchCfg.debounceMs)

  proc rerender() =
    r.clearChildren(resultsEl)
    r.appendChild(resultsEl, renderSearchOverlayResultsContent[R, Node](r, vm))

  proc runServerQuery() =
    ## Server-API path: coalesce this keystroke via the `Debouncer`
    ## generation token, and only the last keystroke of a burst actually
    ## fetches -- the ranked results come back already-scored from the
    ## endpoint and are installed verbatim (`setResultsFromServer`), never
    ## re-ranked client-side.
    let q = $getInputValue(inputEl)
    let token = onInput(debouncer)
    setTimeoutMs(proc() =
      if not shouldFire(debouncer, token): return
      fetchSearchResults(cstring(buildSearchRequestUrl(searchCfg.endpoint, q)),
        proc(text: cstring) =
          vm = setResultsFromServer(vm, q, parseSearchResultsJson($text))
          rerender()), debouncer.intervalMs)

  proc runQuery() =
    if isServerMode:
      runServerQuery()
    else:
      vm = setQuery(vm, index, $getInputValue(inputEl))
      rerender()

  proc openOverlay() =
    setAttribute(overlayEl, cstring(searchOpenAttr), "true")
    removeAttribute(overlayEl, "hidden")
    focusElement(inputEl)
    if (not isServerMode) and (not indexFetchStarted):
      ## Client-index path only fetches the index artifact lazily on first
      ## open; server mode has no client index to fetch.
      indexFetchStarted = true
      fetchSearchIndex(indexUrl, proc(text: cstring) =
        index = parseSearchIndexJson($text)
        runQuery()) ## re-rank whatever's already typed once the index lands

  proc closeOverlay() =
    setAttribute(overlayEl, cstring(searchOpenAttr), "false")
    setAttribute(overlayEl, "hidden", "hidden")
    setInputValue(inputEl, "")
    vm = newSearchViewModel()
    rerender()

  proc onInput(ev: Event) =
    runQuery()

  proc onInputKeydown(ev: Event) =
    case $eventKey(ev)
    of "Escape": closeOverlay()
    of "ArrowDown":
      vm = moveCursor(vm, 1)
      rerender()
    of "ArrowUp":
      vm = moveCursor(vm, -1)
      rerender()
    of "Enter":
      let selected = selectedResult(vm)
      if selected.routePath.len > 0:
        navigateTo(cstring(selected.routePath))
    else: discard

  r.addEventListener(inputEl, "input", onInput)
  r.addEventListener(inputEl, "keydown", onInputKeydown)

  proc onDocKeydown(ev: Event) =
    if eventIsCmdK(ev):
      eventPreventDefault(ev)
      openOverlay()
    elif ($eventKey(ev) == "/") and (not activeElementIsTextEntry()):
      eventPreventDefault(ev)
      openOverlay()

  documentAddKeydownListener(onDocKeydown)

## M4 corrective deliverable 3's prefetch cache (see the full section
## below `wireSoftNav`'s forward declaration for `prefetchRoute` itself)
## has to live here, ahead of `buildRouteApp`'s own use of it, since Nim
## requires a name declared before its first use within a module.
var parsedMarkdownDocCache = initTable[string, MarkdownDoc]()

proc buildEmbeddedSymbolIndex(manifest: RouteManifest): Table[string, string] =
  ## M8 deliverable 2: the JS-target counterpart to
  ## `references.buildSymbolIndex` -- the global `[[sym:...]]` query ->
  ## anchor-href map, built from every `pkSymbolReference` page's
  ## compile-time-embedded Nim source (`embeddedNimSources`) instead of a
  ## runtime filesystem read. Tolerant: a route whose source isn't embedded
  ## simply contributes no entries.
  result = initTable[string, string]()
  for entry in manifest.entries:
    if entry.pageKind == pkSymbolReference:
      let raw = embeddedNimSources.getOrDefault(entry.meta.contentPath, "")
      let ingest = parseNimDoc(raw, moduleNameFromPath(entry.meta.contentPath))
      addSymbolIndexEntries(result, ingest.module, entry.canonicalPath)

proc cachedMarkdownDoc(manifest: RouteManifest; contentPath: string;
                        contentEntry: ContentEntry;
                        resolveSymbol: proc(sym: string): string {.closure.} = nil): MarkdownDoc =
  if parsedMarkdownDocCache.hasKey(contentPath):
    return parsedMarkdownDocCache[contentPath]
  result = parseMarkdownDoc(contentEntry.page.body, contentEntry.source.path,
                             makeContentPathResolver(manifest), resolveSymbol)
  parsedMarkdownDocCache[contentPath] = result

proc isMarkdownDocCached*(contentPath: string): bool =
  ## Test seam: true once `contentPath`'s markdown doc has been parsed
  ## and cached -- by a real navigation, or by `prefetchRoute` alone
  ## (proving a hover/viewport trigger actually warmed the cache before
  ## any click happened).
  parsedMarkdownDocCache.hasKey(contentPath)

## --- M7 deliverable 2: IntersectionObserver active-endpoint sync --------
##
## As the reader scrolls the three-column API reference, the left endpoint
## nav highlights the operation currently in view. Modeled on
## `observeForViewportPrefetch`'s own IIFE-wrapped `IntersectionObserver`
## importcpp glue (M4 corrective deliverable 3, commit 5b0fbfe): guarded so
## a host without `IntersectionObserver` (this repo's Node test shims, and
## the C target, which never runs this JS-only proc) silently no-ops. The
## `rootMargin` biases the trigger toward the top of the viewport so the
## highlighted endpoint is the one the reader is actually reading, not the
## last one merely still touching the bottom edge.
proc observeApiSectionVisible(section: Element; onVisible: proc() {.closure.}) {.importcpp:
  """(function(target, cb){
    try {
      if (typeof IntersectionObserver === 'undefined') { return; }
      var obs = new IntersectionObserver(function(entries){
        for (var i = 0; i < entries.length; i++) {
          if (entries[i].isIntersecting) { cb(); }
        }
      }, { rootMargin: '0px 0px -70% 0px' });
      obs.observe(target);
    } catch (e) {}
  })(#, #)""".}

proc wireApiActiveEndpoint[R](r: R; frame: Node) =
  ## Observes every center operation `<section>` (keyed by `apiAnchorAttr`)
  ## and, when one scrolls into view, marks the matching left-nav link
  ## (`apiTargetAttr`) active (`aria-current`/`data-active`), clearing the
  ## rest -- the same class-scoped structural traversal (`attrOrEmpty`,
  ## null-safe) the rest of this module's wiring uses, so it stays inert
  ## under the browser-mount test shims (no `IntersectionObserver`).
  let sections = findAllElementsByClass(frame, cstring(apiOperationClass))
  let navLinks = findAllElementsByClass(frame, cstring(apiNavLinkClass))
  if sections.len == 0 or navLinks.len == 0: return
  for section in sections:
    let anchorId = $attrOrEmpty(section, cstring(apiAnchorAttr))
    proc onVisible() =
      for link in navLinks:
        let isActive = ($attrOrEmpty(link, cstring(apiTargetAttr))) == anchorId
        setAttribute(link, "aria-current", cstring(if isActive: "true" else: "false"))
        setAttribute(link, "data-active", cstring(if isActive: "true" else: "false"))
    observeApiSectionVisible(section, onVisible)

proc buildRouteApp[R](r: R; path: string; manifest: RouteManifest;
                       cfg: DocsConfig): Node =
  ## Shared body for `createRouteApp` (fresh `WebRenderer` build) and
  ## `hydrateRouteApp` (M4 corrective deliverable 1: reuses the
  ## SSR-rendered DOM via `HydratingRenderer`) -- mounts `path` through
  ## the exact same `matchRoute`/`buildShellViewModel`/`renderSiteFrame`
  ## the SSR entry's `renderRoute` uses, so the JS mount path and SSR
  ## agree on the same shell/page structure for every route in the
  ## manifest, on either renderer. `pkMarkdown` routes (M2 deliverable
  ## 4) mount through `renderMarkdownPage` instead, using the same
  ## compile-time-embedded content lookup; every other page kind's
  ## mount path is unchanged from M1. M3's navigation ViewModel is
  ## built off the same `docsRouteManifest()` + `loadEmbeddedContentEntry`
  ## content graph `buildNavPages` pairs on the SSR side, just with the
  ## compile-time-embedded loader instead of a real filesystem read.
  ## M3 deliverable 3's alias redirects are likewise built off the same
  ## embedded content before matching -- the exact same
  ## `buildAliasRouteEntries`/`withAliasRedirects` call `renderRoute`
  ## makes, just with `loadEmbeddedContentEntry` in place of a real
  ## filesystem read, so an old renamed-page link resolves to a real
  ## redirect on both SSR and JS mount, never just one of them. `cfg`
  ## defaults to the framework's own content-agnostic `docsConfig()`
  ## (M1 corrective deliverable 3); a real site passes its own
  ## `DocsConfig` explicitly.
  let aliasEntries = buildAliasRouteEntries(manifest, loadEmbeddedContentEntry)
  let entry = matchRoute(withAliasRedirects(manifest, aliasEntries), path).entry
  if entry.pageKind == pkMarkdown:
    let contentEntry = loadEmbeddedContentEntry(entry.meta.contentPath)
    let symbolIndex = buildEmbeddedSymbolIndex(manifest)
    let resolveSymbol = proc(q: string): string = symbolIndex.getOrDefault(q, "")
    let doc = cachedMarkdownDoc(manifest, entry.meta.contentPath, contentEntry, resolveSymbol)
    let title = if contentEntry.page.title.len > 0: contentEntry.page.title else: entry.meta.title
    let navPages = buildNavPages(manifest, loadEmbeddedContentEntry)
    let navigation = buildNavigationViewModel(navPages, entry.canonicalPath, doc.headingTree)
    result = renderMarkdownPage[R, Node](r, title, doc.blocks, navigation)
  elif entry.pageKind == pkSymbolReference:
    ## M8 deliverable 1: the JS mount counterpart to `ssr.renderRoute`'s
    ## `pkSymbolReference` branch, kept in lock-step -- ingest the
    ## compile-time-embedded Nim source (empty -> tolerant error notice,
    ## never a crash) and mount the same two-column symbol reference page.
    let srcRaw = embeddedNimSources.getOrDefault(entry.meta.contentPath, "")
    let ingest = parseNimDoc(srcRaw, moduleNameFromPath(entry.meta.contentPath))
    let symVm = buildSymbolReferenceViewModel(ingest, entry.meta.title)
    let title = if entry.meta.title.len > 0: entry.meta.title else: symVm.title
    let navPages = buildNavPages(manifest, loadEmbeddedContentEntry)
    let navigation = buildNavigationViewModel(navPages, entry.canonicalPath)
    result = renderSymbolReferencePage[R, Node](r, title, symVm, navigation)
  elif entry.pageKind == pkApiReference:
    ## M7 deliverable 2: the JS mount counterpart to `ssr.renderRoute`'s
    ## `pkApiReference` branch, kept in lock-step -- ingest the
    ## compile-time-embedded spec (empty -> tolerant error notice, never a
    ## crash) and mount the same three-column `renderApiReferencePage`.
    let specRaw = embeddedApiSpecs.getOrDefault(entry.meta.contentPath, "")
    let ingest = ingestOpenApi(specRaw, entry.meta.contentPath)
    let apiVm = buildApiReferenceViewModel(ingest, entry.meta.title)
    let title = if apiVm.title.len > 0: apiVm.title else: entry.meta.title
    let navPages = buildNavPages(manifest, loadEmbeddedContentEntry)
    let navigation = buildNavigationViewModel(navPages, entry.canonicalPath)
    result = renderApiReferencePage[R, Node](r, title, apiVm, navigation)
  else:
    ## M6 deliverable 2: the 404 (and redirect) page RETAINS the site
    ## navigation, so build it from the whole content graph for every page
    ## kind -- kept in lock-step with `ssr.renderRoute`. The active route
    ## is only a real page's own canonical path; a not-found/redirect page
    ## highlights nothing.
    let navPages = buildNavPages(manifest, loadEmbeddedContentEntry)
    let activePath = if entry.status == rsOk: entry.canonicalPath else: ""
    let navigation = buildNavigationViewModel(navPages, activePath)
    let vm = buildShellViewModel(entry, cfg, loadEmbeddedPage, navigation)
    result = renderSiteFrame[R, Node](r, vm)
  wireSearchInteractivity(r, result, buildSearchIndex(manifest, loadEmbeddedContentEntry))
  wireSearchOverlay(r, result)
  wireThemeToggle(r, result)
  wireTabsInteractivity(r, result)
  wireCodeCopyInteractivity(r, result)
  wireSidebarCollapse(r, result)
  wireNavDrawer(r, result)
  wireApiActiveEndpoint(r, result)

proc createRouteApp*(path: string; manifest: RouteManifest = defaultEmbeddedManifest();
                      cfg: DocsConfig = docsConfig()): Node =
  ## Exposed for tests: mounts `path` into a freshly-built tree via a
  ## plain `WebRenderer`, unchanged from before M4.
  buildRouteApp(WebRenderer(), path, manifest, cfg)

proc currentLocationPathname(): cstring {.importcpp:
  "(typeof window !== 'undefined' && window.location && window.location.pathname) ? window.location.pathname : '/'".}
  ## Defensive against a headless test host with no real `window.location`
  ## -- same idiom as `navigateTo` above; a real browser always has one.

# --- M4 corrective deliverable 2: soft SPA navigation ---------------------
##
## Intercepts in-site `<a>` clicks so navigating the docs site never pays
## for a full document reload: the click is prevented, the new route is
## resolved and rendered through the exact same `buildRouteApp` (hence the
## exact same `buildShellViewModel`/`buildNavigationViewModel` the SSR
## entry uses) the initial mount used, `history.pushState` records the new
## URL, and scroll position is saved for the page being left and restored
## for the page being returned to on `popstate` (back/forward). External
## links -- a different origin (no leading "/", or "//" protocol-relative),
## or one carrying an explicit `target`/`rel="external"` -- are left to the
## browser's own default navigation: this module never calls
## `preventDefault` on those, so a real anchor click just does what it
## always would.
##
## Every DOM access below is guarded the same defensive way this module's
## other `importcpp` glue already is (`typeof window !== 'undefined' &&
## ...`) -- `hydrateRouteApp` wires this unconditionally on every mount,
## and several existing browser-mount suites (e.g.
## `test_hydration_browser_mount.nim`) stub a minimal `window` with no
## `location`/`history`/`addEventListener`/`scrollTo` at all, so an
## unguarded call here would take down every existing hydration suite,
## not just add a new one.

proc eventCtrlKey(e: Event): bool {.importcpp: "(!!(#.ctrlKey))".}
proc eventMetaKey(e: Event): bool {.importcpp: "(!!(#.metaKey))".}
proc eventAltKey(e: Event): bool {.importcpp: "(!!(#.altKey))".}
proc eventButton(e: Event): int {.importcpp: "((#.button)|0)".}
  ## `eventShiftKey`/`eventPreventDefault`/`hasAttribute` moved up next to
  ## `eventKey` (M4 deliverable 1's search glue) so M5 corrective
  ## deliverable 1's sidebar-collapse/nav-drawer wiring can use them too
  ## without a forward declaration -- see that definition's own comment.

proc historyPushState(path: cstring) {.importcpp:
  "(typeof window !== 'undefined' && window.history && window.history.pushState) && window.history.pushState({}, '', #)".}

proc addPopStateListener(handler: proc() {.closure.}) {.importcpp:
  "(typeof window !== 'undefined' && window.addEventListener) && window.addEventListener('popstate', #)".}

proc scrollWindowTo(x, y: int) {.importcpp:
  "(typeof window !== 'undefined' && window.scrollTo) && window.scrollTo(#, #)".}

proc windowScrollX(): int {.importcpp:
  "(typeof window !== 'undefined' && window.scrollX) ? window.scrollX : 0".}

proc windowScrollY(): int {.importcpp:
  "(typeof window !== 'undefined' && window.scrollY) ? window.scrollY : 0".}

var softNavCurrentPath = ""
var softNavScrollPositions = initTable[string, tuple[x, y: int]]()
  ## Module-scope (page-lifetime) state: a real browser only ever
  ## hydrates one page per load, so this never needs to be reset or
  ## scoped to a particular mount.

proc isInSiteHref(href: string): bool =
  ## An absolute in-site path: leading "/" but not "//" (that's
  ## protocol-relative, i.e. cross-origin). Fragment-only links
  ## ("#heading"), `http(s)://`/`mailto:`/relative hrefs, and empty
  ## hrefs are all left for the browser's default handling -- every
  ## real in-site link this framework renders is already an absolute
  ## `RouteEntry.canonicalPath`-derived href (see `navigation_view.nim`/
  ## `markdown_view.nim`), so this is a precise, not just approximate,
  ## in-site test.
  href.len > 0 and href[0] == '/' and (href.len == 1 or href[1] != '/')

proc anchorHref(a: Element): string =
  if hasAttribute(a, "href"): $getAttribute(a, "href") else: ""

proc qualifiesForSoftNav(a: Element): bool =
  ## Shared eligibility check for both click-interception (`onClick`
  ## below) and prefetch triggers (M4 corrective deliverable 3's hover/
  ## viewport wiring) -- a link the click handler would never intercept
  ## (an explicit `target`, `rel="external"`, or not an in-site href) is
  ## never worth warming the cache for either: the real navigation, if
  ## any, would be a full browser load that never reads it.
  if hasAttribute(a, "target"): return false
  if hasAttribute(a, "rel") and ($getAttribute(a, "rel")).contains("external"): return false
  isInSiteHref(anchorHref(a))

proc findAllElementsByTag(root: Node; tag: string): seq[Element] =
  ## Depth-first collection of every descendant `<tag>` element --
  ## mirrors `findAllElementsByClass`'s own idiom above, just keyed off
  ## `tagName` (always present on a real element, unlike `class`)
  ## instead of a class attribute.
  if root.isNodeNil: return
  if root.nodeType == 1:
    let el = Element(root)
    if ($el.tagName).toLowerAscii == tag:
      result.add el
  for child in root.childNodes:
    result.add findAllElementsByTag(child, tag)

proc wireSoftNav(rootEl: Element; manifest: RouteManifest; cfg: DocsConfig)
  ## Forward-declared: `wireSoftNavLink`'s click handler navigates, which
  ## re-renders and needs to re-wire the fresh tree's own links -- the
  ## two are mutually recursive.

proc routePathFromHref(href: string): string =
  ## The exact hash-stripping + normalization `navigateSoft` and
  ## `prefetchRoute` both need to turn a raw `href` into the route path
  ## `matchRoute` resolves against -- one shared helper rather than two
  ## copies of the same two lines.
  let hashIdx = href.find('#')
  normalizeRoutePath(if hashIdx >= 0: href[0 ..< hashIdx] else: href)

# --- M4 corrective deliverable 3: prefetch on hover/viewport --------------
##
## Warms the one genuinely expensive per-route step (`parseMarkdownDoc`'s
## real markdown parse) ahead of an actual navigation, keyed by
## `RouteMeta.contentPath` so a hover or an on-screen appearance for a
## given link pays that cost once, and the real click navigation later
## (through the exact same `buildRouteApp`/`cachedMarkdownDoc` call this
## module's initial mount and every route swap already go through -- no
## second, prefetch-specific rendering path) just reuses it. Resolves
## through the exact same `matchRoute`/`buildAliasRouteEntries`/
## `withAliasRedirects` call `buildRouteApp` makes, so a prefetch and the
## real navigation it warms always agree on the same target route.

proc prefetchRoute(manifest: RouteManifest; href: string) =
  if not isInSiteHref(href): return
  let path = routePathFromHref(href)
  if path == softNavCurrentPath: return ## already the live route/its content
  let aliasEntries = buildAliasRouteEntries(manifest, loadEmbeddedContentEntry)
  let entry = matchRoute(withAliasRedirects(manifest, aliasEntries), path).entry
  if entry.pageKind == pkMarkdown:
    let contentEntry = loadEmbeddedContentEntry(entry.meta.contentPath)
    let symbolIndex = buildEmbeddedSymbolIndex(manifest)
    let resolveSymbol = proc(q: string): string = symbolIndex.getOrDefault(q, "")
    discard cachedMarkdownDoc(manifest, entry.meta.contentPath, contentEntry, resolveSymbol)

proc observeForViewportPrefetch(a: Element; onVisible: proc() {.closure.}) {.importcpp:
  """(function(target, cb){
    try {
      if (typeof IntersectionObserver === 'undefined') { return; }
      var obs = new IntersectionObserver(function(entries){
        for (var i = 0; i < entries.length; i++) {
          if (entries[i].isIntersecting) {
            cb();
            obs.unobserve(target);
            obs.disconnect();
          }
        }
      });
      obs.observe(target);
    } catch (e) {}
  })(#, #)""".}
  ## Wraps the whole observer construction in a single IIFE taking `a`/
  ## `onVisible` as its own JS-local `target`/`cb` params, so the body can
  ## reference `target` twice (`observe`/`unobserve`) without needing a
  ## repeated `#` placeholder for the same formal parameter (Nim's JS
  ## backend maps each `#` to the NEXT parameter in order -- see the
  ## `hasAttribute`-style two-`#`-two-param idiom used elsewhere in this
  ## file; this sidesteps that limit for a param needed more than once).
  ## Guarded the same defensive way as every other `window`-touching glue
  ## in this module: this repo's own `nim js -r` DOM shims (and Node
  ## itself) have no real `IntersectionObserver`, so this silently no-ops
  ## under test -- a real browser always has one. `unobserve`+`disconnect`
  ## on first intersection: one prefetch per link is all `cachedMarkdownDoc`
  ## needs, no point keeping the observer alive after that.

proc saveScrollForCurrentPath() =
  if softNavCurrentPath.len > 0:
    softNavScrollPositions[softNavCurrentPath] = (windowScrollX(), windowScrollY())

proc restoreScrollFor(path: string) =
  let pos = softNavScrollPositions.getOrDefault(path, (0, 0))
  scrollWindowTo(pos.x, pos.y)

# --- M4 corrective deliverable 3: loading indicator for slow routes -------
##
## A single, page-lifetime indicator element (created lazily on the first
## route swap, never on the initial hydration mount -- the initial page
## load isn't a "route change") toggled true/immediately-false around
## every swap below, exactly the "start" and "complete" events a real
## async router fires. It's a *sibling* of `rootEl` (appended to `rootEl`'s
## own parent), not a child, so `swapRouteContent`'s `clearChildren(rootEl)`
## never touches it. This repo's own route content is 100% synchronous
## (compile-time-embedded + parsed in-memory, see `embeddedContent` above),
## so the indicator flips back to hidden well within the same tick it was
## shown in -- CSS (`.docs-route-loading`'s `transition-delay`, see
## `assets/style.css`) is what makes that a real "never visible for a fast
## route", not a JS timer race: a real browser only starts the opacity
## transition after the delay elapses, and resets it if the attribute
## flips back to `false` first, exactly like this framework's other
## delay-based CSS techniques. A consumer whose own content loading is
## genuinely asynchronous (e.g. a real network fetch in place of
## `loadEmbeddedPage`) gets a real, visible indicator for free, with zero
## change to this wiring.

const loadingIndicatorClass = "docs-route-loading"
var loadingIndicatorNode: Node

proc ensureLoadingIndicator(rootEl: Element): Element =
  if loadingIndicatorNode.isNodeNil:
    let el = createElement(document, "div")
    setAttribute(el, "class", cstring(loadingIndicatorClass))
    setAttribute(el, "role", "status")
    setAttribute(el, "data-visible", "false")
    let parent = rootEl.parentNode
    if not parent.isNodeNil:
      discard appendChild(parent, Node(el))
    loadingIndicatorNode = Node(el)
  Element(loadingIndicatorNode)

proc showLoadingIndicator*(rootEl: Element) =
  setAttribute(ensureLoadingIndicator(rootEl), "data-visible", "true")

proc hideLoadingIndicator*(rootEl: Element) =
  if loadingIndicatorNode.isNodeNil: return
  setAttribute(Element(loadingIndicatorNode), "data-visible", "false")

proc loadingIndicatorEl*(): Element =
  ## Test seam: nil (via `Node(result).isNodeNil`) until the first route
  ## swap creates it.
  Element(loadingIndicatorNode)

proc swapRouteContent(rootEl: Element; manifest: RouteManifest; cfg: DocsConfig;
                       path: string) =
  ## The shared "replace `rootEl`'s content with `path`'s route" step
  ## both a click-driven soft nav and a `popstate` swap use: a plain
  ## `WebRenderer` fresh build (there is no existing DOM to hydrate
  ## against once the previous route's content is cleared) through the
  ## exact same `buildRouteApp` the initial mount and `createRouteApp`
  ## use, so every route swap agrees with SSR on the same ViewModels.
  showLoadingIndicator(rootEl)
  let r = WebRenderer()
  r.clearChildren(rootEl)
  let built = buildRouteApp(r, path, manifest, cfg)
  r.appendChild(rootEl, built)
  softNavCurrentPath = path
  wireSoftNav(rootEl, manifest, cfg)
  hideLoadingIndicator(rootEl)

proc navigateSoft(rootEl: Element; manifest: RouteManifest; cfg: DocsConfig;
                   href: string) =
  let path = routePathFromHref(href)
  if path == softNavCurrentPath: return
  saveScrollForCurrentPath()
  swapRouteContent(rootEl, manifest, cfg, path)
  historyPushState(cstring(path))
  scrollWindowTo(0, 0) ## a fresh forward navigation starts at the top,
    ## same convention every mainstream SPA router uses; the prior page's
    ## own scroll position was just saved above, for when the user comes
    ## back to it.

proc wireSoftNavLink(rootEl: Element; manifest: RouteManifest; cfg: DocsConfig;
                      a: Element) =
  proc onClick(ev: Event) =
    if eventCtrlKey(ev) or eventMetaKey(ev) or eventShiftKey(ev) or eventAltKey(ev): return
    if eventButton(ev) != 0: return ## only a plain left click soft-navigates
    if not qualifiesForSoftNav(a): return
    eventPreventDefault(ev)
    navigateSoft(rootEl, manifest, cfg, anchorHref(a))
  proc onPrefetchTrigger() =
    if qualifiesForSoftNav(a): prefetchRoute(manifest, anchorHref(a))
  WebRenderer().addEventListener(a, "click", onClick)
  WebRenderer().addEventListener(a, "mouseenter", proc(ev: Event) = onPrefetchTrigger())
  observeForViewportPrefetch(a, onPrefetchTrigger)

proc wireSoftNav(rootEl: Element; manifest: RouteManifest; cfg: DocsConfig) =
  for a in findAllElementsByTag(Node(rootEl), "a"):
    wireSoftNavLink(rootEl, manifest, cfg, a)

proc wireSoftNavPopState(rootEl: Element; manifest: RouteManifest; cfg: DocsConfig) =
  proc onPopState() =
    let path = normalizeRoutePath($currentLocationPathname())
    if path == softNavCurrentPath: return
    saveScrollForCurrentPath()
    swapRouteContent(rootEl, manifest, cfg, path)
    restoreScrollFor(path)
  addPopStateListener(onPopState)

proc hydrateRouteApp*(rootEl: Element; path: string;
                       manifest: RouteManifest = defaultEmbeddedManifest();
                       cfg: DocsConfig = docsConfig()): Node =
  ## M4 corrective deliverable 1: `createRouteApp`'s hydrating
  ## counterpart -- attaches to `rootEl`'s existing (SSR-rendered)
  ## children via `HydratingRenderer` instead of a full fresh render,
  ## so real node identity is preserved wherever the SSR and client
  ## trees line up structurally, then wires the exact same
  ## search/theme/tabs/code-copy interactivity `createRouteApp` does --
  ## against the reused (not newly-created) DOM nodes, since
  ## `buildRouteApp`'s `result` tree IS (where matched) the original
  ## SSR elements. See `hydrateApp` for why `createRoot` wraps this.
  ## M4 corrective deliverable 2 also wires soft-nav link interception
  ## and the `popstate` handler here -- the real production mount is the
  ## one place both need to happen exactly once, against the real
  ## (post-hydration) live DOM.
  let r = newHydratingRenderer(rootEl)
  var built: Node
  createRoot proc(dispose: proc()) =
    built = buildRouteApp(r, path, manifest, cfg)
  discard dom_api.appendChild(Node(rootEl), built)
  softNavCurrentPath = normalizeRoutePath(path)
  wireSoftNav(rootEl, manifest, cfg)
  wireSoftNavPopState(rootEl, manifest, cfg)
  built

when isMainModule:
  ## Production mount: M4 corrective deliverable 1 replaces M0's fixed
  ## single-route `createApp` + full fresh `render` with a real,
  ## route-aware hydration mount that reuses `#root`'s SSR-rendered DOM.
  let rootEl = document.getElementById("root")
  discard hydrateRouteApp(rootEl, $currentLocationPathname())
