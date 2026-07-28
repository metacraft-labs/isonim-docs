## isonim-docs/site -- thin SSG entry for the framework's own docs.
##
## Calls the framework's own `buildSite` with this site's `content/` dir
## and its own `DocsConfig`, passing NO explicit manifest -- letting the
## framework's own default (`buildManifestFromContent`) auto-discover the
## route table from the real `content/` dir, end to end (dogfooding the
## framework's auto-discovery routing on its own docs).
##
## The reused Metacraft theme's token layer
## (`theme_tokens.isonimDocsTokenLayer`) is emitted to CSS and PREPENDED
## onto `assets/style.css` via `buildSite(docsTokensCss = ...)`, and the
## vendored theme binaries (Geist woff2, search glyph) under `static/` are
## copied verbatim into `public/assets/` AFTER the hash/purge pass so the
## stylesheet's `url(/assets/...)` refs resolve to real files.

when defined(js):
  {.error: "build.nim is a C-target (SSG) entry; not for the JS target".}

import std/os
import build_site
import core/docs_tokens
import ./docs_config
import ./theme_tokens

when isMainModule:
  let tokensCss = emitTokensCss(isonimDocsTokenLayer(), designSystemTokens())
  let n = buildSite(contentDir = "content", cfg = isonimDocsDocsConfig(),
                    docsTokensCss = tokensCss)
  ## Vendored theme binaries live outside `assets/` (which the SSG hashes +
  ## renames) so they land in `public/assets/` at the exact unhashed paths
  ## the stylesheet's `url(/assets/...)` refs point at.
  if dirExists("static"):
    copyDir("static", "public" / "assets")
  echo "SSG: rendered ", n, " static pages into ./public/"
