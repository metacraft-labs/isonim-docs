## isonim-docs Layer 2 — rendering for the API reference ViewModel
## (`src/core/api_reference_vm.nim`, M7 deliverable 2).
##
## The strict three-column Stripe-style layout: LEFT endpoint nav (HTTP
## method color-coded), CENTER per-operation prose + parameter/response
## tables + collapsible request/response body schema tables, RIGHT
## synthesized code samples (curl + JavaScript + Python). Like
## `markdown_view.nim`, the tree is variable-length and can't be a static
## `ui(...)` DSL tree, so every renderer below is written directly against
## the generic backend API (`createElement`/`appendChild`/`setAttribute`/
## `createTextNode`) for the Mock/browser side and plain escaped string
## building (`isonim/ssr/escape`) for the SSR side -- the two kept
## byte-for-byte in lock-step (dual-target parity, a HARD CONSTRAINT of
## M7), exactly as every other component pairs its `renderX`/`renderXHtml`.

import std/strutils
import isonim/ssr/escape
import ../core/openapi
import ../core/api_reference_vm

const
  apiLayoutClass* = "docs-api-layout"
  apiNavClass* = "docs-api-nav"
  apiNavListClass* = "docs-api-nav-list"
  apiNavLinkClass* = "docs-api-nav-link"
  apiContentClass* = "docs-api-content"
  apiSamplesClass* = "docs-api-samples"
  apiOperationClass* = "docs-api-operation"
  apiOperationTitleClass* = "docs-api-operation-title"
  apiMethodClass* = "docs-api-method"
  apiPathClass* = "docs-api-operation-path"
  apiSummaryClass* = "docs-api-summary"
  apiDescriptionClass* = "docs-api-description"
  apiParamTableClass* = "docs-api-param-table"
  apiResponseTableClass* = "docs-api-response-table"
  apiSchemaDetailsClass* = "docs-api-schema-details"
  apiSchemaSummaryClass* = "docs-api-schema-summary"
  apiSchemaTableClass* = "docs-api-schema-table"
  apiSchemaNestedClass* = "docs-api-schema-nested"
  apiSampleGroupClass* = "docs-api-sample-group"
  apiSampleClass* = "docs-api-sample"
  apiSampleLabelClass* = "docs-api-sample-label"
  apiSampleCodeClass* = "docs-api-sample-code"
  apiErrorClass* = "docs-api-errors"
  apiAnchorAttr* = "data-api-anchor"   ## on each center section + sample group
  apiTargetAttr* = "data-api-target"   ## on each left-nav link (its target anchor)
  apiSchemaMaxDepth = 6

proc yesNo(b: bool): string = (if b: "yes" else: "no")

# --- MockRenderer / browser tree mode -----------------------------------

proc addCell[R, E](r: R; row: E; tag, text: string) =
  let cell = r.createElement(tag)
  r.appendChild(cell, r.createTextNode(text))
  r.appendChild(row, cell)

proc renderApiSchema[R, E](r: R; schema: OpenApiSchema; depth: int): E =
  ## A collapsible schema table: a `<details>` whose `<summary>` names the
  ## schema type and whose `<table>` lists each property; a property whose
  ## own schema nests (object/array-of-object) gets a nested collapsible
  ## `<details>` in a spanning row, so deeply-nested schemas stay
  ## collapsible at every level.
  let details = r.createElement("details")
  r.setAttribute(details, "class", apiSchemaDetailsClass)
  if depth == 0: r.setAttribute(details, "open", "open")

  let summary = r.createElement("summary")
  r.setAttribute(summary, "class", apiSchemaSummaryClass)
  let label = if schema != nil and schemaTypeLabel(schema).len > 0: schemaTypeLabel(schema) else: "schema"
  r.appendChild(summary, r.createTextNode(label))
  r.appendChild(details, summary)

  if schema != nil and schema.properties.len > 0 and depth < apiSchemaMaxDepth:
    let table = r.createElement("table")
    r.setAttribute(table, "class", apiSchemaTableClass)
    let thead = r.createElement("thead")
    let headRow = r.createElement("tr")
    for h in ["Field", "Type", "Required", "Description"]:
      addCell[R, E](r, headRow, "th", h)
    r.appendChild(thead, headRow)
    r.appendChild(table, thead)
    let tbody = r.createElement("tbody")
    for prop in schema.properties:
      let required = prop.name in schema.required
      let row = r.createElement("tr")
      addCell[R, E](r, row, "td", prop.name)
      addCell[R, E](r, row, "td", schemaTypeLabel(prop.schema))
      addCell[R, E](r, row, "td", yesNo(required))
      addCell[R, E](r, row, "td", (if prop.schema != nil: prop.schema.description else: ""))
      r.appendChild(tbody, row)
      let child = prop.schema
      let nests = child != nil and (child.properties.len > 0 or
        (child.typ == "array" and child.items != nil and child.items.properties.len > 0))
      if nests and depth + 1 < apiSchemaMaxDepth:
        let nestedRow = r.createElement("tr")
        r.setAttribute(nestedRow, "class", apiSchemaNestedClass)
        let cell = r.createElement("td")
        r.setAttribute(cell, "colspan", "4")
        let nestedSchema = if child.typ == "array" and child.items != nil: child.items else: child
        r.appendChild(cell, renderApiSchema[R, E](r, nestedSchema, depth + 1))
        r.appendChild(nestedRow, cell)
        r.appendChild(tbody, nestedRow)
    r.appendChild(table, tbody)
    r.appendChild(details, table)
  details

proc renderMethodBadge[R, E](r: R; methodUpper, methodClass: string): E =
  let span = r.createElement("span")
  r.setAttribute(span, "class", apiMethodClass & " " & methodClass)
  r.appendChild(span, r.createTextNode(methodUpper))
  span

proc renderApiNav[R, E](r: R; vm: ApiReferenceViewModel): E =
  let navEl = r.createElement("nav")
  r.setAttribute(navEl, "class", apiNavClass)
  r.setAttribute(navEl, "aria-label", "API endpoints")
  let list = r.createElement("ul")
  r.setAttribute(list, "class", apiNavListClass)
  for e in vm.navEntries:
    let li = r.createElement("li")
    let a = r.createElement("a")
    r.setAttribute(a, "class", apiNavLinkClass)
    r.setAttribute(a, "href", "#" & e.anchorId)
    r.setAttribute(a, apiTargetAttr, e.anchorId)
    r.appendChild(a, renderMethodBadge[R, E](r, e.methodUpper, e.methodClass))
    let pathSpan = r.createElement("span")
    r.setAttribute(pathSpan, "class", apiPathClass)
    r.appendChild(pathSpan, r.createTextNode(e.path))
    r.appendChild(a, pathSpan)
    r.appendChild(li, a)
    r.appendChild(list, li)
  r.appendChild(navEl, list)
  navEl

proc renderParamTable[R, E](r: R; rows: seq[ApiParamRow]): E =
  let table = r.createElement("table")
  r.setAttribute(table, "class", apiParamTableClass)
  let thead = r.createElement("thead")
  let headRow = r.createElement("tr")
  for h in ["Name", "In", "Type", "Required", "Description"]:
    addCell[R, E](r, headRow, "th", h)
  r.appendChild(thead, headRow)
  r.appendChild(table, thead)
  let tbody = r.createElement("tbody")
  for row in rows:
    let tr = r.createElement("tr")
    addCell[R, E](r, tr, "td", row.name)
    addCell[R, E](r, tr, "td", row.location)
    addCell[R, E](r, tr, "td", row.typ)
    addCell[R, E](r, tr, "td", yesNo(row.required))
    addCell[R, E](r, tr, "td", row.description)
    r.appendChild(tbody, tr)
  r.appendChild(table, tbody)
  table

proc renderResponseTable[R, E](r: R; rows: seq[ApiResponseRow]): E =
  let table = r.createElement("table")
  r.setAttribute(table, "class", apiResponseTableClass)
  let thead = r.createElement("thead")
  let headRow = r.createElement("tr")
  for h in ["Status", "Description", "Type"]:
    addCell[R, E](r, headRow, "th", h)
  r.appendChild(thead, headRow)
  r.appendChild(table, thead)
  let tbody = r.createElement("tbody")
  for row in rows:
    let tr = r.createElement("tr")
    addCell[R, E](r, tr, "td", row.status)
    addCell[R, E](r, tr, "td", row.description)
    addCell[R, E](r, tr, "td", row.typ)
    r.appendChild(tbody, tr)
  r.appendChild(table, tbody)
  table

proc renderOperation[R, E](r: R; ep: ApiEndpointViewModel): E =
  let section = r.createElement("section")
  r.setAttribute(section, "class", apiOperationClass)
  r.setAttribute(section, "id", ep.anchorId)
  r.setAttribute(section, apiAnchorAttr, ep.anchorId)

  let h2 = r.createElement("h2")
  r.setAttribute(h2, "class", apiOperationTitleClass)
  r.appendChild(h2, renderMethodBadge[R, E](r, ep.methodUpper, ep.methodClass))
  let pathSpan = r.createElement("span")
  r.setAttribute(pathSpan, "class", apiPathClass)
  r.appendChild(pathSpan, r.createTextNode(ep.path))
  r.appendChild(h2, pathSpan)
  r.appendChild(section, h2)

  if ep.summary.len > 0:
    let p = r.createElement("p")
    r.setAttribute(p, "class", apiSummaryClass)
    r.appendChild(p, r.createTextNode(ep.summary))
    r.appendChild(section, p)
  if ep.description.len > 0:
    let p = r.createElement("p")
    r.setAttribute(p, "class", apiDescriptionClass)
    r.appendChild(p, r.createTextNode(ep.description))
    r.appendChild(section, p)

  if ep.parameters.len > 0:
    r.appendChild(section, renderParamTable[R, E](r, ep.parameters))
  if ep.requestBody.present:
    r.appendChild(section, renderApiSchema[R, E](r, ep.requestBody.schema, 0))
  if ep.responses.len > 0:
    r.appendChild(section, renderResponseTable[R, E](r, ep.responses))
    for resp in ep.responses:
      if resp.schema != nil and resp.schema.properties.len > 0:
        r.appendChild(section, renderApiSchema[R, E](r, resp.schema, 0))
  section

proc renderSampleGroup[R, E](r: R; ep: ApiEndpointViewModel): E =
  let group = r.createElement("div")
  r.setAttribute(group, "class", apiSampleGroupClass)
  r.setAttribute(group, apiAnchorAttr, ep.anchorId)
  for sample in ep.samples:
    let box = r.createElement("div")
    r.setAttribute(box, "class", apiSampleClass)
    let label = r.createElement("div")
    r.setAttribute(label, "class", apiSampleLabelClass)
    r.appendChild(label, r.createTextNode(sample.label))
    r.appendChild(box, label)
    let pre = r.createElement("pre")
    r.setAttribute(pre, "class", apiSampleCodeClass)
    let code = r.createElement("code")
    r.setAttribute(code, "class", "language-" & sample.lang)
    r.appendChild(code, r.createTextNode(sample.code))
    r.appendChild(pre, code)
    r.appendChild(box, pre)
    r.appendChild(group, box)
  group

proc renderApiReference*[R, E](r: R; vm: ApiReferenceViewModel): E =
  ## The full three-column API reference tree: one `docs-api-layout`
  ## container holding the left nav, the center content column (one
  ## `<section>` per operation, each carrying its stable anchor id), and
  ## the right samples column (one sample group per operation).
  let layout = r.createElement("div")
  r.setAttribute(layout, "class", apiLayoutClass)

  if vm.errors.len > 0:
    let errBox = r.createElement("div")
    r.setAttribute(errBox, "class", apiErrorClass)
    r.appendChild(errBox, r.createTextNode("This API spec could not be fully parsed: " &
      vm.errors.join("; ")))
    r.appendChild(layout, errBox)

  r.appendChild(layout, renderApiNav[R, E](r, vm))

  let content = r.createElement("div")
  r.setAttribute(content, "class", apiContentClass)
  for ep in vm.endpoints:
    r.appendChild(content, renderOperation[R, E](r, ep))
  r.appendChild(layout, content)

  let samples = r.createElement("div")
  r.setAttribute(samples, "class", apiSamplesClass)
  for ep in vm.endpoints:
    r.appendChild(samples, renderSampleGroup[R, E](r, ep))
  r.appendChild(layout, samples)
  layout

# --- SSR string mode ------------------------------------------------------

proc methodBadgeHtml(methodUpper, methodClass: string): string =
  "<span class=\"" & apiMethodClass & " " & methodClass & "\">" & escapeHtml(methodUpper) & "</span>"

proc apiSchemaHtml(schema: OpenApiSchema; depth: int): string =
  let openAttr = if depth == 0: " open" else: ""
  result = "<details class=\"" & apiSchemaDetailsClass & "\"" & openAttr & ">"
  let label = if schema != nil and schemaTypeLabel(schema).len > 0: schemaTypeLabel(schema) else: "schema"
  result.add "<summary class=\"" & apiSchemaSummaryClass & "\">" & escapeHtml(label) & "</summary>"
  if schema != nil and schema.properties.len > 0 and depth < apiSchemaMaxDepth:
    result.add "<table class=\"" & apiSchemaTableClass & "\"><thead><tr>"
    for h in ["Field", "Type", "Required", "Description"]:
      result.add "<th>" & h & "</th>"
    result.add "</tr></thead><tbody>"
    for prop in schema.properties:
      let required = prop.name in schema.required
      result.add "<tr><td>" & escapeHtml(prop.name) & "</td><td>" &
        escapeHtml(schemaTypeLabel(prop.schema)) & "</td><td>" & yesNo(required) &
        "</td><td>" & escapeHtml(if prop.schema != nil: prop.schema.description else: "") &
        "</td></tr>"
      let child = prop.schema
      let nests = child != nil and (child.properties.len > 0 or
        (child.typ == "array" and child.items != nil and child.items.properties.len > 0))
      if nests and depth + 1 < apiSchemaMaxDepth:
        let nestedSchema = if child.typ == "array" and child.items != nil: child.items else: child
        result.add "<tr class=\"" & apiSchemaNestedClass & "\"><td colspan=\"4\">" &
          apiSchemaHtml(nestedSchema, depth + 1) & "</td></tr>"
    result.add "</tbody></table>"
  result.add "</details>"

proc apiNavHtml(vm: ApiReferenceViewModel): string =
  result = "<nav class=\"" & apiNavClass & "\" aria-label=\"API endpoints\"><ul class=\"" &
    apiNavListClass & "\">"
  for e in vm.navEntries:
    result.add "<li><a class=\"" & apiNavLinkClass & "\" href=\"#" & escapeAttr(e.anchorId) &
      "\" " & apiTargetAttr & "=\"" & escapeAttr(e.anchorId) & "\">" &
      methodBadgeHtml(e.methodUpper, e.methodClass) &
      "<span class=\"" & apiPathClass & "\">" & escapeHtml(e.path) & "</span></a></li>"
  result.add "</ul></nav>"

proc paramTableHtml(rows: seq[ApiParamRow]): string =
  result = "<table class=\"" & apiParamTableClass & "\"><thead><tr>"
  for h in ["Name", "In", "Type", "Required", "Description"]:
    result.add "<th>" & h & "</th>"
  result.add "</tr></thead><tbody>"
  for row in rows:
    result.add "<tr><td>" & escapeHtml(row.name) & "</td><td>" & escapeHtml(row.location) &
      "</td><td>" & escapeHtml(row.typ) & "</td><td>" & yesNo(row.required) &
      "</td><td>" & escapeHtml(row.description) & "</td></tr>"
  result.add "</tbody></table>"

proc responseTableHtml(rows: seq[ApiResponseRow]): string =
  result = "<table class=\"" & apiResponseTableClass & "\"><thead><tr>"
  for h in ["Status", "Description", "Type"]:
    result.add "<th>" & h & "</th>"
  result.add "</tr></thead><tbody>"
  for row in rows:
    result.add "<tr><td>" & escapeHtml(row.status) & "</td><td>" & escapeHtml(row.description) &
      "</td><td>" & escapeHtml(row.typ) & "</td></tr>"
  result.add "</tbody></table>"

proc operationHtml(ep: ApiEndpointViewModel): string =
  result = "<section class=\"" & apiOperationClass & "\" id=\"" & escapeAttr(ep.anchorId) &
    "\" " & apiAnchorAttr & "=\"" & escapeAttr(ep.anchorId) & "\">"
  result.add "<h2 class=\"" & apiOperationTitleClass & "\">" &
    methodBadgeHtml(ep.methodUpper, ep.methodClass) &
    "<span class=\"" & apiPathClass & "\">" & escapeHtml(ep.path) & "</span></h2>"
  if ep.summary.len > 0:
    result.add "<p class=\"" & apiSummaryClass & "\">" & escapeHtml(ep.summary) & "</p>"
  if ep.description.len > 0:
    result.add "<p class=\"" & apiDescriptionClass & "\">" & escapeHtml(ep.description) & "</p>"
  if ep.parameters.len > 0:
    result.add paramTableHtml(ep.parameters)
  if ep.requestBody.present:
    result.add apiSchemaHtml(ep.requestBody.schema, 0)
  if ep.responses.len > 0:
    result.add responseTableHtml(ep.responses)
    for resp in ep.responses:
      if resp.schema != nil and resp.schema.properties.len > 0:
        result.add apiSchemaHtml(resp.schema, 0)
  result.add "</section>"

proc sampleGroupHtml(ep: ApiEndpointViewModel): string =
  result = "<div class=\"" & apiSampleGroupClass & "\" " & apiAnchorAttr & "=\"" &
    escapeAttr(ep.anchorId) & "\">"
  for sample in ep.samples:
    result.add "<div class=\"" & apiSampleClass & "\"><div class=\"" & apiSampleLabelClass &
      "\">" & escapeHtml(sample.label) & "</div><pre class=\"" & apiSampleCodeClass &
      "\"><code class=\"language-" & escapeAttr(sample.lang) & "\">" & escapeHtml(sample.code) &
      "</code></pre></div>"
  result.add "</div>"

proc renderApiReferenceHtml*(vm: ApiReferenceViewModel): string =
  ## SSR string-mode rendering -- byte-for-byte the same shape/order as
  ## `renderApiReference`.
  result = "<div class=\"" & apiLayoutClass & "\">"
  if vm.errors.len > 0:
    result.add "<div class=\"" & apiErrorClass & "\">This API spec could not be fully parsed: " &
      escapeHtml(vm.errors.join("; ")) & "</div>"
  result.add apiNavHtml(vm)
  result.add "<div class=\"" & apiContentClass & "\">"
  for ep in vm.endpoints:
    result.add operationHtml(ep)
  result.add "</div>"
  result.add "<div class=\"" & apiSamplesClass & "\">"
  for ep in vm.endpoints:
    result.add sampleGroupHtml(ep)
  result.add "</div>"
  result.add "</div>"
