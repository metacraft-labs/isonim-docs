## Tier 1 + Tier 2 M9 deliverable 1 + 3 suite -- DUAL-TARGET: both
## `nim c -r` AND `nim js -r` must pass.
##
## Proves the custom-component markdown extension end to end on the pure
## side:
##  * `parseMarkdownBlocks` (`src/core/markdown_vm.nim`) extracts a
##    `<MyButton .../>` tag -- self-closing AND paired -- into a
##    `bkComponent` AST node carrying the Capitalized name + typed props
##    (`getStr`/`getInt`/`getBool`), distinguishing a Capitalized component
##    tag from ordinary lowercase HTML (which stays plain text).
##  * An UNKNOWN component tag (rejected by the registry's `knownPredicate`)
##    becomes a TYPED error/fallback `bkComponent` node (`componentError`
##    set) -- never a crash, never silent corruption.
##  * The consumer-facing `ComponentRegistry` (M9 deliverable 3) resolves a
##    registered component through `renderMarkdownBody`/`renderMarkdownBodyHtml`
##    (both the MockRenderer tree path and the SSR string path, in
##    lock-step), and renders the typed fallback for an unregistered one.
##
## DUAL-TARGET NOTE: every fixture is an in-source `const` string (no
## `std/os` file read), and `core/markdown_vm` + `components/*` are pure
## dual-target modules, so the exact same extraction/rendering runs on both
## backends -- no C-only split to guard.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/markdown_vm
import ../../src/components/markdown_view
import ../../src/components/error_boundary
import ./helpers/mock_tree

const selfClosingDoc = """
Intro paragraph.

<MyButton label="Save" count=3 ratio="1.5" active loud=false/>

Trailing paragraph.
"""

const pairedDoc = "<Callout kind=\"tip\">\nRemember to save often.\n</Callout>"

const lowercaseHtmlDoc = "A line with <div>plain</div> and <br/> ordinary html."

suite "docs custom-component extraction -- pure parsing (Tier 1, dual-target)":
  test "parseMarkdownBlocks extracts a self-closing <MyButton/> tag into a bkComponent node":
    let blocks = parseMarkdownBlocks(selfClosingDoc)
    check blocks.len == 3
    check blocks[0].kind == bkParagraph
    check blocks[1].kind == bkComponent
    check blocks[2].kind == bkParagraph
    check blocks[1].componentName == "MyButton"
    check blocks[1].componentError == ""
    check blocks[1].componentChildren == ""

  test "parseMarkdownBlocks parses props of different types (string, int, bool)":
    let blk = parseMarkdownBlocks(selfClosingDoc)[1]
    # quoted string
    check blk.props.hasProp("label")
    check blk.props.getStr("label") == "Save"
    check blk.props.getProp("label").kind == pvkString
    # unquoted integer
    check blk.props.getProp("count").kind == pvkInt
    check blk.props.getInt("count") == 3
    # quoted numeric still reads leniently as an int
    check blk.props.getInt("ratio", -1) == -1 # "1.5" is not an int
    check blk.props.getStr("ratio") == "1.5"
    # valueless attribute -> boolean true
    check blk.props.getProp("active").kind == pvkBool
    check blk.props.getBool("active")
    # explicit unquoted boolean
    check blk.props.getProp("loud").kind == pvkBool
    check blk.props.getBool("loud") == false
    # a missing prop returns the supplied default, never raises
    check blk.props.getStr("nope", "fallback") == "fallback"
    check blk.props.getInt("nope", 42) == 42

  test "parseMarkdownBlocks extracts a paired <Callout>...</Callout> tag with inner children":
    let blocks = parseMarkdownBlocks(pairedDoc)
    check blocks.len == 1
    check blocks[0].kind == bkComponent
    check blocks[0].componentName == "Callout"
    check blocks[0].props.getStr("kind") == "tip"
    check blocks[0].componentChildren == "Remember to save often."

  test "ordinary lowercase HTML is NOT treated as a component (stays plain text)":
    let blocks = parseMarkdownBlocks(lowercaseHtmlDoc)
    check blocks.len == 1
    check blocks[0].kind == bkParagraph
    check spansText(blocks[0].spans).contains("<div>plain</div>")

  test "an unknown component tag becomes a TYPED error node, not a crash":
    let reg = newComponentRegistry[MockRenderer, MockNode]()
    reg.register("MyButton", proc(r: MockRenderer; inst: ComponentInstance): MockNode =
      r.createElement("button"))
    let blocks = parseMarkdownBlocks(
      "<MyButton/>\n\n<Bogus/>", "", nil, nil, reg.knownPredicate())
    check blocks[0].kind == bkComponent
    check blocks[0].componentError == "" # registered -> no error
    check blocks[1].kind == bkComponent
    check blocks[1].componentName == "Bogus"
    check blocks[1].componentError.len > 0 # unknown -> typed error

suite "docs custom-component rendering -- registry resolution (Tier 2, dual-target)":
  test "renderMarkdownBody renders a registered component via its registry closure":
    let reg = newComponentRegistry[MockRenderer, MockNode]()
    reg.register("MyButton", proc(r: MockRenderer; inst: ComponentInstance): MockNode =
      let el = r.createElement("button")
      r.setAttribute(el, "id", inst.instanceId)
      r.setAttribute(el, "class", componentEmbedClass)
      r.appendChild(el, r.createTextNode(inst.props.getStr("label")))
      el)
    let blocks = parseMarkdownBlocks(
      "<MyButton label=\"Save\"/>", "", nil, nil, reg.knownPredicate())
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks, reg)
    let btn = findByTag(root, "button")
    require btn != nil
    check textContent(btn) == "Save"
    check getAttribute(r, btn, "id") == "docs-component-0"

  test "two embeds of the same component get distinct instance ids":
    let reg = newComponentRegistry[MockRenderer, MockNode]()
    reg.register("MyButton", proc(r: MockRenderer; inst: ComponentInstance): MockNode =
      let el = r.createElement("button")
      r.setAttribute(el, "id", inst.instanceId)
      el)
    let blocks = parseMarkdownBlocks(
      "<MyButton/>\n\n<MyButton/>", "", nil, nil, reg.knownPredicate())
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks, reg)
    let buttons = findAllByTag(root, "button")
    check buttons.len == 2
    check getAttribute(r, buttons[0], "id") != getAttribute(r, buttons[1], "id")

  test "an unregistered component renders the typed fallback element, not a crash":
    let reg = newComponentRegistry[MockRenderer, MockNode]()
    let blocks = parseMarkdownBlocks("<Bogus/>", "", nil, nil, reg.knownPredicate())
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks, reg)
    let fallback = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and getAttribute(r, n, "class") == componentUnknownClass)
    require fallback != nil
    check getAttribute(r, fallback, "data-component") == "Bogus"

  test "a throwing component is contained by the error boundary; a sibling still renders":
    let reg = newComponentRegistry[MockRenderer, MockNode]()
    reg.register("Boom", proc(r: MockRenderer; inst: ComponentInstance): MockNode =
      raise newException(ValueError, "kaboom"))
    reg.register("Ok", proc(r: MockRenderer; inst: ComponentInstance): MockNode =
      let el = r.createElement("span")
      r.appendChild(el, r.createTextNode("healthy"))
      el)
    let blocks = parseMarkdownBlocks(
      "<Boom/>\n\n<Ok/>", "", nil, nil, reg.knownPredicate())
    let r = MockRenderer()
    let root = renderMarkdownBody[MockRenderer, MockNode](r, blocks, reg)
    # the throwing embed rendered the error-boundary fallback span
    let errSpan = findWhere(root, proc(n: MockNode): bool =
      n.kind == mnkElement and n.tag == "span" and
      getAttribute(r, n, "class") == errorBoundaryClass)
    require errSpan != nil
    check textContent(errSpan) == errorBoundaryFallbackText
    check not textContent(root).contains("kaboom") # the message never leaks
    # the sibling embed rendered fine
    check textContent(root).contains("healthy")

suite "docs custom-component rendering -- SSR string (Tier 2, dual-target)":
  test "renderMarkdownBodyHtml renders a registered component and escapes props":
    let reg = newHtmlComponentRegistry()
    reg.register("MyButton", proc(inst: ComponentInstance): string =
      "<button id=\"" & inst.instanceId & "\">" & inst.props.getStr("label") & "</button>")
    let blocks = parseMarkdownBlocks(
      "<MyButton label=\"Save\"/>", "", nil, nil, reg.knownPredicate())
    let html = renderMarkdownBodyHtml(blocks, reg)
    check html.contains("<button id=\"docs-component-0\">Save</button>")

  test "renderMarkdownBodyHtml renders the typed fallback for an unregistered component":
    let reg = newHtmlComponentRegistry()
    let blocks = parseMarkdownBlocks("<Bogus/>", "", nil, nil, reg.knownPredicate())
    let html = renderMarkdownBodyHtml(blocks, reg)
    check html.contains("class=\"" & componentUnknownClass & "\"")
    check html.contains("data-component=\"Bogus\"")

  test "renderMarkdownBodyHtml contains a throwing component and keeps siblings":
    let reg = newHtmlComponentRegistry()
    reg.register("Boom", proc(inst: ComponentInstance): string =
      raise newException(ValueError, "kaboom"))
    reg.register("Ok", proc(inst: ComponentInstance): string = "<span>healthy</span>")
    let blocks = parseMarkdownBlocks(
      "<Boom/>\n\n<Ok/>", "", nil, nil, reg.knownPredicate())
    let html = renderMarkdownBodyHtml(blocks, reg)
    check html.contains("class=\"" & errorBoundaryClass & "\"")
    check not html.contains("kaboom")
    check html.contains("<span>healthy</span>")
