## Real docs build; no test doubles. Retain the published clean URL mapping.
import std/[os, unittest]
import ../../src/build_site
import ../../src/core/config
let scratch = getTempDir() / ("isonim-docs-route-compat-" & $getCurrentProcessId())
let content = scratch / "content"
createDir(content)
writeFile(content / "test.md", "---\ntitle: Test\ndescription: test route\nslug: special.html\n---\n# Test\n")
suite "docs output compatibility":
  test "html slug retains pre-extraction clean-URL output path":
    discard buildSite(outDir = scratch / "site", contentDir = content)
    check fileExists(scratch / "site/special.html/index.html")
removeDir(scratch)
