## isonim-docs Layer 4 — the development server (M11 deliverable 2).
##
## A live-reloading dev server built entirely on the framework's own
## `renderRoute` SSR path (one codebase → SSG via `build_site.nim`, SSR
## via `ssr.nim`, dev via here), so a route serves in dev exactly the
## bytes it would statically generate, plus a small injected live-reload
## client. Three cooperating pieces, each split into a pure, directly
## unit-testable core and a thin `std/asynchttpserver` driver:
##
##   * an HTTP handler (`handleRoute`) that renders a route and, on a
##     render/build failure, serves a full-page browser ERROR OVERLAY
##     (status 500) instead of a blank page or a crash;
##   * a content-tree file WATCHER (`snapshotContentDir` + `pollForChanges`)
##     that content-hashes the served `contentDir` and, on any add / remove
##     / edit, broadcasts a reload signal;
##   * a WEBSOCKET live-reload channel: every served page embeds a tiny
##     client that opens a WS to `liveReloadPath`; the watcher's broadcast
##     is delivered to every connected client as an RFC 6455 text frame,
##     and the client reloads.
##
## The WS handshake (`wsAcceptKey`) and frame encoding (`encodeWsTextFrame`)
## are pure functions verified against the RFC 6455 test vectors, so the
## exact bytes a browser receives are asserted without a live socket. The
## watcher → hub → client path is likewise driven synchronously in tests
## (subscribe a queue, edit a file, `pollForChanges`, assert the queue got
## the reload message) — the same `ReloadHub` the async WS driver drains.

when defined(js):
  {.error: "dev_server.nim is a C-target (server-side) entry point; the dev server has no meaning on the JS/SPA target".}

import std/[os, strutils, tables, algorithm, sha1, base64, httpcore, asynchttpserver, asyncdispatch, asyncnet]
import chronicles
import ./core/config
import ./ssr

const
  wsGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    ## RFC 6455 §1.3 magic GUID appended to the client key before hashing.
  defaultLiveReloadPath* = "/__isonim_livereload"
    ## The in-page WS endpoint the injected client connects to. Namespaced
    ## so it can never collide with a real content route.
  reloadMessage* = "reload"
    ## The single text-frame payload the server pushes on any content change.
  defaultSavePath* = "/__isonim_save"
    ## The in-page POST endpoint an OPT-IN `saveHandler` responds on. Namespaced
    ## like `defaultLiveReloadPath` so it can never collide with a content route.
    ## Inert unless a consumer wires a `saveHandler` (default docs serving for the
    ## three consumers is byte-unchanged).

type
  SaveResult* = object
    ## The outcome of a `saveHandler` invocation, rendered verbatim as the POST
    ## response (status + content-type + body). A consumer's handler returns
    ## this; the async driver just serialises it.
    status*: int
    contentType*: string
    body*: string

  SaveHandler* = proc(body: string): SaveResult {.closure.}
    ## A project-owned POST handler for the save endpoint. It receives the raw
    ## request body (typically a small JSON payload) and returns a `SaveResult`.
    ## The framework owns NOTHING about the payload -- the consumer decodes it
    ## and performs its own persistence (e.g. the design harness patches the
    ## docs token file via `applyDocsTokenEdit`). `nil` (the default) leaves the
    ## save endpoint disabled, so every existing consumer is unaffected.

  ContentSnapshot* = Table[string, string]
    ## Maps a content file's `contentDir`-relative path to a content hash.
    ## A pure value: two snapshots differing means the served content
    ## differs, independently of mtimes or filesystem clock resolution.

  RenderFn* = proc(path: string): tuple[status: int; html: string] {.closure.}
    ## How a request path becomes `(status, html)`. Defaults to the real
    ## `renderRoute` bound to the server's `contentDir`/`cfg`; injectable so
    ## a test can drive the error-overlay path with a deliberately raising
    ## renderer without needing a broken content file on disk.

  ReloadHub* = ref object
    ## Fan-out for reload signals. Each subscriber owns a message queue;
    ## `broadcast` appends to every queue. The async WS driver drains its
    ## queue into socket frames; a test drains it with a plain `check`.
    ## Deliberately transport-agnostic (no socket type here) so the exact
    ## same delivery path is exercised in-process and over a real WS.
    subscribers: seq[ref seq[string]]

  DevServer* = ref object
    contentDir*: string
    cfg*: DocsConfig
    liveReloadPath*: string
    snapshot*: ContentSnapshot
    hub*: ReloadHub
    render*: RenderFn
    assetsDirs*: seq[string]
      ## On-disk dirs served under `/assets/`, searched in order (first match
      ## wins). A themed consumer passes the same dirs its build maps into
      ## `public/assets/` -- e.g. @["assets", "static"] when `style.css` lives
      ## in `assets/` and the fonts/images in `static/`. Empty = no static
      ## assets served (pages still render, just unstyled).
    docsTokensCss*: string
      ## Optional `:root{ --docs-*: … }` token CSS (from
      ## `core/docs_tokens.emitTokensCss`) PREPENDED to the served
      ## `assets/style.css`, exactly as `buildSite(docsTokensCss = …)` does --
      ## so the dev server's theme matches the built site's byte-for-byte.
    tokensCssProvider*: proc(): string {.closure.}
      ## Optional live re-computation of `docsTokensCss`. When set, the served
      ## `assets/style.css` prepends `tokensCssProvider()` (re-read fresh on
      ## every request) instead of the static `docsTokensCss` -- so editing the
      ## design-system token file hot-reloads the theme without a rebuild.
    watchPaths*: seq[string]
      ## Extra individual files to watch alongside `contentDir` (e.g. the shared
      ## design-system token JSON). A change to any of them triggers a reload,
      ## exactly like a content edit.
    saveHandler*: SaveHandler
      ## Optional POST handler mounted at `savePath`. When set, a POST to that
      ## path is dispatched to this closure instead of being rendered as a route;
      ## when `nil` (default) a POST to the save path 404s and nothing else
      ## changes -- so the design harness can opt into a live in-browser save
      ## without altering the three docs consumers' default behaviour.
    savePath*: string
      ## The path `saveHandler` answers on (default `defaultSavePath`).
    clientEntry*: string
      ## M1 (client-JS bundle): OPTIONAL path to the consumer's `nim js` mount
      ## entry (e.g. `src/main.nim`). When set, a request for `/assets/app.js`
      ## is served by compiling that entry with `nim js` (LAZILY, on first
      ## request, then cached for the process lifetime -- so constructing a
      ## server in a test never pays the compile) rather than reading a file
      ## from `assetsDirs`. Empty (the default) leaves `/assets/app.js` to the
      ## normal on-disk asset lookup, so every existing consumer is unchanged.
    clientBundleCache: string
      ## Process-lifetime cache of the compiled `clientEntry` JS (empty until
      ## the first successful `/assets/app.js` request compiles it).

# ---------------------------------------------------------------------------
# Reload hub — the transport-agnostic fan-out the watcher feeds and the WS
# driver drains.
# ---------------------------------------------------------------------------

proc newReloadHub*(): ReloadHub =
  ReloadHub(subscribers: @[])

proc subscribe*(hub: ReloadHub): ref seq[string] =
  ## Registers a fresh, empty queue and returns it. The caller drains it
  ## (a WS client sends each message as a frame; a test asserts on it).
  result = new(seq[string])
  result[] = @[]
  hub.subscribers.add result

proc unsubscribe*(hub: ReloadHub; q: ref seq[string]) =
  ## Drops a queue (a WS client disconnected). No-op if already gone.
  let idx = hub.subscribers.find(q)
  if idx >= 0:
    hub.subscribers.delete idx

proc broadcast*(hub: ReloadHub; msg: string) =
  ## Appends `msg` to every subscriber's queue. Fan-out order is
  ## registration order (deterministic).
  for q in hub.subscribers:
    q[].add msg

proc subscriberCount*(hub: ReloadHub): int =
  hub.subscribers.len

# ---------------------------------------------------------------------------
# Content watcher — a pure snapshot + a diff.
# ---------------------------------------------------------------------------

proc snapshotContentDir*(contentDir: string): ContentSnapshot =
  ## Content-hashes every `*.md` file under `contentDir` (recursively),
  ## keyed by its relative path. Uses file CONTENTS, not mtime, so change
  ## detection is deterministic and immune to coarse filesystem clocks —
  ## the same rule the SSG's own content hashing follows.
  result = initTable[string, string]()
  if not dirExists(contentDir):
    return
  for path in walkDirRec(contentDir):
    if path.endsWith(".md"):
      let rel = path.relativePath(contentDir)
      result[rel] = $secureHash(readFile(path))

proc diffSnapshots*(prev, cur: ContentSnapshot): seq[string] =
  ## Returns the sorted relative paths that were added, removed, or whose
  ## content changed between two snapshots.
  result = @[]
  for k, v in cur:
    if k notin prev or prev[k] != v:
      result.add k
  for k in prev.keys:
    if k notin cur:
      result.add k
  result.sort()

proc snapshotWatchPaths*(paths: seq[string]): ContentSnapshot =
  ## Content-hashes each individually-watched file (e.g. the design-system token
  ## JSON), keyed by a `watch:`-prefixed path so it can never collide with a
  ## `contentDir`-relative key. Missing files are simply absent (their later
  ## appearance shows up as an add).
  result = initTable[string, string]()
  for p in paths:
    if fileExists(p):
      result["watch:" & p] = $secureHash(readFile(p))

# ---------------------------------------------------------------------------
# Live-reload client + error overlay — the injected browser bytes.
# ---------------------------------------------------------------------------

proc liveReloadClientScript*(wsPath: string): string =
  ## The tiny client every served page embeds: opens a WS to `wsPath` on
  ## the page's own host, reloads on any message, and auto-reconnects with
  ## a short backoff (so a reload triggered by the server restarting still
  ## lands). Pure string — no framework dependency.
  """<script>(function(){
  function connect(){
    try{
      var proto = location.protocol === "https:" ? "wss:" : "ws:";
      var ws = new WebSocket(proto + "//" + location.host + """" & wsPath & """");
      ws.onmessage = function(){ location.reload(); };
      ws.onclose = function(){ setTimeout(connect, 1000); };
    }catch(e){ setTimeout(connect, 1000); }
  }
  connect();
})();</script>"""

proc injectLiveReload*(html, wsPath: string): string =
  ## Splices the live-reload client into a rendered page just before
  ## `</body>` (falling back to appending it) so it runs after the page's
  ## own scripts. The route's own bytes are otherwise untouched.
  let script = liveReloadClientScript(wsPath)
  let idx = html.rfind("</body>")
  if idx >= 0:
    html[0 ..< idx] & script & html[idx .. ^1]
  else:
    html & script

proc renderErrorOverlay*(routePath, message: string; wsPath = defaultLiveReloadPath): string =
  ## A full-page browser error overlay shown when a route fails to render
  ## (a build failure at dev time). Retains the live-reload client, so the
  ## moment the author fixes the source the page reloads to the real
  ## content. `message` is HTML-escaped — a raw compiler/exception string
  ## can contain `<`/`&`.
  let safe = message.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"))
  let safeRoute = routePath.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"))
  """<!DOCTYPE html><html><head><meta charset="utf-8">""" &
  """<title>Build error — """ & safeRoute & """</title></head>""" &
  """<body style="margin:0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;background:#1b1b1f;color:#e6e6e6">""" &
  """<div style="padding:2rem;max-width:60rem;margin:0 auto">""" &
  """<div style="color:#ff5c5c;font-size:1.4rem;font-weight:700;margin-bottom:.5rem">Failed to build """ & safeRoute & """</div>""" &
  """<div style="color:#9a9a9a;margin-bottom:1rem">isonim-docs dev server — fix the error below and save; this page reloads automatically.</div>""" &
  """<pre style="white-space:pre-wrap;background:#2a2a2f;padding:1rem;border-radius:6px;border-left:4px solid #ff5c5c;overflow:auto">""" &
  safe & """</pre></div>""" &
  liveReloadClientScript(wsPath) &
  """</body></html>"""

# ---------------------------------------------------------------------------
# DevServer — construction, request handling, polling.
# ---------------------------------------------------------------------------

proc defaultRender(contentDir: string; cfg: DocsConfig): RenderFn =
  ## Binds the real `renderRoute` to this server's content dir + config.
  (proc(path: string): tuple[status: int; html: string] =
    renderRoute(path, contentDir, cfg = cfg))

proc newDevServer*(contentDir: string; cfg: DocsConfig = docsConfig();
                    liveReloadPath = defaultLiveReloadPath;
                    render: RenderFn = nil;
                    assetsDirs: seq[string] = @[]; docsTokensCss = "";
                    tokensCssProvider: proc(): string {.closure.} = nil;
                    watchPaths: seq[string] = @[];
                    saveHandler: SaveHandler = nil;
                    savePath = defaultSavePath;
                    clientEntry = ""): DevServer =
  ## Constructs a dev server over `contentDir`, taking the initial snapshot up
  ## front so the first `pollForChanges` reports only genuine edits made after
  ## startup. `assetsDirs`/`docsTokensCss` (both optional) make the server serve
  ## the consumer's own themed asset dirs under `/assets/` with the token CSS
  ## prepended to `style.css`. `tokensCssProvider`/`watchPaths` (both optional)
  ## enable design-token HOT RELOAD: the token CSS is re-computed live on every
  ## request and a change to any `watchPaths` file (e.g. the design-system token
  ## JSON) triggers a reload -- so editing the design system updates the running
  ## site with no rebuild.
  result = DevServer(
    contentDir: contentDir,
    cfg: cfg,
    liveReloadPath: liveReloadPath,
    hub: newReloadHub(),
    assetsDirs: assetsDirs,
    docsTokensCss: docsTokensCss,
    tokensCssProvider: tokensCssProvider,
    watchPaths: watchPaths,
    saveHandler: saveHandler,
    savePath: savePath,
    clientEntry: clientEntry)
  # Initial snapshot covers content + the watched files.
  result.snapshot = snapshotContentDir(contentDir)
  for k, v in snapshotWatchPaths(watchPaths):
    result.snapshot[k] = v
  result.render = if render != nil: render else: defaultRender(contentDir, cfg)

proc mimeForAsset*(path: string): string =
  ## Minimal content-type map for the asset kinds a docs site ships. Unknown
  ## extensions fall back to a generic binary type.
  let ext = path.splitFile.ext.toLowerAscii
  case ext
  of ".css": "text/css; charset=utf-8"
  of ".js": "text/javascript; charset=utf-8"
  of ".json": "application/json; charset=utf-8"
  of ".svg": "image/svg+xml"
  of ".woff2": "font/woff2"
  of ".woff": "font/woff"
  of ".ttf": "font/ttf"
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  of ".gif": "image/gif"
  of ".ico": "image/x-icon"
  of ".webp": "image/webp"
  else: "application/octet-stream"

proc clientBundleJs(server: DevServer): string =
  ## M1 (client-JS bundle): compile `server.clientEntry` with `nim js` on
  ## first use and cache the result for the process lifetime. Compiles into a
  ## temp file the consumer's own `config.nims` (active in the dev CWD)
  ## governs, exactly like the SSG's `compileClientBundle`. A failed compile
  ## raises, which `handleRoute`'s asset path turns into a 500 rather than
  ## dropping the connection -- so a broken client entry is visible, not silent.
  if server.clientBundleCache.len > 0: return server.clientBundleCache
  let outJs = getTempDir() / "isonim-dev-app.js"
  let cmd = "nim js --hints:off -o:" & quoteShell(outJs) & " " & quoteShell(server.clientEntry)
  info "dev_server_client_bundle_compiling", entry = server.clientEntry
  let code = execShellCmd(cmd)
  if code != 0 or not fileExists(outJs):
    raise newException(IOError,
      "client bundle compile failed (`" & cmd & "` exited " & $code & ")")
  server.clientBundleCache = readFile(outJs)
  info "dev_server_client_bundle_compiled", bytes = server.clientBundleCache.len
  server.clientBundleCache

proc handleAsset*(server: DevServer; path: string):
    tuple[status: int; contentType, body: string] =
  ## Serves a request under `/assets/` from `server.assetsDir`. For
  ## `assets/style.css` the server's `docsTokensCss` is prepended, mirroring
  ## `buildSite(docsTokensCss = …)` so the dev look matches the built site.
  ## A path-escape attempt (`..`), no configured dirs, or a file missing from
  ## every dir all yield 404 (never a filesystem read outside the assets dirs).
  const prefix = "/assets/"
  let rel = path[prefix.len .. ^1]
  if rel.len == 0 or ".." in rel:
    return (404, "text/plain; charset=utf-8", "not found")
  ## M1 (client-JS bundle): a configured `clientEntry` owns `/assets/app.js`,
  ## compiled+cached lazily (see `clientBundleJs`), ahead of the on-disk lookup.
  if rel == "app.js" and server.clientEntry.len > 0:
    return (200, mimeForAsset(rel), server.clientBundleJs())
  for dir in server.assetsDirs:
    let full = dir / rel
    if fileExists(full):
      var body = readFile(full)
      if rel == "style.css":
        # Prefer the live provider (re-read fresh, so design-system edits show
        # immediately) over the static snapshot captured at startup.
        let tokens =
          if server.tokensCssProvider != nil: server.tokensCssProvider()
          else: server.docsTokensCss
        if tokens.len > 0:
          body = tokens & "\n" & body
      return (200, mimeForAsset(rel), body)
  (404, "text/plain; charset=utf-8", "not found")

proc handleRoute*(server: DevServer; path: string):
    tuple[status: int; contentType, body: string] =
  ## Renders `path` through the server's `render` fn. A successful render
  ## (any status the framework returns, incl. its own 404/500 chrome) gets
  ## the live-reload client injected. A RAISED render error — a genuine
  ## dev-time build failure — is caught and turned into the browser error
  ## overlay (status 500) rather than dropping the connection.
  if path == server.liveReloadPath:
    # Non-WS hit on the reload endpoint (e.g. a probe): a plain OK.
    return (200, "text/plain; charset=utf-8", "isonim-docs live-reload endpoint")
  if path.startsWith("/assets/"):
    # Static assets (themed stylesheet, fonts, images) served verbatim; never
    # get the live-reload client injected.
    return handleAsset(server, path)
  try:
    let (status, html) = server.render(path)
    (status, "text/html; charset=utf-8", injectLiveReload(html, server.liveReloadPath))
  except CatchableError as e:
    error "dev_server_render_failed", route = path, err = e.msg
    (500, "text/html; charset=utf-8",
      renderErrorOverlay(path, e.msg, server.liveReloadPath))

proc handleSave*(server: DevServer; body: string): SaveResult =
  ## Dispatches a POST save `body` to the consumer-supplied `saveHandler`. When
  ## no handler is wired (the default for every docs consumer), the endpoint is
  ## inert and returns 404 -- so a stray POST can never mutate anything. The
  ## handler owns decoding + persistence; a raised error is turned into a 500 so
  ## a bad payload never drops the connection. Directly unit-testable without a
  ## socket: construct a server with a handler, call `handleSave`, assert both
  ## the returned `SaveResult` and the handler's side effect (the patched file).
  if server.saveHandler.isNil:
    return SaveResult(status: 404, contentType: "text/plain; charset=utf-8",
      body: "save endpoint not enabled")
  try:
    result = server.saveHandler(body)
  except CatchableError as e:
    result = SaveResult(status: 500, contentType: "text/plain; charset=utf-8",
      body: "save handler failed: " & e.msg)

proc pollForChanges*(server: DevServer): seq[string] =
  ## The watcher tick: re-snapshot the content dir + the watched files, diff
  ## against the last snapshot, and — if anything changed — adopt the new
  ## snapshot and broadcast the reload signal to every connected client. Returns
  ## the changed keys (empty when nothing changed, so it's cheap to call on a
  ## fast timer). A change to a watched design-system file reloads exactly like
  ## a content edit; the browser then re-fetches `style.css` with fresh tokens.
  var cur = snapshotContentDir(server.contentDir)
  for k, v in snapshotWatchPaths(server.watchPaths):
    cur[k] = v
  let changed = diffSnapshots(server.snapshot, cur)
  if changed.len > 0:
    server.snapshot = cur
    server.hub.broadcast(reloadMessage)
    info "dev_server_content_changed", files = changed.len,
      first = (if changed.len > 0: changed[0] else: "")
  changed

# ---------------------------------------------------------------------------
# WebSocket protocol — pure handshake + frame encoding (RFC 6455).
# ---------------------------------------------------------------------------

proc wsAcceptKey*(clientKey: string): string =
  ## Computes the `Sec-WebSocket-Accept` value: base64(SHA1(key + GUID)),
  ## per RFC 6455 §4.2.2. Verified against the spec's own test vector.
  let hex = $secureHash(clientKey & wsGuid)
  # `secureHash` renders the 20-byte SHA1 as a 40-char hex string; decode
  # it back to raw bytes before base64 (the accept key is base64 of the
  # raw digest, not of its hex text).
  var raw = newString(20)
  for i in 0 ..< 20:
    raw[i] = chr(parseHexInt(hex[i*2 .. i*2+1]))
  base64.encode(raw)

proc encodeWsTextFrame*(payload: string): string =
  ## Encodes `payload` as a single unmasked server→client text frame
  ## (FIN=1, opcode=0x1). Server frames are never masked (RFC 6455 §5.1).
  ## Handles the three length encodings (7-bit, 16-bit, 64-bit).
  result = newStringOfCap(payload.len + 10)
  result.add chr(0x81) # FIN + text opcode
  let n = payload.len
  if n <= 125:
    result.add chr(n)
  elif n <= 0xFFFF:
    result.add chr(126)
    result.add chr((n shr 8) and 0xFF)
    result.add chr(n and 0xFF)
  else:
    result.add chr(127)
    for shift in countdown(56, 0, 8):
      result.add chr((n shr shift) and 0xFF)
  result.add payload

proc isWebSocketUpgrade*(req: Request): bool =
  ## True when `req` is a WS upgrade handshake (a case-insensitive
  ## `Upgrade: websocket` with a client key), so the driver can branch
  ## between "serve HTML" and "open the reload channel".
  if not req.headers.hasKey("upgrade"): return false
  if "websocket" notin req.headers["upgrade"].toLowerAscii: return false
  req.headers.hasKey("sec-websocket-key")

proc wsHandshakeResponse*(clientKey: string): string =
  ## The raw HTTP/1.1 101 Switching Protocols response opening the WS.
  "HTTP/1.1 101 Switching Protocols\r\n" &
  "Upgrade: websocket\r\n" &
  "Connection: Upgrade\r\n" &
  "Sec-WebSocket-Accept: " & wsAcceptKey(clientKey) & "\r\n\r\n"

# ---------------------------------------------------------------------------
# Async driver — the real running server (`isonim-docs dev`/`serve`).
# ---------------------------------------------------------------------------

proc serveWebSocket(server: DevServer; req: Request) {.async.} =
  ## Upgrades `req` to a WS, subscribes it to the reload hub, and forwards
  ## every broadcast reload signal to the client as a text frame until the
  ## socket drops. One tiny queue-drain loop; the watcher does the work.
  let client = req.client
  await client.send(wsHandshakeResponse(req.headers["sec-websocket-key"]))
  let q = server.hub.subscribe()
  info "dev_server_ws_open", clients = server.hub.subscriberCount()
  try:
    while not client.isClosed:
      if q[].len > 0:
        let msgs = q[]
        q[].setLen 0
        for m in msgs:
          await client.send(encodeWsTextFrame(m))
      else:
        await sleepAsync(50)
  finally:
    server.hub.unsubscribe q
    info "dev_server_ws_close", clients = server.hub.subscriberCount()

proc processRequest*(server: DevServer; req: Request) {.async.} =
  ## Single request dispatch shared by the production loop (below) and any
  ## test driver: a WS upgrade on the reload path opens the live-reload
  ## channel; anything else is rendered HTML (or the error overlay).
  if req.url.path == server.savePath and req.reqMethod == HttpPost:
    # Opt-in in-browser save: dispatch the POST body to the consumer's handler.
    # A same-origin fetch from the served editor lands here; the handler patches
    # the design-system file and the watcher (if any) reloads dependents.
    let saved = handleSave(server, req.body)
    await req.respond(saved.status.HttpCode, saved.body,
      newHttpHeaders({"Content-Type": saved.contentType,
        "Access-Control-Allow-Origin": "*"}))
    return
  if req.url.path == server.liveReloadPath and isWebSocketUpgrade(req):
    await serveWebSocket(server, req)
    return
  let (status, contentType, body) = handleRoute(server, req.url.path)
  await req.respond(status.HttpCode, body,
    newHttpHeaders({"Content-Type": contentType}))

proc serve*(server: DevServer; port = 8000; pollIntervalMs = 250;
            host = "127.0.0.1") {.async.} =
  ## Runs the dev server: binds `host:port`, serves rendered routes with the
  ## live-reload client injected, upgrades the reload endpoint to a WS, and
  ## polls the content dir every `pollIntervalMs` for edits (broadcasting a
  ## reload to every client on any change). Runs until cancelled.
  ##
  ## `host` defaults to `127.0.0.1` (LOOPBACK ONLY) -- a dev server must not
  ## silently expose unauthenticated docs on the LAN/tailnet. Pass `0.0.0.0`
  ## (e.g. via the consumer's `AH_DEV_HOST`/host arg) to reach it from other
  ## devices on a trusted private network.
  var http = newAsyncHttpServer()
  http.listen(Port(port), host)
  info "dev_server_listening", host = host, port = port,
    contentDir = server.contentDir
  # Warm the client bundle at startup. Compiling it lazily inside the request
  # handler (clientBundleJs on first `/assets/app.js`) blocks the single-threaded
  # event loop for the whole `nim js` compile (tens of seconds), which hangs the
  # server on the first page load. Do the heavy compile now, while the operator is
  # already waiting for startup, so every request is served from cache. A compile
  # failure is logged but does not stop the server -- the site works without JS
  # (progressive enhancement); `/assets/app.js` then 500s visibly per request.
  if server.clientEntry.len > 0:
    info "dev_server_precompiling_client_bundle", entry = server.clientEntry
    try:
      discard server.clientBundleJs()
    except CatchableError as e:
      error "dev_server_client_bundle_precompile_failed", msg = e.msg
  proc pollLoop() {.async.} =
    while true:
      await sleepAsync(pollIntervalMs)
      discard server.pollForChanges()
  asyncCheck pollLoop()
  while true:
    if http.shouldAcceptRequest():
      # The dev server is strictly single-threaded (one `asyncdispatch`
      # event loop), so `renderRoute`/chronicles reading module globals is
      # safe here even though it defeats the compiler's gcsafe inference
      # for `acceptRequest`'s callback type.
      await http.acceptRequest(proc(req: Request) {.async, gcsafe.} =
        {.cast(gcsafe).}:
          await processRequest(server, req))
    else:
      await sleepAsync(20)

when isMainModule:
  ## `nim c -r src/dev_server.nim [port]` — dev-serves the framework's own
  ## checked-in mini-site fixture. A real consumer's `dev` entry (or the
  ## CLI, M11 deliverable 3) constructs a `DevServer` over its own content
  ## dir + `DocsConfig` instead.
  let port = if paramCount() >= 1: parseInt(paramStr(1)) else: 8000
  let ds = newDevServer("tests/fixtures/mini-site")
  echo "isonim-docs dev server on http://localhost:", port
  waitFor serve(ds, port)
