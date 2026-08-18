## Consumer scaffold helpers -- the thin wrappers every docs site's
## `build.nim` / `dev.nim` used to re-paste by hand.
##
## A minimal isonim-docs consumer is now just its `docs_config.nim` (title,
## chrome, section order, basePath), its `content/`, and a few lines that call
## these two helpers. The token CSS comes from the design system's
## `metacraft_docs_theme` helper; the structural CSS is the framework's bundled
## default (plus an optional per-site `assets/overrides.css`). Nothing else is
## copied per site.
##
## These are deliberately parameterised so the framework stays free of any
## dependency on a specific design system: the token CSS + hot-reload provider
## + watched token path are passed IN (a consumer wires them from
## `metacraft_docs_theme`), not imported here.

when defined(js):
  {.error: "docs_scaffold is a C-target (SSG/dev-server) entry; not for the JS target".}

import std/os
import build_site
import dev_server
import core/config

export build_site
export dev_server

proc buildDocsSite*(cfg: DocsConfig;
                    contentDir = "content";
                    docsTokensCss = "";
                    clientEntry = "";
                    staticDir = "static"): int =
  ## Builds `contentDir` into `public/` with the framework SSG, prepending
  ## `docsTokensCss` (the design-system token layer) onto the composed
  ## stylesheet, compiling `clientEntry` into the hashed `assets/app.js`, then
  ## copying a `staticDir` (fonts/images) verbatim into `public/assets/` AFTER
  ## the hash/purge pass so `url(/assets/...)` refs resolve. Returns the page
  ## count. A site with extra post-build steps (e.g. legacy-URL redirects) calls
  ## this and then does its own work on `public/`.
  result = buildSite(contentDir = contentDir, cfg = cfg,
                     docsTokensCss = docsTokensCss, clientEntry = clientEntry)
  if staticDir.len > 0 and dirExists(staticDir):
    copyDir(staticDir, "public" / "assets")

proc docsDevServer*(cfg: DocsConfig;
                    contentDir = "content";
                    assetsDirs = @["assets", "static"];
                    tokensCssProvider: proc(): string {.closure.} = nil;
                    watchPaths: seq[string] = @[];
                    clientEntry = ""): DevServer =
  ## The standard themed, live-reloading docs dev server: serves `contentDir` +
  ## `assetsDirs` (with the composed stylesheet -- framework default or the
  ## site's own, plus `overrides.css`, plus token CSS), watches `contentDir` for
  ## live reload, and -- when a `tokensCssProvider` + `watchPaths` are wired from
  ## the design-system helper -- hot-reloads design-token edits with no rebuild.
  ## Collapses each consumer's hand-rolled `newDocsDevServer` to one call.
  newDevServer(contentDir = contentDir, cfg = cfg, assetsDirs = assetsDirs,
               docsTokensCss = (if tokensCssProvider != nil: tokensCssProvider() else: ""),
               tokensCssProvider = tokensCssProvider,
               watchPaths = watchPaths,
               clientEntry = clientEntry)
