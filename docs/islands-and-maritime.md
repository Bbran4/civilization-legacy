# Island attachment and coastal maritime regions

## Attach a small island to a mainland province

1. Click the mainland province you want the island to belong to.
2. Enable Paint region borders. Attach whole separate islands is on by default.
3. Touch the small island with the brush and release. The entire separate landmass
   joins the selected province, sharing its ID, name and color. No sea bridge is
   painted and no height/water sample changes.
4. Undo restores the former island province, including its original ID and name;
   Redo attaches it again.

A land province may have one connected part on each of several physical islands.
Painting on the same landmass remains a local border edit. The whole-island option
only expands over a landmass where the selected province had no existing part at
stroke start. Turn it off to paint island pixels individually. Separate pieces on
one physical island remain invalid, and ocean regions must remain connected.

When a donor land province loses its final pixels, its record becomes inactive
rather than renumbering other IDs. Inactive records retain their names for Undo
and save compatibility, cannot be selected as paint targets, do not count as active
provinces and own no pixels. Undo/Redo stores these activation changes along with
pixel deltas. Land regions spanning multiple islands retain stable IDs through
saving, loading and later ocean generation. The inspector shows the number of
island parts when a province has more than one.

Generation initially still gives isolated land its own identity; this change adds
explicit manual attachment rather than silently assigning islands by size. A
whole landmass can include multiple existing province IDs, all of which transfer
when attaching that landmass. A donor that still owns another island remains
active for that remaining land.

## Coastal maritime partition

See [Coastal seas and borderless open ocean](coastal-seas.md) for the current
default. The earlier partition modes remain readable for old maps. Previously,
the ocean partition selector offered:

- Coastal maritime regions (default for new maps): choose spread-out coastline
  anchors, then grow equal-cost regions through connected sea. Borders therefore
  originate from coastal locations and respect land barriers and channels.
- Open sea zones: retain the earlier partition using distributed offshore seeds.

Coastless sea maps fall back to offshore seeds. Ocean generation preserves authored
land IDs/names and island attachments. It remains explicit and replaces existing
ocean regions when run. Loading an old ocean map preserves its existing IDs without regeneration. The
current controls stage the new coastal-band style for older coastal maps; Generate
ocean borders explicitly applies the selected layout.

Lakes and enclosed inland water stay unassigned in both modes. Maritime regions
are geographic game-map sectors; ownership, naval access and sea movement rules
are separate future data. This implementation does not add a territorial distance
limit or country ownership to the generated sea regions.

## Storage and validation

The optional province section now uses version 5, retaining active/inactive
records and ocean style while adding coastal reach and the deep-ocean background
mask. Existing v1-v4 province sections remain readable. Main terrain v10 and world manifest v3 are unchanged; snapshot-first
world saving still preserves previous source documents.

Landmass labels and per-region part lists are derived from the authoritative
land/ocean ID raster and rebuilt on load. A land ID can have one connected region
per physical landmass; an ocean ID has one connected sea region. Active records
must own pixels; inactive records must own none. Names and IDs remain stable when
painting. Current coverage still assigns all land to land IDs and generated sea
to ocean IDs, excluding lake/inland masks.

`island_maritime_smoke.gd` checks one-touch whole-island attachment, pixel-only
island edits, untouched mainland borders, archival IDs, exact Undo/Redo including
chained absorptions, multipart save/load, inactive-target rejection, coastal
anchors/determinism, the legacy open-zone option and unassigned lake/inland water.
It also attaches an actual template island through the editor, saves/restores it
with maritime regions and captures real GPU output. Existing border, province,
world and maximum-resolution suites cover integration and compatibility.

Dedicated [split/merge tools](province-split-merge.md) are now implemented, sharing
the island/border editing history and preserving stable IDs.
