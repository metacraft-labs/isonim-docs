## Tier 3 (JS browser mount) M4 corrective deliverable 1 suite -- JS-target only.
##
## Proves `src/main_web.nim`'s `hydrateRouteApp`/`hydrateApp` are REAL
## hydration, not a re-skinned fresh render: mounting over an
## already-present (SSR-shaped) DOM tree reuses the exact same node
## objects at every structural position that lines up -- asserted via
## real JS reference equality (`===`), not just "looks the same" --
## and the interactivity wired onto those reused nodes (the theme
## toggle button) actually works afterward.
##
## The "already-present" tree is built the same way a real browser
## would have produced it from SSR HTML: by running the exact same
## `renderSiteFrame`/`renderMarkdownPage` component code the SSR path
## (`src/ssr.nim`) runs, just via `createRouteApp`'s plain `WebRenderer`
## instead of the SSR string backend -- `isonim-docs`' whole generic-
## renderer contract (proved elsewhere by the MockRenderer/renderRoute/
## browser-mount three-tier suites) guarantees both backends build the
## identical tag/text tree from the identical ViewModel data, so this
## is a faithful stand-in for "the browser already parsed SSR HTML"
## without needing an HTML parser in this shimmed `nim js -r` harness
## (see the DOM shim below -- same idiom as
## `test_code_copy_browser_mount.nim`, which needs `dispatchEvent` for
## the same reason this suite does: to fire the click that proves
## post-hydration interactivity).
##
## `nim js -r` runs under Node.js, which has no DOM. Mirrors
## `test_code_copy_browser_mount.nim`'s shim (dispatchEvent + settable
## `.value`/`.innerHTML`).

when not defined(js):
  {.error: "test_hydration_browser_mount must be compiled with the JS backend: nim js -r tests/docs/test_hydration_browser_mount.nim".}

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
    this.style = {
      _props: {},
      setProperty: function(k, v) { this._props[k] = v; },
      removeProperty: function(k) { delete this._props[k]; },
      cssText: ''
    };
    this._eventListeners = {};
    this.disabled = false;
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
import ../../src/main_web

proc tagOf(n: Node): string =
  var t: cstring
  {.emit: [t, " = ", n, ".tagName;"].}
  ($t).toLowerAscii

proc attrOf(n: Node; name: cstring): string =
  var v: cstring
  {.emit: [v, " = ", n, ".getAttribute(", name, ");"].}
  $v

proc sameNode(a, b: Node): bool {.importcpp: "(# === #)".}
  ## Real JS reference equality -- the actual claim "node identity is
  ## preserved" is making, not just "structurally looks the same".

proc dispatchClickEvent(e: Element) {.importcpp: "#.dispatchEvent({type: 'click'})".}

proc childCount(n: Node): int =
  for c in n.childNodes: inc result

suite "docs JS hydration (Tier 3, JS-target, M4 corrective deliverable 1)":
  test "hydrateRouteApp reuses the SSR-shaped tree's nodes instead of rebuilding them":
    let rootEl = document.getElementById("isonim-docs-hydration-root")

    # Simulate "the browser already parsed SSR HTML into rootEl" by
    # mounting the exact same route through the exact same component
    # code a real SSR response would have gone through (just via
    # `WebRenderer` instead of the SSR string backend -- see this
    # suite's docstring for why that's a faithful stand-in here).
    let preRendered = createRouteApp("/")
    discard appendChild(Node(rootEl), preRendered)
    check childCount(Node(rootEl)) == 1

    # Capture references into the pre-hydration tree at several depths
    # before hydration touches anything.
    let originalFrame = preRendered
    let originalSkipLink = originalFrame.firstChild
    let originalHeader = originalSkipLink.nextSibling
    let originalTitle = originalHeader.firstChild
    let originalSearchBox = originalTitle.nextSibling
    let originalToggle = originalSearchBox.nextSibling
    let originalNav = originalHeader.nextSibling
    let originalMain = originalNav.nextSibling

    check tagOf(originalFrame) == "div"
    check attrOf(originalFrame, "class") == "docs-frame"
    check tagOf(originalToggle) == "button"
    check attrOf(originalToggle, "class") == "docs-theme-toggle"
    let themeBefore = attrOf(originalToggle, "data-theme")

    # Hydrate over the same root -- this must NOT throw the existing
    # tree away and build a fresh one.
    let mounted = hydrateRouteApp(rootEl, "/")

    # No full re-render: still exactly one child under root (the
    # reused frame, not a second fresh tree appended alongside it).
    check childCount(Node(rootEl)) == 1
    check sameNode(Node(rootEl).firstChild, mounted)

    # Real DOM node identity preserved at every structural depth that
    # lines up between the "SSR" tree and the hydrated mount.
    check sameNode(mounted, originalFrame)
    check sameNode(mounted.firstChild, originalSkipLink)
    let header = mounted.firstChild.nextSibling
    check sameNode(header, originalHeader)
    check sameNode(header.firstChild, originalTitle)
    let searchBox = header.firstChild.nextSibling
    check sameNode(searchBox, originalSearchBox)
    let toggle = searchBox.nextSibling
    check sameNode(toggle, originalToggle)
    let navEl = header.nextSibling
    check sameNode(navEl, originalNav)
    let mainEl = navEl.nextSibling
    check sameNode(mainEl, originalMain)

    # Interactive state works: the theme toggle wired during hydration
    # is wired onto the REUSED button (proven above), and a click on
    # it flips the theme -- the same live behaviour `test_theme_mock.nim`
    # style suites prove for a fresh (non-hydrated) mount.
    dispatchClickEvent(Element(toggle))
    let themeAfter = attrOf(toggle, "data-theme")
    check themeAfter != themeBefore
    check attrOf(toggle, "aria-pressed") == (if themeAfter == "dark": "true" else: "false")

  test "hydrateApp reuses the pre-existing shell tree the same way createApp would build fresh":
    let rootEl = document.getElementById("isonim-docs-hydration-app-root")
    let preRendered = createApp()
    discard appendChild(Node(rootEl), preRendered)

    let originalShell = preRendered
    let originalLink = originalShell.firstChild
    let originalTitle = originalLink.nextSibling
    let originalBody = originalTitle.nextSibling

    let mounted = hydrateApp(rootEl)

    check childCount(Node(rootEl)) == 1
    check sameNode(mounted, originalShell)
    check sameNode(mounted.firstChild, originalLink)
    check sameNode(mounted.firstChild.nextSibling, originalTitle)
    check sameNode(mounted.firstChild.nextSibling.nextSibling, originalBody)
