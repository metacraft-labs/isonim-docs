## Tier 3 (JS browser mount) M9 deliverable 2 suite -- JS-target only.
##
## Proves live component embedding hydrates each embed INDEPENDENTLY, with
## STRICTLY ISOLATED reactive state, wrapped in the M6 error boundary:
##  * Two embeds of the same counter component on one page keep independent
##    state -- each embed's render closure allocates its OWN isonim
##    `Signal[int]` (scoped by the embed's unique `instanceId`), so
##    incrementing one leaves the other unchanged (they share no signal).
##  * A deliberately-throwing embed renders the inline error-boundary
##    fallback (`components/error_boundary.renderErrorBoundary`) while a
##    sibling embed on the same page still mounts and still works.
##
## `nim js -r` runs under Node.js, which has no DOM, so this extends the
## same minimal DOM shim the other browser-mount suites use
## (`test_code_copy_browser_mount.nim` etc.) -- adding only a
## `hasAttribute` on the element prototype. Per the shim's direct-dispatch
## discipline (no real event bubbling), the counter component wires its
## click listener directly on its own button, and the test dispatches
## clicks directly on that button.

when not defined(js):
  {.error: "test_component_embed_browser_mount must be compiled with the JS backend: nim js -r tests/docs/test_component_embed_browser_mount.nim".}

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

  // Added for this suite: null-safe presence check (the other shims omit
  // it; the M9 gotchas call for adding it wherever it's touched).
  ElementNode.prototype.hasAttribute = function(name) {
    return (name in this.attributes);
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

  var globalObj = (typeof globalThis !== 'undefined') ? globalThis :
    ((typeof global !== 'undefined') ? global : null);
  if (globalObj) {
    globalObj.document = doc;
    globalObj.window = { document: doc };
  }
})();
""".}

import std/[unittest, strutils]
import isonim/web/dom_api
import isonim/web/client
import isonim/web/web_renderer
import isonim/core/signals
import ../../src/core/markdown_vm
import ../../src/components/markdown_view
import ../../src/components/error_boundary

proc attrOf(n: Node; name: cstring): string =
  var v: cstring
  {.emit: [v, " = ", n, ".getAttribute(", name, ");"].}
  $v

proc dispatchClickEvent(e: Element) {.importcpp: "#.dispatchEvent({type: 'click'})".}

# --- Fixture components registered by the test (framework ships none) ------
#
# `Counter`: each embed allocates its OWN isonim Signal[int] inside the
# render closure -- the reactive state is private to that embed, keyed off
# its unique `instanceId`. The click listener is wired directly on this
# embed's own button (no delegation) and updates this embed's own display
# from this embed's own signal.
proc makeCounterRegistry(): ComponentRegistry[WebRenderer, Node] =
  result = newComponentRegistry[WebRenderer, Node]()
  result.register("Counter", proc(r: WebRenderer; inst: ComponentInstance): Node =
    let count = createSignal(inst.props.getInt("start", 0)) ## per-embed reactive state
    let wrapper = r.createElement("div")
    r.setAttribute(wrapper, "class", "counter")
    r.setAttribute(wrapper, "id", inst.instanceId)
    let display = r.createElement("span")
    r.setAttribute(display, "class", "counter-value")
    r.appendChild(display, r.createTextNode($count.val))
    r.appendChild(wrapper, display)
    let btn = r.createElement("button")
    r.setAttribute(btn, "class", "counter-inc")
    r.appendChild(btn, r.createTextNode("+"))
    proc onClick(ev: Event) =
      count.val = count.val + 1
      display.textContent = cstring($count.val)
    r.addEventListener(btn, "click", onClick)
    r.appendChild(wrapper, btn)
    wrapper)
  result.register("Ok", proc(r: WebRenderer; inst: ComponentInstance): Node =
    let el = r.createElement("span")
    r.setAttribute(el, "class", "ok-embed")
    r.appendChild(el, r.createTextNode("healthy"))
    el)
  result.register("Boom", proc(r: WebRenderer; inst: ComponentInstance): Node =
    raise newException(ValueError, "kaboom"))

proc mountBody(rootId, raw: string; reg: ComponentRegistry[WebRenderer, Node]): Node =
  let rootEl = document.getElementById(rootId)
  let blocks = parseMarkdownBlocks(raw, "", nil, nil,
    proc(name: string): bool = reg.hasComponent(name))
  discard render(proc(): Node =
    let r = WebRenderer()
    renderMarkdownBody[WebRenderer, Node](r, blocks, reg)
  , rootEl)
  rootEl.firstChild ## the markdown-body <div>

suite "docs JS live component embedding (Tier 3, JS-target)":
  test "two counter embeds on one page keep strictly independent state":
    let reg = makeCounterRegistry()
    let body = mountBody("isonim-docs-embed-root-counters", "<Counter/>\n\n<Counter/>", reg)

    let firstCounter = body.firstChild
    let secondCounter = firstCounter.nextSibling
    check attrOf(firstCounter, "class") == "counter"
    check attrOf(secondCounter, "class") == "counter"
    # unique instance ids -> no shared scope
    check attrOf(firstCounter, "id") != attrOf(secondCounter, "id")

    let firstValue = firstCounter.firstChild
    let secondValue = secondCounter.firstChild
    let firstBtn = Element(firstValue.nextSibling)
    let secondBtn = Element(secondValue.nextSibling)
    check ($firstValue.textContent) == "0"
    check ($secondValue.textContent) == "0"

    # increment the first embed twice, the second once
    dispatchClickEvent(firstBtn)
    dispatchClickEvent(firstBtn)
    dispatchClickEvent(secondBtn)

    check ($firstValue.textContent) == "2"  ## first embed's own signal
    check ($secondValue.textContent) == "1" ## second embed unaffected -> not shared

  test "a throwing embed renders the error-boundary fallback while a sibling still works":
    let reg = makeCounterRegistry()
    let body = mountBody("isonim-docs-embed-root-boom", "<Boom/>\n\n<Counter/>", reg)

    let boomNode = body.firstChild
    let counterNode = boomNode.nextSibling
    # the throwing embed became the inline error-boundary fallback span
    check attrOf(boomNode, "class") == errorBoundaryClass
    check ($boomNode.textContent) == errorBoundaryFallbackText
    check not ($body.textContent).contains("kaboom") ## the message never leaks

    # the sibling counter embed still mounted and still works
    check attrOf(counterNode, "class") == "counter"
    let value = counterNode.firstChild
    let btn = Element(value.nextSibling)
    check ($value.textContent) == "0"
    dispatchClickEvent(btn)
    check ($value.textContent) == "1"
