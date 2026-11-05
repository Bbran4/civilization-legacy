# Terrain3D test workspace

The project includes the official Terrain3D **1.1.0** addon, MIT licensed. Its
release supports Godot 4.5–4.8+. Native libraries are installed locally and ignored
by Git. On another checkout, close Godot and run `editor/install-terrain3d.ps1` to
restore the pinned, SHA-256-verified release libraries. The installer preserves an
existing binary directory rather than replacing it.

## Try it

1. Restart Godot after installing the native addon.
2. Open `scenes/terrain3d_trial.tscn`.
3. Select the **Terrain3DTrial** root. Choose template, seed, width, length, height
   range, sea level, mountain detail and mountain weathering in the Inspector.
4. Click **Generate / replace trial terrain**. This replaces only this workspace's
   terrain, including any unsaved sculpting/painting in it. Save first to retain it.
5. Select the **Terrain3D** child to use the addon's native sculpting and material
   painting tools. Grass and cliff slots are provided. Godot's viewport
   navigation applies while editing; select the sea node and press F to frame it.
6. Select the root and click **Carve rivers and lakes** after choosing rainfall,
   warmth, wind direction, river density, width and channel depth. This modifies
   the actual native heightmaps and adds a separate water surface above the beds.
7. Click **Save terrain snapshot**, then **Ctrl+S** to save
   the scene. The scene references the native region directory and stores material
   assets. This is separate from legacy `.terrain.json` / `.world.json` saves.
8. Press **F6** to preview. Wheel zooms, right-drag orbits, middle-drag pans and F
   frames the map. **Inspect generated river** moves the preview camera to a
   generated channel. Preview regeneration is temporary; edit and save in Godot.

The existing runtime editor also has a **Terrain3D test** button that opens this
scene in another game window without transferring or replacing the current world.
The separate window has template, seed, dimensions, height-range and sea-level
controls. Native sculpting/painting and persistence are currently editor-only.

## Scope and limits

### Import a world heightmap

In the Godot editor, select the **Terrain3DTrial** root and choose **World
heightmap** from **Template**, then click **Generate / replace trial terrain**.
Europe and Mediterranean source images are also available. These load the existing
image data directly, without template noise or mountain refinement.

For another image, choose **Imported heightmap** and set **Heightmap File** in the
Inspector. PNG, EXR, JPEG and WebP are supported. In the running preview, use
**Import heightmap image…**, select the image, then click **Generate**. Selecting
a file stages it without changing the displayed terrain.

**Match Heightmap Aspect** fits Length to the source proportions at the chosen
Width, rounded/clamped to the trial's 256-sample tile increments. For the bundled
world, use Width 2048 for a 2048 × 1024 map. Disable it to set both dimensions
explicitly. **Imported Relief** scales imported elevation around the sea datum;
1× uses a full vertical span of 0.5% of the longest map dimension (20.48 world
units for a 4096-wide map). This is a chosen presentation baseline, not recovered
CK3 engine scaling. **Sea Level** selects the normalized height at which the sea
plane intersects it. **Invert Heightmap** reverses heights. Procedural **Height
Range**, **Mountain Detail** and **Mountain Weathering** do not affect imported
heights; they are hidden for imported sources. The seed still controls climate.
The red channel supplies normalized 0–1 height values; EXR inputs should use that
range too. Out-of-range finite values are clamped. Seeds affect procedural
templates, not imported geography. Imported data is converted to float before
resampling; use a high precision EXR when available, since 8-bit images already
have limited elevation precision. Terrain snapshots retain the resulting heights
and source metadata, so saved terrain does not need the external file to display.

Missing or unreadable input leaves the current terrain intact. Generating a valid
new map replaces the trial's current sculpting/painting, as with procedural maps.

### Terrain workspace limits

The bundled World heightmap is **600 × 293, 8-bit**, a small reference image from
the original generator. Upsampling it does not add geographic detail. Import
higher-resolution elevation data to obtain genuinely more detailed mountains and
coasts. The runtime panel records source resolution separately from terrain size.

**Refresh terrain appearance** corrects the slope-based material roles on an
existing terrain without regenerating heights or changing painted control data.
Terrain3D's automatic blend applies the overlay on flatter terrain and the base
on steeper terrain: grass is the overlay and cliff is the base. The first trial
had these assignments reversed. New generations also use a subdued cliff tint.
This is a terrain/material correction, not a completed CK3-style visual pipeline;
vegetation and a distant cartographic presentation still need implementation.
Regional ground tint and carved hydrology are now available as described below.

- Reuses the existing graph, template recipes and height-detail generator; sends
  float32 heights directly to Terrain3D. No 8-bit height export/import round trip.
- Test dimensions are multiples of 256, from 256 to 4096 per axis, at one terrain
  sample per world unit. These are bounded trial settings, not full-world limits.
- Terrain heights are `(normalized_height - sea_level) * vertical_scale`.
  Procedural templates use Height Range as that scale. Imported maps use
  `longest_dimension * 0.005 * imported_relief`. Both preserve the sea contour
  when changing positive vertical scale.
  The simple sea plane stays at zero. Sea level changes flooding, not drainage.
- Includes the upstream demo's CC0 ambientCG grass/cliff materials with height,
  normal and roughness channels. See `assets/terrain3d/asset_licenses.txt`.
  These are testing materials, not a finished visual benchmark.
- Climate-driven runoff and hydraulic rivers/lakes are available in the trial.
  Vegetation, provinces and legacy paint-layer integration remain separate work.
  Existing world/editor behavior is retained.
- Snapshots are local under `.terrain3d-trials/`, ignored by Git. Each explicit
  root snapshot save creates a new directory. Normal scene saves can update the
  currently referenced native regions; use a new snapshot to preserve a version.
- Native Terrain3D region serialization crashed outside editor mode in local
  Godot 4.7.2 and 4.5.1 checks, including graphics-enabled 4.7.2. The trial guards
  that path and exposes saving only in the Godot editor. Editor-mode save/reload
  is exercised by the native smoke test. Exported-build persistence is unverified.

## Verification

Run generation/editing checks with Godot 4.7.2:

```text
godot --headless --path . --script res://tests/terrain3d_trial_smoke.gd
```

Run editor-mode snapshot/reload checks separately (close other verification
instances first; Windows may lock the addon's temporary library):

```text
godot --headless --editor --path . --script res://tests/terrain3d_trial_smoke.gd
```

Use a graphics renderer rather than `--headless` and append `-- --capture` for a
preview image at `.test-runtime/terrain3d-preview.png`. The test checks seeded
repeatability, changed seeds, named templates, actual native height editing,
editor-mode snapshot/reload and retaining earlier snapshots after regeneration.

Upstream: https://github.com/TokisanGames/Terrain3D/releases/tag/v1.1.0-stable

Archive SHA-256: `51B78BC758F5759CBC8EAAAB14E5CF4E8661717E265FDD760F5ABF945F15B243`.

### Executed checks (Godot 4.7.2, Windows)

- Native generation/editing and OpenGL-rendered capture: zero smoke assertions
  failed. Preview inspected on the GTX 1050 Ti. No performance benchmark claimed.
- Heightmap import: bundled world at 2048 × 1024 visually inspected; float EXR
  precision/orientation, inversion, source selection, missing-file preservation
  and editor snapshot/scene reload checks passed. Runtime controls include the
  image picker; manual operating-system file-picker interaction is unverified.
- Detail diagnosis/material correction: confirmed the bundled source is L8 at
  600 × 293; corrected automatic grass/cliff roles and subdued the cliff tint.
  Runtime native checks and an OpenGL world capture pass after the correction;
  refreshing material settings retains heights and painted control bytes.
  The new 4096-per-axis ceiling has not received a maximum-size performance run.
- Editor-mode native snapshot and full scene/material reload: zero smoke
  assertions failed. Verified in an isolated project copy to avoid locking the
  native library used by the user's open editor.
- Existing main scene: starts successfully.
- Existing `heightmap_focus_smoke.gd`: one failure at its flat-plane picking
  assertion. The same assertion fails in a baseline copy using the original
  project settings and editor script, without Terrain3D installed.
- `git diff --check`: clean. No complete regression suite or manual brush/undo
  interaction coverage is claimed.

The runner also reports certificate-store and shader-cache write diagnostics.
Editor-mode SceneTree tests report editor-settings write failures and shutdown
resource warnings; passing assertions do not establish clean editor shutdown.

### Imported relief and depth correction

Imported maps now have a separate **Imported Relief (×)** control. Changing the
procedural Height Range or Mountain Detail cannot change their imported samples;
those controls are hidden for image sources and omitted from their applied
metadata. A 4096-wide import uses a 20.48-unit vertical span at 1× rather than
the earlier arbitrary 160-unit trial scale. This is an adjustable presentation
choice, not a claim of matching CK3's native dimensions.

The preview camera's near plane scales with orbit distance. The previous fixed
0.05 near plane, combined with a 12000 far plane, caused terrain/sea depth fighting
at whole-map distances. Changing height exaggeration exposed those stripes more
strongly. A GTX 1050 Ti capture after the correction has clean sea occlusion;
six sampled deep-water screen positions render blue water above submerged terrain.
Native checks also verify that imported relief scales around the fixed sea datum,
procedural controls do not affect imports, and editor save/scene reload still pass.

### Mountains, climate and carved inland water

Procedural generation now adds conservative hillslope weathering after the existing
ridge/detail pass. It moves material from steep samples toward adjacent lower
ground, preserving coastal samples. This is a small thermal relaxation pass,
not a complete hydraulic erosion simulation. Imported heightmaps bypass both
procedural detail and weathering. Height Range remains an explicit presentation
choice: 100 units across a 512-wide island is very steep; try 30–50 for a gentler
strategic map before adding more mountain detail.

The seeded climate proxy includes latitude, altitude cooling, warmth, rainfall,
evaporation and upwind mountain rain shadows. It produces runoff for drainage and
an optional regional ground tint on generation. Its latitude span is currently
fixed at 70°N to 50°S. Rainfall is a unitless multiplier; this is not a calibrated
climate model, a biome system, seasonal snow or a closed water-balance simulation.
Changing climate controls and carving again updates drainage; regenerate the
terrain to update its generated ground tint. Carving preserves painted control
and color maps.

**Carve rivers and lakes** reuses the existing priority-flood drainage and hydraulic
surface model. Routing uses at most 513 samples on the longest axis, with channels,
lake beds and bank shaping rasterized into the full-resolution terrain. Water
elevations descend along river profiles and meet lake/confluence levels. Shared
water vertices interpolate elevations; a filtered coverage texture smooths shore
edges. These are raster-derived surfaces, not editable spline rivers or a fluid
simulation. Detail is still limited by routing and terrain sampling resolution.

The pre-carving source is retained, so repeating the operation does not repeatedly
cut the same beds. Zero rainfall removes the generated water and restores that
retained source. If you sculpt native heights after carving, the edited terrain
becomes the next source, including its existing beds. No brush-level undo or merge
of subsequent sculpting into the old source is implemented. Save a snapshot before
destructive generation. Snapshots retain the pre-water EXR, carved native regions,
water mesh and water material/coverage separately; then save the scene as usual.

Generation is currently synchronous. A local 4096 × 2048 imported reference map
produced 233 river reaches and 88 lakes, changing 965,724 ground samples in about
49.7 seconds for the carve operation. This is one observed run, not a cold/warm
benchmark; CPU time and peak memory were not measured. Water geometry is bounded
at two million vertices and rejects oversized results before changing native
terrain. Background processing/cancellation and streamed water meshes are future
work. Private reference-game assets are excluded from Git and project exports.

`tests/terrain3d_landscape_smoke.gd` exercises seeded climate, wet and zero-rain
watersheds, carved beds below water, hydraulic continuity, immutable sources,
weathering conservation, native painting preservation, repeat carving, and
editor snapshot/scene reload including water coverage. Headless and OpenGL runs
passed with zero assertions failed. Existing water-layer and terrain-surface
workflows also passed. Editor tests retain the shutdown diagnostics noted above.
