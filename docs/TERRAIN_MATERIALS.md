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

## Data and ownership

- `scripts/rendering/terrain_materials.gd` owns the original procedural library,
  climate-to-material weight palette and seeded regional multipliers.
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
vegetation models and erosion are future work. Repeating motifs can still become
visible across large uniform regions. Normal detail changes lighting, not terrain
silhouettes or water depth. The existing river-water rendering is unchanged.

Version 8 saves remain valid: presentation is derived from the saved map seed,
extent and current biome/climate facts rather than another persisted image cache.

## Validation

Executed on Godot 4.7.2 Compatibility / OpenGL with the GTX 1050 Ti:

```text
godot --path . --script res://tests/terrain_materials_smoke.gd
```

The check verifies seven matching texture layers, periodic seams, mipmaps,
normal-vector/roughness ranges, shared base/LOD resources, fixed world scale,
climate updates retaining meshes/library, deterministic presentation after save
application and no library rebuild on zoom. GPU captures compare layered versus
plain close terrain and assert that toggling decoration does not alter rainfall
diagnostic pixels. A brightness check guards the Compatibility neutral baseline.
Captures are written to `.godot/materials-*.png`. The climate regression was also
run with graphics and passed. No frame-rate or cross-renderer performance claim
is made.

Godot references: [spatial shader normal spaces and OUTPUT_IS_SRGB](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html),
[sampler colour hints and texture arrays](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html).
The original [presentation manual](CK2-map-to-Godot-implementation-manual.md)
provides design context; its historical source findings are preserved.

Next presentation step: width-controlled, depth-aware coast outlines, kept
separate from beach ground, water foam and future political borders.
