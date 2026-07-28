## Tier 1 (pure ViewModel/ingest) M7 OpenAPI-ingestion suite -- DUAL-TARGET
## (`nim c -r` AND `nim js -r`).
##
## Proves M7 deliverable 1: `core/openapi.ingestOpenApi` parses an
## OpenAPI v3 spec supplied as YAML *or* JSON into the same typed model,
## resolves a local `$ref`, and reports a malformed spec as a typed error
## (`ok = false` + `errors`) rather than crashing.
##
## DUAL-TARGET NOTE: the fixture spec is embedded as a `const` string (no
## `std/os` file read), so the exact same YAML and JSON ingestion runs on
## BOTH the C and JS backends -- `core/openapi` is pure `std/strutils` +
## `std/json`, both dual-target, so there is no C-only split to guard.
## (The renderRoute suite, `test_api_reference_renderroute.nim`, exercises
## the real filesystem spec-file read on the C target.)

import std/unittest
import ../../src/core/openapi

const yamlSpec = """
openapi: 3.0.3
info:
  title: Pet Store
  version: 1.2.3
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
  /pets/{petId}:
    get:
      operationId: getPet
      summary: Get one pet
      parameters:
        - name: petId
          in: path
          required: true
          schema:
            type: string
      responses:
        "200":
          description: The pet.
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Pet'
        "404":
          description: Not found.
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
        tag:
          type: string
"""

const jsonSpec = """
{
  "openapi": "3.0.3",
  "info": { "title": "Pet Store", "version": "1.2.3", "description": "A tiny pet API." },
  "servers": [ { "url": "https://api.example.com/v1" } ],
  "paths": {
    "/pets": {
      "get": {
        "operationId": "listPets",
        "summary": "List all pets",
        "description": "Returns every pet.",
        "parameters": [
          { "name": "limit", "in": "query", "description": "How many to return.",
            "required": false, "schema": { "type": "integer", "format": "int32" } }
        ],
        "responses": {
          "200": { "description": "A list of pets.",
            "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Pet" } } } }
        }
      },
      "post": {
        "operationId": "createPet",
        "summary": "Create a pet",
        "requestBody": {
          "required": true,
          "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Pet" } } }
        },
        "responses": { "201": { "description": "Created." } }
      }
    },
    "/pets/{petId}": {
      "get": {
        "operationId": "getPet",
        "summary": "Get one pet",
        "parameters": [
          { "name": "petId", "in": "path", "required": true, "schema": { "type": "string" } }
        ],
        "responses": {
          "200": { "description": "The pet.",
            "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Pet" } } } },
          "404": { "description": "Not found." }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Pet": {
        "type": "object",
        "required": ["id", "name"],
        "properties": {
          "id": { "type": "integer", "format": "int64" },
          "name": { "type": "string", "description": "The pet's name." },
          "tag": { "type": "string" }
        }
      }
    }
  }
}
"""

proc findOp(spec: OpenApiSpec; httpMethod, path: string): OpenApiOperation =
  for op in spec.operations:
    if op.httpMethod == httpMethod and op.path == path: return op
  raise newException(ValueError, "operation not found: " & httpMethod & " " & path)

proc checkPetStore(ingest: OpenApiIngest) =
  ## The shared structural assertions applied to BOTH the YAML and JSON
  ## ingests, so the two formats are proven to produce the same model.
  check ingest.ok
  check ingest.errors.len == 0
  let spec = ingest.spec
  check spec.title == "Pet Store"
  check spec.version == "1.2.3"
  check spec.servers == @["https://api.example.com/v1"]
  # three operations: GET /pets, POST /pets, GET /pets/{petId}
  check spec.operations.len == 3

  let listPets = findOp(spec, "get", "/pets")
  check listPets.operationId == "listPets"
  check listPets.summary == "List all pets"
  check listPets.parameters.len == 1
  check listPets.parameters[0].name == "limit"
  check listPets.parameters[0].location == "query"
  check listPets.parameters[0].required == false
  check listPets.parameters[0].schema.typ == "integer"
  check listPets.parameters[0].schema.format == "int32"
  check listPets.responses.len == 1
  check listPets.responses[0].statusCode == "200"
  check listPets.responses[0].contentType == "application/json"

  # $ref resolution: the 200 response schema resolves to the Pet object,
  # retaining the ref name AND expanding the referenced properties.
  let petSchema = listPets.responses[0].schema
  check petSchema.refName == "Pet"
  check petSchema.typ == "object"
  check petSchema.properties.len == 3
  check petSchema.required == @["id", "name"]
  var propNames: seq[string] = @[]
  for p in petSchema.properties: propNames.add p.name
  check propNames == @["id", "name", "tag"]
  check petSchema.properties[0].schema.typ == "integer"
  check petSchema.properties[0].schema.format == "int64"

  let createPet = findOp(spec, "post", "/pets")
  check createPet.requestBody.present
  check createPet.requestBody.required
  check createPet.requestBody.contentType == "application/json"
  check createPet.requestBody.schema.refName == "Pet"
  check createPet.requestBody.schema.properties.len == 3

  let getPet = findOp(spec, "get", "/pets/{petId}")
  check getPet.parameters.len == 1
  check getPet.parameters[0].name == "petId"
  check getPet.parameters[0].location == "path"
  check getPet.parameters[0].required
  check getPet.responses.len == 2

  # components/schemas exposed as a typed list too
  check spec.schemas.len == 1
  check spec.schemas[0].name == "Pet"

suite "OpenAPI v3 ingestion (Tier 1, dual-target)":
  test "YAML ingestion parses the full model with $ref resolution":
    checkPetStore(ingestOpenApi(yamlSpec, "openapi.yaml"))

  test "JSON ingestion parses the same model as YAML":
    checkPetStore(ingestOpenApi(jsonSpec, "openapi.json"))

  test "YAML and JSON produce structurally identical operation sets":
    let y = ingestOpenApi(yamlSpec, "openapi.yaml")
    let j = ingestOpenApi(jsonSpec, "openapi.json")
    check y.spec.operations.len == j.spec.operations.len
    for i in 0 ..< y.spec.operations.len:
      check y.spec.operations[i].httpMethod == j.spec.operations[i].httpMethod
      check y.spec.operations[i].path == j.spec.operations[i].path
      check y.spec.operations[i].operationId == j.spec.operations[i].operationId

  test "format auto-detection works without a file extension (content sniff)":
    check ingestOpenApi(jsonSpec).ok      ## starts with '{' -> JSON
    check ingestOpenApi(yamlSpec).ok      ## otherwise -> YAML

  test "a malformed JSON spec yields a typed error, not a crash":
    let bad = ingestOpenApi("{ \"openapi\": \"3.0.0\", broken", "broken.json")
    check (not bad.ok)
    check bad.errors.len > 0

  test "an empty spec yields a typed error":
    let empty = ingestOpenApi("   ", "empty.yaml")
    check (not empty.ok)
    check empty.errors.len > 0

  test "a structurally invalid spec (no paths, no version) is flagged, not raised":
    let ingest = ingestOpenApi("title: nope\n", "nopaths.yaml")
    check (not ingest.ok)
    check ingest.errors.len > 0

  test "a cyclic $ref resolves to a stub instead of looping forever":
    const cyclic = """
openapi: 3.0.0
info:
  title: Cyclic
  version: "1.0"
paths:
  /node:
    get:
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Node'
components:
  schemas:
    Node:
      type: object
      properties:
        name:
          type: string
        next:
          $ref: '#/components/schemas/Node'
"""
    let ingest = ingestOpenApi(cyclic, "cyclic.yaml")
    check ingest.ok
    let op = findOp(ingest.spec, "get", "/node")
    let schema = op.responses[0].schema
    check schema.refName == "Node"
    check schema.properties.len == 2
    # the recursive `next` property keeps the ref name but is a stub (its
    # own properties are NOT expanded again -- the cycle is broken)
    var nextProp: OpenApiProperty
    for p in schema.properties:
      if p.name == "next": nextProp = p
    check nextProp.schema.refName == "Node"
    check nextProp.schema.properties.len == 0
