## Thin MockRenderer tree-assertion helpers, built directly on top of
## `isonim/testing/mock_dom`'s public `MockNode` fields -- not a new
## assertion DSL, just enough to avoid repeating the same depth-first
## tree walk in every Tier-2 test.

import isonim/testing/mock_dom

proc findWhere*(root: MockNode; pred: proc(n: MockNode): bool): MockNode =
  ## Depth-first search (pre-order, including `root` itself) for the
  ## first node matching `pred`. Returns `nil` if none match.
  if pred(root):
    return root
  for child in root.children:
    let found = findWhere(child, pred)
    if found != nil:
      return found
  return nil

proc findAllByTag*(root: MockNode; tag: string): seq[MockNode] =
  ## Depth-first (pre-order, including `root` itself) collection of
  ## every element node with the given tag.
  if root.kind == mnkElement and root.tag == tag:
    result.add root
  for child in root.children:
    result.add findAllByTag(child, tag)

proc findByTag*(root: MockNode; tag: string): MockNode =
  ## First descendant (or `root` itself) with the given tag, or `nil`.
  findWhere(root, proc(n: MockNode): bool = n.kind == mnkElement and n.tag == tag)
