## M4b verification (JS half): the foundation "Save" issues the expected POST.
##
## The persistence half that lives in the browser is `postDocsFoundationSave`
## (and the `docsFetchPersist` closure the mount harness hands the workspace as
## `foundationSave`). This proves that action issues a `fetch` POST to the
## dev-server save route with the right URL + JSON payload shape -- by
## installing a mock `fetch` global and inspecting what it received.
##
## SCOPE: this is the JS-side half of the two-halves M4b coverage. The native
## `test_design_save_server.nim` proves the endpoint writes the file AND that
## the editor's Save button drives the broker into the `persist` closure (whose
## JS instance is exactly this `fetch`). The ONE step neither covers is a real
## browser click physically firing the network request end-to-end -- that is a
## documented Playwright-level e2e gap (see this file's and the server test's
## headers), not something reproducible under `nim js -r`.

when not defined(js):
  {.error: "test_editor_save_post must be compiled with the JS backend: nim js -r".}

# A mock `fetch` that records the last call, plus the minimal globals an
# imported editor-chain module may touch at load. `fetch` returns a thenable so
# any (unused) chaining is inert; it never throws, so the fire-and-forget
# `postDocsFoundationSave` records deterministically.
{.emit: """
(function() {
  var g = (typeof globalThis !== 'undefined') ? globalThis : this;
  g.__lastFetch = { called: false, url: '', method: '', body: '' };
  g.fetch = function(url, opts) {
    g.__lastFetch = { called: true, url: String(url),
      method: (opts && opts.method) || '',
      body: (opts && opts.body) || '' };
    return { then: function(){ return this; }, catch: function(){ return this; } };
  };
  if (typeof g.window === 'undefined') g.window = g;
  if (typeof g.localStorage === 'undefined') g.localStorage = {
    _s: {}, getItem: function(k){ return (k in this._s) ? this._s[k] : null; },
    setItem: function(k,v){ this._s[k] = String(v); },
    removeItem: function(k){ delete this._s[k]; } };
  if (typeof g.matchMedia === 'undefined') g.matchMedia = function(){
    return { matches: false, media: '', addEventListener: function(){},
      removeEventListener: function(){}, addListener: function(){}, removeListener: function(){} }; };
  if (typeof g.requestAnimationFrame === 'undefined')
    g.requestAnimationFrame = function(cb){ return setTimeout(function(){ try{cb(Date.now());}catch(e){} }, 0); };
  if (typeof g.cancelAnimationFrame === 'undefined')
    g.cancelAnimationFrame = function(id){ clearTimeout(id); };
})();
""".}

import std/[strutils, unittest]
import ../dtcg_workspace

proc lastCalled(): bool =
  {.emit: "`result` = globalThis.__lastFetch.called;".}
proc lastUrl(): cstring =
  {.emit: "`result` = globalThis.__lastFetch.url;".}
proc lastMethod(): cstring =
  {.emit: "`result` = globalThis.__lastFetch.method;".}
proc lastBody(): cstring =
  {.emit: "`result` = globalThis.__lastFetch.body;".}
proc resetFetch() =
  {.emit: "globalThis.__lastFetch = { called: false, url: '', method: '', body: '' };".}

suite "M4b: foundation Save issues the dev-server POST (JS)":

  test "postDocsFoundationSave POSTs the right URL + JSON payload":
    resetFetch()
    check not lastCalled()

    postDocsFoundationSave(docsSaveEndpoint, "--docs-accent", "light", "#123456")

    check lastCalled()
    check $lastUrl() == docsSaveEndpoint
    check $lastMethod() == "POST"
    let body = $lastBody()
    # The JSON payload names the var/side/value the server writeback consumes.
    check body.contains("\"var\":\"--docs-accent\"")
    check body.contains("\"side\":\"light\"")
    check body.contains("\"value\":\"#123456\"")

  test "the endpoint constant matches the framework default save path":
    check docsSaveEndpoint == "/__isonim_save"

  test "docsFetchPersist (the workspace's foundationSave) POSTs each edit":
    resetFetch()
    let persist = docsFetchPersist(docsSaveEndpoint)
    check persist("--docs-space-4", "light", "1.25rem")
    check lastCalled()
    check $lastUrl() == docsSaveEndpoint
    let body = $lastBody()
    check body.contains("\"var\":\"--docs-space-4\"")
    check body.contains("\"value\":\"1.25rem\"")

  test "a dark-side save carries side=dark":
    resetFetch()
    postDocsFoundationSave(docsSaveEndpoint, "--docs-accent", "dark", "#654321")
    check ($lastBody()).contains("\"side\":\"dark\"")
    check ($lastBody()).contains("\"value\":\"#654321\"")
