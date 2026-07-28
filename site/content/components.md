---
title: Live Component Embedding
description: Extracting custom component tags from markdown into bkComponent AST nodes, binding them by name to a consumer registry, per-embed isolated state, and the error boundary.
order: 9
---
# Live Component Embedding

isonim-docs lets a page embed live, interactive components written by the
consumer. A JSX-style tag in the markdown is extracted into a typed
`bkComponent` AST node and bound *by name* to a component the consumer
registered -- the framework ships none of its own, staying content-agnostic.

## Extracting component tags

A line opening with `<` immediately followed by a capitalized name is parsed
as a component tag (ordinary lowercase HTML like `<div>` stays plain text).
Its attributes are parsed into typed props: a quoted value is a string, an
unquoted all-digits token is an int, `true`/`false` is a bool, and a
valueless attribute is a bool `true`. Every prop also keeps its raw string,
and the `getStr`/`getInt`/`getBool` accessors read them leniently.

```nim runnable
import core/markdown_vm

let doc = parseMarkdownDoc("<Counter start=\"3\" active />", "demo.md")
var found = false
for blk in doc.blocks:
  if blk.kind == bkComponent:
    found = true
    doAssert blk.componentName == "Counter"
    doAssert blk.props.getInt("start") == 3      # quoted "3" reads as 3
    doAssert blk.props.getBool("active") == true # valueless -> bool true
doAssert found
```

A paired `<Card>...</Card>` tag captures its inner text as the embed's
`componentChildren`; a self-closing `<Card/>` has empty children.

## The registry and unknown tags

The consumer binds a name to a component via a registry. On the SSR string
path this is an `HtmlComponentRegistry`; on the browser/tree path it is the
generic `ComponentRegistry[R, E]`. Re-registering a name replaces it, so a
consumer can override a default.

```nim runnable
import core/markdown_vm
import components/component_registry

let reg = newHtmlComponentRegistry()
reg.register("Counter", proc(inst: ComponentInstance): string =
  "<button>" & inst.props.getStr("label", "count") & "</button>")

doAssert reg.hasComponent("Counter")
doAssert not reg.hasComponent("Unknown")
```

When the parser is given the registry's `isComponentKnown` predicate, an
unregistered tag is extracted as a **typed error node** at parse time -- never
a crash, never silent corruption -- so the page renders a visible fallback:

```nim runnable
import core/markdown_vm

let known = proc(name: string): bool = name == "Counter"
let doc = parseMarkdownDoc("<Mystery />", "demo.md", isComponentKnown = known)
for blk in doc.blocks:
  if blk.kind == bkComponent:
    doAssert blk.componentError.len > 0   # "unknown component: Mystery"
```

## Per-embed isolated state and the error boundary

Each embed is handed a `ComponentInstance` carrying a page-unique
`instanceId`. A consumer's render closure scopes its DOM ids and reactive
signals off that id, so two embeds of the same component on one page keep
**strictly isolated state** -- incrementing one counter never moves the
other. Every embed's render is wrapped in the M6 error boundary (see
[SEO & Error Handling](./seo.md)): a component that throws renders the
boundary's fallback while its sibling embeds keep working.
