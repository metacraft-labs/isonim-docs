## isonim-docs Layer 3 — privacy-respecting analytics adapter (M12 deliverable 3).
##
## A vendor-neutral analytics hook: an inline `<script>` emitted into the
## `<head>` ONLY when a consumer configures it, and one that -- when
## `honorDnt` is set (the default) -- no-ops at runtime if the visitor sent
## a Do-Not-Track signal (`navigator.doNotTrack` / `window.doNotTrack` /
## `navigator.msDoNotTrack`). No vendor is baked in: the framework ships a
## generic first-party `beacon` adapter (a `navigator.sendBeacon`/`fetch`
## POST to a consumer-chosen endpoint) and a `custom` adapter (the consumer
## supplies the raw provider snippet), and the `AnalyticsAdapter` closure
## type lets a consumer plug in any provider (Plausible, Matomo, a
## self-hosted collector) without the framework hardcoding one.
##
## Pure/data + a closure (no platform imports), so it runs identically
## under `nim c` and `nim js`; the emitted script body is also fed to
## `csp.nim` so a strict CSP whitelists it by hash. Content-agnostic: the
## framework default (`defaultAnalyticsConfig`) is `apNone`, i.e. emits
## nothing. `test_csp_analytics.nim` asserts the config gating, the DNT
## guard, and the hash on both targets.

import ./config

export AnalyticsProvider, AnalyticsConfig, defaultAnalyticsConfig

type
  AnalyticsAdapter* = object
    ## The pluggable adapter interface (no vendor lock-in): a label plus a
    ## closure producing the provider-specific JS *core* (the DNT guard and
    ## the `<script>` wrapper are added uniformly around it, so an adapter
    ## author writes only the tracking call). A consumer registers a custom
    ## provider by constructing one of these -- mirrors
    ## `server_search.SearchBackend`.
    provider*: AnalyticsProvider
    makeCore*: proc(cfg: AnalyticsConfig): string {.closure.}

const
  analyticsScriptId* = "docs-analytics"
    ## Stable id on the emitted analytics `<script>`, so a test / the client
    ## can find it and so it reads as intentional, not injected.

# --- JS string escaping (single-quoted literals in the emitted snippet) -----

proc escapeJsSingle(s: string): string =
  ## Escapes a value for a single-quoted JS string literal in the emitted
  ## snippet -- so a consumer endpoint/siteId can't break out of the string
  ## or the surrounding `<script>`.
  result = "'"
  for c in s:
    case c
    of '\'': result.add "\\'"
    of '\\': result.add "\\\\"
    of '<': result.add "\\x3c"   ## can't form `</script>`
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    else: result.add c
  result.add '\''

# --- built-in adapters ------------------------------------------------------

proc beaconCore(cfg: AnalyticsConfig): string =
  ## The generic first-party beacon: POST a minimal pageview
  ## (`{p: location.pathname, r: document.referrer, s: siteId}`) to the
  ## configured endpoint via `sendBeacon`, falling back to a keepalive
  ## `fetch`. No third-party script, no cookies -- vendor-neutral by
  ## construction.
  "var d={p:location.pathname,r:document.referrer,s:" &
    escapeJsSingle(cfg.siteId) & "};" &
    "var u=" & escapeJsSingle(cfg.endpoint) & ";" &
    "var b=JSON.stringify(d);" &
    "if(navigator.sendBeacon){navigator.sendBeacon(u,b);}" &
    "else if(window.fetch){fetch(u,{method:'POST',body:b,keepalive:true});}"

proc customCore(cfg: AnalyticsConfig): string =
  ## The consumer-supplied raw JS body verbatim -- the escape hatch for any
  ## provider the framework doesn't ship. Trusted (it's the consumer's own
  ## build config), so it is emitted as-is.
  cfg.customScript

proc newBeaconAdapter*(): AnalyticsAdapter =
  AnalyticsAdapter(provider: apBeacon, makeCore: beaconCore)

proc newCustomAdapter*(): AnalyticsAdapter =
  AnalyticsAdapter(provider: apCustom, makeCore: customCore)

proc resolveAdapter*(cfg: AnalyticsConfig): AnalyticsAdapter =
  ## Picks the built-in adapter matching `cfg.provider`. A consumer with a
  ## bespoke provider bypasses this and passes its own `AnalyticsAdapter`
  ## to `analyticsScriptBody`/`renderAnalyticsHtml` directly.
  case cfg.provider
  of apBeacon: newBeaconAdapter()
  of apCustom: newCustomAdapter()
  of apNone: AnalyticsAdapter(provider: apNone, makeCore: proc(c: AnalyticsConfig): string = "")

# --- assembly ---------------------------------------------------------------

proc dntGuardOpen(honorDnt: bool): string =
  ## The runtime Do-Not-Track gate: reads the three historical DNT signals
  ## and returns early (no tracking) when any is asserted. Emitted only when
  ## `honorDnt` -- an analytics-off-by-DNT site never even runs the beacon.
  if not honorDnt: return ""
  "var dnt=(navigator.doNotTrack||window.doNotTrack||navigator.msDoNotTrack);" &
    "if(dnt=='1'||dnt==='yes'){return;}"

proc analyticsScriptBody*(cfg: AnalyticsConfig; adapter: AnalyticsAdapter): string =
  ## The exact inline-script body emitted for `cfg` (also the string
  ## `csp.cspHashSource` hashes). Empty when the adapter is `apNone`. The
  ## provider core is wrapped in a `try/catch` (analytics must never break a
  ## page) and, when `honorDnt`, behind the DNT early-return.
  if adapter.provider == apNone: return ""
  let core = adapter.makeCore(cfg)
  if core.len == 0: return ""
  "(function(){try{" & dntGuardOpen(cfg.honorDnt) & core & "}catch(e){}})();"

proc analyticsScriptBody*(cfg: AnalyticsConfig): string =
  ## Convenience overload using the built-in adapter for `cfg.provider`.
  analyticsScriptBody(cfg, resolveAdapter(cfg))

proc renderAnalyticsHtml*(cfg: AnalyticsConfig; adapter: AnalyticsAdapter): string =
  ## The analytics `<script>` for the head, or "" when unconfigured
  ## (`apNone`) or the adapter produced no core -- the config gating M12
  ## deliverable 3 requires ("emitted into the head ONLY when configured").
  let body = analyticsScriptBody(cfg, adapter)
  if body.len == 0: return ""
  "<script id=\"" & analyticsScriptId & "\">" & body & "</script>"

proc renderAnalyticsHtml*(cfg: AnalyticsConfig): string =
  ## Convenience overload using the built-in adapter for `cfg.provider`.
  renderAnalyticsHtml(cfg, resolveAdapter(cfg))
