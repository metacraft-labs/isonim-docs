## Tier 3 (JS browser mount) M5 deliverable 2 suite -- JS-target only.
##
## Proves `src/main_web.nim`'s keyboard-triggered search overlay (wired
## inside `hydrateRouteApp`/`createRouteApp` via `wireSearchOverlay`):
##  - a global `Cmd/Ctrl+K` opens the overlay (`data-open` flips to true),
##  - a global `/` opens it too, but ONLY when focus is not already in a
##    text input/textarea/contenteditable,
##  - `Esc` closes it,
##  - `ArrowDown`/`ArrowUp` move the keyboard cursor,
##  - `Enter` navigates to the highlighted result,
##  - matched query terms are wrapped in real `<mark>` elements, and
##  - the index is fetched LAZILY on first open (never at page load): the
##    fetch stub below is only ever consulted once the overlay opens.
##
## `nim js -r` runs under Node.js, which has no DOM. This shim is the
## `document`-only shim `test_search_browser_mount.nim`/
## `test_nav_drawer_browser_mount.nim` use (real `.value`, `dispatchEvent`,
## `.focus()`/`document.activeElement`, `innerHTML`), EXTENDED with the
## three things this suite alone needs: a `document.addEventListener`/
## `dispatchEvent` pair (the overlay's open shortcut is the one genuinely
## document-global listener the framework wires), a synchronous-thenable
## `fetch` stub returning a fixed index JSON (so the lazy fetch resolves
## in-line and the result list can be asserted without awaiting), and a
## `window.location` stub so `Enter` navigation is observable. Every one of
## these is guarded `typeof`-style in `main_web.nim`, so the OTHER mount
## suites (whose shims lack them) keep silently no-oping -- see
## `isonim-docs-nim-js-gotchas` project memory.

when not defined(js):
  {.error: "test_search_shortcuts_browser_mount must be compiled with the JS backend: nim js -r tests/docs/test_search_shortcuts_browser_mount.nim".}

{.emit: """
// ---- DOM shim for Node.js (search-overlay superset) ----
(function() {
  if (typeof document !== 'undefined') return;

  var nodeIdCounter = 0;

  function TextNode(text) {
    this._id = ++nodeIdCounter;
    this.nodeType = 3; this.nodeName = '#text';
    this.data = text; this.parentNode = null;
    this.firstChild = null; this.nextSibling = null; this.childNodes = [];
  }
  TextNode.prototype.remove = function() { if (this.parentNode) this.parentNode.removeChild(this); };
  TextNode.prototype.cloneNode = function(deep) { return new TextNode(this.data); };

  function ElementNode(tag) {
    this._id = ++nodeIdCounter;
    this.nodeType = 1;
    this.nodeName = tag.toUpperCase();
    this.tagName = tag.toUpperCase();
    this.localName = tag.toLowerCase();
    this.data = null;
    this.parentNode = null; this.firstChild = null; this.nextSibling = null;
    this.childNodes = [];
    this.attributes = {};
    this.className = '';
    this.style = { _props: {}, setProperty: function(k, v){this._props[k]=v;}, removeProperty: function(k){delete this._props[k];}, cssText: '' };
    this._eventListeners = {};
    this.disabled = false;
    this.value = '';
    this.isContentEditable = false;
  }

  function updateSiblings(node) {
    var children = node.childNodes;
    node.firstChild = children.length > 0 ? children[0] : null;
    for (var i = 0; i < children.length; i++) {
      children[i].nextSibling = (i + 1 < children.length) ? children[i + 1] : null;
      children[i].parentNode = node;
    }
  }

  function setTextContent(node, val) {
    for (var i = 0; i < node.childNodes.length; i++) node.childNodes[i].parentNode = null;
    node.childNodes = [];
    if (val !== '' && val != null) {
      var t = new TextNode(String(val)); t.parentNode = node; node.childNodes.push(t);
    }
    updateSiblings(node);
  }

  Object.defineProperty(ElementNode.prototype, 'textContent', {
    get: function() {
      var result = '';
      for (var i = 0; i < this.childNodes.length; i++) {
        var c = this.childNodes[i];
        if (c.nodeType === 3) result += c.data; else result += c.textContent;
      }
      return result;
    },
    set: function(val) { setTextContent(this, val); }
  });
  Object.defineProperty(TextNode.prototype, 'textContent', {
    get: function() { return this.data; },
    set: function(val) { this.data = String(val); }
  });

  ElementNode.prototype.appendChild = function(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    if (child.nodeType === 11) {
      var kids = child.childNodes.slice();
      for (var i = 0; i < kids.length; i++) this.appendChild(kids[i]);
      child.childNodes = []; updateSiblings(child); return child;
    }
    child.parentNode = this; this.childNodes.push(child); updateSiblings(this); return child;
  };
  ElementNode.prototype.insertBefore = function(newNode, refNode) {
    if (newNode.parentNode) newNode.parentNode.removeChild(newNode);
    if (refNode == null) return this.appendChild(newNode);
    if (newNode.nodeType === 11) {
      var kids = newNode.childNodes.slice();
      for (var i = 0; i < kids.length; i++) this.insertBefore(kids[i], refNode);
      newNode.childNodes = []; updateSiblings(newNode); return newNode;
    }
    var idx = this.childNodes.indexOf(refNode);
    if (idx >= 0) { newNode.parentNode = this; this.childNodes.splice(idx, 0, newNode); }
    else return this.appendChild(newNode);
    updateSiblings(this); return newNode;
  };
  ElementNode.prototype.removeChild = function(child) {
    var idx = this.childNodes.indexOf(child);
    if (idx >= 0) { this.childNodes.splice(idx, 1); child.parentNode = null; child.nextSibling = null; }
    updateSiblings(this); return child;
  };
  ElementNode.prototype.replaceChild = function(newChild, oldChild) {
    var idx = this.childNodes.indexOf(oldChild);
    if (idx >= 0) {
      if (newChild.parentNode) newChild.parentNode.removeChild(newChild);
      oldChild.parentNode = null; oldChild.nextSibling = null;
      newChild.parentNode = this; this.childNodes[idx] = newChild;
    }
    updateSiblings(this); return oldChild;
  };
  ElementNode.prototype.remove = function() { if (this.parentNode) this.parentNode.removeChild(this); };
  ElementNode.prototype.cloneNode = function(deep) {
    var clone = new ElementNode(this.localName);
    clone.className = this.className;
    var attrKeys = Object.keys(this.attributes);
    for (var i = 0; i < attrKeys.length; i++) clone.attributes[attrKeys[i]] = this.attributes[attrKeys[i]];
    if (deep) for (var j = 0; j < this.childNodes.length; j++) clone.appendChild(this.childNodes[j].cloneNode(true));
    return clone;
  };
  ElementNode.prototype.setAttribute = function(name, value) { this.attributes[name] = value; };
  ElementNode.prototype.removeAttribute = function(name) { delete this.attributes[name]; };
  ElementNode.prototype.getAttribute = function(name) { return (name in this.attributes) ? this.attributes[name] : null; };
  ElementNode.prototype.hasAttribute = function(name) { return name in this.attributes; };
  ElementNode.prototype.addEventListener = function(event, handler) {
    if (!this._eventListeners[event]) this._eventListeners[event] = [];
    this._eventListeners[event].push(handler);
  };
  ElementNode.prototype.removeEventListener = function(event, handler) {
    if (!this._eventListeners[event]) return;
    var idx = this._eventListeners[event].indexOf(handler);
    if (idx >= 0) this._eventListeners[event].splice(idx, 1);
  };
  ElementNode.prototype.dispatchEvent = function(ev) {
    ev.target = this; ev.currentTarget = this;
    var handlers = (this._eventListeners[ev.type] || []).slice();
    for (var i = 0; i < handlers.length; i++) handlers[i](ev);
    return true;
  };
  ElementNode.prototype.focus = function() { doc.activeElement = this; };

  Object.defineProperty(ElementNode.prototype, 'innerHTML', {
    get: function() { return this._innerHTMLValue || ''; },
    set: function(val) {
      for (var i = 0; i < this.childNodes.length; i++) this.childNodes[i].parentNode = null;
      this.childNodes = []; updateSiblings(this); this._innerHTMLValue = val;
    }
  });

  function DocumentFragment() {
    this._id = ++nodeIdCounter; this.nodeType = 11; this.nodeName = '#document-fragment';
    this.parentNode = null; this.firstChild = null; this.nextSibling = null; this.childNodes = [];
  }
  DocumentFragment.prototype.appendChild = ElementNode.prototype.appendChild;
  DocumentFragment.prototype.insertBefore = ElementNode.prototype.insertBefore;
  DocumentFragment.prototype.removeChild = ElementNode.prototype.removeChild;
  DocumentFragment.prototype.replaceChild = ElementNode.prototype.replaceChild;

  function TemplateElement() { ElementNode.call(this, 'template'); this.content = new DocumentFragment(); }
  TemplateElement.prototype = Object.create(ElementNode.prototype);
  TemplateElement.prototype.constructor = TemplateElement;

  var docElement = new ElementNode('html');
  var body = new ElementNode('body');
  docElement.appendChild(body);
  var elementsById = {};

  var doc = {
    nodeType: 9,
    activeElement: null,
    _eventListeners: {},
    createElement: function(tag) { if (tag === 'template') return new TemplateElement(); return new ElementNode(tag); },
    createTextNode: function(text) { return new TextNode(String(text)); },
    createDocumentFragment: function() { return new DocumentFragment(); },
    getElementById: function(id) {
      if (elementsById[id]) return elementsById[id];
      var el = new ElementNode('div'); el.setAttribute('id', id); body.appendChild(el); elementsById[id] = el; return el;
    },
    addEventListener: function(event, handler) {
      if (!this._eventListeners[event]) this._eventListeners[event] = [];
      this._eventListeners[event].push(handler);
    },
    dispatchEvent: function(ev) {
      var handlers = (this._eventListeners[ev.type] || []).slice();
      for (var i = 0; i < handlers.length; i++) handlers[i](ev);
      return true;
    },
    body: body,
    documentElement: docElement
  };

  // A synchronous-thenable fetch stub: the whole fetch(...).then(...).then(...)
  // chain resolves in-line, so a click-triggered lazy fetch has its index
  // available by the time the handler returns -- no awaiting in the test.
  var INDEX_JSON = '{"entries":[' +
    '{"routePath":"/guide/alpha","title":"Alpha Guide","section":"guide","summary":"The first nested page about signals.","headings":["Overview"],"aliases":[]},' +
    '{"routePath":"/guide/beta","title":"Beta Guide","section":"guide","summary":"Signals and effects overview.","headings":[],"aliases":[]}' +
    ']}';
  function SyncThenable(v) { this._v = v; }
  SyncThenable.prototype.then = function(cb) {
    var r = cb(this._v);
    if (r && typeof r.then === 'function') return r;
    return new SyncThenable(r);
  };
  SyncThenable.prototype.catch = function() { return this; };
  var fetchStub = function(url) { return new SyncThenable({ text: function(){ return INDEX_JSON; } }); };

  var win = { document: doc, location: { href: '', pathname: '/' }, fetch: fetchStub };

  if (typeof globalThis !== 'undefined') {
    globalThis.document = doc; globalThis.window = win; globalThis.fetch = fetchStub;
  } else if (typeof global !== 'undefined') {
    global.document = doc; global.window = win; global.fetch = fetchStub;
  }
})();
""".}

import std/[unittest, strutils]
import isonim/web/dom_api
import ../../src/components/search_view
import ../../src/main_web

proc tagOf(n: Node): string =
  var t: cstring
  {.emit: [t, " = ", n, ".tagName;"].}
  ($t).toLowerAscii

proc hasAttr(n: Node; name: cstring): bool {.importcpp: "#.hasAttribute(#)".}

proc attrOf(n: Node; name: cstring): string =
  if hasAttr(n, name):
    var v: cstring
    {.emit: [v, " = ", n, ".getAttribute(", name, ");"].}
    $v
  else: ""

proc classOf(n: Node): string = attrOf(n, "class")

proc findAllByClass(root: Node; cls: string): seq[Element] =
  if root.isNodeNil: return
  if root.nodeType == 1 and attrOf(root, "class") == cls:
    result.add Element(root)
  for c in root.childNodes:
    result.add findAllByClass(c, cls)

proc findAllByTag(root: Node; tag: string): seq[Element] =
  if root.isNodeNil: return
  if root.nodeType == 1 and tagOf(root) == tag:
    result.add Element(root)
  for c in root.childNodes:
    result.add findAllByTag(c, tag)

proc childCount(n: Node): int =
  var l: int
  {.emit: [l, " = ", n, ".childNodes.length;"].}
  l

proc liAt(list: Node; idx: int): Node =
  result = list.firstChild
  for i in 0 ..< idx:
    result = result.nextSibling

proc setValue(e: Element; v: cstring) {.importcpp: "#.value = #".}
proc focusEl(e: Element) {.importcpp: "#.focus()".}
proc dispatchInputEvent(e: Element) {.importcpp: "#.dispatchEvent({type: 'input'})".}
proc dispatchKeydown(e: Element; key: cstring) {.importcpp:
  "#.dispatchEvent({type: 'keydown', key: #, metaKey: false, ctrlKey: false, shiftKey: false, preventDefault: function(){}})".}
proc dispatchDocKeydown(key: cstring; meta: bool) {.importcpp:
  "document.dispatchEvent({type: 'keydown', key: #, metaKey: #, ctrlKey: false, shiftKey: false, preventDefault: function(){}})".}
proc locationHref(): cstring {.importcpp: "(window.location.href)".}

suite "docs JS keyboard search overlay (Tier 3, JS-target, M5 deliverable 2)":
  test "Cmd+K and / open the overlay, / is ignored while a text field is focused, Esc/arrows/Enter/marks work":
    let rootEl = document.getElementById("isonim-docs-search-shortcuts-root")
    let mounted = hydrateRouteApp(rootEl, "/")
    discard mounted

    let overlays = findAllByClass(Node(rootEl), searchOverlayClass)
    require overlays.len == 1
    let overlayEl = overlays[0]
    check attrOf(Node(overlayEl), searchOpenAttr) == "false"

    # overlay structure: overlay -> dialog -> [input, resultsWrapper, hint]
    let dialogNode = Node(overlayEl).firstChild
    let inputNode = dialogNode.firstChild
    let resultsNode = inputNode.nextSibling
    let overlayInput = Element(inputNode)

    # --- Cmd+K opens the overlay -------------------------------------
    dispatchDocKeydown("k", true)
    check attrOf(Node(overlayEl), searchOpenAttr) == "true"

    # --- Esc closes it ----------------------------------------------
    dispatchKeydown(overlayInput, "Escape")
    check attrOf(Node(overlayEl), searchOpenAttr) == "false"

    # --- '/' opens it when focus is NOT in a text field --------------
    focusEl(Element(Node(overlayEl))) # a non-text-entry element holds focus
    dispatchDocKeydown("/", false)
    check attrOf(Node(overlayEl), searchOpenAttr) == "true"

    # --- '/' is ignored while a text input is focused ----------------
    dispatchKeydown(overlayInput, "Escape")
    check attrOf(Node(overlayEl), searchOpenAttr) == "false"
    focusEl(overlayInput) # a text <input> now holds focus
    dispatchDocKeydown("/", false)
    check attrOf(Node(overlayEl), searchOpenAttr) == "false" # NOT opened

    # --- reopen, type a query: lazily-fetched index ranks + highlights
    dispatchDocKeydown("k", true)
    check attrOf(Node(overlayEl), searchOpenAttr) == "true"
    setValue(overlayInput, "signals")
    dispatchInputEvent(overlayInput)

    let list = resultsNode.firstChild
    check tagOf(list) == "ul"
    check childCount(list) == 2 # both fetched entries mention "signals"
    check classOf(liAt(list, 0)).contains(searchResultActiveClass) # top result selected
    check attrOf(liAt(list, 0).firstChild, "href") == "/guide/alpha" # tie broken by routePath

    # matched terms wrapped in real <mark> elements
    let marks = findAllByTag(resultsNode, "mark")
    check marks.len >= 1
    check ($Node(marks[0]).textContent).toLowerAscii == "signals"

    # --- ArrowDown/ArrowUp move the keyboard cursor ------------------
    dispatchKeydown(overlayInput, "ArrowDown")
    var l2 = resultsNode.firstChild
    check not classOf(liAt(l2, 0)).contains(searchResultActiveClass)
    check classOf(liAt(l2, 1)).contains(searchResultActiveClass)
    dispatchKeydown(overlayInput, "ArrowUp")
    var l3 = resultsNode.firstChild
    check classOf(liAt(l3, 0)).contains(searchResultActiveClass)

    # --- Enter navigates to the highlighted result -------------------
    dispatchKeydown(overlayInput, "Enter")
    check $locationHref() == "/guide/alpha"
