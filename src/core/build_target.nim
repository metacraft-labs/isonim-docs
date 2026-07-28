## isonim-docs Layer 4 — build-target selection (M12 deliverable 1).
##
## The framework builds to more than one deployment shape. `build --target`
## chooses between the default static-site generator (`btStatic`, the whole
## `build_site.buildSite` pipeline) and the nginx SSR module (`btNginx`, a
## `ngx_link_func` C-ABI shared object — see `core/nginx_module.nim`).
##
## This module is the pure, content-agnostic core of that selection: parse a
## target name, and produce the exact `nim` argument vector that compiles
## the nginx module. Keeping the recipe here (rather than inlined in the CLI)
## makes it assertable in `test_nginx_target.nim` — the test builds the real
## `.so` from the very same recipe the CLI uses.

when defined(js):
  {.error: "build_target.nim drives C-target builds; it has no meaning on the JS target".}

import std/[os, strutils]

type
  BuildTarget* = enum
    ## The deployment artifact a `build` produces.
    btStatic = "static"   ## the SSG: a directory of static HTML/assets
    btNginx = "nginx"     ## an nginx-link-function SSR module (`.so`)

proc parseBuildTarget*(s: string): BuildTarget =
  ## Parses a `--target` value (case-insensitive; a few friendly aliases).
  ## Empty resolves to the default static target; an unknown value is a
  ## hard `ValueError` so a typo fails loud instead of silently building the
  ## wrong artifact.
  case s.strip.toLowerAscii
  of "", "static", "ssg": btStatic
  of "nginx", "ngx", "ngx_link_func": btNginx
  else: raise newException(ValueError, "unknown build target: '" & s &
    "' (expected 'static' or 'nginx')")

const
  defaultNginxEntry* = "src/nginx_target.nim"
    ## The `--app:lib` entry the nginx recipe compiles by default.
  defaultNginxArtifact* = "ngx_isonim_docs.so"
    ## The default output shared-object name (a name nginx can `load_module`).

proc nginxBuildRecipe*(entry = defaultNginxEntry;
                       outSo = defaultNginxArtifact;
                       useSystemHeader = false): seq[string] =
  ## The exact `nim` argument vector (excluding the `nim` program name) that
  ## compiles the nginx SSR module into a C-ABI shared object. It is a REAL
  ## Nim→C→`.so` build: `--app:lib` emits a shared object, `-d:nginxTarget`
  ## turns on the `ngx_link_func` export layer in `core/nginx_module`, and
  ## `-o:` fixes the artifact path. `useSystemHeader` swaps the vendored
  ## nginx-link-function shim for the real `<ngx_link_func_module.h>` (a
  ## production build against an installed nginx-link-function).
  ##
  ## The CLI runs this verbatim, and the test compiles the real module from
  ## it — so "the recipe" and "what actually built" can never drift.
  result = @[
    "c",
    "--app:lib",
    "-d:nginxTarget",
    "--nimcache:" & (outSo.parentDir / "nimcache-nginx"),
    "-o:" & outSo,
  ]
  if useSystemHeader:
    result.add "-d:nginxUseSystemHeader"
  result.add entry
