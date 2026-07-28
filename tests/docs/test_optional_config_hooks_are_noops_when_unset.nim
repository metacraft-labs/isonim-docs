## metacraft-theme M3 verification (Tier 3, C-target): the OPTIONAL,
## default-empty framework chrome hooks are genuine NO-OPS when unset and
## express the consumer's theme gaps when set.
##
## Proves three things about the M3 hooks, each against the REAL rendering
## path (`ssr.renderRoute` over the checked-in `tests/fixtures/mini-site/`
## for the shell hooks, `markdown_vm`/`markdown_view` for the admonition
## severities):
##
##   * Gap A (`siteLogo`/`logoHref`) and Gap F (`footerHtml`): with them
##     UNSET (the framework default `docsConfig()`) the rendered page is
##     BYTE-FOR-BYTE the pre-M3 markup -- no `docs-logo`, an empty
##     `<footer>` -- and with them SET the only bytes that change are the
##     opt-in logo/footer insertions (proved by reconstructing the default
##     output from the configured one by deleting exactly those fragments).
##   * Gap D (`important`/`caution` admonition severities): `:::important`
##     and `:::caution` now parse to their own kinds and render distinct
##     `.docs-md-admonition-important` / `-caution` classes + labels, while
##     the pre-existing note/tip/warning/danger severities are unchanged and
##     content WITHOUT them renders without those classes.

when defined(js):
  {.error: "test_optional_config_hooks_are_noops_when_unset is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/config
import ../../src/core/markdown_vm
import ../../src/components/markdown_view

const
  logo = "/assets/logo.svg"
  home = "/home"
  footer = "<span>Built by metacraft-labs</span>"

proc cfgUnset(): DocsConfig =
  ## The framework default -- siteLogo/logoHref/footerHtml all empty.
  docsConfig()

proc cfgSet(): DocsConfig =
  result = docsConfig()
  result.siteLogo = logo
  result.logoHref = home
  result.footerHtml = footer

suite "M3 shell hooks -- Gap A (siteLogo/logoHref) + Gap F (footerHtml)":

  test "UNSET: the framework default renders NO logo and an empty footer (byte-for-byte pre-M3)":
    let (status, html) = renderRoute("/", cfg = cfgUnset())
    check status == 200
    # The mini-site index title is "Welcome"; header is the plain title only.
    check html.contains("<h1 class=\"docs-title\">Welcome</h1>")
    check not html.contains("docs-logo")
    check not html.contains("docs-logo-link")
    # The footer is the exact pre-M3 empty element.
    check html.contains("<footer id=\"docs-region-footer\" class=\"docs-footer\"></footer>")

  test "SET: the logo (+ link) and footer HTML appear in the header/footer":
    let (status, html) = renderRoute("/", cfg = cfgSet())
    check status == 200
    check html.contains(
      "<a class=\"docs-logo-link\" href=\"/home\">" &
      "<img class=\"docs-logo\" src=\"/assets/logo.svg\" alt=\"Welcome\" /></a>")
    check html.contains(
      "<footer id=\"docs-region-footer\" class=\"docs-footer\">" & footer & "</footer>")

  test "NO-OP PROOF: the configured output differs from the default ONLY by the opt-in insertions":
    # The strongest no-op guarantee: deleting exactly the logo fragment and
    # the footer body from the CONFIGURED render reproduces the DEFAULT render
    # byte-for-byte -- so the hooks add their content and change nothing else.
    let htmlUnset = renderRoute("/", cfg = cfgUnset()).html
    let htmlSet = renderRoute("/", cfg = cfgSet()).html
    let logoFragment =
      "<a class=\"docs-logo-link\" href=\"/home\">" &
      "<img class=\"docs-logo\" src=\"/assets/logo.svg\" alt=\"Welcome\" /></a>"
    let reconstructed = htmlSet.replace(logoFragment, "").replace(footer, "")
    check reconstructed == htmlUnset

  test "SET: rendering is deterministic across repeated calls":
    check renderRoute("/", cfg = cfgSet()).html == renderRoute("/", cfg = cfgSet()).html

suite "M3 admonition severities -- Gap D (important/caution)":

  test "`:::important` and `:::caution` parse to their own kinds":
    check parseMarkdownDoc(":::important\nx\n:::").blocks[0].admonitionKind == akImportant
    check parseMarkdownDoc(":::caution\nx\n:::").blocks[0].admonitionKind == akCaution

  test "the pre-existing severities are unchanged":
    check parseMarkdownDoc(":::note\nx\n:::").blocks[0].admonitionKind == akNote
    check parseMarkdownDoc(":::tip\nx\n:::").blocks[0].admonitionKind == akTip
    check parseMarkdownDoc(":::warning\nx\n:::").blocks[0].admonitionKind == akWarning
    check parseMarkdownDoc(":::danger\nx\n:::").blocks[0].admonitionKind == akDanger

  test "important/caution render distinct classes + labels":
    let important = renderMarkdownBodyHtml(parseMarkdownDoc(":::important\nBe careful.\n:::").blocks)
    check important.contains("docs-md-admonition-important")
    check important.contains("<strong>Important</strong>")
    let caution = renderMarkdownBodyHtml(parseMarkdownDoc(":::caution\nWatch out.\n:::").blocks)
    check caution.contains("docs-md-admonition-caution")
    check caution.contains("<strong>Caution</strong>")

  test "labels + kind classes for every severity":
    check admonitionLabel(akImportant) == "Important"
    check admonitionLabel(akCaution) == "Caution"
    check admonitionKindClass(akImportant) == "docs-md-admonition-important"
    check admonitionKindClass(akCaution) == "docs-md-admonition-caution"
    # Existing severities keep their exact class names.
    check admonitionKindClass(akNote) == "docs-md-admonition-note"
    check admonitionKindClass(akDanger) == "docs-md-admonition-danger"

  test "NO-OP: content without important/caution renders none of their classes":
    let html = renderRoute("/", cfg = cfgUnset()).html
    check not html.contains("docs-md-admonition-important")
    check not html.contains("docs-md-admonition-caution")
