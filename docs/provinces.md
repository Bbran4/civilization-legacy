# Province foundation

## Using it

Generate Heightmap, then Rivers / lakes, then Build terrain surface. Select
Provinces, choose a target of 1-512 mainland provinces and Generate provinces.
Generation is deterministic for the same source field and target count. Isolated
islands without a sampled seed gain their own province, so the actual count can
exceed the target. Oceans initially have ID 0; optional ocean generation adds separate typed regions.
Lakes and enclosed inland water stay unassigned. See
[Ocean borders and painting](ocean-borders-and-paint.md).

Click the map to inspect a province ID, name, pixel area and number of neighbors.
The selected province is highlighted. Enter a name and Apply province name. Hide
Provinces to return to plain shaded relief. Province visibility is independent of
water and terrain. Play map starts with terrain; its Provinces switch shows the
same saved political regions over the same ground and water.

The province lock protects names, direct regeneration and upstream height, water
and surface edits through the editor. Source changes retain old province data but
mark it stale and hide it. Generating again replaces IDs and names; this is an
explicit rebuild rather than an automatic operation. Manual border painting with per-stroke Undo/Redo is available. Drawn-border split and multi-region merge tools are now available with Undo/Redo;
see [Province split/merge](province-split-merge.md). Civilization ownership and dated scenarios are separate
future systems, not province identity.

## Generation and storage

`scripts/domain/world_provinces.gd` is separate from the retained legacy
terrain-cell preview. It reads canonical land elevations, the finished surface
and independent water mask at full output resolution, up to 2050 pixels. Sampled
seeds spread using a deterministic best-candidate strategy. Multi-source weighted
region growth favors gentle routes and penalizes river crossings. Shared-edge
land connectivity is mandatory within each physical island. Initial generation
assigns islands separate identities; manual attachment can group them under a
mainland ID. See [Island attachment and maritime regions](islands-and-maritime.md).
Rivers remain land pixels in this initial model; lakes and seas stay unassigned.
Rivers influence borders but are not mandatory borders or ownerless major-river
water provinces yet. Mountain passes, crossings and gameplay movement remain later
work. This is a useful first partition, not a complete historical border generator.

A full-resolution integer ID raster and records are stored in an optional
`province_layer` section of existing terrain v10 documents. IDs are exact integers
in bounded lossless float32 compression (maximum ID 65535). Names are stored;
pixel counts and symmetric adjacency are recomputed from the authoritative raster
when loading. Invalid IDs, dimensions, names and disconnected identities are
rejected before modifying live data. Current source-matched coverage must assign
all land and exclude lakes and sea. No regeneration occurs during load.

Surface fingerprints include base/water identity and the exact finished field.
Only a matching current surface activates provinces. World manifest v3 adds the
seventh layer; v1 and v2 migrate in memory, preserving flags and leaving old files
untouched. Existing snapshot-first world saving remains unchanged.

Generation runs on a worker using immutable input references/copies. Installation
rechecks source identity, document session and layer state; shutdown joins workers.
The map shader adds stable province tints and shared-edge borders with water
on top, using nearest-sampled IDs so colors cannot create false identities.
Original shaded relief and raw base inspection remain available.

## Verification and next work

`world_provinces_smoke.gd` checks source preservation, determinism, connected
regions, complete land coverage, lake/sea exclusion, symmetric adjacency, names,
exact disk round trips, invalid imports, v2 migration, source locks, visibility,
gameplay parity/toggle, stale data, pending-job replacement and worker shutdown.
It runs headless and with actual graphics. The maximum-resolution water test now
builds and restores all four layers at 2050 square. Editor/world/heightmap/surface/
water and shared-renderer suites provide regression coverage.

Next: deeper province inspection/labels and water
crossing relationships, province selection/inspection in gameplay, and optional
political labels. Biomes, painting and trees remain separate later layers. Manual
visual/zoom/performance review remains with the user.

Province snapshots now use version 5 for appended split IDs after sea records,
retaining the finite coastal sea band and deep-ocean
background, retaining archived IDs and land/ocean kinds. V1-v4 maps remain readable.
See [Coastal seas](coastal-seas.md). Accepted painted borders preserve IDs/names and
save exactly. Ocean generation preserves authored land borders.

[Impassable land](impassable-land.md) can now be erased out of province coverage
and painted back with Undo/Redo. Province v6 stores that separate mask and authored
part policy while reading v1-v5. Current land coverage can be assigned or explicitly
marked impassable; water remains protected.
