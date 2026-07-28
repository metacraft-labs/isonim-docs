## isonim-docs Layer 4 shell — SSR/SSG entry.
##
## M1 replaces M0's single hardcoded "/" dispatch with the real,
## manifest-driven route contract (`src/core/routes.docsRouteManifest`):
## every real route resolves through `matchRoute` against the same
## manifest the (future) JS mount entry will share, loads its own bound
## content file, and renders through the real rendering shell (document
## head + site frame) rather than M0's minimal single-route shell.

when defined(js):
  {.error: "ssr.nim is a C-target (server-side) entry point; use main_web.nim for the JS target".}

import std/[os, tables]
import chronicles
import isonim/ssr/renderer
import ./core/content
import ./core/config
import ./core/routes
import ./core/shell_vm
import ./core/markdown_vm
import ./core/navigation_vm
import ./core/references
import ./core/openapi
import ./core/api_reference_vm
import ./core/nimdoc
import ./core/symbol_reference_vm
import ./core/tutorial_vm
import ./core/version_vm
import ./core/i18n_vm
import ./core/plugin
import ./components/shell
import ./components/version_selector
import ./components/language_switcher
import ./components/markdown_page
import ./components/api_reference_page
import ./components/symbol_reference_page
import ./components/tutorial_page

const unmatchableVersionPath = "/\x00unknown-version"
  ## A path no real content pattern can match (`matchPath` compares
  ## non-empty segments and no content slug contains a NUL), so routing an
  ## unknown `/vX.Y/` prefix through it falls straight to the manifest's typed
  ## 404 instead of silently serving the latest content under a bogus version.

proc htmlOpenTag(htmlLang: string): string =
  ## The document `<html>` open tag, carrying `lang="xx"` when i18n resolved a
  ## locale (M10 deliverable 3) and the bare `<html>` otherwise -- so an
  ## un-internationalized page is byte-for-byte unchanged.
  if htmlLang.len > 0: "<html lang=\"" & htmlLang & "\">" else: "<html>"

proc renderRoute*(path: string; contentDir: string = "tests/fixtures/mini-site";
                   manifest: RouteManifest = buildManifestFromContent(contentDir);
                   cfg: DocsConfig = docsConfig();
                   versions: VersionCatalog = VersionCatalog();
                   locales: LocaleCatalog = LocaleCatalog();
                   translations: TranslationTable = TranslationTable();
                   host: PluginHost = PluginHost()):
    tuple[status: int, html: string] =
  ## Renders `path` to `(status, html)` against `manifest`: a matched
  ## entry loads its own bound content file (`RouteMeta.contentPath`)
  ## and renders through the real rendering shell; an unmatched path
  ## renders the manifest's typed not-found page without touching the
  ## filesystem. `contentDir` defaults to the framework's own checked-in
  ## `tests/fixtures/mini-site/` (M1 corrective deliverable 5 -- the
  ## framework carries no real content of its own) but is overridable so
  ## a consumer, or a test, points it at its own real or hermetic
  ## content directory. `manifest`'s framework default (M1 corrective deliverable
  ## 2) auto-discovers the route table from `contentDir` via
  ## `routes.buildManifestFromContent`, so a plain, config-free content
  ## dir "just routes" -- passing an explicit `manifest` (e.g. the
  ## hand-authored `docsRouteManifest()`) still fully overrides it, the
  ## other routing model this same parameter has always supported.
  ## `pkMarkdown` routes (M2 deliverable
  ## 4) load their bound file as a full `ContentEntry` and render
  ## through the markdown page frame; every other page kind keeps the
  ## original M0/M1 `buildShellViewModel`/`renderSiteFrameHtml` path
  ## unchanged -- route *matching* is 100% shared either way, and (as in
  ## the original M1 code) content loading that can raise happens before
  ## `renderToString`, while the actual HTML string-building call still
  ## runs inside its closure. Before matching, `manifest` is extended
  ## with M3 deliverable 3's real alias redirect entries (one real,
  ## authored `aliases:` front matter entry per bound route), so an old,
  ## renamed page's route resolves to a real 301 instead of a 404 --
  ## `manifest` itself (the parameter, and `docsRouteManifest()`) stays
  ## the one hardcoded, platform-agnostic entry list; the extension only
  ## ever happens here and in `main_web.nim`'s `createRouteApp`, the two
  ## real serving entry points. `cfg` defaults to the framework's own
  ## content-agnostic `docsConfig()` (M1 corrective deliverable 3) --
  ## a real site passes its own `DocsConfig` explicitly (e.g.
  ## `../isonim/docs/users/src/docs_config.isonimDocsConfig()` for the IsoNim docs consumer).
  ## M10 deliverable 2 (versioning). When `versions` is non-empty the request
  ## path is resolved through the version catalog FIRST: a `/vX.Y/` prefix is
  ## stripped to a `basePath`, and a KNOWN non-latest version is served from its
  ## own isolated content dir + manifest (`versionContentDir` /
  ## `buildManifestFromContent`), while latest/unprefixed keeps the caller's
  ## own `contentDir`/`manifest` unchanged. An unknown prefixed version routes
  ## to a 404 (via `unmatchableVersionPath`) rather than leaking latest content.
  ## The derived selector + "outdated" banner are rendered as body chrome. When
  ## `versions` is empty the whole block is inert -- the exact pre-M10 behaviour.
  ## M10 deliverable 3 (i18n). When `locales` is non-empty the request path is
  ## resolved through the locale catalog FIRST (outermost prefix): a `/xx/`
  ## prefix for a DECLARED locale is stripped to a `basePath` before any version
  ## resolution, the shared manifest still answers, and the shell renders its
  ## chrome in that locale -- the language switcher (body chrome), the
  ## `translations`-driven UI strings, `hreflang` alternates in `<head>`, and a
  ## `<html lang>` attribute. When `locales` is empty the whole i18n block is
  ## inert -- the exact pre-M10 behaviour.
  let localeOn = locales.locales.len > 0
  let versioningOn = versions.versions.len > 0
  let lres = resolveLocalePath(locales, path)
  # Version resolution runs on the LOCALE-stripped path so `/de/v1.2/x` composes;
  # when i18n is off `lres.basePath` is just the normalized `path`.
  let versionInput = if localeOn: lres.basePath else: path
  let res = resolveVersionedPath(versions, versionInput)
  let servesOldVersion = versioningOn and res.prefixed and res.known and
                          not isLatest(versions, res.versionId)
  let effContentDir = if servesOldVersion:
      versionContentDir(contentDir, versions, res.versionId) else: contentDir
  let effManifest = if servesOldVersion:
      buildManifestFromContent(effContentDir) else: manifest
  let matchTarget =
    if versioningOn and res.prefixed and not res.known: unmatchableVersionPath
    elif versioningOn or localeOn: res.basePath
    else: path
  let versionChrome =
    if versioningOn: renderVersionChromeHtml(
        buildVersionSelector(versions, res), buildVersionBanner(versions, res))
    else: ""

  # --- i18n derived chrome/head (M10 deliverable 3) ---
  let curLocale = localeInfo(locales, lres.localeId)
  let htmlLang = if localeOn: localeHtmlLang(curLocale) else: ""
  let htmlOpen = htmlOpenTag(htmlLang)
  # The language switcher is built over the LOCALE-stripped page path
  # (`lres.basePath`, still version-prefixed if any) so switching locale keeps
  # the reader on the same page/version. Its caption is translated via the
  # table, falling back to the renderer's built-in default when unset.
  let switcherLabelKey = i18nKeyLanguageSwitcherLabel
  let switcherLabelRaw = translate(translations, lres.localeId, switcherLabelKey)
  let switcherLabel = if switcherLabelRaw == switcherLabelKey: "" else: switcherLabelRaw
  let localeChrome =
    if localeOn: renderLanguageSwitcherHtml(
        buildLanguageSwitcher(locales, lres, switcherLabel))
    else: ""
  let bodyChrome = versionChrome & localeChrome
  let hreflangAlternates =
    if localeOn: buildHreflangAlternates(locales, lres.basePath, cfg.baseUrl)
    else: @[]

  let loadEntry = proc(contentPath: string): ContentEntry = loadContentEntry(effContentDir, contentPath)
  let aliasEntries = buildAliasRouteEntries(effManifest, loadEntry)
  let entry = matchRoute(withAliasRedirects(effManifest, aliasEntries), matchTarget).entry
  if entry.status == rsNotFound:
    warn "docs_route_not_found", path = path
  if entry.status == rsRedirect:
    info "docs_route_redirected", path = path, target = entry.redirectTo

  let status = statusCode(entry.status)
  ## Built up front (never raises), so it is available both for the normal
  ## render and, if the body render raises, for the M6 deliverable-2 HTTP
  ## 500 fallback -- which retains the site chrome (head + header/nav/
  ## footer) instead of re-raising the exception.
  let head = buildDocumentHead(entry.meta, cfg, entry.canonicalPath, hreflangAlternates)
  ## M12 deliverable 3: the full head region, laid out per the security
  ## config -- `<meta charset="utf-8">` first, then (when enabled) the CSP
  ## meta, plus the framework's inline scripts (theme bootstrap always;
  ## analytics when configured), hashed into the CSP `script-src`. On the
  ## framework default the theme bootstrap is the head's `headTop` (inside
  ## `<head>`, after the charset meta) -- never emitted before `<head>`.
  let headRegion = renderSecureDocumentHeadHtml(head, cfg)

  proc siteNavigation(): NavigationViewModel =
    ## M6 deliverable 2: EVERY page kind -- including the typed 404 and a
    ## redirect page -- retains the site navigation, so it is built from
    ## the whole content graph regardless of `entry.status`. A page that
    ## isn't a real, matched route (404/redirect) highlights nothing.
    let navPages = buildNavPages(effManifest, loadEntry)
    let activePath = if entry.status == rsOk: entry.canonicalPath else: ""
    buildNavigationViewModel(navPages, activePath, sectionOrder = cfg.sectionOrder)

  proc fallbackHtml(): string =
    ## The HTTP-500 page: normal shell chrome with an error notice in place
    ## of the page body. Navigation is best-effort -- if even the content
    ## graph can't be read, the chrome still renders with an empty nav.
    let nav = try: siteNavigation() except CatchableError: NavigationViewModel()
    let vm = SiteShellViewModel(head: head, pageKind: entry.pageKind,
                                 pageTitle: entry.meta.title, navigation: nav,
                                 siteLogo: cfg.siteLogo, logoHref: cfg.logoHref,
                                 footerHtml: cfg.footerHtml, chrome: chromeOf(cfg))
    htmlOpen & headRegion & "<body>" & bodyChrome &
      renderErrorFallbackHtml(vm) & "</body></html>"

  try:
    ## M5 deliverable 2 (search UX): the search index is NO LONGER inlined
    ## into the served page. It is emitted by the SSG (`build_site.nim`) as
    ## a SEPARATE, content-hashed `/search-index.<hash>.json` artifact that
    ## the keyboard-triggered overlay (`components/search_view.
    ## renderSearchOverlay`, rendered inside the site frame) fetches lazily
    ## on first open -- so no page ships the whole index in its HTML. The
    ## overlay carries the build-time `defaultSearchIndexUrl` placeholder,
    ## which `build_site.buildSite` rewrites to the hashed path exactly like
    ## the M2 asset-href rewrite. (The previous M4 inline JSON bootstrap
    ## `<script>` island was a data island nothing on the client read; the
    ## live inline search box binds to the compile-time-embedded index in
    ## `main_web.nim`, not to any served HTML payload.)
    ## M8 deliverable 2: the global `[[sym:...]]` resolver, built once from
    ## every `pkSymbolReference` page's parsed source -- the exact same
    ## `references.buildSymbolIndex` map the reference checker validates
    ## symrefs against, so a rendered symref's link and its validation
    ## always agree. A resolved query rewrites to a real symbol-anchor link;
    ## an unknown one renders as inline code (and is caught by the checker).
    let symbolIndex = buildSymbolIndex(effContentDir, effManifest)
    let resolveSymbol = proc(q: string): string = symbolIndex.getOrDefault(q, "")

    var renderFn: proc(): string
    if entry.pageKind == pkMarkdown:
      let contentEntry = loadContentEntry(effContentDir, entry.meta.contentPath)
      let doc = parseMarkdownDocWithPlugins(host, contentEntry.page.body, contentEntry.source.path,
                                  makeContentPathResolver(effManifest), resolveSymbol)
      let pageTitle = if contentEntry.page.title.len > 0: contentEntry.page.title else: entry.meta.title
      let navPages = buildNavPages(effManifest, loadEntry)
      let navigation = buildNavigationViewModel(navPages, entry.canonicalPath, doc.headingTree,
                                                sectionOrder = cfg.sectionOrder)
      renderFn = proc(): string =
        htmlOpen & headRegion & "<body>" & bodyChrome &
          renderMarkdownPageHtml(pageTitle, doc.blocks, navigation,
            siteLogo = cfg.siteLogo, logoHref = cfg.logoHref, footerHtml = cfg.footerHtml, chrome = chromeOf(cfg)) & "</body></html>"
    elif entry.pageKind == pkApiReference:
      ## M7 deliverable 2: the route's `contentPath` binds to a
      ## consumer-supplied OpenAPI v3 spec file (YAML or JSON). The raw
      ## file read can raise (a missing file) -- caught by this proc's own
      ## try/except into the M6 500 fallback -- but ingestion itself is
      ## tolerant: a MALFORMED spec yields a typed error the page renders
      ## as an inline notice, never a crash (M7 deliverable 1's contract).
      let specRaw = readFile(effContentDir / entry.meta.contentPath)
      let ingest = ingestOpenApi(specRaw, entry.meta.contentPath)
      let apiVm = buildApiReferenceViewModel(ingest, entry.meta.title)
      let pageTitle = if apiVm.title.len > 0: apiVm.title else: entry.meta.title
      let navPages = buildNavPages(effManifest, loadEntry)
      let navigation = buildNavigationViewModel(navPages, entry.canonicalPath)
      renderFn = proc(): string =
        htmlOpen & headRegion & "<body>" & bodyChrome &
          renderApiReferencePageHtml(pageTitle, apiVm, navigation,
            siteLogo = cfg.siteLogo, logoHref = cfg.logoHref, footerHtml = cfg.footerHtml, chrome = chromeOf(cfg)) & "</body></html>"
    elif entry.pageKind == pkSymbolReference:
      ## M8 deliverable 1: the route's `contentPath` binds to a
      ## consumer-supplied Nim SOURCE file. The raw read can raise (a
      ## missing file) -- caught by this proc's own try/except into the M6
      ## 500 fallback -- but ingestion itself is tolerant: unparseable
      ## source yields a typed error the page renders as an inline notice,
      ## never a crash (M8 deliverable 1's contract, mirroring OpenAPI).
      let srcRaw = readFile(effContentDir / entry.meta.contentPath)
      let ingest = parseNimDoc(srcRaw, moduleNameFromPath(entry.meta.contentPath))
      let symVm = buildSymbolReferenceViewModel(ingest, entry.meta.title)
      let pageTitle = if entry.meta.title.len > 0: entry.meta.title else: symVm.title
      let navPages = buildNavPages(effManifest, loadEntry)
      let navigation = buildNavigationViewModel(navPages, entry.canonicalPath)
      renderFn = proc(): string =
        htmlOpen & headRegion & "<body>" & bodyChrome &
          renderSymbolReferencePageHtml(pageTitle, symVm, navigation,
            siteLogo = cfg.siteLogo, logoHref = cfg.logoHref, footerHtml = cfg.footerHtml, chrome = chromeOf(cfg)) & "</body></html>"
    elif entry.pageKind == pkTutorial:
      ## M10 deliverable 1: the route's `contentPath` binds to a
      ## consumer-supplied markdown file whose top-level `##` (H2) sections
      ## are the tutorial's ordered STEPS. The body renders through the same
      ## markdown pipeline as `pkMarkdown`; the tutorial rail (progress,
      ## checkmarks, reset, series prev/next) is derived from the doc's
      ## heading tree. Completion is hydrated with an always-empty `get` on
      ## SSR (no server-side reader state); the JS mount rehydrates from real
      ## `localStorage`. Step derivation never crashes -- a tutorial with no
      ## H2 sections simply renders an empty (0-of-0) rail.
      let contentEntry = loadContentEntry(effContentDir, entry.meta.contentPath)
      let doc = parseMarkdownDocWithPlugins(host, contentEntry.page.body, contentEntry.source.path,
                                  makeContentPathResolver(effManifest), resolveSymbol)
      let pageTitle = if contentEntry.page.title.len > 0: contentEntry.page.title else: entry.meta.title
      var steps: seq[TutorialStep] = @[]
      for h in doc.headingTree:
        if h.level == 2:
          let sid = if h.id.len > 0: h.id else: slugifyStepId(h.text, steps.len)
          steps.add newTutorialStep(sid, h.text, "#" & sid)
      let tut = newTutorialViewModel(entry.canonicalPath, pageTitle, steps)
      let navPages = buildNavPages(effManifest, loadEntry)
      let navigation = buildNavigationViewModel(navPages, entry.canonicalPath, doc.headingTree,
                                                sectionOrder = cfg.sectionOrder)
      renderFn = proc(): string =
        htmlOpen & headRegion & "<body>" & bodyChrome &
          renderTutorialPageHtml(pageTitle, tut, doc.blocks, navigation,
            siteLogo = cfg.siteLogo, logoHref = cfg.logoHref, footerHtml = cfg.footerHtml, chrome = chromeOf(cfg)) & "</body></html>"
    else:
      let navigation = siteNavigation()
      let vm = buildShellViewModel(entry, cfg,
        proc(contentPath: string): DocsPage = loadDocsPage(effContentDir / contentPath), navigation)
      renderFn = proc(): string =
        htmlOpen & headRegion & "<body>" & bodyChrome &
          renderSiteFrameHtml(vm) & "</body></html>"
    ## M11 deliverable 1: the final HTML string passes through every
    ## registered `onRender` hook (in registration order) before it leaves
    ## the renderer -- an empty host returns it unchanged.
    let html = host.applyOnRender(renderToString(renderFn))
    info "docs_route_rendered", path = path, status = status
    result = (status, html)
  except CatchableError as e:
    ## M6 deliverable 2: a body-render failure returns a real HTTP 500
    ## fallback page (with chrome) instead of re-raising.
    error "docs_render_error", path = path, contentPath = entry.meta.contentPath,
      error = e.msg
    result = (500, renderToString(fallbackHtml))
