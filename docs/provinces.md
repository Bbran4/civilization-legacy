# Province foundation

## Using it

Generate Heightmap, then Rivers / lakes, then Build terrain surface. Select
Provinces, choose a target of 1-512 mainland provinces and Generate provinces.
Generation is deterministic for the same source field and target count. Isolated
islands without a sampled seed gain their own province, so the actual count can
exceed the target. Oceans and lakes have ID 0 and are not owned by land provinces.

Click the map to inspect a province ID, name, pixel area and number of neighbors.
The selected province is highlighted. Enter a name and Apply province name. Hide
Provinces to return to plain shaded relief. Province visibility is independent of
water and terrain. Play map starts with terrain; its Provinces switch shows the
same saved political regions over the same ground and water.

The province lock protects names, direct regeneration and upstream height, water
and surface edits through the editor. Source changes retain old province data but
mark it stale and hide it. Generating again replaces IDs and names; this is an
explicit rebuild rather than an automatic operation. Manual brush/split/merge is
not implemented yet. Civilization ownership and dated scenarios are separate
future systems, not province identity.

## Generation and storage

`scripts/domain/world_provinces.gd` is separate from the retained legacy
terrain-cell preview. It reads canonical land elevations, the finished surface
and independent water mask at full output resolution, up to 2050 pixels. Sampled
seeds spread using a deterministic best-candidate strategy. Multi-source weighted
region growth favors gentle routes and penalizes river crossings. Shared-edge
land connectivity is mandatory; disconnected islands get separate identities.
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
The new map shader adds stable province tints and shared-edge borders with water
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

Next: manual border paint with undo, split/merge and stable-ID editing, water
crossing relationships, province selection/inspection in gameplay, and optional
political labels. Biomes, painting and trees remain separate later layers. Manual
visual/zoom/performance review remains with the user.
