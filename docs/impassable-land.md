# Impassable land eraser and repainting

> **Version note:** Current terrain documents are v15 and world manifests are v6. Older version numbers below record this feature's introduction. See [the current renderer](display-height-cache.md) and [README](../README.md) for active behavior.

## Use it

In Provinces, select Erase to impassable land in Province tool and enable it. Drag
across a mountain area or another land area to remove its province coverage.
A red cursor shows the brush footprint. The area becomes unassigned impassable
land, displayed as dark terrain relief without internal province borders. No
province selection is required for erasing.

To restore it, switch to Paint borders, select a land province, enable painting
and paint the erased area. Its impassable flag clears and it joins the selected
province. Painting erased land with no selected province creates a fresh land
province, which also works after all previous land provinces have been erased.
Undo/Redo restores both exact pixel IDs and passability, including archived names
and newly created province activation. Escape cancels unfinished strokes.

The eraser affects only assigned land. Sea regions, deep ocean, lakes and inland
water are protected. Terrain heights, rivers/lakes and the finished ground surface
remain unchanged. Layer locks, visibility and source/model guards apply as with
other province tools. Saving/loading preserves the mask; ocean regeneration does
not remove it. Regenerating land provinces replaces authored edits as before.

## Land parts and adjacency

Erased mountain strips can divide a province into several passable pieces. Land
touched by erasure or restoration supports these authored parts, including when
other provinces provide a route around the mountain strip. Ordinary untouched
provinces retain their previous connectivity validation; oceans remain connected.
Part-policy changes are included in Undo/Redo. Merges carry the authored part
policy forward. Physical landmass labels include impassable land, so a mountain
barrier does not make half a continent count as a separate island for attachment.
Whole-island attachment preserves impassable holes.

Province adjacency is rebuilt from remaining assigned shared edges. Erasing the
only shared border removes that adjacency; restoring coverage can add it again.
The map exposes `is_impassable(uv)` for future movement/pathfinding consumers.
Actual unit movement/pathfinding is a later game system and must respect this
mask rather than assuming all pixels in a province are traversable.

## Storage and implementation

- `world_provinces.gd` stores a separate binary impassable mask. Such pixels must
  be land, have ID 0 and remain distinct from unassigned water. Erase capsules set
  the mask; land painting clears it. Empty land donors are archived with stable
  names/IDs. Physical land and passable-part indexing remain separate.
- `province_edit_history.gd` stores before/after mask bytes with pixel ID deltas,
  activation and part-policy changes. The existing 50-edit/64-MiB pixel-delta bound
  remains, with mask bytes included in the accounting. History remains session-only.
- `province_border_brush.gd` adds the fourth tool and supports no-selection erasing
  and restoration into a newly allocated land ID. Drafts stay separate until commit.
- The shared shader renders unassigned impassable land in dark grayscale relief,
  preserving the two-tone sea presentation and original terrain-only view.
- Province section v6 stores the mask and authored-part policy; v1-v5 remain
  readable with no added impassable areas. Terrain v10/world manifest v3 remain.
  Invalid mask dimensions/values, assigned masked pixels and masked water reject
  before changing the live map.

## Verification and next work

`impassable_land_smoke.gd` covers draft isolation, erase/repaint, exact Undo/Redo,
shared-border adjacency removal, ridge-separated land parts, restoration into a
different province, physical-island semantics, water protection, empty-province
archival, new-province restoration, old-format loading, ocean regeneration, actual
editor gestures/controls, disk save/load, locks and gameplay state. Graphics output
is captured from the actual application. The 2050-square suite includes erasure,
Undo/Redo and exact mask restoration alongside split and all source layers.

Automatic mountain-based marking, movement rules and expanded visual labels are
later work. Manual painting is unrestricted by elevation so authors can choose
which terrain should be impassable. Manual visual/zoom/performance review remains
with the user.
