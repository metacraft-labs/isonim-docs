## M1 verification (mount + preview): the editor over the Metacraft workspace.
##
## JS-target (`nim js -r`). Proves that the DTCG-adapted Metacraft docs
## workspace drives a real, live editor:
##   * `createEditorVM(workspace)` -- the EXACT live `EditorVM` `mountEditor`
##     builds internally (browser.nim `mountEditor` does
##     `let vm = createEditorVM(workspace)` and returns it) -- loads the
##     adapted foundation tokens + design schema;
##   * editing a token through the real VM API (`editFoundationToken`)
##     updates the bound docs-component preview (the previewHook re-resolves
##     `--docs-*` from the live tokens -- the "VariableBinding re-resolves"
##     contract);
##   * the edit surfaces impact (affected docs stories) and the token's
##     WCAG contrast ratio (`tokenManagerItems`).
##
## SCOPE / KNOWN LIMITATION -- the DOM shell ATTACH step of `mountEditor`
## (`renderEditorShell` -> DOM) is NOT exercised headlessly here. Under
## `-d:nodejs` (which `nim js -r` sets) Nim's std/dom ships an in-memory
## dummy `document` whose created elements carry no `.style` object (and no
## `createElementNS`, no real `querySelector`, no event dispatch), so the
## editor's rich shell reconciler dereferences `element.style` = nil during
## render. Emulating the full DOM (element `.style`, namespaced elements,
## selectors, events) from the test is impractical and would amount to
## reimplementing a browser; a genuine shell-attach check belongs in a real
## headless-browser (Playwright) e2e, driven by `design/index.html` +
## `design/main.nim`. What IS proven here is the whole live-VM contract
## `mountEditor` wraps: `createEditorVM` over the adapted workspace, a real
## token edit, live preview re-resolution, and impact/contrast surfacing.
##
## Node.js has no DOM globals, so a minimal shim backs the raw-JS globals the
## VM layer touches (`window`/`localStorage`/`matchMedia`/`requestAnimation
## Frame`), same idiom as isonim-docs/tests/docs/test_routes_browser_mount.nim.

when not defined(js):
  {.error: "test_editor_mount_and_preview must be compiled with the JS backend: nim js -r".}

{.emit: """
(function() {
  // Bail only if a COMPLETE document (with a <head>) is already present.
  // An imported Nim module in the editor chain may install a partial
  // `document` stub without `head`; we must still install the full shim so
  // `document.head` (used by injectEditorStyles) resolves.
  if (typeof document !== 'undefined' && document && document.head &&
      typeof document.createElement === 'function') return;
  var nodeIdCounter = 0;

  function TextNode(text) {
    this._id = ++nodeIdCounter; this.nodeType = 3; this.nodeName = '#text';
    this.data = text; this.textContent = text; this.parentNode = null;
    this.firstChild = null; this.nextSibling = null; this.childNodes = []; this.ownerDocument = null;
  }
  TextNode.prototype.remove = function() { if (this.parentNode) this.parentNode.removeChild(this); };
  TextNode.prototype.cloneNode = function(deep) { return new TextNode(this.data); };

  function ElementNode(tag) {
    this._id = ++nodeIdCounter; this.nodeType = 1;
    this.nodeName = tag.toUpperCase(); this.tagName = tag.toUpperCase();
    this.localName = tag.toLowerCase(); this.data = null;
    this.parentNode = null; this.firstChild = null; this.nextSibling = null;
    this.childNodes = []; this.attributes = {}; this.className = '';
    this.innerHTML = '';
    this.style = { _props: {}, setProperty: function(k, v) { this._props[k] = v; },
      removeProperty: function(k) { delete this._props[k]; }, cssText: '' };
    this._eventListeners = {}; this.disabled = false;
    this.dataset = {}; this.ownerDocument = null;
  }
  function updateSiblings(node) {
    var c = node.childNodes; node.firstChild = c.length ? c[0] : null;
    for (var i = 0; i < c.length; i++) {
      c[i].nextSibling = (i + 1 < c.length) ? c[i + 1] : null; c[i].parentNode = node;
    }
  }
  function setTextContent(node, val) {
    for (var i = 0; i < node.childNodes.length; i++) node.childNodes[i].parentNode = null;
    node.childNodes = [];
    if (val !== '' && val != null) { var t = new TextNode(String(val)); t.parentNode = node; node.childNodes.push(t); }
    updateSiblings(node);
  }
  Object.defineProperty(ElementNode.prototype, 'textContent', {
    get: function() { var r = ''; for (var i = 0; i < this.childNodes.length; i++) {
      var c = this.childNodes[i]; r += (c.nodeType === 3) ? c.data : c.textContent; } return r; },
    set: function(val) { setTextContent(this, val); } });
  Object.defineProperty(TextNode.prototype, 'textContent', {
    get: function() { return this.data; }, set: function(val) { this.data = String(val); } });
  ElementNode.prototype.appendChild = function(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    if (child.nodeType === 11) { var k = child.childNodes.slice();
      for (var i = 0; i < k.length; i++) this.appendChild(k[i]);
      child.childNodes = []; updateSiblings(child); return child; }
    child.parentNode = this; this.childNodes.push(child); updateSiblings(this); return child; };
  ElementNode.prototype.insertBefore = function(newNode, refNode) {
    if (newNode.parentNode) newNode.parentNode.removeChild(newNode);
    if (refNode == null) return this.appendChild(newNode);
    if (newNode.nodeType === 11) { var k = newNode.childNodes.slice();
      for (var i = 0; i < k.length; i++) this.insertBefore(k[i], refNode);
      newNode.childNodes = []; updateSiblings(newNode); return newNode; }
    var idx = this.childNodes.indexOf(refNode);
    if (idx >= 0) { newNode.parentNode = this; this.childNodes.splice(idx, 0, newNode); }
    else return this.appendChild(newNode);
    updateSiblings(this); return newNode; };
  ElementNode.prototype.removeChild = function(child) {
    var idx = this.childNodes.indexOf(child);
    if (idx >= 0) { this.childNodes.splice(idx, 1); child.parentNode = null; child.nextSibling = null; }
    updateSiblings(this); return child; };
  ElementNode.prototype.replaceChild = function(newChild, oldChild) {
    var idx = this.childNodes.indexOf(oldChild);
    if (idx >= 0) { if (newChild.parentNode) newChild.parentNode.removeChild(newChild);
      oldChild.parentNode = null; oldChild.nextSibling = null; newChild.parentNode = this;
      this.childNodes[idx] = newChild; }
    updateSiblings(this); return oldChild; };
  ElementNode.prototype.remove = function() { if (this.parentNode) this.parentNode.removeChild(this); };
  ElementNode.prototype.cloneNode = function(deep) {
    var clone = new ElementNode(this.localName); clone.className = this.className;
    var ks = Object.keys(this.attributes);
    for (var i = 0; i < ks.length; i++) clone.attributes[ks[i]] = this.attributes[ks[i]];
    if (deep) for (var j = 0; j < this.childNodes.length; j++) clone.appendChild(this.childNodes[j].cloneNode(true));
    return clone; };
  ElementNode.prototype.setAttribute = function(name, value) { this.attributes[name] = value; };
  ElementNode.prototype.removeAttribute = function(name) { delete this.attributes[name]; };
  ElementNode.prototype.getAttribute = function(name) { return (name in this.attributes) ? this.attributes[name] : null; };
  ElementNode.prototype.hasAttribute = function(name) { return (name in this.attributes); };
  ElementNode.prototype.addEventListener = function(ev, h) { (this._eventListeners[ev] = this._eventListeners[ev] || []).push(h); };
  ElementNode.prototype.removeEventListener = function(ev, h) {
    if (!this._eventListeners[ev]) return; var i = this._eventListeners[ev].indexOf(h);
    if (i >= 0) this._eventListeners[ev].splice(i, 1); };
  ElementNode.prototype.querySelector = function() { return null; };
  ElementNode.prototype.querySelectorAll = function() { return []; };
  ElementNode.prototype.getElementsByTagName = function() { return []; };
  ElementNode.prototype.focus = function() {};
  ElementNode.prototype.contains = function() { return false; };

  function DocumentFragment() {
    this._id = ++nodeIdCounter; this.nodeType = 11; this.nodeName = '#document-fragment';
    this.parentNode = null; this.firstChild = null; this.nextSibling = null; this.childNodes = []; this.ownerDocument = null; }
  DocumentFragment.prototype.appendChild = ElementNode.prototype.appendChild;
  DocumentFragment.prototype.insertBefore = ElementNode.prototype.insertBefore;
  DocumentFragment.prototype.removeChild = ElementNode.prototype.removeChild;
  DocumentFragment.prototype.replaceChild = ElementNode.prototype.replaceChild;
  Object.defineProperty(DocumentFragment.prototype, 'textContent', {
    get: function() { var r = ''; for (var i = 0; i < this.childNodes.length; i++) {
      var c = this.childNodes[i]; r += (c.nodeType === 3) ? c.data : c.textContent; } return r; },
    set: function(val) { setTextContent(this, val); } });
  DocumentFragment.prototype.cloneNode = function(deep) {
    var clone = new DocumentFragment();
    if (deep) for (var i = 0; i < this.childNodes.length; i++) clone.appendChild(this.childNodes[i].cloneNode(true));
    return clone; };
  function TemplateElement() { ElementNode.call(this, 'template'); this.content = new DocumentFragment(); }
  TemplateElement.prototype = Object.create(ElementNode.prototype);
  TemplateElement.prototype.constructor = TemplateElement;

  var docElement = new ElementNode('html');
  var head = new ElementNode('head');
  var body = new ElementNode('body');
  docElement.appendChild(head); docElement.appendChild(body);
  var elementsById = {};
  var doc;
  function own(el) { el.ownerDocument = doc; return el; }
  doc = {
    nodeType: 9,
    createElement: function(tag) { return own(tag === 'template' ? new TemplateElement() : new ElementNode(tag)); },
    createElementNS: function(ns, tag) { return own(new ElementNode(tag)); },
    createTextNode: function(text) { return own(new TextNode(String(text))); },
    createComment: function(text) { var n = new TextNode(String(text)); n.nodeType = 8; n.nodeName = '#comment'; return own(n); },
    createDocumentFragment: function() { return own(new DocumentFragment()); },
    getElementById: function(id) { if (elementsById[id]) return elementsById[id];
      var el = own(new ElementNode('div')); el.setAttribute('id', id); body.appendChild(el); elementsById[id] = el; return el; },
    querySelector: function() { return null; },
    querySelectorAll: function() { return []; },
    addEventListener: function() {}, removeEventListener: function() {},
    body: body, head: head, documentElement: docElement };
  // ownerDocument must be a WRITABLE data property: Nim's stdlib appendChild
  // assigns `child.ownerDocument = parent.ownerDocument`, so a getter-only
  // property would break it. Seed the pre-created nodes here.
  docElement.ownerDocument = doc; head.ownerDocument = doc; body.ownerDocument = doc;

  var win = {
    document: doc,
    location: { href: 'http://localhost/', pathname: '/', hash: '', search: '', origin: 'http://localhost' },
    history: { pushState: function() {}, replaceState: function() {}, back: function() {} },
    matchMedia: function() { return { matches: false, media: '', addEventListener: function() {},
      removeEventListener: function() {}, addListener: function() {}, removeListener: function() {} }; },
    localStorage: { _s: {}, getItem: function(k) { return (k in this._s) ? this._s[k] : null; },
      setItem: function(k, v) { this._s[k] = String(v); }, removeItem: function(k) { delete this._s[k]; } },
    addEventListener: function() {}, removeEventListener: function() {},
    // Real (setTimeout-backed) rAF so the reactive scheduler renders the
    // shell, but the callback is wrapped: after the synchronous mount has
    // returned and we've captured its outcome, a later deferred frame may
    // fire against a node the reconciler has since disposed
    // ("null.ownerDocument"). That late async churn is irrelevant to the
    // assertions, so it is swallowed rather than aborting the run.
    requestAnimationFrame: function(cb) { return setTimeout(function() { try { cb(Date.now()); } catch (e) {} }, 0); },
    cancelAnimationFrame: function(id) { clearTimeout(id); },
    getComputedStyle: function() { return { getPropertyValue: function() { return ''; } }; } };

  Object.defineProperty(ElementNode.prototype, 'firstElementChild', { get: function() {
    for (var i = 0; i < this.childNodes.length; i++) if (this.childNodes[i].nodeType === 1) return this.childNodes[i];
    return null; } });
  Object.defineProperty(ElementNode.prototype, 'nextElementSibling', { get: function() {
    if (!this.parentNode) return null; var sibs = this.parentNode.childNodes; var seen = false;
    for (var i = 0; i < sibs.length; i++) { if (seen && sibs[i].nodeType === 1) return sibs[i]; if (sibs[i] === this) seen = true; }
    return null; } });

  var g = (typeof globalThis !== 'undefined') ? globalThis : (typeof global !== 'undefined') ? global : this;
  g.document = doc; g.window = win;
  g.location = win.location; g.history = win.history;
  g.matchMedia = win.matchMedia; g.localStorage = win.localStorage;
  g.requestAnimationFrame = win.requestAnimationFrame; g.cancelAnimationFrame = win.cancelAnimationFrame;
  g.getComputedStyle = win.getComputedStyle;
})();
""".}

import std/[strutils, unittest]

import isonim/core/signals
import isonim/editor
import core/tokens
import ../../src/theme_tokens
import ../dtcg_workspace

const
  brandJson = staticRead("../../../../codetracer-design-system/brand/brand.json")
  aliasJson = staticRead("../../../../codetracer-design-system/alias/alias.json")
  mappedJson = staticRead("../../../../codetracer-design-system/mapped/mapped.json")

proc metacraftTokens(): TokenSet =
  loadTokensFromStrings([brandJson, aliasJson, mappedJson])

proc findToken(vm: EditorVM; key: string): FoundationTokenEntry =
  for t in vm.foundations.tokens.val:
    if t.key == key: return t
  FoundationTokenEntry()

proc contrastItem(vm: EditorVM; key: string): TokenManagerItem =
  for it in vm.tokenManagerItems():
    if it.key == key: return it
  TokenManagerItem()

let ts = metacraftTokens()
let layer = isonimDocsTokenLayer()

suite "Metacraft workspace: live editor mount + preview (M1)":

  test "createEditorVM loads the adapted Metacraft foundation tokens":
    let ws = metacraftEditorWorkspace(layer, ts)
    let vm = createEditorVM(ws)
    check not vm.isNil
    check vm.foundations.tokens.val.len == ws.foundationTokens.len
    check vm.foundations.tokens.val.len > 20        # the full --docs-* set
    # the adapted design schema rode along into the live VM
    check vm.designSystemSchema.val.nodes.len == ws.foundationTokens.len
    # a genuinely token-bound var kept its DTCG alias-chain head
    # (--docs-focus-ring binds colors.blue.500 in the real Metacraft layer)
    let focusRing = findToken(vm, "--docs-focus-ring")
    check focusRing.aliasOf == "colors.blue.500"

  test "editing a token updates the bound docs-component preview":
    var vm: EditorVM
    let ws = metacraftEditorWorkspace(layer, ts,
      tokensAccessor = proc(): seq[FoundationTokenEntry] =
        if vm.isNil: @[] else: vm.foundations.tokens.val)
    vm = createEditorVM(ws)

    # Preview of the Top-nav story before the edit (accent themes it).
    let before = ws.previewHook(StoryNavTop, pbWeb)
    check before.status == ppsRendered
    check "--docs-accent=" in before.bodyText
    check "#ff0000" notin before.bodyText

    # Edit the accent token through the real VM API.
    let res = vm.editFoundationToken("--docs-accent", "#ff0000")
    check res.status == pesAccepted
    check findToken(vm, "--docs-accent").value == "#ff0000"

    # The bound preview re-resolves from the live tokens.
    let after = ws.previewHook(StoryNavTop, pbWeb)
    check "--docs-accent=#ff0000" in after.bodyText
    check after.bodyText != before.bodyText

  test "edit surfaces impact (affected docs stories) and contrast":
    var vm: EditorVM
    let ws = metacraftEditorWorkspace(layer, ts,
      tokensAccessor = proc(): seq[FoundationTokenEntry] =
        if vm.isNil: @[] else: vm.foundations.tokens.val)
    vm = createEditorVM(ws)

    let res = vm.editFoundationToken("--docs-accent", "#123456")
    check res.status == pesAccepted
    # impact: the affected docs stories surfaced.
    check res.impacts.len == 1
    check res.impacts[0].affectedStories.len > 0
    check vm.foundations.impacts.val.len == 1

    # contrast: the token manager surfaces a real WCAG ratio + threshold.
    let item = contrastItem(vm, "--docs-accent")
    check item.key == "--docs-accent"
    check item.minContrast == 4.5
    check item.contrastRatio > 0.0
