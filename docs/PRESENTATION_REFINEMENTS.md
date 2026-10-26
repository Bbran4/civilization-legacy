# Tree, river and relief refinements

These belong to the terrain presentation layers already started. River occlusion
and mouth overlap were defects in that first pass, not features intentionally
waiting for snow/ice. The following corrections are implemented.

## Trees

The editor now has an applied population target (0-250,000), actual-count feedback,
editable `.tscn` tree assets and an extensible habitat catalog. See
[tree controls and editing guide](VEGETATION.md). Definition rules can intentionally
add desert or snowy-land variants without changing biome identity. Target counts
remain limited by suitable ground, spacing and placement work.

## Rivers and standing water

Rivers were already triangle ribbons, but the previous shader disabled depth
testing and was static. Native routes also reached destination cell centres,
including lake and ocean cells. This made streams appear through mountains and
across receiving water surfaces.

Water now retains normal depth testing. River banks are sampled/draped to the
terrain, and the shader follows the actual displayed LOD height blend. Fragment
depth is reconstructed from that same height sample to reduce small ribbon/terrain
intersection gaps. The height offset is bounded, rather than growing without
limit with map size. Lake planes also use a small fixed offset and depth testing.

The water view indexes the actual clipped lake polygons. Fine river spans are
cut where their centers enter a visible lake or ocean; bank edges are clipped
back to dry ground too. A tiny landward inset protects boundaries against float
rounding. Lake outlets are clipped in the opposite direction, beginning at their
shore instead of their underwater source-cell center. The vegetation clearance
index consumes these final dry spans rather than the former over-water route.

Across-stream and cumulative downstream coordinates drive animated ripples and
bank colour. Steep descending spans get a faster-looking foamy cascade treatment.
These are flowing surface ribbons on the existing heightfield. **Detached cliff
waterfalls, spray/particles, plunge pools and carved riverbeds are still separate
work.** The display does not rewrite the hydrology route or erode the heightmap.
No exact native Paradox shader or waterfall implementation is claimed.

Clipping uses sampled heightfields and lake polygons; microscopic/sub-grid shores
and intersections can still need refinement. River channels have not been carved,
so a conditioned drainage route can still cross terrain that needs channel shaping.

## Why the terrain can look flat

The project already had mesh normals and tiled detail normals. It now additionally
builds a fixed per-pixel **macro normal field** from the highest-detail height
surface, with numeric sampling and normal mipmaps. Terrain LODs share that field,
so broad relief shading no longer depends only on a coarse mesh's interpolated
normals. It combines with the tiled material normal detail without changing source
heights, water routing or biome labels. Zoom does not regenerate the field.

Normals change lighting, not the mountain silhouette. **Elevation (relief)** raises
or flattens actual geometry; the source heightmap controls landforms. Fully zoomed
out, the camera still intentionally uses the flat unlit map view requested earlier.
Recognizable ridges/valleys, erosion/channel carving and authored high-quality
normal/material assets can improve the appearance further. The generated field
is not a copy of CK2's installed normal bitmap or an invented extra height channel.

## Saves and validation

Version 9 stores the applied tree target; versions 1-8 migrate with a default target
while retaining source terrain. Asset scenes/catalogs stay project resources.

`terrain_presentation_controls_smoke.gd` verifies typed count application, zero,
count saving/bounds, scene rebaking, an added desert variant, and fixed shared
macro normals. `river_surface_smoke.gd` uses rendered fixtures to verify animated
flow and full occlusion by a foreground object; a natural map checks every emitted
corridor center and bank vertex is outside standing water, and verifies current
LOD height binding without a river mesh rebuild. A steep generated Volcano
also verifies that slope-driven cascade intensity reaches the shader. Existing hydrology tests also
passed after the geometry change.

```text
godot --path . --script res://tests/terrain_presentation_controls_smoke.gd
godot --path . --script res://tests/river_surface_smoke.gd
```

Next planned work remains ice/snow presentation. Dedicated waterfall geometry and
channel carving deserve their own landform/water pass rather than being described
as completed by the cascade shader.
