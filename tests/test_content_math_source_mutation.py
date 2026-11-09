#!/usr/bin/env python3
"""Falsify source coordinates, strict SSR and configured graph wiring in copies.

The actual real-file/real-KaTeX suite must compile and reject each production
mutation by its named semantic assertion. Live sources are never rewritten.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
if not os.environ.get("ISONIM_KATEX"):
    raise SystemExit("ISONIM_KATEX not configured; use the content-tools shell")
MUTANTS = [
    ("body-offset", "ssr.nim", "firstLine = contentEntry.page.bodyLine",
      "firstLine = contentEntry.source.line", 2,
      "test_content_math_source.nim",
      "front matter title and blank lines retain invalid expression location"),
    ("strict-route-errors", "ssr.nim", "if strictRenderErrors: raise", "discard", 1,
      "test_content_math_source.nim",
      "front matter title and blank lines retain invalid expression location"),
    ("static-failure", "build_site.nim", ", strictRenderErrors = true", "", 1,
      "test_content_math_source.nim",
      "static build refuses missing selected content and preserves previous output"),
    ("graph-parser-host", "core/references.nim", "parseMarkdownDocWithPlugins(pageHost,",
      "parseMarkdownDocWithPlugins(PluginHost(),", 1, "test_content_math_references.nim",
      "configured graph catches the same active math heading and table links as SSR"),
    ("build-graph-host", "build_site.nim", "validateContentGraph(contentDir, manifest, host = host)",
      "validateContentGraph(contentDir, manifest)", 1, "test_content_math_references.nim",
      "configured static build validates with its host and preserves published bytes"),
]
reports = ROOT / "build/content-source-mutation-reports"
reports.mkdir(parents=True, exist_ok=True)
for name, source, old, new, count, test_name, assertion in MUTANTS:
    with tempfile.TemporaryDirectory(prefix="content-source-mutant-", dir=ROOT / "build") as temp:
        scratch = Path(temp)
        for original in (ROOT / "src").rglob("*.nim"):
            destination = scratch / original.relative_to(ROOT)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, destination)
        (scratch / "assets").mkdir()
        shutil.copy2(ROOT / "assets/style.css", scratch / "assets/style.css")
        test = scratch / "tests/docs" / test_name
        test.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "tests/docs" / test_name, test)
        target = scratch / "src" / source
        text = target.read_text()
        if text.count(old) != count:
            raise SystemExit(f"{name}: production mutation site changed")
        target.write_text(text.replace(old, new))
        binary = scratch / name
        compile_log = reports / f"{name}-compile.log"
        run_log = reports / f"{name}-run.log"
        with compile_log.open("w") as output:
            built = subprocess.run(["nim", "c", f"--out:{binary}",
                f"--nimcache:{ROOT / 'build/nimcache/content-source-mutations' / name}", str(test)],
                stdout=output, stderr=subprocess.STDOUT)
        if built.returncode:
            raise SystemExit(f"{name}: compile failure is NOT mutation evidence: {compile_log}")
        with run_log.open("w") as output:
            run = subprocess.run([str(binary)], stdout=output, stderr=subprocess.STDOUT)
        if run.returncode == 0 or f"[FAILED] {assertion}" not in run_log.read_text():
            raise SystemExit(f"{name}: required assertion did not fail: {run_log}")
        print(f"PASS: {name} compiled; named assertion failed (exit {run.returncode})", flush=True)
