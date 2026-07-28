# Sibling-repo path switching, mirroring ../isonim/demos/config.nims.
# Toolchain and these repos are expected to come from the IsoNim dev
# shell (`nix develop ../isonim -c <cmd>`) — do not assume a global nim.
#
# demos/config.nims anchors on `$projectDir` (the compiled main file's own
# directory) because every demo main file lives directly in demos/. Our
# main files live at varying depths (src/*.nim, tests/docs/*.nim), so
# `$projectDir` isn't stable across entry points; anchor on this file's
# own directory (the isonim-docs repo root) instead via `currentSourcePath`.
import std/os

let root = currentSourcePath().parentDir()
switch("path", root / "../isonim/src")
switch("path", root / "../nim-everywhere/src")

# isonim_docs uses chronicles for structured logging (docs build + route
# resolution). chronicles is vendored inside ../isonim/vendor (see
# ../isonim/tests/config.nims for the same pattern) because `nimble
# install chronicles` is unreliable in this workspace; faststreams comes
# from the sibling ../nim-faststreams checkout, matching ../isonim itself.
switch("path", root / "../nim-faststreams")
switch("path", root / "../nim-stew")
switch("path", root / "../isonim/vendor/chronicles")
switch("path", root / "../isonim/vendor/serialization")
switch("path", root / "../isonim/vendor/json_serialization")
switch("define", "chronicles_sinks=textlines[stderr]")
switch("define", "chronicles_runtime_filtering=on")
switch("define", "chronicles_log_level=TRACE")
