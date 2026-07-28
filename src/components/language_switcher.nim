## isonim-docs Layer 2 — rendering for the i18n ViewModel
## (`src/core/i18n_vm.nim`, M10 deliverable 3).
##
## One purely structural piece the site chrome composes, mirroring
## `version_selector.nim`'s selector split (generic renderer-backed tree + a
## byte-for-byte SSR string, no click wiring of its own -- switching locale is
## a plain in-site `<a>` navigation, so no JS island is needed here):
##   * the LANGUAGE SWITCHER (`renderLanguageSwitcher`) -- a small labelled
##     `<nav>` of in-site links, one per catalog locale, the current one marked
##     `aria-current="true"`; each link carries `hreflang`/`lang` so assistive
##     tech and crawlers know the target language. Placed in the site header
##     next to the theme toggle / version selector.
##
## Content-agnostic: it renders whatever `LanguageSwitcherViewModel` it's handed
## and never derives locale state. The (translatable) switcher caption comes in
## on the VM's `label`, defaulting to `languageSwitcherLabel` when empty.

import isonim/ssr/escape
import ../core/i18n_vm

const
  languageSwitcherClass* = "docs-language-switcher"
  languageSwitcherLabel* = "Language"
  languageOptionClass* = "docs-language-option"

proc switcherLabel(vm: LanguageSwitcherViewModel): string =
  ## The caption to render: the VM's own (translated) label, or the built-in
  ## default when it carries none.
  if vm.label.len > 0: vm.label else: languageSwitcherLabel

proc renderLanguageSwitcher*[R, E](r: R; vm: LanguageSwitcherViewModel): E =
  ## The language-switcher tree: a labelled `<nav>` of in-site links, one per
  ## catalog locale, the current one carrying `aria-current="true"` and every
  ## link its target `hreflang`/`lang`. Returns an inert empty node when the
  ## catalog is empty (feature disabled), so the header carries nothing when
  ## i18n is off.
  let nav = r.createElement("nav")
  if vm.options.len == 0:
    return nav
  r.setAttribute(nav, "class", languageSwitcherClass)
  r.setAttribute(nav, "aria-label", switcherLabel(vm))
  for opt in vm.options:
    let a = r.createElement("a")
    r.setAttribute(a, "class", languageOptionClass)
    r.setAttribute(a, "href", opt.url)
    r.setAttribute(a, "hreflang", opt.htmlLang)
    r.setAttribute(a, "lang", opt.htmlLang)
    if opt.current:
      r.setAttribute(a, "aria-current", "true")
    r.appendChild(a, r.createTextNode(opt.label))
    r.appendChild(nav, a)
  nav

proc renderLanguageSwitcherHtml*(vm: LanguageSwitcherViewModel): string =
  ## SSR string-mode rendering -- same shape as `renderLanguageSwitcher`. Empty
  ## string when the catalog is empty, so an un-internationalized site's header
  ## markup is unchanged.
  if vm.options.len == 0: return ""
  result = "<nav class=\"" & languageSwitcherClass & "\" aria-label=\"" &
    escapeAttr(switcherLabel(vm)) & "\">"
  for opt in vm.options:
    result.add "<a class=\"" & languageOptionClass & "\" href=\"" &
      escapeAttr(opt.url) & "\" hreflang=\"" & escapeAttr(opt.htmlLang) &
      "\" lang=\"" & escapeAttr(opt.htmlLang) & "\""
    if opt.current:
      result.add " aria-current=\"true\""
    result.add ">" & escapeHtml(opt.label) & "</a>"
  result.add "</nav>"
