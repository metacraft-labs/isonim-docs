## Tier 1 (pure) suite for M1 (corrective) deliverable 1 --
## `buildManifestFromEntries`/`buildManifestFromContent`
## (`src/core/routes.nim`) -- dual-target: both `nim c -r` and
## `nim js -r` must pass.
##
## Mirrors `test_docs_graph_integration.nim`'s own in-memory-graph
## convention (`parseContentEntry` over hand-written raw strings, no
## filesystem access) rather than a real directory walk -- there is no
## real filesystem on the JS target, so the real-`contentDir`-walking
## half of `buildManifestFromContent` is C-target-only and covered
## separately by `test_manifest_from_content_renderroute.nim`.
##
## Proves the CRITICAL RECONCILIATION the milestone calls for: unlike
## the hand-authored `docsRouteManifest()` (which can, and for
## `getting-started.md` does, bind a content file to a route path that
## disagrees with that file's own `content.deriveRoutePath`-derived
## route -- see `navigation_vm`'s module docstring), a manifest built by
## `buildManifestFromEntries` sets `RouteEntry.canonicalPath` directly
## from `ContentEntry.routePath`. There is only the one rule left, and
## since `navigation_vm.navPage` links every nav surface to that same
## `canonicalPath`, routing and navigation can no longer disagree for a
## manifest built this way.

import std/[unittest, sets]
import ../../src/core/content
import ../../src/core/routes
import ../../src/core/navigation_vm

suite "buildManifestFromEntries -- routing (Tier 1, dual-target)":
  test "one pkMarkdown entry per content file, canonicalPath set from the content loader's own derived routePath":
    let entries = @[
      parseContentEntry("# Home\n\nWelcome.", "index.md"),
      parseContentEntry("# Getting Started\n\nInstall the framework.", "guide/getting-started.md"),
    ]
    let manifest = buildManifestFromEntries(entries)
    check manifest.entries.len == 2
    check manifest.entries[0].pageKind == pkMarkdown
    check manifest.entries[0].canonicalPath == entries[0].routePath
    check manifest.entries[0].canonicalPath == "/"
    check manifest.entries[0].meta.contentPath == "index.md"
    check manifest.entries[1].canonicalPath == entries[1].routePath
    check manifest.entries[1].canonicalPath == "/guide/getting-started"
    check manifest.entries[1].meta.contentPath == "guide/getting-started.md"

  test "a nested index.md binds to its own section root, not the site root":
    let entries = @[
      parseContentEntry("# Home\n\nWelcome.", "index.md"),
      parseContentEntry("# Guide\n\nOverview.", "guide/index.md"),
    ]
    let manifest = buildManifestFromEntries(entries)
    check manifest.entries[0].canonicalPath == "/"
    check manifest.entries[1].canonicalPath == "/guide"

  test "meta.title/description/contentPath reflect front matter overrides, exactly like the content loader's own page/front":
    let raw = "---\ntitle: Custom Title\ndescription: A custom blurb.\n---\n# Ignored\n\nBody.\n"
    let entries = @[parseContentEntry(raw, "about.md")]
    let manifest = buildManifestFromEntries(entries)
    check manifest.entries[0].meta.title == "Custom Title"
    check manifest.entries[0].meta.description == "A custom blurb."

  test "an authored aliases: front matter value becomes a real pkRedirect entry targeting the file's own canonical route":
    let raw = "---\naliases: /old-about, /about-us\n---\n# About\n\nBody.\n"
    let entries = @[parseContentEntry(raw, "about.md")]
    let manifest = buildManifestFromEntries(entries)
    check manifest.entries.len == 3
    check manifest.entries[0].pageKind == pkMarkdown
    check manifest.entries[0].canonicalPath == "/about"
    var redirects: seq[RouteEntry] = @[]
    for entry in manifest.entries:
      if entry.pageKind == pkRedirect: redirects.add entry
    check redirects.len == 2
    for r in redirects:
      check r.status == rsRedirect
      check r.redirectTo == "/about"
    var aliasPaths = initHashSet[string]()
    for r in redirects: aliasPaths.incl r.canonicalPath
    check "/old-about" in aliasPaths
    check "/about-us" in aliasPaths

  test "no alias front matter yields no redirect entries":
    let entries = @[parseContentEntry("# About\n\nBody.", "about.md")]
    let manifest = buildManifestFromEntries(entries)
    check manifest.entries.len == 1

suite "buildManifestFromEntries -- reconciliation with navigation (Tier 1, dual-target)":
  test "routing and navigation agree on the exact same canonical path for a nested content file (no fork)":
    let entries = @[
      parseContentEntry("# Home\n\nWelcome.", "index.md"),
      parseContentEntry("# Getting Started\n\nInstall the framework.", "guide/getting-started.md"),
    ]
    let byPath = block:
      var t: seq[(string, ContentEntry)] = @[]
      for e in entries: t.add (e.source.path, e)
      t
    proc loadEntry(contentPath: string): ContentEntry =
      for (path, e) in byPath:
        if path == contentPath: return e
      raise newException(ValueError, "missing fixture entry: " & contentPath)

    let manifest = buildManifestFromEntries(entries)
    let pages = buildNavPages(manifest, loadEntry)
    var found = false
    for page in pages:
      if page.slug == "getting-started":
        found = true
        # The content loader's own derived routePath ("/guide/getting-started")
        # and the manifest's canonicalPath agree -- unlike the hand-authored
        # docsRouteManifest()'s "/guide/getting-started" binding for the flat
        # `getting-started.md` file, there is no disagreement left to reconcile.
        check page.routePath == entries[1].routePath
        check page.routePath == "/guide/getting-started"
    check found

  test "nav order still follows front matter order/slug within a section, exactly like loadContentEntries' own sort":
    let entries = @[
      parseContentEntry("---\norder: 2\n---\n# Advanced\n\nBody.", "guide/advanced.md"),
      parseContentEntry("---\norder: 1\n---\n# Getting Started\n\nBody.", "guide/getting-started.md"),
    ]
    let manifest = buildManifestFromEntries(entries)
    proc loadEntry(contentPath: string): ContentEntry =
      for e in entries:
        if e.source.path == contentPath: return e
      raise newException(ValueError, "missing fixture entry: " & contentPath)
    let pages = buildNavPages(manifest, loadEntry)
    let sidebar = buildSidebar(pages, "")
    check sidebar.sections.len == 1
    check sidebar.sections[0].items.len == 2
    check sidebar.sections[0].items[0].title == "Getting Started"
    check sidebar.sections[0].items[1].title == "Advanced"
