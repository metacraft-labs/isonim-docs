## isonim-docs `core/csp` -- kept for compatibility: the
## Content-Security-Policy manager (per-page inline-script hashes folded
## into `script-src`) moved to IsoNim itself, as `isonim/static/csp`,
## together with the `CspDirective`/`CspConfig` types.
##
## This module re-exports that module unchanged (`sha256Digest`,
## `sha256Base64`, `cspHashSource`, `buildCspPolicy`, `cspHeaderValue`,
## `renderCspMetaHtml`, `CspDirective`, `CspConfig`, `defaultCspConfig`,
## `strictCspConfig`). New code should import `isonim/static/csp`.

{.deprecated: "isonim-docs' core/csp moved to IsoNim: import isonim/static/csp instead".}

import isonim/static/csp
export csp
