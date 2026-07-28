## isonim-docs Layer 2 — component-level error boundary (M6 deliverable 2).
##
## A minimal, real error boundary primitive for embedded components: a
## wrapper that runs a component's render and, if it raises, substitutes a
## small inline fallback element in its place rather than letting the
## exception tear down the whole page render. M9's live component
## embedding wraps every per-embed hydration in this so a single throwing
## component shows a fallback instead of breaking the page.
##
## Dual-target by construction, mirroring every other `components/*`
## renderer's split: the tree/mock/browser path (`renderErrorBoundary`)
## is generic over the renderer backend API
## (`createElement`/`setAttribute`/`createTextNode`/`appendChild`), so it
## renders identically under `MockRenderer` and the real `WebRenderer`;
## the SSR string path (`renderErrorBoundaryHtml`) produces the exact same
## shape as a plain string. Neither touches `std/os`, so both compile on
## `nim c` and `nim js`.

import isonim/ssr/escape

const
  errorBoundaryClass* = "docs-component-error"
  errorBoundaryFallbackText* = "This component failed to render."

proc renderErrorBoundary*[R, E](r: R; render: proc(): E {.closure.};
                                 fallbackText: string = errorBoundaryFallbackText): E =
  ## Runs `render()`; on success returns its element unchanged, so a
  ## healthy component is wrapped at zero structural cost. If `render()`
  ## raises any `CatchableError`, returns a small inline
  ## `<span class="docs-component-error">` fallback element instead --
  ## the error never escapes to the caller.
  try:
    render()
  except CatchableError:
    let span = r.createElement("span")
    r.setAttribute(span, "class", errorBoundaryClass)
    r.appendChild(span, r.createTextNode(fallbackText))
    span

proc renderErrorBoundaryHtml*(render: proc(): string {.closure.};
                               fallbackText: string = errorBoundaryFallbackText): string =
  ## SSR string-mode counterpart -- same shape/behavior as
  ## `renderErrorBoundary`: returns the component's HTML on success, or the
  ## `.docs-component-error` inline fallback span on a raised error.
  try:
    render()
  except CatchableError:
    "<span class=\"" & errorBoundaryClass & "\">" & escapeHtml(fallbackText) & "</span>"
