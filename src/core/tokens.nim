## isonim-docs `core/tokens` -- kept for compatibility: the DTCG
## design-token loader and alias resolver moved to IsoNim itself, as
## `isonim/theming/dtcg`.
##
## This module re-exports that module unchanged (`TokenSet`,
## `TokenCategory`, `ResolvedToken`, `TokenError`, `loadTokens`,
## `loadTokensFromStrings`, `resolve`, `resolveToken`, ...). New code
## should import `isonim/theming/dtcg`.

{.deprecated: "isonim-docs' core/tokens moved to IsoNim: import isonim/theming/dtcg instead".}

import isonim/theming/dtcg
export dtcg
