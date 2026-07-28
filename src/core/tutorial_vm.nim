## isonim-docs Layer 3 — the interactive-tutorial ViewModel (M10
## deliverable 1). Pure data + pure reducers, zero platform/CSS/DOM
## imports, so it is headless-testable on both `nim c` and `nim js`
## exactly like `theme_vm.nim` and `symbol_reference_vm.nim`.
##
## A tutorial is an ordered list of steps (each a stable id + display
## title, typically an in-page `## Step` heading + its anchor) that a
## reader works through, plus optional prev/next links to the sibling
## tutorials of the same SERIES. Two orthogonal pieces of state ride on
## top of that static shape:
##   * step COMPLETION, tracked per `(seriesId, stepId)` and persisted to
##     `localStorage` on the JS mount so a returning reader keeps their
##     checkmarks -- and cleared wholesale by `reset`;
##   * derived PROGRESS (how many of the total steps are done, as a count
##     and a 0..100 percent) the layout renders as a progress bar.
##
## Persistence (`localStorage` on JS, nothing on SSR) is never touched
## directly here: `readCompletion`/`persistStep`/`resetCompletion` take
## injected get/set closures -- the exact same seam `theme_vm`'s
## `readPersistedTheme`/`persistTheme` use -- so a test hands them a fake
## in-memory store and the real JS mount hands them real `localStorage`
## glue. The VM itself is content-agnostic: it is fed an already-assembled
## `seq[TutorialStep]` + series links (from H2 headings, front matter, or
## anywhere), it never derives them, mirroring how `symbol_reference_vm`
## is fed an already-ingested module.

import std/strutils

type
  TutorialStep* = object
    id*: string      ## Stable per-step id: the storage-key suffix AND the
                     ## in-page anchor the step links to. Must be unique
                     ## within a tutorial (the H2 anchor id already is).
    title*: string   ## Display title shown in the step rail / checklist.
    anchor*: string  ## In-page href the step's checklist entry points at
                     ## (usually "#" & id); empty when the step is not a
                     ## navigable section.
    completed*: bool ## Whether the reader has marked this step done --
                     ## hydrated from storage by `applyCompletion`, toggled
                     ## by the layout, the source of the rendered checkmark.

  SeriesLink* = object
    ## A prev/next neighbour within the same tutorial series. `routePath`
    ## empty means "no neighbour in that direction" (`present` is false),
    ## so the first tutorial has no prev and the last has no next.
    routePath*: string
    title*: string

  TutorialViewModel* = object
    seriesId*: string        ## Stable id namespacing this tutorial's storage
                             ## keys, so two tutorials never collide on a
                             ## shared step id.
    title*: string
    steps*: seq[TutorialStep]
    prev*: SeriesLink        ## Previous tutorial in the series (`present`
                             ## false when this is the first).
    next*: SeriesLink        ## Next tutorial in the series.

const
  tutorialStoragePrefix* = "isonim-docs-tutorial"
  stepDoneMarker* = "1" ## The one value written for a completed step; any
                        ## other stored value (empty, cleared, corrupted)
                        ## reads back as "not done", so a tutorial never
                        ## fails to render over a bad storage entry.

proc present*(link: SeriesLink): bool =
  ## A series link points somewhere only when it carries a real route
  ## path -- the zero-value `SeriesLink()` is "no neighbour".
  link.routePath.len > 0

proc stepStorageKey*(seriesId, stepId: string): string =
  ## The single `localStorage` key a step's completion is read from and
  ## written to -- the one place the key shape lives, so a read and a
  ## write can never disagree. Namespaced by `seriesId` so identically
  ## named steps in different tutorials stay independent.
  tutorialStoragePrefix & ":" & seriesId & ":" & stepId

# --- Derived progress ---------------------------------------------------

proc totalSteps*(vm: TutorialViewModel): int = vm.steps.len

proc completedCount*(vm: TutorialViewModel): int =
  ## How many steps are currently marked done.
  for s in vm.steps:
    if s.completed: inc result

proc progressPercent*(vm: TutorialViewModel): int =
  ## Completion as a 0..100 integer percent, rounded to the nearest whole
  ## percent. A tutorial with no steps is 0% (never a divide-by-zero),
  ## and an all-done tutorial is exactly 100 (the rounding can't overshoot
  ## because `completedCount <= totalSteps`).
  if vm.steps.len == 0: return 0
  (completedCount(vm) * 100 + vm.steps.len div 2) div vm.steps.len

proc isComplete*(vm: TutorialViewModel): bool =
  ## True only when there is at least one step and every step is done --
  ## an empty tutorial is never "complete".
  vm.steps.len > 0 and completedCount(vm) == vm.steps.len

proc stepIndexById*(vm: TutorialViewModel; stepId: string): int =
  ## The index of the step with `stepId`, or -1 when none matches -- the
  ## lookup the layout uses to toggle exactly the clicked step.
  result = -1
  for i in 0 ..< vm.steps.len:
    if vm.steps[i].id == stepId: return i

# --- Pure state transitions ---------------------------------------------

proc withStepCompleted*(vm: TutorialViewModel; index: int; done: bool): TutorialViewModel =
  ## Returns a copy of `vm` with step `index` set to `done`. An
  ## out-of-range index is a no-op (returns `vm` unchanged) rather than
  ## raising -- a stale click must never crash the page.
  result = vm
  if index >= 0 and index < result.steps.len:
    result.steps[index].completed = done

proc toggleStep*(vm: TutorialViewModel; index: int): TutorialViewModel =
  ## Flips step `index`'s completion; out-of-range is a no-op.
  if index >= 0 and index < vm.steps.len:
    withStepCompleted(vm, index, not vm.steps[index].completed)
  else:
    vm

proc resetCompletion*(vm: TutorialViewModel): TutorialViewModel =
  ## Returns a copy with every step marked not-done -- the pure half of
  ## the "reset" action (the storage half is `clearStoredCompletion`).
  result = vm
  for i in 0 ..< result.steps.len:
    result.steps[i].completed = false

# --- Persistence seam (injected storage) --------------------------------

type
  TutorialStorageGet* = proc(key: string): string {.closure.}
  TutorialStorageSet* = proc(key, value: string) {.closure.}

proc readCompletion*(get: TutorialStorageGet; seriesId, stepId: string): bool =
  ## Reads one step's persisted completion through the injected `get`
  ## seam. Only the exact `stepDoneMarker` counts as done; anything else
  ## (unset, cleared to "", a value a future build wrote) reads back as
  ## not-done, mirroring `theme_vm.themeFromString`'s tolerant fallback.
  get(stepStorageKey(seriesId, stepId)) == stepDoneMarker

proc persistStep*(set: TutorialStorageSet; seriesId, stepId: string; done: bool) =
  ## Writes one step's completion: `stepDoneMarker` when done, "" (the
  ## cleared value `readCompletion` treats as not-done) otherwise -- so a
  ## toggle-off is durably persisted, not just dropped.
  set(stepStorageKey(seriesId, stepId), if done: stepDoneMarker else: "")

proc applyCompletion*(vm: TutorialViewModel; get: TutorialStorageGet): TutorialViewModel =
  ## Hydrates every step's `completed` flag from storage through `get` --
  ## the read counterpart the SSR-agnostic initial render (SSR passes a
  ## get that always returns "") and the JS mount (real `localStorage`)
  ## both funnel through, so checkmarks come from exactly one rule.
  result = vm
  for i in 0 ..< result.steps.len:
    result.steps[i].completed = readCompletion(get, vm.seriesId, result.steps[i].id)

proc clearStoredCompletion*(set: TutorialStorageSet; vm: TutorialViewModel) =
  ## The storage half of "reset": clears every step's key back to the
  ## not-done value. Pairs with `resetCompletion` (the in-memory half) so
  ## the reset button both blanks the checkmarks and forgets them.
  for s in vm.steps:
    persistStep(set, vm.seriesId, s.id, false)

# --- Builders -----------------------------------------------------------

proc newTutorialViewModel*(seriesId, title: string; steps: seq[TutorialStep];
                           prev: SeriesLink = SeriesLink();
                           next: SeriesLink = SeriesLink()): TutorialViewModel =
  TutorialViewModel(seriesId: seriesId, title: title, steps: steps,
                    prev: prev, next: next)

proc newTutorialStep*(id, title: string; anchor: string = ""): TutorialStep =
  ## Builds a step, defaulting its in-page `anchor` to `"#" & id` when the
  ## caller doesn't supply one (the common case: the step id IS the H2
  ## heading anchor). An explicit empty-string anchor can't be requested
  ## this way, which is intentional -- every real step is navigable.
  TutorialStep(id: id, title: title,
               anchor: if anchor.len > 0: anchor else: "#" & id)

proc slugifyStepId*(text: string; index: int): string =
  ## A deterministic fallback step id for a heading with no anchor of its
  ## own: lowercased, non-alphanumerics collapsed to single hyphens,
  ## suffixed with the 1-based step number so two same-named headings
  ## never collide. Pure ASCII folding (no Unicode tables), matching the
  ## dual-target constraint.
  var s = ""
  var lastDash = false
  for c in text:
    if c in {'a'..'z', '0'..'9'}:
      s.add c; lastDash = false
    elif c in {'A'..'Z'}:
      s.add chr(ord(c) + (ord('a') - ord('A'))); lastDash = false
    elif not lastDash and s.len > 0:
      s.add '-'; lastDash = true
  s = s.strip(chars = {'-'})
  let base = if s.len > 0: s else: "step"
  base & "-" & $(index + 1)
