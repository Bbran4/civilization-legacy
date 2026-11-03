# Map Editor 2.0 — Phase 1

## Workspace

Run `scenes/main.tscn`. Select Heightmap, Rivers / lakes, Climate, Ground paint,
or Trees in the left stack. The right panel shows that layer's existing controls.
The central area uses the original 3D viewport, camera, picking and renderer.
View settings and Full map are available from the top toolbar.

`V` controls visibility; `L` protects data from editor actions. Selecting another
layer, hiding a layer or changing a lock cancels the active ground brush.
Heightmap is the base world: hiding it hides its dependent scene children too.
Climate visibility suppresses diagnostic overlays; it does not remove climate's
contribution to biome generation. River visibility hides the river/lake meshes;
it does not remove water from the generated simulation. Ground visibility hides
paint coverage without deleting pixels. Existing camera-dependent tree fading
and height/climate display rules still apply.

## Storage and compatibility

1. Save terrain using **Save terrain**. This remains the original version 10
   `.terrain.json` document, with its existing validation and overwrite backup.
2. Use **Save world** to write a distinct `.world.json` sidecar referencing the
   last saved terrain. It records layer visibility, locks and selection. It does
   not save unsaved terrain edits: save terrain again first when needed.
3. **Open world** validates the sidecar and terrain before applying layer state.
   References in the same directory are relative; other references are absolute.
   Move the manifest and terrain together to preserve a relative reference.
4. **Load terrain** still opens legacy terrain directly. It leaves workspace
   layer preferences in place. Loading a terrain/world is an explicit document
   replacement; locks protect editing actions, not document opening.

World manifests have their own format and version, reject duplicate/unknown
layers and invalid flags, limit input size, and back up overwritten manifests.
Writes use a temporary file before replacement. Saving/loading a world does not
write to the referenced terrain. World dimensions, seed, resolution and payloads
remain canonical in that referenced terrain document.

## Extension points

- `scripts/domain/map_layer.gd`: stable layer ID, title, visibility, lock state,
  read dependencies and serializable presentation state.
- `scripts/storage/world_manifest.gd`: default registry and versioned sidecar I/O.
- `scripts/ui/terrain_editor.gd`: layer selection, contextual groups, toolbar,
  visibility adapters and editor mutation guards.
- Renderers retain normal view rules and additionally respect `editor_visible`.
  This flag is presentation-only and is not written into legacy terrain payloads.

The existing generator still computes coupled height/climate/hydrology/biome/tree
outputs. Terrain generation therefore requires every layer unlocked. Climate
regeneration also requires every layer unlocked because it can rebuild dependent
data. Tree and ground operations respect their own lock. This conservative Phase 1
rule prevents automatic regeneration from silently changing protected data.

## Validation

Godot 4.7.2, headless smoke scripts:

- `tests/map_editor_phase1_smoke.gd` — shell contexts, dependency contract,
  locks, brush cancellation, visibility, manifest validation, UI save path,
  relative references, backup, exact terrain restoration and missing references.
- `tests/terrain_editor_smoke.gd` — existing generation, import, persistence,
  validation and camera behavior. Its angled-view checks explicitly enable 3D
  presentation because the current project defaults to flat presentation.
- `tests/terrain_palette_smoke.gd` — palette, paint, undo and save roundtrip.
- `tests/terrain_climate_smoke.gd`, `tests/terrain_biomes_smoke.gd`,
  `tests/terrain_hydrology_smoke.gd`, `tests/terrain_vegetation_smoke.gd`.

Run each with `Godot --headless --path . --script tests/<name>.gd`.
The Phase 1 script also runs with a graphics window and captures
`.godot/editor-phase1.png` to verify the real rendered workspace.

Existing tests now access the contextual Climate panel through the editor;
climate typing selects the Climate context first. The climate inspector assertion
uses the current `Biome at point:` wording. Screenshot paths follow the new
context host rather than assuming the form is directly inside the scroll view.

## Remaining work

- Independent river, forest and province authoring and per-layer payload files.
- Dependency invalidation, stale-layer indicators and explicit rebuild choices.
- Height brushes and multi-layer undo/redo. Ground's existing undo is retained.
- World Save All / packaging, dirty-state prompts and metadata editing.
- Resizable/collapsible panels and smaller-window layouts. Phase 1 uses the
  existing 1280 x 800 workspace target with scrollable contextual properties.
- Compositing controls beyond visibility (opacity, order and blend mode).
