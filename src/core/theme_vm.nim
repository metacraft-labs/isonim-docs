## isonim-docs Layer 3 — the light/dark theme ViewModel (M2 deliverable
## 2). Pure data + pure reducers, zero platform/CSS/DOM imports, so it's
## headless-testable on both `nim c` and `nim js` exactly like
## `search_vm.nim`'s own Tier-1 half.
##
## Persistence (`localStorage` on JS, nothing on SSR) is a
## platform-specific concern this module never touches directly --
## `readPersistedTheme`/`persistTheme` take injected get/set closures
## (mirrors `shell_vm.buildShellViewModel`'s own `loadPage` seam), so a
## test can hand them a fake in-memory store and the real JS mount
## (`src/main_web.nim`) hands them real `localStorage` glue. Likewise,
## "does the system prefer dark" is passed in as a plain `bool`
## (`prefersDark`) rather than read here, so `resolveInitialTheme` stays
## dual-target pure.

type
  Theme* = enum
    thLight
    thDark

  ThemeViewModel* = object
    ## `theme` defaults to `thLight` (the enum's first value) -- the
    ## same "always the same, deterministic default" convention
    ## `search_vm.SearchViewModel`'s zero value already uses for every
    ## SSR/JS-mounted page's *initial* render; the real preferred/
    ## persisted theme is resolved and applied by the SSR no-flash
    ## bootstrap script / JS mount wiring, not baked into this default.
    theme*: Theme

const
  themeStorageKey* = "isonim-docs-theme"
  themeAttrName* = "data-theme"

proc themeToString*(theme: Theme): string =
  case theme
  of thLight: "light"
  of thDark: "dark"

proc themeFromString*(s: string; default: Theme = thLight): Theme =
  ## Parses a persisted/attribute string back into a `Theme`; anything
  ## other than exactly "light" or "dark" (unset, corrupted, a future
  ## value this build doesn't know) falls back to `default` rather than
  ## raising -- a theme toggle must never be the reason a page fails to
  ## render.
  case s
  of "dark": thDark
  of "light": thLight
  else: default

proc otherTheme*(theme: Theme): Theme =
  case theme
  of thLight: thDark
  of thDark: thLight

proc toggleTheme*(theme: Theme): Theme = otherTheme(theme)

proc toggle*(vm: ThemeViewModel): ThemeViewModel =
  ThemeViewModel(theme: toggleTheme(vm.theme))

proc resolveInitialTheme*(persisted: string; prefersDark: bool): Theme =
  ## The one shared precedence rule the SSR bootstrap script, the JS
  ## mount's initial sync, and this suite's own tests all agree on: an
  ## explicit persisted value (`"light"`/`"dark"`) always wins over the
  ## system default; only an empty/unrecognized `persisted` value falls
  ## back to `prefersDark`.
  if persisted == "light" or persisted == "dark":
    themeFromString(persisted)
  elif prefersDark:
    thDark
  else:
    thLight

proc newThemeViewModel*(persisted: string = ""; prefersDark: bool = false): ThemeViewModel =
  ThemeViewModel(theme: resolveInitialTheme(persisted, prefersDark))

type
  ThemeStorageGet* = proc(key: string): string {.closure.}
  ThemeStorageSet* = proc(key, value: string) {.closure.}

proc readPersistedTheme*(get: ThemeStorageGet): string =
  ## Reads the one storage key every persisted-theme read/write agrees
  ## on (`themeStorageKey`) through the injected `get` seam -- a fake
  ## in-memory store in tests, real `localStorage.getItem` on JS.
  get(themeStorageKey)

proc persistTheme*(set: ThemeStorageSet; theme: Theme) =
  set(themeStorageKey, themeToString(theme))
