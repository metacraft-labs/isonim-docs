## Tier 1 (ViewModel / pure-helper) M2 theme suite -- dual-target: both
## `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free half of `src/core/theme_vm.nim`
## (M2 deliverable 2): toggle state, the persisted-value read/write
## round trip through an injected fake `localStorage`-shaped store, and
## the `prefers-color-scheme` system-default fallback -- all exercised
## through plain closures/in-memory tables, no filesystem or browser
## access anywhere, so the exact same assertions hold on both targets.

import std/[unittest, tables]
import ../../src/core/theme_vm

suite "docs theme ViewModel -- toggle state (Tier 1, dual-target)":
  test "toggleTheme flips light to dark and back":
    check toggleTheme(thLight) == thDark
    check toggleTheme(thDark) == thLight

  test "otherTheme is toggleTheme's own name for 'the theme this isn't'":
    check otherTheme(thLight) == thDark
    check otherTheme(thDark) == thLight

  test "ThemeViewModel.toggle flips the wrapped theme, leaving the rest of the shape alone":
    let vm = ThemeViewModel(theme: thLight)
    check toggle(vm).theme == thDark
    check toggle(toggle(vm)).theme == thLight

  test "the zero-value ThemeViewModel defaults to light":
    check ThemeViewModel().theme == thLight

suite "docs theme ViewModel -- string round trip (Tier 1, dual-target)":
  test "themeToString/themeFromString round-trip both real themes":
    check themeFromString(themeToString(thLight)) == thLight
    check themeFromString(themeToString(thDark)) == thDark

  test "themeFromString falls back to the given default for unset/corrupted values":
    check themeFromString("") == thLight
    check themeFromString("purple", default = thDark) == thDark
    check themeFromString("LIGHT") == thLight # exact-match only, not case-insensitive

suite "docs theme ViewModel -- resolveInitialTheme precedence (Tier 1, dual-target)":
  test "an explicit persisted 'dark' wins over a light system preference":
    check resolveInitialTheme("dark", prefersDark = false) == thDark

  test "an explicit persisted 'light' wins over a dark system preference":
    check resolveInitialTheme("light", prefersDark = true) == thLight

  test "no persisted value falls back to the system preference: dark":
    check resolveInitialTheme("", prefersDark = true) == thDark

  test "no persisted value falls back to the system preference: light":
    check resolveInitialTheme("", prefersDark = false) == thLight

  test "a corrupted/unrecognized persisted value is treated the same as no value":
    check resolveInitialTheme("neon", prefersDark = true) == thDark
    check resolveInitialTheme("neon", prefersDark = false) == thLight

  test "newThemeViewModel wraps resolveInitialTheme with the same precedence":
    check newThemeViewModel("dark", prefersDark = false).theme == thDark
    check newThemeViewModel("", prefersDark = true).theme == thDark
    check newThemeViewModel().theme == thLight # both defaults: no persisted value, light system

suite "docs theme ViewModel -- persisted value read/write via a fake localStorage (Tier 1, dual-target)":
  test "persistTheme writes exactly the storage key readPersistedTheme reads back":
    var store = initTable[string, string]()
    let get = proc(key: string): string =
      store.getOrDefault(key, "")
    let put = proc(key, value: string) =
      store[key] = value

    check readPersistedTheme(get) == "" # nothing persisted yet
    persistTheme(put, thDark)
    check readPersistedTheme(get) == "dark"
    check store[themeStorageKey] == "dark"

    persistTheme(put, thLight)
    check readPersistedTheme(get) == "light"

  test "a full round trip: persist, read back, resolve against a fake store":
    var store = initTable[string, string]()
    let get = proc(key: string): string =
      store.getOrDefault(key, "")
    let put = proc(key, value: string) =
      store[key] = value

    persistTheme(put, thDark)
    let resolved = resolveInitialTheme(readPersistedTheme(get), prefersDark = false)
    check resolved == thDark
