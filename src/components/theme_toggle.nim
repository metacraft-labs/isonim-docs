## isonim-docs Layer 2 — rendering for the theme ViewModel
## (`src/core/theme_vm.nim`, M2 deliverable 2).
##
## Mirrors `search_view.nim`'s own split: a purely structural rendering
## of whatever `ThemeViewModel` state it's handed -- one `<button>`
## carrying `data-theme`/`aria-pressed`/`aria-label` attributes that
## reflect the *current* theme -- with no click wiring of its own (that
## live behaviour is a platform-specific concern belonging to the
## JS-target-only mount entry, `src/main_web.nim`, exactly the same
## "generic rendering here, live wiring at the Layer 4 shell" split
## `components/shell.nim`'s own docstring calls out).
##
## `renderThemeBootstrapHtml` is the separate, SSR-only no-flash piece:
## a real (not a JSON data island, unlike `search_view.
## renderSearchBootstrapHtml`) inline `<script>` that runs synchronously
## in `<head>`, before the page paints, so the very first frame already
## carries the right `data-theme` attribute on `<html>` -- reading
## `localStorage` first, falling back to `prefers-color-scheme`. Both
## halves agree on the one shared `theme_vm.resolveInitialTheme`
## precedence rule; this script is a hand-written JS restatement of it
## (real client-side execution, not something `nim js` compiles).

import isonim/ssr/escape
import ../core/theme_vm

const
  themeToggleClass* = "docs-theme-toggle"
  themeToggleId* = "docs-theme-toggle"
  themeToggleLabel* = "Toggle color theme"

proc toggleAriaLabel(theme: Theme): string =
  "Switch to " & themeToString(otherTheme(theme)) & " theme"

proc toggleGlyph(theme: Theme): string =
  case theme
  of thLight: "☀" # sun -- shown while light is active, click to go dark
  of thDark: "☽"  # crescent moon -- shown while dark is active

# --- MockRenderer / browser tree mode -----------------------------------

proc renderThemeToggle*[R, E](r: R; vm: ThemeViewModel): E =
  let btn = r.createElement("button")
  r.setAttribute(btn, "type", "button")
  r.setAttribute(btn, "id", themeToggleId)
  r.setAttribute(btn, "class", themeToggleClass)
  r.setAttribute(btn, "data-theme", themeToString(vm.theme))
  r.setAttribute(btn, "aria-pressed", (if vm.theme == thDark: "true" else: "false"))
  r.setAttribute(btn, "aria-label", toggleAriaLabel(vm.theme))
  r.appendChild(btn, r.createTextNode(toggleGlyph(vm.theme)))
  btn

# --- SSR string mode ------------------------------------------------------

proc renderThemeToggleHtml*(vm: ThemeViewModel): string =
  "<button type=\"button\" id=\"" & themeToggleId & "\" class=\"" & themeToggleClass &
    "\" data-theme=\"" & themeToString(vm.theme) &
    "\" aria-pressed=\"" & (if vm.theme == thDark: "true" else: "false") &
    "\" aria-label=\"" & escapeAttr(toggleAriaLabel(vm.theme)) & "\">" &
    escapeHtml(toggleGlyph(vm.theme)) & "</button>"

const themeBootstrapScriptId* = "docs-theme-bootstrap"

proc escapeJsString(s: string): string =
  ## Minimal single-quoted JS string literal escaping for the fixed,
  ## framework-controlled constants (`themeStorageKey`/`themeAttrName`)
  ## this bootstrap script embeds -- never user/content-supplied text,
  ## so this doesn't need `search_vm.escapeJsonString`'s full generality.
  result.add '\''
  for c in s:
    case c
    of '\'': result.add "\\'"
    of '\\': result.add "\\\\"
    else: result.add c
  result.add '\''

proc themeBootstrapScriptBody*(): string =
  ## The raw JS body of the no-flash bootstrap -- the exact text between the
  ## `<script>` tags. Split out from `renderThemeBootstrapHtml` so the M12
  ## CSP manager (`core/csp.nim`) can hash the identical bytes a browser
  ## hashes when matching a `'sha256-...'` script-src source.
  "(function(){try{" &
    "var k=" & escapeJsString(themeStorageKey) & ";" &
    "var a=" & escapeJsString(themeAttrName) & ";" &
    "var t=localStorage.getItem(k);" &
    "if(t!=='light'&&t!=='dark'){" &
    "t=(window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches)?'dark':'light';" &
    "}" &
    "document.documentElement.setAttribute(a,t);" &
    "}catch(e){}})();"

proc renderThemeBootstrapHtml*(): string =
  ## The no-flash bootstrap: a synchronous inline `<script>` meant to be
  ## emitted as early as possible in `<head>` (see `src/ssr.nim`), so it
  ## runs -- and sets `data-theme` on `document.documentElement` -- before
  ## the browser paints anything, avoiding a flash of the wrong theme.
  ## Wrapped in `try/catch` because `localStorage`/`matchMedia` access can
  ## throw in locked-down embeds/private-browsing modes; a theme bootstrap
  ## failing must never be the reason a page fails to render.
  "<script id=\"" & themeBootstrapScriptId & "\">" &
    themeBootstrapScriptBody() & "</script>"
