## Optional native integration: real files, real docs route loading, and real
## KaTeX. No mock output or successful missing-tool skips. Run in the shared
## content-tools Nix shell; the ordinary docs suite needs no external renderer.
import std/[unittest, os, strutils, tempfiles]
import isonim/content/ext/math
import ../../src/core/plugin
import ../../src/core/routes
import ../../src/ssr
import ../../src/build_site

let katex = getEnv("ISONIM_KATEX")
doAssert katex.len > 0, "ISONIM_KATEX not configured; use the content-tools shell"
let work = createTempDir("docs-math-source-", "")
let host = newPluginHost(Plugin(name: "math", renderers: mathHooks(katex).renderers))

suite "real docs math source coordinates":
  test "front matter title and blank lines retain invalid expression location":
    writeFile(work / "index.md", "---\ntitle: Metadata title\n---\n\n# Visible title\n\n\n$\\frac{$\n")
    var failure = ""
    try: discard renderRoute("/", contentDir = work, host = host, strictRenderErrors = true)
    except ValueError as e: failure = e.msg
    check "index.md:8: KaTeX exited with status 1" in failure
    check "ParseError" in failure
  test "tutorial display fences use their actual opening line":
    writeFile(work / "tutorial.md", "---\ntitle: Tutorial\nlayout: tutorial\n---\n\n# Visible title\n\n\n```math\n\\frac{\n```\n")
    var failure = ""
    try: discard renderRoute("/tutorial", contentDir = work, host = host, strictRenderErrors = true)
    except ValueError as e: failure = e.msg
    check "tutorial.md:9: KaTeX exited with status 1" in failure
  test "static build refuses invalid math and preserves the previous output":
    let output = work / "published"
    createDir(output)
    writeFile(output / "index.html", "previous published bytes")
    var failure = ""
    try: discard buildSite(contentDir = work, outDir = output, host = host)
    except ValueError as e: failure = e.msg
    check "index.md:8: KaTeX exited with status 1" in failure
    check readFile(output / "index.html") == "previous published bytes"
    let response = renderRoute("/", contentDir = work, host = host)
    check response.status == 500

  test "static build refuses missing selected content and preserves previous output":
    # A real file-loading failure after graph preflight is bypassed by the empty
    # host. This discriminates the builder's strict final-render error contract.
    let output = work / "missing-published"
    createDir(output)
    writeFile(output / "index.html", "previous selected-content bytes")
    let manifest = newRouteManifest(@[
      newRouteEntry("/", pkMarkdown, meta = RouteMeta(contentPath: "missing.md"))])
    var failure = ""
    try: discard buildSite(contentDir = work, outDir = output, manifest = manifest)
    except CatchableError as e: failure = e.msg
    check "missing.md" in failure
    check readFile(output / "index.html") == "previous selected-content bytes"

removeDir(work)
