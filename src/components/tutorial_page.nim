## isonim-docs Layer 4 — the tutorial page frame (M10 deliverable 1).
##
## Wraps `tutorial.renderTutorial`/`renderTutorialHtml` in the exact same
## header/nav/main/footer region shape and stable `regionId` anchors as
## `components/symbol_reference_page.renderSymbolReferencePage` and
## `components/api_reference_page.renderApiReferencePage` -- so a
## `pkTutorial` page carries the identical site chrome as every other page
## kind, with the interactive tutorial layout (progress rail + markdown
## body) as its `<main>`. The tutorial rail renders ABOVE the page's own
## markdown body (`markdown_view.renderMarkdownDoc`), so a reader sees
## their step progress before scrolling into the step content. The tree
## (`renderTutorialPage`) and SSR string (`renderTutorialPageHtml`) paths
## are kept byte-for-byte in lock-step, exactly like every other page frame.

import ../core/tutorial_vm
import ../core/markdown_vm
import ../core/shell_vm
import ../core/navigation_vm
import ../core/search_vm
import ../core/theme_vm
import ../core/config
import ./shell
import ./navigation_view
import ./tutorial
import ./markdown_view
import ./search_view
import ./theme_toggle

proc renderTutorialPage*[R, E](r: R; pageTitle: string; tut: TutorialViewModel;
                               blocks: seq[Block] = @[];
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

  let mainEl = r.createElement("main")
  r.setAttribute(mainEl, "id", regionId(prMain))
  r.setAttribute(mainEl, "class", mainClass)
  r.setAttribute(mainEl, "tabindex", "-1")
  r.appendChild(mainEl, renderTutorial[R, E](r, tut))
  r.appendChild(mainEl, renderMarkdownBody[R, E](r, blocks))
  r.appendChild(frame, mainEl)

  ## Prev/next pagination at the bottom of the content column (sibling after
  ## `.docs-main`), matching the other page frames.
  r.appendChild(frame, renderAdjacent[R, E](r, navigation.previous, navigation.next))

  let footerEl = r.createElement("footer")
  r.setAttribute(footerEl, "id", regionId(prFooter))
  r.setAttribute(footerEl, "class", footerClass)
  r.appendChild(frame, footerEl)

  r.appendChild(frame, renderSearchOverlay[R, E](r, SearchViewModel()))
  frame

proc renderTutorialPageHtml*(pageTitle: string; tut: TutorialViewModel;
                             blocks: seq[Block] = @[];
                             navigation: NavigationViewModel = NavigationViewModel();
                             search: SearchViewModel = SearchViewModel();
                             theme: ThemeViewModel = ThemeViewModel();
                             siteLogo = ""; logoHref = ""; footerHtml = "";
                             chrome = DocsChrome()): string =
  ## M3 optional chrome hooks (see `shell.renderDocsHeaderHtml`/
  ## `renderDocsFooterHtml`) -- empty by default, byte-for-byte pre-M3.
  ## `chrome` is the metacraft-theme-parity M1 bundle -- a default
  ## `DocsChrome()` renders every new hook as nothing (byte-for-byte pre-M1).
  "<div class=\"" & frameClass & "\">" &
    renderSkipLinkHtml() &
    renderDocsHeaderHtml(pageTitle, search, theme, siteLogo, logoHref, chrome) &
    "<nav id=\"" & regionId(prNav) & "\" class=\"" & navClass & "\">" &
      renderNavigationHtml(navigation, renderSidebarExtrasHtml(chrome, theme)) & "</nav>" &
    "<main id=\"" & regionId(prMain) & "\" class=\"" & mainClass & "\" tabindex=\"-1\">" &
      renderContentTitleHtml(pageTitle, chrome) &
      renderTutorialHtml(tut) &
      renderMarkdownBodyHtml(blocks) &
    "</main>" &
    renderAdjacentHtml(navigation.previous, navigation.next) &
    renderNeedHelpHtml(chrome) &
    renderDocsFooterHtml(footerHtml) &
    renderSearchOverlayHtml(SearchViewModel()) &
  "</div>"
