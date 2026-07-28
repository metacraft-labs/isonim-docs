## Tier 3 (JS browser mount) M4 corrective deliverable 2 suite -- JS-target only.
##
## Proves `src/main_web.nim`'s soft SPA navigation (wired inside
## `hydrateRouteApp`): clicking an in-site `<a>` updates the DOM through
## the exact same `buildRouteApp` (hence the same `buildShellViewModel`/
## `buildNavigationViewModel` the SSR entry uses) and calls
## `history.pushState` -- no document reload -- back/forward
## (`popstate`) restores the prior route AND its saved scroll position,
## and a link explicitly marked external (a different-origin href, or an
## explicit `target`) is left completely alone (never intercepted, never
## `preventDefault`ed).
##
## `nim js -r` runs under Node.js, which has no DOM, no `window`. Mirrors
## `test_hydration_browser_mount.nim`'s DOM shim (itself mirroring
## `isonim/tests/test_web.nim`'s), extended with a minimal but real
## `window.location`/`window.history`/`window.scrollTo`/
## `window.addEventListener('popstate', ...)` -- everything
## `src/main_web.nim`'s soft-nav wiring actually touches -- so a real
## `history.pushState`/`.back()`/`.forward()` call chain drives the exact
## same code path a real browser's back/forward buttons would.

when not defined(js):
  {.error: "test_soft_nav_browser_mount must be compiled with the JS backend: nim js -r tests/docs/test_soft_nav_browser_mount.nim".}

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

  // ---- window/location/history shim for soft-nav (M4 corrective deliverable 2) ----
  var windowEventListeners = {};
  var historyStack = ['/'];
  var historyIndex = 0;

  function dispatchPopState() {
    var handlers = (windowEventListeners['popstate'] || []).slice();
    for (var i = 0; i < handlers.length; i++) { handlers[i]({type: 'popstate'}); }
  }

  var win = {
    document: doc,
    location: { pathname: '/' },
    scrollX: 0,
    scrollY: 0,
    scrollTo: function(x, y) { win.scrollX = x; win.scrollY = y; },
    history: {
      pushState: function(state, title, url) {
        historyStack = historyStack.slice(0, historyIndex + 1);
        historyStack.push(url);
        historyIndex = historyStack.length - 1;
        win.location.pathname = url;
      },
      replaceState: function(state, title, url) {
        historyStack[historyIndex] = url;
        win.location.pathname = url;
      },
      back: function() {
        if (historyIndex > 0) {
          historyIndex -= 1;
          win.location.pathname = historyStack[historyIndex];
          dispatchPopState();
        }
      },
      forward: function() {
        if (historyIndex < historyStack.length - 1) {
          historyIndex += 1;
          win.location.pathname = historyStack[historyIndex];
          dispatchPopState();
        }
      }
    },
    addEventListener: function(type, handler) {
      if (!windowEventListeners[type]) windowEventListeners[type] = [];
      windowEventListeners[type].push(handler);
    },
    removeEventListener: function(type, handler) {
      if (!windowEventListeners[type]) return;
      var idx = windowEventListeners[type].indexOf(handler);
      if (idx >= 0) windowEventListeners[type].splice(idx, 1);
    }
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.document = doc;
    globalThis.window = win;
  } else if (typeof global !== 'undefined') {
    global.document = doc;
    global.window = win;
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

proc childCount(n: Node): int =
  for c in n.childNodes: inc result

proc findAllAnchors(root: Node): seq[Element] =
  if root.isNodeNil: return
  if root.nodeType == 1:
    if tagOf(root) == "a": result.add Element(root)
  for c in root.childNodes:
    result.add findAllAnchors(c)

proc findAnchorByHref(root: Node; href: string): Element =
  for a in findAllAnchors(root):
    if attrOf(Node(a), "href") == href:
      return a
  raise newException(ValueError, "no anchor with href " & href & " in mounted tree")

proc dispatchClickEvent(e: Element) {.importcpp:
  "#.dispatchEvent({type: 'click', button: 0, preventDefault: function(){}})".}
  ## A real click `Event` always carries `button`/`preventDefault` --
  ## this shim's synthetic one carries just enough of both for
  ## `main_web.nim`'s soft-nav click handler to read.

proc dispatchMouseEnterEvent(e: Element) {.importcpp:
  "#.dispatchEvent({type: 'mouseenter'})".}
  ## Drives `main_web.nim`'s M4 corrective deliverable 3 hover-prefetch
  ## listener -- wired directly on each anchor (this shim's own
  ## `dispatchEvent` only invokes listeners registered on the exact
  ## element it's called on, no bubbling, matching the file's own
  ## documented reason for wiring listeners per-element rather than via
  ## document-level delegation).

proc windowPathnameNow(): string =
  var p: cstring
  {.emit: [p, " = window.location.pathname;"].}
  $p

proc windowScrollXNow(): int {.importcpp: "(window.scrollX)".}
proc windowScrollYNow(): int {.importcpp: "(window.scrollY)".}
proc setWindowScrollY(y: int) {.importcpp: "window.scrollY = #".}
proc historyBack() {.importcpp: "window.history.back()".}
proc historyForward() {.importcpp: "window.history.forward()".}

suite "docs JS soft SPA navigation (Tier 3, JS-target, M4 corrective deliverable 2)":
  test "in-site click navigates + pushes state without reload; external/target-marked links are never intercepted; back/forward restore route and scroll":
    let rootEl = document.getElementById("isonim-docs-soft-nav-root")
    let mounted = hydrateRouteApp(rootEl, "/")
    check childCount(Node(rootEl)) == 1
    check windowPathnameNow() == "/"

    # --- M4 corrective deliverable 3: loading indicator for slow routes --
    # Not created by the initial hydration mount -- only a real route swap
    # (below) creates it. Exercising `showLoadingIndicator`/
    # `hideLoadingIndicator` directly proves the real DOM toggle
    # `swapRouteContent` wires around every swap, without racing a JS timer
    # (see `main_web.nim`'s own comment on why this repo's fully-synchronous
    # route content makes a timer-based test nondeterministic).
    check Node(loadingIndicatorEl()).isNodeNil
    showLoadingIndicator(rootEl)
    check attrOf(Node(loadingIndicatorEl()), "data-visible") == "true"
    hideLoadingIndicator(rootEl)
    check attrOf(Node(loadingIndicatorEl()), "data-visible") == "false"

    let indexHeader = mounted.firstChild.nextSibling
    check ($indexHeader.firstChild.textContent) == mountedMarkdownPage("index.md").title

    # Simulate the user having scrolled down before navigating away.
    setWindowScrollY(240)

    # --- in-site click: navigates, pushes state, no reload ---------------
    let alphaLink = findAnchorByHref(Node(rootEl), "/guide/alpha")
    dispatchClickEvent(alphaLink)

    check windowPathnameNow() == "/guide/alpha"
    check childCount(Node(rootEl)) == 1
    block:
      let header = Node(rootEl).firstChild.firstChild.nextSibling
      check ($header.firstChild.textContent) == mountedMarkdownPage("guide/alpha.md").title
    # A fresh forward navigation starts scrolled to the top.
    check windowScrollXNow() == 0
    check windowScrollYNow() == 0

    # --- external href: a different-origin link is NEVER intercepted -----
    let betaLink = findAnchorByHref(Node(rootEl), "/guide/beta")
    setAttribute(betaLink, "href", "https://example.com/")
    dispatchClickEvent(betaLink)
    check windowPathnameNow() == "/guide/alpha" # unchanged
    block:
      let header = Node(rootEl).firstChild.firstChild.nextSibling
      check ($header.firstChild.textContent) == mountedMarkdownPage("guide/alpha.md").title

    # --- explicit target: also never intercepted, even with an in-site href ---
    setAttribute(betaLink, "href", "/guide/beta")
    setAttribute(betaLink, "target", "_blank")
    dispatchClickEvent(betaLink)
    check windowPathnameNow() == "/guide/alpha" # still unchanged
    removeAttribute(betaLink, "target")

    # --- back/forward restore both the prior route and its own scroll ----
    setWindowScrollY(150) # scrolled state on "/guide/alpha" just before leaving it
    dispatchClickEvent(betaLink) # now a real in-site click: navigates for real
    check windowPathnameNow() == "/guide/beta"
    block:
      let header = Node(rootEl).firstChild.firstChild.nextSibling
      check ($header.firstChild.textContent) == mountedMarkdownPage("guide/beta.md").title
    check windowScrollYNow() == 0 # fresh forward nav starts at the top again

    setWindowScrollY(77) # scrolled state on "/guide/beta" just before going back

    historyBack()
    check windowPathnameNow() == "/guide/alpha"
    block:
      let header = Node(rootEl).firstChild.firstChild.nextSibling
      check ($header.firstChild.textContent) == mountedMarkdownPage("guide/alpha.md").title
    check windowScrollYNow() == 150 # restored exactly what was saved leaving "/guide/alpha"

    historyForward()
    check windowPathnameNow() == "/guide/beta"
    block:
      let header = Node(rootEl).firstChild.firstChild.nextSibling
      check ($header.firstChild.textContent) == mountedMarkdownPage("guide/beta.md").title
    check windowScrollYNow() == 77 # restored exactly what was saved leaving "/guide/beta"

    # --- M4 corrective deliverable 3: prefetch on hover -------------------
    # "getting-started.md" hasn't been navigated to yet in this test, so
    # its markdown doc isn't cached yet either -- proving a genuine warm,
    # not one that just happened to already be true from an earlier real
    # navigation (as it would be for the alpha/beta pages exercised above).
    check not isMarkdownDocCached("getting-started.md")
    let gettingStartedLink = findAnchorByHref(Node(rootEl), "/getting-started")
    dispatchMouseEnterEvent(gettingStartedLink)
    check isMarkdownDocCached("getting-started.md") # warmed by hover alone, before any click

    # The real click navigation afterwards still renders correctly (the
    # prefetch-warmed cache entry is consumed, not bypassed) and the
    # loading indicator (wired around every swap by `swapRouteContent`)
    # ends up hidden again, not stuck visible.
    dispatchClickEvent(gettingStartedLink)
    check windowPathnameNow() == "/getting-started"
    block:
      let header = Node(rootEl).firstChild.firstChild.nextSibling
      check ($header.firstChild.textContent) == mountedMarkdownPage("getting-started.md").title
    check attrOf(Node(loadingIndicatorEl()), "data-visible") == "false"
