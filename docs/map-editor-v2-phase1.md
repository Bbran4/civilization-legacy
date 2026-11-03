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

1. **Save world** saves the current terrain and layer state together. On a new
   world it asks for a `.world.json` location; subsequent saves reuse that location.
   **Save as** saves the current world in another location.
2. Each world save writes a fresh, uniquely named `.terrain.json` snapshot beside
   the manifest, then replaces the manifest with a relative reference to that
   snapshot. No previous terrain or world snapshot is overwritten. The manifest's
   `.bak` continues to reference its own original snapshot.
3. **Open world** validates the sidecar and terrain before applying layer state.
   Move the manifest and its referenced terrain snapshot together. Legacy Phase 1
   sidecars and their relative or absolute references still open normally.
4. **Save terrain** and **Load terrain** retain the original terrain-only workflow,
   version 10 format, validation and overwrite backups. Importing a legacy terrain
   creates an unsaved world; saving that world writes a separate snapshot, leaving
   the imported file unchanged.

The viewport status distinguishes Saved from Unsaved changes. Applied generation,
climate, tree, paint/undo/clear and palette edits mark the world dirty, as do layer
visibility, locks and selection. Selecting a file to open, or closing the editor,
with unsaved changes offers Save world, Discard changes and Cancel. Save and
continue runs the pending action only after a successful world save. A failed save
or cancelled save chooser keeps edits and cancels the pending replacement/close.
Direct load methods are programmatic operations; the interactive entry points
provide these prompts. Pending generator/climate inputs still require Generate
or Apply: world saves capture the actual map rather than unapplied form values.

World manifests have their own format and version, reject duplicate/unknown
layers and invalid flags, limit input size, and back up overwritten manifests.
Temporary writes check write errors before replacement. If manifest publication
fails, the just-created snapshot is removed and prior files remain valid. Older
snapshots are intentionally retained; automatic retention/cleanup is future work.
World dimensions, seed, resolution and payloads remain canonical in the referenced
terrain document. External asset packaging is not added in this phase.

## Extension points

- `scripts/domain/map_layer.gd`: stable layer ID, title, visibility, lock state,
  read dependencies and serializable presentation state.
- `scripts/domain/map_layer_graph.gd`: transitive impact traversal and affected-lock checks.
- `scripts/storage/world_manifest.gd`: default registry and versioned sidecar I/O.
- `scripts/storage/world_project.gd`: snapshot-first world save publication.
- `scripts/ui/terrain_editor.gd`: layer selection, contextual groups, toolbar,
  visibility adapters and editor mutation guards.
- Renderers retain normal view rules and additionally respect `editor_visible`.
  This flag is presentation-only and is not written into legacy terrain payloads.

The existing generator still computes coupled height/climate/hydrology/biome/tree
outputs. The stack now shows which layers an operation affects. Regeneration
checks the source and all transitive dependents, and names any locked blockers.
Heightmap generation affects all five layers. Climate regeneration affects
Climate, Rivers/lakes and Trees, so a height or ground lock does not block it.
Trees also read river data. Tree and ground operations affect only their own layer.
The dependency traversal terminates even if a future extension introduces a cycle.
This is an impact/lock foundation; per-layer stale revisions and selective rebuild
execution remain future work. Existing generation still eagerly rebuilds its
coupled outputs, and height regeneration still clears unlocked ground paint.

## Validation

Godot 4.7.2, headless smoke scripts:

- `tests/world_project_smoke.gd` — Save All/Save As, immutable payloads, valid
  backups, current paint/climate capture, late save failure cleanup, dependency
  locks, dirty tracking and save/discard/cancel behavior.
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
The Phase 1 and world workflow scripts also run with a graphics window and
capture `.godot/editor-phase1.png` and `.godot/editor-world-workflow.png` for
verification of the real rendered workspace.

Existing tests now access the contextual Climate panel through the editor;
climate typing selects the Climate context first. The climate inspector assertion
uses the current `Biome at point:` wording. Screenshot paths follow the new
context host rather than assuming the form is directly inside the scroll view.

## Remaining work

- Independent river, forest and province authoring and per-layer payload files.
- Dependency invalidation, stale-layer indicators and explicit rebuild choices.
- Height brushes and multi-layer undo/redo. Ground's existing undo is retained.
- Snapshot retention/cleanup, external asset packaging and metadata editing.
- Resizable/collapsible panels and smaller-window layouts. Phase 1 uses the
  existing 1280 x 800 workspace target with scrollable contextual properties.
- Compositing controls beyond visibility (opacity, order and blend mode).
