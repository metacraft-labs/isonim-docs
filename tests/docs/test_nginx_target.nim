## M12 deliverable 1 (nginx adapter) suite — C-target only.
##
## Asserts the `--target=nginx` build END TO END, with a REAL compile — this
## suite never stubs the C target out:
##
##   1. the pure build-target core: `parseBuildTarget` and the exact
##      `nginxBuildRecipe` the CLI runs (`--app:lib -d:nginxTarget`);
##   2. the content-agnostic dispatch seam `renderForNginx` — a typed 500
##      with no app, the registered app's response otherwise, and the
##      empty-content-type -> HTML normalisation — with NO nginx headers;
##   3. a REAL Nim->C->`.so` build of `src/nginx_target.nim` from that very
##      recipe, producing a loadable shared object;
##   4. the C-ABI contract of the produced artifact: the exported
##      `isonim_docs_ssr` and `ngx_link_func_init_cycle` symbols resolve via
##      `dlopen`/`dlsym`;
##   5. an END-TO-END round trip through the compiled module: a C driver
##      links the `.so`, runs `NimMain`, calls `isonim_docs_ssr` over the
##      vendored nginx-link-function shim ctx, and the handler renders real
##      SSR HTML back through `ngx_link_func_write_resp`.
##
## Steps 3-5 shell out to `nim`/`cc` from the IsoNim dev shell (the same
## shell that runs this test); if either is somehow absent the suite fails
## loudly rather than skipping the compile check.

when defined(js):
  {.error: "test_nginx_target is a C-target-only suite (the nginx module is a server .so)".}

import std/[unittest, os, osproc, strutils, dynlib]
import ../../src/core/build_target
import ../../src/core/nginx_module

const
  repoRoot = currentSourcePath().parentDir() / ".." / ".."
  fixtureSite = currentSourcePath().parentDir() / ".." / "fixtures" / "mini-site"
  shimDir = currentSourcePath().parentDir() / ".." / ".." /
    "src" / "core" / "vendor" / "nginx"

proc mkTmpDir(tag: string): string =
  ## A unique temp working dir for the compile artifacts, removed by the
  ## caller. Uniqueness comes from pid so parallel runs never collide.
  result = getTempDir() / ("isonim_nginx_" & tag & "_" & $getCurrentProcessId())
  removeDir(result)
  createDir(result)

suite "nginx target -- build-target core (M12 deliverable 1, pure)":

  test "parseBuildTarget: defaults, aliases, and hard failure on garbage":
    check parseBuildTarget("") == btStatic
    check parseBuildTarget("static") == btStatic
    check parseBuildTarget("ssg") == btStatic
    check parseBuildTarget("nginx") == btNginx
    check parseBuildTarget("NGINX") == btNginx
    check parseBuildTarget(" ngx ") == btNginx
    check parseBuildTarget("ngx_link_func") == btNginx
    expect ValueError:
      discard parseBuildTarget("apache")

  test "nginxBuildRecipe: a real --app:lib -d:nginxTarget shared-object build":
    let recipe = nginxBuildRecipe(entry = "src/nginx_target.nim",
                                  outSo = "build/ngx_isonim_docs.so")
    check recipe[0] == "c"
    check "--app:lib" in recipe
    check "-d:nginxTarget" in recipe
    check "-o:build/ngx_isonim_docs.so" in recipe
    check recipe[^1] == "src/nginx_target.nim"
    # The recipe never silently produces a static binary or a JS target.
    check "-d:nginxUseSystemHeader" notin recipe   # default = vendored shim
    let sysRecipe = nginxBuildRecipe(useSystemHeader = true)
    check "-d:nginxUseSystemHeader" in sysRecipe

suite "nginx target -- content-agnostic dispatch seam (M12 deliverable 1)":

  setup:
    # Each test starts from a clean, unregistered adapter.
    setNginxTargetApp(nil)

  test "renderForNginx: a typed 500, never a crash, when no app is registered":
    check not hasNginxTargetApp()
    let r = renderForNginx("/anything")
    check r.status == 500
    check r.body.len > 0
    check r.contentType == "text/plain; charset=utf-8"

  test "renderForNginx: dispatches to the registered app verbatim":
    setNginxTargetApp(proc(uri: string): NginxResponse =
      NginxResponse(status: 200, contentType: "text/html; charset=utf-8",
                    body: "rendered:" & uri))
    check hasNginxTargetApp()
    let r = renderForNginx("/guide/intro")
    check r.status == 200
    check r.body == "rendered:/guide/intro"

  test "renderForNginx: normalises an empty content type to HTML":
    setNginxTargetApp(proc(uri: string): NginxResponse =
      NginxResponse(status: 200, contentType: "", body: "x"))
    let r = renderForNginx("/")
    check r.contentType == "text/html; charset=utf-8"

suite "nginx target -- REAL compile of the C target (M12 deliverable 1)":

  test "build --target=nginx compiles src/nginx_target.nim into a loadable .so":
    let nimExe = findExe("nim")
    check nimExe.len > 0                       # dev shell must provide nim
    let work = mkTmpDir("so")
    defer: removeDir(work)
    let outSo = work / "ngx_isonim_docs.so"
    let recipe = nginxBuildRecipe(entry = repoRoot / "src" / "nginx_target.nim",
                                  outSo = outSo)
    # Build with the framework's config.nims in effect by running from the
    # repo root, exactly as the CLI would.
    let cmd = quoteShell(nimExe) & " " & quoteShellCommand(recipe)
    let (buildLog, code) = execCmdEx(cmd, workingDir = repoRoot)
    checkpoint("nim build exit=" & $code & "\n" & buildLog)
    check code == 0
    check fileExists(outSo)
    check getFileSize(outSo) > 0

    # (4) The produced artifact exports the nginx-link-function C-ABI the
    # module contract promises — assert against the REAL object via dlopen.
    let lib = loadLib(outSo)
    check lib != nil
    check lib.symAddr("isonim_docs_ssr") != nil
    check lib.symAddr("ngx_link_func_init_cycle") != nil
    unloadLib(lib)

  test "the compiled module renders real SSR HTML through the nginx C-ABI":
    let nimExe = findExe("nim")
    let ccExe = if getEnv("CC").len > 0: getEnv("CC") else: findExe("cc")
    check nimExe.len > 0
    check ccExe.len > 0
    let work = mkTmpDir("e2e")
    defer: removeDir(work)
    let outSo = work / "ngx_isonim_docs.so"
    let recipe = nginxBuildRecipe(entry = repoRoot / "src" / "nginx_target.nim",
                                  outSo = outSo)
    let (buildLog, buildCode) = execCmdEx(
      quoteShell(nimExe) & " " & quoteShellCommand(recipe), workingDir = repoRoot)
    checkpoint("nim build exit=" & $buildCode & "\n" & buildLog)
    check buildCode == 0
    check fileExists(outSo)

    # A C driver that drives the compiled module exactly as nginx-link-
    # function would: init the Nim runtime, then call the exported handler
    # over a shim ctx and read back what the handler wrote via
    # ngx_link_func_write_resp.
    let driverC = work / "driver.c"
    writeFile(driverC, """
#include "ngx_link_func_shim.h"
#include <stdio.h>
#include <string.h>

extern void NimMain(void);
extern void isonim_docs_ssr(ngx_link_func_ctx_t *ctx);
extern void ngx_link_func_init_cycle(ngx_link_func_cycle_t *cycle);

int main(void) {
    NimMain();
    ngx_link_func_cycle_t cyc;
    ngx_link_func_init_cycle(&cyc);

    ngx_link_func_ctx_t ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.request_uri = "/";
    isonim_docs_ssr(&ctx);

    if (!ctx.out_written) { printf("FAIL no-write\n"); return 2; }
    printf("STATUS=%lu LEN=%zu\n",
           (unsigned long)ctx.out_status, ctx.out_body_len);
    if (ctx.out_status != 200) { printf("FAIL status\n"); return 3; }
    if (ctx.out_body == NULL || ctx.out_body_len == 0) {
        printf("FAIL empty\n"); return 4;
    }
    if (strstr(ctx.out_body, "<html") == NULL &&
        strstr(ctx.out_body, "<!DOCTYPE") == NULL &&
        strstr(ctx.out_body, "<!doctype") == NULL) {
        printf("FAIL not-html\n"); return 5;
    }
    if (ctx.out_content_type == NULL ||
        strstr(ctx.out_content_type, "text/html") == NULL) {
        printf("FAIL content-type\n"); return 6;
    }
    printf("OK\n");
    return 0;
}
""")
    let driverBin = work / "driver"
    let ccCmd = quoteShellCommand(@[
      ccExe, driverC, outSo, "-I" & shimDir,
      "-Wl,-rpath," & work, "-o", driverBin])
    let (ccLog, ccCode) = execCmdEx(ccCmd, workingDir = work)
    checkpoint("cc exit=" & $ccCode & "\n" & ccCmd & "\n" & ccLog)
    check ccCode == 0
    check fileExists(driverBin)

    # Point the module's default app at the framework fixture site (absolute,
    # so it resolves regardless of the driver's cwd), then run it.
    putEnv("ISONIM_DOCS_CONTENT_DIR", absolutePath(fixtureSite))
    let (runLog, runCode) = execCmdEx(quoteShell(driverBin), workingDir = work)
    checkpoint("driver exit=" & $runCode & "\n" & runLog)
    check runCode == 0
    check "OK" in runLog
    check "STATUS=200" in runLog
