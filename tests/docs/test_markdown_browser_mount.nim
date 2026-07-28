## Tier 3 (JS route-mount parity) M2 markdown suite -- JS-target only.
##
## Proves M2 deliverable 4's JS half: `src/main_web.nim`'s
## `createRouteApp` mounts a real, representative markdown page (from the
## framework's own checked-in `tests/fixtures/mini-site/`, M1 corrective
## deliverable 5) through `renderMarkdownPage`, with the same heading IDs
## and block structure `test_markdown_renderroute.nim` already proves for
## the SSR path -- the same `matchRoute` M0/M1's JS route-mount parity
## suite (`test_routes_browser_mount.nim`) uses, no markdown-specific
## routing fork.
##
## `nim js -r` runs under Node.js, which has no DOM. Mirrors
## ../isonim/tests/test_web.nim's approach (also used by
## `test_routes_browser_mount.nim`): inject a minimal DOM shim via
## `{.emit.}` before any import that touches `document`.

when not defined(js):
  {.error: "test_markdown_browser_mount must be compiled with the JS backend: nim js -r tests/docs/test_markdown_browser_mount.nim".}

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
import ../../src/core/markdown_vm
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

let fixtureManifest = newRouteManifest(@[
  newRouteEntry("/guide/alpha", pkMarkdown, meta = RouteMeta(title: "Alpha Guide", contentPath: "guide/alpha.md")),
  newRouteEntry("/guide/beta", pkMarkdown, meta = RouteMeta(title: "Beta Guide", contentPath: "guide/beta.md")),
])

suite "docs JS route-mount parity -- markdown pages (Tier 3, JS-target)":
  test "createRouteApp('/guide/alpha') mounts a real markdown page through renderMarkdownPage":
    let (expectedTitle, expectedBlocks) = mountedMarkdownPage("guide/alpha.md")
    check expectedTitle == "Alpha Guide"

    let rootEl = document.getElementById("isonim-docs-md-route-root-signals-effects")
    discard render(proc(): Node = createRouteApp("/guide/alpha", fixtureManifest), rootEl)

    let frameNode = rootEl.firstChild
    check tagOf(frameNode) == "div"
    check attrOf(frameNode, "class") == "docs-frame"

    let skipLinkNode = frameNode.firstChild
    check tagOf(skipLinkNode) == "a"
    check attrOf(skipLinkNode, "class") == "docs-skip-link"
    check attrOf(skipLinkNode, "href") == "#docs-region-main"

    let headerNode = skipLinkNode.nextSibling
    check tagOf(headerNode) == "header"
    check attrOf(headerNode, "id") == "docs-region-header"
    let h1Node = headerNode.firstChild
    check tagOf(h1Node) == "h1"
    check $h1Node.textContent == expectedTitle

    let navNode = headerNode.nextSibling
    check tagOf(navNode) == "nav"
    check attrOf(navNode, "id") == "docs-region-nav"

    let mainNode = navNode.nextSibling
    check tagOf(mainNode) == "main"
    check attrOf(mainNode, "id") == "docs-region-main"

    let mdBodyNode = mainNode.firstChild
    check tagOf(mdBodyNode) == "div"
    check attrOf(mdBodyNode, "class") == "docs-md-body"

    let footerNode = mainNode.nextSibling
    check tagOf(footerNode) == "footer"
    check attrOf(footerNode, "id") == "docs-region-footer"

    # Same heading IDs and structure as SSR: walk the mounted tree for the
    # first heading and confirm its id matches the anchor ID the exact
    # same `parseMarkdownBlocks` call (`expectedBlocks`) assigned.
    var firstHeadingId = ""
    for blk in expectedBlocks:
      if blk.kind == bkHeading:
        firstHeadingId = blk.headingId
        break
    check firstHeadingId.len > 0

    var headingNode = mdBodyNode.firstChild
    var foundHeadingId = ""
    while not headingNode.isNodeNil:
      let tag = tagOf(headingNode)
      if tag.len == 2 and tag[0] == 'h' and tag[1] in {'1' .. '6'}:
        foundHeadingId = attrOf(headingNode, "id")
        break
      headingNode = headingNode.nextSibling
    check foundHeadingId == firstHeadingId

  test "createRouteApp('/guide/beta') mounts a second representative markdown page":
    let (expectedTitle, _) = mountedMarkdownPage("guide/beta.md")
    check expectedTitle == "Beta Guide"

    let rootEl = document.getElementById("isonim-docs-md-route-root-editor-overview")
    discard render(proc(): Node = createRouteApp("/guide/beta", fixtureManifest), rootEl)

    let headerNode = rootEl.firstChild.firstChild.nextSibling
    let h1Node = headerNode.firstChild
    check $h1Node.textContent == expectedTitle

    let mainNode = headerNode.nextSibling.nextSibling
    let mdBodyNode = mainNode.firstChild
    check attrOf(mdBodyNode, "class") == "docs-md-body"
