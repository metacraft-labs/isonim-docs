## Tier 1 (ViewModel / pure-helper) M10 versioning suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free `src/core/version_vm.nim` (M10
## deliverable 2): parsing/building `/vX.Y/` route prefixes, resolving a
## request path to the version it targets, per-version CONTENT isolation
## (a `/v1.2/guide/x` matches that version's OWN manifest, not latest's) and
## per-version SEARCH-INDEX isolation, the "outdated version" banner shown on
## a known non-latest version, and the version selector. Route resolution is
## exercised against hand-built `RouteManifest`s (no filesystem), so the exact
## same assertions hold on both targets, mirroring `test_tutorial_vm.nim`.

import std/[unittest, strutils]
import ../../src/core/version_vm
import ../../src/core/routes

proc sampleCatalog(): VersionCatalog =
  ## Newest-first, latest = 2.0.
  newVersionCatalog(@[
    newVersionInfo("2.0", "v2.0 (latest)"),
    newVersionInfo("1.2"),
    newVersionInfo("1.0", "v1.0")], latestId = "2.0")

proc manifestTitled(title, contentPath: string): RouteManifest =
  ## A one-entry manifest binding "/guide/x" to a version-specific page, so a
  ## match's title/contentPath reveals WHICH version's content answered.
  newRouteManifest(@[
    newRouteEntry("/guide/x", pkMarkdown,
      meta = RouteMeta(title: title, contentPath: contentPath))])

suite "docs versioning -- /vX.Y/ prefix parse + build (Tier 1, dual-target)":
  test "versionPrefix mints the /vX.Y/ shape":
    check versionPrefix("1.2") == "/v1.2"

  test "splitVersionPrefix strips a version prefix into (id, basePath)":
    check splitVersionPrefix("/v1.2/guide/x") == ("1.2", "/guide/x")
    check splitVersionPrefix("/v1.2") == ("1.2", "/")
    check splitVersionPrefix("/v2.0/") == ("2.0", "/")

  test "an unprefixed path has no version and is returned normalized":
    check splitVersionPrefix("/guide/x") == ("", "/guide/x")
    check splitVersionPrefix("guide/x/") == ("", "/guide/x")

  test "a real page whose slug merely starts with 'v' is not a version":
    check splitVersionPrefix("/verbose") == ("", "/verbose")
    check splitVersionPrefix("/vim/setup") == ("", "/vim/setup")

  test "withVersionPrefix is the inverse of splitVersionPrefix":
    check withVersionPrefix("1.2", "/guide/x") == "/v1.2/guide/x"
    check withVersionPrefix("1.2", "/") == "/v1.2"
    let (id, base) = splitVersionPrefix("/v1.2/guide/x")
    check withVersionPrefix(id, base) == "/v1.2/guide/x"

suite "docs versioning -- resolving a path to its version (Tier 1, dual-target)":
  test "an unprefixed path resolves to the latest, never outdated":
    let r = resolveVersionedPath(sampleCatalog(), "/guide/x")
    check r.versionId == "2.0"
    check r.basePath == "/guide/x"
    check r.prefixed == false
    check r.known
    check r.outdated == false

  test "a known non-latest prefix resolves to that version and is outdated":
    let r = resolveVersionedPath(sampleCatalog(), "/v1.2/guide/x")
    check r.versionId == "1.2"
    check r.basePath == "/guide/x"
    check r.prefixed
    check r.known
    check r.outdated

  test "the latest version's own prefix resolves but is NOT outdated":
    let r = resolveVersionedPath(sampleCatalog(), "/v2.0/guide/x")
    check r.versionId == "2.0"
    check r.known
    check r.outdated == false

  test "an unknown version prefix is flagged (caller 404s), never outdated":
    let r = resolveVersionedPath(sampleCatalog(), "/v9.9/guide/x")
    check r.versionId == "9.9"
    check r.known == false
    check r.outdated == false

suite "docs versioning -- per-version content + index isolation (Tier 1, dual-target)":
  test "/v1.2/guide/x matches v1.2's OWN manifest, not latest's":
    let cat = sampleCatalog()
    let latest = manifestTitled("X (latest)", "guide/x.md")
    let v12 = manifestTitled("X (v1.2)", "guide/x.md")
    let r = resolveVersionedPath(cat, "/v1.2/guide/x")
    # The router matches the STRIPPED basePath against that version's manifest.
    check matchRoute(v12, r.basePath).entry.meta.title == "X (v1.2)"
    # ...and the same basePath against latest's manifest gives latest's content.
    let rl = resolveVersionedPath(cat, "/guide/x")
    check matchRoute(latest, rl.basePath).entry.meta.title == "X (latest)"

  test "versionContentDir isolates non-latest versions in a SIBLING versions/ dir":
    let cat = sampleCatalog()
    check versionContentDir("site/content", cat, "2.0") == "site/content"
    check versionContentDir("site/content", cat, "1.2") == "site/versions/v1.2"
    check versionContentDir("site/content/", cat, "1.0") == "site/versions/v1.0"
    check versionContentDir("content", cat, "1.2") == "./versions/v1.2"

  test "the search index url is version-isolated for non-latest versions":
    let cat = sampleCatalog()
    check versionedSearchIndexPath(cat, "2.0", "/search-index.json") == "/search-index.json"
    check versionedSearchIndexPath(cat, "1.2", "/search-index.json") == "/v1.2/search-index.json"

suite "docs versioning -- outdated banner (Tier 1, dual-target)":
  test "a known non-latest version shows the banner linking back to latest":
    let cat = sampleCatalog()
    let b = buildVersionBanner(cat, resolveVersionedPath(cat, "/v1.2/guide/x"))
    check b.show
    check b.versionId == "1.2"
    check b.latestId == "2.0"
    check b.latestUrl == "/guide/x" # same page, canonical (unprefixed) latest
    check "not the latest" in b.message

  test "the latest version shows no banner":
    let cat = sampleCatalog()
    check buildVersionBanner(cat, resolveVersionedPath(cat, "/guide/x")).show == false
    check buildVersionBanner(cat, resolveVersionedPath(cat, "/v2.0/guide/x")).show == false

  test "an unknown version shows no banner (it is a 404, not an old page)":
    let cat = sampleCatalog()
    check buildVersionBanner(cat, resolveVersionedPath(cat, "/v9.9/guide/x")).show == false

suite "docs versioning -- version selector (Tier 1, dual-target)":
  test "one option per catalog version, current flagged, urls per version":
    let cat = sampleCatalog()
    let sel = buildVersionSelector(cat, resolveVersionedPath(cat, "/v1.2/guide/x"))
    check sel.options.len == 3
    check sel.currentId == "1.2"
    # latest option links to the canonical unprefixed page; the viewed 1.2
    # option is current and links to the /v1.2/ page.
    check sel.options[0].id == "2.0"
    check sel.options[0].url == "/guide/x"
    check sel.options[0].current == false
    check sel.options[1].id == "1.2"
    check sel.options[1].url == "/v1.2/guide/x"
    check sel.options[1].current
    check sel.options[2].url == "/v1.0/guide/x"

  test "the label defaults to 'v' & id when none was declared":
    let cat = sampleCatalog()
    let sel = buildVersionSelector(cat, resolveVersionedPath(cat, "/guide/x"))
    check sel.options[0].label == "v2.0 (latest)"
    check sel.options[1].label == "v1.2" # no explicit label -> defaulted
