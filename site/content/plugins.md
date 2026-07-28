---
title: Plugins
description: The deterministic plugin host with onConfig / preParse / postParse / onRender / onBuildComplete lifecycle hooks and custom markdown-directive registration.
order: 11
---
# Plugins

The plugin host lets a consumer (or the framework itself) hook the
build/render pipeline at fixed points and register custom markdown
directives. It is pure data plus closures -- no filesystem, no platform
imports -- and an empty host is a total no-op, so a plugin-free build is
byte-for-byte unchanged.

## Lifecycle hooks

A `Plugin` declares only the hooks it uses (every hook is optional). The host
fires each hook across all registered plugins **in registration order**, so
ordering is deterministic and a later plugin sees an earlier one's edits. The
five hook points are:

- `onConfig` -- mutate the resolved `DocsConfig` once at startup;
- `preParse` -- transform a page's raw markdown text before parsing;
- `postParse` -- inspect or mutate the parsed AST (`MarkdownDoc.blocks`);
- `onRender` -- transform a page's final rendered HTML string;
- `onBuildComplete` -- observe the finished static build.

```nim runnable
import std/strutils
import core/plugin
import core/config

var host: PluginHost

# onConfig mutates the resolved config once at startup.
host.registerPlugin(Plugin(name: "brand",
  onConfig: proc(cfg: var DocsConfig) = cfg.siteTitle = "Rebranded Docs"))

var cfg = docsConfig()
host.applyOnConfig(cfg)
doAssert cfg.siteTitle == "Rebranded Docs"

# preParse threads a page's raw markdown through every plugin in order.
host.registerPlugin(Plugin(name: "footer",
  preParse: proc(body: string): string = body & "\n\nAppended by a plugin."))

doAssert host.applyPreParse("# Title").contains("Appended by a plugin.")
```

## Custom directives

A plugin can also register a custom `:::name args ... :::` directive: a
renderer that turns the directive's argument line and raw body into rendered
blocks, spliced into the document exactly where the directive appeared. An
unregistered `:::name` falls through to the built-in admonition handling
unchanged.

```nim runnable
import std/strutils
import core/plugin
import core/markdown_vm

let youtube = DirectiveRegistration(name: "youtube",
  render: proc(args: string; body: string): seq[Block] =
    @[Block(kind: bkParagraph, spans: @[
      InlineSpan(kind: ikText, text: "Embedded video: " & args)])])

var host = newPluginHost(Plugin(name: "media", directives: @[youtube]))
doAssert host.knowsDirective("youtube")

# Parsing through the host wires the directive into the markdown pipeline.
let doc = parseMarkdownDocWithPlugins(host, ":::youtube dQw4w9WgXcQ\n:::\n")
var text = ""
for blk in doc.blocks:
  if blk.kind == bkParagraph:
    for s in blk.spans: text.add s.text
doAssert text.contains("dQw4w9WgXcQ")
```

`parseMarkdownDocWithPlugins` is the one entry point that runs the whole
chain: `preParse` transforms the raw text, the host's directives are wired
into the parser, then `postParse` runs over the resulting AST. With an empty
host it is exactly `parseMarkdownDoc` -- the hooks are no-ops and the
directive closures are nil.
