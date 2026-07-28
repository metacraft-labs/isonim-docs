## Tier 2 (MockRenderer + SSR string) M2 theme toggle rendering suite --
## dual-target: both `nim c -r` and `nim js -r` must pass.
##
## Proves `src/components/theme_toggle.nim` renders the theme
## ViewModel from `src/core/theme_vm.nim` (M2 deliverable 2) identically
## on the MockRenderer/browser tree side and the SSR string side: the
## toggle button carries a `data-theme` attribute reflecting the current
## theme, an `aria-pressed` state, and an `aria-label` describing the
## theme a click switches *to* -- all as a pure function of a given
## `ThemeViewModel`. Also proves the SSR-only no-flash bootstrap script
## (`renderThemeBootstrapHtml`) emits real, executable JS that reads
## `localStorage` before falling back to `prefers-color-scheme`, keyed
## on the exact same `themeStorageKey`/`themeAttrName` constants the
## Tier 1 suite (`test_theme_vm.nim`) and the JS mount's click wiring
## (`src/main_web.nim`) both use.
##
## Also carries M2 deliverable 4's a11y suites: the skip-to-content
## link (`shell.renderSkipLink`/`renderSkipLinkHtml`) is the site
## frame's/markdown page frame's real first child on both the
## MockRenderer tree side and the SSR string side, targets
## `#docs-region-main`, and the existing header/nav/main/footer landmark
## roles (and `main`'s new `tabindex="-1"`, so the skip link has
## somewhere focusable to land) survive its addition unchanged.

import std/[unittest, strutils]
import isonim/testing/mock_dom
import ../../src/core/theme_vm
import ../../src/core/shell_vm
import ../../src/core/markdown_vm
import ../../src/components/theme_toggle
import ../../src/components/shell
import ../../src/components/markdown_page
import ./helpers/mock_tree

suite "docs theme toggle rendering -- MockRenderer (Tier 2, dual-target)":
  test "renderThemeToggle: a light-theme ViewModel renders a button carrying data-theme=light":
    let r = MockRenderer()
    let root = renderThemeToggle[MockRenderer, MockNode](r, ThemeViewModel(theme: thLight))
    check getAttribute(r, root, "id") == themeToggleId
    check getAttribute(r, root, "class") == themeToggleClass
    check getAttribute(r, root, "data-theme") == "light"
    check getAttribute(r, root, "aria-pressed") == "false"
    check getAttribute(r, root, "aria-label") == "Switch to dark theme"

  test "renderThemeToggle: a dark-theme ViewModel renders a button carrying data-theme=dark":
    let r = MockRenderer()
    let root = renderThemeToggle[MockRenderer, MockNode](r, ThemeViewModel(theme: thDark))
    check getAttribute(r, root, "data-theme") == "dark"
    check getAttribute(r, root, "aria-pressed") == "true"
    check getAttribute(r, root, "aria-label") == "Switch to light theme"

  test "renderThemeToggle: is a real <button type=button>, not a bare clickable div":
    let r = MockRenderer()
    let root = renderThemeToggle[MockRenderer, MockNode](r, ThemeViewModel())
    check getAttribute(r, root, "type") == "button"

suite "docs theme toggle rendering -- SSR string (Tier 2, dual-target)":
  test "renderThemeToggleHtml: mirrors the MockRenderer attributes for a light theme":
    let html = renderThemeToggleHtml(ThemeViewModel(theme: thLight))
    check html.startsWith("<button type=\"button\" id=\"" & themeToggleId & "\"")
    check html.contains("class=\"" & themeToggleClass & "\"")
    check html.contains("data-theme=\"light\"")
    check html.contains("aria-pressed=\"false\"")
    check html.contains("aria-label=\"Switch to dark theme\"")
    check html.endsWith("</button>")

  test "renderThemeToggleHtml: mirrors the MockRenderer attributes for a dark theme":
    let html = renderThemeToggleHtml(ThemeViewModel(theme: thDark))
    check html.contains("data-theme=\"dark\"")
    check html.contains("aria-pressed=\"true\"")
    check html.contains("aria-label=\"Switch to light theme\"")

  test "renderThemeBootstrapHtml: emits a stable-id inline script, not a JSON data island":
    let html = renderThemeBootstrapHtml()
    check html.startsWith("<script id=\"" & themeBootstrapScriptId & "\">")
    check html.endsWith("</script>")
    check not html.contains("type=\"application/json\"")

  test "renderThemeBootstrapHtml: reads the real storage key before falling back to prefers-color-scheme":
    let html = renderThemeBootstrapHtml()
    check html.contains("localStorage.getItem(k)")
    check html.contains("'" & themeStorageKey & "'")
    check html.contains("matchMedia")
    check html.contains("prefers-color-scheme: dark")

  test "renderThemeBootstrapHtml: sets the real data-theme attribute on document.documentElement":
    let html = renderThemeBootstrapHtml()
    check html.contains("document.documentElement.setAttribute(a,t)")
    check html.contains("'" & themeAttrName & "'")

  test "renderThemeBootstrapHtml: is wrapped in try/catch so a locked-down environment can't fail the page":
    let html = renderThemeBootstrapHtml()
    check html.contains("try{")
    check html.contains("}catch(e){}")

suite "docs a11y: skip-to-content link + focus/landmark roles (Tier 2, dual-target) -- M2 deliverable 4":
  test "renderSiteFrame: the frame's real first child is a skip link targeting the main region":
    let r = MockRenderer()
    let root = renderSiteFrame[MockRenderer, MockNode](r, SiteShellViewModel(pageTitle: "Home"))
    let skipLink = root.children[0]
    check skipLink.kind == mnkElement
    check skipLink.tag == "a"
    check getAttribute(r, skipLink, "class") == skipLinkClass
    check getAttribute(r, skipLink, "href") == "#" & regionId(prMain)

  test "renderSiteFrame: header/nav/main/footer landmark roles survive the skip link's addition":
    let r = MockRenderer()
    let root = renderSiteFrame[MockRenderer, MockNode](r, SiteShellViewModel(pageTitle: "Home"))
    let header = findByTag(root, "header")
    require header != nil
    check getAttribute(r, header, "id") == regionId(prHeader)
    let nav = findByTag(root, "nav")
    require nav != nil
    check getAttribute(r, nav, "id") == regionId(prNav)
    let main = findByTag(root, "main")
    require main != nil
    check getAttribute(r, main, "id") == regionId(prMain)
    check getAttribute(r, main, "tabindex") == "-1"
    let footer = findByTag(root, "footer")
    require footer != nil
    check getAttribute(r, footer, "id") == regionId(prFooter)

  test "renderMarkdownPage: the frame's real first child is a skip link targeting the main region":
    let r = MockRenderer()
    let root = renderMarkdownPage[MockRenderer, MockNode](r, "Guide", @[])
    let skipLink = root.children[0]
    check skipLink.tag == "a"
    check getAttribute(r, skipLink, "class") == skipLinkClass
    check getAttribute(r, skipLink, "href") == "#" & regionId(prMain)
    let main = findByTag(root, "main")
    require main != nil
    check getAttribute(r, main, "tabindex") == "-1"

suite "docs a11y: skip-to-content link -- SSR string (Tier 2, dual-target) -- M2 deliverable 4":
  test "renderSkipLinkHtml: a real <a> targeting the main region, carrying the styling hook class":
    let html = renderSkipLinkHtml()
    check html == "<a class=\"" & skipLinkClass & "\" href=\"#" & regionId(prMain) & "\">" & skipLinkText & "</a>"

  test "renderSiteFrameHtml: the skip link is emitted before the header, and main carries tabindex=-1":
    let html = renderSiteFrameHtml(SiteShellViewModel(pageTitle: "Home"))
    check html.contains(renderSkipLinkHtml())
    check html.find(renderSkipLinkHtml()) < html.find("<header")
    check html.contains("<main id=\"" & regionId(prMain) & "\" class=\"" & mainClass & "\" tabindex=\"-1\">")

  test "renderMarkdownPageHtml: the skip link is emitted before the header, and main carries tabindex=-1":
    let html = renderMarkdownPageHtml("Guide", @[])
    check html.contains(renderSkipLinkHtml())
    check html.find(renderSkipLinkHtml()) < html.find("<header")
    check html.contains("<main id=\"" & regionId(prMain) & "\" class=\"" & mainClass & "\" tabindex=\"-1\">")
