# Province appearance and smooth borders

Select **Provinces > Province view > Borders only — no province fill** to keep
terrain relief and boundaries without random land colors. Play map has the same
choice beside its Provinces switch. Coastal water colors and dark impassable land
remain visible. Selected provinces still highlight while editing.

## National borders

Use **Create nation color**, enter a name and choose a color. Select a land
province, choose its nation and press **Assign nation to selected province**.
Unassigned removes the assignment. The province layer lock protects these edits.
Nation assignments save with the world; they are authoring groups, not a campaign
ownership or diplomacy system.

- Boundaries inside one nation use dark dotted lines.
- Different nations have a dark shared center and a fading color band on each
  nation's own side. A neutral neighbor has no colored band.
- Coastal national borders have the nation's band on the land side.
- Sea-region boundaries remain thin solid lines; deep ocean remains borderless.
- New maps have no invented nations. Unassigned land provinces use dotted lines.

Splits inherit their source nation's assignment. Merges retain the kept province's
nation. Border Undo/Redo preserves current nation metadata. Nation assignment and
creation mark the world dirty but are not themselves brush Undo/Redo actions.
Palette editing/removal and bulk assignment remain future work.

## Rendering and compatibility

`province_border_paths.gd` traces each shared raster boundary once, preserves side
orientation and junction endpoints, simplifies at 1.1 native pixels, and applies
two smoothing passes. `province_border_renderer.gd` batches ribbons by style and
nation pair. The ribbon shader extrudes in screen pixels and antialiases edges;
province dashes retain world spacing. Geometry is cached. Nation changes reuse
paths and rebuild styles. Brush drafts use immediate raster feedback, then rebuild
smooth paths on commit. Editor and Play map share the renderer. Raw heightmap view
hides overlays.

Only display geometry is smoothed. Authoritative IDs, neighbors, picking, height
samples, river/lake data and impassable masks remain unchanged. Extreme zoom can
reveal a small difference between the visual curve and raster picking edge. This
is a first rendering pass inspired by the reference, not Imperator's renderer.

Province section v7 adds a bounded nation palette and per-land-province nation ID.
Versions 1–6 load without invented nations or changed pixels. Terrain document v10
and world manifest v3 remain unchanged. Existing files update only on explicit save.
Invalid colors and nation references reject before install.

## Verification

`province_border_only_smoke.gd` checks the appearance control.
`smooth_province_borders_smoke.gd` checks old/new save data, invalid ownership,
shared paths, 2050-pixel tracing, split inheritance, Undo, caching, preview fallback,
and actual GPU border colors on the correct sides. Existing province, split/merge,
impassable, island and world-save suites exercise underlying behavior. Manual
visual and zoom review remains useful for choosing final widths and dash spacing.
