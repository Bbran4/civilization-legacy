# Coastal seas and borderless open ocean

The default ocean presentation follows the supplied visual reference: light-blue
bordered sea zones near land, with one continuous dark-blue open ocean beyond them.
Open ocean has no province IDs or internal borders. Lakes and enclosed inland
water remain unassigned and are excluded from the open-ocean background mask.

## Using it

After the existing height/water/surface/land workflow, select Provinces, choose
Coastal seas + borderless open ocean and press Generate ocean borders. Coastal sea
reach controls how far the bordered band extends from shore, in reference pixels
at a 1025-pixel output. Default reach is 64; supported range is 8-256, scaling with
output resolution. Target ocean regions controls subdivisions inside that band.

Opening older maps does not discard saved sea IDs or painted land/island edits.
Generate ocean borders explicitly applies the new layout and replaces old sea
zones while preserving land IDs, archived island records and names. Legacy
full-ocean zones remain available as an alternate mode. Source terrain and water
heights never change.

The political view in the editor and Play map shares the same coastal IDs and
background mask. Terrain-only/raw inspection retains its existing behavior.
Coastal zones can be named and painted with Undo/Redo as before; painting cannot
extend into the unassigned deep ocean. Reach changes the outer coastal envelope.

## Data and rendering

`world_provinces.gd` classifies map-edge-connected sea, excluding lake pixels and
inland water. An eight-neighbor chamfer distance envelope identifies near-shore
sea, then the existing connected region growth partitions only this finite band.
Coastal seeds follow the shoreline; distant sea never receives an ID. A coastless
sea map remains continuous dark-blue open ocean with no generated coastal zones.

A separate binary sea-background mask distinguishes unassigned deep ocean from
unassigned lakes/inland water. The optional province section advances to v4,
storing this mask losslessly and preserving coastal reach. V1-v3 snapshots remain
readable; main terrain v10 and world manifest v3 are unchanged. Draft copies own
their mask data so regeneration cannot mutate the installed map in flight.

Current coverage validation recomputes the band and checks that all eligible
coastal pixels have ocean IDs, deep pixels have none, and the sea mask excludes
land/lakes/inland water. IDs, archived records, island parts and adjacency retain
their prior validation. Save/load restores the exact result without regeneration.

The shared shader uses uniform light-blue sea-zone fill and dark boundaries, with
four-sided sea-zone outlines. Deep ocean renders as a uniform dark blue through
its background classification, independently of region IDs. No ID edge is drawn
there. Terrain shading and river/lake rendering remain intact.

## Verification and limits

`coastal_seas_smoke.gd` verifies finite coastal coverage, ID-free deep water,
preserved land IDs, lake/inland exclusion, exact mask/reach JSON and disk storage,
draft isolation, reach changes, invalid settings/masks, coastless maps and actual
GPU/editor/gameplay parity. GPU samples check both sea colors. The 2050-pixel
round-trip suite, island attachment, border painting, province/world and shared
renderer suites provide regression coverage.

This is a generated coastal-envelope/sea-zone model. Historical sea regions and
country/naval ownership are not added. Manual visual, zoom and performance review
remain with the user; the reach/count controls support further visual tuning.
