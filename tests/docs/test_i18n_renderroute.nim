## Tier 3 (SSR `renderRoute`) M10 i18n integration -- C-target only
## (`ssr.nim` is a server-side entry, like every other `*_renderroute.nim`).
##
## Proves the i18n ViewModel (`core/i18n_vm`) is actually WIRED into
## `ssr.renderRoute` (M10 deliverable 3): passing a `LocaleCatalog` +
## `TranslationTable` makes a `/de/`-prefixed request resolve to that locale
## (serving the SHARED content), renders the language switcher + a translated
## caption, emits `hreflang` alternates in `<head>` and a `<html lang>` attr,
## while an unprefixed page is the default locale and a site with NO catalog is
## byte-for-byte the pre-M10 (un-internationalized) shape.

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/i18n_vm
import ../../src/components/language_switcher

const siteDir = "tests/fixtures/mini-site"

proc catalog(): LocaleCatalog =
  newLocaleCatalog(@[
    newLocaleInfo("en", "English"),
    newLocaleInfo("de", "Deutsch", "de-DE")], defaultId = "en")

proc table(): TranslationTable =
  result = newTranslationTable("en")
  result.setTranslations("en", {"language_switcher.label": "Language"})
  result.setTranslations("de", {"language_switcher.label": "Sprache"})

suite "docs i18n -- renderRoute wiring (Tier 3, C-target)":
  test "the default (unprefixed) page emits the switcher, hreflang, and lang=en":
    let (status, html) = renderRoute("/guide/alpha", siteDir,
                                     locales = catalog(), translations = table())
    check status == 200
    check languageSwitcherClass in html
    check "<html lang=\"en\">" in html
    # hreflang alternates for both locales + x-default, in <head>.
    check "hreflang=\"en\"" in html
    check "<link rel=\"alternate\" hreflang=\"de-DE\" href=\"/de/guide/alpha\" />" in html
    check "hreflang=\"x-default\"" in html
    # en has no override for the label key beyond "Language" -> default caption.
    check "aria-label=\"Language\"" in html

  test "a /de/ page resolves to that locale: shared content, lang=de, translated caption":
    let (status, html) = renderRoute("/de/guide/alpha", siteDir,
                                     locales = catalog(), translations = table())
    check status == 200
    check "<html lang=\"de-DE\">" in html
    check "aria-label=\"Sprache\"" in html          # translated switcher caption
    check "aria-current=\"true\"" in html            # the current (de) option
    # the switcher's en option links back to the canonical unprefixed page.
    check "href=\"/guide/alpha\"" in html
    # hreflang alternates are still emitted on the localized page.
    check "hreflang=\"de-DE\"" in html

  test "an undeclared locale-looking prefix 404s (it is not a declared locale)":
    let (status, html) = renderRoute("/fr/guide/alpha", siteDir,
                                     locales = catalog(), translations = table())
    check status == 404
    check "Page not found" in html

  test "with no catalog the site is un-internationalized (pre-M10 behaviour)":
    let (status, html) = renderRoute("/guide/alpha", siteDir)
    check status == 200
    check languageSwitcherClass notin html # no i18n chrome at all
    check "hreflang" notin html
    check "<html>" in html                  # bare <html>, no lang attr
