---
title: OpenAPI REST Reference
description: Build-time OpenAPI v3 ingestion (YAML + JSON) into a typed model and a Stripe-style three-column reference page with method color-coding, synthesized code samples, and deep-linkable per-operation anchors.
order: 7
---
# OpenAPI REST Reference

isonim-docs renders a REST API's OpenAPI v3 spec as a Stripe-style
three-column reference page (`pkApiReference`): a left endpoint nav, center
prose with parameter and schema tables, and right synthesized code samples.
The spec is a consumer-supplied YAML or JSON file bound to a route -- the
framework ships no spec of its own.

## Ingestion

`core/openapi.ingestOpenApi` parses a spec -- **either YAML or JSON**, chosen
by extension or a content sniff -- into a typed model (info, servers, paths,
operations, parameters, request/response schemas, `components/schemas`), with
local `$ref` resolution (cyclic refs are broken with a named stub). The YAML
path is a hand-written indentation subset parser, not a C-only YAML library,
so ingestion runs on both the C and JS backends.

Ingestion is **tolerant by contract**: a malformed spec never crashes the
build -- it yields `ok = false` with a populated `errors` list, so the page
can show an error notice instead.

```nim runnable
import core/openapi
import core/api_reference_vm

const spec = """{
  "openapi": "3.0.0",
  "info": { "title": "Pet API", "version": "1.0.0" },
  "servers": [ { "url": "https://api.example.com" } ],
  "paths": {
    "/pets": {
      "get": {
        "operationId": "listPets",
        "summary": "List all pets",
        "responses": { "200": { "description": "A list of pets." } }
      }
    }
  }
}"""

let ingest = ingestOpenApi(spec, "petstore.json")
doAssert ingest.ok
doAssert ingest.spec.title == "Pet API"
doAssert ingest.spec.operations.len == 1

let vm = buildApiReferenceViewModel(ingest)
doAssert vm.endpoints.len == 1
doAssert vm.endpoints[0].methodUpper == "GET"
# Every operation gets a deep-linkable anchor and synthesized samples.
doAssert vm.endpoints[0].anchorId.len > 0
doAssert vm.endpoints[0].samples.len >= 1   # curl + JavaScript + Python
```

A broken spec is flagged, never fatal:

```nim runnable
import core/openapi

let bad = ingestOpenApi("{ this is not valid json", "broken.json")
doAssert not bad.ok
doAssert bad.errors.len > 0
```

## The three-column page

`core/api_reference_vm` transforms the ingested spec into the render-ready
ViewModel: the left nav entries, the center parameter/response rows and
collapsible schema tables, and the right code samples (curl plus JavaScript
and Python, synthesized from the operation's own path, method, and request
body). HTTP methods are color-coded through a per-method CSS class, and every
operation gets a stable anchor minted through the same registry that mints
heading anchors -- so an in-site link to `#operation-...` resolves through
the exact same checker a heading-anchor link does.

```nim runnable
import std/strutils
import core/openapi
import core/api_reference_vm

# The left nav / center heading color-code each method via a CSS class.
doAssert methodClass("get") == "docs-api-method-get"
doAssert methodClass("post") == "docs-api-method-post"

const spec = """openapi: 3.0.0
info:
  title: Pet API
  version: "1.0.0"
paths:
  /pets:
    post:
      operationId: createPet
      summary: Create a pet
      responses:
        "201":
          description: Created.
"""

let ingest = ingestOpenApi(spec, "petstore.yaml")   # YAML ingests too
doAssert ingest.ok
let anchors = operationAnchorIds(ingest.spec)
doAssert anchors.len == 1
doAssert anchors[0].startsWith("operation-")   # deep-linkable per operation
```

Because the operation anchors join the site-wide anchor set, cross-links to
individual endpoints are validated by the same reference checker that guards
[library symbol references](./library-reference.md) and internal doc links.
