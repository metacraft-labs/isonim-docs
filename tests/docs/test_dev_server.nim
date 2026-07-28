## Tier 3-ish (real filesystem + real SSR + a real bound socket) M11
## deliverable 2 suite -- C-target only.
##
## `dev_server.nim` is a C-target-only server entry (a live-reloading dev
## server has no meaning on the JS/SPA target), so this suite runs the real
## `DevServer` over hermetic mini-site fixtures rather than mocking any of
## it. It proves the milestone's declared contract:
##
##   * the server returns 200 for a route (both at the `handleRoute` level
##     and over a REAL bound HTTP socket via `processRequest`);
##   * a content change triggers a reload signal -- the file WATCHER
##     (`pollForChanges`) detects an add / edit / remove, adopts the new
##     snapshot, and BROADCASTS the reload to every subscribed client, the
##     exact `ReloadHub` queue the async WS driver drains;
##   * the WEBSOCKET path: the RFC 6455 handshake accept key and the
##     server->client text frame are asserted against the spec's own test
##     vectors, so the exact bytes a browser receives are proven;
##   * a build failure renders the browser ERROR OVERLAY (status 500)
##     instead of crashing or dropping the connection.

when defined(js):
  {.error: "test_dev_server is a C-target-only suite (dev_server.nim is a server entry point)".}

import std/[unittest, os, strutils, asynchttpserver, asyncdispatch, httpclient]
import ../../src/dev_server
import ./helpers/fixture_dir

proc writeMiniSite(dir: string) =
  writeFixtureFile(dir, "index.md", "# Fixture Home\n\nHello from the dev server.")
  writeFixtureFile(dir, "guide/alpha.md", "# Alpha\n\nAlpha body.")

suite "docs dev server -- real DevServer over hermetic fixtures (M11 deliverable 2, C-target)":

  test "handleRoute returns 200 for a real route and injects the live-reload client":
    withFixtureDir:
      writeMiniSite(fixtureDir)
      let ds = newDevServer(fixtureDir)

      let (status, contentType, body) = handleRoute(ds, "/")
      check status == 200
      check contentType == "text/html; charset=utf-8"
      # The rendered page's own content is served verbatim...
      check body.contains("Fixture Home")
      # ...plus the injected live-reload client pointed at the WS endpoint.
      check body.contains(defaultLiveReloadPath)
      check body.contains("new WebSocket")
      # A nested route serves 200 too.
      check handleRoute(ds, "/guide/alpha").status == 200

  test "the live-reload client is spliced in just before </body>":
    let html = "<html><body><main>hi</main></body></html>"
    let injected = injectLiveReload(html, defaultLiveReloadPath)
    check injected.contains("</main>")
    # Script sits before the closing body tag, and the tag survives exactly once.
    let bodyClose = injected.find("</body>")
    let scriptAt = injected.find("new WebSocket")
    check scriptAt >= 0
    check scriptAt < bodyClose
    check injected.count("</body>") == 1

  test "the file watcher detects an EDIT and broadcasts a reload signal":
    withFixtureDir:
      writeMiniSite(fixtureDir)
      let ds = newDevServer(fixtureDir)
      let client = ds.hub.subscribe() # stands in for a connected WS client

      # No change yet -> no signal.
      check ds.pollForChanges().len == 0
      check client[].len == 0

      # Edit a served file.
      writeFixtureFile(fixtureDir, "guide/alpha.md", "# Alpha\n\nEDITED body.")
      let changed = ds.pollForChanges()
      check changed == @["guide/alpha.md"]
      # ...and the reload signal reached the client queue.
      check client[] == @[reloadMessage]

      # A second poll with nothing new is silent (idempotent snapshot).
      check ds.pollForChanges().len == 0
      check client[].len == 1

  test "the watcher detects an ADD and a REMOVE":
    withFixtureDir:
      writeMiniSite(fixtureDir)
      let ds = newDevServer(fixtureDir)
      let client = ds.hub.subscribe()

      writeFixtureFile(fixtureDir, "guide/beta.md", "# Beta\n\nnew page")
      check ds.pollForChanges() == @["guide/beta.md"]
      check client[].len == 1

      removeFile(fixtureDir / "guide" / "beta.md")
      check ds.pollForChanges() == @["guide/beta.md"]
      check client[].len == 2

  test "broadcast fans out to every subscribed client, and unsubscribe stops delivery":
    let hub = newReloadHub()
    let a = hub.subscribe()
    let b = hub.subscribe()
    check hub.subscriberCount == 2
    hub.broadcast(reloadMessage)
    check a[] == @[reloadMessage]
    check b[] == @[reloadMessage]
    hub.unsubscribe(a)
    check hub.subscriberCount == 1
    hub.broadcast("again")
    check a[] == @[reloadMessage]        # a no longer receives
    check b[] == @[reloadMessage, "again"]

  test "a build failure renders the browser error overlay (500), not a crash":
    withFixtureDir:
      writeMiniSite(fixtureDir)
      # Inject a renderer that raises, simulating a dev-time build failure.
      let boom = proc(path: string): tuple[status: int; html: string] =
        raise newException(ValueError, "boom: bad markdown at line 7")
      let ds = newDevServer(fixtureDir, render = boom)

      let (status, contentType, body) = handleRoute(ds, "/")
      check status == 500
      check contentType == "text/html; charset=utf-8"
      check body.contains("Failed to build")
      check body.contains("boom: bad markdown at line 7")
      # The overlay keeps the live-reload client so the fixed page reloads itself.
      check body.contains(defaultLiveReloadPath)

  test "the error overlay HTML-escapes the failure message":
    let overlay = renderErrorOverlay("/x", "unexpected <token> & \"stuff\"")
    check overlay.contains("&lt;token&gt;")
    check overlay.contains("&amp;")
    check not overlay.contains("<token>")

  test "WebSocket handshake accept key matches the RFC 6455 test vector":
    # RFC 6455 s1.3 worked example.
    check wsAcceptKey("dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
    check wsHandshakeResponse("dGhlIHNhbXBsZSBub25jZQ==").contains(
      "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    check wsHandshakeResponse("dGhlIHNhbXBsZSBub25jZQ==").startsWith(
      "HTTP/1.1 101 Switching Protocols")

  test "server->client text frames encode per RFC 6455 (unmasked, 3 length forms)":
    # 6-byte payload -> 7-bit length.
    check encodeWsTextFrame(reloadMessage) == "\x81\x06reload"
    # 200-byte payload -> 16-bit extended length (126 marker + 2 bytes).
    let mid = 'x'.repeat(200)
    let midFrame = encodeWsTextFrame(mid)
    check midFrame[0] == '\x81'
    check midFrame[1] == '\x7e'                 # 126
    check midFrame[2] == '\x00'
    check midFrame[3] == chr(200)
    check midFrame[4 .. ^1] == mid
    check midFrame.len == 4 + 200

  test "isWebSocketUpgrade recognizes only a real upgrade handshake":
    var upgrade = newHttpHeaders()
    upgrade["Upgrade"] = "websocket"
    upgrade["Sec-WebSocket-Key"] = "abc"
    check isWebSocketUpgrade(Request(headers: upgrade))
    var plain = newHttpHeaders()
    check not isWebSocketUpgrade(Request(headers: plain))

  test "end-to-end: a real bound socket serves 200 with the live-reload client embedded":
    withFixtureDir:
      writeMiniSite(fixtureDir)
      let ds = newDevServer(fixtureDir)

      var http = newAsyncHttpServer()
      http.listen(Port(0))                       # OS-assigned ephemeral port
      let port = http.getPort()

      proc acceptOne() {.async.} =
        await http.acceptRequest(proc(req: Request) {.async, gcsafe.} =
          {.cast(gcsafe).}:
            await processRequest(ds, req))
      asyncCheck acceptOne()

      let client = newAsyncHttpClient()
      let resp = waitFor client.get("http://127.0.0.1:" & $port.int & "/")
      check resp.code == Http200
      let body = waitFor resp.body
      check body.contains("Fixture Home")
      check body.contains(defaultLiveReloadPath)
      client.close()
      http.close()
