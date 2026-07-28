---
title: Deployment (nginx Adapter)
description: The --target=nginx build producing an nginx-link-function SSR module, and the content-agnostic adapter that wires the framework's renderer to the C-ABI.
order: 14
---
# Deployment: the nginx Adapter

Beyond the default static build (a directory of HTML you can host anywhere),
isonim-docs can build an **nginx SSR module**: a shared object nginx loads via
nginx-link-function (`ngx_link_func`), rendering routes in-process on each
request through the exact same `renderRoute` path the SSG and dev server use.

## The `--target=nginx` build

The build target is a typed choice. The default is the static SSG; `nginx`
selects the SSR-module build, driven by a shared compile recipe (the same one
the module's test compiles):

```nim runnable
import core/build_target

# The build target is parsed from --target (or TARGET); default is static.
doAssert parseBuildTarget("") == btStatic
doAssert parseBuildTarget("static") == btStatic
doAssert parseBuildTarget("nginx") == btNginx

# The nginx module is compiled from a shared recipe into a .so artifact.
let recipe = nginxBuildRecipe(entry = defaultNginxEntry,
                              outSo = defaultNginxArtifact)
doAssert recipe.len > 0
```

From the CLI this is `isonim-docs build --target=nginx --nginx-out=PATH`; the
default artifact name is `ngx_isonim_docs.so`.

## The content-agnostic adapter

The split is deliberate. `core/nginx_module` knows nothing about routes or
content -- it exposes the C-ABI handler plus a **pluggable renderer slot**.
The target entry (`src/nginx_target.nim`) is the only place the concrete
renderer meets the C-ABI: at library-init time it registers the framework's
manifest-driven `renderRoute` as the app. A different site could ship its own
entry registering its own app against the same adapter.

```nim runnable
import std/strutils
import core/nginx_module

# A site registers its SSR renderer into the pluggable slot at load time.
proc myApp(uri: string): NginxResponse =
  NginxResponse(status: 200, contentType: "text/html; charset=utf-8",
                body: "<h1>" & uri & "</h1>")

setNginxTargetApp(myApp)
doAssert hasNginxTargetApp()

# The C handler dispatches through the registered app.
let resp = renderForNginx("/pets")
doAssert resp.status == 200
doAssert resp.body.contains("/pets")
```

Before any app is registered, `renderForNginx` returns a typed 500 rather
than crashing -- a misconfigured module fails loud but safe. A real
deployment points the module at its built content dir via the
`ISONIM_DOCS_CONTENT_DIR` env var; the manifest is built once, on the first
request, so library load stays cheap.
