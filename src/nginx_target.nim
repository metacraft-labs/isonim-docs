## isonim-docs Layer 4 — the `--target=nginx` build entry (M12 deliverable 1).
##
## Compiled as an `--app:lib` shared object (see `core/build_target.
## nginxBuildRecipe`), this is the concrete nginx SSR module nginx
## `dlopen`s via nginx-link-function (`ngx_link_func` / ngx-isonim). It does
## exactly two things:
##
##   1. wires the framework's real SSR renderer (`ssr.renderRoute`) into the
##      content-agnostic nginx adapter as the registered app, and
##   2. re-exports the adapter's C-ABI handlers (`isonim_docs_ssr`,
##      `ngx_link_func_init_cycle`) by importing `core/nginx_module` under
##      `-d:nginxTarget`.
##
## The content-agnostic split is deliberate: `core/nginx_module` knows
## nothing about routes or content; THIS entry is the only place the
## concrete renderer meets the C-ABI, so a different site could ship its own
## entry registering its own app against the same adapter.
##
## The registration runs at library-init time (module top level), which is
## what nginx triggers when it loads the `.so`; nginx-link-function then
## calls `ngx_link_func_init_cycle` and, per request, `isonim_docs_ssr`.

when defined(js):
  {.error: "nginx_target.nim is the C-target nginx SSR module entry; it has no meaning on the JS target".}

import std/os
import ./core/nginx_module
import ./core/routes
import ./ssr

const defaultContentEnv = "ISONIM_DOCS_CONTENT_DIR"
  ## Real deployments point the module at their built content dir via this
  ## env var; absent, it falls back to the framework's own fixture site so a
  ## freshly-built module still renders something rather than 500-ing.

var
  gContentDir = ""
  gManifest: RouteManifest
  gManifestReady = false

proc resolvedContentDir(): string =
  if gContentDir.len > 0: gContentDir
  else:
    let fromEnv = getEnv(defaultContentEnv)
    if fromEnv.len > 0: fromEnv else: "tests/fixtures/mini-site"

proc frameworkNginxApp(uri: string): NginxResponse =
  ## The SSR app the nginx handler dispatches to: renders `uri` through the
  ## framework's manifest-driven `renderRoute`, exactly the same rendering
  ## contract the SSG and the dev server use. The manifest is built once, on
  ## the first request, so library load stays cheap and cannot fail on a
  ## missing content dir before any request arrives.
  if not gManifestReady:
    let dir = resolvedContentDir()
    gManifest = buildManifestFromContent(dir)
    gContentDir = dir
    gManifestReady = true
  let (status, html) = renderRoute(uri, gContentDir, gManifest)
  NginxResponse(status: status, contentType: "text/html; charset=utf-8",
                body: html)

# Wire the concrete renderer into the content-agnostic adapter at load time.
# This runs during the library's `NimMain` init (which nginx triggers when it
# loads the `.so`); it only REGISTERS the app — no rendering, no I/O — so
# module load stays a pure, side-effect-free wiring step.
setNginxTargetApp(frameworkNginxApp)
