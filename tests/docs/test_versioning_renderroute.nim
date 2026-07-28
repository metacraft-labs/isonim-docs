## Tier 3 (SSR `renderRoute`) M10 versioning integration -- C-target only
## (`ssr.nim` is a server-side entry, like every other `*_renderroute.nim`).
##
## Proves the versioning ViewModel (`core/version_vm`) is actually WIRED into
## `ssr.renderRoute` (M10 deliverable 2): passing a `VersionCatalog` makes a
## `/v1.2/`-prefixed request resolve to that version's ISOLATED content dir
## (`tests/fixtures/versioned-site/versions/v1.2/`) and renders the "outdated
## version" banner + version selector, while the unprefixed latest page serves
## the canonical content with NO banner, and an unknown version prefix 404s
## instead of leaking latest content.

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/version_vm
import ../../src/components/version_selector

const siteDir = "tests/fixtures/versioned-site/latest"
  ## The latest content root; older snapshots live in the SIBLING
  ## `tests/fixtures/versioned-site/versions/v<id>/` (see `versionContentDir`),
  ## so the latest walk never sees them.

proc catalog(): VersionCatalog =
  newVersionCatalog(@[
    newVersionInfo("2.0", "v2.0 (latest)"),
    newVersionInfo("1.2")], latestId = "2.0")

suite "docs versioning -- renderRoute wiring (Tier 3, C-target)":
  test "the latest (unprefixed) page serves canonical content with no banner":
    let (status, html) = renderRoute("/guide/x", siteDir, versions = catalog())
    check status == 200
    check "Guide X (latest)" in html
    check "ISOLATED v1.2" notin html
    check versionBannerClass notin html # no outdated banner on latest
    check versionSelectorClass in html  # selector still present

  test "a /v1.2/ page serves that version's isolated content + outdated banner":
    let (status, html) = renderRoute("/v1.2/guide/x", siteDir, versions = catalog())
    check status == 200
    check "ISOLATED v1.2" in html      # the v1.2 tree answered, not latest
    check "Guide X (latest)" notin html
    check versionBannerClass in html   # outdated banner rendered
    check "not the latest" in html
    check ("href=\"/guide/x\"" in html) # banner/selector link back to latest

  test "an unknown version prefix 404s instead of leaking latest content":
    let (status, html) = renderRoute("/v9.9/guide/x", siteDir, versions = catalog())
    check status == 404
    check "Page not found" in html          # the typed 404 main region
    check "This is the LATEST content" notin html # latest BODY never served
    check "ISOLATED v1.2" notin html

  test "with no catalog the site is unversioned (pre-M10 behaviour)":
    let (status, html) = renderRoute("/guide/x", siteDir)
    check status == 200
    check "Guide X (latest)" in html
    check versionSelectorClass notin html # no version chrome at all
    check versionBannerClass notin html
