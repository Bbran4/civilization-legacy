# Layered ground painting review

The separate 3D painter has been replaced with a Ground paint layer in the existing
world generator. It uses the existing overview, camera and shared gameplay renderer.
No additional terrain mesh, copied world or separate appearance file is involved.

## Ownership and composition

- `domain/map_paint.gd` owns the paint image, bounded undo history and PNG payload.
- `ui/map_paint_brush.gd` owns brush interaction and interpolated drag strokes.
  Picking intersects the actual overview plane rather than its shaded height data.
- `rendering/terrain_map.gdshader` composites paint after terrain relief, before
  water, province fills and borders. Raw height view bypasses appearance paint.
- `storage/terrain_document.gd` validates and restores paint with world generation
  data. Version 12 adds paint; older files start transparent. PNG dimensions are
  checked before decoding to bound image allocations.
- `storage/world_manifest.gd` version 5 owns paint visibility/locking alongside the
  other layers. Versions 1–4 migrate in memory. Paint has no dependent generation
  layers, so painting cannot invalidate their caches.

The standalone painter scene, scripts, shaders and its obsolete smoke test have
been removed. Existing generation, water, province and border workflows remain.

## Limits

Paint currently means soft color strokes and erasure, not texture asset brushes,
biome simulation or tree placement. The paint raster is 1024×1024 with sixteen
undo images. It follows normalized coordinates when map dimensions change.
Large saves still load synchronously. Existing water/surface/province integration
checks have emitted resource cleanup warnings; clean lifecycle verification is
not claimed. Exact Godot 4.7 behavior remains unverified.

## Executed checks for this change

- `map_paint_smoke.gd`: zero failures headless and with OpenGL Compatibility;
  inspected a rendered capture showing paint under rivers, lakes and borders.
- `terrain_surface_smoke.gd`: PASS, including older-manifest migration.
- `world_provinces_smoke.gd`: PASS, including save/load, stale data and gameplay.
- `git diff --check`: clean.

The local Godot 4.5.1 engine reports certificate-store errors and generic OpenGL
initialization diagnostics in this environment. Rendering and the integration
assertions complete. Retained surface/province tests also report resource cleanup
warnings at exit; these remain unresolved. The full historical suite was not run.
