---
title: Components
section: guide
order: 2
slug: directives
aliases: /old-components, /older-components
---

# Components

:::hero title="Welcome" subtitle="Docs for everyone"
:::button href="start.md" variant="primary"
Start
:::button href="https://example.com" variant="secondary"
Learn more
:::

:::cards
:::card title="Getting Started" icon="/img/start.svg" href="./syntax.md"
Begin here.
:::card title="Reference" href="https://example.com/ref"
Look things up.
:::

:::cards variant="compact"
:::card title="Compact" href="./syntax.md"
A compact card.
:::

:::button href="./syntax.md"
Read the syntax guide
:::

:::faq
:::q title="Is it fast?"
Yes.
:::q title="Is it free?"
Also yes.
:::

:::video https://youtu.be/xZsJ55JVqmU title="Demo"

:::form action="/support" method="post" submit="Send"
@field name="email" label="Email" type=email placeholder="you@example.com" required
@field name="topic" label="Topic" type=select options="Bug,Idea"
@field name="msg" label="Message" type=textarea
:::
