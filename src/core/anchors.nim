## isonim-docs `core/anchors` -- kept for compatibility: the heading
## anchor rules moved to IsoNim itself, as `isonim/content/anchors`.
##
## This module re-exports that module unchanged (`slugifyHeadingText`,
## `AnchorIdRegistry`, `newAnchorIdRegistry`, `nextId`, `nextRawId`,
## `assignHeadingIds`). New code should import `isonim/content/anchors`.

{.deprecated: "isonim-docs' core/anchors moved to IsoNim: import isonim/content/anchors instead".}

import isonim/content/anchors as contentAnchors
export contentAnchors
