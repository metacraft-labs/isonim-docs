## isonim-docs base-path support for project-subpath hosting.
##
## GitHub *project* Pages (and any deploy that serves a site under a URL prefix
## such as `https://<org>.github.io/<repo>/`) host the site below the domain
## root. The SSG otherwise emits every internal link, asset, stylesheet and
## search-index URL as ROOT-RELATIVE (`/assets/style.css`, `/getting-started`),
## which resolves against the domain root and 404s under a subpath.
##
## `DocsConfig.basePath` closes that gap. Left empty (the framework default) the
## build is byte-identical to before -- root hosting is unaffected. When set to
## e.g. `/isonim-docs`, `buildSite` prefixes every internal root-relative URL it
## emits (page `href`/`src`/`data-search-index-url`, stylesheet `url(...)`, and
## the search index's `routePath`s) with that prefix, so the published site
## resolves correctly under the subpath. Absolute (`https://…`), protocol-
## relative (`//…`) and fragment (`#…`) URLs are never touched, and the absolute
## canonical/sitemap URLs already carry the subpath via `baseUrl`.

import std/strutils

proc normalizeBasePath*(basePath: string): string =
  ## Canonicalize a configured base path: `""` stays `""` (root hosting);
  ## otherwise exactly one leading slash and no trailing slash, so
  ## `"isonim-docs"`, `"/isonim-docs"` and `"/isonim-docs/"` all yield
  ## `"/isonim-docs"`.
  let b = basePath.strip().strip(chars = {'/'})
  if b.len == 0: "" else: "/" & b

proc prefixRootRelativeUrls*(s, base: string; markers: openArray[string]): string =
  ## After each `markers` occurrence, insert `base` before a ROOT-RELATIVE URL
  ## value (one that starts `/x`, but NOT protocol-relative `//x`). Absolute,
  ## fragment and already-relative values are left untouched. `base` must be
  ## normalized (leading slash, no trailing). An empty `base` is a no-op.
  if base.len == 0: return s
  result = newStringOfCap(s.len + s.len div 8)
  var i = 0
  while i < s.len:
    var hit = false
    for m in markers:
      if s.continuesWith(m, i):
        let j = i + m.len
        # Root-relative iff the value begins with a single '/'. `j+1 == len`
        # (value is exactly "/") still counts; "//" (protocol-relative) does not.
        if j < s.len and s[j] == '/' and (j + 1 >= s.len or s[j + 1] != '/'):
          result.add m
          result.add base          # continue scanning from the '/', now after `base`
          i = j
          hit = true
          break
    if not hit:
      result.add s[i]
      inc i

const
  htmlUrlMarkers* = ["href=\"", "src=\"", "data-search-index-url=\""]
    ## The root-relative URL-bearing attributes the framework emits in page HTML.
  cssUrlMarkers* = ["url(\"", "url('", "url("]
    ## `url(...)` references in emitted CSS (fonts/images), quoted or bare.
  searchIndexMarkers* = ["\"routePath\":\""]
    ## The route URLs inside the JSON search index.

proc applyBasePathHtml*(html, base: string): string =
  ## Prefix every root-relative page-HTML URL (`href`/`src`/search-index attr).
  prefixRootRelativeUrls(html, base, htmlUrlMarkers)

proc applyBasePathCss*(css, base: string): string =
  ## Prefix every root-relative `url(...)` in emitted CSS.
  prefixRootRelativeUrls(css, base, cssUrlMarkers)

proc applyBasePathSearchIndex*(json, base: string): string =
  ## Prefix every root-relative `routePath` in the JSON search index.
  prefixRootRelativeUrls(json, base, searchIndexMarkers)
