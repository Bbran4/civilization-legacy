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
   range, sea level and mountain detail in the Inspector.
4. Click **Generate / replace trial terrain**. This replaces only this workspace's
   terrain, including any unsaved sculpting/painting in it. Save first to retain it.
5. Select the **Terrain3D** child to use the addon's native sculpting and material
   painting tools. Grass and cliff slots are provided. Godot's viewport
   navigation applies while editing; select the sea node and press F to frame it.
6. Select the root and click **Save terrain snapshot**, then **Ctrl+S** to save
   the scene. The scene references the native region directory and stores material
   assets. This is separate from legacy `.terrain.json` / `.world.json` saves.
7. Press **F6** to preview. Wheel zooms, right-drag orbits, middle-drag pans and F
   frames the map. Preview regeneration is temporary; edit and save in Godot.

The existing runtime editor also has a **Terrain3D test** button that opens this
scene in another game window without transferring or replacing the current world.
The separate window has template, seed, dimensions, height-range and sea-level
controls. Native sculpting/painting and persistence are currently editor-only.

## Scope and limits

- Reuses the existing graph, template recipes and height-detail generator; sends
  float32 heights directly to Terrain3D. No 8-bit height export/import round trip.
- Test dimensions are multiples of 256, from 256 to 2048 per axis, at one terrain
  sample per world unit. These are bounded trial settings, not full-world limits.
- Terrain heights are `normalized_height * height_range - sea_level * height_range`.
  The simple sea plane stays at zero. Sea level changes flooding, not drainage.
- Includes the upstream demo's CC0 ambientCG grass/cliff materials with height,
  normal and roughness channels. See `assets/terrain3d/asset_licenses.txt`.
  These are testing materials, not a finished visual benchmark.
- No climate, hydraulic rivers/lakes, vegetation, province or legacy paint-layer
  integration is claimed. Existing world/editor behavior is retained.
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
