/*
 * ngx_link_func_shim.c — implementation of the vendored ngx_link_func
 * app C-ABI shim (see ngx_link_func_shim.h). Compiled INTO the
 * isonim-docs `--target=nginx` shared object (and into the C test driver)
 * so the module links to a real artifact without the nginx-link-function
 * package. Under NGX_LINK_FUNC_USE_SYSTEM this whole file is empty — nginx
 * supplies these symbols at runtime instead.
 */
#include "ngx_link_func_shim.h"

#ifndef NGX_LINK_FUNC_USE_SYSTEM

#include <stdlib.h>
#include <string.h>

void ngx_link_func_write_resp(
    ngx_link_func_ctx_t *ctx,
    uintptr_t status_code,
    const char *status_line,
    const char *content_type,
    const char *resp_content,
    size_t resp_content_len) {
    if (ctx == NULL) {
        return;
    }
    ctx->out_status = status_code;
    ctx->out_status_line = status_line;
    ctx->out_content_type = content_type;
    /* Copy the body so it outlives the caller's buffer, mirroring how the
     * real module hands owned nginx buffers to the output chain. */
    if (ctx->out_body != NULL) {
        free(ctx->out_body);
        ctx->out_body = NULL;
    }
    ctx->out_body = (char *)malloc(resp_content_len + 1);
    if (ctx->out_body != NULL) {
        if (resp_content != NULL && resp_content_len > 0) {
            memcpy(ctx->out_body, resp_content, resp_content_len);
        }
        ctx->out_body[resp_content_len] = '\0';
    }
    ctx->out_body_len = resp_content_len;
    ctx->out_written = 1;
}

const char *ngx_link_func_get_uri(ngx_link_func_ctx_t *ctx) {
    if (ctx == NULL) {
        return NULL;
    }
    return ctx->request_uri;
}

char *ngx_link_func_get_query_param(ngx_link_func_ctx_t *ctx, const char *key) {
    if (ctx == NULL || ctx->req_args == NULL || key == NULL) {
        return NULL;
    }
    size_t key_len = strlen(key);
    const char *p = ctx->req_args;
    while (*p != '\0') {
        /* Match "key=" at a parameter boundary. */
        if (strncmp(p, key, key_len) == 0 && p[key_len] == '=') {
            const char *val = p + key_len + 1;
            const char *end = strchr(val, '&');
            size_t vlen = (end != NULL) ? (size_t)(end - val) : strlen(val);
            char *out = (char *)malloc(vlen + 1);
            if (out == NULL) {
                return NULL;
            }
            memcpy(out, val, vlen);
            out[vlen] = '\0';
            return out;
        }
        const char *amp = strchr(p, '&');
        if (amp == NULL) {
            break;
        }
        p = amp + 1;
    }
    return NULL;
}

void *ngx_link_func_palloc(ngx_link_func_ctx_t *ctx, size_t size) {
    (void)ctx;
    return malloc(size);
}

#endif /* NGX_LINK_FUNC_USE_SYSTEM */
