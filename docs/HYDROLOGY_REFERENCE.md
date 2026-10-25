# Lakes, drainage basins and rivers

## Using the editor

Generate a map normally. Lakes and rivers are generated automatically after
height, geography and climate; there are no extra generation settings to tune.

- **Terrain** shows lake surfaces and blue river channels.
- Choose **Drainage basins** in the bottom-right view selector to see catchments.
  Matching colours drain to the same outlet or closed lake. The colours do not
  indicate countries or provinces.
- Click terrain or water for its basin, river reach, accumulated-flow strength,
  lake spill level, actual lake depth and outlet state. Scroll the inspector for geographic/climate
  details. The original land/water feature describes the heightmap relative to
  sea level; the current surface label distinguishes lakes and exposed dry beds.
- Change rainfall, warmth, latitude or wind, then **Apply climate** to recalculate
  runoff and lake/river flows. Zero rainfall produces no generated inland water
  or flowing rivers. Oceans remain.
- **Show heights** hides hydrology presentation so the original heightmap remains
  readable. Climate/basin overlays also hide water ribbons and lake meshes to keep
  their data colours visible.

## Model

`scripts/domain/terrain_hydrology.gd` owns drainage, lake membership, runoff,
catchments and river identities. It samples the existing smoothed geographic
heightfield at the native graph sites. It does not alter integer source heights,
original saved height samples or terrain LOD meshes. Using display heights avoids
routing entirely by an unsmoothed source that may differ from visible terrain.

1. Group below-sea-level cells connected to the map border as open ocean.
2. Seed a deterministic priority flood at ocean shores and cropped map boundaries.
   Each cell receives the minimum elevation of a drainage path to those outlets.
3. Keep the resulting elevations as a separate conditioning field. Strictly
   descending edges prefer the steepest neighboring descent. Flood parents resolve
   equal-height flats without circular routes.
4. Group connected depressed cells sharing a spill level into reservoir candidates.
   Each has one external potential spill route. Collapse each reservoir into a
   single node before accumulating runoff, preventing multiple outlets from
   duplicating the same water.
5. Process the resulting acyclic graph from tributaries toward outlets, collecting
   local rainfall and all upstream discharge at each confluence.
6. Derive catchments from terminal ocean cells, cropped boundaries, closed lakes
   or dry depressions. IDs are deterministic for identical inputs, not guaranteed
   across terrain/climate edits that change drainage or outlet state.

The priority-flood concept follows [Barnes, Lehman and Mulla (2014)](https://doi.org/10.1016/j.cageo.2013.04.024).
This is an original graph implementation, not copied source from that paper's
reference software.

## Rainfall, evaporation and lake levels

The first-pass runoff coefficient is **0.35**: estimated annual rainfall times
native clipped cell area times this fraction becomes available runoff. Ocean
rainfall is excluded. This is a game calibration, not a fitted infiltration model.
The other 65% is outside the simulated runoff budget.

A lake's available inflow is compared with an annual evaporative-demand proxy
summed over its candidate area. This proxy is owned by the climate model and is
also used for biome aridity: `max(150, 400 + 45 * max(-5, temperature))` mm/year.
Loss is bounded by available inflow. Surplus leaves through the lake's single
outlet and can feed downstream rivers or further lakes. Underfed lakes are closed;
zero-inflow candidates are shown as dry depressions.

**Lake surfaces use their geometric spill elevations in this pass.** Different
basins have different horizontal water levels, including lakes above sea level.
An underfed but nonzero-input closed lake still uses its spill-capacity surface:
partial filling, equilibrium shoreline shrinkage, storage history and seasonal
level fluctuations are not simulated. This is a static map-generation model,
not a time-stepped water simulation. Resolving partial closed-lake levels and
separating sub-depressions as they fill are follow-up hydrology work.

Runoff is measured internally in **mm × map-unit² / year**, not m³/s: map units
have no asserted real-world kilometre scale. The inspector's flow strength is
accumulated model runoff divided by the automatic river threshold. The threshold
scales with map area, so changing the geographic cell density does not itself
redefine what counts as a major channel.

## Presentation

`scripts/rendering/terrain_hydrology_view.gd` builds horizontal lake surfaces by
clipping native Delaunay triangles against each lake level. River ribbons follow
connected drainage cells, get wider with increasing discharge and round their
visual bends while retaining source/mouth locations. Heights sample the fixed
high-resolution surface, rather than regenerating while zooming.

Water uses an unshaded map overlay with depth testing disabled, keeping narrow
rivers and small lakes legible over lower-detail terrain. This is presentation,
not channel carving; tilt occlusion and shore precision can be improved later.
Rounded visual ribbons approximate the exact cell route. Hydrological downhill
and accumulation guarantees apply to the graph and conditioned water elevations,
not every interpolated vertex of the decorative ribbon.

The ocean material masks enclosed reservoir footprints so a low inland basin is
not also filled by the old global sea plane. Geographic overview coastlines are
filtered to open-water shores; lake boundaries come from their own surfaces.
The basin raster is a fixed, nearest-cell categorical display; tiny catchments
may fall below its resolution while remaining present in inspected data.

Source changes rebuild topology. Climate-only edits reuse it and recompute flow,
outlet states, basin colours and water geometry. Zoom and LOD changes rebuild none
of these. Picking uses current lake surfaces and exposed dry beds rather than
assuming that every low location is covered by the ocean.

## Documents

Version **7** terrain documents record hydrology algorithm version 1, along with
the existing height, geography and climate source data. Derived networks and
water meshes are regenerated on load rather than persisted as a second large cache.
Versions 1–7 remain supported. Old graph maps gain hydrology while preserving their
saved heights and climate choices. Graphless legacy maps need Generate before
cell drainage can be derived. Invalid hydrology versions are rejected before
mutating the visible world.

## Verification

`tests/terrain_hydrology_smoke.gd` exercises:

- All-ocean, flat land, a draining slope, an above-sea-level bowl and multiple basins.
- Neighbor-only nonascending routes, termination without cycles, basin area coverage,
  exact confluence/lake inflow accounting and total runoff/loss/export conservation.
- Wet overflow, underfed closed lakes, zero-rainfall dry beds and deterministic repeats.
- All 14 real procedural templates.
- The actual runtime imported-heightmap, climate, water-mesh and picking pipeline.
- Fixed lake/terrain geometry through zoom; climate changes preserve height and LOD.
- Basin and height overlays, clicked-water inspection, actual file/JSON round-trips,
  version 6 migration and rejection of unsupported hydrology versions.

Run the regular checks and optional large-map case:

```text
godot --headless --path . --script res://tests/terrain_hydrology_smoke.gd
godot --headless --path . --script res://tests/terrain_hydrology_smoke.gd -- --large
```

Omit `--headless` for rendered captures of a lake, its outlet, basin colours and a
natural continents map. A large 4096×2048 source with 80,000 native cells produced
498 reservoir candidates, 1690 basins and 122 river reaches in one run. The hydrology
pass reported 990 ms for topology and 440 ms for climate/flow calculations. Those
stage timings exclude source-graph construction, geography, rendering, display
raster generation and file work. They are single observations, not a frame-rate or
controlled performance benchmark.

Remaining work includes partial/seasonal lake levels, channel erosion, improved
shore and tilt presentation, river-fed wetlands and floodplains. These are not
represented as completed simulation features.
