# Automatic terrain textures

The Ground paint layer now owns automatic procedural materials underneath its
manual paint image. No extra world layer or external asset download is required.
New worlds enable generation by default. Terrain documents through version 12 keep
their previous appearance until the user enables it; version 13 saves the choices.

## Ownership

- `domain/terrain_texturing.gd` owns versioned defaults, bounds and validation.
- `rendering/procedural_ground_textures.gd` creates five seeded 128×128 RGBA tiles:
  grass, earth, sand, rock and snow. Noise wraps periodically, fine grain uses a
  deterministic integer hash, and mipmaps are generated once. Alpha carries a
  coarse material-variation field; RGB carries albedo.
- `rendering/automatic_ground.gdshaderinc` owns continuous placement/blending from
  existing terrain/geography textures. Gentle land blends grass and earth;
  geographic shoreline distance estimates supply sand; broad world-scale slope
  supplies exposed rock; altitude supplies snow. Nearby water increases greenery.
  Rock uses triplanar coordinates to reduce stretching on steep faces.
- `terrain_map_renderer.gd` retains one library per world seed/variation. Changing
  seed/variation replaces the library; scale and coverage settings only update
  uniforms. Hidden/disabled textures do not trigger generation. Zoom does not
  regenerate assets. No full-world image bake is retained or serialized.
- Ground paint UI parses settings before applying them. New variation increments
  the parsed seed before committing, avoiding stale SpinBox display text and an
  unnecessary intermediate material generation. Existing visibility/locking applies.
- `terrain_document.gd` validates settings before changing live state and stores
  them beside manual paint. Height, water, surface and province identity are unchanged.

## Limits

This is procedural albedo texturing with existing relief shading. It is not a
climate/biome simulation, scanned-material library, texture painting brush, dynamic
shadow system or vegetation pass. Snow uses height percentage, not temperature.
Shore distance and wetness are local estimates rather than a baked hydrological
soil model. Finite tiles repeat, although macro variation and mip filtering reduce
repetition. There are no generated microgeometry or material normal maps yet.

Generation is synchronous but bounded to five small images. The material adds five
samplers (fourteen total in the current combined shader), so the tested Compatibility
hardware supports the full shader. Runtime CPU/frame-time/memory benchmarks have
not been claimed. Color/contrast and visual thresholds remain art-direction choices.

## Verification

`automatic_textures_smoke.gd` checks exact repeat generation for equal seeds,
changed variations, bounded tiles/mipmaps, invalid settings, GPU grass/sand/rock/snow
placement, paint/water priority, raw grayscale, cached-library reuse, UI locking and
visibility, JSON reload, legacy appearance and fail-before-apply behavior. Captured
flat and close-up views are under `.test-runtime/` for visual inspection.

Executed on locally available Godot 4.5.1 Mono with OpenGL Compatibility; exact
project-target 4.7 behavior remains unverified. The engine emits certificate-store
and generic OpenGL initialization diagnostics in this environment; successful
assertions are reported separately. The complete historical suite is not claimed.


Executed checks for this change: automatic texture checks pass headless and with
GPU rendering; `map_paint_smoke.gd` and `zoom_relief_smoke.gd` pass with graphics;
`git diff --check` is clean. The GPU checks also confirm that hiding generated water
reveals the textured bed rather than leaving a duplicate water layer underneath.
