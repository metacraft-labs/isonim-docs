/*
 * ngx_link_func_shim.h — a vendored, self-contained subset of the
 * nginx-link-function (a.k.a. `ngx_link_func` / ngx-isonim) application
 * C-ABI, used to build and TEST the isonim-docs `--target=nginx` SSR
 * module without requiring the real nginx-link-function package or nginx
 * development headers to be installed.
 *
 * nginx-link-function (https://github.com/Taymindis/nginx-link-function)
 * lets an application ship an ordinary shared object that nginx `dlopen`s
 * at runtime: the app exports plain C functions (a per-cycle initializer
 * and one handler per configured route) and talks to nginx purely through
 * this small C-ABI — `ngx_link_func_get_uri` to read the request path and
 * `ngx_link_func_write_resp` to emit the response. Because that boundary
 * is a handful of C functions, we can reproduce it faithfully here as a
 * SHIM: the exact same isonim-docs Nim module compiles and links against
 * either header, so switching to a production build is a define flip
 * (`-d:nginxUseSystemHeader`) — see `src/core/nginx_module.nim`.
 *
 * When NGX_LINK_FUNC_USE_SYSTEM is defined, this header defers entirely to
 * the real `<ngx_link_func_module.h>`; otherwise it provides a compilable,
 * dependency-free stand-in whose `ngx_link_func_write_resp` also CAPTURES
 * the response back into the ctx so a C test driver can assert the round
 * trip (see `tests/docs/test_nginx_target.nim`).
 */
#ifndef NGX_LINK_FUNC_SHIM_H
#define NGX_LINK_FUNC_SHIM_H

#ifdef NGX_LINK_FUNC_USE_SYSTEM
/* Production path: use the real nginx-link-function app header. The
 * isonim-docs module only touches the accessors declared below, all of
 * which the real header provides with identical signatures. */
#include <ngx_link_func_module.h>
#else

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * The per-request context nginx-link-function hands to each app handler.
 * The real struct carries nginx internals; the shim keeps the fields the
 * isonim-docs handler actually reads (the request path + query string)
 * plus CAPTURE slots the real struct does not have, so a test driver can
 * read back whatever the handler wrote via ngx_link_func_write_resp.
 */
typedef struct ngx_link_func_ctx_s {
    /* Request inputs the app reads through the accessors below. */
    const char *request_uri;   /* request path, e.g. "/guide/intro" */
    const char *req_args;      /* raw query string, or NULL */
    const char *req_body;      /* request body bytes, or NULL */
    size_t      req_body_len;

    /* Shim-only response capture (absent from the real ctx). */
    uintptr_t   out_status;
    const char *out_status_line;
    const char *out_content_type;
    char       *out_body;
    size_t      out_body_len;
    int         out_written;   /* 1 once write_resp has been called */
} ngx_link_func_ctx_t;

/* The per-cycle object passed to ngx_link_func_init_cycle at module load. */
typedef struct ngx_link_func_cycle_s {
    void *_reserved;
} ngx_link_func_cycle_t;

/*
 * Emit the full response for this request. In real nginx-link-function
 * this allocates nginx buffers and hands them to the output chain; in the
 * shim it copies the body into ctx->out_body and records the status /
 * content type so a driver can assert the exact bytes the handler wrote.
 */
void ngx_link_func_write_resp(
    ngx_link_func_ctx_t *ctx,
    uintptr_t status_code,
    const char *status_line,
    const char *content_type,
    const char *resp_content,
    size_t resp_content_len);

/* Return the request path (URI without the query string), or NULL. */
const char *ngx_link_func_get_uri(ngx_link_func_ctx_t *ctx);

/* Look up a query-string parameter by key; NULL when absent. */
char *ngx_link_func_get_query_param(ngx_link_func_ctx_t *ctx, const char *key);

/* Allocate request-scoped memory (malloc in the shim). */
void *ngx_link_func_palloc(ngx_link_func_ctx_t *ctx, size_t size);

#ifdef __cplusplus
}
#endif

#endif /* NGX_LINK_FUNC_USE_SYSTEM */
#endif /* NGX_LINK_FUNC_SHIM_H */
