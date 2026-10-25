# Biomes and water-supported habitats

Stage 4 now produces native-cell biome identity, water availability and potential
canopy cover after climate and hydrology. In the bottom-right panel choose
**Biomes** for categorical habitat colours, or **Terrain** for gently blended
natural cover. Click a cell to see its biome, potential tree cover and nearby-water
influence. These percentages describe suitability, not placed tree models.

## Ownership and rules

`terrain_biomes.gd` owns classification, names, colours and ecology. Existing IDs
0-11 retain their meanings: Marine, Ice, Tundra, Cold desert, Hot desert, Steppe,
Grassland, Savanna, Boreal forest, Temperate forest, Temperate rainforest and
Tropical rainforest. New IDs are 12 Lake water, 13 Wetland and 14 Riparian woodland.
Lake water does not assert salinity: that is not simulated.

The annual climate classifier uses rainfall divided by an evaporative-demand proxy:
`max(150, 400 + 45 * max(-5, temperature))` mm/year. Below -12 C is ice and below
2 C is tundra. Otherwise rainfall below 150 mm/year or moisture ratio below 0.2
is desert (hot at 18 C); ratio below 0.45 is steppe. Warm land (20 C+) is savanna
or tropical rainforest (1800+ mm/year). Below 8 C, sufficiently moist land becomes
boreal forest. Other moist land becomes temperate forest or temperate rainforest
(2000+ mm/year), otherwise grassland.

Hydrology is generated first. Active lakes and routed river cells seed a
multi-source shortest-distance traversal along graph edges, excluding ocean.
Influence decays exponentially with distance and elevation above that water.
Its radius is the larger of 0.5% map length and 1.5 graph spacings; traversal stops
at three radii. Effective ecological moisture adds at most 1.2 times annual
evaporative demand times this influence. **It does not change rainfall**, river
flow or lake water balance. This is an original gameplay suitability model,
not groundwater, soil saturation, flood frequency or a scientific water budget.

Suitable water-supported land below slope 0.065 becomes wetland; very wet
(2200+ mm/year), very flat lowland can also become wetland. Moderately sloped
water-supported banks become riparian woodland. Cold ice/tundra takes priority.
Inactive dry lake beds use terrestrial climate rules. Zero-rain channels provide
no persistent water support. Slope uses canonical relief, independent of the
user's visual Elevation control. Seasonal wetlands, coastal salt marshes, soils,
groundwater and detailed floodplain modeling remain future refinements.

Potential canopy differs by habitat, fades at the cold treeline and steep slopes,
and is zero on ocean, active lakes and active river channel cells. Habitat and
canopy are separate from future deterministic tree placement and art.

## Rendering and saving

Base ground colour retains the shared 281 by 601 climate palette with gentle
five-tap threshold blending (within +/-1 C and +/-20 mm/year). Local water support
and wetland/riparian weights are separate, linearly sampled spatial fields;
base climate colour is not replaced by a blurred low-resolution colour map.
The diagnostic Biomes view uses nearest-sampled categorical colours. Its fixed
256-long-edge raster and native cells impose a sampling limit; ground blending
can differ from exact cell labels at boundaries. Beaches, rocks and snow remain
presentation layers and can cover the biome ground tint.

Cell inspection reads the owning native-cell result. Applying climate regenerates
hydrology then ecology, while retaining heights, geographic identity and terrain
LOD meshes. Camera movement only changes presentation. Version 8 documents record
the biome algorithm version; derived arrays are regenerated. Versions 1-7 still
load, with current ecology added without changing saved source terrain.

## Validation and reference

`terrain_biomes_smoke.gd` checks habitat cases, cliff/cold/water exclusions,
actual routed river influence, zero-rain removal, determinism, inspector/material
propagation, version rejection and version 7 migration. The climate regression
checks rainfall-driven changes, shared palette reuse, unchanged geometry and
biome reproduction through a real JSON/file round trip. Hydrology regression
checks the lake identity and canopy exclusion alongside drainage and picking.

The installed CK2 files were inspected as reference only; see
[asset evidence and recommendations](CK2_ASSET_REFERENCE.md). No CK2 assets or
shaders are copied. Tiled textures and detail normals now have an initial
[layered material implementation](TERRAIN_MATERIALS.md). Tree instances, province
borders and the remaining [implementation manual](CK2-map-to-Godot-implementation-manual.md)
are the subsequent presentation work, not part of this classifier milestone.
