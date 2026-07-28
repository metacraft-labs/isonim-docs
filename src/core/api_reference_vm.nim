## isonim-docs Layer 3 — API reference ViewModel (M7 deliverables 2 & 3).
##
## Pure, dual-target transform from the ingested `openapi.OpenApiSpec`
## into a render-ready ViewModel for the Stripe-style three-column
## reference page: the left endpoint nav, the center per-operation
## metadata (parameter rows + the request/response body schemas the
## component renders as collapsible tables), and the right synthesized
## code samples (curl + JavaScript + Python). Every operation gets a
## stable, deep-linkable anchor id (M7 deliverable 3) minted through the
## exact same `anchors.AnchorIdRegistry`/`slugifyHeadingText` rules the
## markdown heading anchors use, so an operation anchor slugs and dedups
## identically to a heading anchor and plugs into the same cross-link/
## anchor resolution (`operationAnchorIds` exposes the set the reference
## checker validates deep links against).
##
## No platform/CSS imports (only `std/strutils`, `core/openapi`,
## `core/anchors`), so it is headless-testable on both `nim c` and
## `nim js`, exactly like the other `*_vm.nim` modules.

import std/strutils
import ./openapi
import ./anchors

type
  ApiParamRow* = object
    name*: string
    location*: string
    typ*: string
    required*: bool
    description*: string

  ApiResponseRow* = object
    status*: string
    description*: string
    typ*: string
    schema*: OpenApiSchema

  ApiCodeSample* = object
    label*: string   ## "curl" / "JavaScript" / "Python"
    lang*: string    ## code-fence language class hint
    code*: string

  ApiEndpointViewModel* = object
    anchorId*: string
    methodUpper*: string   ## "GET" / "POST" / ...
    methodClass*: string   ## "docs-api-method-get" / ...
    path*: string
    summary*: string
    description*: string
    parameters*: seq[ApiParamRow]
    requestBody*: OpenApiRequestBody
    responses*: seq[ApiResponseRow]
    samples*: seq[ApiCodeSample]

  ApiNavEntry* = object
    anchorId*: string
    methodUpper*: string
    methodClass*: string
    path*: string
    summary*: string

  ApiReferenceViewModel* = object
    title*: string
    description*: string
    navEntries*: seq[ApiNavEntry]
    endpoints*: seq[ApiEndpointViewModel]
    errors*: seq[string]

proc methodClass*(httpMethod: string): string =
  ## The method-specific CSS class the left nav + center heading use for
  ## HTTP-method color-coding (`assets/style.css` maps each onto a color).
  "docs-api-method-" & httpMethod.toLowerAscii()

proc schemaTypeLabel*(schema: OpenApiSchema): string =
  ## A short human display label for a schema's type: the referenced
  ## component name when it came from a `$ref`, `T[]` for an array of `T`,
  ## the scalar type otherwise (with any `format` in parentheses).
  if schema == nil: return ""
  if schema.refName.len > 0: return schema.refName
  if schema.typ == "array" and schema.items != nil:
    return schemaTypeLabel(schema.items) & "[]"
  result = schema.typ
  if schema.format.len > 0:
    result = (if result.len > 0: result else: "value") & " (" & schema.format & ")"

# --- Code-sample synthesis ------------------------------------------------

proc sampleValueForType(schema: OpenApiSchema): string =
  ## A JSON placeholder literal for a scalar/ref schema, used when
  ## synthesizing a request-body example.
  if schema == nil: return "null"
  case schema.typ
  of "string": "\"string\""
  of "integer", "number": "0"
  of "boolean": "true"
  of "array": "[]"
  else:
    if schema.refName.len > 0 or schema.typ == "object": "{ }" else: "null"

proc sampleRequestJson(schema: OpenApiSchema): string =
  ## A one-level JSON skeleton `{ "prop": <value>, ... }` from an object
  ## schema's top-level properties -- enough to make the synthesized
  ## samples concrete without recursing into every nested schema.
  if schema == nil: return "{}"
  if schema.properties.len == 0: return "{}"
  var parts: seq[string] = @[]
  for p in schema.properties:
    parts.add "\"" & p.name & "\": " & sampleValueForType(p.schema)
  "{ " & parts.join(", ") & " }"

proc buildCurlSample(baseUrl: string; endpoint: ApiEndpointViewModel;
                      requestBody: OpenApiRequestBody): ApiCodeSample =
  let url = baseUrl & endpoint.path
  var code = "curl -X " & endpoint.methodUpper & " \"" & url & "\""
  if requestBody.present:
    code.add " \\\n  -H \"Content-Type: application/json\""
    code.add " \\\n  -d '" & sampleRequestJson(requestBody.schema) & "'"
  ApiCodeSample(label: "curl", lang: "bash", code: code)

proc buildJavaScriptSample(baseUrl: string; endpoint: ApiEndpointViewModel;
                            requestBody: OpenApiRequestBody): ApiCodeSample =
  let url = baseUrl & endpoint.path
  var code = "const res = await fetch(\"" & url & "\", {\n"
  code.add "  method: \"" & endpoint.methodUpper & "\""
  if requestBody.present:
    code.add ",\n  headers: { \"Content-Type\": \"application/json\" }"
    code.add ",\n  body: JSON.stringify(" & sampleRequestJson(requestBody.schema) & ")"
  code.add "\n});\nconst data = await res.json();"
  ApiCodeSample(label: "JavaScript", lang: "javascript", code: code)

proc buildPythonSample(baseUrl: string; endpoint: ApiEndpointViewModel;
                        requestBody: OpenApiRequestBody): ApiCodeSample =
  let url = baseUrl & endpoint.path
  var code = "import requests\n\nresp = requests." & endpoint.methodUpper.toLowerAscii() &
    "(\"" & url & "\""
  if requestBody.present:
    code.add ", json=" & sampleRequestJson(requestBody.schema)
  code.add ")\ndata = resp.json()"
  ApiCodeSample(label: "Python", lang: "python", code: code)

# --- ViewModel assembly ---------------------------------------------------

proc operationAnchorId*(reg: var AnchorIdRegistry; op: OpenApiOperation): string =
  ## The one place an operation's deep-link anchor id is minted (M7
  ## deliverable 3): `operation-<slug>` where the slug is the operationId
  ## when present, else `<method> <path>`, slugged + deduped through the
  ## exact same `anchors` rules the markdown heading anchors use.
  let base =
    if op.operationId.len > 0: op.operationId
    else: op.httpMethod & " " & op.path
  "operation-" & reg.nextId(base)

proc operationAnchorIds*(spec: OpenApiSpec): seq[string] =
  ## The deep-link anchor ids an API-reference page exposes -- the set the
  ## cross-link/anchor resolver (`references.checkContentGraph`) validates
  ## an in-site `#operation-...` fragment against, so a link to an
  ## operation anchor resolves the same way a link to a heading anchor
  ## does. Rebuilds the ids with a fresh registry, matching
  ## `buildApiReferenceViewModel` exactly.
  var reg = newAnchorIdRegistry()
  for op in spec.operations:
    result.add operationAnchorId(reg, op)

proc buildApiReferenceViewModel*(ingest: OpenApiIngest; fallbackTitle: string = ""):
    ApiReferenceViewModel =
  ## Assembles the render-ready ViewModel from an ingested spec. Tolerant:
  ## `ingest.errors` are carried through so the page can show an error
  ## notice for a malformed spec instead of the caller crashing.
  let spec = ingest.spec
  result.title = if spec.title.len > 0: spec.title else: fallbackTitle
  result.description = spec.description
  result.errors = ingest.errors

  let baseUrl = if spec.servers.len > 0: spec.servers[0] else: ""

  var reg = newAnchorIdRegistry()
  for op in spec.operations:
    var ep = ApiEndpointViewModel(
      anchorId: operationAnchorId(reg, op),
      methodUpper: op.httpMethod.toUpperAscii(),
      methodClass: methodClass(op.httpMethod),
      path: op.path,
      summary: op.summary,
      description: op.description,
      requestBody: op.requestBody)

    for p in op.parameters:
      ep.parameters.add ApiParamRow(
        name: p.name, location: p.location,
        typ: schemaTypeLabel(p.schema), required: p.required,
        description: p.description)

    for r in op.responses:
      ep.responses.add ApiResponseRow(
        status: r.statusCode, description: r.description,
        typ: schemaTypeLabel(r.schema), schema: r.schema)

    ep.samples.add buildCurlSample(baseUrl, ep, op.requestBody)
    ep.samples.add buildJavaScriptSample(baseUrl, ep, op.requestBody)
    ep.samples.add buildPythonSample(baseUrl, ep, op.requestBody)

    result.navEntries.add ApiNavEntry(
      anchorId: ep.anchorId, methodUpper: ep.methodUpper,
      methodClass: ep.methodClass, path: ep.path, summary: ep.summary)
    result.endpoints.add ep
