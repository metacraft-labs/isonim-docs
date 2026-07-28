## Tier 3 (JS route-mount parity) M1 routing suite -- JS-target only.
##
## Proves `src/main_web.nim`'s `createRouteApp` mounts the exact same
## `docsRouteManifest()` / `buildShellViewModel` / `renderSiteFrame` shell
## structure the SSR entry's `renderRoute` (`test_routes_renderroute.nim`)
## and the MockRenderer tier (`test_routes_mock.nim`) already prove -- for
## the index route, a nested route bound to its own content file,
## trailing-slash normalization, and the typed not-found route -- so JS
## mount and SSR agree on the same route manifest and page ViewModels
## with no route-specific forks.
##
## `nim js -r` runs under Node.js, which has no DOM. Mirrors
## ../isonim/tests/test_web.nim's approach (also used by
## `test_bootstrap_browser_mount.nim`): inject a minimal DOM shim via
## `{.emit.}` before any import that touches `document`.

when not defined(js):
  {.error: "test_routes_browser_mount must be compiled with the JS backend: nim js -r tests/docs/test_routes_browser_mount.nim".}

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

suite "docs JS route-mount parity (Tier 3, JS-target)":
  test "createRouteApp('/') mounts the index route through the real rendering shell":
    let expected = mountedRoutePage("index.md")
    let rootEl = document.getElementById("isonim-docs-route-root-index")
    discard render(proc(): Node = createRouteApp("/", docsRouteManifest()), rootEl)

    let frameNode = rootEl.firstChild
    check not frameNode.isNodeNil
    check tagOf(frameNode) == "div"
    check attrOf(frameNode, "class") == "docs-frame"

    let skipLinkNode = frameNode.firstChild
    check tagOf(skipLinkNode) == "a"
    check attrOf(skipLinkNode, "class") == "docs-skip-link"
    check attrOf(skipLinkNode, "href") == "#docs-region-main"

    let headerNode = skipLinkNode.nextSibling
    check tagOf(headerNode) == "header"
    check attrOf(headerNode, "id") == "docs-region-header"
    check attrOf(headerNode, "class") == "docs-header"

    let h1Node = headerNode.firstChild
    check tagOf(h1Node) == "h1"
    check $h1Node.textContent == expected.title

    let navNode = headerNode.nextSibling
    check tagOf(navNode) == "nav"
    check attrOf(navNode, "id") == "docs-region-nav"

    let mainNode = navNode.nextSibling
    check tagOf(mainNode) == "main"
    check attrOf(mainNode, "id") == "docs-region-main"

    let bodyNode = mainNode.firstChild
    check tagOf(bodyNode) == "div"
    check attrOf(bodyNode, "class") == "docs-body"
    check $bodyNode.textContent == expected.body

    let footerNode = mainNode.nextSibling
    check tagOf(footerNode) == "footer"
    check attrOf(footerNode, "id") == "docs-region-footer"

  test "createRouteApp('/guide/getting-started') mounts the nested route from its own bound content file":
    let expected = mountedRoutePage("getting-started.md")
    check expected.title == "Getting Started"
    let rootEl = document.getElementById("isonim-docs-route-root-nested")
    discard render(proc(): Node = createRouteApp("/guide/getting-started", docsRouteManifest()), rootEl)

    let headerNode = rootEl.firstChild.firstChild.nextSibling
    let h1Node = headerNode.firstChild
    check $h1Node.textContent == expected.title

    let mainNode = headerNode.nextSibling.nextSibling
    let bodyNode = mainNode.firstChild
    check $bodyNode.textContent == expected.body
    # Proves the nested route loaded its own bound file, not the index's.
    check not ($bodyNode.textContent).contains("documentation-site framework")

  test "createRouteApp normalizes a trailing slash to the same nested-route match":
    let rootWithSlash = document.getElementById("isonim-docs-route-root-trailing-slash")
    discard render(proc(): Node = createRouteApp("/guide/getting-started/", docsRouteManifest()), rootWithSlash)
    let rootWithoutSlash = document.getElementById("isonim-docs-route-root-trailing-slash-2")
    discard render(proc(): Node = createRouteApp("/guide/getting-started", docsRouteManifest()), rootWithoutSlash)

    let h1WithSlash = rootWithSlash.firstChild.firstChild.nextSibling.firstChild
    let h1WithoutSlash = rootWithoutSlash.firstChild.firstChild.nextSibling.firstChild
    check $h1WithSlash.textContent == $h1WithoutSlash.textContent

    let bodyWithSlash = rootWithSlash.firstChild.firstChild.nextSibling.nextSibling.nextSibling.firstChild
    let bodyWithoutSlash = rootWithoutSlash.firstChild.firstChild.nextSibling.nextSibling.nextSibling.firstChild
    check $bodyWithSlash.textContent == $bodyWithoutSlash.textContent

  test "createRouteApp('/missing') mounts the typed not-found page with a structurally distinct shape":
    let rootEl = document.getElementById("isonim-docs-route-root-notfound")
    discard render(proc(): Node = createRouteApp("/missing", docsRouteManifest()), rootEl)

    let headerNode = rootEl.firstChild.firstChild.nextSibling
    let h1Node = headerNode.firstChild
    check $h1Node.textContent == "Not Found"

    let mainNode = headerNode.nextSibling.nextSibling
    check attrOf(mainNode, "id") == "docs-region-main"

    let notFoundNode = mainNode.firstChild
    check tagOf(notFoundNode) == "div"
    check attrOf(notFoundNode, "class") == "docs-not-found"
    check $notFoundNode.textContent == "Page not found"
