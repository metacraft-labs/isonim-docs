## isonim-docs Layer 2 — the minimal docs page shell (M0 proof route).
##
## Generic over the renderer backend (`proc renderX*[R, E](r: R; ...): E`
## per AGENTS.md), so the exact same DSL tree is exercised by
## `MockRenderer` (Tier 2 tests) and the real browser DOM (`WebRenderer`,
## JS-target mount) without any code changes -- this is the framework's
## existing seam (see ../isonim/examples/wanderlust), not a new one.
##
## SSR needs string output rather than a live element tree, which the
## `ui` DSL provides as a separate codegen mode (`ui: ...`, no renderer
## argument -- see isonim/dsl/ui.nim). `renderShellHtml` is kept
## structurally identical to `renderShell` on purpose: same markup, two
## different macro backends. M1 replaces both with the real
## routing/rendering core; a hand-rolled pair is enough for one route.

import isonim/core/computation
import isonim/dsl/ui
import isonim/ssr/escape
import ../core/routes
import ../core/shell_vm
import ../core/search_vm
import ../core/theme_vm
import ../core/config
import isonim/static/csp
import isonim/static/head
import isonim/static/scripts
import ../core/analytics
import ./navigation_view
import ./search_view
import ./theme_toggle
import ./image_viewer

# The `ui(r): ...` client-mode macro expands to code that references
# `createRenderEffect` as a bare (non-hygienic) identifier resolved at
# each call site's scope, not just here where `ui` itself is imported --
# so every caller of `renderShell` needs it in scope too. Re-export it
# rather than making every call site (tests, main_web.nim) import
# isonim's reactive core module just to satisfy the macro's internals.
export computation

# The SEO head renderers moved to `isonim/static/head`; re-exported so every
# existing caller of `shell.renderDocumentHead` / `renderDocumentHeadHtml`
# keeps compiling.
export renderDocumentHead, renderDocumentHeadHtml

const
  shellClass* = "docs-shell"
  titleClass* = "docs-title"
  bodyClass* = "docs-body"

proc renderShell*[R, E](r: R; vm: ShellViewModel): E =
  ## Client/mock tree-mode rendering: title, body slot, and a real
  ## stylesheet `<link>` as the static-asset hook.
  ui(r):
    tdiv(class = shellClass):
      link(rel = "stylesheet", href = vm.stylesheetHref)
      h1(class = titleClass):
        text vm.title
      tdiv(class = bodyClass):
        text vm.bodyText

proc renderShellHtml*(vm: ShellViewModel): string =
  ## SSR string-mode rendering -- same shape as `renderShell`.
  ui:
    tdiv(class = shellClass):
      link(rel = "stylesheet", href = vm.stylesheetHref)
      h1(class = titleClass):
        text vm.title
      tdiv(class = bodyClass):
        text vm.bodyText

const
  frameClass* = "docs-frame"
  headerClass* = "docs-header"
  navClass* = "docs-nav"
  mainClass* = "docs-main"
  mainWideClass* = "docs-main--wide"
    ## metacraft-theme-parity M6: added ALONGSIDE `mainClass` on a LANDING page
    ## (one whose body contains a `:::hero`, per `markdown_view.pageHasHero`) so
    ## the theme can give the landing a WIDER content column than a normal
    ## article -- a purely additive class the consumer's CSS opts into; a
    ## consumer that never styles it sees no change. A normal (non-hero) page's
    ## `<main>` stays exactly `class="docs-main"`.
  footerClass* = "docs-footer"
  notFoundClass* = "docs-not-found"
  redirectClass* = "docs-redirect"
  redirectLinkClass* = "docs-redirect-link"
  skipLinkClass* = "docs-skip-link"
  skipLinkText* = "Skip to content"
  errorFallbackClass* = "docs-error-fallback"
  errorFallbackText* = "This page could not be rendered."
  logoClass* = "docs-logo"          ## M3 (Gap A): the header logo `<img>`.
  logoLinkClass* = "docs-logo-link" ## M3 (Gap A): the optional logo link wrapper.
  # Minimal-chrome (auth-style) page layout: a full-page section with only a
  # logo at the top and a centered card, no sidebar/header-nav/TOC/footer
  # (WebFlow `.section-fullpage` + `.nav-secondary` + `.container-center`).
  frameMinimalClass* = "docs-frame--minimal" ## added ALONGSIDE `frameClass`.
  minimalNavClass* = "docs-minimal-nav"       ## the logo-only top bar.
  mainMinimalClass* = "docs-main--minimal"    ## added ALONGSIDE `mainClass`.
  minimalCardClass* = "docs-minimal-card"     ## the centered auth card.
  # metacraft-theme-parity M1 chrome classes (all default-off; see `DocsChrome`).
  headerNavClass* = "docs-header-nav"        ## Gap B: header nav-button group (WebFlow `.ct-nav-links`).
  headerNavBtnClass* = "docs-header-nav-btn"  ## Gap B: one header nav button (WebFlow `.ct-nav-btn`).
  sidebarExtrasClass* = "docs-sidebar-extras" ## Gap C: bottom-of-sidebar social + toggle wrapper.
  sidebarLinkClass* = "docs-sidebar-link"     ## Gap C: one social link (WebFlow `.link-with-icon`).
  sidebarLinkIconClass* = "docs-sidebar-link-icon" ## Gap C: the social link `<img>` icon.
  themeSwitchWrapClass* = "docs-theme-switch-wrap" ## Gap C: pill-toggle wrapper (WebFlow `.theme-switch-wrap`).
  contentTitleClass* = "docs-md-title"        ## content-page `<h1>` at the top of `.docs-main`.
  contentMetaClass* = "docs-md-meta"          ## the "Last updated <date>" meta line under the H1.
  needHelpClass* = "docs-need-help"           ## the "Need some help?" block above `.docs-footer`.
  needHelpHeadingClass* = "docs-need-help-heading"
  needHelpLinkClass* = "docs-need-help-link"
  needHelpLinkIconClass* = "docs-need-help-link-icon"

proc renderHeaderNavHtml(links: seq[tuple[label, href: string]]): string =
  ## metacraft-theme-parity M1 (Gap B): the OPTIONAL header nav-button group.
  ## Empty `links` (the framework default) -> "" (nothing emitted), so the
  ## header is byte-for-byte the pre-M1 markup.
  if links.len == 0: return ""
  result = "<nav class=\"" & headerNavClass & "\">"
  for link in links:
    result.add "<a class=\"" & headerNavBtnClass & "\" href=\"" & escapeAttr(link.href) &
      "\">" & escapeHtml(link.label) & "</a>"
  result.add "</nav>"

proc renderDocsHeaderHtml*(pageTitle: string; search: SearchViewModel;
                           theme: ThemeViewModel;
                           siteLogo = ""; logoHref = "";
                           chrome = DocsChrome()): string =
  ## The one place the SSR-string site header is built, shared by every
  ## page renderer (`renderSiteFrameHtml` + the markdown/api/symbol/tutorial
  ## page shells) so they stay in lock-step. `siteLogo`/`logoHref` are the M3
  ## (Gap A) OPTIONAL hooks: when `siteLogo` is empty (the framework default)
  ## NOTHING is emitted before the title, so the header is byte-for-byte the
  ## pre-M3 markup; when set, a `<img class="docs-logo">` (wrapped in a
  ## `logoHref` link when that too is set) is the header's first child, ahead
  ## of the plain `.docs-title` text.
  ##
  ## `chrome` carries the metacraft-theme-parity M1 hooks. A default
  ## `DocsChrome()` (the framework default) leaves the header byte-for-byte the
  ## pre-M1 markup: `headerLinks` empty -> no nav group, `pageTitleInContent`
  ## false -> the `.docs-title` H1 is still emitted, `sidebarThemeToggle` false
  ## -> the header still carries the theme toggle. When a consumer opts in, the
  ## header adds a `.docs-header-nav` button group after the search box, and/or
  ## drops the title H1 (it moves into `.docs-main`) and/or drops the theme
  ## toggle (it moves into the sidebar pill).
  var logoHtml = ""
  if siteLogo.len > 0:
    let img = "<img class=\"" & logoClass & "\" src=\"" & escapeAttr(siteLogo) &
      "\" alt=\"" & escapeAttr(pageTitle) & "\" />"
    logoHtml =
      if logoHref.len > 0:
        "<a class=\"" & logoLinkClass & "\" href=\"" & escapeAttr(logoHref) &
          "\">" & img & "</a>"
      else: img
  let titleHtml =
    if chrome.pageTitleInContent: ""
    else: "<h1 class=\"" & titleClass & "\">" & escapeHtml(pageTitle) & "</h1>"
  let toggleHtml =
    if chrome.sidebarThemeToggle: ""
    else: renderThemeToggleHtml(theme)
  "<header id=\"" & regionId(prHeader) & "\" class=\"" & headerClass & "\">" &
    logoHtml &
    titleHtml &
    renderSearchBoxHtml(search) &
    renderHeaderNavHtml(chrome.headerLinks) &
    toggleHtml &
  "</header>"

proc renderSidebarExtrasHtml*(chrome: DocsChrome; theme: ThemeViewModel): string =
  ## metacraft-theme-parity M1 (Gap C): the OPTIONAL block appended at the
  ## BOTTOM of `.docs-nav-sidebar` -- the external social links (`sidebarLinks`,
  ## WebFlow `.link-with-icon`) followed by the pill theme toggle (WebFlow
  ## `.theme-switch-wrap`) when `sidebarThemeToggle` is on. Returns "" when
  ## neither is configured, so the sidebar is byte-for-byte pre-M1. The toggle
  ## reuses the SAME `renderThemeToggleHtml` button (id `docs-theme-toggle`) the
  ## header would otherwise carry -- and the header suppresses its own copy when
  ## `sidebarThemeToggle` is on -- so there is exactly one toggle and the JS
  ## click wiring still binds by id.
  if chrome.sidebarLinks.len == 0 and not chrome.sidebarThemeToggle: return ""
  result = "<div class=\"" & sidebarExtrasClass & "\">"
  for link in chrome.sidebarLinks:
    result.add "<a class=\"" & sidebarLinkClass & "\" href=\"" & escapeAttr(link.href) &
      "\" target=\"_blank\" rel=\"noopener\">"
    if link.icon.len > 0:
      result.add "<img class=\"" & sidebarLinkIconClass & "\" src=\"" & escapeAttr(link.icon) &
        "\" alt=\"\" />"
    result.add "<span>" & escapeHtml(link.label) & "</span></a>"
  if chrome.sidebarThemeToggle:
    result.add "<div class=\"" & themeSwitchWrapClass & "\">" & renderThemeToggleHtml(theme) & "</div>"
  result.add "</div>"

proc renderContentTitleHtml*(pageTitle: string; chrome: DocsChrome): string =
  ## metacraft-theme-parity M1: the OPTIONAL content-page `<h1>` (+ "Last
  ## updated" meta) rendered as the FIRST child of `.docs-main` when
  ## `pageTitleInContent` is on (WebFlow's big content H1). Returns "" when off,
  ## so the content area is byte-for-byte pre-M1.
  if not chrome.pageTitleInContent: return ""
  result = "<h1 class=\"" & contentTitleClass & "\">" & escapeHtml(pageTitle) & "</h1>"
  if chrome.showLastUpdated and chrome.lastUpdated.len > 0:
    result.add "<div class=\"" & contentMetaClass & "\"><span>Last updated</span> <span>" &
      escapeHtml(chrome.lastUpdated) & "</span></div>"

proc renderNeedHelpHtml*(chrome: DocsChrome): string =
  ## metacraft-theme-parity M1: the OPTIONAL "Need some help?" block (WebFlow
  ## `.footer` region) rendered ABOVE `.docs-footer`. Returns "" when neither a
  ## heading nor any links are configured, so the page is byte-for-byte pre-M1.
  if chrome.needHelp.heading.len == 0 and chrome.needHelp.links.len == 0: return ""
  result = "<section class=\"" & needHelpClass & "\">"
  if chrome.needHelp.heading.len > 0:
    result.add "<div class=\"" & needHelpHeadingClass & "\">" &
      escapeHtml(chrome.needHelp.heading) & "</div>"
  for link in chrome.needHelp.links:
    result.add "<a class=\"" & needHelpLinkClass & "\" href=\"" & escapeAttr(link.href) & "\">"
    if link.icon.len > 0:
      result.add "<img class=\"" & needHelpLinkIconClass & "\" src=\"" & escapeAttr(link.icon) &
        "\" alt=\"\" />"
    result.add "<span>" & escapeHtml(link.label) & "</span></a>"
  result.add "</section>"

proc renderDocsFooterHtml*(footerHtml = ""): string =
  ## The one place the SSR-string site footer is built. `footerHtml` is the
  ## M3 (Gap F) OPTIONAL hook: empty by the framework default -- byte-for-byte
  ## the pre-M3 empty `<footer>` -- and, when a consumer sets it, its raw HTML
  ## is emitted VERBATIM inside the footer (trusted site config, not user
  ## content). SSR-string-only by design: arbitrary HTML has no generic
  ## renderer-backend node representation, so the tree/mock path renders the
  ## unchanged empty footer.
  "<footer id=\"" & regionId(prFooter) & "\" class=\"" & footerClass & "\">" &
    footerHtml & "</footer>"

proc renderSkipLink*[R, E](r: R): E =
  ## M2 deliverable 4: a "skip to content" link, rendered as the site
  ## frame's very first child (before header/nav) so it's the first
  ## tabbable element on every page -- a keyboard/screen-reader user can
  ## jump straight past the header and nav landmarks into
  ## `#docs-region-main` without tabbing through them. Visually hidden
  ## off-screen until focused (`.docs-skip-link` in `assets/style.css`),
  ## so it never affects sighted mouse users' layout.
  let a = r.createElement("a")
  r.setAttribute(a, "class", skipLinkClass)
  r.setAttribute(a, "href", "#" & regionId(prMain))
  r.appendChild(a, r.createTextNode(skipLinkText))
  a

proc renderSkipLinkHtml*(): string =
  ## SSR string-mode rendering -- same shape as `renderSkipLink`.
  "<a class=\"" & skipLinkClass & "\" href=\"#" & regionId(prMain) & "\">" & skipLinkText & "</a>"

proc docsPageScripts*(cfg: DocsConfig): seq[PageScript] =
  ## Every executable script an isonim-docs page declares, in emission
  ## order: the theme no-flash bootstrap (always, early in `<head>`), the
  ## analytics beacon (only when configured, also early in `<head>`), the
  ## deferred app bundle (only when `appScriptHref` is set, just before
  ## `</head>`), and the image viewer (always, as the last child of
  ## `<body>` -- see `components/image_viewer`). `cfg.scriptPolicy` decides
  ## which of them a page carries (`isonim/static/scripts`): all of them
  ## under the default `spDeclared`, only the analytics snippet under
  ## `spNone`. (The JSON-LD and search-index blocks are
  ## `type=application/(ld+)json` data blocks, not executable, so neither
  ## the policy nor CSP `script-src` applies to them.)
  result = @[inlineScript(themeBootstrapScriptBody(), id = themeBootstrapScriptId,
                          slot = ssHeadTop)]
  let analyticsBody = analyticsScriptBody(cfg.analytics)
  if analyticsBody.len > 0:
    result.add inlineScript(analyticsBody, id = analyticsScriptId, slot = ssHeadTop,
                            role = srAnalytics)
  if cfg.appScriptHref.len > 0:
    result.add externalScript(cfg.appScriptHref, slot = ssHeadEnd)
  result.add inlineScript(imageViewerScriptBody(), id = imageViewerScriptId,
                          slot = ssBodyEnd)

proc renderHeadSecurityTop*(cfg: DocsConfig): string =
  ## The secure head prelude (M12 deliverable 3): the CSP `<meta>` (first,
  ## so it governs everything after it), then the framework's own early
  ## inline scripts in a fixed order -- the theme no-flash bootstrap and the
  ## analytics beacon (only when configured), as `cfg.scriptPolicy` keeps
  ## them. The same script bodies are hashed into the CSP's `script-src`.
  let kept = applyScriptPolicy(cfg.scriptPolicy, docsPageScripts(cfg))
  renderCspMetaHtml(cfg.csp, inlineScriptBodies(kept)) & renderScriptsHtml(kept, ssHeadTop)

proc renderAppScriptHtml*(cfg: DocsConfig): string =
  ## M1 (client-JS bundle): the single `<script src="..." defer></script>` the
  ## framework injects into `<head>` on EVERY page when a consumer configures
  ## `appScriptHref` (the compiled `nim js` app bundle). `defer` makes it
  ## PROGRESSIVE ENHANCEMENT -- it runs after the document is fully parsed, so
  ## the SSR HTML is complete and navigable without it and the script only
  ## ADDS behaviour (theme toggle, live search, sidebar collapse, soft-nav).
  ## Empty `appScriptHref` (the framework default) -> "" (byte-for-byte the
  ## pre-M1 head). A same-origin `/assets/...` src is allowed by even a strict
  ## `script-src 'self'` CSP, so no per-page hash is needed.
  if cfg.appScriptHref.len == 0: return ""
  renderScriptHtml(externalScript(cfg.appScriptHref, slot = ssHeadEnd))

proc renderSecureDocumentHeadHtml*(head: DocumentHead; cfg: DocsConfig): string =
  ## The full head region (everything between `<html...>` and `<body>`),
  ## laid out per the security config and the script policy
  ## (`isonim/static/head.renderPageHeadHtml`): `<meta charset="utf-8">`
  ## first; then the CSP `<meta>` when a consumer enables CSP (so the policy
  ## governs the scripts whose hashes it carries); then the theme no-flash
  ## bootstrap and the analytics beacon (when configured), before `<title>`;
  ## and the deferred app `<script>` (when `appScriptHref` is set) just
  ## before `</head>`. Under `cfg.scriptPolicy = spNone` only the analytics
  ## beacon (if configured) remains, and the head's one other `<script>` is
  ## the JSON-LD data block.
  renderPageHeadHtml(head, docsPageScripts(cfg), cfg.scriptPolicy, cfg.csp)

proc renderSiteFrame*[R, E](r: R; vm: SiteShellViewModel): E =
  ## The rendering shell: header/nav/main/footer regions carrying stable
  ## `regionId` anchors for later navigation/search wiring, title
  ## injection in the header, and a distinct not-found rendering shape
  ## in the main region so a 404 page is structurally identifiable, not
  ## just text-different. The nav region renders M3's real navigation
  ## ViewModel (`navigation_view.renderNavigation`) -- a variable-length
  ## tree the static `ui` DSL can't express, so (like
  ## `markdown_page.nim` before it) this is built directly against the
  ## generic renderer backend API rather than the DSL.
  let frame = r.createElement("div")
  r.setAttribute(frame, "class", frameClass)
  r.appendChild(frame, renderSkipLink[R, E](r))

  let header = r.createElement("header")
  r.setAttribute(header, "id", regionId(prHeader))
  r.setAttribute(header, "class", headerClass)
  let h1 = r.createElement("h1")
  r.setAttribute(h1, "class", titleClass)
  r.appendChild(h1, r.createTextNode(vm.pageTitle))
  r.appendChild(header, h1)
  r.appendChild(header, renderSearchBox[R, E](r, vm.search))
  r.appendChild(header, renderThemeToggle[R, E](r, vm.theme))
  r.appendChild(frame, header)

  let navEl = r.createElement("nav")
  r.setAttribute(navEl, "id", regionId(prNav))
  r.setAttribute(navEl, "class", navClass)
  r.appendChild(navEl, renderNavigation[R, E](r, vm.navigation))
  r.appendChild(frame, navEl)

  let mainEl = r.createElement("main")
  r.setAttribute(mainEl, "id", regionId(prMain))
  r.setAttribute(mainEl, "class", mainClass)
  r.setAttribute(mainEl, "tabindex", "-1")
  if vm.pageKind == pkNotFound:
    let notFoundDiv = r.createElement("div")
    r.setAttribute(notFoundDiv, "class", notFoundClass)
    r.appendChild(notFoundDiv, r.createTextNode("Page not found"))
    r.appendChild(mainEl, notFoundDiv)
  elif vm.pageKind == pkRedirect:
    let redirectDiv = r.createElement("div")
    r.setAttribute(redirectDiv, "class", redirectClass)
    r.appendChild(redirectDiv, r.createTextNode("This page has moved to "))
    let a = r.createElement("a")
    r.setAttribute(a, "class", redirectLinkClass)
    r.setAttribute(a, "href", vm.redirectTo)
    r.appendChild(a, r.createTextNode(vm.redirectTo))
    r.appendChild(redirectDiv, a)
    r.appendChild(mainEl, redirectDiv)
  else:
    let bodyDiv = r.createElement("div")
    r.setAttribute(bodyDiv, "class", bodyClass)
    r.appendChild(bodyDiv, r.createTextNode(vm.bodyText))
    r.appendChild(mainEl, bodyDiv)
  r.appendChild(frame, mainEl)

  ## Prev/next pagination at the bottom of the content column (a sibling after
  ## `.docs-main`), matching every page frame -- not inside the nav region.
  r.appendChild(frame, renderAdjacent[R, E](r, vm.navigation.previous, vm.navigation.next))

  let footerEl = r.createElement("footer")
  r.setAttribute(footerEl, "id", regionId(prFooter))
  r.setAttribute(footerEl, "class", footerClass)
  r.appendChild(frame, footerEl)

  ## M5 deliverable 2: the keyboard-triggered search overlay, rendered
  ## once per page as the frame's last child so it never disturbs the
  ## front-anchored header/nav/main structural traversals the live
  ## wiring (and the hydration/browser-mount suites) rely on.
  r.appendChild(frame, renderSearchOverlay[R, E](r, SearchViewModel(),
    search = vm.serverSearch))

  frame

proc renderSiteFrameHtml*(vm: SiteShellViewModel): string =
  ## SSR string-mode rendering -- same shape as `renderSiteFrame`.
  "<div class=\"" & frameClass & "\">" &
    renderSkipLinkHtml() &
    renderDocsHeaderHtml(vm.pageTitle, vm.search, vm.theme, vm.siteLogo, vm.logoHref, vm.chrome) &
    "<nav id=\"" & regionId(prNav) & "\" class=\"" & navClass & "\">" &
      renderNavigationHtml(vm.navigation, renderSidebarExtrasHtml(vm.chrome, vm.theme)) &
    "</nav>" &
    "<main id=\"" & regionId(prMain) & "\" class=\"" & mainClass & "\" tabindex=\"-1\">" &
      renderContentTitleHtml(vm.pageTitle, vm.chrome) &
      (if vm.pageKind == pkNotFound:
         "<div class=\"" & notFoundClass & "\">Page not found</div>"
       elif vm.pageKind == pkRedirect:
         "<div class=\"" & redirectClass & "\">This page has moved to " &
           "<a class=\"" & redirectLinkClass & "\" href=\"" & escapeAttr(vm.redirectTo) & "\">" &
           escapeHtml(vm.redirectTo) & "</a></div>"
       else:
         "<div class=\"" & bodyClass & "\">" & escapeHtml(vm.bodyText) & "</div>") &
    "</main>" &
    renderAdjacentHtml(vm.navigation.previous, vm.navigation.next) &
    renderNeedHelpHtml(vm.chrome) &
    renderDocsFooterHtml(vm.footerHtml) &
    renderSearchOverlayHtml(SearchViewModel(), search = vm.serverSearch) &
  "</div>"

proc renderErrorFallbackHtml*(vm: SiteShellViewModel): string =
  ## M6 deliverable 2: the HTTP-500 fallback body `ssr.renderRoute` serves
  ## when a page's body render raises -- the full site chrome
  ## (skip link, header, nav, footer, search overlay) kept intact, with a
  ## small `.docs-error-fallback` message standing in for the page content
  ## instead of the exception propagating out of `renderRoute`. Structured
  ## the exact same way as `renderSiteFrameHtml` so a served 500 is
  ## visually a normal page with an error notice, not a bare stack trace.
  "<div class=\"" & frameClass & "\">" &
    renderSkipLinkHtml() &
    renderDocsHeaderHtml(vm.pageTitle, vm.search, vm.theme, vm.siteLogo, vm.logoHref, vm.chrome) &
    "<nav id=\"" & regionId(prNav) & "\" class=\"" & navClass & "\">" &
      renderNavigationHtml(vm.navigation, renderSidebarExtrasHtml(vm.chrome, vm.theme)) &
    "</nav>" &
    "<main id=\"" & regionId(prMain) & "\" class=\"" & mainClass & "\" tabindex=\"-1\">" &
      "<div class=\"" & errorFallbackClass & "\">" & escapeHtml(errorFallbackText) & "</div>" &
    "</main>" &
    renderAdjacentHtml(vm.navigation.previous, vm.navigation.next) &
    renderNeedHelpHtml(vm.chrome) &
    renderDocsFooterHtml(vm.footerHtml) &
    renderSearchOverlayHtml(SearchViewModel(), search = vm.serverSearch) &
  "</div>"
