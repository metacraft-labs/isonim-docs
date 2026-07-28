## M6 deliverable 2 (component-level error boundary) suite -- DUAL-TARGET:
## both `nim c -r` and `nim js -r` must pass, since the boundary is the
## primitive M9's live component embedding wraps every per-embed hydration
## in, and that hydration runs on the JS target.
##
## Proves the boundary catches a throwing component's render and
## substitutes a small inline fallback element instead of letting the
## exception escape -- exercised on BOTH the MockRenderer tree path
## (`renderErrorBoundary`) and the SSR string path
## (`renderErrorBoundaryHtml`).

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/components/error_boundary
import ./helpers/mock_tree

suite "docs component error boundary (M6 deliverable 2, dual-target)":
  test "renderErrorBoundaryHtml returns the component HTML on success":
    let html = renderErrorBoundaryHtml(proc(): string = "<button>Click</button>")
    check html == "<button>Click</button>"

  test "renderErrorBoundaryHtml substitutes the inline fallback when the component render raises":
    let html = renderErrorBoundaryHtml(proc(): string =
      raise newException(ValueError, "boom"))
    check html.contains("class=\"" & errorBoundaryClass & "\"")
    check html.contains(errorBoundaryFallbackText)
    check not html.contains("boom") # the error message itself never leaks into the page

  test "renderErrorBoundary (tree) returns the component element on success":
    let r = MockRenderer()
    let node = renderErrorBoundary[MockRenderer, MockNode](r, proc(): MockNode =
      let el = r.createElement("button")
      r.appendChild(el, r.createTextNode("Click"))
      el)
    check node.kind == mnkElement
    check node.tag == "button"

  test "renderErrorBoundary (tree) substitutes a fallback element when the component render raises":
    let r = MockRenderer()
    let node = renderErrorBoundary[MockRenderer, MockNode](r, proc(): MockNode =
      raise newException(ValueError, "boom"))
    check node.kind == mnkElement
    check node.tag == "span"
    check getAttribute(r, node, "class") == errorBoundaryClass
    check textContent(node) == errorBoundaryFallbackText
