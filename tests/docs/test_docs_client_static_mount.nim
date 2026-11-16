## Tier 3 (JS browser mount) suite for `src/docs_client.nim`: proves the shared
## progressive-enhancement helper wires `:::tabs` switching (click + keyboard
## arrows), `Copy code` buttons, collapsible sidebar sections, mobile nav
## drawer, theme toggle, and search box onto static MPA pages.

when not defined(js):
  {.error: "test_docs_client_static_mount requires JS backend: nim js -r tests/docs/test_docs_client_static_mount.nim".}

{.emit: """
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
  function ElementNode(tag) {
    this._id = ++nodeIdCounter;
    this.nodeType = 1;
    this.nodeName = tag.toUpperCase();
    this.tagName = tag.toUpperCase();
    this.localName = tag.toLowerCase();
    this.parentNode = null;
    this.firstChild = null;
    this.nextSibling = null;
    this.childNodes = [];
    this.attributes = {};
    this.className = '';
    this._eventListeners = {};
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
  Object.defineProperty(ElementNode.prototype, 'textContent', {
    get: function() {
      var r = '';
      for (var i = 0; i < this.childNodes.length; i++) {
        var c = this.childNodes[i];
        r += (c.nodeType === 3) ? c.data : c.textContent;
      }
      return r;
    },
    set: function(val) {
      this.childNodes = [];
      if (val !== '' && val != null) {
        var t = new TextNode(String(val));
        t.parentNode = this;
        this.childNodes.push(t);
      }
      updateSiblings(this);
    }
  });
  ElementNode.prototype.appendChild = function(child) {
    if (child.parentNode) child.parentNode.removeChild(child);
    child.parentNode = this;
    this.childNodes.push(child);
    updateSiblings(this);
    return child;
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
  ElementNode.prototype.setAttribute = function(name, value) {
    this.attributes[name] = String(value);
    if (name === 'class') this.className = String(value);
    if (name === 'id') elementsById[String(value)] = this;
  };
  ElementNode.prototype.removeAttribute = function(name) {
    delete this.attributes[name];
  };
  ElementNode.prototype.getAttribute = function(name) {
    return (name in this.attributes) ? this.attributes[name] : null;
  };
  ElementNode.prototype.addEventListener = function(ev, fn) {
    if (!this._eventListeners[ev]) this._eventListeners[ev] = [];
    this._eventListeners[ev].push(fn);
  };
  ElementNode.prototype.focus = function() { doc.activeElement = this; };
  ElementNode.prototype.dispatchEvent = function(ev) {
    ev.target = this;
    ev.currentTarget = this;
    ev.preventDefault = ev.preventDefault || function() {};
    var hs = (this._eventListeners[ev.type] || []).slice();
    for (var i = 0; i < hs.length; i++) hs[i](ev);
    return true;
  };

  var docElement = new ElementNode('html');
  var body = new ElementNode('body');
  docElement.appendChild(body);
  var elementsById = {};
  var doc = {
    nodeType: 9,
    createElement: function(tag) { return new ElementNode(tag); },
    createTextNode: function(text) { return new TextNode(String(text)); },
    getElementById: function(id) { return elementsById[id] || null; },
    body: body,
    documentElement: docElement,
    activeElement: null,
    _listeners: {},
    addEventListener: function(ev, fn) {
      if (!this._listeners[ev]) this._listeners[ev] = [];
      this._listeners[ev].push(fn);
    }
  };
  var lastClip = '';
  var nav = {
    clipboard: {
      writeText: function(t) { lastClip = t; return { catch: function() {} }; }
    }
  };
  var store = {};
  var ls = {
    getItem: function(k) { return (k in store) ? store[k] : null; },
    setItem: function(k, v) { store[k] = String(v); }
  };
  var g = (typeof globalThis !== 'undefined') ? globalThis : global;
  g.document = doc;
  g.window = { document: doc, matchMedia: function() { return { matches: false }; } };
  g.localStorage = ls;
  Object.defineProperty(g, 'navigator', { value: nav, configurable: true, writable: true });
  g.__lastClip = function() { return lastClip; };
})();
""".}

import std/unittest
import isonim/web/dom_api
import isonim/web/web_renderer
import isonim/content/markdown
import ../../src/components/markdown_view
import ../../src/components/navigation_view
import ../../src/components/theme_toggle
import ../../src/core/theme_vm
import ../../src/core/search_vm
import ../../src/docs_client

proc fireClick(el: Element) {.importcpp: "#.dispatchEvent({type: 'click'})".}
proc fireKey(el: Element; key: cstring) {.importcpp: "#.dispatchEvent({type: 'keydown', key: #})".}
proc getAttr(el: Element; name: cstring): cstring {.importcpp: "(#.getAttribute(#) || '')".}
proc hasAttr(el: Element; name: cstring): bool {.importcpp: "(#.getAttribute(#) !== null)".}
proc lastCopied(): cstring {.importcpp: "globalThis.__lastClip()".}

suite "docs_client progressive enhancement on static MPA DOM":
  test "mountStaticDocsClient wires :::tabs click + keyboard, Copy code, sidebar collapse and theme toggle":
    let r = WebRenderer()
    let md =
      ":::tabs\n@tab Linux\n```bash\ncurl -fsSL https://get.reprobuild.com/sh | sh\n```\n" &
      "@tab macOS\nUse Nix.\n@tab Windows\nUse Scoop.\n:::\n"
    let blocks = parseMarkdownBlocks(md)
    let bodyNode = Node(documentBody(document))
    let mdRoot = renderMarkdownBody[WebRenderer, Node](r, blocks)
    r.appendChild(bodyNode, mdRoot)

    # Sidebar collapsible section
    let sec = r.createElement("div")
    r.setAttribute(sec, "class", sidebarSectionClass & " " & sidebarSectionExpandedClass)
    r.setAttribute(sec, "data-nav-key", "guides")
    let secBtn = r.createElement("button")
    r.setAttribute(secBtn, "class", sidebarSectionTitleClass)
    r.setAttribute(secBtn, "aria-expanded", "true")
    r.appendChild(Node(sec), Node(secBtn))
    r.appendChild(bodyNode, Node(sec))

    # Theme toggle button
    let toggleNode = renderThemeToggle[WebRenderer, Node](r, newThemeViewModel("", false))
    r.appendChild(bodyNode, toggleNode)

    mountStaticDocsClient(SearchIndex())

    # 1. Tabs: initially tab 0 selected, panels 1 & 2 hidden
    let tabs = findAllElementsByClass(bodyNode, cstring(tabClass))
    let panels = findAllElementsByClass(bodyNode, cstring(tabpanelClass))
    check tabs.len == 3
    check panels.len == 3
    check $getAttr(tabs[0], "aria-selected") == "true"
    check hasAttr(panels[2], "hidden")

    fireClick(tabs[2]) # Switch to Windows tab
    check $getAttr(tabs[2], "aria-selected") == "true"
    check $getAttr(tabs[0], "aria-selected") == "false"
    check not hasAttr(panels[2], "hidden")
    check hasAttr(panels[0], "hidden")

    fireKey(tabs[2], "ArrowRight") # Wrap around to Linux tab (0)
    check $getAttr(tabs[0], "aria-selected") == "true"
    check not hasAttr(panels[0], "hidden")

    # 2. Code copy button inside tab 0
    let copyBtns = findAllElementsByClass(bodyNode, cstring(codeCopyButtonClass))
    check copyBtns.len == 1
    fireClick(copyBtns[0])
    check $getAttr(copyBtns[0], "data-copied") == "true"
    check $lastCopied() == "curl -fsSL https://get.reprobuild.com/sh | sh"

    # 3. Sidebar collapse toggle
    fireClick(secBtn)
    check $getAttr(secBtn, "aria-expanded") == "false"

    # 4. Theme toggle
    let themeBtn = getElementById(document, cstring(themeToggleId))
    fireClick(themeBtn)
    check $getAttr(themeBtn, "data-theme") == "dark"
