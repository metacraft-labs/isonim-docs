# isonim-docs/site -- the isonim-docs FRAMEWORK's own documentation site.
#
# Sibling-repo path switching, mirroring ../config.nims (the framework's
# own) and ../../isonim/docs/users/config.nims (the reference consumer),
# adjusted for this package's location one directory below the framework
# repo root (isonim-docs/site/ instead of isonim-docs/).
#
# Toolchain and these repos are expected to come from the IsoNim dev shell
# (`nix develop ../../isonim -c <cmd>` from here) -- do not assume a global
# nim.
#
# `nim c`'s config-file lookup walks up from the *project* (entry) file's
# own directory, so this file is what's active when compiling anything
# rooted under this package (src/ or tests/), even though most of the code
# being compiled lives in the sibling isonim-docs framework repo. Every
# path the framework's own config.nims sets up therefore has to be set up
# here too, adjusted for this package's extra directory depth.
import std/os

let root = currentSourcePath().parentDir()
let siblingRoot = root / "../.." ## .../codetracer-ci-refactor/

switch("path", siblingRoot / "isonim-docs/src") ## the framework being documented, a PATH dependency
switch("path", siblingRoot / "isonim/src")
switch("path", siblingRoot / "nim-everywhere/src")
switch("path", siblingRoot / "nim-faststreams")
switch("path", siblingRoot / "nim-stew")
switch("path", siblingRoot / "isonim/vendor/chronicles")
switch("path", siblingRoot / "isonim/vendor/serialization")
switch("path", siblingRoot / "isonim/vendor/json_serialization")
switch("define", "chronicles_sinks=textlines[stderr]")
switch("define", "chronicles_runtime_filtering=on")
switch("define", "chronicles_log_level=TRACE")
