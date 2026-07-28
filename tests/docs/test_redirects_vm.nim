## Tier 1 (ViewModel / pure-helper) M3 redirects suite -- dual-target:
## both `nim c -r` and `nim js -r` must pass.
##
## Proves the pure, filesystem-free half of M3 deliverable 3 (redirect
## and alias support for renamed pages): the typed `pkRedirect`/
## `rsRedirect` route contract (`src/core/routes.nim`), the
## authoring-to-routing alias bridge (`references.buildAliasMap`,
## `references.buildAliasRouteEntries`, `references.withAliasRedirects`),
## and the redirect ViewModel (`shell_vm.redirectShellViewModel`). All of
## it is exercised through in-memory `RouteEntry`/`ContentEntry` values
## built by hand -- no filesystem access anywhere -- so the exact same
## assertions hold on both targets. The real, whole-content-graph build
## wiring (`renderRoute` actually serving a 301, `checkContentGraph`
## auto-picking up authored `aliases:` front matter) is C-target-only
## and covered separately by `test_redirects_renderroute.nim`.

import std/[unittest, tables, sets]
import ../../src/core/content
import ../../src/core/markdown_vm
import ../../src/core/config
import ../../src/core/routes
import ../../src/core/references
import ../../src/core/shell_vm

suite "docs routes -- pkRedirect / rsRedirect contract (Tier 1, dual-target)":
  test "newRedirectEntry normalizes both its own pattern and its redirect target":
    let entry = newRedirectEntry("/guide/old-dsl/", "/guide/dsl")
    check entry.pageKind == pkRedirect
    check entry.status == rsRedirect
    check entry.canonicalPath == "/guide/old-dsl"
    check entry.redirectTo == "/guide/dsl"

  test "statusCode maps rsRedirect to a real HTTP 301":
    check statusCode(rsRedirect) == 301

  test "matchRoute resolves an old aliased path to its own pkRedirect entry, not the not-found entry":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
      newRedirectEntry("/guide/old-dsl", "/guide/dsl"),
    ])
    let match = matchRoute(manifest, "/guide/old-dsl")
    check match.entry.pageKind == pkRedirect
    check match.entry.status == rsRedirect
    check match.entry.redirectTo == "/guide/dsl"

  test "matchRoute still resolves a real route byte-for-byte the same when alias entries are present":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
      newRedirectEntry("/guide/old-dsl", "/guide/dsl"),
    ])
    let match = matchRoute(manifest, "/guide/dsl")
    check match.entry.pageKind == pkMarkdown
    check match.entry.status == rsOk

suite "docs shell -- redirectShellViewModel (Tier 1, dual-target)":
  test "redirectShellViewModel carries the entry's redirectTo and an empty nav, touching no content":
    let entry = newRedirectEntry("/guide/old-dsl", "/guide/dsl")
    let vm = redirectShellViewModel(entry)
    check vm.pageKind == pkRedirect
    check vm.redirectTo == "/guide/dsl"
    check vm.navigation.sidebar.sections.len == 0

  test "buildShellViewModel dispatches a pkRedirect entry to redirectShellViewModel without calling loadPage":
    let entry = newRedirectEntry("/guide/old-dsl", "/guide/dsl")
    let vm = buildShellViewModel(entry, docsConfig(),
      proc(contentPath: string): DocsPage = raise newException(IOError, "loadPage must not be called for a redirect entry"))
    check vm.pageKind == pkRedirect
    check vm.redirectTo == "/guide/dsl"

suite "docs references -- buildAliasMap (Tier 1, dual-target)":
  test "buildAliasMap maps a page's authored aliases to its manifest-bound canonical route":
    let entry = parseContentEntry("---\naliases: /guide/old-dsl, /guide/ancient-dsl\n---\n# The ui DSL\n\nBody.",
                                   "guide/dsl.md")
    let contentPathToRoute = {"guide/dsl.md": "/guide/dsl"}.toTable
    let aliases = buildAliasMap(@[entry], contentPathToRoute)
    check aliases.len == 2
    check aliases["/guide/old-dsl"] == "/guide/dsl"
    check aliases["/guide/ancient-dsl"] == "/guide/dsl"

  test "buildAliasMap skips content not bound to any real manifest route":
    let entry = parseContentEntry("---\naliases: /guide/old-dsl\n---\n# Draft\n\nBody.", "guide/dsl.md")
    let aliases = buildAliasMap(@[entry], initTable[string, string]())
    check aliases.len == 0

  test "buildAliasMap resolves through the manifest's canonical path, not the content graph's own derived routePath":
    # Mirrors the M0/M1 getting-started.md case (navigation_vm.navPage's own
    # docstring): a content entry's derived `routePath` and the route it's
    # actually bound to under the manifest can disagree; the alias must
    # resolve to the latter, since that's what `knownRoutes` is built from.
    let entry = parseContentEntry("---\naliases: /old-start\n---\n# Getting Started\n\nBody.",
                                   "getting-started.md")
    check entry.routePath == "/getting-started"
    let contentPathToRoute = {"getting-started.md": "/guide/getting-started"}.toTable
    let aliases = buildAliasMap(@[entry], contentPathToRoute)
    check aliases["/old-start"] == "/guide/getting-started"

suite "docs references -- buildAliasRouteEntries / withAliasRedirects (Tier 1, dual-target)":
  test "buildAliasRouteEntries mints one pkRedirect entry per authored alias, targeting the entry's own canonicalPath":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
    ])
    let content = {
      "guide/dsl.md": parseContentEntry(
        "---\naliases: /guide/old-dsl, /guide/ancient-dsl\n---\n# The ui DSL\n\nBody.", "guide/dsl.md"),
    }.toTable
    let entries = buildAliasRouteEntries(manifest, proc(contentPath: string): ContentEntry = content[contentPath])
    check entries.len == 2
    check entries[0].pageKind == pkRedirect
    check entries[0].redirectTo == "/guide/dsl"
    check entries[1].redirectTo == "/guide/dsl"

  test "buildAliasRouteEntries silently skips any manifest entry whose content fails to load":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
    ])
    let entries = buildAliasRouteEntries(manifest,
      proc(contentPath: string): ContentEntry = raise newException(IOError, "no such fixture file"))
    check entries.len == 0

  test "withAliasRedirects appends alias entries after the real entries, so a real route always wins a name clash":
    let manifest = newRouteManifest(@[
      newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
    ])
    let aliasEntries = @[newRedirectEntry("/guide/old-dsl", "/guide/dsl")]
    let extended = withAliasRedirects(manifest, aliasEntries)
    check extended.entries.len == 2
    check extended.entries[0].pageKind == pkMarkdown
    check extended.entries[1].pageKind == pkRedirect
    check matchRoute(extended, "/guide/old-dsl").entry.redirectTo == "/guide/dsl"
    check matchRoute(extended, "/guide/dsl").entry.pageKind == pkMarkdown

suite "docs references -- checkPageReferences honors an auto-built alias map exactly like a hand-built one (Tier 1, dual-target)":
  test "a page reference to an aliased-but-now-known route is not flagged":
    let doc = parseMarkdownDoc("# Other Guide\n\nSee [the renamed guide](/guide/old-dsl) for more.")
    let source = ContentSource(path: "guide/other.md", line: 1)
    let knownRoutes = ["/guide/dsl"].toHashSet()
    let aliases = {"/guide/old-dsl": "/guide/dsl"}.toTable
    let issues = checkPageReferences(doc, source, "/guide/other", knownRoutes,
      initTable[string, HashSet[string]](), aliases)
    check issues.len == 0
