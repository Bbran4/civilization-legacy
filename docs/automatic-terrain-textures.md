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
  geographic shoreline distance estimates supply slope-limited sand with varying
  width; broad world-scale slope supplies exposed rock; altitude supplies snow.
  Seeded macro variation and tile alpha break up material edges, including a softer
  snowline. Two differently oriented grass/earth samples reduce obvious repetition.
  Rock uses triplanar coordinates to reduce stretching on steep faces.
- A nine-point local water estimate includes diagonal banks. River edges expose
  darker damp soil with greener outer fringes; lake shores gain damp sand. Reach
  respects both world units and the water mask resolution. This is appearance only:
  water visibility does not redefine the geographic bank input, while removing the
  mask removes its bank influence. Paint and political/water overlays retain priority.
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
samplers, and the tested Compatibility hardware supports the full combined shader.
The blending pass adds texture reads for bank sampling and grass/earth detail;
it adds no textures, CPU bakes or saved settings. Runtime CPU/frame-time/memory benchmarks have
not been claimed. Color/contrast and visual thresholds remain art-direction choices.

## Verification

`automatic_textures_smoke.gd` checks exact repeat generation for equal seeds,
changed variations, bounded tiles/mipmaps, invalid settings, GPU grass/sand/rock/snow
placement, paint/water priority, raw grayscale, cached-library reuse, UI locking and
visibility, JSON reload, legacy appearance and fail-before-apply behavior. Captured
flat and close-up views are under `.test-runtime/` for visual inspection.
The blending regression also renders a 25-step snowline elevation sweep and
vertical/horizontal river masks: nearby dry bank pixels darken, distant ground
stays unchanged, hiding water preserves banks, and removing its mask clears them.

Executed on locally available Godot 4.5.1 Mono with OpenGL Compatibility; exact
project-target 4.7 behavior remains unverified. The engine emits certificate-store
and generic OpenGL initialization diagnostics in this environment; successful
assertions are reported separately. The complete historical suite is not claimed.


Executed checks for this change: automatic texture checks pass headless and with
GPU rendering; `map_paint_smoke.gd` and `zoom_relief_smoke.gd` pass with graphics;
`git diff --check` is clean. The GPU checks also confirm that hiding generated water
reveals the textured bed rather than leaving a duplicate water layer underneath.

For the blending refinement, GPU `automatic_textures_smoke.gd` and headless
`forest_smoke.gd` / `map_paint_smoke.gd` completed with zero failures on that engine.
