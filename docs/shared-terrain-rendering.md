# Shared terrain rendering — Step 1

Shaded relief is now the default terrain presentation in both the editor and the
runtime map. The accepted lighting calculation is unchanged: the same height
samples, fixed light direction, ridge contrast and sea-datum treatment drive both.
Trees, climate/biomes, ground paint, provinces, rivers and lakes stay disabled.

## Using it

- Open the project normally to edit the map; it now starts with shaded relief on.
- Press **Play map** to enter the runtime view of the current authored terrain.
  This uses current applied data, including unsaved terrain edits. Staged form
  inputs still require Generate first.
- Press **Return to editor** or Escape to resume editing. Terrain, workspace
  selection and unsaved state are retained. The inactive editor's camera/input
  processing is suspended while playing.
- **Raw height values (editor only)** is a diagnostic display option. Gameplay
  always starts shaded, even if this editor option is checked. PNG exports remain
  raw height data, and terrain/world saves preserve the original float samples.
- Closing while playing returns to the editor's existing unsaved-change safeguard.

`scenes/gameplay_map.tscn` also runs independently, without the editor UI. This is
an entry point for the gameplay map presentation; civilization simulation and
other gameplay systems are not added by this change.

## Implementation

- `scripts/rendering/terrain_map_renderer.gd` owns the map plane, normalized float
  texture and material. It depends only on height data and rendering nodes.
- `scripts/rendering/terrain_map.gdshader` is the single shared shaded-relief
  shader. It replaces the editor-named `heightmap_only.gdshader`, retaining its UID
  and the accepted shading formula. Both shaders/material and terrain defaults
  enable shaded relief.
- `scripts/rendering/heightmap_terrain.gd` delegates focused terrain presentation
  to that renderer. The canonical height samples and generation algorithm are
  unchanged. A `startup_document` can be assigned before adding a terrain scene
  to the tree, so runtime loading restores saved samples directly without first
  generating a different map or applying refinement again.
- `scenes/gameplay_map.tscn` and `scripts/gameplay/world_map.gd` supply the runtime
  camera, environment and small return/exit HUD. There is no editor dependency.
- `scripts/ui/terrain_editor.gd` captures the current terrain document, opens the
  runtime scene, and restores the original editor session on return.

The retained legacy combined biome/LOD pipeline is not reactivated or substituted
for this foundation. Future terrain overlays should build on the shared map
renderer so they retain its canonical height detail and shading.

No terrain save format changes are introduced. No coast-generation changes,
zoom/performance tuning or approved visual benchmark collection are included;
those reviews remain with the user as requested.

## Functional verification

`tests/shared_terrain_rendering_smoke.gd` verifies:

- Shared shader, exact float height texture, seed and sample dimensions.
- Shaded defaults in the editor, runtime and editor-free standalone runtime.
- Actual GPU output parity at identical framing, independent of editor panels.
- Play/return camera and input ownership, retained terrain and unsaved state.
- Raw-editor inspection cannot switch gameplay to an unshaded display.
- Closing the runtime view preserves unsaved-change handling.
- Exports remain unchanged, and other terrain systems stay inactive.

The existing heightmap-focus, world-project and terrain-editor suites cover
backward-compatible loading, exports and editing behavior. Run scripts with
`Godot --headless --path . --script tests/<name>.gd`; run the shared renderer suite
without `--headless` to exercise GPU parity. These are functional checks, not the
manual zoom/performance review or visual benchmark approval.
