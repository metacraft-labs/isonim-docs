---
title: CSP & Analytics
description: Build-time Content-Security-Policy generation with per-page inline-script SHA-256 hashing, and a vendor-neutral, DNT-honoring analytics adapter emitted only when configured.
order: 15
---
# CSP & Analytics

Two security- and privacy-facing features round out the head: a build-time
Content-Security-Policy manager and a vendor-neutral analytics hook. Both are
strictly opt-in -- the framework default emits neither, so an unconfigured
site's `<head>` is byte-for-byte unchanged.

## Content-Security-Policy

A strict CSP that forbids `'unsafe-inline'` must instead whitelist each inline
`<script>` a page emits by the SHA-256 of its exact body. Those bodies -- the
theme no-flash bootstrap, and the analytics beacon when configured -- are
known at build time, so `core/csp` hashes them and folds the resulting
`'sha256-...'` sources into the policy's `script-src`, emitting either a
`<meta http-equiv="Content-Security-Policy">` tag or the equivalent header
value. The SHA-256 is a from-scratch, dual-target implementation (Nim's stdlib
ships no sha256, and a CSP hash-source must be sha256/384/512).

```nim runnable
import std/strutils
import core/config
import core/csp

# CSP is opt-in: disabled by default, so nothing is emitted.
doAssert buildCspPolicy(defaultCspConfig(), @[]).len == 0

# A strict policy folds each inline script's hash into script-src.
let inlineScript = "console.log('theme bootstrap')"
let policy = buildCspPolicy(strictCspConfig(), @[inlineScript])
doAssert policy.contains("script-src")
doAssert policy.contains("'sha256-")
```

The hash-source for one script body is its `'sha256-<base64>'` expression --
the exact token a browser matches against the script text:

```nim runnable
import std/strutils
import core/csp

let src = cspHashSource("console.log('hi')")
doAssert src.startsWith("'sha256-")
doAssert src.endsWith("'")
```

## Analytics

The analytics hook is vendor-neutral: no third-party script is baked in. The
framework ships a first-party `beacon` adapter (a `navigator.sendBeacon` /
`fetch` POST to a consumer-chosen endpoint) and a `custom` adapter (the
consumer's own raw snippet), and the `AnalyticsAdapter` closure type lets a
consumer plug in any provider. The snippet is emitted into the head **only
when configured**, wrapped in `try/catch`, and -- when `honorDnt` (the
default) -- gated behind a runtime Do-Not-Track check, so a visitor who sent
a DNT signal is never tracked. The emitted body is also fed to the CSP
manager so a strict policy whitelists it by hash.

```nim runnable
import std/strutils
import core/config
import core/analytics

# Analytics is opt-in: apNone (the default) emits nothing.
doAssert renderAnalyticsHtml(defaultAnalyticsConfig()).len == 0

# A configured first-party beacon emits a DNT-guarded inline script.
let cfg = AnalyticsConfig(provider: apBeacon, endpoint: "/collect",
                          siteId: "isonim-docs", honorDnt: true)
let html = renderAnalyticsHtml(cfg)
doAssert html.contains("<script")
doAssert html.contains("doNotTrack")   # the runtime DNT guard
```
