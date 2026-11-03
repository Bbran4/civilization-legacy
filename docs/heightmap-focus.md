# Grayscale heightmap focus

The active editor now works only on heightmap terrain, using the existing Noise
and 14 procedural templates plus supplied/imported heightmaps. Default: Continents,
seed 42. Trees, biomes, climate, river/lake water surfaces, provinces, ground paint
and their editing controls are disabled. The code is retained for later work.

## Controls

- Template and Seed choose the broad land layout.
- Coast detail adds smaller bays, headlands and islands around the template coast.
- Mountain detail adds continuous ridges, branching shoulders and shallow erosion
  valleys. These are height changes; no river or lake layer is created.
- Resolution offers 513 or 1025 samples along the longest edge (the existing save
  format uses 512 or 1024 grid cells). Aspect ratio follows map width/height.
- Generate applies the staged choices; New seed generates another world.
- Shaded relief preview adds grayscale lighting to inspect landforms. It defaults
  off and changes neither saved samples nor exported height values.
- Export grayscale PNG writes the canonical height field as an 8-bit grayscale
  image. World/terrain documents retain the full float32 height samples.

Black is low terrain and white is high terrain. Template sea datum is 20% height;
raw exports retain elevations below it, rather than painting them with water.
The default viewport is a flat, unshaded grayscale height field. Coastlines can
also be inspected in the optional shaded preview. Wheel/pan/full-map navigation
remains available. Clicking the map inspects the actual refined sample height.

## Generation changes

Previously automatic density could reduce the default map to 1,000 source cells.
The focused profile now uses 20,000 source cells and a high-resolution scalar
raster. Native template recipes are unchanged. Their continuous raster is refined
with seeded, multi-scale coastal domain warping and ridge/branch detail, followed
by shallow downhill rain-trace erosion. Diagonal steps account for distance.
The refinement does not change the original template cell-height arrays.

This is a procedural first pass toward more natural terrain; it does not claim
DEM accuracy or reproduce Imperator's authored geography. Erosion is lightweight,
not a full sediment/tectonic simulation. Further visual tuning should stay on this
heightmap layer before other systems are re-enabled.

The viewport reads the same scalar data used by saves and exports, on one plane.
It does not rely on extra camera-dependent LOD detail to create an appearance that
is absent from the saved map. This avoids constructing millions of mesh triangles
just to inspect a grayscale image. The geographic cache is retained for the legacy
terrain document contract, but climate, hydrology, biome, tree and province
simulation are not instantiated.

Supplied and imported heightmaps are sampled directly, preserving their authored
heights instead of quantizing through the coarse cell grid or adding template
noise. Coast/mountain and island shaping controls are disabled for these sources.

## Compatibility

Existing terrain documents and exact saved samples still load. Restoration never
runs refinement a second time. Terrain format version 10 is retained with an
optional, validated `heightmap_detail` section (refinement version, coast and
mountain settings); older documents without it remain readable. Old terrain saves
are not rewritten by world saves, which still publish separate snapshots.

The full pipeline remains available through the Terrain node's `heightmap_only`
flag, for later reactivation. Existing subsystem test fixtures explicitly select
the combined pipeline and their original Noise template, rather than depending on
the active editor's new defaults.

## Validation

- `heightmap_focus_smoke.gd`: all 14 templates refine deterministically; normalized
  bounds; unchanged source cells; zero-detail identity; main-scene focus;
  disabled generators/controls; canonical grayscale export; exact terrain/world
  save/restore; legacy optional metadata; direct import sampling; plane picking.
- `heightmap_parity.gd`: the original cell recipes still match the upstream
  JavaScript reference for all 14 templates and reference seeds.
- Phase 1, world workflow, editor, palette, climate and hydrology regression suites.
- The focus suite also renders both raw and shaded workspace screenshots with
  Godot's OpenGL renderer for visual inspection.

All generation and screenshots come from the game code, without image retouching.
