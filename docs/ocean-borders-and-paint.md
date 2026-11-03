# Ocean regions and manual border painting

## Generate the oceans

After generating Heightmap, Rivers / lakes, Terrain surface and land Provinces:

1. In Provinces, choose Target ocean regions (1-256).
2. Choose Coastal seas + borderless open ocean, then Generate ocean borders.
   Coastal sea reach limits the light-blue bordered envelope. Deep ocean receives
   no IDs or borders; see [Coastal seas](coastal-seas.md). Sea connected to a map edge is partitioned into
   connected ocean regions, following the exact existing coastline. Explicit lake
   pixels and enclosed inland water remain excluded.
3. Click an ocean region to inspect/name it just like a land province. The optional
   Provinces view in Play map presents the same land and ocean IDs.

Ocean generation preserves existing land IDs, names and painted land borders.
Running it again replaces only ocean IDs/names/borders. Regenerating land provinces
still replaces the entire region layer. The target count is approximate because
separate ocean components can require additional regions. Ocean regions are a
political/map-data overlay, not a modification to elevation or water generation.
Sea colors and borders appear only with Provinces visible; terrain-only relief is
unchanged. Borders maintain readable screen width when the map is zoomed out.

## Paint a border

1. Click the region you want to expand, with painting off.
2. Enable Paint region borders and choose brush radius. Radius is measured in
   pixels at a 1025-pixel reference output and scales with map resolution.
3. Drag the left mouse button over a neighboring region to transfer pixels to the
   selected region. Alt-click picks a different target while painting is enabled.
4. Release to validate/apply one complete stroke. Escape cancels an unfinished
   stroke. A circle previews the footprint; fast mouse motion paints a continuous
   capsule between samples rather than leaving gaps.
5. Undo border stroke / Ctrl+Z reverses a stroke. Redo / Ctrl+Y or Ctrl+Shift+Z
   restores it. Shortcuts apply in the Provinces context, leaving text-field undo
   and the legacy ground brush alone.

Land can repaint only land regions, ocean only ocean regions. Lakes, inland water,
coastlines and all source height/water fields remain unchanged. Strokes must leave
land regions connected within each physical island and ocean regions connected.
Separate islands can share one land ID. Attach whole separate islands (on by
default) transfers a touched separate landmass to the selected province. A fully
painted-over land province is archived, with Undo restoring its ID/name. Invalid
same-island splits or ocean disconnections reject the whole stroke. Dedicated
split/merge commands remain future tools. See [Island attachment](islands-and-maritime.md). Region IDs and
names remain stable during painting; areas and neighbors update after each edit.

Draft strokes are separate from the installed world. Saving or inspecting the
installed document cannot accidentally capture an invalid partial stroke. Loading
another model, hiding/locking the layer or switching context cancels an unfinished
stroke. Mouse release outside the map still finishes the stroke; moving over UI
breaks the interpolation path. Lock/visibility/source checks also protect Undo/Redo.

Undo holds at most 50 committed strokes, bounded to 64 MiB of pixel deltas across
Undo and Redo. Starting another stroke after Undo clears Redo. History is session-
only and clears on model replacement/loading/regeneration; it is not stored in
world saves. Accepted painted borders themselves save exactly, including region
names and recomputed adjacency. Renaming does not overwrite border history.

## Implementation and compatibility

- `world_provinces.gd`: typed land/ocean records, boundary-connected ocean flood,
  deterministic coastal/offshore sea partition, kind-safe capsule edits, exact v4 region snapshots,
  complete typed coverage and connected-region validation. V1 land-only and v2 land/ocean province
  snapshots still load. V3 archived IDs remain supported; V4 adds coastal reach
  and the borderless open-ocean background mask. Main terrain v10/world manifest v3 stay unchanged.
- `province_edit_history.gd`: separate editable drafts, atomic connectedness checks,
  bounded pixel deltas, exact Undo/Redo and preservation of separately edited names.
- `province_border_brush.gd`: picking, projected cursor, gestures/shortcuts, target
  selection and commit/cancel routing. The installed raster is not mutated until
  validation succeeds. Validation/indexing occurs on stroke release.
- `terrain_editor.gd`: ocean count/generation worker, stable-source/session install
  checks, painting controls and independent region visibility. Ocean generation
  runs in the existing guarded province worker and joins safely on shutdown.
- `terrain_map.gdshader`: separate ocean color/border treatment and screen-width
  border sampling. Water still draws above land political colors.

Loading recomputes region areas and symmetric adjacency from IDs. Neighbor lists
now include shared land/ocean coast edges; kinds distinguish them. Adjacency alone
is not a movement/crossing rule. Current source-matched documents must assign land
only to land IDs and boundary-connected sea only to ocean IDs when ocean generation
is enabled; lakes/inland water stay unassigned. Old/stale caches are retained but
cannot activate against different source maps.

`ocean_border_paint_smoke.gd` covers deterministic ocean IDs, preserved land data,
lake/inland exclusion, v1 compatibility, mixed-region round trips, draft isolation,
continuous painting, exact Undo/Redo, rejection of invalid same-island/ocean disconnections,
cross-kind protection, screen-to-map gestures, document replacement, locks,
background-job replacement/shutdown and real graphics/gameplay output. The maximum
resolution test also generates/restores oceans at 2050 square. Manual visual/zoom
and performance approval remains with the user.
