## Tier 1 (ViewModel / pure-helper) M10 i18n suite -- dual-target: both
## `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free `src/core/i18n_vm.nim` (M10 deliverable 3):
## parsing/building `/xx/` locale route prefixes (recognised only for a
## DECLARED locale), resolving a request path to the locale it targets, the
## UI-string translation table with default-locale fallback for a missing key,
## the language switcher, and the `hreflang` alternates emitted in `<head>`.
## All assertions are pure data, so the exact same checks hold on both targets,
## mirroring `test_versioning_routes.nim`.

import std/unittest
import ../../src/core/i18n_vm

proc sampleCatalog(): LocaleCatalog =
  ## Default = en; de is a prefixed locale with a BCP-47 htmlLang.
  newLocaleCatalog(@[
    newLocaleInfo("en", "English"),
    newLocaleInfo("de", "Deutsch", "de-DE")], defaultId = "en")

proc sampleTable(): TranslationTable =
  ## en fully translated; de translates only ONE of the two keys, so the other
  ## must fall back to en.
  result = newTranslationTable("en")
  result.setTranslations("en", {
    "nav.search": "Search",
    "language_switcher.label": "Language"})
  result.setTranslations("de", {
    "language_switcher.label": "Sprache"}) # nav.search deliberately missing

suite "docs i18n -- /xx/ locale prefix parse + build (Tier 1, dual-target)":
  test "localePrefix mints the /xx/ shape":
    check localePrefix("de") == "/de"

  test "splitLocalePrefix strips a DECLARED locale prefix into (id, basePath)":
    let cat = sampleCatalog()
    check splitLocalePrefix(cat, "/de/guide/x") == ("de", "/guide/x")
    check splitLocalePrefix(cat, "/de") == ("de", "/")
    check splitLocalePrefix(cat, "/en/guide/x") == ("en", "/guide/x")

  test "an unprefixed path has no locale and is returned normalized":
    let cat = sampleCatalog()
    check splitLocalePrefix(cat, "/guide/x") == ("", "/guide/x")
    check splitLocalePrefix(cat, "guide/x/") == ("", "/guide/x")

  test "a first segment that is NOT a declared locale is not a prefix":
    let cat = sampleCatalog()
    # "enterprise" merely starts like "en" but is its own content page.
    check splitLocalePrefix(cat, "/enterprise") == ("", "/enterprise")
    # "fr" is a plausible locale but undeclared -> treated as content.
    check splitLocalePrefix(cat, "/fr/guide/x") == ("", "/fr/guide/x")

  test "withLocalePrefix is the inverse of splitLocalePrefix":
    check withLocalePrefix("de", "/guide/x") == "/de/guide/x"
    check withLocalePrefix("de", "/") == "/de"
    let (id, base) = splitLocalePrefix(sampleCatalog(), "/de/guide/x")
    check withLocalePrefix(id, base) == "/de/guide/x"

suite "docs i18n -- resolving a path to its locale (Tier 1, dual-target)":
  test "an unprefixed path resolves to the default locale":
    let r = resolveLocalePath(sampleCatalog(), "/guide/x")
    check r.localeId == "en"
    check r.basePath == "/guide/x"
    check r.prefixed == false

  test "a declared locale prefix resolves to that locale and strips the prefix":
    let r = resolveLocalePath(sampleCatalog(), "/de/guide/x")
    check r.localeId == "de"
    check r.basePath == "/guide/x"
    check r.prefixed

  test "an undeclared first segment resolves to the default on the whole path":
    let r = resolveLocalePath(sampleCatalog(), "/fr/guide/x")
    check r.localeId == "en"
    check r.basePath == "/fr/guide/x" # left intact for the router to 404
    check r.prefixed == false

  test "localeUrl: default is canonical (unprefixed), others are /xx/-prefixed":
    let cat = sampleCatalog()
    check localeUrl(cat, "en", "/guide/x") == "/guide/x"
    check localeUrl(cat, "de", "/guide/x") == "/de/guide/x"
    check localeUrl(cat, "en", "/") == "/"
    check localeUrl(cat, "de", "/") == "/de"

suite "docs i18n -- UI-string translation table + fallback (Tier 1, dual-target)":
  test "a translated key returns the locale's own string":
    let t = sampleTable()
    check translate(t, "en", "nav.search") == "Search"
    check translate(t, "de", "language_switcher.label") == "Sprache"

  test "a key missing in a non-default locale falls back to the default locale":
    let t = sampleTable()
    # de has no nav.search -> falls back to en's "Search".
    check translate(t, "de", "nav.search") == "Search"

  test "a key missing everywhere falls back to the key itself (never blank)":
    let t = sampleTable()
    check translate(t, "de", "totally.unknown") == "totally.unknown"
    check translate(t, "en", "totally.unknown") == "totally.unknown"

  test "an empty table returns the key for every lookup":
    let t = TranslationTable()
    check translate(t, "de", "nav.search") == "nav.search"
    check hasTranslations(t) == false
    check hasTranslations(sampleTable())

suite "docs i18n -- language switcher (Tier 1, dual-target)":
  test "one option per locale, current flagged, urls per locale":
    let cat = sampleCatalog()
    let sw = buildLanguageSwitcher(cat, resolveLocalePath(cat, "/de/guide/x"))
    check sw.options.len == 2
    check sw.currentId == "de"
    check sw.options[0].id == "en"
    check sw.options[0].url == "/guide/x"       # default -> canonical
    check sw.options[0].current == false
    check sw.options[1].id == "de"
    check sw.options[1].url == "/de/guide/x"     # current locale, prefixed
    check sw.options[1].current
    check sw.options[1].htmlLang == "de-DE"

  test "the label defaults to the id when none was declared, htmlLang to id":
    let cat = newLocaleCatalog(@[newLocaleInfo("en"), newLocaleInfo("de")], "en")
    let sw = buildLanguageSwitcher(cat, resolveLocalePath(cat, "/guide/x"))
    check sw.options[1].label == "de"       # no explicit label
    check sw.options[1].htmlLang == "de"    # no explicit htmlLang -> id
    check sw.currentId == "en"

  test "a translated caption is carried through on the VM":
    let cat = sampleCatalog()
    let sw = buildLanguageSwitcher(cat, resolveLocalePath(cat, "/guide/x"), "Sprache")
    check sw.label == "Sprache"

suite "docs i18n -- hreflang alternates (Tier 1, dual-target)":
  test "one alternate per locale plus an x-default, root-relative by default":
    let cat = sampleCatalog()
    let alts = buildHreflangAlternates(cat, "/guide/x")
    check alts.len == 3
    check alts[0] == ("en", "/guide/x")
    check alts[1] == ("de-DE", "/de/guide/x")
    check alts[2] == ("x-default", "/guide/x") # points at the default locale

  test "alternates are absolute when a baseUrl is configured":
    let cat = sampleCatalog()
    let alts = buildHreflangAlternates(cat, "/guide/x", "https://docs.example.com")
    check alts[0] == ("en", "https://docs.example.com/guide/x")
    check alts[1] == ("de-DE", "https://docs.example.com/de/guide/x")
    check alts[2] == ("x-default", "https://docs.example.com/guide/x")

  test "an empty catalog emits no alternates (i18n off)":
    check buildHreflangAlternates(LocaleCatalog(), "/guide/x").len == 0
