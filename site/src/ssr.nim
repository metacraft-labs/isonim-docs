## isonim-docs/site -- thin SSR entry for the framework's own docs.
##
## Calls the framework's own `renderRoute` with this site's `content/` dir
## and its own `DocsConfig`, passing NO explicit manifest -- letting the
## framework's own default (`buildManifestFromContent`) auto-discover the
## route table from the real `content/` dir, end to end.

when defined(js):
  {.error: "ssr.nim is a C-target (server-side) entry point".}

import "../../src/ssr" as frameworkSsr
import ./docs_config

proc renderRoute*(path: string; contentDir = "content"): tuple[status: int, html: string] =
  frameworkSsr.renderRoute(path, contentDir, cfg = isonimDocsDocsConfig())

when isMainModule:
  ## Proof-of-life SSR smoke check: renders "/" and reports it, so
  ## `just serve` has something real to run today.
  let (status, html) = renderRoute("/")
  echo "SSR smoke: GET / -> ", status, " (", html.len, " bytes)"
