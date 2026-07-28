## M12 deliverable 3 (CSP manager + privacy-respecting analytics) suite --
## DUAL-TARGET: both `nim c -r` and `nim js -r` must pass.
##
## The CSP hashing, policy assembly, analytics adapter, DNT gating and the
## head-prelude composition (`shell.renderHeadSecurityTop`) are pure string
## work over `DocsConfig`, so they run identically on BOTH targets and are
## exercised here without a filesystem. The SSR wiring half -- that
## `renderRoute` actually emits the CSP meta (first in `<head>`) + the
## framework's inline scripts, with the correct hashes, only when a consumer
## enables them -- is `src/ssr.nim` (C-target-only), so it is guarded under
## `when not defined(js)`.
##
## The CSP hashes are pinned two ways: (1) against the published NIST
## SHA-256 vectors (so "the hash is real, not a stub"), and (2) against the
## EXACT body between the emitted `<script>` tags (so the meta whitelists
## precisely the scripts the page ships -- a browser enforcing the policy
## would run them and block anything else).

import std/[unittest, strutils]
import ../../src/core/config
import ../../src/core/csp
import ../../src/core/analytics
import ../../src/components/theme_toggle
import ../../src/components/shell

when not defined(js):
  import ../../src/ssr

# The exact body a browser hashes for each of the framework's inline
# scripts -- the text between the emitted `<script ...>` and `</script>`.
proc innerScript(html: string): string =
  ## Extracts the body of the FIRST inline `<script>` in `html`.
  let open = html.find(">")
  let close = html.find("</script>")
  doAssert open >= 0 and close > open
  html[open + 1 ..< close]

suite "CSP sha256 hashing -- pinned to NIST vectors + the real script bodies (dual-target)":

  test "sha256Base64 matches the published NIST vectors (the hash is real)":
    check sha256Base64("") == "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
    check sha256Base64("abc") == "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0="
    # A 448-bit multi-block message, exercising the padding/length path.
    check sha256Base64("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
      "JI1qYdIGOLjlwCaTDD5gOaM85Flk/yFn9uzt1BnbBsE="

  test "cspHashSource wraps the base64 digest in the CSP source grammar":
    check cspHashSource("abc") == "'sha256-ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0='"

  test "the theme bootstrap's CSP hash is over its EXACT emitted body":
    let bodyFromHtml = innerScript(renderThemeBootstrapHtml())
    # The body helper and the emitted `<script>` content are the same bytes...
    check bodyFromHtml == themeBootstrapScriptBody()
    # ...so hashing either yields the token a browser would match.
    check cspHashSource(themeBootstrapScriptBody()) == cspHashSource(bodyFromHtml)

suite "CSP policy assembly + per-page inline-script hashing (dual-target)":

  test "disabled CSP emits no policy and no meta (framework default)":
    let cfg = defaultCspConfig()
    check cfg.enabled == false
    check buildCspPolicy(cfg, @["(function(){})();"]) == ""
    check renderCspMetaHtml(cfg, @["(function(){})();"]) == ""

  test "strict CSP folds every inline-script hash into script-src":
    let cfg = strictCspConfig()
    let bodyA = "(function(){var a=1;})();"
    let bodyB = "(function(){var b=2;})();"
    let policy = buildCspPolicy(cfg, @[bodyA, bodyB])
    check policy.contains("default-src 'self'")
    check policy.contains("object-src 'none'")
    check policy.contains("base-uri 'self'")
    # script-src carries 'self' AND both computed hashes, no 'unsafe-inline'
    # (a strict, hash-based policy -- inline scripts ride in by hash, not by
    # blanket unsafe-inline).
    check policy.contains("script-src 'self' " & cspHashSource(bodyA) & " " &
      cspHashSource(bodyB))
    check not policy.contains("script-src 'unsafe-inline'")

  test "duplicate inline bodies collapse to a single hash source":
    let cfg = strictCspConfig()
    let body = "(function(){})();"
    let policy = buildCspPolicy(cfg, @[body, body])
    let h = cspHashSource(body)
    # exactly one occurrence of the hash in the whole policy
    check policy.count(h) == 1

  test "a policy without a configured script-src gets one created for the hashes":
    let cfg = CspConfig(enabled: true,
      directives: @[CspDirective(name: "default-src", sources: @["'self'"])])
    let body = "(function(){})();"
    let policy = buildCspPolicy(cfg, @[body])
    check policy.contains("script-src 'self' " & cspHashSource(body))

  test "renderCspMetaHtml wraps the policy in an http-equiv meta":
    let cfg = strictCspConfig()
    let body = "(function(){})();"
    let meta = renderCspMetaHtml(cfg, @[body])
    check meta.startsWith("<meta http-equiv=\"Content-Security-Policy\" content=\"")
    check meta.endsWith("\" />")
    check meta.contains(cspHashSource(body))

  test "cspHeaderValue equals the meta's policy (same string, header channel)":
    let cfg = strictCspConfig()
    let bodies = @["(function(){})();"]
    check cspHeaderValue(cfg, bodies) == buildCspPolicy(cfg, bodies)

suite "analytics adapter -- config gating + DNT gating, vendor-neutral (dual-target)":

  test "the framework default emits nothing (analytics is opt-in)":
    let cfg = defaultAnalyticsConfig()
    check cfg.provider == apNone
    check analyticsScriptBody(cfg) == ""
    check renderAnalyticsHtml(cfg) == ""

  test "an unconfigured DocsConfig emits no analytics script":
    check renderAnalyticsHtml(docsConfig().analytics) == ""

  test "the beacon adapter emits a first-party POST, no third-party script":
    let cfg = AnalyticsConfig(provider: apBeacon, endpoint: "/collect",
      siteId: "site42", honorDnt: true)
    let html = renderAnalyticsHtml(cfg)
    check html.startsWith("<script id=\"" & analyticsScriptId & "\">")
    check html.contains("sendBeacon")
    check html.contains("'/collect'")
    check html.contains("'site42'")
    # vendor-neutral: no external script src, no known-vendor host baked in.
    check not html.contains("<script src")
    check not html.contains("google-analytics")

  test "honorDnt=true wraps the beacon in a runtime Do-Not-Track early return":
    let cfg = AnalyticsConfig(provider: apBeacon, endpoint: "/c", honorDnt: true)
    let body = analyticsScriptBody(cfg)
    check body.contains("navigator.doNotTrack")
    check body.contains("window.doNotTrack")
    check body.contains("navigator.msDoNotTrack")
    check body.contains("return;")
    # the DNT check precedes the beacon call
    check body.find("doNotTrack") < body.find("sendBeacon")

  test "honorDnt=false omits the DNT guard (a site may legitimately opt out)":
    let cfg = AnalyticsConfig(provider: apBeacon, endpoint: "/c", honorDnt: false)
    let body = analyticsScriptBody(cfg)
    check not body.contains("doNotTrack")
    check body.contains("sendBeacon")

  test "the custom adapter emits the consumer's raw snippet (no vendor lock-in)":
    let cfg = AnalyticsConfig(provider: apCustom,
      customScript: "myTracker('pageview');", honorDnt: true)
    let body = analyticsScriptBody(cfg)
    check body.contains("myTracker('pageview');")
    check body.contains("doNotTrack")   # still DNT-gated

  test "a consumer-supplied adapter plugs in without touching the framework":
    # Prove the adapter interface is genuinely pluggable: a bespoke provider
    # constructed by the consumer, not one of the built-ins.
    let mine = AnalyticsAdapter(provider: apCustom,
      makeCore: proc(c: AnalyticsConfig): string = "plausible(" & c.siteId & ");")
    let cfg = AnalyticsConfig(provider: apCustom, siteId: "acme", honorDnt: true)
    let html = renderAnalyticsHtml(cfg, mine)
    check html.contains("plausible(acme);")

  test "the emitted analytics body escapes a hostile endpoint out of the JS string":
    let cfg = AnalyticsConfig(provider: apBeacon,
      endpoint: "'});</script><script>evil()//", honorDnt: false)
    let html = renderAnalyticsHtml(cfg)
    check not html.contains("</script><script>evil")

suite "head-prelude composition -- CSP meta first, then the hashed scripts (dual-target)":

  test "defaults collapse the prelude to exactly the theme bootstrap":
    let top = renderHeadSecurityTop(docsConfig())
    check top == renderThemeBootstrapHtml()
    check not top.contains("http-equiv")
    check not top.contains(analyticsScriptId)

  test "CSP + analytics on: meta precedes the scripts and hashes them both":
    var cfg = docsConfig()
    cfg.csp = strictCspConfig()
    cfg.analytics = AnalyticsConfig(provider: apBeacon, endpoint: "/collect",
      honorDnt: true)
    let top = renderHeadSecurityTop(cfg)
    # order: CSP meta, then theme bootstrap, then analytics.
    let metaAt = top.find("http-equiv")
    let themeAt = top.find(themeBootstrapScriptId)
    let anaAt = top.find(analyticsScriptId)
    check metaAt >= 0 and themeAt > metaAt and anaAt > themeAt
    # the meta whitelists the EXACT bodies of both emitted scripts.
    check top.contains(cspHashSource(themeBootstrapScriptBody()))
    check top.contains(cspHashSource(analyticsScriptBody(cfg.analytics)))

  test "CSP on but analytics off: only the theme bootstrap is hashed":
    var cfg = docsConfig()
    cfg.csp = strictCspConfig()
    let top = renderHeadSecurityTop(cfg)
    check top.contains(cspHashSource(themeBootstrapScriptBody()))
    check not top.contains(analyticsScriptId)

when not defined(js):
  suite "CSP + analytics SSR wiring -- renderRoute over the real head (C-target)":

    test "default config: no CSP meta, no analytics, theme bootstrap present":
      let (status, html) = renderRoute("/")
      check status == 200
      check not html.contains("http-equiv=\"Content-Security-Policy\"")
      check not html.contains("id=\"" & analyticsScriptId & "\"")
      check html.contains("id=\"" & themeBootstrapScriptId & "\"")

    test "enabled config: CSP meta (first in head) + analytics both emitted":
      var cfg = docsConfig()
      cfg.csp = strictCspConfig()
      cfg.analytics = AnalyticsConfig(provider: apBeacon, endpoint: "/collect",
        siteId: "docs", honorDnt: true)
      let (status, html) = renderRoute("/", cfg = cfg)
      check status == 200
      # the CSP meta is the first child of <head>, before any inline script.
      let headAt = html.find("<head>")
      let metaAt = html.find("http-equiv=\"Content-Security-Policy\"")
      let themeAt = html.find(themeBootstrapScriptId)
      let anaAt = html.find(analyticsScriptId)
      check headAt >= 0
      check metaAt > headAt
      check themeAt > metaAt
      check anaAt > themeAt
      # the served meta carries the correct hashes for the served scripts.
      check html.contains(cspHashSource(themeBootstrapScriptBody()))
      check html.contains(cspHashSource(analyticsScriptBody(cfg.analytics)))
      # analytics honors DNT and hits the first-party endpoint.
      check html.contains("navigator.doNotTrack")
      check html.contains("'/collect'")

    test "analytics-only config: script emitted but no CSP meta":
      var cfg = docsConfig()
      cfg.analytics = AnalyticsConfig(provider: apBeacon, endpoint: "/c",
        honorDnt: true)
      let (_, html) = renderRoute("/", cfg = cfg)
      check html.contains("id=\"" & analyticsScriptId & "\"")
      check not html.contains("http-equiv=\"Content-Security-Policy\"")
