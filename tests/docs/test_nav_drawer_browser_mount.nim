## Tier 3 (JS browser mount) M5 corrective deliverable 1 suite -- JS-target only.
##
## Proves `src/main_web.nim`'s <768px hamburger drawer (wired inside
## `hydrateRouteApp` via `wireNavDrawer`): the hamburger `<button>`
## (`navigation_view.navDrawerToggleClass`, hidden above the breakpoint
## by CSS -- see `assets/style.css` -- but always present in the markup,
## which is the one thing this DOM-only harness can actually assert)
## toggles the drawer body's `[data-open]`/`aria-expanded` open and
## closed, moves focus into the drawer's first focusable element on
## open, traps Tab/Shift+Tab between the drawer's first and last
## focusable elements while open (WAI-ARIA APG dialog focus-trap
## pattern), and Escape closes the drawer and returns focus to the
## toggle button.
##
## `nim js -r` runs under Node.js, which has no DOM, no `window`. This
## shim is the `document`-only subset of `test_soft_nav_browser_mount.
## nim`'s own DOM shim (`ElementNode`/`TextNode`/`DocumentFragment`/
## `doc`) -- no `window`/`history`/`location` needed here, since none of
## `wireNavDrawer`'s own DOM touches go through `window` at all, and
## every OTHER piece of chrome `hydrateRouteApp` wires unconditionally
## (soft-nav, theme toggle, prefetch) already guards its own `window`/
## `localStorage`/`matchMedia`/`IntersectionObserver` access with
## `typeof X !== 'undefined'` checks, so it silently no-ops without one
## -- see `isonim-docs-nim-js-gotchas` project memory. Extended with a
## real `ElementNode.prototype.focus`/`document.activeElement` pair
## (absent from the base shim -- nothing before this needed live focus
## tracking), the one thing the focus-trap assertions below need that
## the base shim doesn't already provide.

when not defined(js):
  {.error: "test_nav_drawer_browser_mount must be compiled with the JS backend: nim js -r tests/docs/test_nav_drawer_browser_mount.nim".}

{.emit: """
// ---- Minimal document-only DOM shim for Node.js (same idiom as isonim/tests/test_web.nim) ----
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

  ElementNode.prototype.hasAttribute = function(name) {
    return name in this.attributes;
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

  // M5 corrective deliverable 1: a real `.focus()` that updates
  // `document.activeElement`, exactly enough for a focus-trap test --
  // absent from the base shim this is copied from (nothing before this
  // needed live focus tracking).
  ElementNode.prototype.focus = function() {
    doc.activeElement = this;
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
    activeElement: null,
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
  } else if (typeof global !== 'undefined') {
    global.document = doc;
  }
})();
""".}

import std/[unittest, strutils]
import isonim/web/dom_api
import ../../src/main_web
import ../../src/components/navigation_view

proc tagOf(n: Node): string =
  var t: cstring
  {.emit: [t, " = ", n, ".tagName;"].}
  ($t).toLowerAscii

proc hasAttr(n: Node; name: cstring): bool {.importcpp: "#.hasAttribute(#)".}

proc attrOf(n: Node; name: cstring): string =
  ## Guarded the same way `main_web.hasAttribute` is: `getAttribute`
  ## returns JS `null` for a missing attribute, and converting that
  ## straight to a Nim string crashes.
  if hasAttr(n, name):
    var v: cstring
    {.emit: [v, " = ", n, ".getAttribute(", name, ");"].}
    $v
  else: ""

proc findAllByClass(root: Node; cls: string): seq[Element] =
  if root.isNodeNil: return
  if root.nodeType == 1 and attrOf(root, "class") == cls:
    result.add Element(root)
  for c in root.childNodes:
    result.add findAllByClass(c, cls)

proc findFocusable(root: Node): seq[Element] =
  ## Mirrors `main_web.findFocusableElements`'s own a/button DOM-order
  ## walk, kept independent here so the test doesn't just assert against
  ## itself.
  if root.isNodeNil: return
  if root.nodeType == 1 and (tagOf(root) == "a" or tagOf(root) == "button"):
    result.add Element(root)
  for c in root.childNodes:
    result.add findFocusable(c)

proc dispatchClickEvent(e: Element) {.importcpp:
  "#.dispatchEvent({type: 'click', button: 0, preventDefault: function(){}})".}

proc dispatchKeydownEvent(e: Element; key: cstring; shiftKey: bool) {.importcpp:
  "#.dispatchEvent({type: 'keydown', key: #, shiftKey: #, preventDefault: function(){}})".}

proc focusEl(e: Element) {.importcpp: "#.focus()".}

proc activeElementIs(e: Element): bool {.importcpp: "(document.activeElement === #)".}

suite "docs JS <768px hamburger drawer (Tier 3, JS-target, M5 corrective deliverable 1)":
  test "hamburger toggle opens/closes the drawer body and traps focus while open":
    let rootEl = document.getElementById("isonim-docs-nav-drawer-root")
    let mounted = hydrateRouteApp(rootEl, "/")
    discard mounted

    let toggles = findAllByClass(Node(rootEl), navDrawerToggleClass)
    require toggles.len == 1
    let toggleEl = toggles[0]

    let bodies = findAllByClass(Node(rootEl), navDrawerBodyClass)
    require bodies.len == 1
    let bodyEl = bodies[0]

    # --- narrow-viewport hamburger markup is present -----------------
    # (CSS gates its visibility below 768px; this harness has no layout
    # engine, so the one thing provable here is that the toggle exists,
    # carries the CSS hook, and starts closed.)
    check attrOf(Node(toggleEl), "aria-expanded") == "false"
    check attrOf(Node(bodyEl), "data-open") == "false"

    let focusables = findFocusable(Node(bodyEl))
    check focusables.len >= 2 # the mini-site fixture's real sidebar/adjacent links
    let first = focusables[0]
    let last = focusables[^1]

    # --- opening moves focus into the drawer, to its first focusable --
    dispatchClickEvent(toggleEl)
    check attrOf(Node(bodyEl), "data-open") == "true"
    check attrOf(Node(toggleEl), "aria-expanded") == "true"
    check activeElementIs(first)

    # --- Tab on the last focusable wraps to the first (forward trap) --
    focusEl(last)
    check activeElementIs(last)
    dispatchKeydownEvent(bodyEl, "Tab", false)
    check activeElementIs(first)

    # --- Shift+Tab on the first focusable wraps to the last -----------
    dispatchKeydownEvent(bodyEl, "Tab", true)
    check activeElementIs(last)

    # --- Escape closes the drawer and returns focus to the toggle -----
    dispatchKeydownEvent(bodyEl, "Escape", false)
    check attrOf(Node(bodyEl), "data-open") == "false"
    check attrOf(Node(toggleEl), "aria-expanded") == "false"
    check activeElementIs(toggleEl)

    # --- clicking the toggle again re-opens it -------------------------
    dispatchClickEvent(toggleEl)
    check attrOf(Node(bodyEl), "data-open") == "true"
    check activeElementIs(first)
