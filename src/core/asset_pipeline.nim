## isonim-docs `core/asset_pipeline` -- kept for compatibility: the
## static-asset pipeline (content-hashed file names, `asset-manifest.json`,
## the CSS purge) moved to IsoNim itself, as `isonim/static/assets`.
##
## This module re-exports that module unchanged (`contentHash`,
## `hashedAssetName`, `extractUsedClasses`, `purgeCss`,
## `writeAssetManifest`, plus the new `renderAssetManifest` and the
## directory pass `hashAndPurgeAssets`). New code should import
## `isonim/static/assets`.

{.deprecated: "isonim-docs' core/asset_pipeline moved to IsoNim: import isonim/static/assets instead".}

import isonim/static/assets
export assets
