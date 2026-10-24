# Terrain generation roadmap

Land/water/coastlines, basic climate and first-pass biome cover are implemented.
The remaining stages below are proposed.
The player-facing inputs are heightmap, seed, width and height, plus optional
island shaping and elevation. Other generation choices are derived automatically
and deterministically; three camera zoom preferences apply immediately.

## Current foundation

The project generates a cell graph and heightfield, renders water at a common sea
level, supplies height/slope-based colours, and prebuilds three mesh detail levels.
The map now classifies connected islands/large landmasses, border-connected open water and
enclosed inland-water candidates. It stores coastal flags, approximate coast
distances, depth below the sea datum and fixed display shoreline paths. The flat
overview shows shoreline outlines and water-depth colours. There are still no
drainage networks or lake outlets. Climate-derived biome data and ground colours
now make the world visibly respond to temperature and moisture. Temperature, prevailing wind and
estimated annual rainfall now follow the applied bottom-right climate gizmo. Land snow tint now follows temperature when climate exists; this is not a
snowpack or ocean-ice simulation.

## Implemented: land, water and coastlines

The geographic pass turns elevation into a connected model before rivers or biomes:

1. Classify cells against the heightmap's sea datum, retaining original heights.
2. Group connected land cells into landmasses and connected water cells into water
   bodies with stable IDs and areas.
3. Treat water connected to the map border as open water; enclosed components
   become inland-water candidates. Regional crops use the border as an open
   boundary, rather than claiming that every border-connected sea is an ocean.
4. Extract ordered coastline loops, including holes and islands, with a display
   contour aligned to the heightfield's sea level. Keep geographic identity
   separate from how a smoothed coastline is drawn.
5. Derive coastal cells, distance to the coast, and depth below sea level.
6. Save the derived geographic data with the map and show its identity in the
   cell inspector.

A height threshold alone is not enough to model lakes above sea level: their
levels, outlets and wet/dry status belong to the later drainage work.
A lake will need its own water surface instead of raising the global ocean plane.

Executed acceptance checks: every cell belongs to exactly one geographic
component; every coastline separates land from water; closed loops have stable
orientation and correct holes; boundary-connected water is identified; the same
inputs reproduce the same IDs and topology; changing mesh LOD never changes them.
The executed cases include all-land, all-water, one island, enclosed water, nested
islands/water holes, narrow straits and cropped shorelines. Tests also cover
shortest-path distance recurrence, JSON round-trips, malformed and stale caches,
version 4 compatibility and unchanged geographic data through LOD transitions.

Component identity follows the raw cell graph at height datum 20. Display shores
trace the smoothed heightfield at 0.2 using a fixed sampling budget; they can omit
features smaller than that budget and do not redefine component identity. IDs are
stable for identical saved graph/heights, not guaranteed across terrain edits.
See [geography implementation](GEOGRAPHY_REFERENCE.md) for bounds and limitations.

## Implemented: basic climate

The bottom-right globe places the map's latitude range; a compass rotates the
latitude-based prevailing winds. Warmth and rainfall controls tune the result.
Temperature uses latitude and canonical height; transported ocean moisture,
latitude bands and upslope loss generate rainfall and rain shadows. Three overlays
and cell inspection expose these fields. Climate parameters save in version 6
maps; older graph maps gain defaults without changing saved heights.

See [climate model and verification](CLIMATE_REFERENCE.md) for calibration and
limits. These fields are annual estimates, not daily or seasonal weather.

First-pass [biome cover](BIOMES_REFERENCE.md) now connects climate to normal
terrain colours. Seasonal vegetation, forests as placed objects and river-fed
habitats remain future extensions.

## Next milestone: drainage, lakes and rivers

Use estimated rainfall, cell area and terrain height to derive catchments,
downhill flow, runoff accumulation, lake water levels/outlets and river paths.
Retain original terrain unless an explicit erosion or depression-filling stage is
introduced. Climate fields alone do not resolve lake surfaces or water outlets.

## Following stages

| Order | Stage | Main outputs and dependencies |
| --- | --- | --- |
| 2 (implemented) | Basic climate | Temperature, prevailing winds and rainfall from elevation, an internal geographic extent and ocean proximity |
| 3 | Drainage, lakes and rivers | Catchments, downhill connections, runoff accumulation, lake levels/outlets and river paths using rainfall and cell area |
| 4 (first pass implemented) | Biomes | Vegetation and habitat classes from temperature, moisture, height and water access |
| 5 | Ice and snow | Persistent snow, ice-cap areas and frozen-water masks from climate and elevation |
| 6 | Terrain presentation | Ocean depth colours, shelves, coastline styling, beaches, river meshes, biome materials and vegetation placement |

Climate precedes the final river pass because rainfall determines the available
water. A first drainage prototype may use uniform rainfall, but it must be
identified as provisional. Rivers should follow a consistent drainage graph,
merge downstream and terminate in an ocean, lake or intentional closed basin.
Use a separate working drainage surface to resolve depressions and flats without
silently rewriting the chosen heightmap. Physical erosion or river carving can
be a later optional generation pass with explicit downstream regeneration.

Biomes should be the result of climate and hydrology, not arbitrary patches of
colour. Temperature also distinguishes polar ice from high-altitude snow. Ocean
and relief appearance can be improved in parallel, but presentation should consume
these shared geographic facts rather than create competing terrain definitions.

The first climate implementation should choose a documented internal geographic
extent. Map dimensions are currently world units, not latitude, kilometres or a
planet model; width and height alone cannot determine a real climate.

## After natural terrain

Resources, fertility, travel costs, provinces, settlements, routes and civilization
simulation can build on the natural map. For this game's legacy system, persistent
land and water identities will also provide places where later civilization traces
can remain attached across runs.
