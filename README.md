# Civilization Legacy

Godot world generation with layered map authoring.

## Terrain3D trial

Terrain3D 1.1.0 is installed as an optional terrain workspace. Open
`scenes/terrain3d_trial.tscn` to generate seeded templates and use the native
sculpting/material tools, or choose **Terrain3D test** in the existing editor for
a separate runtime preview. See [setup and editing instructions](docs/TERRAIN3D_TRIAL.md).

## World layers

- **Heightmap** — seeded terrain, templates, imported heightmaps and grayscale export.
- **Ground paint** — automatic terrain textures with an independent manual color overlay.
- **Rivers / lakes** — generated drainage and hydraulic elevations.
- **Terrain surface** — the combined heightmap and hydraulic beds/banks.
- **Provinces** — land, enclosed inland-water and maritime regions, borders and nation assignments.
- **Trees** — seven regional tree species, kept separate from world geography.

Ground paint is composited after heightmap/combined-surface shading and before
rivers, lakes, province colors and borders. Relief shading remains visible through
paint. Raw height inspection still shows the original grayscale data. Paint is
restricted visually to land; it cannot cover water or province overlays.

Enclosed terrain basins at or below the sea datum receive one province per
connected water body when provinces are generated. Generated hydraulic lakes
remain separate. For an existing map, **Generate ocean borders** also fills missing
inland-water provinces while preserving existing land and inland-water IDs.
A full province rebuild replaces IDs and authored names, as before.

## Automatic terrain textures

New worlds automatically generate seamless grass, soil, sand, rock and snow
materials from the world seed. Placement follows terrain slope and elevation,
shorelines and nearby water. These are visual rules, not a climate simulation.

For an existing save, select **Ground paint → Generate textures**. Earlier saves
keep their original appearance until you enable generation. Adjust texture scale,
grass amount, rock slope or snow height, then generate again. **New texture
variation** chooses a new reproducible variation without touching geography or
manual paint. Choose **Borders only** in Provinces to inspect the full terrain
appearance without political-color fills.

Ocean provinces preserve the original water colors in **Borders only** mode.
With fills enabled, only assigned sea provinces receive a tint; unassigned water
always keeps its original depth colors. Large enclosed sea-level basins also
support ocean provinces. For older worlds flooded as a lake, regenerate rivers/
lakes, terrain surface and provinces, then generate ocean borders.

Textures sit beneath manual paint, water and province overlays, work in both the
flat overview and 3D relief, and save with the world. Ground paint visibility and
locking apply to generated textures too. Raw-height view and height exports remain
grayscale. Erasing manual paint reveals the generated textures below it.

Only five small material tiles are generated; their mipmaps filter distant detail.
Zooming and panning reuse the cached tiles. Source terrain changes automatically
update placement, without baking or storing a world-sized texture image.

## Regional controls

Open **Ground paint → Regional controls…**. Choose warmth or moisture coverage to
preview the climate field. Whole-map controls adjust warmth/moisture by up to 50
percentage points; variation changes the generated pattern.

For a local change, enable **Brush a selection on the map**, left-drag an area,
set its adjustments/variation, then **Regenerate selected area**. Yellow shows the
selection with a soft edge. **Reset selected to generated** removes local edits;
**Undo regional change** or Ctrl+Z restores up to 16 changes. Whole-map offsets
also apply to edited regions; whole-map variation preserves their local overrides.

Ground appearance and forests update while geography stays unchanged. Trees
outside the edited field's filtering footprint retain their placement and species.
Regional edits save with the world and work in Play map. Ground paint visibility
and lock protect regional editing. Previews and the current selection are temporary.

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
painter and its preview renderer have been removed. Manual texture brushes and climate-based biomes are not included. Trees have their own layer below.

## Trees

New worlds automatically plant clustered regional trees. For an
existing world, select **Trees → Generate trees**. Adjust the tree budget, forest
coverage, size, slope limit and tree line, then generate again. **New forest
variation** changes the placement reproducibly. Settings save with the world.

Oak, birch, spruce, stone pine, olive, acacia and palm have distinct silhouettes,
bark and foliage colors. Each instance varies in size, crown width, height, lean
and rotation. Cool wet regions favor spruce/birch, mild wet regions oak, mild dry
regions olive/stone pine, hot dry regions acacia and hot wet regions palms. These
are stylized regional mixes. The Trees panel shows actual species counts;
**Adjust regional mix…** opens warmth/moisture controls.

Trees avoid sea, rivers, lakes, steep slopes and high ground. Their eligibility also
respects enabled terrain-texture snow/rock thresholds. The budget is an upper
bound: available ground and spacing can leave fewer trees. Tree lock protects
settings; world regeneration still updates placement so forests follow geography.
Manual ground-color strokes do not remove or regenerate trees.

Seeded regional warmth and moisture now guide both ground appearance and forests.
Dry warm areas show more exposed soil and muted grass; moist regions favor greener
ground and denser forests. Colder regions favor conifers and lower snowlines.
The field follows map latitude and elevation; it does not change world geography.
It is derived from the world seed, so changing texture variation keeps the regions
in place. Existing saves regenerate this appearance automatically.

The layer eye hides trees and forest shading. Raw height inspection hides them
automatically. The overview shows forest shading; individual trees fade in as you
zoom closer. Roots follow the same displayed terrain mesh through zoom. Zoom/pan
reuses existing placements and coverage. The current models are original,
procedurally built low-poly trees with slight wind sway; there are no external
model dependencies. There is no manual tree-planting/erasing brush yet.

## Terrain display preparation

Display heights are cached at source resolution as float32 world heights. Large
updates prepare the combined ground/water display in a worker; the editor remains
responsive and shows **Updating terrain view…** until the result is ready. Picking
pauses during replacement and resumes against the actual displayed triangles.
Fine world-scaled normals remain visible at full relief. Zoom reuses prepared
fields. Large sources now use camera-dependent patches, reaching approximately 2048 cells
along a 2050-pixel source near the camera. Smooth detail transitions share the same
surface with picking, borders and tree roots. See [chunked terrain](docs/chunked-terrain.md).
Rivers and lakes with saved hydraulic levels use a separate translucent surface.
Close views show depth-dependent color, subtle ripples and pale bank edges over
the conditioned bed. The Rivers / lakes eye reveals the bed. Older mask-only water
uses the original overlay until hydraulic levels are generated.

## Lighting and atmosphere

Terrain and trees share warm sunlight and cool sky fill in the editor and gameplay.
Mountains and individual trees cast real sun shadows over the displayed terrain.
Valleys also receive subtle local shading. Shadows fade in with 3D relief; the
flat overview skips shadow rendering. Province visibility never changes shadow strength.
Oblique views gain a light distance haze; the top-down overview stays clear.
Water uses a calmer palette with a depth gradient for open sea. Province fills
and border lines retain their readability, and raw-height inspection stays neutral.
These effects use the map shaders and a filtered directional shadow map, without
volumetric fog. Zoom in to see cast shadows; the full-map overview remains flat.

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
mesh implementation, without tiled distance LOD. Lighting combines shared relief
shading with directional cast shadows in the raised 3D view.

## Storage

Terrain document version 15 adds saved `regional_controls`, with global choices
and a bounded local override map. Older saves use the original generated regions.
Version 14 adds `tree_settings`; older saves keep trees disabled
until generation is requested. Version 13 introduced `texture_settings`; missing settings in older
saves default to disabled. Version 12 introduced `map_paint`. Earlier saves load with a
transparent paint layer. World manifest version 6 adds Trees; version 5 introduced the independent paint
layer. Earlier manifests gain these in memory without rewriting the original file.
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

The project targets Godot 4.7. This terrain-display update is verified with Godot
4.7.2 / OpenGL Compatibility on Intel UHD 730. Older feature documents record their
original Godot 4.5.1 test environment; those records are historical, not the current
engine requirement. See [display-height caching and fine normals](docs/display-height-cache.md)
for the current renderer and measured limits. Historical pipeline references are
marked as archived.
