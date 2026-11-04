# Civilization Legacy

Godot world generation with layered map authoring.

## World layers

- **Heightmap** — seeded terrain, templates, imported heightmaps and grayscale export.
- **Ground paint** — an independent color layer over terrain shading.
- **Rivers / lakes** — generated drainage and hydraulic elevations.
- **Terrain surface** — the combined heightmap and hydraulic beds/banks.
- **Provinces** — land/maritime regions, borders and nation assignments.

Ground paint is composited after heightmap/combined-surface shading and before
rivers, lakes, province colors and borders. Relief shading remains visible through
paint. Raw height inspection still shows the original grayscale data. Paint is
restricted visually to land; it cannot cover water or province overlays.

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

The available local test engine is Godot 4.5.1 Mono. The project retains its existing
4.7 configuration; exact 4.7 behavior has not been verified. Historical reference
and design documents may describe retired systems. See `docs/world-painter-review.md`
for the current implementation review.
