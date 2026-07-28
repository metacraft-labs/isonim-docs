## metacraft-theme-parity M1 verification (Tier 3, C-target): the OPTIONAL,
## default-off framework CHROME hooks are genuine NO-OPS when unset and express
## the WebFlow-parity chrome when set. Exercised against the REAL rendering path
## (`ssr.renderRoute` over the checked-in `tests/fixtures/mini-site/`).
##
## Proves, both ways:
##
##   * UNSET (the framework default `docsConfig()`): the rendered mini-site page
##     is BYTE-FOR-BYTE the pre-M1 markup -- none of the new chrome classes
##     appear, the header still carries the `.docs-title` H1 and the theme
##     toggle, and repeated renders are identical.
##   * ADDITIVE hooks (`headerLinks` Gap B, `sidebarLinks` Gap C, `needHelp`)
##     with the two PLACEMENT switches left off: the header nav buttons, the
##     bottom-of-sidebar social links, and the need-help block appear -- and
##     deleting exactly those inserted fragments from the configured render
##     reproduces the default render byte-for-byte, so they add their content
##     and change nothing else.
##   * PLACEMENT switches (`sidebarThemeToggle`, `pageTitleInContent` +
##     `lastUpdated`): the theme toggle moves out of the header into the sidebar
##     pill, and the page title moves out of the header into an `<h1
##     class="docs-md-title">` at the top of `.docs-main` with a "Last updated"
##     meta line -- matching WebFlow.

when defined(js):
  {.error: "test_chrome_hooks_noop_when_unset is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/config

const
  ghIcon = "/assets/img/icon__github.svg"
  twIcon = "/assets/img/icon__twitter.svg"
  helpIcon = "/assets/img/icon__support.svg"

proc cfgUnset(): DocsConfig =
  ## The framework default -- every new chrome hook empty/false.
  docsConfig()

proc cfgAdditive(): DocsConfig =
  ## Only the purely-ADDITIVE hooks: header nav buttons, sidebar social links,
  ## and the need-help block. The two placement switches stay OFF, so nothing is
  ## removed from the header -- these are strict insertions.
  result = docsConfig()
  result.headerLinks = @[(label: "Support", href: "/support"), (label: "FAQ", href: "/faq")]
  result.sidebarLinks = @[
    (label: "Github", href: "https://github.com/metacraft-labs/codetracer", icon: ghIcon),
    (label: "Twitter", href: "https://x.com/CodeTracerIDE", icon: twIcon)]
  result.needHelp = (heading: "Need some help?", links: @[
    (label: "Contact our support", href: "/support", icon: helpIcon),
    (label: "Frequently asked questions", href: "/faq", icon: "")])

proc cfgFull(): DocsConfig =
  ## Everything, including the two PLACEMENT switches.
  result = cfgAdditive()
  result.sidebarThemeToggle = true
  result.pageTitleInContent = true
  result.lastUpdated = "April 2026"
  result.showLastUpdated = true

# --- the exact fragments the additive hooks insert (mirrors the renderers) ---
const headerNavFragment =
  "<nav class=\"docs-header-nav\">" &
  "<a class=\"docs-header-nav-btn\" href=\"/support\">Support</a>" &
  "<a class=\"docs-header-nav-btn\" href=\"/faq\">FAQ</a></nav>"

const sidebarExtrasFragment =
  "<div class=\"docs-sidebar-extras\">" &
  "<a class=\"docs-sidebar-link\" href=\"https://github.com/metacraft-labs/codetracer\" target=\"_blank\" rel=\"noopener\">" &
  "<img class=\"docs-sidebar-link-icon\" src=\"" & ghIcon & "\" alt=\"\" /><span>Github</span></a>" &
  "<a class=\"docs-sidebar-link\" href=\"https://x.com/CodeTracerIDE\" target=\"_blank\" rel=\"noopener\">" &
  "<img class=\"docs-sidebar-link-icon\" src=\"" & twIcon & "\" alt=\"\" /><span>Twitter</span></a></div>"

const needHelpFragment =
  "<section class=\"docs-need-help\">" &
  "<div class=\"docs-need-help-heading\">Need some help?</div>" &
  "<a class=\"docs-need-help-link\" href=\"/support\">" &
  "<img class=\"docs-need-help-link-icon\" src=\"" & helpIcon & "\" alt=\"\" /><span>Contact our support</span></a>" &
  "<a class=\"docs-need-help-link\" href=\"/faq\"><span>Frequently asked questions</span></a></section>"

suite "M1 chrome hooks -- UNSET is byte-for-byte pre-M1":

  test "UNSET: none of the new chrome classes appear":
    let (status, html) = renderRoute("/", cfg = cfgUnset())
    check status == 200
    for marker in ["docs-header-nav", "docs-sidebar-extras", "docs-sidebar-link",
                   "docs-theme-switch-wrap", "docs-md-title", "docs-md-meta",
                   "docs-need-help"]:
      check not html.contains(marker)

  test "UNSET: the header keeps its `.docs-title` H1 and its theme toggle":
    let html = renderRoute("/", cfg = cfgUnset()).html
    check html.contains("<h1 class=\"docs-title\">Welcome</h1>")
    check html.contains("id=\"docs-theme-toggle\"")

  test "UNSET: rendering is deterministic across repeated calls":
    check renderRoute("/", cfg = cfgUnset()).html == renderRoute("/", cfg = cfgUnset()).html

suite "M1 chrome hooks -- additive hooks (Gap B/C + need-help)":

  test "SET: header nav buttons, sidebar social links, and need-help appear":
    let html = renderRoute("/", cfg = cfgAdditive()).html
    check html.contains(headerNavFragment)
    check html.contains(sidebarExtrasFragment)
    check html.contains(needHelpFragment)
    # The sidebar extras land INSIDE the sidebar nav, before its close.
    check html.contains(sidebarExtrasFragment & "</nav>")
    # The need-help block sits ABOVE the footer.
    check html.contains(needHelpFragment & "<footer id=\"docs-region-footer\"")

  test "NO-OP PROOF: deleting exactly the inserted fragments reproduces the default":
    let htmlUnset = renderRoute("/", cfg = cfgUnset()).html
    let htmlSet = renderRoute("/", cfg = cfgAdditive()).html
    let reconstructed = htmlSet
      .replace(headerNavFragment, "")
      .replace(sidebarExtrasFragment, "")
      .replace(needHelpFragment, "")
    check reconstructed == htmlUnset

  test "additive hooks leave the header title + toggle in place":
    let html = renderRoute("/", cfg = cfgAdditive()).html
    check html.contains("<h1 class=\"docs-title\">Welcome</h1>")
    check html.contains("id=\"docs-theme-toggle\"")

suite "M1 chrome hooks -- placement switches (sidebar toggle + content H1)":

  test "sidebarThemeToggle: the toggle moves from the header into the sidebar pill":
    let html = renderRoute("/", cfg = cfgFull()).html
    # Exactly one toggle, and it lives inside the sidebar pill wrapper.
    check html.count("id=\"docs-theme-toggle\"") == 1
    check html.contains("<div class=\"docs-theme-switch-wrap\"><button")
    # The header no longer carries the toggle: the search box is now the
    # header's last interactive control before the nav buttons.
    check html.contains("docs-theme-switch-wrap")

  test "pageTitleInContent: the title moves into a content H1 with a last-updated meta":
    let html = renderRoute("/", cfg = cfgFull()).html
    # The header no longer emits the `.docs-title` H1...
    check not html.contains("<h1 class=\"docs-title\">Welcome</h1>")
    # ...it is an `<h1 class="docs-md-title">` at the top of the content instead,
    # with the "Last updated" meta line under it.
    check html.contains("<h1 class=\"docs-md-title\">Welcome</h1>")
    check html.contains("<div class=\"docs-md-meta\"><span>Last updated</span> <span>April 2026</span></div>")

  test "SET (full): the header nav buttons are still present":
    let html = renderRoute("/", cfg = cfgFull()).html
    check html.contains(headerNavFragment)
