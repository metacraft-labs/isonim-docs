## isonim-docs Layer 3 — deterministic, headless-testable site config.
##
## Pure data, no platform imports -- per the IsoNim cross-platform
## architecture rules in AGENTS.md, works identically under `nim c` and
## `nim js`.

type
  SearchMode* = enum
    ## M12 deliverable 2: which path the search box's queries take. The
    ## framework default is `smClientIndex` (every pre-M12 behaviour: rank
    ## the compile-time-embedded / lazily-fetched client index in the
    ## browser). A consumer opts into `smServerApi` to instead send each
    ## (debounced) query to a server search endpoint -- for corpora too
    ## large to ship as a client index. Kept as a plain string-backed enum
    ## (not a bool) so the on-page `data-search-mode` attribute the client
    ## reads is self-describing and a third mode could be added without a
    ## flag-day rename.
    smClientIndex = "client"
    smServerApi = "server"

  ServerSearchConfig* = object
    ## The consumer-supplied search toggle (M12 deliverable 2). Pure data,
    ## content-agnostic: the framework default (`defaultServerSearchConfig`)
    ## leaves `mode == smClientIndex`, so search behaves exactly as it did
    ## before M12 unless a site turns the server path on. `endpoint` is the
    ## server API path the client `fetch`es in `smServerApi` mode;
    ## `debounceMs` is how long the client coalesces keystrokes before
    ## firing one server request (see `server_search.Debouncer`).
    mode*: SearchMode
    endpoint*: string
    debounceMs*: int

  CspDirective* = object
    ## One Content-Security-Policy directive (M12 deliverable 3): a name
    ## (`default-src`, `script-src`, ...) and its ordered source list. Plain
    ## data so a consumer composes a policy without the framework knowing
    ## any site's origins; `core/csp.nim` folds per-page inline-script hashes
    ## into `script-src` at emit time.
    name*: string
    sources*: seq[string]

  CspConfig* = object
    ## A consumer's CSP (M12 deliverable 3). `enabled` is the master switch;
    ## the framework default (`defaultCspConfig`) is OFF, so a site that
    ## configures nothing keeps its exact prior head. `directives` are the
    ## base directives -- the per-page `'sha256-...'` hash-sources are added
    ## to `script-src` at render time (`core/csp.nim`), never stored here.
    enabled*: bool
    directives*: seq[CspDirective]

  AnalyticsProvider* = enum
    ## Which analytics adapter a site uses (M12 deliverable 3). `apNone`
    ## (the framework default) emits nothing -- analytics is opt-in. String-
    ## backed so the value is self-describing in any config/debug output.
    apNone = "none"
    apBeacon = "beacon"   ## generic first-party beacon POST (no vendor)
    apCustom = "custom"   ## consumer-supplied raw provider snippet

  AnalyticsConfig* = object
    ## Consumer analytics configuration (M12 deliverable 3). `apNone` (the
    ## default) emits no snippet at all. `endpoint`/`siteId` parameterize the
    ## built-in first-party beacon; `customScript` is the raw JS body for
    ## `apCustom`. `honorDnt` (default true) gates the emitted script behind
    ## a runtime Do-Not-Track check (`core/analytics.nim`).
    provider*: AnalyticsProvider
    endpoint*: string
    siteId*: string
    customScript*: string
    honorDnt*: bool

  DocsConfig* = object
    siteTitle*: string
    siteDescription*: string
    defaultRoute*: string
    stylesheetHref*: string
    baseUrl*: string ## M6 deliverable 1 (SEO): the site's absolute base
                     ## URL (e.g. "https://docs.example.com"), consumer-
                     ## supplied so the framework stays content-agnostic --
                     ## used to build absolute canonical/OpenGraph URLs and
                     ## the SSG's `sitemap.xml`/`robots.txt`. Left empty by
                     ## the framework default (`docsConfig()`), in which
                     ## case canonical/og URLs fall back to root-relative
                     ## route paths rather than being fabricated against a
                     ## hardcoded host.
    search*: ServerSearchConfig ## M12 deliverable 2's addition: the
                     ## client-index-vs-server-API search toggle. Defaults
                     ## (via `docsConfig()`) to `defaultServerSearchConfig()`
                     ## -- i.e. the client-index path, so every pre-M12 call
                     ## site keeps its exact prior behaviour.
    csp*: CspConfig  ## M12 deliverable 3: the build-time Content-Security-
                     ## Policy. Defaults (via `docsConfig()`) to
                     ## `defaultCspConfig()` -- DISABLED -- so an
                     ## unconfigured site's `<head>` is byte-for-byte
                     ## unchanged. A consumer opts into a policy;
                     ## `core/csp.nim` hashes the page's inline scripts into
                     ## it.
    analytics*: AnalyticsConfig ## M12 deliverable 3: the privacy-respecting
                     ## analytics hook. Defaults to `defaultAnalyticsConfig()`
                     ## -- `apNone`, i.e. no snippet emitted -- so analytics
                     ## is strictly opt-in and DNT-honoring when enabled
                     ## (`core/analytics.nim`).
    siteLogo*: string ## metacraft-theme M3 (Gap A): OPTIONAL logo the shell
                     ## renders as an `<img class="docs-logo">` inside
                     ## `.docs-header`, ahead of the plain `.docs-title` text.
                     ## Empty by the framework default (`docsConfig()`), so the
                     ## header is byte-for-byte the pre-M3 markup unless a
                     ## consumer sets it. Content-agnostic: the framework only
                     ## emits whatever asset path/URL the consumer supplies.
    logoHref*: string ## metacraft-theme M3 (Gap A): OPTIONAL link target the
                     ## logo `<img>` is wrapped in (`<a class="docs-logo-link">`)
                     ## when BOTH it and `siteLogo` are set -- e.g. a home link.
                     ## Empty by default; a bare (un-linked) logo when unset.
    footerHtml*: string ## metacraft-theme M3 (Gap F): OPTIONAL raw HTML the
                     ## shell renders inside the otherwise-empty `.docs-footer`
                     ## (e.g. a copyright/attribution line). Empty by the
                     ## framework default, so the footer stays byte-for-byte the
                     ## pre-M3 empty `<footer>`. Emitted VERBATIM (trusted site
                     ## config, not user content); an SSR-string hook, since raw
                     ## HTML has no generic-renderer node representation.
    headerLinks*: seq[tuple[label, href: string]]
                     ## metacraft-theme-parity M1 (Gap B): OPTIONAL nav buttons
                     ## rendered at the RIGHT of `.docs-header` (WebFlow
                     ## `.ct-nav-btn` -- Sign In/Support/FAQ). Empty by the
                     ## framework default, so the header is byte-for-byte the
                     ## pre-M1 markup unless a consumer sets it.
    sidebarLinks*: seq[tuple[label, href, icon: string]]
                     ## metacraft-theme-parity M1 (Gap C): OPTIONAL external
                     ## links rendered with an `<img>` icon at the BOTTOM of
                     ## `.docs-nav-sidebar` (WebFlow `.link-with-icon` --
                     ## Github/Twitter). `icon` is the asset path/URL. Empty by
                     ## the framework default -> nothing emitted.
    sidebarThemeToggle*: bool
                     ## metacraft-theme-parity M1 (Gap C): OPTIONAL theme-toggle
                     ## PLACEMENT switch. `false` (the framework default) keeps
                     ## the toggle in the header, unchanged. `true` moves the
                     ## single `#docs-theme-toggle` into a pill at the bottom of
                     ## `.docs-nav-sidebar` (WebFlow `.theme-switch`) and the
                     ## header stops emitting it (exactly one toggle either way,
                     ## so the JS click wiring still binds to the same id).
    pageTitleInContent*: bool
                     ## metacraft-theme-parity M1: OPTIONAL content-page header
                     ## layout. `false` (the framework default) keeps the page
                     ## title only in the header, unchanged. `true` renders the
                     ## page `title` as an `<h1 class="docs-md-title">` at the top
                     ## of `.docs-main` AND makes the header stop emitting the
                     ## `.docs-title` (header = logo + search + nav + toggle),
                     ## matching WebFlow.
    lastUpdated*: string
                     ## metacraft-theme-parity M1: OPTIONAL "Last updated" date
                     ## text rendered in a `.docs-md-meta` line under the content
                     ## `<h1>` (only when `showLastUpdated` and
                     ## `pageTitleInContent` are both on). Empty -> no meta line.
    showLastUpdated*: bool
                     ## metacraft-theme-parity M1: master switch for the
                     ## `lastUpdated` meta line. `false` (default) -> no line.
    needHelp*: tuple[heading: string, links: seq[tuple[label, href, icon: string]]]
                     ## metacraft-theme-parity M1: OPTIONAL "Need some help?"
                     ## block (WebFlow `.footer` region) rendered as a
                     ## `.docs-need-help` section ABOVE `.docs-footer`. Empty
                     ## `heading` + empty `links` (the framework default) -> the
                     ## block is not emitted at all, so the page is byte-for-byte
                     ## the pre-M1 markup unless a consumer sets it.

const
  defaultSearchEndpoint* = "/api/search"
    ## The framework-default server search endpoint path a `smServerApi`
    ## site's client posts queries to (consumers override it). The SSG /
    ## dev server need not know about it -- it is emitted into the page as
    ## the overlay's `data-search-endpoint` for the client to read.
  defaultSearchDebounceMs* = 200
    ## The default keystroke-coalescing window (ms) before a server search
    ## request fires -- long enough that fast typing sends one request, not
    ## one per character, short enough to feel live.

proc defaultServerSearchConfig*(): ServerSearchConfig =
  ## The framework's content-agnostic search-toggle default: the
  ## client-index path (M12 deliverable 2's "when toggled off, the existing
  ## client index path must still work"). `endpoint`/`debounceMs` carry
  ## sane values a site that flips `mode` to `smServerApi` inherits without
  ## having to restate them.
  ServerSearchConfig(mode: smClientIndex, endpoint: defaultSearchEndpoint,
    debounceMs: defaultSearchDebounceMs)

proc defaultCspConfig*(): CspConfig =
  ## The framework default: CSP disabled. Emits no meta/header, so every
  ## pre-M12 page is byte-for-byte unchanged unless a consumer opts in.
  CspConfig(enabled: false, directives: @[])

proc strictCspConfig*(): CspConfig =
  ## A ready-made strict starting point a consumer can adopt or extend: no
  ## `'unsafe-inline'` on scripts (inline scripts ride in via their per-page
  ## hashes -- `core/csp.nim`), everything else same-origin. Content-
  ## agnostic: it names no host, only `'self'`. `object-src 'none'` +
  ## `base-uri 'self'` close the usual injection escape hatches.
  CspConfig(enabled: true, directives: @[
    CspDirective(name: "default-src", sources: @["'self'"]),
    CspDirective(name: "script-src", sources: @["'self'"]),
    CspDirective(name: "style-src", sources: @["'self'", "'unsafe-inline'"]),
    CspDirective(name: "img-src", sources: @["'self'", "data:"]),
    CspDirective(name: "connect-src", sources: @["'self'"]),
    CspDirective(name: "object-src", sources: @["'none'"]),
    CspDirective(name: "base-uri", sources: @["'self'"]),
  ])

proc defaultAnalyticsConfig*(): AnalyticsConfig =
  ## The framework's content-agnostic default: analytics OFF (`apNone`),
  ## DNT honored if ever enabled. A site opts in with its own config.
  AnalyticsConfig(provider: apNone, honorDnt: true)

type
  DocsChrome* = object
    ## metacraft-theme-parity M1: the bundle of OPTIONAL chrome hooks the SSR
    ## header/sidebar/content/footer renderers consume, derived once from a
    ## `DocsConfig` by `chromeOf`. A default-constructed `DocsChrome()` (every
    ## field empty/false) is the framework default: passed to the renderers it
    ## makes them emit byte-for-byte the pre-M1 markup. Bundled into one object
    ## (rather than a fresh positional parameter per hook) so threading it
    ## through the page renderers is one argument, and the "unset == no-op"
    ## default is a single zero value.
    headerLinks*: seq[tuple[label, href: string]]
    sidebarLinks*: seq[tuple[label, href, icon: string]]
    sidebarThemeToggle*: bool
    pageTitleInContent*: bool
    lastUpdated*: string
    showLastUpdated*: bool
    needHelp*: tuple[heading: string, links: seq[tuple[label, href, icon: string]]]

proc chromeOf*(cfg: DocsConfig): DocsChrome =
  ## Projects a `DocsConfig`'s M1 chrome hooks into the `DocsChrome` bundle the
  ## SSR renderers take. The framework-default `docsConfig()` leaves every one
  ## of these fields empty/false, so `chromeOf(docsConfig())` is a plain
  ## `DocsChrome()` -- i.e. the byte-identical no-op default.
  DocsChrome(
    headerLinks: cfg.headerLinks,
    sidebarLinks: cfg.sidebarLinks,
    sidebarThemeToggle: cfg.sidebarThemeToggle,
    pageTitleInContent: cfg.pageTitleInContent,
    lastUpdated: cfg.lastUpdated,
    showLastUpdated: cfg.showLastUpdated,
    needHelp: cfg.needHelp,
  )

proc joinSiteUrl*(baseUrl, routePath: string): string =
  ## Joins a consumer-supplied `baseUrl` with a normalized route path into
  ## the absolute URL SEO tags and the sitemap cite. Pure string work (no
  ## `std/os`/`uri`), so it is identical on the C and JS targets. With no
  ## `baseUrl` configured it returns the root-relative path unchanged --
  ## the framework never invents a host it wasn't given.
  var p = routePath
  if p.len == 0: p = "/"
  if p[0] != '/': p = "/" & p
  if baseUrl.len == 0:
    return p
  var b = baseUrl
  while b.len > 1 and b[^1] == '/':
    b = b[0 ..< b.len - 1]
  b & p

proc docsConfig*(): DocsConfig =
  ## The framework's own content-agnostic default `DocsConfig` -- carries
  ## no site-specific branding (M1 corrective deliverable 3). A real site
  ## supplies its own `DocsConfig` (e.g. `../isonim/docs/users/src/docs_config.isonimDocsConfig()`
  ## for the current isonim-docs site, or a future consumer package's own
  ## const/config file) and passes it explicitly wherever a `DocsConfig`
  ## default parameter is accepted -- this proc is only ever the
  ## fallback when no such override is given.
  DocsConfig(
    siteTitle: "Documentation",
    siteDescription: "Documentation site.",
    defaultRoute: "/",
    stylesheetHref: "/assets/style.css",
    search: defaultServerSearchConfig(),
    csp: defaultCspConfig(),
    analytics: defaultAnalyticsConfig(),
  )
