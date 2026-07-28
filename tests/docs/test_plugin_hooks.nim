## M11 deliverable 1 suite -- dual-target: both `nim c -r` and `nim js -r`
## must pass (the plugin host is pure, platform-free code).
##
## Proves the plugin architecture (`src/core/plugin.nim`):
##
##   * a sample plugin's five lifecycle hooks (onConfig, preParse,
##     postParse, onRender, onBuildComplete) each fire, in the canonical
##     pipeline order, and their effects are observable (config mutated,
##     raw text transformed, AST mutated, HTML transformed, build info
##     reported);
##   * with two plugins registered, EVERY hook fires in registration
##     order (deterministic ordering, A before B);
##   * a plugin-registered custom `:::rating N` markdown directive is
##     recognised by the parser and RENDERS (its produced blocks appear in
##     the emitted HTML), while `:::tabs` and the built-in admonitions are
##     untouched; an unregistered `:::whatever` still falls through to the
##     admonition handling.
##
## The pure suite drives the exact code path `renderRoute`/`buildSite`
## use (`parseMarkdownDocWithPlugins` + the `apply*` hook procs). A second,
## C-target-only suite drives `src/ssr.renderRoute` end to end to prove the
## same hooks fire inside the real SSR pipeline.

import std/[unittest, strutils]
import ../../src/core/plugin
import ../../src/core/config
import ../../src/core/markdown_vm
import ../../src/components/markdown_view

type SampleEffects = ref object
  ## Shared, closure-captured recorder: every hook appends its own tag so
  ## a test can assert the exact firing order, and a few hooks record the
  ## value they saw so their effect is observable too.
  log: seq[string]

proc samplePlugin(tag: string; fx: SampleEffects): Plugin =
  ## A fully-exercised sample plugin. `tag` namespaces its log entries so
  ## two instances (A/B) prove registration-order determinism. Its custom
  ## `:::rating N` directive renders N filled stars as a paragraph.
  result.name = tag
  result.onConfig = proc(cfg: var DocsConfig) =
    fx.log.add tag & ":onConfig"
    cfg.siteDescription = "set-by-" & tag
  result.preParse = proc(body: string): string =
    fx.log.add tag & ":preParse"
    body.replace("PLACEHOLDER", "expanded-by-" & tag)
  result.postParse = proc(doc: var MarkdownDoc) =
    fx.log.add tag & ":postParse"
    doc.blocks.add Block(kind: bkParagraph,
      spans: @[InlineSpan(kind: ikText, text: "postparse-marker-" & tag)])
  result.onRender = proc(html: string): string =
    fx.log.add tag & ":onRender"
    html & "<!--rendered-by-" & tag & "-->"
  result.onBuildComplete = proc(info: BuildInfo) =
    fx.log.add tag & ":onBuildComplete:" & $info.pageCount
  let ratingRender = proc(args, body: string): seq[Block] =
    let n = try: args.strip().parseInt() except ValueError: 0
    @[Block(kind: bkParagraph,
      spans: @[InlineSpan(kind: ikText, text: "★".repeat(n))])]
  result.directives = @[DirectiveRegistration(name: "rating", render: ratingRender)]

suite "docs plugin host -- lifecycle hooks (Tier 1, dual-target)":
  test "every lifecycle hook fires in canonical pipeline order and mutates as declared":
    let fx = SampleEffects()
    let host = newPluginHost(samplePlugin("P", fx))

    var cfg = docsConfig()
    host.applyOnConfig(cfg)
    check cfg.siteDescription == "set-by-P"        # onConfig mutation observable

    let body = "# Title\n\nA PLACEHOLDER token."
    let doc = host.parseMarkdownDocWithPlugins(body)
    # preParse ran (token expanded), postParse ran (marker paragraph appended).
    let html = renderMarkdownBodyHtml(doc.blocks)
    check "expanded-by-P" in html
    check "postparse-marker-P" in html

    let finalHtml = host.applyOnRender(html)
    check finalHtml.endsWith("<!--rendered-by-P-->")

    host.applyOnBuildComplete(BuildInfo(pageCount: 3, outDir: "public"))

    check fx.log == @["P:onConfig", "P:preParse", "P:postParse",
                      "P:onRender", "P:onBuildComplete:3"]

  test "two plugins: each hook fires in registration order (A before B)":
    let fx = SampleEffects()
    let host = newPluginHost(samplePlugin("A", fx), samplePlugin("B", fx))

    var cfg = docsConfig()
    host.applyOnConfig(cfg)
    check cfg.siteDescription == "set-by-B"        # B ran last, so B wins

    let doc = host.parseMarkdownDocWithPlugins("# T\n\nbody")
    discard host.applyOnRender(renderMarkdownBodyHtml(doc.blocks))
    host.applyOnBuildComplete(BuildInfo(pageCount: 1, outDir: "public"))

    check fx.log == @[
      "A:onConfig", "B:onConfig",
      "A:preParse", "B:preParse",
      "A:postParse", "B:postParse",
      "A:onRender", "B:onRender",
      "A:onBuildComplete:1", "B:onBuildComplete:1"]

  test "an empty host is a total no-op (plugin-free build is unchanged)":
    let host = PluginHost()
    var cfg = docsConfig()
    let before = cfg.siteDescription
    host.applyOnConfig(cfg)
    check cfg.siteDescription == before
    check host.applyPreParse("raw") == "raw"
    check host.applyOnRender("<html>") == "<html>"
    let doc = host.parseMarkdownDocWithPlugins("# T\n\none paragraph")
    # Same blocks parseMarkdownDoc would yield with no directive closures --
    # compared by rendered HTML (`Block` is a case object, no derived `==`).
    check renderMarkdownBodyHtml(doc.blocks) ==
      renderMarkdownBodyHtml(parseMarkdownDoc("# T\n\none paragraph").blocks)

suite "docs plugin host -- custom markdown directives (Tier 1, dual-target)":
  test "a registered ':::rating N' directive is recognised and renders its blocks":
    let fx = SampleEffects()
    let host = newPluginHost(samplePlugin("P", fx))
    let doc = host.parseMarkdownDocWithPlugins(":::rating 5\nignored body\n:::")
    # The directive yields one paragraph; postParse then appends its marker.
    check doc.blocks.len == 2
    check doc.blocks[0].kind == bkParagraph
    check "★★★★★" in renderMarkdownBlockHtml(doc.blocks[0], "0")   # five stars rendered

  test "a custom directive composes with ordinary blocks in document order":
    let fx = SampleEffects()
    let host = newPluginHost(samplePlugin("P", fx))
    let doc = host.parseMarkdownDocWithPlugins("## Head\n\n:::rating 2\n:::\n\nafter")
    # postParse appended one marker paragraph, so: heading, rating, after, marker.
    check doc.blocks[0].kind == bkHeading
    check doc.blocks[1].kind == bkParagraph
    check "★★" in renderMarkdownBlockHtml(doc.blocks[1], "1")
    check doc.blocks[2].kind == bkParagraph

  test "':::tabs' stays a built-in even when custom directives are registered":
    let fx = SampleEffects()
    let host = newPluginHost(samplePlugin("P", fx))
    let doc = host.parseMarkdownDocWithPlugins(":::tabs\n@tab A\nBody.\n:::")
    check doc.blocks[0].kind == bkTabs

  test "an unregistered ':::note' still falls through to the built-in admonition":
    let fx = SampleEffects()
    let host = newPluginHost(samplePlugin("P", fx))   # only 'rating' is registered
    let doc = host.parseMarkdownDocWithPlugins(":::note\nHeads up.\n:::")
    check doc.blocks[0].kind == bkAdmonition
    check doc.blocks[0].admonitionKind == akNote


## --- C-target-only: the hooks fire inside the real SSR pipeline ---------
when not defined(js):
  import ../../src/ssr
  import ../../src/core/routes

  suite "docs plugin host -- renderRoute integration (Tier 3, C-target)":
    const fixtureDir = "tests/fixtures/mini-site"

    test "renderRoute runs onRender and postParse hooks for a markdown route":
      let fx = SampleEffects()
      let host = newPluginHost(samplePlugin("SSR", fx))
      let (status, html) = renderRoute("/getting-started", fixtureDir,
        buildManifestFromContent(fixtureDir), docsConfig(), host = host)
      check status == 200
      check html.endsWith("<!--rendered-by-SSR-->")   # onRender fired last
      check "postparse-marker-SSR" in html            # postParse mutated the AST
      check "SSR:preParse" in fx.log                   # preParse fired in-pipeline
      check "SSR:postParse" in fx.log
      check "SSR:onRender" in fx.log

    test "renderRoute with an empty host renders byte-for-byte unchanged":
      let manifest = buildManifestFromContent(fixtureDir)
      let a = renderRoute("/getting-started", fixtureDir, manifest, docsConfig())
      let b = renderRoute("/getting-started", fixtureDir, manifest, docsConfig(),
        host = PluginHost())
      check a.html == b.html
