## isonim-docs Layer 3 — the internationalization (i18n) ViewModel (M10
## deliverable 3). Pure data + pure resolution logic, zero platform/CSS/DOM
## imports, so it is headless-testable on both `nim c` and `nim js` exactly
## like `version_vm.nim`/`tutorial_vm.nim`/`theme_vm.nim`.
##
## An internationalized docs site serves the SAME content graph under several
## UI locales. The DEFAULT locale is the canonical, unprefixed site
## (`/guide/x`); every other locale lives behind a `/xx/` route prefix
## (`/de/guide/x`), so the router strips the prefix, matches the shared
## manifest, and the shell renders its chrome in the resolved locale's
## language. This module owns exactly four content-agnostic pieces of that,
## deliberately mirroring `version_vm`'s shape one-for-one:
##   * PARSING a `/xx/`-prefixed path into `(localeId, basePath)` and back
##     (`splitLocalePrefix`/`withLocalePrefix`). Unlike a version prefix (a
##     digit-guarded `/vX.Y/`), a locale prefix is recognised ONLY when the
##     first path segment is a DECLARED catalog locale -- so a real content
##     page literally named `/enterprise` is never mistaken for a locale;
##   * RESOLVING a request path to the locale it targets (`resolveLocalePath`)
##     -- an unprefixed path is the default locale, a declared prefix is that
##     locale;
##   * the UI-STRING TRANSLATION TABLE (`TranslationTable` / `translate`): a
##     per-locale `key -> string` map with default-locale fallback for any
##     key a non-default locale doesn't translate, and the key itself as the
##     last-resort fallback -- so a half-translated locale never renders a
##     blank label, and a brand-new key is visible (as its key) rather than
##     silently empty;
##   * the derived UI/head state: the LANGUAGE SWITCHER
##     (`buildLanguageSwitcher`, one option per locale linking to the same page
##     in that locale) and the `hreflang` ALTERNATES
##     (`buildHreflangAlternates`, one `<link rel=alternate hreflang=..>` per
##     locale plus an `x-default` pointing at the default locale) the `<head>`
##     emits so search engines can serve the right language.
##
## Like `version_vm`, the VM never touches a filesystem or a manifest of its
## own -- it is fed an already-assembled `LocaleCatalog` + `TranslationTable`
## (from consumer config) and hands the caller a `basePath` to match against
## the shared `RouteManifest`. The zero-value `LocaleCatalog()` means "i18n
## disabled": an un-internationalized site keeps its exact pre-M10 shape.

import std/tables
import ./routes
import ./config

type
  LocaleInfo* = object
    id*: string       ## Locale id as it appears in the route prefix: the "de"
                      ## in `/de/...` (prefix is `localePrefix(id)` == "/de").
                      ## Free-form; the framework never parses it beyond an
                      ## exact match against the catalog, so "en", "de",
                      ## "pt-br" all work.
    label*: string    ## Display label shown in the language switcher, e.g.
                      ## "Deutsch". Falls back to `id` when empty.
    htmlLang*: string ## BCP-47 language tag emitted as this locale's
                      ## `hreflang` alternate and (by the shell) the document
                      ## `<html lang>` attribute, e.g. "de-DE". Falls back to
                      ## `id` when empty.

  LocaleCatalog* = object
    ## The consumer-declared set of UI locales. `locales` is in display order;
    ## `defaultId` names the one served canonically/unprefixed and used as the
    ## translation fallback. The zero-value `LocaleCatalog()` means "i18n
    ## disabled" -- the whole feature is opt-in, so a single-locale site keeps
    ## its exact pre-M10 shape.
    locales*: seq[LocaleInfo]
    defaultId*: string

  LocaleResolution* = object
    ## The outcome of resolving a request path against a catalog.
    localeId*: string ## The locale the path targets: the parsed prefix, or
                      ## `catalog.defaultId` when the path is unprefixed.
    basePath*: string ## The path with any `/xx/` prefix stripped -- what the
                      ## caller matches against the shared `RouteManifest`.
    prefixed*: bool   ## Whether the incoming path actually carried a declared
                      ## locale prefix (false => the canonical default site).

  TranslationTable* = object
    ## The UI-string translation table: `strings[localeId][key] = value`.
    ## `defaultLocaleId` is the fallback locale `translate` consults when a
    ## non-default locale is missing a key. The zero-value carries no strings,
    ## so `translate` always returns the key itself (a safe, visible default).
    defaultLocaleId*: string
    strings*: Table[string, Table[string, string]]

  LanguageOption* = object
    id*: string
    label*: string
    htmlLang*: string
    url*: string     ## Route to the current page in this locale.
    current*: bool   ## Whether this is the locale currently being viewed.

  LanguageSwitcherViewModel* = object
    options*: seq[LanguageOption]
    currentId*: string
    label*: string   ## The switcher's own (translatable) label; empty => the
                     ## renderer's built-in default.

  HreflangAlternate* = tuple[hreflang, href: string]
    ## One `<link rel="alternate" hreflang=.. href=..>`. A plain tuple (not a
    ## named object) so `shell_vm.DocumentHead` can carry a `seq` of these
    ## without importing this module -- the head builder stays generic/SEO,
    ## this module stays i18n.

const
  i18nKeyLanguageSwitcherLabel* = "language_switcher.label"
    ## The well-known translation key the shell looks up for the language
    ## switcher's label, so a consumer can localise it via the table.

# --- Locale id <-> route prefix ----------------------------------------

proc localePrefix*(id: string): string =
  ## The route-path prefix a locale's pages live behind: "de" -> "/de". The one
  ## place the `/xx/` shape is minted, so parsing and building never disagree.
  "/" & id

proc isKnownLocale*(catalog: LocaleCatalog; id: string): bool =
  ## Whether `id` is one of the catalog's declared locales.
  for l in catalog.locales:
    if l.id == id: return true
  false

proc isDefaultLocale*(catalog: LocaleCatalog; id: string): bool =
  ## Whether `id` is the catalog's canonical default locale.
  id == catalog.defaultId

proc localeLabel*(l: LocaleInfo): string =
  ## The switcher-visible label, defaulting to `id` when none was given.
  if l.label.len > 0: l.label else: l.id

proc localeHtmlLang*(l: LocaleInfo): string =
  ## The BCP-47 tag for `hreflang`/`<html lang>`, defaulting to `id`.
  if l.htmlLang.len > 0: l.htmlLang else: l.id

proc localeInfo*(catalog: LocaleCatalog; id: string): LocaleInfo =
  ## The declared `LocaleInfo` for `id`, or a bare `LocaleInfo(id: id)` when
  ## the catalog doesn't declare it (so callers always get usable defaults).
  for l in catalog.locales:
    if l.id == id: return l
  LocaleInfo(id: id)

proc splitLocalePrefix*(catalog: LocaleCatalog; path: string): tuple[localeId, basePath: string] =
  ## Splits a request path into `(localeId, basePath)`: with `de` a declared
  ## locale, "/de/guide/x" -> ("de", "/guide/x") and "/de" -> ("de", "/"); an
  ## unprefixed or unknown-first-segment path -> ("", normalizedPath). A prefix
  ## is recognised ONLY when the first segment is a DECLARED catalog locale, so
  ## a content page named "/enterprise" is never mistaken for a locale. Both
  ## halves come back normalized (`routes.normalizeRoutePath`).
  let p = normalizeRoutePath(path)
  if p.len >= 2 and p[0] == '/':
    var i = 1
    while i < p.len and p[i] != '/': inc i
    let seg = p[1 ..< i]
    if isKnownLocale(catalog, seg):
      let rest = if i < p.len: p[i .. ^1] else: "/"
      return (seg, normalizeRoutePath(rest))
  ("", p)

proc withLocalePrefix*(localeId, basePath: string): string =
  ## Re-attaches a locale prefix to a base path: ("de", "/guide/x") ->
  ## "/de/guide/x"; ("de", "/") -> "/de". The inverse of `splitLocalePrefix`
  ## for a known locale, so a round trip through both is the identity.
  let b = normalizeRoutePath(basePath)
  if b == "/": localePrefix(localeId)
  else: localePrefix(localeId) & b

# --- Resolution --------------------------------------------------------

proc resolveLocalePath*(catalog: LocaleCatalog; path: string): LocaleResolution =
  ## Resolves `path` against `catalog`. An unprefixed path is the default
  ## locale (`localeId = defaultId`, `prefixed = false`); a declared prefix
  ## names its own locale. Never raises; an unknown-first-segment path simply
  ## resolves as the default locale on the whole (normalized) path, which the
  ## router then matches (and typically 404s) like any other unmatched route.
  let (rawId, base) = splitLocalePrefix(catalog, path)
  let prefixed = rawId.len > 0
  let id = if prefixed: rawId else: catalog.defaultId
  LocaleResolution(localeId: id, basePath: base, prefixed: prefixed)

proc localeUrl*(catalog: LocaleCatalog; localeId, basePath: string): string =
  ## The route to `basePath` in `localeId`: the canonical, unprefixed path for
  ## the default locale, a `/xx/`-prefixed path for any other. The one rule the
  ## switcher, hreflang alternates, and any deep link switching locale go
  ## through.
  if isDefaultLocale(catalog, localeId): normalizeRoutePath(basePath)
  else: withLocalePrefix(localeId, basePath)

# --- UI-string translation table ---------------------------------------

proc newTranslationTable*(defaultLocaleId: string): TranslationTable =
  ## An empty translation table whose fallback locale is `defaultLocaleId`
  ## (normally the catalog's `defaultId`).
  TranslationTable(defaultLocaleId: defaultLocaleId,
                   strings: initTable[string, Table[string, string]]())

proc setTranslations*(table: var TranslationTable; localeId: string;
                      pairs: openArray[(string, string)]) =
  ## Registers (or extends) `localeId`'s `key -> value` UI strings. Repeated
  ## calls for the same locale merge; a repeated key overwrites.
  if not table.strings.hasKey(localeId):
    table.strings[localeId] = initTable[string, string]()
  for (k, v) in pairs:
    table.strings[localeId][k] = v

proc hasTranslations*(table: TranslationTable): bool =
  ## Whether any strings are registered (i18n string-table active).
  table.strings.len > 0

proc translate*(table: TranslationTable; localeId, key: string): string =
  ## Looks up `key` for `localeId` with default-locale fallback: the locale's
  ## own value if present, else the `defaultLocaleId`'s value, else the `key`
  ## itself (never a blank string). This is the deliverable's "missing
  ## translation falls back to the default locale" contract.
  if table.strings.hasKey(localeId) and table.strings[localeId].hasKey(key):
    return table.strings[localeId][key]
  if table.defaultLocaleId.len > 0 and table.defaultLocaleId != localeId and
     table.strings.hasKey(table.defaultLocaleId) and
     table.strings[table.defaultLocaleId].hasKey(key):
    return table.strings[table.defaultLocaleId][key]
  key

# --- Derived UI: switcher + hreflang -----------------------------------

proc buildLanguageSwitcher*(catalog: LocaleCatalog; res: LocaleResolution;
                            label: string = ""): LanguageSwitcherViewModel =
  ## One switcher option per catalog locale, each linking to the CURRENT page
  ## (`res.basePath`) in that locale, with the viewed locale marked `current`.
  ## Empty when the catalog declares no locales (feature disabled). `label` is
  ## the switcher's own (already-translated) caption; empty leaves the renderer
  ## to use its built-in default.
  var opts: seq[LanguageOption] = @[]
  for l in catalog.locales:
    opts.add LanguageOption(id: l.id, label: localeLabel(l),
      htmlLang: localeHtmlLang(l),
      url: localeUrl(catalog, l.id, res.basePath),
      current: l.id == res.localeId)
  LanguageSwitcherViewModel(options: opts, currentId: res.localeId, label: label)

proc buildHreflangAlternates*(catalog: LocaleCatalog; basePath: string;
                              baseUrl: string = ""): seq[HreflangAlternate] =
  ## One `hreflang` alternate per catalog locale (its BCP-47 tag -> its URL for
  ## this page), plus a final `x-default` alternate pointing at the default
  ## locale -- the standard Google multi-locale signalling. Hrefs are absolute
  ## when `baseUrl` is set (via `config.joinSiteUrl`), root-relative otherwise,
  ## exactly like the canonical URL. Empty when the catalog declares no
  ## locales, so an un-internationalized page's `<head>` is unchanged.
  result = @[]
  if catalog.locales.len == 0: return
  for l in catalog.locales:
    result.add (localeHtmlLang(l),
                joinSiteUrl(baseUrl, localeUrl(catalog, l.id, basePath)))
  if catalog.defaultId.len > 0:
    result.add ("x-default",
                joinSiteUrl(baseUrl, localeUrl(catalog, catalog.defaultId, basePath)))

# --- Builders ----------------------------------------------------------

proc newLocaleInfo*(id: string; label: string = ""; htmlLang: string = ""): LocaleInfo =
  LocaleInfo(id: id, label: label, htmlLang: htmlLang)

proc newLocaleCatalog*(locales: seq[LocaleInfo]; defaultId: string): LocaleCatalog =
  ## Assembles a catalog and names its default (canonical, unprefixed) locale.
  ## `defaultId` should be one of `locales`' ids.
  LocaleCatalog(locales: locales, defaultId: defaultId)
