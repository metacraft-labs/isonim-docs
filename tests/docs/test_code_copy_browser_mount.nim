## Tier 3 (JS browser mount) M3 deliverable 3 suite -- JS-target only.
##
## Proves `src/main_web.nim`'s `wireCodeCopyButton`/
## `wireCodeCopyInteractivity` give the SSR/MockRenderer-rendered copy
## button (`components/markdown_view.renderCodeFence`, proved
## structurally by `test_code_copy_mock.nim`) real, live behaviour:
## clicking it copies the code fence's own text (stripped of the
## syntax-highlighting `<span>` wrapper -- `Node.textContent` already
## flattens that) via `navigator.clipboard.writeText`, and toggles the
## button into a "copied" state (`data-copied="true"`, a changed
## `aria-label`, changed visible text).
##
## `nim js -r` runs under Node.js, which has no DOM. Mirrors
## `test_search_browser_mount.nim`'s shim (dispatchEvent + settable
## `.value`), plus a `navigator.clipboard.writeText` stub that records
## the copied text -- neither the routes/markdown/search/bootstrap
## browser-mount suites' own copies of this shim need a clipboard stub.

when not defined(js):
  {.error: "test_code_copy_browser_mount must be compiled with the JS backend: nim js -r tests/docs/test_code_copy_browser_mount.nim".}

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

  // Records the last copied text so the test can assert on it -- a real
  // browser's `navigator.clipboard.writeText` returns a Promise; this
  // stub mirrors that shape (`writeClipboardText`'s `.catch(...)` needs
  // a thenable) without doing any real async work.
  var lastClipboardWrite = '';
  var nav = {
    clipboard: {
      writeText: function(text) {
        lastClipboardWrite = text;
        return { catch: function() {} };
      }
    }
  };

  var globalObj = (typeof globalThis !== 'undefined') ? globalThis :
    ((typeof global !== 'undefined') ? global : null);
  if (globalObj) {
    globalObj.document = doc;
    globalObj.window = { document: doc };
    // Node 21+ ships its own read-only global `navigator` (Web API
    // compatibility) -- a plain `globalObj.navigator = nav` silently
    // no-ops against it, so `wireCodeCopyButton`'s
    // `navigator.clipboard.writeText` call would hit the real
    // (clipboard-less) Node navigator instead of this stub.
    // `defineProperty` overrides it outright.
    Object.defineProperty(globalObj, 'navigator', {value: nav, configurable: true, writable: true});
    globalObj.__docsTestLastClipboardWrite = function() { return lastClipboardWrite; };
  }
})();
""".}

import std/[unittest, strutils]
import isonim/web/dom_api
import isonim/web/client
import isonim/web/web_renderer
import ../../src/core/markdown_vm
import ../../src/components/markdown_view
import ../../src/main_web

proc tagOf(n: Node): string =
  var t: cstring
  {.emit: [t, " = ", n, ".tagName;"].}
  ($t).toLowerAscii

proc attrOf(n: Node; name: cstring): string =
  var v: cstring
  {.emit: [v, " = ", n, ".getAttribute(", name, ");"].}
  $v

proc dispatchClickEvent(e: Element) {.importcpp: "#.dispatchEvent({type: 'click'})".}
proc lastClipboardWriteRaw(): cstring {.importcpp: "globalThis.__docsTestLastClipboardWrite()".}
proc lastClipboardWrite(): string = $lastClipboardWriteRaw()

suite "docs JS live copy-to-clipboard code buttons (Tier 3, JS-target)":
  test "clicking the copy button copies the fence's own text and toggles the copied state":
    let rootEl = document.getElementById("isonim-docs-code-copy-root-basic")
    let blocks = parseMarkdownBlocks("```nim\necho 1\n```")
    discard render(proc(): Node =
      let r = WebRenderer()
      renderMarkdownBody[WebRenderer, Node](r, blocks)
    , rootEl)
    wireCodeCopyInteractivity(WebRenderer(), rootEl)

    let bodyNode = rootEl.firstChild
    check attrOf(bodyNode, "class") == markdownBodyClass
    let wrapperNode = bodyNode.firstChild
    check attrOf(wrapperNode, "class") == codeBlockClass
    let btnNode = wrapperNode.firstChild
    check tagOf(btnNode) == "button"
    check attrOf(btnNode, "aria-label") == codeCopyIdleLabel
    check attrOf(btnNode, "data-copied") == "false"

    dispatchClickEvent(Element(btnNode))

    check lastClipboardWrite() == "echo 1"
    check attrOf(btnNode, "data-copied") == "true"
    check attrOf(btnNode, "aria-label") == codeCopyCopiedLabel
    check ($btnNode.textContent) == codeCopyCopiedLabel

  test "each code block's copy button wires and copies independently":
    let rootEl = document.getElementById("isonim-docs-code-copy-root-multi")
    let blocks = parseMarkdownBlocks("```nim\necho 1\n```\n\n```json\n{}\n```")
    discard render(proc(): Node =
      let r = WebRenderer()
      renderMarkdownBody[WebRenderer, Node](r, blocks)
    , rootEl)
    wireCodeCopyInteractivity(WebRenderer(), rootEl)

    let bodyNode = rootEl.firstChild
    let firstWrapper = bodyNode.firstChild
    let secondWrapper = firstWrapper.nextSibling
    let firstBtn = Element(firstWrapper.firstChild)
    let secondBtn = Element(secondWrapper.firstChild)

    dispatchClickEvent(secondBtn)
    check lastClipboardWrite() == "{}"
    check attrOf(Node(secondBtn), "data-copied") == "true"
    check attrOf(Node(firstBtn), "data-copied") == "false"
