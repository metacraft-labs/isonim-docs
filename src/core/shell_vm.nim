## isonim-docs Layer 3 — ViewModels for the docs rendering shell. Pure
## data derived from `DocsPage`/`RouteEntry`/`DocsConfig`; zero
## platform/CSS imports, so it's headless-testable without any renderer.

import ./content
import ./config
import ./routes
import ./navigation_vm
import ./search_vm
import ./theme_vm
import isonim/static/head

# The SEO head type and its builders moved to `isonim/static/head`;
# re-exported so every existing import of this module sees the same type.
# `DocumentHead` (with the head fields it always had, plus `themeColors`,
# `ogImage` and `twitterCard`, empty by default) is that module's type.
export DocumentHead, ThemeColor, formatPageTitle, jsonLdString

type
  ShellViewModel* = object
    ## M0's minimal single-route shell VM. Still used by the M0 proof
    ## route (`src/ssr.nim`, `src/main_web.nim`) -- kept as-is so M0
    ## stays green; `SiteShellViewModel` below is the M1 rendering-shell
    ## VM built on top of the real route contract.
    title*: string
    bodyText*: string
    stylesheetHref*: string

  PageRegion* = enum
    ## The rendering shell's stable layout regions -- the anchors M3's
    ## navigation and M4's search wiring attach to.
    prHeader
    prNav
    prMain
    prFooter

  SiteShellViewModel* = object
    ## The M1 rendering-shell VM: a route's document head plus the
    ## visible page title/body content, keyed by page kind so the shell
    ## can render the not-found shape without a separate VM type.
    ## `navigation` is M3's addition -- the real-content-graph-backed
    ## sidebar/breadcrumbs/adjacent-pages ViewModel the shell's stable
    ## `prNav` region renders (see `navigation_vm.nim`). It defaults to
    ## the zero-value `NavigationViewModel()` (an empty nav region,
    ## exactly M0/M1/M2's original shape) so every pre-M3 call site of
    ## `siteShellViewModel`/`notFoundShellViewModel`/`buildShellViewModel`
    ## keeps compiling and passing unchanged.
    head*: DocumentHead
    pageKind*: PageKind
    pageTitle*: string
    bodyText*: string
    navigation*: NavigationViewModel
    redirectTo*: string ## M3 deliverable 3's addition: for a `pkRedirect`
                        ## entry, the canonical route path it resolves to.
                        ## Empty (and unused) for every other page kind.
    siteLogo*: string ## metacraft-theme M3 (Gap A): the optional header logo
                      ## asset path/URL, threaded from `DocsConfig.siteLogo` so
                      ## `renderSiteFrameHtml` can render it in `.docs-header`.
                      ## Empty (framework default) -> no logo, byte-for-byte the
                      ## pre-M3 header. Defaults to "" so every pre-M3 call site
                      ## that builds a `SiteShellViewModel` directly is unchanged.
    logoHref*: string ## metacraft-theme M3 (Gap A): the optional link target the
                      ## logo is wrapped in (`DocsConfig.logoHref`). Empty -> a
                      ## bare, un-linked logo.
    footerHtml*: string ## metacraft-theme M3 (Gap F): the optional raw footer
                      ## HTML (`DocsConfig.footerHtml`) rendered in `.docs-footer`.
                      ## Empty (framework default) -> the pre-M3 empty `<footer>`.
    chrome*: DocsChrome ## metacraft-theme-parity M1: the bundle of optional
                      ## header-nav / sidebar-social+pill-toggle / content-H1 /
                      ## need-help chrome hooks (`config.chromeOf(cfg)`) the
                      ## `renderSiteFrameHtml` path renders. A default
                      ## `DocsChrome()` (the framework default) renders every hook
                      ## as nothing, so the frame stays byte-for-byte pre-M1.
    serverSearch*: ServerSearchConfig ## M12 deliverable 2's addition: the
                             ## client-index-vs-server-API search toggle
                             ## (`config.ServerSearchConfig`) the shell emits
                             ## onto the search overlay so the client mount
                             ## picks the right path. Populated from `cfg.search`
                             ## by the builders below; defaults to the zero-value
                             ## (client mode) so every pre-M12 call site that
                             ## constructs a `SiteShellViewModel` directly keeps
                             ## its exact prior (client-index) behaviour.
    search*: SearchViewModel ## M4 deliverable 1's addition: the search
                             ## box's *initial* (always closed, empty-query)
                             ## state every SSR/JS-mounted page renders --
                             ## real interactivity is wired up client-side
                             ## after mount (`main_web.nim`), against the
                             ## real build-time index, not per-route data
                             ## here. Defaults to the zero-value
                             ## `SearchViewModel()` so every pre-M4 call
                             ## site of `siteShellViewModel`/
                             ## `notFoundShellViewModel`/`buildShellViewModel`
                             ## keeps compiling and passing unchanged.
    theme*: ThemeViewModel ## M2 deliverable 2's addition: the theme
                           ## toggle's *initial* state every SSR/JS-mounted
                           ## page renders -- always the zero-value
                           ## `ThemeViewModel()` (`thLight`), exactly the
                           ## same "deterministic default, real state
                           ## resolved client-side" convention `search`
                           ## above already uses (see its own docstring);
                           ## the real persisted/preferred theme is applied
                           ## by the SSR no-flash bootstrap script
                           ## (`components/theme_toggle.
                           ## renderThemeBootstrapHtml`) and JS mount's
                           ## click wiring (`src/main_web.nim`), never
                           ## baked into this per-route ViewModel.

proc shellViewModel*(page: DocsPage; cfg: DocsConfig = docsConfig()): ShellViewModel =
  ShellViewModel(title: page.title, bodyText: page.body,
                  stylesheetHref: cfg.stylesheetHref)

const
  regionHeaderId* = "docs-region-header"
  regionNavId* = "docs-region-nav"
  regionMainId* = "docs-region-main"
  regionFooterId* = "docs-region-footer"

proc regionId*(region: PageRegion): string =
  ## The one place stable region IDs are minted, so the rendering shell
  ## and later navigation/search wiring always agree on the same
  ## DOM/SSR anchor IDs.
  case region
  of prHeader: regionHeaderId
  of prNav: regionNavId
  of prMain: regionMainId
  of prFooter: regionFooterId

proc buildJsonLd*(head: DocumentHead): string =
  ## The JSON-LD (`schema.org`) document a docs page emits: a `TechArticle`
  ## with its headline/description and (when configured) its absolute URL,
  ## plus the site as its publisher (`isonim/static/head.articleJsonLd`).
  articleJsonLd(head, "TechArticle")

proc buildDocumentHead*(meta: RouteMeta; cfg: DocsConfig;
                         routePath: string = "";
                         alternates: seq[tuple[hreflang, href: string]] = @[]): DocumentHead =
  ## Metadata hook: a route's typed `RouteMeta` drives the document
  ## head, falling back to the site-wide config for whichever fields the
  ## route itself doesn't set. `routePath` (the route's canonical path) is
  ## joined with `cfg.baseUrl` into the absolute canonical/OpenGraph URL
  ## (M6 deliverable 1); it defaults to "" so pre-M6 call sites keep
  ## compiling -- they simply get a root-relative canonical URL.
  let description = if meta.description.len > 0: meta.description else: cfg.siteDescription
  result = DocumentHead(title: formatPageTitle(meta.title, cfg.siteTitle),
               description: description, stylesheetHref: cfg.stylesheetHref,
               siteName: cfg.siteTitle,
               canonicalUrl: joinSiteUrl(cfg.baseUrl, routePath),
               ogType: "article", alternates: alternates)
  result.jsonLd = buildJsonLd(result)

proc siteShellViewModel*(entry: RouteEntry; page: DocsPage;
                          cfg: DocsConfig = docsConfig();
                          navigation: NavigationViewModel = NavigationViewModel()): SiteShellViewModel =
  ## For a matched, real route: the loaded page content supplies the
  ## visible title/body, falling back to the route's own meta title when
  ## the content has none.
  let pageTitle = if page.title.len > 0: page.title else: entry.meta.title
  SiteShellViewModel(head: buildDocumentHead(entry.meta, cfg, entry.canonicalPath),
                      pageKind: entry.pageKind,
                      pageTitle: pageTitle, bodyText: page.body, navigation: navigation,
                      serverSearch: cfg.search,
                      siteLogo: cfg.siteLogo, logoHref: cfg.logoHref,
                      footerHtml: cfg.footerHtml, chrome: chromeOf(cfg))

proc notFoundShellViewModel*(entry: RouteEntry;
                              cfg: DocsConfig = docsConfig();
                              navigation: NavigationViewModel = NavigationViewModel()): SiteShellViewModel =
  ## For the typed not-found entry: there is no real content file to
  ## load, so the shell renders directly off the entry's own meta. M6
  ## deliverable 2 makes the 404 page RETAIN the site navigation -- the
  ## caller (which has the whole content graph) passes it in, exactly like
  ## `siteShellViewModel`; it still defaults to an empty nav so pre-M6
  ## call sites keep their original shape.
  SiteShellViewModel(head: buildDocumentHead(entry.meta, cfg, entry.canonicalPath),
                      pageKind: pkNotFound,
                      pageTitle: entry.meta.title, bodyText: "", navigation: navigation,
                      serverSearch: cfg.search,
                      siteLogo: cfg.siteLogo, logoHref: cfg.logoHref,
                      footerHtml: cfg.footerHtml, chrome: chromeOf(cfg))

proc redirectShellViewModel*(entry: RouteEntry;
                              cfg: DocsConfig = docsConfig();
                              navigation: NavigationViewModel = NavigationViewModel()): SiteShellViewModel =
  ## For a `pkRedirect` alias entry (M3 deliverable 3): there is no real
  ## content file to load either -- an old, renamed page's route resolves
  ## straight off the entry's own `redirectTo`. Navigation is threaded
  ## through the same way (defaulting to empty) so a redirect page can
  ## carry the site chrome's nav too.
  SiteShellViewModel(head: buildDocumentHead(entry.meta, cfg, entry.canonicalPath),
                      pageKind: pkRedirect,
                      pageTitle: "Redirecting…", bodyText: "", redirectTo: entry.redirectTo,
                      navigation: navigation, serverSearch: cfg.search,
                      siteLogo: cfg.siteLogo, logoHref: cfg.logoHref,
                      footerHtml: cfg.footerHtml, chrome: chromeOf(cfg))

proc buildShellViewModel*(entry: RouteEntry; cfg: DocsConfig;
                           loadPage: proc(contentPath: string): DocsPage {.closure.};
                           navigation: NavigationViewModel = NavigationViewModel()): SiteShellViewModel =
  ## The one shared route-resolution step both the SSR entry
  ## (`src/ssr.nim`'s `renderRoute`) and the JS mount entry
  ## (`src/main_web.nim`'s `createRouteApp`) call after `matchRoute`:
  ## a matched route loads its own bound content file and builds
  ## `siteShellViewModel`; the typed not-found entry builds
  ## `notFoundShellViewModel` without loading anything, and a `pkRedirect`
  ## alias entry builds `redirectShellViewModel` the same way. Content
  ## loading is the only platform-specific seam -- a real filesystem read
  ## on SSR, a compile-time-embedded lookup on JS (no runtime filesystem
  ## there) -- so it's injected via `loadPage` rather than forked here.
  ## `navigation` is likewise caller-built (it needs the *whole* content
  ## graph, not just this one route's page) and simply passed through.
  if entry.pageKind == pkNotFound:
    notFoundShellViewModel(entry, cfg, navigation)
  elif entry.pageKind == pkRedirect:
    redirectShellViewModel(entry, cfg, navigation)
  else:
    siteShellViewModel(entry, loadPage(entry.meta.contentPath), cfg, navigation)
