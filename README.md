# Civilization Legacy

Godot world generation with layered map authoring.

## World layers

- **Heightmap** — seeded terrain, templates, imported heightmaps and grayscale export.
- **Ground paint** — an independent color layer over terrain shading.
- **Rivers / lakes** — generated drainage and hydraulic elevations.
- **Terrain surface** — the combined heightmap and hydraulic beds/banks.
- **Provinces** — land, enclosed inland-water and maritime regions, borders and nation assignments.

Ground paint is composited after heightmap/combined-surface shading and before
rivers, lakes, province colors and borders. Relief shading remains visible through
paint. Raw height inspection still shows the original grayscale data. Paint is
restricted visually to land; it cannot cover water or province overlays.

Enclosed terrain basins at or below the sea datum receive one province per
connected water body when provinces are generated. Generated hydraulic lakes
remain separate. For an existing map, **Generate ocean borders** also fills missing
inland-water provinces while preserving existing land and inland-water IDs.
A full province rebuild replaces IDs and authored names, as before.

## Painting

Run the main scene, select **Ground paint**, and enable the ground brush. Choose
a color and radius, then left-drag on the map. Enable **Erase paint** to reveal the
underlying terrain. Ctrl+Z or **Undo ground stroke** undoes up to sixteen strokes;
**Clear ground paint** is also undoable. The layer visibility and lock controls
work the same way as the other world layers.

Painting never changes heights, drainage, hydraulic surfaces or province IDs.
Rebuilding those layers preserves the paint. Paint follows normalized map
coordinates if the map dimensions change. The paint canvas is 1024×1024.

**Save terrain…** and **Save world…** include paint. Opening a world restores the
paint and its visibility/lock state. Gameplay uses the same renderer and saved
paint. Saves retain backups; world saves reference uniquely named terrain snapshots.

There is no separate painter window or appearance file. The earlier standalone
painter and its preview renderer have been removed. Texture brushes, biome
simulation and tree placement are not part of this initial ground-color layer.

## Zoom-based 3D terrain

The full map starts flat and top-down. Zooming from 1× to 3× smoothly tilts the
camera and raises the terrain; beyond 3× the terrain uses full relief. Right-drag
to rotate/tilt, middle-drag or WASD to move, and press F to return to the flat
full-map overview. Raw height inspection stays flat at every zoom.

Paint, rivers/lakes and provinces use the same map coordinates throughout.
Visible water is raised to saved hydraulic elevations. Ground painting, province
editing and inspection pick the displayed surface. Borders and brush/split
previews follow its triangles. Existing saves work without regeneration.

The overview uses a simple plane; close views reuse a prepared relief grid capped
at 513 samples per longest axis. Full-resolution source heights remain unchanged.
Fine features smaller than the display grid can be softened; this is a bounded
mesh implementation, without tiled distance LOD. Lighting retains the shared
shader's directional relief shading; dynamic cast shadows are not implemented.

## Storage

Terrain document version 12 includes `map_paint`. Earlier saves load with a
transparent paint layer. World manifest version 5 includes the independent paint
layer; earlier manifests gain it in memory without rewriting the original file.
Retired legacy climate/tree/texture-palette metadata is ignored.

## Verification

```text
godot --headless --path . --log-file .map-paint.log --script res://tests/map_paint_smoke.gd
```

This integration check generates height, water, hydraulic surface and provinces,
paints through the editor brush, verifies generation data stays unchanged, checks
undo/lock/visibility, saves and reloads terrain/world JSON, and rejects malformed
paint. Add `-- --capture` without `--headless` to capture a rendered preview under
`.test-runtime/`.

`zoom_relief_smoke.gd` additionally checks zoom transitions, displayed-surface
picking, tilted painting, raw-view restoration, hydraulic elevations, and exact
triangle splits for draped lines.

The available local test engine is Godot 4.5.1 Mono. The project retains its existing
4.7 configuration; exact 4.7 behavior has not been verified. Historical reference
and design documents may describe retired systems. See `docs/world-painter-review.md`
for the current implementation review.
