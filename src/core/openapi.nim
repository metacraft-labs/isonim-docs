## isonim-docs Layer 3 — OpenAPI v3 ingestion (M7 deliverable 1).
##
## Parses an OpenAPI v3 spec, supplied as either YAML or JSON, into a
## typed, filesystem-free Nim model (info, servers, paths -> operations
## {method, summary, description, parameters, requestBody, responses},
## parameter objects, request/response schemas, components/schemas) with
## local `$ref` resolution and TOLERANT error reporting: a malformed
## spec yields a typed `OpenApiIngest` carrying `ok = false` and an
## `errors` seq, NEVER an unhandled raise that would abort a consumer's
## build.
##
## DUAL-TARGET APPROACH (chosen: option (a) from the milestone brief --
## keep BOTH the model AND the parsing dual-target):
##  * JSON is parsed with `std/json`, which compiles and runs on both the
##    C and JS backends.
##  * YAML is parsed by a small, pure-`std/strutils` indentation-based
##    YAML-SUBSET parser written here (`parseYamlSubset`) rather than any
##    of Nim's C-only YAML libraries -- OpenAPI YAML is a constrained
##    subset (nested block maps/sequences, scalars, flow `[..]`/`{..}`),
##    so a hand-written parser stays dual-target by construction.
## Both parsers lower to one common `SpecNode` (scalar/seq/map) tree, and
## a single `buildSpec` builds the typed model from that tree -- so the
## dual-target test exercises YAML *and* JSON ingestion on BOTH targets
## through the exact same model-building code path. No `std/os`, no
## `staticRead`, no C-only import anywhere in this module.

import std/[strutils, json, tables, sets]

type
  SpecNodeKind* = enum
    snkScalar
    snkSeq
    snkMap

  SpecNode* = ref object
    ## The one intermediate tree both the YAML-subset parser and the
    ## `std/json` path lower to, so `buildSpec` never forks per format.
    ## Maps keep insertion order (a `seq` of pairs, not a `Table`) so the
    ## rendered path/operation order matches the authored spec.
    case kind*: SpecNodeKind
    of snkScalar: scalar*: string
    of snkSeq: items*: seq[SpecNode]
    of snkMap: fields*: seq[tuple[key: string, val: SpecNode]]

  OpenApiSchema* = ref object
    ## A resolved (or partially-resolved) JSON-Schema fragment. `refName`
    ## is set when this schema originated from a local `$ref`
    ## (`#/components/schemas/<name>`) -- resolved in place, but the name
    ## is retained for display. A cyclic `$ref` resolves to a stub schema
    ## with only `refName` set (no expanded properties) to break the loop.
    typ*: string          ## "object" / "array" / "string" / "integer" / ...
    format*: string
    description*: string
    refName*: string
    properties*: seq[OpenApiProperty]
    required*: seq[string]
    items*: OpenApiSchema  ## element schema for `type: array`
    enumValues*: seq[string]

  OpenApiProperty* = object
    name*: string
    schema*: OpenApiSchema

  OpenApiParameter* = object
    name*: string
    location*: string     ## the OpenAPI `in`: query/path/header/cookie
    description*: string
    required*: bool
    schema*: OpenApiSchema

  OpenApiRequestBody* = object
    present*: bool
    description*: string
    required*: bool
    contentType*: string
    schema*: OpenApiSchema

  OpenApiResponse* = object
    statusCode*: string   ## "200" / "404" / "default"
    description*: string
    contentType*: string
    schema*: OpenApiSchema

  OpenApiOperation* = object
    httpMethod*: string   ## lowercase: get/put/post/delete/patch/...
    path*: string
    operationId*: string
    summary*: string
    description*: string
    parameters*: seq[OpenApiParameter]
    requestBody*: OpenApiRequestBody
    responses*: seq[OpenApiResponse]

  OpenApiSpec* = object
    title*: string
    version*: string
    description*: string
    servers*: seq[string]
    operations*: seq[OpenApiOperation]
    schemas*: seq[OpenApiProperty] ## components/schemas, name -> schema

  OpenApiIngest* = object
    ## The tolerant result of ingesting a spec: `ok` is false and
    ## `errors` non-empty when the spec could not be parsed or is
    ## structurally invalid; `spec` is still a well-formed (possibly
    ## empty) value either way, so a consumer can render an error notice
    ## without crashing.
    ok*: bool
    spec*: OpenApiSpec
    errors*: seq[string]

const httpMethods = ["get", "put", "post", "delete", "patch", "options", "head", "trace"]

# --- SpecNode helpers -----------------------------------------------------

proc newScalar(s: string): SpecNode = SpecNode(kind: snkScalar, scalar: s)

proc getField*(node: SpecNode; key: string): SpecNode =
  ## Case-sensitive map lookup returning nil when absent or when `node`
  ## isn't a map, so callers can probe optional keys without raising.
  if node == nil or node.kind != snkMap: return nil
  for f in node.fields:
    if f.key == key: return f.val
  nil

proc scalarStr(node: SpecNode): string =
  if node != nil and node.kind == snkScalar: node.scalar else: ""

proc fieldStr(node: SpecNode; key: string): string =
  scalarStr(getField(node, key))

proc fieldBool(node: SpecNode; key: string): bool =
  fieldStr(node, key).toLowerAscii() == "true"

# --- YAML-subset parser ---------------------------------------------------

proc stripInlineComment(line: string): string =
  ## Drops a trailing ` #...` comment that isn't inside a quoted scalar.
  ## A `#` at column 0 (whole-line comment) is handled by the caller; here
  ## we only trim an unquoted mid/end-of-line comment.
  var inSingle = false
  var inDouble = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if c == '\'' and not inDouble: inSingle = not inSingle
    elif c == '"' and not inSingle: inDouble = not inDouble
    elif c == '#' and not inSingle and not inDouble:
      if i == 0 or line[i - 1] in {' ', '\t'}:
        return line[0 ..< i]
    inc i
  line

proc unquoteScalar(s: string): string =
  let t = s.strip()
  if t.len >= 2 and ((t[0] == '"' and t[^1] == '"') or (t[0] == '\'' and t[^1] == '\'')):
    return t[1 ..< t.len - 1]
  t

type YamlLine = tuple[indent: int, text: string]

proc parseScalarOrFlow(rest: string): SpecNode =
  ## A YAML value that fits on one line: a flow sequence `[a, b]`, a flow
  ## map `{a: b, c: d}` (both used by OpenAPI for e.g. `required:` and
  ## `enum:`/tags), or a plain/quoted scalar.
  let t = rest.strip()
  if t.len >= 2 and t[0] == '[' and t[^1] == ']':
    result = SpecNode(kind: snkSeq)
    let inner = t[1 ..< t.len - 1].strip()
    if inner.len > 0:
      for part in inner.split(','):
        result.items.add newScalar(unquoteScalar(part.strip()))
  elif t.len >= 2 and t[0] == '{' and t[^1] == '}':
    result = SpecNode(kind: snkMap)
    let inner = t[1 ..< t.len - 1].strip()
    if inner.len > 0:
      for part in inner.split(','):
        let kv = part.strip()
        let ci = kv.find(':')
        if ci >= 0:
          result.fields.add (kv[0 ..< ci].strip(), newScalar(unquoteScalar(kv[ci + 1 .. ^1].strip())))
  else:
    result = newScalar(unquoteScalar(t))

proc parseNode(lines: var seq[YamlLine]; pos: var int; indent: int): SpecNode

proc parseMap(lines: var seq[YamlLine]; pos: var int; indent: int): SpecNode =
  result = SpecNode(kind: snkMap)
  while pos < lines.len and lines[pos].indent == indent and not lines[pos].text.startsWith("- ") and lines[pos].text != "-":
    let text = lines[pos].text
    var key: string
    var rest: string
    let colon = text.find(": ")
    if colon >= 0:
      key = text[0 ..< colon].strip()
      rest = text[colon + 2 .. ^1].strip()
    elif text.endsWith(":"):
      key = text[0 ..< text.len - 1].strip()
      rest = ""
    else:
      # Not a valid map line -- treat the whole line as a bare key with an
      # empty value rather than raising.
      key = text.strip()
      rest = ""
    key = unquoteScalar(key)
    inc pos
    if rest.len > 0:
      result.fields.add (key, parseScalarOrFlow(rest))
    elif pos < lines.len and lines[pos].indent > indent:
      result.fields.add (key, parseNode(lines, pos, lines[pos].indent))
    else:
      result.fields.add (key, newScalar(""))

proc parseSeq(lines: var seq[YamlLine]; pos: var int; indent: int): SpecNode =
  result = SpecNode(kind: snkSeq)
  while pos < lines.len and lines[pos].indent == indent and
        (lines[pos].text == "-" or lines[pos].text.startsWith("- ")):
    let text = lines[pos].text
    # column, within the original line, where the item content begins
    var j = 1
    while j < text.len and text[j] == ' ': inc j
    let rest = if j < text.len: text[j .. ^1] else: ""
    if rest.len == 0:
      inc pos
      if pos < lines.len and lines[pos].indent > indent:
        result.items.add parseNode(lines, pos, lines[pos].indent)
      else:
        result.items.add newScalar("")
    else:
      let childIndent = indent + j
      # Rewrite this line so the item content is re-parsed as if it began
      # at `childIndent`; continuation lines of the same item align there.
      lines[pos] = (childIndent, rest)
      result.items.add parseNode(lines, pos, childIndent)

proc parseNode(lines: var seq[YamlLine]; pos: var int; indent: int): SpecNode =
  if pos >= lines.len: return newScalar("")
  if lines[pos].text == "-" or lines[pos].text.startsWith("- "):
    parseSeq(lines, pos, indent)
  else:
    parseMap(lines, pos, indent)

proc parseYamlSubset(raw: string): SpecNode =
  ## Pure indentation-based YAML-subset parser. Raises `ValueError` on a
  ## grossly malformed document (e.g. empty / no structure) so
  ## `ingestOpenApi` can convert it into a tolerant typed error.
  var lines: seq[YamlLine] = @[]
  for rawLine in raw.splitLines():
    let noComment = stripInlineComment(rawLine)
    let stripped = noComment.strip()
    if stripped.len == 0: continue
    if stripped == "---" or stripped == "...": continue ## YAML document markers
    var indent = 0
    while indent < noComment.len and noComment[indent] == ' ': inc indent
    lines.add (indent, stripped)
  if lines.len == 0:
    raise newException(ValueError, "empty YAML document")
  var pos = 0
  result = parseNode(lines, pos, lines[0].indent)

# --- JSON -> SpecNode -----------------------------------------------------

proc jsonToSpecNode(n: JsonNode): SpecNode =
  case n.kind
  of JObject:
    result = SpecNode(kind: snkMap)
    for key, val in n.fields:
      result.fields.add (key, jsonToSpecNode(val))
  of JArray:
    result = SpecNode(kind: snkSeq)
    for item in n.items:
      result.items.add jsonToSpecNode(item)
  of JString: result = newScalar(n.getStr())
  of JInt: result = newScalar($n.getInt())
  of JFloat: result = newScalar($n.getFloat())
  of JBool: result = newScalar(if n.getBool(): "true" else: "false")
  of JNull: result = newScalar("")

# --- Typed model building -------------------------------------------------

proc buildSchema(node: SpecNode; components: Table[string, SpecNode];
                  resolving: HashSet[string]): OpenApiSchema =
  ## Builds a typed schema from a schema node, resolving a local `$ref`
  ## (`#/components/schemas/<name>`) against `components`. A `$ref` whose
  ## target is already being resolved (a recursive/self-referential
  ## schema) yields a stub with only `refName` set, breaking the cycle.
  if node == nil:
    return OpenApiSchema()
  if node.kind != snkMap:
    return OpenApiSchema(typ: scalarStr(node))

  let refNode = getField(node, "$ref")
  if refNode != nil and refNode.kind == snkScalar:
    let refStr = refNode.scalar
    let slash = refStr.rfind('/')
    let name = if slash >= 0: refStr[slash + 1 .. ^1] else: refStr
    if name in resolving:
      return OpenApiSchema(refName: name, typ: "object")
    if components.hasKey(name):
      var nextResolving = resolving
      nextResolving.incl name
      result = buildSchema(components[name], components, nextResolving)
      result.refName = name
      return result
    # Unresolved external/unknown ref: keep the name, don't fail.
    return OpenApiSchema(refName: name)

  result = OpenApiSchema(
    typ: fieldStr(node, "type"),
    format: fieldStr(node, "format"),
    description: fieldStr(node, "description"))

  let props = getField(node, "properties")
  if props != nil and props.kind == snkMap:
    if result.typ.len == 0: result.typ = "object"
    for f in props.fields:
      result.properties.add OpenApiProperty(
        name: f.key, schema: buildSchema(f.val, components, resolving))

  let req = getField(node, "required")
  if req != nil and req.kind == snkSeq:
    for it in req.items:
      if it.kind == snkScalar: result.required.add it.scalar

  let items = getField(node, "items")
  if items != nil:
    if result.typ.len == 0: result.typ = "array"
    result.items = buildSchema(items, components, resolving)

  let enumNode = getField(node, "enum")
  if enumNode != nil and enumNode.kind == snkSeq:
    for it in enumNode.items:
      if it.kind == snkScalar: result.enumValues.add it.scalar

proc firstContentSchema(contentNode: SpecNode; components: Table[string, SpecNode]):
    tuple[contentType: string, schema: OpenApiSchema] =
  ## Picks a `content` block's media type, preferring `application/json`,
  ## and builds its schema. Returns ("", nil) when there is no content.
  if contentNode == nil or contentNode.kind != snkMap or contentNode.fields.len == 0:
    return ("", nil)
  var chosen = contentNode.fields[0]
  for f in contentNode.fields:
    if f.key == "application/json":
      chosen = f
      break
  let schemaNode = getField(chosen.val, "schema")
  (chosen.key, buildSchema(schemaNode, components, initHashSet[string]()))

proc buildParameter(node: SpecNode; components: Table[string, SpecNode]): OpenApiParameter =
  OpenApiParameter(
    name: fieldStr(node, "name"),
    location: fieldStr(node, "in"),
    description: fieldStr(node, "description"),
    required: fieldBool(node, "required"),
    schema: buildSchema(getField(node, "schema"), components, initHashSet[string]()))

proc buildOperation(httpMethod, path: string; node: SpecNode;
                     pathLevelParams: seq[OpenApiParameter];
                     components: Table[string, SpecNode]): OpenApiOperation =
  result = OpenApiOperation(
    httpMethod: httpMethod, path: path,
    operationId: fieldStr(node, "operationId"),
    summary: fieldStr(node, "summary"),
    description: fieldStr(node, "description"))
  result.parameters = pathLevelParams

  let params = getField(node, "parameters")
  if params != nil and params.kind == snkSeq:
    for p in params.items:
      result.parameters.add buildParameter(p, components)

  let rb = getField(node, "requestBody")
  if rb != nil and rb.kind == snkMap:
    let (ct, schema) = firstContentSchema(getField(rb, "content"), components)
    result.requestBody = OpenApiRequestBody(
      present: true,
      description: fieldStr(rb, "description"),
      required: fieldBool(rb, "required"),
      contentType: ct, schema: schema)

  let responses = getField(node, "responses")
  if responses != nil and responses.kind == snkMap:
    for f in responses.fields:
      let (ct, schema) = firstContentSchema(getField(f.val, "content"), components)
      result.responses.add OpenApiResponse(
        statusCode: f.key,
        description: fieldStr(f.val, "description"),
        contentType: ct, schema: schema)

proc buildSpec(root: SpecNode): OpenApiIngest =
  ## Structural validation + typed model assembly. Tolerant: a missing
  ## `openapi` version or `paths` block is reported as an error rather
  ## than raising, and the (possibly empty) model is still returned.
  if root == nil or root.kind != snkMap:
    return OpenApiIngest(ok: false, errors: @["spec root is not a mapping"])

  var spec = OpenApiSpec()
  var errors: seq[string] = @[]

  if getField(root, "openapi") == nil and getField(root, "swagger") == nil:
    errors.add "missing required \"openapi\" version field"

  let info = getField(root, "info")
  spec.title = fieldStr(info, "title")
  spec.version = fieldStr(info, "version")
  spec.description = fieldStr(info, "description")

  let servers = getField(root, "servers")
  if servers != nil and servers.kind == snkSeq:
    for s in servers.items:
      let url = fieldStr(s, "url")
      if url.len > 0: spec.servers.add url

  # components/schemas kept raw for $ref resolution, plus a typed copy.
  var components = initTable[string, SpecNode]()
  let comps = getField(root, "components")
  let schemasNode = getField(comps, "schemas")
  if schemasNode != nil and schemasNode.kind == snkMap:
    for f in schemasNode.fields:
      components[f.key] = f.val
  if schemasNode != nil and schemasNode.kind == snkMap:
    for f in schemasNode.fields:
      spec.schemas.add OpenApiProperty(
        name: f.key,
        schema: buildSchema(f.val, components, initHashSet[string]()))

  let paths = getField(root, "paths")
  if paths == nil or paths.kind != snkMap:
    errors.add "missing or invalid \"paths\" object"
  else:
    for pathField in paths.fields:
      let path = pathField.key
      let pathItem = pathField.val
      if pathItem == nil or pathItem.kind != snkMap: continue
      # path-level shared parameters, merged into every operation
      var pathParams: seq[OpenApiParameter] = @[]
      let pp = getField(pathItem, "parameters")
      if pp != nil and pp.kind == snkSeq:
        for p in pp.items:
          pathParams.add buildParameter(p, components)
      for opField in pathItem.fields:
        if opField.key.toLowerAscii() in httpMethods:
          spec.operations.add buildOperation(
            opField.key.toLowerAscii(), path, opField.val, pathParams, components)

  OpenApiIngest(ok: errors.len == 0, spec: spec, errors: errors)

# --- Public entry point ---------------------------------------------------

proc detectJson(raw, sourcePath: string): bool =
  ## Chooses the parser: by file extension when the source path carries a
  ## recognizable one, else by sniffing the first non-space character (a
  ## JSON document starts with `{`).
  let lower = sourcePath.toLowerAscii()
  if lower.endsWith(".json"): return true
  if lower.endsWith(".yaml") or lower.endsWith(".yml"): return false
  let t = raw.strip()
  t.len > 0 and t[0] == '{'

proc ingestOpenApi*(raw: string; sourcePath: string = ""): OpenApiIngest =
  ## Ingests an OpenAPI v3 spec (YAML or JSON) into the typed model.
  ## Tolerant by contract: any parse or structural failure yields
  ## `ok = false` with a populated `errors` seq -- this proc NEVER lets an
  ## exception escape, so a bad spec flags the build instead of aborting
  ## it. `sourcePath` only picks the parser (see `detectJson`); the model
  ## and every downstream step are identical for both formats and both
  ## backends.
  if raw.strip().len == 0:
    return OpenApiIngest(ok: false, errors: @["empty spec document"])
  var root: SpecNode
  try:
    if detectJson(raw, sourcePath):
      root = jsonToSpecNode(parseJson(raw))
    else:
      root = parseYamlSubset(raw)
  except CatchableError as e:
    return OpenApiIngest(ok: false, errors: @["failed to parse spec: " & e.msg])
  except:
    ## The JS backend surfaces a native `JSON.parse` failure as a FOREIGN
    ## exception that isn't a Nim `CatchableError`; a bare `except` keeps
    ## the tolerant contract on both backends (a bad spec flags the build
    ## rather than aborting it).
    return OpenApiIngest(ok: false, errors: @["failed to parse spec: " & getCurrentExceptionMsg()])
  try:
    result = buildSpec(root)
  except CatchableError as e:
    result = OpenApiIngest(ok: false, errors: @["failed to build model: " & e.msg])
  except:
    result = OpenApiIngest(ok: false, errors: @["failed to build model: " & getCurrentExceptionMsg()])
