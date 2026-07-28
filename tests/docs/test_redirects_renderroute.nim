## Tier 3 (SSR / `renderRoute` + build-gate) M3 redirects suite --
## C-target only.
##
## Proves M3 deliverable 3 wired all the way into the real rendering
## shell and the real build-time reference gate: `renderRoute` resolves
## an old, renamed page's route to a real HTTP 301 with a rendered
## redirect page carrying its target (`src/ssr.nim`'s `renderRoute`,
## `src/core/routes.newRedirectEntry`), and `checkContentGraph`/
## `validateContentGraph` (the whole-graph build gate `src/check_links.nim`
## wires into `just docs-smoke`) automatically honor real, authored
## `aliases:` front matter without a caller having to rebuild the alias
## table by hand -- so a page rename that updates its own `aliases:`
## list never breaks an existing in-repo link to its old address.

when defined(js):
  {.error: "test_redirects_renderroute is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ../../src/core/references
import ./helpers/fixture_dir
import ./helpers/html_normalize

suite "docs SSR renderRoute -- alias redirects (Tier 3, C-target)":
  test "renderRoute resolves an old aliased path to a real 301 pointing at the renamed page's canonical route":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", """---
aliases: /guide/old-dsl
---
# The ui DSL

Body text.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
      ])

      let (status, html) = renderRoute("/guide/old-dsl", fixtureDir, manifest)
      check status == 301
      check normalizeHtml(html).contains("href=\"/guide/dsl\"")

  test "renderRoute still resolves the renamed page's own real route unchanged when an alias also exists":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", """---
aliases: /guide/old-dsl
---
# The ui DSL

Body text.
""")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(title: "The ui DSL", contentPath: "guide/dsl.md")),
      ])

      let (status, html) = renderRoute("/guide/dsl", fixtureDir, manifest)
      check status == 200
      check normalizeHtml(html).contains("Body text.")

  test "renderRoute still 404s a path that matches no real route and no alias":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", "# The ui DSL\n\nBody.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
      ])
      let (status, _) = renderRoute("/guide/never-existed", fixtureDir, manifest)
      check status == 404

suite "docs references -- checkContentGraph auto-derives aliases from real content front matter (Tier 3, C-target)":
  test "a link to a page's own authored alias resolves with no explicit aliases table passed in":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", """---
aliases: /guide/old-dsl
---
# The ui DSL

Body.
""")
      writeFixtureFile(fixtureDir, "guide/other.md",
        "# Other Guide\n\nSee [the renamed guide](/guide/old-dsl) for more.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(contentPath: "guide/other.md")),
      ])
      check checkContentGraph(fixtureDir, manifest).len == 0

  test "validateContentGraph does not raise for a real fixture graph whose only cross-link is through an authored alias":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "guide/dsl.md", """---
aliases: /guide/old-dsl
---
# The ui DSL

Body.
""")
      writeFixtureFile(fixtureDir, "guide/other.md",
        "# Other Guide\n\nSee [the renamed guide](/guide/old-dsl) for more.")
      let manifest = newRouteManifest(@[
        newRouteEntry("/guide/dsl", pkMarkdown, meta = RouteMeta(contentPath: "guide/dsl.md")),
        newRouteEntry("/guide/other", pkMarkdown, meta = RouteMeta(contentPath: "guide/other.md")),
      ])
      validateContentGraph(fixtureDir, manifest)

# The equivalent check against the real IsoNim content corpus's aliases +
# docsRouteManifest() now lives in the consumer package (M1 corrective
# deliverable 4: ../isonim/docs/users/tests/test_redirects.nim), since
# that corpus is consumer content, not framework fixture data.
