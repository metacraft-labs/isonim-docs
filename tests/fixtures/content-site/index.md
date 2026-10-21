---
title: Content Site
description: A fixture that exercises every content-library feature the docs build renders.
---

# Content Site

Welcome to {{site}}. This page is built by the release gate and compared
byte for byte with `tests/golden/content-site/`, so a change to how
content is parsed, anchored or highlighted shows up as a diff.

## Getting Started!

Run `nimble install` first, then read the [syntax guide](./guide/syntax.md)
and its [code section](./guide/syntax.md#code-blocks). The
[components page](guide/components.md) shows the directives. Symbols such
as [[sym:Foo.bar]] stay code when nothing resolves them.

![A diagram](./img/diagram.png)

## Getting, Started

The same words as the heading above, so its anchor gets a numeric suffix.

## API & SDK: v2.0 -- Notes

- First item with `code`
- Second item with a [link](https://example.com/x)
- Third item

1. One
2. Two

## Ünïcode Heading Ωmega

| Name | Kind | Notes |
| --- | --- | --- |
| alpha | `int` | first |
| beta | string | [more](./guide/syntax.md) |

### ???

A heading made only of punctuation falls back to a fixed anchor.

## Getting Started!

A third copy of the first heading.
