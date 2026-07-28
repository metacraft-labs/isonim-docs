## isonim-docs Layer 2 — rendering for the tutorial ViewModel
## (`src/core/tutorial_vm.nim`, M10 deliverable 1).
##
## The interactive-tutorial layout: a progress header (bar + "N of M
## steps" label), a checklist of steps (each a checkmark reflecting its
## persisted completion + a link to its in-page anchor), a reset button,
## and a prev/next series footer. Like `symbol_reference.nim`, the tree is
## variable-length and can't be a static `ui(...)` DSL tree, so every
## renderer is written directly against the generic backend API for the
## Mock/browser side and plain escaped string building for the SSR side --
## the two kept byte-for-byte in lock-step (dual-target parity).
##
## Behaviour hooks the JS mount binds to are carried as `data-*` attrs the
## SSR markup already emits (`data-tutorial-step`, `data-tutorial-reset`,
## `data-completed`), so hydration attaches to server-rendered nodes
## instead of re-rendering -- the same contract the M3 copy button and M9
## component embeds use.

import isonim/ssr/escape
import ../core/tutorial_vm

const
  tutLayoutClass* = "docs-tutorial"
  tutProgressClass* = "docs-tutorial-progress"
  tutProgressBarClass* = "docs-tutorial-progress-bar"
  tutProgressFillClass* = "docs-tutorial-progress-fill"
  tutProgressLabelClass* = "docs-tutorial-progress-label"
  tutStepsClass* = "docs-tutorial-steps"
  tutStepClass* = "docs-tutorial-step"
  tutStepDoneClass* = "docs-tutorial-step-done"
  tutCheckClass* = "docs-tutorial-check"
  tutStepLinkClass* = "docs-tutorial-step-link"
  tutResetClass* = "docs-tutorial-reset"
  tutSeriesNavClass* = "docs-tutorial-series-nav"
  tutPrevClass* = "docs-tutorial-prev"
  tutNextClass* = "docs-tutorial-next"

  tutStepAttr* = "data-tutorial-step"   ## step id, on each checklist item
  tutResetAttr* = "data-tutorial-reset" ## on the reset button
  tutCompletedAttr* = "data-completed"  ## "true"/"false" on each step item
  checkmarkGlyph* = "✓"            ## ✓ shown for a completed step

proc progressLabel*(vm: TutorialViewModel): string =
  ## The human-readable progress line the header shows -- one shared
  ## string so the tree and SSR paths never phrase it differently.
  $completedCount(vm) & " of " & $totalSteps(vm) & " steps"

# --- MockRenderer / browser tree mode -----------------------------------

proc renderProgress[R, E](r: R; vm: TutorialViewModel): E =
  let wrap = r.createElement("div")
  r.setAttribute(wrap, "class", tutProgressClass)

  let bar = r.createElement("div")
  r.setAttribute(bar, "class", tutProgressBarClass)
  r.setAttribute(bar, "role", "progressbar")
  r.setAttribute(bar, "aria-valuemin", "0")
  r.setAttribute(bar, "aria-valuemax", "100")
  r.setAttribute(bar, "aria-valuenow", $progressPercent(vm))
  let fill = r.createElement("div")
  r.setAttribute(fill, "class", tutProgressFillClass)
  r.setAttribute(fill, "style", "width:" & $progressPercent(vm) & "%")
  r.appendChild(bar, fill)
  r.appendChild(wrap, bar)

  let label = r.createElement("p")
  r.setAttribute(label, "class", tutProgressLabelClass)
  r.appendChild(label, r.createTextNode(progressLabel(vm)))
  r.appendChild(wrap, label)
  wrap

proc renderStep[R, E](r: R; step: TutorialStep): E =
  let li = r.createElement("li")
  r.setAttribute(li, "class",
    if step.completed: tutStepClass & " " & tutStepDoneClass else: tutStepClass)
  r.setAttribute(li, tutStepAttr, step.id)
  r.setAttribute(li, tutCompletedAttr, if step.completed: "true" else: "false")

  let check = r.createElement("span")
  r.setAttribute(check, "class", tutCheckClass)
  r.setAttribute(check, "aria-hidden", "true")
  r.appendChild(check, r.createTextNode(if step.completed: checkmarkGlyph else: ""))
  r.appendChild(li, check)

  let a = r.createElement("a")
  r.setAttribute(a, "class", tutStepLinkClass)
  r.setAttribute(a, "href", step.anchor)
  r.appendChild(a, r.createTextNode(step.title))
  r.appendChild(li, a)
  li

proc renderSeriesNav[R, E](r: R; vm: TutorialViewModel): E =
  let nav = r.createElement("nav")
  r.setAttribute(nav, "class", tutSeriesNavClass)
  r.setAttribute(nav, "aria-label", "Tutorial series")
  if vm.prev.present:
    let a = r.createElement("a")
    r.setAttribute(a, "class", tutPrevClass)
    r.setAttribute(a, "rel", "prev")
    r.setAttribute(a, "href", vm.prev.routePath)
    r.appendChild(a, r.createTextNode("← " & vm.prev.title))
    r.appendChild(nav, a)
  if vm.next.present:
    let a = r.createElement("a")
    r.setAttribute(a, "class", tutNextClass)
    r.setAttribute(a, "rel", "next")
    r.setAttribute(a, "href", vm.next.routePath)
    r.appendChild(a, r.createTextNode(vm.next.title & " →"))
    r.appendChild(nav, a)
  nav

proc renderTutorial*[R, E](r: R; vm: TutorialViewModel): E =
  ## The full tutorial layout tree: progress header, step checklist, reset
  ## button, and series prev/next footer.
  let layout = r.createElement("section")
  r.setAttribute(layout, "class", tutLayoutClass)
  r.setAttribute(layout, "data-tutorial-series", vm.seriesId)

  let h2 = r.createElement("h2")
  r.appendChild(h2, r.createTextNode(vm.title))
  r.appendChild(layout, h2)

  r.appendChild(layout, renderProgress[R, E](r, vm))

  let list = r.createElement("ol")
  r.setAttribute(list, "class", tutStepsClass)
  for step in vm.steps:
    r.appendChild(list, renderStep[R, E](r, step))
  r.appendChild(layout, list)

  let reset = r.createElement("button")
  r.setAttribute(reset, "type", "button")
  r.setAttribute(reset, "class", tutResetClass)
  r.setAttribute(reset, tutResetAttr, "true")
  r.appendChild(reset, r.createTextNode("Reset progress"))
  r.appendChild(layout, reset)

  r.appendChild(layout, renderSeriesNav[R, E](r, vm))
  layout

# --- SSR string mode ------------------------------------------------------

proc progressHtml(vm: TutorialViewModel): string =
  let pct = $progressPercent(vm)
  "<div class=\"" & tutProgressClass & "\">" &
    "<div class=\"" & tutProgressBarClass & "\" role=\"progressbar\" " &
      "aria-valuemin=\"0\" aria-valuemax=\"100\" aria-valuenow=\"" & pct & "\">" &
      "<div class=\"" & tutProgressFillClass & "\" style=\"width:" & pct & "%\"></div>" &
    "</div>" &
    "<p class=\"" & tutProgressLabelClass & "\">" & escapeHtml(progressLabel(vm)) & "</p>" &
  "</div>"

proc stepHtml(step: TutorialStep): string =
  let cls = if step.completed: tutStepClass & " " & tutStepDoneClass else: tutStepClass
  "<li class=\"" & cls & "\" " & tutStepAttr & "=\"" & escapeAttr(step.id) & "\" " &
    tutCompletedAttr & "=\"" & (if step.completed: "true" else: "false") & "\">" &
    "<span class=\"" & tutCheckClass & "\" aria-hidden=\"true\">" &
      (if step.completed: checkmarkGlyph else: "") & "</span>" &
    "<a class=\"" & tutStepLinkClass & "\" href=\"" & escapeAttr(step.anchor) & "\">" &
      escapeHtml(step.title) & "</a>" &
  "</li>"

proc seriesNavHtml(vm: TutorialViewModel): string =
  result = "<nav class=\"" & tutSeriesNavClass & "\" aria-label=\"Tutorial series\">"
  if vm.prev.present:
    result.add "<a class=\"" & tutPrevClass & "\" rel=\"prev\" href=\"" &
      escapeAttr(vm.prev.routePath) & "\">" & escapeHtml("← " & vm.prev.title) & "</a>"
  if vm.next.present:
    result.add "<a class=\"" & tutNextClass & "\" rel=\"next\" href=\"" &
      escapeAttr(vm.next.routePath) & "\">" & escapeHtml(vm.next.title & " →") & "</a>"
  result.add "</nav>"

proc renderTutorialHtml*(vm: TutorialViewModel): string =
  ## SSR string-mode rendering -- byte-for-byte the same shape/order as
  ## `renderTutorial`.
  result = "<section class=\"" & tutLayoutClass & "\" data-tutorial-series=\"" &
    escapeAttr(vm.seriesId) & "\">"
  result.add "<h2>" & escapeHtml(vm.title) & "</h2>"
  result.add progressHtml(vm)
  result.add "<ol class=\"" & tutStepsClass & "\">"
  for step in vm.steps:
    result.add stepHtml(step)
  result.add "</ol>"
  result.add "<button type=\"button\" class=\"" & tutResetClass & "\" " &
    tutResetAttr & "=\"true\">Reset progress</button>"
  result.add seriesNavHtml(vm)
  result.add "</section>"
