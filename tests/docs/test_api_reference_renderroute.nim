## Tier 3 (SSR / `renderRoute`) M7 API-reference suite -- C-target only.
##
## Proves M7 deliverables 2 & 3: a `pkApiReference` route, bound to a real
## OpenAPI v3 spec file, round-trips through `src/ssr.renderRoute` into the
## strict three-column layout -- left endpoint nav (HTTP-method
## color-coded), center prose + parameter/response tables + collapsible
## schema tables, right synthesized code samples -- with a stable,
## deep-linkable per-operation anchor the left nav targets. Uses a real
## hermetic fixture spec file (never a mocked filesystem), exactly like
## `test_markdown_renderroute.nim`.

when defined(js):
  {.error: "test_api_reference_renderroute is a C-target-only suite".}

import std/[unittest, strutils]
import ../../src/ssr
import ../../src/core/routes
import ../../src/core/config
import ./helpers/fixture_dir
import ./helpers/html_normalize

const fixtureCfg = DocsConfig(siteTitle: "Fixture Docs", siteDescription: "Fixture docs site.",
                               defaultRoute: "/", stylesheetHref: "/assets/style.css")

const petStoreYaml = """
openapi: 3.0.3
info:
  title: Pet Store
  version: "1.0"
  description: A tiny pet API.
servers:
  - url: https://api.example.com/v1
paths:
  /pets:
    get:
      operationId: listPets
      summary: List all pets
      description: Returns every pet.
      parameters:
        - name: limit
          in: query
          description: How many to return.
          required: false
          schema:
            type: integer
            format: int32
      responses:
        "200":
          description: A list of pets.
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Pet'
    post:
      operationId: createPet
      summary: Create a pet
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Pet'
      responses:
        "201":
          description: Created.
components:
  schemas:
    Pet:
      type: object
      required: [id, name]
      properties:
        id:
          type: integer
          format: int64
        name:
          type: string
          description: The pet's name.
"""

suite "docs SSR renderRoute -- API reference pages (Tier 3, C-target)":
  test "renderRoute renders a pkApiReference spec into the strict three-column layout":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "api/openapi.yaml", petStoreYaml)
      let manifest = newRouteManifest(@[
        newRouteEntry("/api", pkApiReference,
          meta = RouteMeta(title: "API Reference", contentPath: "api/openapi.yaml")),
      ])

      let (status, html) = renderRoute("/api", fixtureDir, manifest, fixtureCfg)
      check status == 200
      let normalized = normalizeHtml(html)

      # The corrected framework head: <html> opens straight into <head>,
      # whose first child is the charset <meta> (UTF-8 decode fix).
      check normalized.startsWith("<html><head><meta charset=\"utf-8\" />")
      # head title uses the route meta title; visible page <h1> uses the
      # spec's own title (Pet Store), so both are exercised.
      check normalized.contains("<title>API Reference — Fixture Docs</title>")
      check normalized.find("<meta charset=\"utf-8\" />") < normalized.find("<title>")
      check normalized.contains("<h1 class=\"docs-title\">Pet Store</h1>")

      # strict THREE-COLUMN layout: the layout container + its three columns
      check normalized.contains("<div class=\"docs-api-layout\">")
      check normalized.contains("<nav class=\"docs-api-nav\"")
      check normalized.contains("<div class=\"docs-api-content\">")
      check normalized.contains("<div class=\"docs-api-samples\">")

      # HTTP-method color-coding classes on both operations
      check normalized.contains("docs-api-method-get")
      check normalized.contains("docs-api-method-post")
      check normalized.contains(">GET<")
      check normalized.contains(">POST<")

      # per-operation deep-link anchors, targeted by the left nav
      check normalized.contains("id=\"operation-listpets\"")
      check normalized.contains("id=\"operation-createpet\"")
      check normalized.contains("href=\"#operation-listpets\"")
      check normalized.contains("data-api-target=\"operation-listpets\"")

      # synthesized code samples: curl for both, plus at least one language
      check normalized.contains("curl -X GET")
      check normalized.contains("curl -X POST")
      check normalized.contains(">JavaScript<")

      # parameter table matching the spec
      check normalized.contains("<table class=\"docs-api-param-table\">")
      check normalized.contains(">limit<")
      check normalized.contains(">query<")

      # response table matching the spec
      check normalized.contains("<table class=\"docs-api-response-table\">")
      check normalized.contains(">200<")
      check normalized.contains(">201<")

      # collapsible schema table with the $ref-resolved Pet properties
      check normalized.contains("<details class=\"docs-api-schema-details\"")
      check normalized.contains("<summary class=\"docs-api-schema-summary\">Pet</summary>")
      check normalized.contains("<table class=\"docs-api-schema-table\">")
      check normalized.contains(">name<")

  test "renderRoute is stable across repeated calls against the same spec":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "api/openapi.yaml", petStoreYaml)
      let manifest = newRouteManifest(@[
        newRouteEntry("/api", pkApiReference,
          meta = RouteMeta(title: "API Reference", contentPath: "api/openapi.yaml")),
      ])
      let first = normalizeHtml(renderRoute("/api", fixtureDir, manifest, fixtureCfg).html)
      let second = normalizeHtml(renderRoute("/api", fixtureDir, manifest, fixtureCfg).html)
      check first == second

  test "a malformed spec renders an error notice, not a crash (HTTP 200, not 500)":
    withFixtureDir:
      writeFixtureFile(fixtureDir, "api/broken.yaml", "this is: not\n  a: valid\n    openapi")
      let manifest = newRouteManifest(@[
        newRouteEntry("/api", pkApiReference,
          meta = RouteMeta(title: "API Reference", contentPath: "api/broken.yaml")),
      ])
      let (status, html) = renderRoute("/api", fixtureDir, manifest, fixtureCfg)
      # tolerant: a bad spec still renders a real page (with the site
      # chrome + an error notice), never an unhandled crash / HTTP 500.
      check status == 200
      let normalized = normalizeHtml(html)
      check normalized.contains("docs-api-errors")
