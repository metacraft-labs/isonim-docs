## isonim-docs Layer 4 — the markdown page frame (M2 deliverable 4).
##
## Wraps `markdown_view.renderMarkdownBody`/`renderMarkdownBodyHtml` in
## the exact same header/nav/main/footer region shape and stable
## `regionId` anchors as `components/shell.renderSiteFrame` -- reusing
## `shell.nim`'s own class constants and `shell_vm.regionId` rather than
## redefining them -- so a `pkMarkdown` page looks structurally identical
## to an M0/M1 `pkDoc`/`pkIndex` page except for its body content. Built
## directly against the generic renderer backend API
## (`createElement`/`appendChild`/`setAttribute`/`createTextNode`) rather
## than the `ui` DSL, matching `markdown_view.nim`'s own style: the
## body's dynamic block list has to be assembled with `r.appendChild` in
## a loop either way (see that module's docstring), so composing the
## whole frame the same direct way keeps one style throughout instead of
## mixing it with the DSL for the static header/nav/footer chrome.

import ../core/markdown_vm
import ../core/shell_vm
import ../core/navigation_vm
import ../core/search_vm
import ../core/theme_vm
import ../core/config
import ./shell
import ./navigation_view
import ./markdown_view
import ./search_view
import ./theme_toggle

proc renderMarkdownPage*[R, E](r: R; pageTitle: string; blocks: seq[Block];
                                navigation: NavigationViewModel = NavigationViewModel();
                                search: SearchViewModel = SearchViewModel();
                                theme: ThemeViewModel = ThemeViewModel()): E =
  let frame = r.createElement("div")
  r.setAttribute(frame, "class", frameClass)
  r.appendChild(frame, renderSkipLink[R, E](r))

  let header = r.createElement("header")
  r.setAttribute(header, "id", regionId(prHeader))
  r.setAttribute(header, "class", headerClass)
  let h1 = r.createElement("h1")
  r.setAttribute(h1, "class", titleClass)
  r.appendChild(h1, r.createTextNode(pageTitle))
  r.appendChild(header, h1)
  r.appendChild(header, renderSearchBox[R, E](r, search))
  r.appendChild(header, renderThemeToggle[R, E](r, theme))
  r.appendChild(frame, header)

  let navEl = r.createElement("nav")
  r.setAttribute(navEl, "id", regionId(prNav))
  r.setAttribute(navEl, "class", navClass)
  r.appendChild(navEl, renderNavigation[R, E](r, navigation))
  r.appendChild(frame, navEl)

  ## metacraft-theme-parity M6: a LANDING page (its body carries a `:::hero`)
  ## gets the wider content column (`mainWideClass`) and DROPS the prev/next
  ## pager -- a landing is not part of a linear article sequence, and the
  ## WebFlow home has none. Derived from `blocks` so this path and the
  ## SSR-string one stay byte-identical. A normal (non-hero) page is untouched.
  let landing = pageHasHero(blocks)
  let mainEl = r.createElement("main")
  r.setAttribute(mainEl, "id", regionId(prMain))
  r.setAttribute(mainEl, "class", if landing: mainClass & " " & mainWideClass else: mainClass)
  r.setAttribute(mainEl, "tabindex", "-1")
  r.appendChild(mainEl, renderMarkdownBody[R, E](r, blocks))
  r.appendChild(frame, mainEl)

  ## Prev/next pagination sits at the BOTTOM of the content column (a sibling
  ## after `.docs-main`), matching normal docs UX, rather than inside the nav
  ## region above the H1 -- but never on a landing page (see above).
  if not landing:
    r.appendChild(frame, renderAdjacent[R, E](r, navigation.previous, navigation.next))

  let footerEl = r.createElement("footer")
  r.setAttribute(footerEl, "id", regionId(prFooter))
  r.setAttribute(footerEl, "class", footerClass)
  r.appendChild(frame, footerEl)

  ## M5 deliverable 2: the keyboard-triggered search overlay (see
  ## `components/shell.renderSiteFrame`) -- last child of the frame.
  r.appendChild(frame, renderSearchOverlay[R, E](r, SearchViewModel()))

  frame

proc renderMarkdownPageHtml*(pageTitle: string; blocks: seq[Block];
                              navigation: NavigationViewModel = NavigationViewModel();
                              search: SearchViewModel = SearchViewModel();
                              theme: ThemeViewModel = ThemeViewModel();
                              siteLogo = ""; logoHref = ""; footerHtml = "";
                              chrome = DocsChrome()): string =
  ## `siteLogo`/`logoHref`/`footerHtml` are the M3 optional chrome hooks,
  ## threaded from `DocsConfig` by the SSR entry; empty by default so the
  ## header/footer stay byte-for-byte the pre-M3 markup (see
  ## `shell.renderDocsHeaderHtml`/`renderDocsFooterHtml`). `chrome` is the
  ## metacraft-theme-parity M1 bundle -- a default `DocsChrome()` renders every
  ## new hook (header nav, sidebar social + pill toggle, content `<h1>` +
  ## last-updated, need-help block) as nothing, so the page stays byte-for-byte
  ## pre-M1.
  ## metacraft-theme-parity M6: a LANDING page (its body carries a `:::hero`)
  ## renders the `<main>` with the extra `mainWideClass` (wider content column)
  ## and OMITS the prev/next pager -- kept in lock-step with the MockRenderer
  ## `renderMarkdownPage` above by deriving both from `blocks`. A normal
  ## (non-hero) page's `<main>` and pager are byte-for-byte the pre-M6 markup.
  let landing = pageHasHero(blocks)
  let mainCls = if landing: mainClass & " " & mainWideClass else: mainClass
  "<div class=\"" & frameClass & "\">" &
    renderSkipLinkHtml() &
    renderDocsHeaderHtml(pageTitle, search, theme, siteLogo, logoHref, chrome) &
    "<nav id=\"" & regionId(prNav) & "\" class=\"" & navClass & "\">" &
      renderNavigationHtml(navigation, renderSidebarExtrasHtml(chrome, theme)) & "</nav>" &
    "<main id=\"" & regionId(prMain) & "\" class=\"" & mainCls & "\" tabindex=\"-1\">" &
      renderContentTitleHtml(pageTitle, chrome) &
      renderMarkdownBodyHtml(blocks) &
    "</main>" &
    (if landing: "" else: renderAdjacentHtml(navigation.previous, navigation.next)) &
    renderNeedHelpHtml(chrome) &
    renderDocsFooterHtml(footerHtml) &
    renderSearchOverlayHtml(SearchViewModel()) &
  "</div>"
