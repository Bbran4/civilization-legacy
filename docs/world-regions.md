# Regional appearance

`domain/world_regions.gd` owns one 128×128 RGBA8 field per world seed. Red holds
lowland warmth and green holds moisture. Independent seeded noise perturbs warmth
and moisture; top/bottom edges are cooler and the map center warmer. Elevation
reduces warmth using the shared lapse constant. These are normalized artistic
values, not degrees, rainfall, weather, seasons or a water-cycle simulation.

The renderer retains one field, generates it even when ground appearance is hidden
(forests still need it), and replaces it only when the seed changes. CPU samples
the quantized texels with the same clamp/texel-center bilinear mapping as the GPU.
Texture and forest variations do not reseed climate. Zoom and layer visibility
reuse it. There is no new world layer, saved payload or settings migration.

Ground moisture guides grass/soil balance, dry warm regions gain warmer muted
colors, and cold regions lower the snowline. Existing manual paint, water and
political overlays remain above these materials. Forest placement samples the same
field: dry/cold areas have lower suitability and cold areas favor conifers. Local
tree limits respect the regional texture snowline. Source heights, hydraulic data
and province identity are never written by this appearance pipeline.

This changes regenerated appearance and tree layouts for existing seeded saves.
Earlier terrain documents with automatic textures/trees disabled remain disabled.
The base field adds one 64 KiB image plus its GPU texture (driver overhead unmeasured)
and one terrain sampler. No CPU/frame-time benchmark is claimed.

Checks in `automatic_textures_smoke.gd` cover seed repeatability, bounded resolution,
moisture range, latitude/elevation cooling and CPU edge sampling. GPU checks use
controlled climate inputs to verify greener wet regions and lower cold snowlines,
then restore the real shared field. Forest checks cover regional snow limits,
unchanged source geography, deterministic save/reload and climate reuse when
texture variation changes. Validation uses installed Godot 4.5.1 Compatibility;
the project's target 4.7 remains unverified.

Executed: GPU automatic-texture and forest checks, plus headless map-paint checks,
all completed with zero failures. Engine certificate-store and generic OpenGL
startup diagnostics remain present in this environment. `git diff --check` passed.
