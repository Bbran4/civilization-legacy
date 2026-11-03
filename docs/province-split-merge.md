# Province split and merge tools

## Split a province

1. In Provinces, pick the province to split with the editing tool off.
2. Choose Draw split border in Province tool, then enable Draw split border.
3. Drag a line across the selected province, starting and ending at or beyond its
   boundary. A line preview shows the cut. A closed loop is also supported.
4. Release to apply the split. One side becomes a new province; the other retains
   the original ID/name. The new province is selected and can be renamed with the
   existing Region name field. Escape cancels an unfinished cut.

Only the selected province is modified. Other provinces, coasts, lakes and open
water remain intact. Split one connected island part at a time; other island parts
stay with the original province. A line that misses the province, fails to divide
it, or produces more than two pieces is rejected without changing the world.
Both land provinces and coastal sea regions can be split, retaining their kind.

## Merge provinces

1. With the tool off, pick the province whose ID/name you want to keep.
2. Choose Merge provinces, enable Pick provinces to merge, then click additional
   regions. Click a donor again to remove it. Alt-click changes the kept province.
3. Selected regions are highlighted, and the panel lists their names/IDs.
4. Press Merge selected provinces. The kept ID/name owns the combined pixels;
   donor records are archived without renumbering other IDs.

Select up to 32 regions at once. Land can merge with land; sea with sea. Land
provinces on separate islands may merge. On a single island, the merged shape
must remain connected, so include any connecting provinces. Sea merges must also
remain connected. Lakes, inland water and deep ocean have no selectable IDs and
cannot be merged or filled. Locking/hiding the layer blocks edits and cancels an
unfinished cut/selection. Model replacement rejects obsolete selections.

## Undo, IDs and storage

Undo province edit / Ctrl+Z reverses paint, split or merge operations. Redo /
Ctrl+Y or Ctrl+Shift+Z repeats them. Split Undo restores original pixels and archives
the new ID; Redo reactivates that same ID. Merge Undo restores each donor's exact
ID, name and pixels. New edits after Undo clear Redo and allocate fresh IDs rather
than reusing archived ones. Names edited separately remain preserved.

History remains session-only (50 edits / 64 MiB of pixel deltas). Accepted edits
save exactly; loading/regenerating clears the history. The optional province
section advances to v5, allowing new land IDs after existing sea records. V1-v4
snapshots remain readable; main terrain v10/world manifest v3 stay unchanged.
Ocean regeneration archives replaced sea records and appends new ones instead of
renumbering or removing later land IDs. This preserves provinces created after
sea generation. IDs remain bounded to the existing 65535-record limit.

## Implementation and validation

`world_provinces.gd` rasterizes the drawn line only within the selected connected
part, finds two resulting sides, and assigns cut pixels without creating holes.
Draft indexing verifies connectivity, kind and full coverage. `province_edit_history.gd`
stores changed pixel deltas plus archived/created record activation, sharing one
history with border painting. `province_border_brush.gd` handles tool selection,
line preview, screen-space gestures, selection highlights, commit/cancel, source
checks and keyboard shortcuts. The shared shader supports merge selection tint.
Installed data remains unchanged until an operation validates successfully.

`province_split_merge_smoke.gd` covers open cuts/closed loops, stable IDs/names,
land/sea kinds, exact Undo/Redo, branching IDs, mixed/nonadjacent merge rejection,
new land IDs after ocean records, later ocean regeneration, actual editor gestures,
disk restoration, selection, locks and stale model guards. The 2050-pixel suite
also performs split/Undo/Redo and restores an appended land ID after sea records.
GPU checks inspect real merge selection and tool controls. Manual aesthetics, zoom
and performance review remains with the user.
