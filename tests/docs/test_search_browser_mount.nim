## Tier 3 (JS browser mount) M4 search suite -- JS-target only.
##
## Proves `src/main_web.nim`'s `createRouteApp` mounts a real, live
## search box wired against the real, compile-time-embedded search
## index (`wireSearchInteractivity`): typing into the search `<input>`
## re-ranks and re-renders the result list in place, `ArrowDown`/
## `ArrowUp` move the keyboard cursor, and the same result-selection
## markup `test_search_mock.nim` already proves structurally
## (`docs-search-result-active`/`aria-selected`) shows up for real
## here, driven by simulated DOM events rather than direct ViewModel
## construction.
##
## `nim js -r` runs under Node.js, which has no DOM. Mirrors
## ../isonim/tests/test_web.nim's approach (also used by
## `test_routes_browser_mount.nim`): inject a minimal DOM shim via
## `{.emit.}` before any import that touches `document`. This shim
## additionally gives `ElementNode` a real (settable) `.value` field
## and a `dispatchEvent` method that invokes whatever handlers
## `addEventListener` recorded -- neither exists in the routes/markdown/
## bootstrap browser-mount suites' own copy of this shim, since they
## never need to simulate a live keystroke or keypress.

when not defined(js):
  {.error: "test_search_browser_mount must be compiled with the JS backend: nim js -r tests/docs/test_search_browser_mount.nim".}

{.emit: """
// ---- Minimal DOM shim for Node.js (same idiom as isonim/tests/test_web.nim) ----
(function() {
  if (typeof document !== 'undefined') return;

  var nodeIdCounter = 0;

  function TextNode(text) {
    this._id = ++nodeIdCounter;
    this.nodeType = 3;
    this.nodeName = '#text';
    this.data = text;
    this.textContent = text;
    this.parentNode = null;
    this.firstChild = null;
    this.nextSibling = null;
    this.childNodes = [];
  }
  TextNode.prototype.remove = function() {
    if (this.parentNode) this.parentNode.removeChild(this);
  };
  TextNode.prototype.cloneNode = function(deep) {
    return new TextNode(this.data);
  };

  function ElementNode(tag) {
    this._id = ++nodeIdCounter;
    this.nodeType = 1;
    this.nodeName = tag.toUpperCase();
    this.tagName = tag.toUpperCase();
    this.localName = tag.toLowerCase();
    this.data = null;
    this.parentNode = null;
    this.firstChild = null;
    this.nextSibling = null;
    this.childNodes = [];
    this.attributes = {};
    this.className = '';
    this.innerHTML = '';
    this.style = {
      _props: {},
      setProperty: function(k, v) { this._props[k] = v; },
      removeProperty: function(k) { delete this._props[k]; },
      cssText: ''
    };
    this._eventListeners = {};
    this.disabled = false;
    this.value = '';
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
    for (var i = 0; i < node.childNodes.length; i++) {
      node.childNodes[i].parentNode = null;
    }
    node.childNodes = [];
    if (val !== '' && val != null) {
      var t = new TextNode(String(val));
      t.parentNode = node;
      node.childNodes.push(t);
    }
    updateSiblings(node);
  }

  Object.defineProperty(ElementNode.prototype, 'textContent', {
    get: function() {
      var result = '';
      for (var i = 0; i < this.childNodes.length; i++) {
        var c = this.childNodes[i];
        if (c.nodeType === 3) result += c.data;
        else result += c.textContent;
      }
      return result;
    },
    set: function(val) {
      setTextContent(this, val);
    }
  });

  Object.defineProperty(TextNode.prototype, 'textContent', {
    get: function() { return this.data; },
    set: function(val) { this.data = String(val); }
  });

  ElementNode.prototype.appendChild = function(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    if (child.nodeType === 11) {
      var kids = child.childNodes.slice();
      for (var i = 0; i < kids.length; i++) {
        this.appendChild(kids[i]);
      }
      child.childNodes = [];
      updateSiblings(child);
      return child;
    }
    child.parentNode = this;
    this.childNodes.push(child);
    updateSiblings(this);
    return child;
  };

  ElementNode.prototype.insertBefore = function(newNode, refNode) {
    if (newNode.parentNode) newNode.parentNode.removeChild(newNode);
    if (refNode == null) {
      return this.appendChild(newNode);
    }
    if (newNode.nodeType === 11) {
      var kids = newNode.childNodes.slice();
      for (var i = 0; i < kids.length; i++) {
        this.insertBefore(kids[i], refNode);
      }
      newNode.childNodes = [];
      updateSiblings(newNode);
      return newNode;
    }
    var idx = this.childNodes.indexOf(refNode);
    if (idx >= 0) {
      newNode.parentNode = this;
      this.childNodes.splice(idx, 0, newNode);
    } else {
      return this.appendChild(newNode);
    }
    updateSiblings(this);
    return newNode;
  };

  ElementNode.prototype.removeChild = function(child) {
    var idx = this.childNodes.indexOf(child);
    if (idx >= 0) {
      this.childNodes.splice(idx, 1);
      child.parentNode = null;
      child.nextSibling = null;
    }
    updateSiblings(this);
    return child;
  };

  ElementNode.prototype.replaceChild = function(newChild, oldChild) {
    var idx = this.childNodes.indexOf(oldChild);
    if (idx >= 0) {
      if (newChild.parentNode) newChild.parentNode.removeChild(newChild);
      oldChild.parentNode = null;
      oldChild.nextSibling = null;
      newChild.parentNode = this;
      this.childNodes[idx] = newChild;
    }
    updateSiblings(this);
    return oldChild;
  };

  ElementNode.prototype.remove = function() {
    if (this.parentNode) this.parentNode.removeChild(this);
  };

  ElementNode.prototype.cloneNode = function(deep) {
    var clone = new ElementNode(this.localName);
    clone.className = this.className;
    var attrKeys = Object.keys(this.attributes);
    for (var i = 0; i < attrKeys.length; i++) {
      clone.attributes[attrKeys[i]] = this.attributes[attrKeys[i]];
    }
    if (deep) {
      for (var j = 0; j < this.childNodes.length; j++) {
        clone.appendChild(this.childNodes[j].cloneNode(true));
      }
    }
    return clone;
  };

  ElementNode.prototype.setAttribute = function(name, value) {
    this.attributes[name] = value;
  };

  ElementNode.prototype.removeAttribute = function(name) {
    delete this.attributes[name];
  };

  ElementNode.prototype.getAttribute = function(name) {
    return (name in this.attributes) ? this.attributes[name] : null;
  };

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
    ev.target = this;
    ev.currentTarget = this;
    var handlers = (this._eventListeners[ev.type] || []).slice();
    for (var i = 0; i < handlers.length; i++) { handlers[i](ev); }
    return true;
  };

  // WebRenderer.clearChildren(node) sets `node.innerHTML = ""` -- give
  // ElementNode a real accessor for it (the plain-field default this
  // shim otherwise uses is inert on assignment) so a live re-render
  // actually detaches the old children instead of silently leaving them
  // in place underneath the freshly-appended new ones. Only the "assign
  // empty string to clear" half of real innerHTML semantics is
  // implemented -- the only way isonim's own renderers ever use it.
  Object.defineProperty(ElementNode.prototype, 'innerHTML', {
    get: function() { return this._innerHTMLValue || ''; },
    set: function(val) {
      for (var i = 0; i < this.childNodes.length; i++) {
        this.childNodes[i].parentNode = null;
      }
      this.childNodes = [];
      updateSiblings(this);
      this._innerHTMLValue = val;
    }
  });

  function DocumentFragment() {
    this._id = ++nodeIdCounter;
    this.nodeType = 11;
    this.nodeName = '#document-fragment';
    this.parentNode = null;
    this.firstChild = null;
    this.nextSibling = null;
    this.childNodes = [];
  }
  DocumentFragment.prototype.appendChild = ElementNode.prototype.appendChild;
  DocumentFragment.prototype.insertBefore = ElementNode.prototype.insertBefore;
  DocumentFragment.prototype.removeChild = ElementNode.prototype.removeChild;
  DocumentFragment.prototype.replaceChild = ElementNode.prototype.replaceChild;
  Object.defineProperty(DocumentFragment.prototype, 'textContent', {
    get: function() {
      var result = '';
      for (var i = 0; i < this.childNodes.length; i++) {
        var c = this.childNodes[i];
        if (c.nodeType === 3) result += c.data;
        else result += c.textContent;
      }
      return result;
    },
    set: function(val) { setTextContent(this, val); }
  });
  DocumentFragment.prototype.cloneNode = function(deep) {
    var clone = new DocumentFragment();
    if (deep) {
      for (var i = 0; i < this.childNodes.length; i++) {
        clone.appendChild(this.childNodes[i].cloneNode(true));
      }
    }
    return clone;
  };

  function TemplateElement() {
    ElementNode.call(this, 'template');
    this.content = new DocumentFragment();
  }
  TemplateElement.prototype = Object.create(ElementNode.prototype);
  TemplateElement.prototype.constructor = TemplateElement;

  var docElement = new ElementNode('html');
  var body = new ElementNode('body');
  docElement.appendChild(body);

  var elementsById = {};

  var doc = {
    nodeType: 9,
    createElement: function(tag) {
      if (tag === 'template') return new TemplateElement();
      return new ElementNode(tag);
    },
    createTextNode: function(text) {
      return new TextNode(String(text));
    },
    createDocumentFragment: function() {
      return new DocumentFragment();
    },
    getElementById: function(id) {
      if (elementsById[id]) return elementsById[id];
      var el = new ElementNode('div');
      el.setAttribute('id', id);
      body.appendChild(el);
      elementsById[id] = el;
      return el;
    },
    body: body,
    documentElement: docElement
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.document = doc;
    globalThis.window = { document: doc };
  } else if (typeof global !== 'undefined') {
    global.document = doc;
    global.window = { document: doc };
  }
})();
""".}

import std/[unittest, strutils]
import isonim/web/dom_api
import isonim/web/client
import ../../src/components/search_view
import ../../src/core/routes
import ../../src/main_web

proc tagOf(n: Node): string =
  var t: cstring
  {.emit: [t, " = ", n, ".tagName;"].}
  ($t).toLowerAscii

proc attrOf(n: Node; name: cstring): string =
  var v: cstring
  {.emit: [v, " = ", n, ".getAttribute(", name, ");"].}
  $v

proc setValue(e: Element; v: cstring) {.importcpp: "#.value = #".}
proc valueOf(e: Element): cstring {.importcpp: "#.value".}
proc dispatchInputEvent(e: Element) {.importcpp: "#.dispatchEvent({type: 'input'})".}
proc dispatchKeydownEvent(e: Element; key: cstring) {.importcpp: "#.dispatchEvent({type: 'keydown', key: #})".}

proc searchInputOf(rootEl: Element): Element =
  ## The exact structural path `wireSearchInteractivity` itself wires
  ## against: frame -> [skip link, header] -> header -> [title, search
  ## box] -> [input, ...].
  let frameNode = rootEl.firstChild
  let headerNode = frameNode.firstChild.nextSibling
  Element(headerNode.firstChild.nextSibling.firstChild)

proc searchResultsWrapperOf(rootEl: Element): Node =
  let frameNode = rootEl.firstChild
  let headerNode = frameNode.firstChild.nextSibling
  headerNode.firstChild.nextSibling.firstChild.nextSibling

proc childCount(n: Node): int =
  var l: int
  {.emit: [l, " = ", n, ".childNodes.length;"].}
  l

proc liAt(list: Node; idx: int): Node =
  result = list.firstChild
  for i in 0 ..< idx:
    result = result.nextSibling

proc classOf(n: Node): string =
  attrOf(n, "class")

suite "docs JS live search (Tier 3, JS-target)":
  test "an untouched mount renders an empty search box with an empty result list":
    let rootEl = document.getElementById("isonim-docs-search-root-initial")
    discard render(proc(): Node = createRouteApp("/"), rootEl)

    let inputEl = searchInputOf(rootEl)
    check attrOf(inputEl, "id") == searchInputId
    check ($valueOf(inputEl)) == ""

    let wrapper = searchResultsWrapperOf(rootEl)
    let content = wrapper.firstChild
    check tagOf(content) == "ul"
    check childCount(content) == 0

  test "typing a query re-renders the result list, ranked with the top result selected":
    let rootEl = document.getElementById("isonim-docs-search-root-query")
    discard render(proc(): Node = createRouteApp("/"), rootEl)
    let inputEl = searchInputOf(rootEl)
    let wrapper = searchResultsWrapperOf(rootEl)

    setValue(inputEl, "fixture")
    dispatchInputEvent(inputEl)

    let list = wrapper.firstChild
    check tagOf(list) == "ul"
    check childCount(list) == 3 # "/", "/guide/alpha", "/guide/beta" each mention "fixture"; getting-started.md does not

    let first = liAt(list, 0)
    check classOf(first).contains(searchResultActiveClass)
    check attrOf(first.firstChild, "href") == "/"

  test "ArrowDown/ArrowUp move the keyboard cursor across the live-rendered result list":
    let rootEl = document.getElementById("isonim-docs-search-root-keyboard")
    discard render(proc(): Node = createRouteApp("/"), rootEl)
    let inputEl = searchInputOf(rootEl)
    let wrapper = searchResultsWrapperOf(rootEl)

    setValue(inputEl, "fixture")
    dispatchInputEvent(inputEl)

    dispatchKeydownEvent(inputEl, "ArrowDown")
    var list = wrapper.firstChild
    check not classOf(liAt(list, 0)).contains(searchResultActiveClass)
    check classOf(liAt(list, 1)).contains(searchResultActiveClass)
    # All three pages tie on a single summary-only "fixture" match; the tie
    # breaks alphabetically by routePath, so index 1 is "/guide/alpha".
    check attrOf(liAt(list, 1).firstChild, "href") == "/guide/alpha"

    dispatchKeydownEvent(inputEl, "ArrowUp")
    list = wrapper.firstChild
    check classOf(liAt(list, 0)).contains(searchResultActiveClass)
    check not classOf(liAt(list, 1)).contains(searchResultActiveClass)

  test "a query matching nothing re-renders the no-results message INSIDE the results container":
    let rootEl = document.getElementById("isonim-docs-search-root-empty")
    discard render(proc(): Node = createRouteApp("/"), rootEl)
    let inputEl = searchInputOf(rootEl)
    let wrapper = searchResultsWrapperOf(rootEl)

    setValue(inputEl, "xyznonexistentterm")
    dispatchInputEvent(inputEl)

    # WebFlow parity: the no-results message is an <li class="docs-search-empty">
    # nested INSIDE the `.docs-search-results` <ul> dropdown card, not a bare
    # floating <div> sibling.
    let content = wrapper.firstChild
    check tagOf(content) == "ul"
    check classOf(content) == searchResultsClass
    let empty = content.firstChild
    check tagOf(empty) == "li"
    check classOf(empty) == searchEmptyClass
    check ($empty.textContent).contains("xyznonexistentterm")

  test "clearing the query back to empty re-renders an empty result list, not the empty-state shape":
    let rootEl = document.getElementById("isonim-docs-search-root-clear")
    discard render(proc(): Node = createRouteApp("/"), rootEl)
    let inputEl = searchInputOf(rootEl)
    let wrapper = searchResultsWrapperOf(rootEl)

    setValue(inputEl, "fixture")
    dispatchInputEvent(inputEl)
    setValue(inputEl, "")
    dispatchInputEvent(inputEl)

    let content = wrapper.firstChild
    check tagOf(content) == "ul"
    check childCount(content) == 0
