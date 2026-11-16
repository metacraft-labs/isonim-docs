## isonim-docs Layer 3 — `llms.txt` and `llms-full.txt` generation (`llmstxt.org`).
##
## Pure functions over `DocsConfig`, `RouteManifest`, and a content loader so
## both `build_site.nim` (SSG) and `dev_server.nim` (live preview) share one
## implementation. Activated only when `cfg.emitLlmsTxt` is `true` (opt-in,
## leaving default `docsConfig()` builds byte-unchanged).

when defined(js):
  {.error: "llms_txt.nim is a C-target SSG/dev-server helper".}

import std/[strutils, tables]
import ./config
import ./routes
import ./content
import ./base_path

proc humanizeSection(sec: string): string =
  if sec.len == 0: return "Overview"
  var words = sec.replace('-', ' ').replace('_', ' ').splitWhitespace()
  for i in 0 ..< words.len:
    if words[i].len > 0:
      words[i][0] = words[i][0].toUpperAscii()
  words.join(" ")

proc canonicalPageUrl*(baseUrl, routePath: string): string =
  let root = baseUrl.strip(leading = false, trailing = true, chars = {'/'})
  if root.len == 0:
    return routePath
  if routePath == "/":
    root & "/"
  else:
    root & routePath

proc markdownMirrorRelPaths*(routePath: string): seq[string] =
  ## Relative output paths for a route's raw Markdown mirrors (`llmstxt.org` v2):
  ## `/guides/install` emits `guides/install.md`, `guides/install/index.md`, and
  ## `guides/install/index.html.md` so agents appending `.md` to clean or slash
  ## URLs always resolve 200 OK without HTML chrome.
  let clean = routePath.strip(chars = {'/'})
  if clean.len == 0:
    @["index.md", "index.html.md"]
  elif clean.endsWith(".md"):
    @[clean]
  else:
    @[clean & ".md", clean & "/index.md", clean & "/index.html.md"]

proc markdownRelPath*(routePath: string): string =
  markdownMirrorRelPaths(routePath)[0]

proc canonicalMarkdownUrl*(baseUrl, routePath: string): string =
  let root = baseUrl.strip(leading = false, trailing = true, chars = {'/'})
  let mdRel = "/" & markdownRelPath(routePath)
  if root.len == 0: mdRel else: root & mdRel

proc stripGeneratedCommentLines(md: string): string =
  ## Strips standalone `<!-- generated:... -->` region markers outside code
  ## fences so raw `.md` mirrors and `llms-full.txt` stay clean for agents.
  var outLines: seq[string] = @[]
  var inFence = false
  for line in md.splitLines():
    let s = line.strip()
    if s.startsWith("```") or s.startsWith("~~~"):
      inFence = not inFence
    if not inFence and s.startsWith("<!-- generated:") and s.endsWith("-->"):
      continue
    outLines.add line
  outLines.join("\n").strip()

proc renderPageMarkdown*(contentDir: string; entry: RouteEntry): string =
  ## Returns the clean, front-matter-stripped Markdown body for `entry` so an
  ## agent fetching `<route>.md` receives only topic content.
  if entry.meta.contentPath.len == 0:
    return ""
  let ce = loadContentEntry(contentDir, entry.meta.contentPath)
  let body = stripGeneratedCommentLines(ce.page.body)
  let title = if ce.front.title.len > 0: ce.front.title
              elif entry.meta.title.len > 0: entry.meta.title
              else: ""
  if title.len > 0 and not body.startsWith("# "):
    "# " & title & "\n\n" & body & "\n"
  else:
    body & "\n"

proc orderedSections(found: seq[string]; configured: seq[string]): seq[string] =
  var seen: Table[string, bool]
  if "" in found:
    result.add ""
    seen[""] = true
  for s in configured:
    if s in found and s notin seen:
      result.add s
      seen[s] = true
  for s in found:
    if s notin seen:
      result.add s
      seen[s] = true

proc topSectionOf(routePath: string): string =
  let trimmed = routePath.strip(chars = {'/'})
  if trimmed.len == 0: return ""
  let slash = trimmed.find('/')
  if slash < 0: "" else: trimmed[0 ..< slash]

proc renderLlmsTxt*(cfg: DocsConfig; manifest: RouteManifest): string =
  ## Renders a compact `llmstxt.org` index (`# Title`, `> Summary`, grouped
  ## Markdown links with descriptions, plus an Optional link to `llms-full.txt`).
  var lines: seq[string] = @["# " & cfg.siteTitle, ""]
  if cfg.siteDescription.len > 0:
    lines.add "> " & cfg.siteDescription
    lines.add ""

  var bySection: Table[string, seq[RouteEntry]]
  var sectionNames: seq[string] = @[]
  for entry in manifest.entries:
    if entry.pageKind == pkRedirect or entry.status != rsOk:
      continue
    let sec = topSectionOf(entry.canonicalPath)
    if sec notin bySection:
      sectionNames.add sec
      bySection[sec] = @[]
    bySection[sec].add entry

  for sec in orderedSections(sectionNames, cfg.sectionOrder):
    lines.add "## " & humanizeSection(sec)
    lines.add ""
    for entry in bySection[sec]:
      let title = if entry.meta.title.len > 0: entry.meta.title else: entry.canonicalPath
      let url =
        if entry.meta.contentPath.len > 0:
          canonicalMarkdownUrl(cfg.baseUrl, entry.canonicalPath)
        else:
          canonicalPageUrl(cfg.baseUrl, entry.canonicalPath)
      if entry.meta.description.len > 0:
        lines.add "- [" & title & "](" & url & "): " & entry.meta.description
      else:
        lines.add "- [" & title & "](" & url & ")"
    lines.add ""

  let fullUrl = canonicalPageUrl(cfg.baseUrl, "/llms-full.txt")
  lines.add "## Optional"
  lines.add ""
  lines.add "- [Complete Documentation Corpus (llms-full.txt)](" & fullUrl & "): Single-file full-text Markdown reference of every page on this site."
  lines.add ""
  lines.join("\n")

proc renderLlmsFullTxt*(cfg: DocsConfig; contentDir: string; manifest: RouteManifest): string =
  ## Renders `llms-full.txt` by concatenating every non-redirect Markdown page's
  ## title, canonical URL, description, and body.
  var lines: seq[string] = @["# " & cfg.siteTitle & " — Complete Documentation", ""]
  if cfg.siteDescription.len > 0:
    lines.add "> " & cfg.siteDescription
    lines.add ""

  for entry in manifest.entries:
    if entry.pageKind == pkRedirect or entry.status != rsOk or entry.meta.contentPath.len == 0:
      continue
    let ce = loadContentEntry(contentDir, entry.meta.contentPath)
    let title = if ce.front.title.len > 0: ce.front.title
                elif entry.meta.title.len > 0: entry.meta.title
                else: entry.canonicalPath
    let url = canonicalPageUrl(cfg.baseUrl, entry.canonicalPath)
    lines.add "---"
    lines.add ""
    lines.add "## " & title
    lines.add ""
    lines.add "URL: " & url
    if ce.front.description.len > 0:
      lines.add "Description: " & ce.front.description
    lines.add ""
    lines.add stripGeneratedCommentLines(ce.page.body)
    lines.add ""

  lines.join("\n")

proc renderLlmsHeaders*(basePath: string): string =
  ## Renders static-host `_headers` advertising standard `rel="describedby"`
  ## (`llmstxt.org` v2 / RFC 8288) alongside `rel="llms-txt"` and UTF-8 plain
  ## text / Markdown content types.
  let base = normalizeBasePath(basePath)
  "/*\n" &
  "  Link: <" & base & "/llms.txt>; rel=\"describedby\"; type=\"text/plain\", <" &
    base & "/llms.txt>; rel=\"llms-txt\", <" &
    base & "/llms-full.txt>; rel=\"llms-full-txt\"\n\n" &
  base & "/llms.txt\n" &
  "  Content-Type: text/plain; charset=utf-8\n\n" &
  base & "/llms-full.txt\n" &
  "  Content-Type: text/plain; charset=utf-8\n\n" &
  base & "/*.md\n" &
  "  Content-Type: text/markdown; charset=utf-8\n"
