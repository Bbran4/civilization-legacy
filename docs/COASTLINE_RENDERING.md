# Coastline ribbons

Ocean coast outlines now use soft-edged triangle ribbons in Terrain view at every
zoom. They retain ordinary scene depth testing: foreground mountains and objects
can hide them. This replaces the old overview-only line overlay that drew through
terrain. Beach ground remains part of the terrain material; foam, waves, lake
rims and political borders are separate future presentation systems.

## Geometry and width

`terrain_geography_view.gd` traces the sea-level contour of the fixed highest-detail
rendered height field using the existing geography owner's triangle-contour
algorithm. It does not replace canonical cell coast flags, saved geography paths,
feature IDs, hydrology or source heights. For graphless/disabled-detail rendering,
the base field is used with the same visual relief scaling as its mesh.

Each accepted segment gets a triangle strip with cumulative world distance in UV.x
and signed cross-strip position in UV.y. Closed rings retain a closing segment;
cropped open paths have butt caps and never gain an invented map-frame border.
Consecutive numerical duplicates are removed. Ordinary joins use a miter capped
at two half-widths; acute bends use a bevel wedge instead of a long spike. Opposite
banks and independent loops are never stitched together. Ocean membership is
filtered per segment using the hydrology owner, so lake candidates are not
outlined as sea merely because their bed lies below the sea datum.

The shader projects the side direction through the camera to target **1.6 pixels
in overview** and **1.25 pixels up close**, smoothly blended with the existing
camera transition. Half-width also has a world-space cap of 0.25% of the longest
map edge, with a two-half-width maximum join reach. Soft alpha edges make measured
colour coverage narrower than the full ribbon. These are automatic style defaults,
not new generation controls. Very narrow or subpixel channels cannot be made
fully readable at every zoom; their terrain and topology are preserved.

## Surface following and depth

The LOD owner retains three read-only numeric height textures, generated with its
three existing full-map height levels. The coastline shader samples the same
triangle diagonal as the terrain mesh and interpolates the current parent/fine
fields by the displayed LOD morph factor. It follows the higher of sea level and
displayed ground, then adds a small height bias bounded to 0.0005-0.01 world units.
Depth testing stays enabled; transparent edges do not write depth. Render ordering
helps surface layering but cannot override foreground occlusion.

The fixed high-field mesh stays unchanged as zoom changes. Its centerline is
locally projected onto the displayed sea edge with up to four bounded height-root
corrections, limited to 1.5 coarse-cell diagonals. This reduces the edge offset
caused by a coarse LOD approximating the fine contour differently. All vertices
at one join share the same projection direction, keeping bevels connected. Width extrusion,
edge projection, LOD draping and a few uniforms update on the GPU; no new paths,
mesh rebuild or geographic regeneration occurs on zoom. Rainfall edits reuse the
ocean ribbon mesh. New terrain/relief fields rebuild presentation. The mesh bounds
include shader expansion and vertical draping, and ribbons do not cast shadows.

The detailed contour follows the finest rendered field. Local edge projection is
bounded and can fail where a tiny high-detail island disappears entirely from a
coarser height field, or where the local derivative gives no usable water crossing.
It does not invent a missing landmass, change topology or recover sub-grid coves.
Extreme silhouettes or relief may still occlude small parts of a ribbon. The extra
contour pass, height textures and local shader sampling add generation/GPU work
and memory on large maps; no frame-rate or maximum-map performance claim is made.

Ribbons are hidden in Temperature, Rainfall, Winds, Drainage basins, Biomes and Show
heights. Return to Terrain to restore them. Noncanonical manually moved sea planes
continue to suppress canonical sea outlines. Existing version 8 saves are unchanged
and derive the new appearance on load.

## Executed verification

Godot 4.7.2 Compatibility / OpenGL, GTX 1050 Ti:

```text
godot --path . --script res://tests/terrain_coastline_smoke.gd
godot --headless --path . --script res://tests/terrain_geography_smoke.gd
godot --headless --path . --script res://tests/strategy_zoom_smoke.gd
```

The coastline test checks triangle primitives, closed-loop length, open caps,
acute bevels, bounded joins, duplicate points, per-segment filtering, independent
strait banks and empty inputs. Rendered fixtures verify stable width across 20,
10 and 5 world-unit orthographic views, complete foreground-object occlusion and
height following at parent/fine blends 0, 0.5 and 1. A displaced-edge fixture
also checks horizontal projection onto the actual sea crossing at those blends. Measured soft colour coverage
was 1.09 pixels at all three tested zooms, under the nominal 1.6-pixel ribbon.
Actual map integration checks persistent mesh identity, current LOD field binding,
climate-edit reuse, unmodified geographic snapshots, diagnostic visibility and
base-only rendering after disabling terrain detail.
Captures are written to `.godot/coast-*.png` for visual inspection.

Geography regressions cover island/hole/strait/cropped topology and save migration;
camera regressions verify the existing three fixed LODs. The rendered material
regression also passed with the new outlines, including its diagnostic image
comparison. No native CK2 rendering behavior is claimed or required.

This implements the first coastline step in chapter 7 of the
[presentation manual](CK2-map-to-Godot-implementation-manual.md). Deterministic
[vegetation placement](VEGETATION.md) now consumes the biome/canopy/water facts.
The shader height sampler and LOD field binder are shared with tree presentation.
