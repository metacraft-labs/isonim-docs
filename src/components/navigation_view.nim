## isonim-docs Layer 2 — rendering for the navigation ViewModel
## (`src/core/navigation_vm.nim`, M3 deliverable 1).
##
## Four distinct nav landmarks -- breadcrumbs, sidebar, table of
## contents, previous/next pagination -- nested inside the rendering
## shell's single stable `regionId(prNav)` slot (`shell_vm.nim`'s own
## docstring calls that slot out as exactly where M3's navigation
## attaches). Every list here is variable-length, so -- like
## `markdown_view.nim` before it -- these are written directly against
## the generic renderer backend API and plain escaped string building,
## not the static `ui` DSL.

import isonim/ssr/escape
import ../core/navigation_vm
import ../core/markdown_vm

const
  navRegionClass* = "docs-navigation"
  navDrawerToggleClass* = "docs-nav-drawer-toggle"
  navDrawerToggleLabel* = "Menu"
  navDrawerBodyClass* = "docs-nav-drawer-body"
  navDrawerBodyId* = "docs-nav-drawer-body"
  breadcrumbNavClass* = "docs-nav-breadcrumbs"
  breadcrumbListClass* = "docs-nav-breadcrumb-list"
  breadcrumbItemClass* = "docs-nav-breadcrumb"
  breadcrumbCurrentClass* = "docs-nav-breadcrumb-current"
  sidebarNavClass* = "docs-nav-sidebar"
  sidebarSectionClass* = "docs-nav-section"
  sidebarSectionExpandedClass* = "docs-nav-section-expanded"
  sidebarSectionTitleClass* = "docs-nav-section-title"
  sidebarChildrenClass* = "docs-nav-section-children"
  sidebarListClass* = "docs-nav-section-list"
  sidebarItemClass* = "docs-nav-item"
  sidebarItemActiveClass* = "docs-nav-item-active"
  sidebarExternalIconClass* = "docs-nav-external-icon"
  tocNavClass* = "docs-nav-toc"
  tocListClass* = "docs-nav-toc-list"
  tocItemClass* = "docs-nav-toc-item"
  adjacentNavClass* = "docs-nav-adjacent"
  prevLinkClass* = "docs-nav-prev"
  nextLinkClass* = "docs-nav-next"

# --- MockRenderer / browser tree mode -----------------------------------

proc renderBreadcrumbs[R, E](r: R; crumbs: seq[Breadcrumb]): E =
  let nav = r.createElement("nav")
  r.setAttribute(nav, "class", breadcrumbNavClass)
  r.setAttribute(nav, "aria-label", "breadcrumbs")
  let list = r.createElement("ol")
  r.setAttribute(list, "class", breadcrumbListClass)
  for crumb in crumbs:
    let li = r.createElement("li")
    r.setAttribute(li, "class", breadcrumbItemClass)
    if crumb.isCurrent:
      let span = r.createElement("span")
      r.setAttribute(span, "class", breadcrumbCurrentClass)
      r.setAttribute(span, "aria-current", "page")
      r.appendChild(span, r.createTextNode(crumb.title))
      r.appendChild(li, span)
    else:
      let a = r.createElement("a")
      r.setAttribute(a, "href", crumb.routePath)
      r.appendChild(a, r.createTextNode(crumb.title))
      r.appendChild(li, a)
    r.appendChild(list, li)
  r.appendChild(nav, list)
  nav

proc renderSidebarItem[R, E](r: R; item: NavItem): E =
  let li = r.createElement("li")
  let itemClass =
    if item.isActive: sidebarItemClass & " " & sidebarItemActiveClass
    else: sidebarItemClass
  r.setAttribute(li, "class", itemClass)
  let a = r.createElement("a")
  r.setAttribute(a, "href", item.routePath)
  if item.isActive:
    r.setAttribute(a, "aria-current", "page")
  if isExternalNavLink(item.routePath):
    r.setAttribute(a, "target", "_blank")
    r.setAttribute(a, "rel", "noopener")
    r.appendChild(a, r.createTextNode(item.title))
    let icon = r.createElement("span")
    r.setAttribute(icon, "class", sidebarExternalIconClass)
    r.setAttribute(icon, "aria-hidden", "true")
    r.appendChild(icon, r.createTextNode(" \xE2\x86\x97"))
    r.appendChild(a, icon)
  else:
    r.appendChild(a, r.createTextNode(item.title))
  r.appendChild(li, a)
  li

proc renderSidebarSection[R, E](r: R; section: NavSection): E =
  ## Recurses through `section.children` -- M5 corrective deliverable 1:
  ## an infinite-depth tree, not a flat run of sections -- rendering
  ## each nested level as a `.docs-nav-section-children` wrapper inside
  ## its own parent section. The section title (when non-empty --
  ## the ungrouped top level has none) is a real `<button>`, not a
  ## plain `<span>`: `main_web.wireSidebarCollapse` wires its click to
  ## toggle `.docs-nav-section-expanded` + `aria-expanded` on this same
  ## node, and persist that choice to `localStorage` keyed by
  ## `section.key`, so click-to-collapse state survives a reload.
  let sectionEl = r.createElement("div")
  let sectionClass =
    if section.isExpanded: sidebarSectionClass & " " & sidebarSectionExpandedClass
    else: sidebarSectionClass
  r.setAttribute(sectionEl, "class", sectionClass)
  r.setAttribute(sectionEl, "data-nav-key", section.key)
  if section.title.len > 0:
    let toggleEl = r.createElement("button")
    r.setAttribute(toggleEl, "type", "button")
    r.setAttribute(toggleEl, "class", sidebarSectionTitleClass)
    r.setAttribute(toggleEl, "aria-expanded", if section.isExpanded: "true" else: "false")
    r.appendChild(toggleEl, r.createTextNode(section.title))
    r.appendChild(sectionEl, toggleEl)
  if section.items.len > 0:
    let list = r.createElement("ul")
    r.setAttribute(list, "class", sidebarListClass)
    for item in section.items:
      r.appendChild(list, renderSidebarItem[R, E](r, item))
    r.appendChild(sectionEl, list)
  if section.children.len > 0:
    let childrenEl = r.createElement("div")
    r.setAttribute(childrenEl, "class", sidebarChildrenClass)
    for child in section.children:
      r.appendChild(childrenEl, renderSidebarSection[R, E](r, child))
    r.appendChild(sectionEl, childrenEl)
  sectionEl

proc renderSidebar[R, E](r: R; sidebar: SidebarViewModel): E =
  let nav = r.createElement("nav")
  r.setAttribute(nav, "class", sidebarNavClass)
  r.setAttribute(nav, "aria-label", "sidebar")
  for section in sidebar.sections:
    r.appendChild(nav, renderSidebarSection[R, E](r, section))
  nav

proc renderNavDrawerToggle[R, E](r: R): E =
  ## M5 corrective deliverable 1's <768px hamburger: always rendered (a
  ## real browser hides it above the breakpoint via CSS, see
  ## `assets/style.css`'s `.docs-nav-drawer-toggle` media query) rather
  ## than only rendered/hidden at build time -- an SSR page has no
  ## viewport to test against, only the client does.
  let btn = r.createElement("button")
  r.setAttribute(btn, "type", "button")
  r.setAttribute(btn, "class", navDrawerToggleClass)
  r.setAttribute(btn, "aria-expanded", "false")
  r.setAttribute(btn, "aria-controls", navDrawerBodyId)
  r.setAttribute(btn, "aria-label", navDrawerToggleLabel)
  r.appendChild(btn, r.createTextNode(navDrawerToggleLabel))
  btn

proc renderTocNodes[R, E](r: R; nodes: seq[HeadingNode]): E =
  let list = r.createElement("ul")
  r.setAttribute(list, "class", tocListClass)
  for node in nodes:
    let li = r.createElement("li")
    r.setAttribute(li, "class", tocItemClass)
    let a = r.createElement("a")
    r.setAttribute(a, "href", "#" & node.id)
    r.appendChild(a, r.createTextNode(node.text))
    r.appendChild(li, a)
    if node.children.len > 0:
      r.appendChild(li, renderTocNodes[R, E](r, node.children))
    r.appendChild(list, li)
  list

proc renderToc[R, E](r: R; toc: seq[HeadingNode]): E =
  let nav = r.createElement("nav")
  r.setAttribute(nav, "class", tocNavClass)
  r.setAttribute(nav, "aria-label", "table of contents")
  r.appendChild(nav, renderTocNodes[R, E](r, toc))
  nav

proc renderAdjacent*[R, E](r: R; previous, next: AdjacentPage): E =
  ## The previous/next pagination `<nav>`. Rendered by each page frame as a
  ## sibling AFTER `.docs-main` (bottom of the content column), NOT inside the
  ## nav region -- so, like normal docs UX, prev/next sits at the end of the
  ## article rather than above its H1, and it is never trapped inside the
  ## mobile off-canvas nav drawer.
  let nav = r.createElement("nav")
  r.setAttribute(nav, "class", adjacentNavClass)
  r.setAttribute(nav, "aria-label", "pagination")
  if previous.routePath.len > 0:
    let a = r.createElement("a")
    r.setAttribute(a, "class", prevLinkClass)
    r.setAttribute(a, "href", previous.routePath)
    r.appendChild(a, r.createTextNode(previous.title))
    r.appendChild(nav, a)
  if next.routePath.len > 0:
    let a = r.createElement("a")
    r.setAttribute(a, "class", nextLinkClass)
    r.setAttribute(a, "href", next.routePath)
    r.appendChild(a, r.createTextNode(next.title))
    r.appendChild(nav, a)
  nav

proc renderNavigation*[R, E](r: R; vm: NavigationViewModel): E =
  ## The full nav region: the <768px hamburger toggle, then the
  ## breadcrumb/sidebar/TOC landmarks (in reading order) inside a
  ## `.docs-nav-drawer-body` wrapper -- the one element
  ## `main_web.wireNavDrawer`'s open/close and focus trap operate on, and CSS
  ## turns into an off-canvas drawer below the mobile breakpoint. The outer
  ## `.docs-navigation` container itself is unchanged (same class, same first
  ## two callers `getAttribute` against it directly). The prev/next pagination
  ## is deliberately NOT part of this region -- each page frame renders it via
  ## `renderAdjacent` as a sibling after `.docs-main` (bottom of the content),
  ## so it reads at the end of the article, not above its H1, and is never
  ## trapped in the mobile drawer.
  let container = r.createElement("div")
  r.setAttribute(container, "class", navRegionClass)
  r.appendChild(container, renderNavDrawerToggle[R, E](r))
  let body = r.createElement("div")
  r.setAttribute(body, "class", navDrawerBodyClass)
  r.setAttribute(body, "id", navDrawerBodyId)
  r.setAttribute(body, "data-open", "false")
  r.appendChild(body, renderBreadcrumbs[R, E](r, vm.breadcrumbs))
  r.appendChild(body, renderSidebar[R, E](r, vm.sidebar))
  r.appendChild(body, renderToc[R, E](r, vm.toc))
  r.appendChild(container, body)
  container

# --- SSR string mode ------------------------------------------------------

proc renderBreadcrumbsHtml*(crumbs: seq[Breadcrumb]): string =
  result = "<nav class=\"" & breadcrumbNavClass & "\" aria-label=\"breadcrumbs\"><ol class=\"" &
    breadcrumbListClass & "\">"
  for crumb in crumbs:
    result.add "<li class=\"" & breadcrumbItemClass & "\">"
    if crumb.isCurrent:
      result.add "<span class=\"" & breadcrumbCurrentClass & "\" aria-current=\"page\">" &
        escapeHtml(crumb.title) & "</span>"
    else:
      result.add "<a href=\"" & escapeAttr(crumb.routePath) & "\">" & escapeHtml(crumb.title) & "</a>"
    result.add "</li>"
  result.add "</ol></nav>"

proc renderSidebarItemHtml(item: NavItem): string =
  let itemClass =
    if item.isActive: sidebarItemClass & " " & sidebarItemActiveClass
    else: sidebarItemClass
  let currentAttr = if item.isActive: " aria-current=\"page\"" else: ""
  if isExternalNavLink(item.routePath):
    "<li class=\"" & itemClass & "\"><a href=\"" & escapeAttr(item.routePath) &
      "\" target=\"_blank\" rel=\"noopener\"" & currentAttr & ">" & escapeHtml(item.title) &
      "<span class=\"" & sidebarExternalIconClass & "\" aria-hidden=\"true\"> \xE2\x86\x97</span></a></li>"
  else:
    "<li class=\"" & itemClass & "\"><a href=\"" & escapeAttr(item.routePath) & "\"" &
      currentAttr & ">" & escapeHtml(item.title) & "</a></li>"

proc renderSidebarSectionHtml(section: NavSection): string =
  ## SSR string-mode counterpart of `renderSidebarSection` -- same
  ## recursive-tree shape, same `<button>`-not-`<span>` title markup.
  let sectionClass =
    if section.isExpanded: sidebarSectionClass & " " & sidebarSectionExpandedClass
    else: sidebarSectionClass
  result = "<div class=\"" & sectionClass & "\" data-nav-key=\"" & escapeAttr(section.key) & "\">"
  if section.title.len > 0:
    result.add "<button type=\"button\" class=\"" & sidebarSectionTitleClass & "\" aria-expanded=\"" &
      (if section.isExpanded: "true" else: "false") & "\">" & escapeHtml(section.title) & "</button>"
  if section.items.len > 0:
    result.add "<ul class=\"" & sidebarListClass & "\">"
    for item in section.items:
      result.add renderSidebarItemHtml(item)
    result.add "</ul>"
  if section.children.len > 0:
    result.add "<div class=\"" & sidebarChildrenClass & "\">"
    for child in section.children:
      result.add renderSidebarSectionHtml(child)
    result.add "</div>"
  result.add "</div>"

proc renderSidebarHtml*(sidebar: SidebarViewModel; extrasHtml = ""): string =
  ## `extrasHtml` (metacraft-theme-parity M1, Gap C) is an OPTIONAL pre-rendered
  ## HTML slot appended at the BOTTOM of `.docs-nav-sidebar` -- the social links
  ## + pill theme toggle (`shell.renderSidebarExtrasHtml`). Empty by default
  ## (the framework default), so the sidebar is byte-for-byte pre-M1. SSR-string
  ## only, like `shell.renderDocsFooterHtml`'s `footerHtml`: it is raw
  ## site-config HTML with no generic-renderer node representation.
  result = "<nav class=\"" & sidebarNavClass & "\" aria-label=\"sidebar\">"
  for section in sidebar.sections:
    result.add renderSidebarSectionHtml(section)
  result.add extrasHtml
  result.add "</nav>"

proc renderNavDrawerToggleHtml(): string =
  "<button type=\"button\" class=\"" & navDrawerToggleClass & "\" aria-expanded=\"false\" aria-controls=\"" &
    navDrawerBodyId & "\" aria-label=\"" & escapeAttr(navDrawerToggleLabel) & "\">" &
    escapeHtml(navDrawerToggleLabel) & "</button>"

proc renderTocNodesHtml(nodes: seq[HeadingNode]): string =
  result = "<ul class=\"" & tocListClass & "\">"
  for node in nodes:
    result.add "<li class=\"" & tocItemClass & "\"><a href=\"#" & escapeAttr(node.id) & "\">" &
      escapeHtml(node.text) & "</a>"
    if node.children.len > 0:
      result.add renderTocNodesHtml(node.children)
    result.add "</li>"
  result.add "</ul>"

proc renderTocHtml*(toc: seq[HeadingNode]): string =
  "<nav class=\"" & tocNavClass & "\" aria-label=\"table of contents\">" & renderTocNodesHtml(toc) & "</nav>"

proc renderAdjacentHtml*(previous, next: AdjacentPage): string =
  result = "<nav class=\"" & adjacentNavClass & "\" aria-label=\"pagination\">"
  if previous.routePath.len > 0:
    result.add "<a class=\"" & prevLinkClass & "\" href=\"" & escapeAttr(previous.routePath) & "\">" &
      escapeHtml(previous.title) & "</a>"
  if next.routePath.len > 0:
    result.add "<a class=\"" & nextLinkClass & "\" href=\"" & escapeAttr(next.routePath) & "\">" &
      escapeHtml(next.title) & "</a>"
  result.add "</nav>"

proc renderNavigationHtml*(vm: NavigationViewModel; sidebarExtrasHtml = ""): string =
  ## `sidebarExtrasHtml` (metacraft-theme-parity M1, Gap C) is threaded straight
  ## into `renderSidebarHtml`'s bottom-of-sidebar slot; empty by default so the
  ## nav region is byte-for-byte pre-M1.
  "<div class=\"" & navRegionClass & "\">" &
    renderNavDrawerToggleHtml() &
    "<div class=\"" & navDrawerBodyClass & "\" id=\"" & navDrawerBodyId & "\" data-open=\"false\">" &
      renderBreadcrumbsHtml(vm.breadcrumbs) &
      renderSidebarHtml(vm.sidebar, sidebarExtrasHtml) &
      renderTocHtml(vm.toc) &
    "</div>" &
  "</div>"
