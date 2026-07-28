## Normalizes incidental HTML whitespace so SSR string-mode snapshot
## assertions don't get flaky over exact literal spacing the `ui: ...`
## SSR macro happens to produce. Pure string transform -- safe on every
## target, so it doubles as one of the "deterministic docs test helpers"
## the dual-target Tier-1 suite proves.

import std/strutils

proc normalizeHtml*(html: string): string =
  ## Collapses any run of whitespace to a single space, then drops any
  ## whitespace directly touching a tag boundary (`> ` or ` <`)
  ## entirely, since that's pure inter-tag padding rather than
  ## meaningful text content.
  var collapsed = ""
  var lastWasSpace = false
  for ch in html:
    if ch in Whitespace:
      if not lastWasSpace:
        collapsed.add(' ')
      lastWasSpace = true
    else:
      collapsed.add(ch)
      lastWasSpace = false
  result = collapsed.replace("> ", ">").replace(" <", "<").strip()
