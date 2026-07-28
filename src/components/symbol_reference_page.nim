## isonim-docs Layer 4 — the symbol reference page frame (M8 deliverable 1).
##
## Wraps `symbol_reference.renderSymbolReference`/`renderSymbolReferenceHtml`
## in the exact same header/nav/main/footer region shape and stable
## `regionId` anchors as `components/markdown_page.renderMarkdownPage` and
## `components/api_reference_page.renderApiReferencePage` -- reusing
## `shell.nim`'s own class constants and `shell_vm.regionId` -- so a
## `pkSymbolReference` page carries the identical site chrome as every other
## page kind, with the two-column symbol reference layout as its `<main>`
## body. The tree (`renderSymbolReferencePage`) and SSR string
## (`renderSymbolReferencePageHtml`) paths are kept byte-for-byte in
## lock-step, exactly like `api_reference_page.nim`.

import ../core/symbol_reference_vm
import ../core/shell_vm
import ../core/navigation_vm
import ../core/search_vm
import ../core/theme_vm
import ../core/config
import ./shell
import ./navigation_view
import ./symbol_reference
import ./search_view
import ./theme_toggle

proc renderSymbolReferencePage*[R, E](r: R; pageTitle: string; vm: SymbolReferenceViewModel;
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
  r.appendChild(mainEl, renderSymbolReference[R, E](r, vm))
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

proc renderSymbolReferencePageHtml*(pageTitle: string; vm: SymbolReferenceViewModel;
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
      renderSymbolReferenceHtml(vm) &
    "</main>" &
    renderAdjacentHtml(navigation.previous, navigation.next) &
    renderNeedHelpHtml(chrome) &
    renderDocsFooterHtml(footerHtml) &
    renderSearchOverlayHtml(SearchViewModel()) &
  "</div>"
