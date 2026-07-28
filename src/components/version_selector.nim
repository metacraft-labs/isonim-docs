## isonim-docs Layer 2 — rendering for the versioning ViewModel
## (`src/core/version_vm.nim`, M10 deliverable 2).
##
## Two purely structural pieces the site chrome composes, mirroring
## `theme_toggle.nim`'s split (generic renderer-backed tree + a byte-for-byte
## SSR string, no click wiring of its own -- the live "switch version"
## behaviour is a plain in-site `<a>`/`<select>` navigation, so no JS island is
## needed here):
##   * the "outdated version" BANNER (`renderVersionBanner`) -- rendered ABOVE
##     the page's `<main>` on any known non-latest version, with a link back to
##     the same page on latest; renders NOTHING when `vm.show` is false, so a
##     latest page carries no banner markup at all;
##   * the version SELECTOR (`renderVersionSelector`) -- a small labelled list
##     of in-site links, one per catalog version, the current one marked
##     `aria-current="true"`, placed in the site header next to the theme
##     toggle.
##
## Both are content-agnostic: they render whatever `VersionBannerViewModel` /
## `VersionSelectorViewModel` they're handed and never derive version state.

import isonim/ssr/escape
import ../core/version_vm

const
  versionBannerClass* = "docs-version-banner"
  versionBannerRole* = "alert"
  versionBannerLinkClass* = "docs-version-banner-link"
  versionBannerLinkText* = "Go to the latest version"
  versionSelectorClass* = "docs-version-selector"
  versionSelectorLabel* = "Documentation version"
  versionSelectorOptionClass* = "docs-version-option"

# --- Outdated banner ----------------------------------------------------

proc renderVersionBanner*[R, E](r: R; vm: VersionBannerViewModel): E =
  ## The "outdated version" banner tree. When `vm.show` is false this still
  ## returns a real (empty) node so callers can unconditionally append it; the
  ## empty `<div>` carries no banner class, so it is inert. When shown it is a
  ## `role="alert"` region with the message and a link back to latest.
  let box = r.createElement("div")
  if not vm.show:
    return box
  r.setAttribute(box, "class", versionBannerClass)
  r.setAttribute(box, "role", versionBannerRole)
  r.appendChild(box, r.createTextNode(vm.message & " "))
  let a = r.createElement("a")
  r.setAttribute(a, "class", versionBannerLinkClass)
  r.setAttribute(a, "href", vm.latestUrl)
  r.appendChild(a, r.createTextNode(versionBannerLinkText))
  r.appendChild(box, a)
  box

proc renderVersionBannerHtml*(vm: VersionBannerViewModel): string =
  ## SSR string-mode rendering -- same shape as `renderVersionBanner`. Emits
  ## the empty string (not even an empty div) when hidden, so a latest page's
  ## HTML is byte-for-byte unchanged by the versioning feature being present.
  if not vm.show: return ""
  "<div class=\"" & versionBannerClass & "\" role=\"" & versionBannerRole & "\">" &
    escapeHtml(vm.message & " ") &
    "<a class=\"" & versionBannerLinkClass & "\" href=\"" & escapeAttr(vm.latestUrl) & "\">" &
    versionBannerLinkText & "</a>" &
  "</div>"

# --- Version selector ---------------------------------------------------

proc renderVersionSelector*[R, E](r: R; vm: VersionSelectorViewModel): E =
  ## The version-selector tree: a labelled `<nav>` of in-site links, one per
  ## catalog version, the current one carrying `aria-current="true"`. Returns
  ## an inert empty node when the catalog is empty (feature disabled), so the
  ## header carries nothing when versioning is off.
  let nav = r.createElement("nav")
  if vm.options.len == 0:
    return nav
  r.setAttribute(nav, "class", versionSelectorClass)
  r.setAttribute(nav, "aria-label", versionSelectorLabel)
  for opt in vm.options:
    let a = r.createElement("a")
    r.setAttribute(a, "class", versionSelectorOptionClass)
    r.setAttribute(a, "href", opt.url)
    if opt.current:
      r.setAttribute(a, "aria-current", "true")
    r.appendChild(a, r.createTextNode(opt.label))
    r.appendChild(nav, a)
  nav

proc renderVersionSelectorHtml*(vm: VersionSelectorViewModel): string =
  ## SSR string-mode rendering -- same shape as `renderVersionSelector`. Empty
  ## string when the catalog is empty, so an unversioned site's header markup
  ## is unchanged.
  if vm.options.len == 0: return ""
  result = "<nav class=\"" & versionSelectorClass & "\" aria-label=\"" &
    versionSelectorLabel & "\">"
  for opt in vm.options:
    result.add "<a class=\"" & versionSelectorOptionClass & "\" href=\"" &
      escapeAttr(opt.url) & "\""
    if opt.current:
      result.add " aria-current=\"true\""
    result.add ">" & escapeHtml(opt.label) & "</a>"
  result.add "</nav>"

proc renderVersionChromeHtml*(selector: VersionSelectorViewModel;
                              banner: VersionBannerViewModel): string =
  ## The combined version chrome the SSR body prepends once per page: the
  ## selector then the banner. Both collapse to "" when inactive, so this is the
  ## single hook `src/ssr.nim` injects right after `<body>` -- an unversioned
  ## page (empty catalog, no banner) gets an empty string and is unchanged.
  renderVersionSelectorHtml(selector) & renderVersionBannerHtml(banner)
