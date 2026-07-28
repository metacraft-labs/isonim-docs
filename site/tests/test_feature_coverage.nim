## isonim-docs/site -- Verification test 3 (C-target only).
##
## Asserts the self-docs cover the WHOLE framework, not a subset: for every
## shipped framework capability (the set from `corrective.milestones.org`
## M1-M12) there is a real `content/` page documenting it, AND that page is a
## genuine auto-discovered, routable member of this site's own content graph
## (not merely a file on disk that no route serves). The capability -> page
## mapping is derived explicitly, so dropping a page -- the self-docs
## regressing to a subset of the framework -- fails this test. Real
## assertions, no skips.

import std/[unittest, os, tables, sets]
import core/routes

suite "isonim-docs self-docs -- every shipped framework feature has a content page (Tier 3, C-target)":
  test "the capability set from corrective.milestones.org M1-M12 each maps to a real content/ page":
    let repoRoot = currentSourcePath().parentDir().parentDir()
    let contentDir = repoRoot / "content"

    ## The shipped framework capability set (corrective.milestones.org
    ## M1-M12), each mapped to the `content/` page that documents it. A page
    ## may cover more than one closely-related capability (e.g. navigation
    ## and both search paths), but every capability must map to a page that
    ## exists and is served.
    let featurePages = {
      "M1: file-based routing & auto-discovery": "routing.md",
      "M1: content authoring & frontmatter": "getting-started.md",
      "M2: theming & design tokens / asset pipeline": "theming.md",
      "M3: extended markdown engine": "markdown.md",
      "M4: isomorphic rendering (SSG/SSR/SPA) & hydration": "index.md",
      "M5: navigation depth & client search": "navigation-and-search.md",
      "M6: SEO artifacts & error handling": "seo.md",
      "M7: OpenAPI REST reference": "api-reference.md",
      "M8: library (Nim) API reference & symbol anchors": "library-reference.md",
      "M9: live component embedding": "components.md",
      "M10: tutorials, versioning & i18n": "tutorials.md",
      "M11: plugin architecture": "plugins.md",
      "M11: dev server / HMR": "dev-server.md",
      "M11: CLI toolchain": "cli.md",
      "M12: deployment adapter (nginx)": "deployment.md",
      "M12: server-side search": "navigation-and-search.md",
      "M12: CSP & analytics": "security.md",
    }.toOrderedTable

    ## The pages the framework's own auto-discovery actually finds -- the set
    ## every mapped page must be a real, routable member of, so a mapping can
    ## never point at an orphan file no route serves.
    let manifest = buildManifestFromContent(contentDir)
    var discoveredContentPaths = initHashSet[string]()
    for entry in manifest.entries:
      if entry.pageKind != pkRedirect and entry.meta.contentPath.len > 0:
        discoveredContentPaths.incl entry.meta.contentPath

    check discoveredContentPaths.len > 0

    for capability, page in featurePages:
      checkpoint capability & " -> content/" & page
      ## 1. The documenting page exists on disk.
      check fileExists(contentDir / page)
      ## 2. It is a real auto-discovered, routable page, not an orphan file.
      check page in discoveredContentPaths

    ## The capabilities matrix / feature index page ties them all together.
    check fileExists(contentDir / "features.md")
    check "features.md" in discoveredContentPaths
