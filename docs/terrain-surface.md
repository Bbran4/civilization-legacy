# Terrain surface: third build step

## Workflow

1. Generate Heightmap using the existing templates and 256-2050 pixel output.
2. Generate Rivers / lakes. You can keep the base heightmap locked.
3. Select Terrain surface, adjust riverbed depth, lake bed depth and bank width,
   then press Build terrain surface. Source layers may be locked while building.
4. Compare using layer visibility. Hiding Terrain surface reveals the base ground;
   water visibility remains separate. Raw-height inspection always shows the base.
5. Play map uses the exact current derived field and independent water overlay.
   A map with water requires a current terrain surface before entering Play map.
6. Save world/terrain normally. Export surface PNG writes the derived grayscale
   elevations; the original heightmap export continues to write the base terrain.

Depths use normalized 0-1 elevation units. Bank width uses pixels at a 1025-pixel
reference resolution and scales with output size. Values are staged until Build.
The bank corridor can lower high ground and raise local depressions to contain
water; river and lake pixels receive submerged beds. Distant terrain is untouched.

## Data and rendering

- `terrain_water_layer.gd` retains the water mask plus normalized surface levels,
  river centerline profiles (x, y, width, level), flow, destination IDs, lake levels,
  seeds and outlet references. IDs/names remain independent of the ground cache.
- Profiles must flow downhill, connect at matching junction elevations/positions,
  and form an acyclic feature network including lake outlets. Flat shore channels
  that leave and re-enter a lake are marked internal, not counted as net outlets. Invalid imported
  hydraulic records are rejected before changing the live terrain.
- `terrain_surface.gd` reads immutable normalized base heights and current water.
  It carves submerged beds and conditions a bounded shore corridor. A two-pass
  distance sweep blends banks back into the original terrain. The result is a
  separate normalized float32 field, with settings and both source fingerprints.
- `float_payload.gd` stores fields and profiles losslessly using bounded compressed
  float32 payloads. Visible PNG exports are 8-bit images; saved caches retain float
  precision. Source hashes make stale outputs unavailable without deleting them.
- The shared editor/gameplay renderer binds the derived field for shaded relief
  while retaining its canonical base field for future water generation. Logical
  surface-height queries also use current derived ground, independent of visibility.
  Overview uses a flat plane; zoom blends into a displaced relief grid. The
  display-height cache and fine shading are described in [display-height caching](display-height-cache.md).

## Safety and compatibility

Current terrain documents are v15; world manifests are v6. Historically, terrain
document version 10 introduced the optional terrain_surface cache and optional
water version 2 records. Documents without either field still load. Old water
version 1 masks remain viewable/exportable and are never silently regenerated;
Build asks for water regeneration to supply elevation/profile records.

World manifest version 2 originally added the surface layer. Version 1 manifests are validated
against their original five layers, then upgraded in memory without rewriting
files or changing their saved visibility/lock states. Save world still writes a
new unique terrain snapshot before publishing the manifest, preserving old saves.

Locking Terrain surface blocks changes to either upstream source through the
editor. Source changes retain but hide old surface data. Build runs on a worker;
installation rechecks source identity, document session and layer permissions.
Closing waits for workers to finish. Save/load restores fields without rerunning
generators. Invalid numeric dimensions/payloads and exposed cached water beds are
rejected before applying a document.

## Validation and limits

`terrain_surface_smoke.gd` covers immutable sources, deterministic conditioning,
submerged beds and containing shores, independent feature names, hydraulic JSON
round trips, corrupt/uphill data rejection, legacy manifest migration, worker
session changes/shutdown, exact save/load, layer visibility, dependency locks and
shared gameplay output. It also captures real GPU views when run without headless.
`terrain_water_resolution_smoke.gd` builds and restores all three fields at 2050
pixels. Existing editor, world, heightmap, water and shared-rendering tests remain
part of regression validation. `terrain_surface_templates_smoke.gd` checks the
water records and ground build for all 14 procedural templates at 256 pixels.

This is controlled terrain conditioning around generated drainage, not a complete
hydraulic erosion or sediment simulation. It does not reroute water after carving.
Profile/junction validation concerns the water surface; it does not assert every
bed pixel follows a strictly decreasing path. Existing natural depressions can
remain below the carved channel. Water names/flow/IDs are a data foundation, not a
naming UI, crossings/combat implementation or province integration. Manual visual,
zoom and performance approval remains separate. Next: review bank/depth settings
on approved templates, then use this final ground and water data for provinces.

## Province follow-on

The optional [Provinces layer](provinces.md) now reads this finished field. World
manifest v3 adds its state and reads both v1 and v2 worlds without rewriting them.
Province generation, inspection/naming and neighbor records are implemented;
manual border editing, crossings/combat and ownership/scenarios remain future work.
