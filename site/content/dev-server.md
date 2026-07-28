---
title: Dev Server & Live Reload
description: The development server built on the SSR render path, its content-tree file watcher, the websocket live-reload channel, and the full-page error overlay.
order: 12
---
# Dev Server & Live Reload

The development server serves routes through the framework's own
`renderRoute` SSR path, so a route in dev renders exactly the bytes it would
statically generate -- plus a small injected live-reload client. It is three
cooperating pieces, each split into a pure, unit-testable core and a thin
`std/asynchttpserver` driver.

## Live reload

Every served page embeds a tiny client that opens a websocket to the
namespaced live-reload endpoint. A `ReloadHub` fans a reload signal out to
every connected client; the hub is transport-agnostic (no socket type in it),
so the exact same delivery path is exercised in-process and over a real
socket:

```nim runnable
import dev_server

let hub = newReloadHub()
let client = hub.subscribe()      # a WS client's message queue
hub.broadcast(reloadMessage)      # the watcher pushes a reload signal
doAssert client[] == @[reloadMessage]
```

The injected client and the RFC 6455 websocket handshake are pure functions,
so the exact bytes a browser receives are asserted without a live socket
(`wsAcceptKey` here is pinned to the RFC's own worked example):

```nim runnable
import std/strutils
import dev_server

# Every served page carries the live-reload client, wired to the WS endpoint.
let page = injectLiveReload("<body></body>", defaultLiveReloadPath)
doAssert page.contains(defaultLiveReloadPath)

# The WS handshake accept-key is a pure function of the client key.
doAssert wsAcceptKey("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
```

## The file watcher

The watcher content-hashes the served content dir into a `ContentSnapshot`
and, on any add / remove / edit, diffs two snapshots to detect the change and
broadcast a reload -- independently of mtimes or filesystem clock resolution:

```nim runnable
import std/tables
import dev_server

var before: ContentSnapshot
var after: ContentSnapshot
before["index.md"] = "hash-a"
after["index.md"] = "hash-b"      # the file was edited
after["about.md"] = "hash-c"      # a file was added

let changed = diffSnapshots(before, after)
doAssert "index.md" in changed
doAssert "about.md" in changed
```

## The error overlay

On a render or build failure the dev server does not serve a blank page or
crash: `handleRoute` returns a full-page **browser error overlay** (status
500) carrying the failure message, so a mistake in a content file surfaces
immediately and legibly. The overlay reuses the same live-reload channel, so
fixing the file reloads the page automatically.

The dev server is one of three build targets over the one engine: SSG via
[the build](./getting-started.md), the [nginx SSR module](./deployment.md),
and this dev server. All of them are driven by the
[CLI toolchain](./cli.md).
