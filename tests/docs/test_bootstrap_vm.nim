## Tier 1 (ViewModel / pure-helper) bootstrap suite -- dual-target: both
## `nim c -r` and `nim js -r` must pass.
##
## Proves:
##   * fixture/content discovery -- `resolveContentDir` joins a base dir
##     and the content dir name deterministically (pure path logic, no
##     filesystem access, so it's exercisable on both targets even
##     though real filesystem I/O is C-target only -- see
##     `test_bootstrap_renderroute.nim` for that).
##   * config loading -- `parseDocsPage` turns real file content into a
##     `DocsPage`, and `shellViewModel` turns that + `DocsConfig` into
##     the ViewModel the shell component renders.
##   * a deterministic docs test helper -- `normalizeHtml`, used by the
##     SSR snapshot tier, behaves identically on both targets.

import std/unittest
import ../../src/core/content
import ../../src/core/config
import ../../src/core/shell_vm
import ./helpers/html_normalize

suite "docs bootstrap -- pure ViewModel / content helpers (Tier 1, dual-target)":
  test "parseDocsPage extracts the title from a leading '# ' heading and treats the rest as body":
    let page = parseDocsPage(
      "# Getting Started\n\nWelcome to isonim-docs.\nSecond line.",
      "fixture:inline")
    check page.title == "Getting Started"
    check page.body == "Welcome to isonim-docs.\nSecond line."
    check page.sourcePath == "fixture:inline"

  test "parseDocsPage tolerates leading blank lines and a bare (non-#) first line as title":
    let page = parseDocsPage("\n\nPlain Title\nBody line one.", "fixture:inline-2")
    check page.title == "Plain Title"
    check page.body == "Body line one."

  test "parseDocsPage strips a leading '#' with no following space too":
    let page = parseDocsPage("#NoSpace\n\nBody.", "fixture:inline-3")
    check page.title == "NoSpace"
    check page.body == "Body."

  test "resolveContentDir joins the base dir and content dir name without a doubled separator":
    check resolveContentDir("/repo/isonim-docs", "content") == "/repo/isonim-docs/content"
    check resolveContentDir("/repo/isonim-docs/", "content") == "/repo/isonim-docs/content"

  test "resolveContentDir defaults the content dir name to 'content'":
    check resolveContentDir("/repo/isonim-docs") == "/repo/isonim-docs/content"

  test "shellViewModel derives title/body/stylesheet from a DocsPage and DocsConfig":
    let page = parseDocsPage("# Hello\n\nWorld.", "fixture:inline-4")
    let vm = shellViewModel(page, docsConfig())
    check vm.title == "Hello"
    check vm.bodyText == "World."
    check vm.stylesheetHref == "/assets/style.css"

  test "normalizeHtml collapses incidental whitespace between tags but leaves inline text spacing alone":
    check normalizeHtml("<div>  <h1>Title</h1>\n  <p>Body text here</p>  </div>") ==
      "<div><h1>Title</h1><p>Body text here</p></div>"
    check normalizeHtml("<span>a   b</span>") == "<span>a b</span>"
