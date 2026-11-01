# Terrain material palette and coverage blending

The Terrain view now uses editable, authored surface choices. Each land biome
has three texture/pattern slots; beach sand, mountain rock, snow cover and wet
soil also have separate rows. A runtime brush can paint a biome mix or an
individual slot without changing geography or ecology.

Start with the [plain-language texture and painting guide](GROUND_PAINTING.md).

## Colour and coverage ownership

- Colour images provide the actual ground colour. The old regional RGB
  multipliers, cross-biome pigment ratios and broad colour-filter lookup are
  removed. Starter colours apply only while generating a built-in texture;
  imported albedo images are never multiplied by a biome palette colour.
- Numeric black/white masks control texture coverage. Per-slot amount biases the
  competing masks; a narrow normalized contact band feathers their edges. One
  surface dominates most patches, rather than broadly mixing climate colours.
- Seeded world-space sampling, slot repeat sizes and rotation determine patterns.
  The same inputs reproduce the pattern, and zoom does not regenerate it. Colour
  and normal textures have mipmaps and repeating sampling; only normal detail
  fades at distant zoom. Authored coverage patterns remain separate numeric data.
- Noisy climate lookup selects land-biome material identity through the
  domain-owned classification rules. Nearby-water masks select wetland/riparian
  surfaces. Beach, rock and snow masks use the existing coverage-shaped contacts.
  These are appearance selectors; native biome IDs remain unchanged.
- Manual paint overrides generated ground using the same authored surface path.
  The painted row/slot and coverage are numeric image channels, never inferred
  from display colours. Thin brush coverage remains visible; full coverage uses
  the larger blotch masks. Normal and roughness blending follows the same weights.
- Mountain rock uses three projections to reduce stretching on steep faces.
  Fixed macro normals, ridge geometry, snow exposure, cavity tint and overview
  hillshading remain in place. See [mountain terrain](MOUNTAIN_TERRAIN.md).

## Assets and contracts

`terrain_paint_variant.gd` owns the image choices, starter texture/colour, coverage
pattern, tile size, rotation, amount, pattern repeat and roughness for one slot.
`terrain_biome_paint.gd` groups three slots. `terrain_paint_catalog.gd` owns the
19-row/three-slot data contract, validation and serialization. Native IDs 0–14
retain their ordering; water IDs 0 and 12 are reserved/disabled in the ground UI.
Rows 15–18 mean beach, rock, snow and wet soil. This fixed contract supplies 57
layers and bounded shader sampling.

The editable default is `assets/terrain/default_ground_palette.tres`. Runtime
changes use deep copies, keeping other maps and the default asset independent.
The original seven procedural surfaces remain starter-art sources and a simple
fallback; they no longer decide authored biome colour. Original art can be
replaced with PNG/JPG/WebP files or readable saved Texture2D assets.

`terrain_palette_library.gd` resolves all image dependencies before replacing any
live material. It caches one current palette using settings, paths and source
modification times; explicit Apply reloads assets. Resized image copies bound
retained working images. Base terrain and all LOD materials share the resulting
resources, and geometry/climate edits reuse unchanged palette arrays.

Each of the three arrays has 57 layers at 256 x 256:

| Array | RGB | Alpha |
| --- | --- | --- |
| Colour | Source colour, sampled with `source_color` | Reserved; imported alpha does not supply coverage |
| Normal | Renormalized numeric tangent normal | Chosen roughness |
| Coverage | Numeric placement mask, red channel sampled | Unused |

Starter micro-height alpha remains available in the fallback source library;
authored placement is governed by coverage instead. Numeric patterns, normal data,
material IDs and paint are not sampled with `source_color`. Rotation is applied
to both image coordinates and decoded normal directions. The production shader
declares 16 samplers including diagnostic/fallback inputs, staying within the
OpenGL 3 fragment-sampler minimum; only the current Compatibility desktop device
was executed, not other renderers or hardware.

## Painting and persistence

`terrain_paint_layer.gd` owns capsule strokes, falloff/strength accumulation,
erasing, clearing and bounded undo history. Its texture encodes material row in
red, strength in green and optional individual slot in blue. IDs use exact texel
fetches while strength is filtered separately. Strokes update one shared texture;
no terrain mesh, climate, drainage or vegetation rebuild is involved.

The layer allocates on first paint, targeting roughly half-unit texels and capping
the longer edge at 2049 nodes. Undo stores compressed pre-stroke snapshots, capped
at 16 entries and 32 MiB combined. History is not saved with the map.

Version 10 stores palette settings and the PNG paint layer. Source image files
are linked, not embedded. The document owner validates configuration and resolves
images/decodes paint before changing live state. PNG header dimensions are checked
against the bounded layout before decoding; pixel material/slot IDs are validated.
Missing files, invalid patterns/configuration and malformed paint return errors.
Versions 1–9 gain the default palette with an empty paint layer.

`terrain_material_panel.gd` owns the runtime texture window; `terrain_brush.gd`
routes brush input ahead of cell inspection, offers erase/undo/clear and shows a
depth-tested brush footprint. The inspector distinguishes the paint layer from
native facts. Painting is available in Terrain view and leaves other diagnostic
views unchanged. New map generation clears paint; palette application does not.

## Executed checks

Godot 4.7.2 Compatibility / OpenGL on the GTX 1050 Ti:

- `terrain_palette_smoke.gd`: default assets/deep-copy independence; live editor
  cards and file selection; shared 57-layer resources; cached rebinding; invalid
  mixes rejected before replacing textures; source-red/source-blue GPU colour
  preservation and distinct coverage patches; a green brush through the editor
  input handler; row/slot/strength encoding; erase/undo/clear; exact palette/paint
  round trips; missing image and malformed PNG rejection; version 9 migration;
  source heights/biome IDs unchanged. Captures include the real texture window.
- `terrain_materials_smoke.gd`: starter texture periodicity, numeric normal and
  roughness ranges, resource reuse, saved appearance, rendered detail and rainfall
  diagnostic bypass. The neutral brightness check isolates the starter fallback;
  authored image colour is checked separately by the controlled GPU test above.
- `terrain_blending_smoke.gd`: world scale/seed stability, diagnostic preservation,
  fixed native data, and actual production beach/wetland/woodland coverage masks
  in black and white. The old colour-blur assertion is retired with that pipeline.
- Existing editor/document, hydrology, mountain and fixed-LOD/camera regressions
  cover their public workflows with the new material/save implementation.

The original [presentation manual](CK2-map-to-Godot-implementation-manual.md),
[coastline pass](COASTLINE_RENDERING.md) and [vegetation pass](VEGETATION.md) retain
context. Images of earlier beach/material passes are historical; the current
controls and painting previews are in the [new guide](GROUND_PAINTING.md).
Material array construction and map generation are synchronous and may pause the
editor while preparing assets. No frame-rate, isolated benchmark or cross-renderer
performance guarantee is claimed.
