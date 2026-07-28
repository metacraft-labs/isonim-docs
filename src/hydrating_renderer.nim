## isonim-docs JS-only hydration renderer (M4 corrective deliverable 1).
##
## Implements the exact same generic renderer duck-type
## `WebRenderer` does (`createElement`/`appendChild`/`setAttribute`/...
## -- see `../isonim/src/isonim/web/web_renderer.nim`), so it drops
## into `renderShell[R, E]`/`renderSiteFrame[R, E]`/`renderMarkdownPage[R, E]`
## unchanged (`main_web.nim`'s `buildApp`/`buildRouteApp` are generic
## over `R` for exactly this reason). The one difference:
## `createElement`/`createTextNode` REUSE the existing SSR-rendered DOM
## node at that structural position instead of unconditionally calling
## `document.createElement`/`createTextNode`.
##
## SSR and the client mount build byte-for-byte the same tag/text tree
## from the same ViewModel data -- the whole point of the shared
## `renderX[R, E]` contract already proven by this repo's MockRenderer
## vs renderRoute vs browser-mount three-tier test suites -- so a
## plain, snapshot-based depth-first positional walk of the
## already-parsed SSR DOM is enough to line reused nodes up with the
## client mount's construction calls. This deliberately does NOT go
## through `../isonim/src/isonim/web/hydration.nim`'s `data-hk`/
## `sharedConfig` registry: that machinery keys reuse off a hydration
## counter advanced by *isonim's own* signals-based component
## construction (`getHydrationKey`/its per-node reactive computation
## scoping), and off `data-hk` markers isonim's `ssrElement` emits --
## this framework's dual SSR-string/client-tree DSL backends (see
## `../isonim/src/isonim/dsl/ui.nim`) don't run through either of those,
## so threading isonim's registry through code that doesn't use it
## would mean forking the DSL's SSR string codegen (a change to the
## isonim engine itself, out of scope for this framework repo) just to
## grow markers a purely-structural walk doesn't need. A structural
## mismatch (SSR/client trees somehow diverged) falls back to creating
## a fresh node for that one spot -- and, since its own children then
## have nothing to match either, every descendant along with it --
## never a crash, just a smaller-than-ideal reuse for that subtree.

when not defined(js):
  {.error: "hydrating_renderer.nim requires the JS backend: nim js -r/nim js".}

import std/strutils
import isonim/web/dom_api
import isonim/web/web_renderer

type
  HydrationFrame = object
    snapshot: seq[Node] ## the reused parent's original children, captured
      ## once (before any mutation) so later sibling moves triggered by
      ## `appendChild` can never desync this frame's own cursor.
    index: int

  HydrationState = ref object
    stack: seq[HydrationFrame]
      ## `stack[^1]` is always "the children of whichever element is
      ## currently under construction" -- pushed by `createElement`/
      ## `createTextNode`, popped by the `appendChild` call that later
      ## attaches that same node into its parent. Mirrors the DSL
      ## codegen's own strict create-then-append call nesting (see
      ## `isonim/dsl/ui.nim`'s `processNode`/`processChildren`), so the
      ## stack always stays balanced.

  HydratingRenderer* = object
    ## Value type (like `WebRenderer`) copied freely through DSL-
    ## generated code; `state` is a `ref` so every copy shares the one
    ## real cursor stack.
    web: WebRenderer
    state: HydrationState

proc snapshotChildren(n: Node): seq[Node] =
  for c in n.childNodes:
    result.add c

proc newHydratingRenderer*(root: Element): HydratingRenderer =
  ## `root`'s current children are the SSR-rendered tree the very
  ## first `createElement` call (the mounted page's own outermost
  ## element) is matched against.
  result.web = WebRenderer()
  result.state = HydrationState(stack: @[HydrationFrame(snapshot: snapshotChildren(Node(root)))])

proc matchesTag(n: Node; tag: string): bool =
  n.nodeType == 1 and ($Element(n).tagName).toLowerAscii == tag

proc createElement*(r: HydratingRenderer; tag: string): Element =
  let top = r.state.stack.len - 1
  var reused: Node = nil
  if r.state.stack[top].index < r.state.stack[top].snapshot.len:
    let candidate = r.state.stack[top].snapshot[r.state.stack[top].index]
    if matchesTag(candidate, tag):
      reused = candidate
      inc r.state.stack[top].index
  result =
    if reused.isNodeNil: r.web.createElement(tag)
    else: Element(reused)
  r.state.stack.add HydrationFrame(
    snapshot: (if reused.isNodeNil: @[] else: snapshotChildren(Node(result))))

proc createTextNode*(r: HydratingRenderer; text: string): Node =
  let top = r.state.stack.len - 1
  var reused: Node = nil
  if r.state.stack[top].index < r.state.stack[top].snapshot.len:
    let candidate = r.state.stack[top].snapshot[r.state.stack[top].index]
    if candidate.nodeType == 3:
      reused = candidate
      inc r.state.stack[top].index
  if reused.isNodeNil:
    result = r.web.createTextNode(text)
  else:
    reused.textContent = cstring(text) ## keep in sync even though SSR/client
      ## text content should already agree byte-for-byte -- cheap, and
      ## correct even if they ever don't.
    result = reused
  r.state.stack.add HydrationFrame()

proc appendChild*(r: HydratingRenderer; parent: Element, child: Element) =
  discard r.state.stack.pop()
  r.web.appendChild(parent, child)

proc appendChild*(r: HydratingRenderer; parent: Element, child: Node) =
  discard r.state.stack.pop()
  r.web.appendChild(parent, child)

proc appendChild*(r: HydratingRenderer; parent: Node, child: Node) =
  discard r.state.stack.pop()
  r.web.appendChild(parent, child)

proc setAttribute*(r: HydratingRenderer; node: Element; name, value: string) =
  r.web.setAttribute(node, name, value)

proc removeAttribute*(r: HydratingRenderer; node: Element; name: string) =
  r.web.removeAttribute(node, name)

proc setTextContent*(r: HydratingRenderer; node: Element; text: string) =
  r.web.setTextContent(node, text)

proc setTextContent*(r: HydratingRenderer; node: Node; text: string) =
  r.web.setTextContent(node, text)

proc addEventListener*(r: HydratingRenderer; node: Element; event: string;
                        handler: proc()) =
  r.web.addEventListener(node, event, handler)

proc addEventListener*(r: HydratingRenderer; node: Element; event: string;
                        handler: proc(ev: Event)) =
  r.web.addEventListener(node, event, handler)

proc firstChild*(r: HydratingRenderer; node: Element): Node = r.web.firstChild(node)
proc nextSibling*(r: HydratingRenderer; node: Element): Node = r.web.nextSibling(node)
proc parentNode*(r: HydratingRenderer; node: Element): Node = r.web.parentNode(node)

proc setStyle*(r: HydratingRenderer; node: Element; prop: string; value: string) =
  r.web.setStyle(node, prop, value)

proc removeChild*(r: HydratingRenderer; parent: Element; child: Element) =
  r.web.removeChild(parent, child)

proc insertBefore*(r: HydratingRenderer; parent: Element; child: Element;
                    reference: Element) =
  r.web.insertBefore(parent, child, reference)

proc clearChildren*(r: HydratingRenderer; node: Element) =
  r.web.clearChildren(node)

proc clearEventListeners*(r: HydratingRenderer; node: Element) =
  r.web.clearEventListeners(node)
