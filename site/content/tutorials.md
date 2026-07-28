---
title: Tutorials, Versioning & i18n
description: The interactive tutorial layout with step progress and completion tracking, documentation versioning with /vX.Y/ route prefixes, and i18n with locale prefixes, a translation table, and hreflang alternates.
order: 10
---
# Tutorials, Versioning & i18n

Three orthogonal, opt-in features let a docs site grow from a single set of
reference pages into a guided, multi-version, multi-language product. Each is
a pure ViewModel fed already-assembled data from consumer config, so all
three are headless-testable on both backends.

## Interactive tutorials

A tutorial (`pkTutorial`) is an ordered list of steps -- typically the page's
`##` headings -- rendered with a progress rail. `core/tutorial_vm` tracks
per-step completion, persists it to `localStorage` on the browser (through an
injected storage seam, so SSR and tests use a fake store), and derives the
progress percentage the layout's progress bar renders. Reset clears both the
in-memory checkmarks and the stored keys, and prev/next links connect the
sibling tutorials of a series.

```nim runnable
import core/tutorial_vm

var vm = newTutorialViewModel("intro", "Getting Started Tutorial", @[
  newTutorialStep("install", "Install the toolchain"),
  newTutorialStep("build", "Build the site"),
])
doAssert vm.totalSteps == 2
doAssert vm.progressPercent == 0

vm = vm.toggleStep(0)
doAssert vm.completedCount == 1
doAssert vm.progressPercent == 50

vm = vm.toggleStep(1)
doAssert vm.isComplete
doAssert vm.progressPercent == 100

vm = vm.resetCompletion()
doAssert vm.completedCount == 0
```

## Versioning

A versioned site serves N snapshots side by side. The **latest** version is
the canonical, unprefixed site (`/guide/x`); every older version lives behind
a `/vX.Y/` route prefix (`/v1.2/guide/x`) with its own isolated content tree
and search index. `core/version_vm` parses and builds the prefix, resolves a
request path to the version it targets, derives the isolated content/search
paths, and produces the "outdated version" banner shown only on a known,
non-latest version:

```nim runnable
import core/version_vm

let catalog = newVersionCatalog(@[
  newVersionInfo("2.0", "v2.0 (latest)"),
  newVersionInfo("1.2", "v1.2"),
], latestId = "2.0")

# The latest is served unprefixed and is never "outdated".
let latest = resolveVersionedPath(catalog, "/guide/intro")
doAssert latest.versionId == "2.0"
doAssert not latest.outdated

# An older version is served behind its /vX.Y/ prefix, flagged outdated.
let older = resolveVersionedPath(catalog, "/v1.2/guide/intro")
doAssert older.versionId == "1.2"
doAssert older.basePath == "/guide/intro"
doAssert older.outdated
doAssert buildVersionBanner(catalog, older).show
```

## Internationalization

An i18n site serves the same content graph under several UI locales. The
**default** locale is the canonical, unprefixed site; every other locale
lives behind a `/xx/` prefix (`/de/guide/x`). `core/i18n_vm` parses the
locale prefix (recognized only when the first segment is a *declared* locale,
so a page named `/enterprise` is never mistaken for a locale), holds the
UI-string translation table with default-locale fallback, builds the language
switcher, and emits the `hreflang` alternates the head needs:

```nim runnable
import core/i18n_vm

let catalog = newLocaleCatalog(@[
  newLocaleInfo("en", "English", "en"),
  newLocaleInfo("de", "Deutsch", "de-DE"),
], defaultId = "en")

let res = resolveLocalePath(catalog, "/de/guide/intro")
doAssert res.localeId == "de"
doAssert res.basePath == "/guide/intro"

var strings = newTranslationTable("en")
strings.setTranslations("en", {"nav.home": "Home"})
strings.setTranslations("de", {"nav.home": "Startseite"})
doAssert strings.translate("de", "nav.home") == "Startseite"
# A key a locale doesn't translate falls back to the default locale.
doAssert strings.translate("de", "nav.only-en") == strings.translate("en", "nav.only-en")

# One hreflang alternate per locale, plus a final x-default.
let alternates = buildHreflangAlternates(catalog, "/guide/intro")
doAssert alternates.len == 3
```
