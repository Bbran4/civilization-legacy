# Geography generation: ownership and verification

## Scope and authority

`terrain_geography.gd` derives connected geographic components from the saved
cell graph and integer heights. It does not edit heights, route rivers, invent
rainfall, fill depressions, name oceans or simulate lakes above sea level.

- Cells at height 20 or above are land; lower cells are water.
- Components use the graph's real-site adjacency, with stable IDs assigned in
  ascending first-cell order. IDs remain stable for identical graph/heights, not
  across edits that merge or split components.
- `island` is enclosed land with area below 10% of the total rectangular map area.
- `landmass` is land at or above that threshold, or any land touching the map
  boundary (cropping cannot establish an island). The cutoff uses summed Voronoi
  area, independent of cell density, and is a game rule rather than a geologic claim.
- `open_water` reaches a positive-length clipped map-border edge.
- `inland_water` has no such edge contact; it is a lake candidate, not a claim of
  physically resolved water level or outlet. Cropped regional water reaching the
  border is treated as open, regardless of what that water body is called.

The graph owns clipped Voronoi polygons, their cached areas and border contact.
Area uses origin-relative cross products to reduce cancellation. Geography sums
these facts instead of independently interpreting cell geometry.

## Coastal facts and display paths

A cell is coastal when any real neighbor has the opposite land/water status.
Multi-source Dijkstra computes shortest graph-edge distance to those coastal-cell
centres, using physical map-coordinate edge lengths. Both water and land receive
values. Coastal seeds are zero; worlds without a coast use -1 to mean no distance.
This is an approximate distance to coastal cells, not exact shoreline distance or
kilometres. Depth is `max(0, 20 - source height)` in integer height units.

Display paths are separate from cell-component topology. A fixed regular sampling
grid uses twice the longest cell-lattice dimension, bounded to 32–512 cells along
the long edge with matching aspect ratio. It samples the same continuous smoothed
field as terrain rendering. Two triangles per sample cell match the mesh diagonal.
Canonical grid-edge IDs join crossings of height 0.2 without coordinate-rounding
repairs or unstable nearest-point stitching.

Directed segments keep land on the left in map coordinates. Closed outer land
rings have positive signed area, water holes negative. Shores reaching a cropped
boundary remain open; no fake coast is inserted along the rectangular map frame.
Zero-size paths collapsed by floating-point precision are counted separately.

Canonical paths and the height texture stay fixed until source changes. Visible
sea outlines now use depth-tested triangle ribbons in both overview and angled
views, with camera-controlled width and the active terrain LOD's height fields.
Their detailed presentation contours are traced separately from the fixed highest
rendered field using the same contour algorithm. This does not replace saved
geographic identities or the coarser canonical paths described above. Climate and
height diagnostic modes hide the decoration. See [coastline rendering](COASTLINE_RENDERING.md)
for geometry, width, depth, sampling limits and executed checks.
Water shades remain visual bathymetry from the supplied field, not an ocean or
wave simulation.

The contour grid can omit features below its sampling scale, and display smoothing
can make contours differ from categorical cell boundaries. Neither changes feature
IDs. This geography stage does not assign latitude, biomes, ocean names or
continent names; the separate climate and biome stages now add latitude and cover. Old
manually raised water planes retain their appearance and suppress canonical
shoreline outlines when they no longer intersect the canonical sea datum.

## Cache and documents

Version 5 terrain documents contain a versioned geography block with component data,
per-cell IDs/coast/distances/depth, contour dimensions, paths and a source fingerprint.
The graph owner fingerprints geometry, topology, heights, map dimensions and
smoothing at canonical geometric precision. Schema validation checks bounded counts,
types, finite values, feature memberships/counts, area totals, source-depth agreement,
contour extent/orientation and source identity before terrain mutation.

Geography cache version 2 adds island labels. Version 1 caches, which called all
land components `landmass`, remain loadable and gain the new labels when rebuilt.

The geographic block is a derived cache. Loading reconstructs authoritative facts
from the saved graph instead of trusting edited cached measurements. Original
height samples remain exact. Version 3/4 graph documents gain geography on load;
version 1/2 surfaces without a historical graph remain without cell metadata until
regenerated. Existing 64 MiB limits and overwrite backups still apply.

Graph geometry and the complete geography result are cached in memory; terrain
regeneration reuses them when source identity is unchanged. LOD and camera movement
only update visibility/uniforms. They never generate components, coast paths or
water textures.

## Verification executed

On Godot 4.7.2:

- `terrain_geography_smoke.gd`: all-land/all-water, large/small enclosed land, the
  10% threshold, cropped land, legacy geography cache migration, enclosed water, nested
  islands and holes, cropped shorelines and a narrow strait; component coverage,
  depth and coastal flags, Dijkstra recurrence, contour sea-level intersection,
  orientation, deterministic repetition, actual JSON/file round-trip, old version 4
  migration, stale/malformed caches, edited-cache authority and LOD independence.
- Editor, terrain quality, terrain smoke, fixed-LOD/camera and 42-case source parity
  regressions passed with geography enabled.
- The real graph test passed at 100,352 actual cells, including area coverage,
  save/load and runtime picking; its final generation took 31.91 seconds on one run.
- GPU inspection of the saved 4096×2048 world with 80,000 cells produced 216 features
  and 110 shoreline paths. Its new-format save occupied 10.27 MiB and validated after
  JSON reload. Overview, 3D and shadow captures completed without runtime errors.

One measured cached-world GPU workflow took 18.9 seconds elapsed, 17.1 seconds
sampled Godot-process CPU and 465.2 MiB sampled peak Godot-process memory at 500 ms
intervals. Geographic generation accounted for 3.58 seconds in that run. This
workflow includes startup, cached graph loading, geography, LOD, a new-format save
and validation plus GPU captures; it excludes new 80,000-cell triangulation.
Concurrent checks were active. Child-process/GPU memory, steady FPS, agent-token
cost and equivalent cold/warm comparisons were not measured; these observations
are not a controlled before/after benchmark.

Basic [climate generation](CLIMATE_REFERENCE.md) and initial
[hydrology](HYDROLOGY_REFERENCE.md) are now implemented. Drainage, river networks
and static lake spill levels/outlets are derived after geography; partial/seasonal
lake levels and erosion remain future work.
