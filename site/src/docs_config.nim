## isonim-docs/site -- this site's own `DocsConfig`, branded for the
## isonim-docs FRAMEWORK's own documentation.
##
## These are the framework's OWN docs, a product distinct from CodeTracer
## and from the isonim-framework docs, so the branding here is isonim-docs':
## `siteTitle: "isonim-docs"`, an isonim-docs footer, and NO logo (the
## header renders the plain `.docs-title` text -- no CodeTracer mark is
## shipped). `stylesheetHref` is kept unchanged so the SSG hash/purge
## pipeline (and its non-dangling guarantee) is untouched; the look is
## delivered by the reused token layer (`theme_tokens.isonimDocsTokenLayer`)
## + `assets/style.css`, not by pointing at a different stylesheet.

import core/config

proc isonimDocsDocsConfig*(): DocsConfig =
  DocsConfig(
    siteTitle: "isonim-docs",
    siteDescription: "Documentation for isonim-docs -- the Nim documentation-site framework built on IsoNim.",
    defaultRoute: "/",
    stylesheetHref: "/assets/style.css",
    baseUrl: "https://isonim-docs.dev",
    # No `siteLogo`/`logoHref`: the framework's own docs ship no logo, so the
    # header is the plain `.docs-title` text ("isonim-docs"). `footerHtml`
    # fills the `.docs-footer` with the framework's own attribution line.
    footerHtml: "isonim-docs -- built with isonim-docs. " &
      "<a href=\"https://github.com/metacraft-labs\">metacraft-labs</a>.",
  )
