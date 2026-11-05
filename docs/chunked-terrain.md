# Camera-dependent terrain patches

Large display fields now use terrain patches instead of the single 512-cell relief
grid. The cheap flat overview remains. Source fields up to 513 pixels retain their
existing grid. Larger fields use up to 16×16 patches, with the shorter axis following
map aspect ratio. Each patch selects one of five shared density meshes: 8, 16, 32,
64 or 128 cells per side. A 2050-pixel source can therefore show approximately 2048
cells along its longest edge near the camera. This is presentation-only; terrain
v15, world manifest v6, hydrology and authoritative province IDs are unchanged.

## Detail selection and transitions

`terrain_patches.gd` selects density from projected cell size (a four-pixel target)
and distance from the camera focus. Far patches use coarser shared meshes. Native
source resolution caps the maximum detail. Frustum culling operates on each patch;
full-resolution extrema from the display-preparation job conservatively bound them.

Fine vertices blend from the parent mesh's triangle surface, with continuous zoom
and spatial weights. At a density threshold the finer mesh starts on the same
parent plane. The distance radii are separated by two patch diagonals, and morph
bands are capped at half a diagonal. This ensures the parent is fully detailed
where a child patch exists: shared fine/coarse edges match without skirts. Adjacent
patches differ by at most one level. Small camera movements update weights, density
choices and a small LOD texture; they do not rebake the display-height field.

Meshes are shared ArrayMeshes, with level metadata in vertex color alpha. Patch
positions use ordinary node transforms. This avoids consuming the limited GL
per-instance shader-parameter buffer when the editor and Play map coexist.

## One displayed surface

`map_relief.gdshaderinc` samples the actual morphed patch triangles. Terrain
vertices, tree roots and province ribbons share this definition. CPU sampling in
`terrain_patches.gd` uses the same lattice, diagonal and morph weights. Picking
marches conservatively at the finest supported cell spacing and then refines the
hit. It does not intersect an unrelated full-resolution height approximation.

Borders and authoring previews split at the finest shared lattice. That lattice
also contains every coarser edge and diagonal, so draped segments stay on the drawn
surface as levels change, without rebuilding paths on camera movement. Ribbon
width probes use their local patch cell size. Map-local UVs are reconstructed using
the terrain owner's inverse transform. The GPU test checks translated terrain too.

The renderer exposes `set_chunking_enabled(false)` as a fallback/comparison switch;
it is not a new authoring setting or saved field. Raw height inspection still uses
the overview plane. Height exports and saved source arrays remain unchanged.

## Verification and observed limits

Godot 4.7.2 / Intel UHD 730 OpenGL Compatibility:

- `terrain_patches_smoke.gd`: mixed detail, matching edges, continuous density
  thresholds, bounded assigned triangles, unchanged sources/cache builds, narrow
  channel comparison, GPU/CPU height agreement, no sampled seam holes and translated
  terrain. Mixed-edge CPU error was below 0.0001 world units; threshold crossing
  changed tested heights by 0.00000367 units. GPU readback uses an 8-bit height color,
  with observed maximum error 0.29812 units within its quantization tolerance.
- In the controlled channel fixture, height error versus the display field fell
  from 8.83900 units on the old grid to 1.77126 with close patches. This is one
  synthetic feature, not proof that every one-pixel river becomes smooth geometry.
- The tested view/focus matrix assigned at most 2,290,688 triangles versus 8,388,608
  for a uniform 2048-square grid. A mixed-detail GPU diagnostic rendered 196,608
  primitives after culling. Assigned triangles and rendered primitives are different
  measurements; these numbers are not frame-rate guarantees.
- `terrain_patches_integration_smoke.gd`: camera picking across zoom/pan, no rebake,
  exact draped-line segmentation, shared tree sampler, an actual political line on
  a raised patch surface, raw-mode restoration and Play map reconstruction.
- Existing display cache, normals, relief, regional/tree, shared-renderer, shadow
  and border checks cover affected consumers. The sea border-width fixture now
  enables the current blue water palette so dark grayscale sea is not counted as ink.

This resolves geometry below the former 512-cell cap; it cannot create detail
missing from the source. Extreme close views expose the generator's existing rough
ridges. Sources with unusual aspect ratios can oversample their shorter dimension.
Density constants are currently internal, not user-facing quality presets. Maximum
forest/shadow frame time and peak process memory have not been benchmarked.

Water still uses the shared display-height/colored-overlay path. Separate water
surfaces and more convincing water presentation remain the next terrain stage.
