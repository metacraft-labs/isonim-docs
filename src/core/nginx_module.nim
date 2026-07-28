## isonim-docs Layer 4 — the content-agnostic nginx SSR adapter (M12
## deliverable 1).
##
## This is the framework side of the `--target=nginx` build: the glue that
## lets an isonim-docs site be served **natively by nginx** through the
## nginx-link-function (`ngx_link_func` / ngx-isonim) C-ABI, exactly like
## `../isonim/src/isonim/ssr_nginx/module_glue.nim` bridges the IsoNim SSR
## renderer into nginx. nginx `dlopen`s the produced shared object and, for
## each configured route, calls the exported `isonim_docs_ssr` handler; the
## handler reads the request URI, runs the registered SSR app, and writes
## the response back through `ngx_link_func_write_resp`.
##
## Two hard content-agnosticism rules keep the framework free of any
## specific site:
##   * the SSR renderer is a PLUGGABLE slot (`setNginxTargetApp`), not a
##     hardcoded import — the concrete renderer is wired by the target
##     entry (`src/nginx_target.nim`), never here;
##   * the C-ABI itself is compiled against a VENDORED shim of the
##     nginx-link-function app header (`vendor/nginx/ngx_link_func_shim.h`),
##     so the module compiles and links into a real `.so` with no external
##     nginx dependency. A production build against the real header is a
##     single define flip (`-d:nginxUseSystemHeader`).
##
## `renderForNginx` (the pure dispatch the C handler calls) and the app
## registration are always available; the C-ABI import/export layer is
## emitted only under `-d:nginxTarget`, so ordinary C-target tests can link
## this module and exercise the dispatch contract without pulling in the
## shim or any `exportc` symbols.

when defined(js):
  {.error: "nginx_module.nim is a C-target (server) adapter; it has no meaning on the JS/SPA target".}

type
  NginxResponse* = object
    ## The full response the SSR app produced for one request. `contentType`
    ## defaults to HTML when the app leaves it empty (see `renderForNginx`).
    status*: int
    contentType*: string
    body*: string

  NginxTargetApp* = proc(uri: string): NginxResponse
    ## A content-agnostic SSR entry: maps a request path to a full response.
    ## The framework never defines one; a site (or `src/nginx_target.nim`)
    ## registers its renderer via `setNginxTargetApp`.

var gNginxApp: NginxTargetApp = nil
  ## The single registered app the C handler dispatches to. `nil` until a
  ## site wires one — `renderForNginx` then returns a typed 500 rather than
  ## crashing, so a misconfigured module fails loud but safe.

proc setNginxTargetApp*(app: NginxTargetApp) =
  ## Registers the SSR renderer the nginx handler will call. Called once at
  ## module load (from the target entry's top level, which real nginx runs
  ## via `ngx_link_func_init_cycle`). Idempotent — last registration wins.
  gNginxApp = app

proc hasNginxTargetApp*(): bool =
  ## Whether a renderer has been registered — lets a test assert the wiring
  ## without invoking it.
  gNginxApp != nil

proc renderForNginx*(uri: string): NginxResponse =
  ## Pure, content-agnostic SSR dispatch used by the nginx C-ABI handler.
  ## Delegates to the registered app; when none is registered it returns a
  ## typed `500` (never a crash), and it normalises an empty content type to
  ## HTML so every app need not repeat it. This is the seam the whole nginx
  ## adapter is tested through — no nginx headers required.
  if gNginxApp == nil:
    return NginxResponse(
      status: 500,
      contentType: "text/plain; charset=utf-8",
      body: "isonim-docs nginx target: no SSR app registered")
  result = gNginxApp(uri)
  if result.contentType.len == 0:
    result.contentType = "text/html; charset=utf-8"

# ---------------------------------------------------------------------------
# C-ABI layer — emitted ONLY for the `--target=nginx` build (`-d:nginxTarget`).
# Binds the vendored nginx-link-function shim (or, with
# `-d:nginxUseSystemHeader`, the real header) and exports the two C
# functions nginx-link-function calls: the per-cycle initializer and the
# per-route SSR handler.
# ---------------------------------------------------------------------------

when defined(nginxTarget):
  import std/os

  const shimDir = currentSourcePath().parentDir() / "vendor" / "nginx"
  {.passC: "-I" & shimDir.}

  when defined(nginxUseSystemHeader):
    # Production: nginx provides ngx_link_func_* at runtime; tell the shim
    # header to defer to the real <ngx_link_func_module.h>. No shim .c.
    {.passC: "-DNGX_LINK_FUNC_USE_SYSTEM".}
  else:
    # Self-contained: compile the vendored shim implementation into the .so
    # so it links with zero external nginx dependencies.
    {.compile: shimDir / "ngx_link_func_shim.c".}

  type
    NgxLinkFuncCtx {.importc: "ngx_link_func_ctx_t",
                     header: "ngx_link_func_shim.h".} = object
    NgxLinkFuncCyclePtr = pointer

  proc ngxWriteResp(ctx: ptr NgxLinkFuncCtx; statusCode: uint;
      statusLine, contentType, respContent: cstring; respContentLen: csize_t)
    {.importc: "ngx_link_func_write_resp", header: "ngx_link_func_shim.h".}

  proc ngxGetUri(ctx: ptr NgxLinkFuncCtx): cstring
    {.importc: "ngx_link_func_get_uri", header: "ngx_link_func_shim.h".}

  proc statusLineFor(status: int): cstring =
    ## Maps the handful of status codes the SSR path emits to their reason
    ## phrase; anything else falls back to a bare code so nginx still gets a
    ## valid status line.
    case status
    of 200: "200 OK"
    of 404: "404 Not Found"
    of 500: "500 Internal Server Error"
    else: cstring($status)

  proc isonimDocsSsr(ctx: ptr NgxLinkFuncCtx)
      {.exportc: "isonim_docs_ssr", cdecl, dynlib.} =
    ## The per-route content handler nginx-link-function calls. Reads the
    ## request URI, runs the registered SSR app via `renderForNginx`, and
    ## writes the response through nginx's `ngx_link_func_write_resp`.
    ## Mirrors `ssr_nginx/module_glue.handleSsrRequest`, but over the
    ## link-function C-ABI rather than raw `ngx_http_*`.
    if ctx == nil:
      return
    let rawUri = ngxGetUri(ctx)
    let uri = if rawUri != nil: $rawUri else: "/"
    let resp = renderForNginx(uri)
    ngxWriteResp(ctx, resp.status.uint, statusLineFor(resp.status),
                 resp.contentType.cstring, resp.body.cstring,
                 resp.body.len.csize_t)

  proc ngxLinkFuncInitCycle(cycle: NgxLinkFuncCyclePtr)
      {.exportc: "ngx_link_func_init_cycle", cdecl, dynlib.} =
    ## Per-cycle initializer nginx-link-function calls once at module load
    ## (and on reload). The app registration itself happens at the target
    ## entry's top level (which runs during library init), so there is
    ## nothing to do here yet; the export exists because
    ## nginx-link-function requires the symbol to be present.
    discard cycle
