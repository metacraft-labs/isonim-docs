## Tier 1 (ViewModel / pure-helper) M10 tutorial suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free `src/core/tutorial_vm.nim` (M10
## deliverable 1): step-progress derivation, per-step completion persisted
## through an injected fake `localStorage`-shaped store, the reset action
## (both its in-memory and storage halves), and prev/next navigation
## within a tutorial series -- all through plain closures/in-memory
## tables, no filesystem or browser access anywhere, so the exact same
## assertions hold on both targets (mirrors `test_theme_vm.nim`).

import std/[unittest, tables]
import ../../src/core/tutorial_vm

proc sampleSteps(): seq[TutorialStep] =
  @[newTutorialStep("install", "Install the toolchain"),
    newTutorialStep("hello", "Write hello world"),
    newTutorialStep("build", "Build and run")]

proc fakeStore(): tuple[store: TableRef[string, string],
                        get: TutorialStorageGet, put: TutorialStorageSet] =
  let store = newTable[string, string]()
  let get = proc(key: string): string = store.getOrDefault(key, "")
  let put = proc(key, value: string) = store[key] = value
  (store, get, put)

suite "docs tutorial ViewModel -- step shape + progress (Tier 1, dual-target)":
  test "newTutorialStep defaults the anchor to '#' & id":
    let s = newTutorialStep("install", "Install")
    check s.anchor == "#install"
    check s.completed == false
    check newTutorialStep("a", "A", "#custom").anchor == "#custom"

  test "a fresh tutorial reports zero progress":
    let vm = newTutorialViewModel("intro", "Intro", sampleSteps())
    check totalSteps(vm) == 3
    check completedCount(vm) == 0
    check progressPercent(vm) == 0
    check isComplete(vm) == false

  test "progressPercent tracks completed steps and rounds to nearest whole percent":
    var vm = newTutorialViewModel("intro", "Intro", sampleSteps())
    vm = withStepCompleted(vm, 0, true)
    check completedCount(vm) == 1
    check progressPercent(vm) == 33 # 1/3 -> 33.3 rounds to 33
    vm = withStepCompleted(vm, 1, true)
    check progressPercent(vm) == 67 # 2/3 -> 66.7 rounds to 67
    vm = withStepCompleted(vm, 2, true)
    check progressPercent(vm) == 100
    check isComplete(vm)

  test "an empty tutorial is 0% and never 'complete' (no divide-by-zero)":
    let vm = newTutorialViewModel("empty", "Empty", @[])
    check progressPercent(vm) == 0
    check isComplete(vm) == false

  test "toggleStep flips exactly one step; out-of-range is a harmless no-op":
    var vm = newTutorialViewModel("intro", "Intro", sampleSteps())
    vm = toggleStep(vm, 1)
    check vm.steps[1].completed
    check completedCount(vm) == 1
    vm = toggleStep(vm, 1)
    check vm.steps[1].completed == false
    let before = vm
    check toggleStep(vm, 99) == before # no crash, no change

  test "stepIndexById finds a step by id, -1 when absent":
    let vm = newTutorialViewModel("intro", "Intro", sampleSteps())
    check stepIndexById(vm, "hello") == 1
    check stepIndexById(vm, "nope") == -1

suite "docs tutorial ViewModel -- completion persistence via a fake store (Tier 1, dual-target)":
  test "persistStep writes exactly the key readCompletion reads back":
    let (store, get, put) = fakeStore()
    check readCompletion(get, "intro", "install") == false
    persistStep(put, "intro", "install", true)
    check readCompletion(get, "intro", "install")
    check store[stepStorageKey("intro", "install")] == stepDoneMarker
    persistStep(put, "intro", "install", false)
    check readCompletion(get, "intro", "install") == false

  test "storage keys are namespaced per series so same-named steps stay independent":
    let (_, get, put) = fakeStore()
    persistStep(put, "seriesA", "step1", true)
    check readCompletion(get, "seriesA", "step1")
    check readCompletion(get, "seriesB", "step1") == false

  test "applyCompletion hydrates every step's checkmark from storage":
    let (_, get, put) = fakeStore()
    persistStep(put, "intro", "install", true)
    persistStep(put, "intro", "build", true)
    let vm = applyCompletion(newTutorialViewModel("intro", "Intro", sampleSteps()), get)
    check vm.steps[0].completed # install
    check vm.steps[1].completed == false # hello, never persisted
    check vm.steps[2].completed # build
    check completedCount(vm) == 2

  test "a corrupted/unknown stored value reads back as not-done":
    let (_, get, put) = fakeStore()
    put(stepStorageKey("intro", "install"), "yes") # not the done marker
    check readCompletion(get, "intro", "install") == false

suite "docs tutorial ViewModel -- reset (Tier 1, dual-target)":
  test "resetCompletion blanks every checkmark in memory":
    var vm = newTutorialViewModel("intro", "Intro", sampleSteps())
    vm = withStepCompleted(vm, 0, true)
    vm = withStepCompleted(vm, 2, true)
    check completedCount(vm) == 2
    vm = resetCompletion(vm)
    check completedCount(vm) == 0
    check progressPercent(vm) == 0

  test "clearStoredCompletion forgets every step so a reload starts fresh":
    let (_, get, put) = fakeStore()
    persistStep(put, "intro", "install", true)
    persistStep(put, "intro", "hello", true)
    let vm = newTutorialViewModel("intro", "Intro", sampleSteps())
    clearStoredCompletion(put, vm)
    let reloaded = applyCompletion(vm, get)
    check completedCount(reloaded) == 0

suite "docs tutorial ViewModel -- series prev/next (Tier 1, dual-target)":
  test "a zero-value SeriesLink is 'no neighbour'":
    check SeriesLink().present == false
    check SeriesLink(routePath: "/tut/2", title: "Part 2").present

  test "the first tutorial has a next but no prev; the last, the reverse":
    let first = newTutorialViewModel("t1", "Part 1", sampleSteps(),
      next = SeriesLink(routePath: "/tut/part-2", title: "Part 2"))
    check first.prev.present == false
    check first.next.present
    check first.next.routePath == "/tut/part-2"

    let last = newTutorialViewModel("t3", "Part 3", sampleSteps(),
      prev = SeriesLink(routePath: "/tut/part-2", title: "Part 2"))
    check last.prev.present
    check last.next.present == false

suite "docs tutorial ViewModel -- step id slugify fallback (Tier 1, dual-target)":
  test "slugifyStepId folds to ascii-kebab and suffixes the step number":
    check slugifyStepId("Install the Toolchain", 0) == "install-the-toolchain-1"
    check slugifyStepId("Build & Run!", 2) == "build-run-3"
    check slugifyStepId("", 0) == "step-1" # nothing usable -> a stable default
