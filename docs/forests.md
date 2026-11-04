# Seeded forests

The Trees layer is a decorative, independently configurable world layer. New worlds
enable it; earlier terrain documents retain a tree-free appearance until generation
is requested. Terrain document version 14 stores tree settings; manifest version 6
stores the layer's visibility/lock state. Old tree/climate systems are not revived.

## Ownership and placement

`forest_settings.gd` validates all saved choices. `forest_view.gd` derives a layout
from the world seed, variation, current source-height fingerprint, current water
fingerprint and effective texture snow/rock limits. A deterministic permutation
visits jittered cells throughout the map, preventing early-budget bias toward one
edge. Per-cell seeds keep candidate transforms independent of rejection order.
Noise makes forest patches; a spatial hash prevents crowded trunks/crowns. Broadleaf
and conifer selection varies with elevation and seed, not a simulated climate.

`terrain_map_renderer.gd` owns dry-ground/physical-slope sampling. A lazily prepared
summed-area mask rejects any forbidden source/water sample in a conservative canopy
footprint in constant query time. It includes river and lake coverage even when
water artwork is hidden. Source heights and water content fingerprints invalidate
the mask; zoom, visibility and manual color strokes do not. Empty legacy hydraulic
payloads are skipped when hashing rather than passed to a hash API that rejects
empty updates. Valid nonempty hydraulic fingerprints retain their previous meaning.

Tree placement reads these facts and never writes heights, water, terrain surfaces,
paint or province identities. Ground-material slope/snow choices may rebuild tree
placement; manual paint pixels do not. The Trees layer dependency list reflects the
ground-appearance dependency. Its lock protects settings, not a frozen forest over
newly changed geography.

## Rendering and bounds

Original low-poly meshes are built in code by `forest_meshes.gd`. Broadleaf and
conifer instances are batched by species into an 8×8 spatial grid (at most 128
MultiMesh draws), allowing chunk culling in close views. Per-instance color is
explicitly initialized; vertex colors are passed explicitly to the fragment stage
for Compatibility rendering. A shared material applies mild wind and directional
shading. Trees do not cast dynamic shadows in this implementation.

The forest shader uses the renderer's shared relief grid for root heights. Instance
scale is accounted for, so roots do not float as the map rises/flattens. Culling
bounds include crowns, wind and terrain relief.

Orthographic zoom uses the nominal tree size in screen pixels: at 4 pixels or
smaller all tree batches are hidden, at 12 pixels or larger they are fully visible,
and a smooth crossfade connects the two. Opaque screen-door fading avoids sorting
transparent crowns. Perspective views currently use full geometry. The camera
sets its size before publishing presentation changes, avoiding a one-step lag.

A mipmapped coverage mask, derived from accepted placements and capped at 1024
pixels on its longest side, shades the distant ground. It fades away as trees
appear, below manual paint, water and political overlays, with a geographic land
clip. The Trees eye and raw-height view hide both representations. Zoom changes
uniforms and batch visibility, never placements, transforms or coverage pixels.
No additional saved data or migration is needed.

The saved tree budget is at most 20,000 and placement visits at most 160,000
candidates. Actual counts may be lower. The clearance cache is at most one
`(sample_width + 1) × (sample_height + 1)` Int32 buffer, bounded by the supported terrain
resolution. Generation is synchronous. No measured CPU/frame-time/peak-memory
performance claim is made; dense forests and large source grids can still take
longer to prepare. Billboard geometry and manual tree editing are future
work. The models are stylized baseline assets, not scanned or photorealistic trees.

## Executed validation

`forest_smoke.gd` checks actual generated inland water, wet-footprint rejection,
sea/snow/slope exclusions, budget/work/batch bounds, deterministic regeneration,
variation, root relief binding, raw view, visibility/locking, JSON/world reload,
legacy migration, malformed choices and unchanged source geography. Its GPU path
compares visible/hidden forest captures and checks colored leaves rather than black
silhouettes. Cache regressions cover same-resource water-mask changes, hidden water,
and re-binding a mask after source rebuild. Zoom checks cover both endpoints,
the midpoint, reuse of the mask/layout, layer hiding and zero-budget cleanup.
GPU captures check the overview shading and close-up colored tree geometry.

The forest GPU check completed with zero failures. Existing map-paint, automatic
texture, zoom-relief, terrain-surface and world-province smoke checks also passed.
The latter two emitted retained-resource cleanup warnings.
Testing uses the locally available Godot 4.5.1 Mono/OpenGL Compatibility engine;
exact project-target 4.7 behavior remains unverified. The engine emits certificate
store and generic OpenGL startup diagnostics in this environment. The complete
historical suite is not claimed.
