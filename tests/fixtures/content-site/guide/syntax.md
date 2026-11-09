---
title: Syntax Guide
section: guide
order: 1
description: Code fences in every built-in language, admonitions and tabs.
---

# Syntax Guide

## Code Blocks

```nim
proc greet(name: string): string =
  # a comment
  result = "Hello, " & name & "! " & $42 & " " & $3.14
```

```bash
if [ -f "$HOME/.profile" ]; then
  echo 'found' # note
fi
```

```sh
export X=1
```

```json
{"key": "value", "n": 12.5e3, "ok": true, "none": null}
```

```ts
const x: number = 0x1F; // hex
/* block
   comment */
let s = `template ${x}`;
```

```js
function f() { return "s"; }
```

```TypeScript
interface I { a: string }
```

```cobol
DISPLAY 'unknown language stays plain'.
```

```
no language at all
```

## Admonitions

:::note
A note with `code`.
:::

:::tip
A tip.
:::

:::important
Important.
:::

:::warning
Back up first.
Then proceed.
:::

:::caution
Careful.
:::

:::danger
Danger.
:::

:::mystery
An unknown kind becomes a note.
:::

## Tabs

:::tabs
@tab Nim
```nim
echo 1
```
@tab Bash
```bash
echo 1
```
:::

## Rating

:::rating 3
:::

See the [home page](../index.md#getting-started-2).
