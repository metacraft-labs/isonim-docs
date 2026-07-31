## isonim-docs Layer 3 — navigation ViewModels for the docs rendering
## shell (M3 deliverable 1), built on the real content graph M2 already
## produces: `content.ContentEntry` (front matter, section, order, slug)
## and `routes.RouteEntry` (the authoritative, matchable route path a
## page actually renders at).
##
## `RouteEntry.canonicalPath` -- not `ContentEntry.routePath` -- is the
## link target every nav ViewModel below points at. The two can
## legitimately disagree: M0/M1's `/guide/getting-started` binds to the
## flat `getting-started.md` file, whose own `content.nim`-derived route
## path is `/getting-started`. Routing already won that disagreement (the
## manifest is what `matchRoute` resolves against), so navigation follows
## routing's answer rather than forking a second opinion -- `navPage`
## below is the one place that pairing happens.
##
## Pure data + pure builders, no filesystem access anywhere (the
## `loadEntry` closure `buildNavPages` takes is the one platform-specific
## seam, injected exactly like `shell_vm.buildShellViewModel`'s
## `loadPage`), so this whole module is Tier-1-testable on both `nim c`
## and `nim js`.

import std/[algorithm, strutils]
import ./content
import ./routes
import ./markdown_vm

type
  NavPage* = object
    ## One page's flattened nav-relevant facts: routing's own canonical
    ## link target, plus the content graph's title/section/order/slug --
    ## everything the builders below need, with no further coupling to
    ## `RouteEntry`/`ContentEntry` themselves.
    routePath*: string
    title*: string
    section*: string
    order*: int
    slug*: string

  NavItem* = object
    ## One sidebar leaf: a page's link plus the active-nav selection flag.
    routePath*: string
    title*: string
    isActive*: bool

  NavSection* = object
    ## One sidebar group, now a recursive tree node (M5 corrective
    ## deliverable 1: infinite-depth sidebar): `key` is the FULL
    ## '/'-joined section path from the content root (""  for the
    ## ungrouped top-level pages, "guide" for a one-level section,
    ## "guide/advanced" for a nested one, etc. -- the same path
    ## `deriveSection` already produces for arbitrarily deep nested
    ## content dirs), `title` this node's OWN last-segment display
    ## label (not the full path -- a nested node under "Guide" just
    ## says "Advanced", not "Guide Advanced"), `items` the pages whose
    ## `section` is exactly `key` (not a descendant section), `children`
    ## any nested subsections one level down, and `isExpanded` the
    ## section-expansion-state default -- always open for the ungrouped
    ## top level, open for any node containing the active page (directly
    ## or via a descendant), collapsed otherwise, so the active route's
    ## whole ancestor chain auto-expands.
    key*: string
    title*: string
    items*: seq[NavItem]
    children*: seq[NavSection]
    isExpanded*: bool

  SidebarViewModel* = object
    sections*: seq[NavSection]

  Breadcrumb* = object
    title*: string
    routePath*: string
    isCurrent*: bool

  AdjacentPage* = object
    ## A previous/next link; a zero-value (`routePath == ""`) means there
    ## is no adjacent page in that direction (start/end of the reading
    ## order), the same empty-string-sentinel convention `content.nim`
    ## and `routes.nim` already use elsewhere in this codebase.
    title*: string
    routePath*: string

  NavigationViewModel* = object
    sidebar*: SidebarViewModel
    breadcrumbs*: seq[Breadcrumb]
    previous*: AdjacentPage
    next*: AdjacentPage
    toc*: seq[HeadingNode] ## The *active* page's own on-page section
                           ## table of contents -- `markdown_vm`'s
                           ## already-stable heading tree, reused as-is
                           ## rather than redefined here.

proc humanizeKey*(key: string): string =
  ## Turns a raw section/slug key ("guide", "getting-started") into a
  ## display label ("Guide", "Getting Started"): title-cases every
  ## '/'- and '-'-separated word and joins them with a space. Empty
  ## input (the ungrouped top-level section) stays empty.
  if key.len == 0: return ""
  var words: seq[string] = @[]
  for segment in key.split('/'):
    for word in segment.split({'-', '_'}):
      if word.len > 0:
        words.add word[0].toUpperAscii & word[1 .. ^1]
  words.join(" ")

proc sectionRank(section: string; sectionOrder: seq[string]): int =
  ## A section's rank for ordering: the index of its TOP-LEVEL segment in the
  ## consumer-supplied `sectionOrder`. Sections not listed (and every section
  ## when `sectionOrder` is empty) rank equal-and-last, so the caller's
  ## alphabetical tiebreak then applies -- i.e. an empty `sectionOrder`
  ## preserves the historical alphabetical section order exactly.
  if sectionOrder.len == 0: return int.high
  let top = if '/' in section: section.split('/')[0] else: section
  let idx = sectionOrder.find(top)
  if idx >= 0: idx else: int.high

proc sortNavPages*(pages: seq[NavPage]; sectionOrder: seq[string] = @[]): seq[NavPage] =
  ## The one stable nav reading order every builder below shares:
  ## (section-rank, section, front-matter order, slug) -- exactly `content.nim`'s
  ## `loadContentEntries` sort, so the sidebar and the prev/next chain never
  ## disagree on page order. `sectionOrder` (optional, from `DocsConfig`) puts
  ## the named sections in that order; unlisted sections and an empty
  ## `sectionOrder` fall back to alphabetical, unchanged.
  result = pages
  result.sort(proc(a, b: NavPage): int =
    if a.section != b.section:
      let ra = sectionRank(a.section, sectionOrder)
      let rb = sectionRank(b.section, sectionOrder)
      if ra != rb: return cmp(ra, rb)
      return cmp(a.section, b.section)
    if a.order != b.order: return cmp(a.order, b.order)
    cmp(a.slug, b.slug))

proc isExternalNavLink*(routePath: string): bool =
  ## True for a nav item pointing off-site rather than at one of this
  ## site's own routes -- the same "absolute in-site path" test
  ## `main_web.isInSiteHref` uses for soft-nav eligibility, inverted:
  ## any `NavPage`/`NavItem.routePath` NOT starting with a single "/"
  ## (an `https://...` URL, a protocol-relative "//host/..." link, a
  ## bare "mailto:", etc.) is external. A nav config that wants an
  ## external link in the tree (alongside content-dir-derived pages)
  ## just supplies one with such a `routePath` -- no separate "is this
  ## external" flag needed anywhere in the pipeline.
  not (routePath.len > 0 and routePath[0] == '/' and (routePath.len == 1 or routePath[1] != '/'))

proc insertNavItem(parent: var NavSection; segments: seq[string]; parentKey: string; item: NavItem) =
  ## Recursively walks/creates the section path `segments` (the page's
  ## own `section` string split on '/') under `parent`, finally adding
  ## `item` to the leaf node's own `items` -- the one place the flat
  ## `section` string a page carries turns into its place in the
  ## infinite-depth tree.
  if segments.len == 0:
    parent.items.add item
    return
  let segment = segments[0]
  let childKey = if parentKey.len == 0: segment else: parentKey & "/" & segment
  var idx = -1
  for i in 0 ..< parent.children.len:
    if parent.children[i].key == childKey:
      idx = i
      break
  if idx < 0:
    parent.children.add NavSection(key: childKey, title: humanizeKey(segment))
    idx = parent.children.len - 1
  insertNavItem(parent.children[idx], segments[1 ..< segments.len], childKey, item)

proc computeNavExpansion(node: var NavSection; activeRoutePath: string): bool =
  ## Post-order: a node auto-expands iff it (or any descendant) holds
  ## the active page -- the "active route's ancestor path auto-expands"
  ## default -- propagating the answer back up so every ancestor on the
  ## way to the active leaf expands too, not just the immediate parent.
  var hasActive = false
  for item in node.items:
    if item.routePath == activeRoutePath: hasActive = true
  for i in 0 ..< node.children.len:
    if computeNavExpansion(node.children[i], activeRoutePath): hasActive = true
  node.isExpanded = hasActive
  hasActive

proc forceExpandAll(node: var NavSection) =
  ## M1 (robust no-JS nav): unconditionally mark this node and every
  ## descendant expanded, overriding the active-path-only auto-expand
  ## default. Used when `DocsConfig.expandAllNavSections` is on so the
  ## sidebar's real `<a>` links are visible/navigable without the client JS
  ## (the collapsed-section CSS `display:none`s them otherwise). JS
  ## click-to-collapse still toggles individual sections on top of this.
  node.isExpanded = true
  for i in 0 ..< node.children.len:
    forceExpandAll(node.children[i])

proc buildSidebar*(pages: seq[NavPage]; activeRoutePath: string;
                   sectionOrder: seq[string] = @[];
                   expandAll = false): SidebarViewModel =
  ## Builds the infinite-depth sidebar tree (M5 corrective deliverable
  ## 1): every page's full `section` path (however deeply nested --
  ## "guide", "guide/advanced", "guide/advanced/tips", ...) becomes its
  ## place in a recursive `NavSection` tree, rather than a flat list of
  ## same-key runs. The ungrouped top level (`section == ""`) stays a
  ## real top-level `NavSection` with an empty key/title, exactly as
  ## before, so single-level content (no nested dirs at all) renders
  ## byte-for-byte the same shape it always has -- infinite depth is
  ## additive, not a breaking reshape of the shallow case.
  let sorted = sortNavPages(pages, sectionOrder)
  var root = NavSection(key: "", title: "", isExpanded: true)
  for page in sorted:
    let item = NavItem(routePath: page.routePath, title: page.title,
                        isActive: page.routePath == activeRoutePath)
    let segments = if page.section.len == 0: @[] else: page.section.split('/')
    insertNavItem(root, segments, "", item)
  for i in 0 ..< root.children.len:
    discard computeNavExpansion(root.children[i], activeRoutePath)
  if expandAll:
    for i in 0 ..< root.children.len:
      forceExpandAll(root.children[i])
  var sections: seq[NavSection] = @[]
  if root.items.len > 0:
    sections.add NavSection(key: "", title: "", items: root.items, isExpanded: true)
  sections.add root.children
  SidebarViewModel(sections: sections)

proc toggleNavSection(section: NavSection; key: string): NavSection =
  ## Depth-first, value-copying toggle: flips exactly the node whose
  ## `key` matches (at any depth) and rebuilds every ancestor along the
  ## way to it (a plain field reassignment on an unrelated sibling
  ## subtree short-circuits immediately, no copy needed there). Written
  ## with value returns rather than a `ptr`/`addr` into the tree since
  ## this module is dual-target (`nim js -r` too) and the JS backend's
  ## pointer support for `seq` element addresses isn't reliable enough
  ## to depend on here.
  result = section
  if result.key == key:
    result.isExpanded = not result.isExpanded
    return
  for i in 0 ..< result.children.len:
    result.children[i] = toggleNavSection(result.children[i], key)

proc toggleNavSection*(sidebar: SidebarViewModel; key: string): SidebarViewModel =
  ## Pure click-to-collapse step: flips exactly the node matching `key`
  ## (searched at any depth) and leaves the rest of the tree unchanged.
  ## The real browser-side click handler (`main_web.wireSidebarCollapse`)
  ## toggles the same node's DOM state directly rather than replaying
  ## this and re-rendering -- this is the one place that logic is pure
  ## and dual-target-testable independent of the DOM.
  result = SidebarViewModel(sections: sidebar.sections)
  for i in 0 ..< result.sections.len:
    result.sections[i] = toggleNavSection(result.sections[i], key)

proc buildBreadcrumbs*(pages: seq[NavPage]; activeRoutePath: string;
                        siteTitle: string = "Home"): seq[Breadcrumb] =
  ## Home, then (for a sectioned page) a section crumb pointing at that
  ## section's own index route, then the active page itself. The site
  ## root and an unresolvable active route (e.g. mid-404) both collapse
  ## to a single, non-forked Home crumb.
  result.add Breadcrumb(title: siteTitle, routePath: "/", isCurrent: activeRoutePath == "/")
  if activeRoutePath == "/":
    return
  var active: NavPage
  var found = false
  for page in pages:
    if page.routePath == activeRoutePath:
      active = page
      found = true
      break
  if not found:
    return
  if active.section.len > 0:
    result.add Breadcrumb(title: humanizeKey(active.section),
                           routePath: deriveRoutePath(active.section, "index"), isCurrent: false)
  result.add Breadcrumb(title: active.title, routePath: active.routePath, isCurrent: true)

proc buildAdjacentPages*(pages: seq[NavPage]; activeRoutePath: string;
                         sectionOrder: seq[string] = @[]):
    tuple[previous, next: AdjacentPage] =
  ## Previous/next within the same sorted reading order the sidebar
  ## uses, flattened across section boundaries. An active route absent
  ## from `pages` (e.g. a 404) yields no adjacent pages in either
  ## direction.
  let sorted = sortNavPages(pages, sectionOrder)
  var idx = -1
  for i, page in sorted:
    if page.routePath == activeRoutePath:
      idx = i
      break
  if idx < 0:
    return (AdjacentPage(), AdjacentPage())
  let previous =
    if idx > 0: AdjacentPage(title: sorted[idx - 1].title, routePath: sorted[idx - 1].routePath)
    else: AdjacentPage()
  let next =
    if idx < sorted.len - 1: AdjacentPage(title: sorted[idx + 1].title, routePath: sorted[idx + 1].routePath)
    else: AdjacentPage()
  (previous, next)

proc buildNavigationViewModel*(pages: seq[NavPage]; activeRoutePath: string;
                                toc: seq[HeadingNode] = @[];
                                sectionOrder: seq[string] = @[];
                                expandAll = false): NavigationViewModel =
  ## The one entry point later renderers (`components/navigation_view.nim`)
  ## and shell wiring (`ssr.nim`'s `renderRoute`, `main_web.nim`'s
  ## `createRouteApp`) use: every sub-ViewModel above, built off the same
  ## page list and active route so they never disagree with each other.
  ## `sectionOrder` (from `DocsConfig.sectionOrder`) orders the top-level
  ## sections; empty = alphabetical, unchanged.
  let (previous, next) = buildAdjacentPages(pages, activeRoutePath, sectionOrder)
  NavigationViewModel(sidebar: buildSidebar(pages, activeRoutePath, sectionOrder, expandAll),
                       breadcrumbs: buildBreadcrumbs(pages, activeRoutePath),
                       previous: previous, next: next, toc: toc)

proc navPage*(entry: RouteEntry; content: ContentEntry): NavPage =
  ## Pairs one manifest entry with its own loaded content: the link
  ## target is routing's `canonicalPath` (see the module docstring for
  ## why, not `content.routePath`); the display title prefers the
  ## content's own title, falling back to the route's meta title exactly
  ## like `shell_vm.siteShellViewModel` already does, so the two never
  ## disagree on a page's displayed title either.
  let title = if content.page.title.len > 0: content.page.title else: entry.meta.title
  NavPage(routePath: entry.canonicalPath, title: title, section: content.section,
          order: content.front.order, slug: content.slug)

proc buildNavPages*(manifest: RouteManifest;
                     loadEntry: proc(contentPath: string): ContentEntry {.closure.}): seq[NavPage] =
  ## Builds the real site-wide nav page list: every real (non-not-found)
  ## manifest entry paired with its own loaded `ContentEntry` via
  ## `navPage` -- the one canonical content graph routing and navigation
  ## share, per M3's integration constraint, rather than a second,
  ## forked page list. An entry whose content fails to load (a
  ## manifest/fixture mismatch -- most hermetic fixtures only seed the
  ## one or two files a given test actually needs, not the whole real
  ## manifest) is left out of the graph instead of failing the whole
  ## build; broken *in-page* references failing the build is M3
  ## deliverable 2's job, not this one's.
  var pages: seq[NavPage] = @[]
  for entry in manifest.entries:
    try:
      let ce = loadEntry(entry.meta.contentPath)
      ## A `hidden: true` page stays fully routed/rendered (it is still a real
      ## manifest entry) but is dropped from the nav graph, so a header-linked
      ## utility page (FAQ/Support/Sign In) never appears in the docs sidebar.
      if ce.front.hidden: continue
      pages.add navPage(entry, ce)
    except CatchableError:
      discard
  sortNavPages(pages)
