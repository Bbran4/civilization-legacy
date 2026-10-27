# Layered terrain materials

The Terrain view now combines biome colour, regional tint, repeating surface
textures, fine normals and roughness. This implements the initial material step
in chapter 6 of the presentation manual. It does not change source heights,
climate, hydrology, biome identity, picking or the three fixed terrain LODs.

## What is visible

Seven original procedural surfaces are provided: grass, dry grass, soil, sand,
rock, snow and wet ground. Biome climate selects a blend of the first four;
canopy suitability adds forest-floor soil. Beaches expose sand, water availability
adds darker wet ground, slopes/high relief expose rock and existing cold/slope
rules provide snow coverage. Rock samples three projections to reduce stretching
on cliffs. Grass/dry grass are surface patterns, not individual 3D blades.

The existing continuous biome palette supplies the broad land colour. A separate
seeded regional RGB multiplier supplies restrained warm/cool variation. This is
appearance data, never a second classification authority. Native biome IDs remain
unchanged; the Biomes diagnostic still shows their categorical colours.

Each texture repeats every **8 world units**, regardless of map dimensions.
Albedo, micro-height, normal and roughness detail fade with projected pixel size
and the overview blend. Fine detail fully fades when a pixel spans 0.4 world
units; the fully zoomed-out map retains its readable regional colour. Mipmaps and
anisotropic filtering reduce distant shimmer. These are fixed presentation
choices, with no additional player-facing generation settings.

Run the scene, keep the bottom-right view on **Terrain**, and zoom inland or near
a wet bank. Zoom out to compare the clean flat overview. Temperature, Rainfall,
Winds, Drainage basins, Biomes and Show heights bypass decorative tint/detail so
their numeric or categorical meaning remains readable.

## Seeded terrain transitions

The Terrain view now uses three scales of world-space noise to break up material
contacts and add restrained grass, dry-ground and soil patches inside mixed
habitats. Approximate patch spacings are 32, 6 and 1.5 world units; these are
fixed presentation scales, independent of map width and height. A bounded warp
(up to two units per axis) bends appearance sampling near contacts. Appearance-only climate offsets interrupt otherwise uniform colour bands.

The colour lookup and material-weight lookup now share a broader transition band
around climate classification thresholds. The previous narrow palette smoothing
could leave an almost straight forest/dry-ground or desert edge even when material
noise was active. Two sliding box passes per axis produce a triangular filter
with support of +/-4 degrees C and +/-240 mm/year (plus the original small
palette smoothing). This is a cached rendering lookup, separate from the original
domain palette and categorical biome field. Uniform interiors stay unchanged
when the filter footprint contains only their own biome.

Seeded signals offset appearance lookup coordinates by `(signal - 0.5) * 8` C
and `(signal - 0.5) * 1000` mm/year before material patch weighting. These are
bounded visual variations, not edits to annual climate measurements. Broadening
both lookups allows neighbouring ground materials to participate at the same
contacts as the colour transition, rather than applying noise only inside an
otherwise sharply coloured biome. The width of this colour band on the map
depends on the local climate gradient; the noise patch spacing remains fixed in
world units.

Ground weights remain normalized. The same weights influence pigment, texture,
roughness and fine normals; micro-height adds smaller contact detail. Wet ground,
beach sand, rock and snow also receive restrained contact variation while pure
mask interiors stay intact. These changes do not create different native biome
IDs, temperature/rainfall measurements, terrain geometry or water routing.

The map seed selects a stable offset into one shared, periodic RGBA noise texture.
Base terrain and all three LODs use that same field. Zoom fades unresolved noise
scales and texture detail without regenerating patterns or relocating the broad
warp. Larger maps retain the same physical patch scale. This remains a periodic
procedural starter material: authored textures and broader art tuning can improve
it further, and it does not claim to reproduce CK3's shader.

Blending is automatic in **Terrain**. There are no new generation controls. Height,
climate and categorical diagnostic views bypass this decorative layer.

## Data and ownership

- `scripts/rendering/terrain_materials.gd` owns the original procedural library,
  climate-to-material weight palette, matched appearance transition colour/weight
  lookups, shared numeric transition noise and seeded regional multipliers.
- `terrain_blending.gdshaderinc` owns world-space transition masks, appearance warp,
  normalized patch weights and pigment variation.
- `terrain_surface.gdshaderinc` owns the normalized texture blending and normal
  composition; `terrain.gdshader` combines it with biome ground colour, beaches,
  exposed rock, snow and diagnostic views.
- The seven albedo layers share one Texture2DArray. Their RGB is colour data and
  alpha explicitly means micro-height for transition weighting. A separate array
  contains numeric tangent normals in RGB and roughness in alpha. Material
  identity is the array layer, not an RGB colour.
- All mip levels belong to their individual array layers, so adjacent surfaces
  cannot bleed through atlas borders. Albedo uses `source_color`; numeric normals,
  roughness, weight channels and regional multipliers do not.
- Albedo is normalized around its encoded neutral value in Compatibility and its
  linear neutral in Forward+/Mobile. Only Compatibility was executed and verified.
  Detail gradients are decoded to terrain-local coordinates, cliff projections
  are reoriented, the gradient is projected onto the macro tangent plane and the
  resulting normal is transformed to view space. No mesh tangents are required.
- Base and LOD materials share the cached library. It builds once per process.
  Regional noise rebuilds only for a different seed/map extent. Climate edits use
  the updated ecology field with existing textures and meshes; zoom never builds
  materials or changes simulation data.

The library is generated from original periodic noise at 128 by 128 texels per
surface. There are no copied CK2 images/shaders, downloads or added packages.
These are restrained starter textures; detailed authored art, seasonal variations,
richer authored vegetation art and erosion are future work. The separate
[vegetation pass](VEGETATION.md) now supplies original starter tree models. Repeating motifs can still become
visible across large uniform regions. Normal detail changes lighting, not terrain
silhouettes or water depth. River presentation is documented separately in
[presentation refinements](PRESENTATION_REFINEMENTS.md).

Version 9 stores the tree target and still derives material presentation: presentation is derived from the saved map seed,
extent and current biome/climate facts rather than another persisted image cache.

## Validation

Executed on Godot 4.7.2 Compatibility / OpenGL with the GTX 1050 Ti:

```text
godot --path . --script res://tests/terrain_materials_smoke.gd
godot --path . --script res://tests/terrain_blending_smoke.gd
```

The check verifies seven matching texture layers, periodic seams, mipmaps,
normal-vector/roughness ranges, shared base/LOD resources, fixed world scale,
climate updates retaining meshes/library, deterministic presentation after save
application and no library rebuild on zoom. GPU captures compare layered versus
plain close terrain and assert that toggling decoration does not alter rainfall
diagnostic pixels. A brightness check guards the Compatibility neutral baseline.
Captures are written to `.godot/materials-*.png`. The climate regression was also
run with graphics and passed. The blending GPU check compares enabled/disabled uniform-ground patches, fixed
world scale after doubling map dimensions, different/repeated seeds, unchanged
rainfall/height diagnostic pixels and unchanged native data and mesh identity
across zooms. Dedicated forest/dry-ground and hot-desert gradient fixtures check
that halfway colour contours gain noise variation. Neutral-noise captures isolate
the underlying palette contact and verify a smaller strongest colour slope across
four pixels, avoiding 8-bit capture quantization. Material weights remain normalized
and deep desert interiors retain their colour. Captures are in `.godot/blending-*.png`; close terrain and the
controlled transition comparison were inspected visually. No frame-rate or cross-renderer performance claim
is made.

Godot references: [spatial shader normal spaces and OUTPUT_IS_SRGB](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html),
[sampler colour hints and texture arrays](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html).
The original [presentation manual](CK2-map-to-Godot-implementation-manual.md)
provides design context; its historical source findings are preserved.

The next presentation step is now implemented: [width-controlled, depth-tested
coast outlines](COASTLINE_RENDERING.md), separate from beach ground, water foam
and future political borders. Deterministic [biome-driven vegetation](VEGETATION.md) is now implemented.

A fixed high-detail macro-normal field now supplies per-pixel terrain relief
shading across mesh LODs; see [presentation refinements](PRESENTATION_REFINEMENTS.md).
