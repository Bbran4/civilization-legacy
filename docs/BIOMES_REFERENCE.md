# Climate-driven terrain cover

The normal **Terrain** view now responds to climate rather than showing the same
height-based green terrain in every climate. Apply a climate, then choose Terrain
to see its first-pass biome cover. Clicking a cell shows its biome name.

## Rules

`scripts/domain/terrain_biomes.gd` owns biome classification, names and colours.
Water is Marine. Land can be Ice, Tundra, Cold desert, Hot desert, Steppe,
Grassland, Savanna, Boreal forest, Temperate forest, Temperate rainforest or
Tropical rainforest.

The rules use annual mean temperature and estimated annual precipitation. A
simple evaporative-demand proxy is `max(150, 400 + 45 * max(-5, temperature))`
mm/year. Rainfall divided by this value gives a moisture ratio: the same rainfall
supports less vegetation at higher temperatures. This is a gameplay approximation,
not a solved water balance or a full scientific biome classification.

- Below −12°C: ice-covered land; −12..2°C: tundra.
- Other land with rainfall below 150 mm/year or moisture ratio below 0.20: desert,
  labelled hot at 18°C or above and cold below that.
- Moisture ratio below 0.45: steppe.
- At 20°C or above: tropical rainforest with at least 1800 mm/year, otherwise savanna.
- Below 8°C: boreal forest when sufficiently moist, otherwise grassland.
- Other land with at least 2000 mm/year: temperate rainforest.
- Remaining sufficiently moist land: temperate forest; otherwise grassland.

Temperature thresholds and annual rainfall cannot resolve seasonality, soils,
groundwater or river-fed vegetation. Rivers and lake outlets do not exist yet.
There are no placed forest meshes or vegetation assets in this pass: biome ground
colours and data are implemented, along with temperature-driven land snow cover.
Ocean ice and a dynamic snowpack are not implemented.

The broad distinction follows NASA's [annual temperature/precipitation biome diagram](https://appliedsciences.nasa.gov/sites/default/files/2021-08/SDM_Part1_Final.pdf)
and [tropical rainforest description](https://science.nasa.gov/kids/earth/mission-biomes/biorainforest/).
The specific rules and calibration above are our simplified design choices.

## Rendering and saving

Biome IDs still use the fixed climate grid, but visible ground colours no longer
come from a blurred low-resolution map. A shared 281×601 palette maps temperature
and rainfall to the existing biome colours, using the same domain classifier as
the cell labels. The shader first samples continuous climate at each visible
point, then reads this palette with gentle transitions. A small five-tap filter
softens classification thresholds within ±1°C and ±20 mm/year in palette space;
it leaves uniform biome interiors intact. The 0.5°C / 10 mm/year palette spacing
is unchanged. No spatial map blur or palette mipmaps are used, so close-up detail
is preserved and categorical biome data stays unchanged.

Beaches, exposed rock, slope shading and fine surface variation remain. Snow tint
follows calculated temperature when climate is present; legacy graphless terrain
retains its old height-based appearance. Coastline and terrain geometry do not
change when applying climate. Climate overlays and the height view still work
independently of normal terrain cover. Water rendering remains separate from land
cover, avoiding blue vegetation fringes at the coast.

The cell inspector classifies its interpolated climate values against its raw
land/water status. Display sampling can blend biome boundaries and differ slightly
from categorical labels close to a boundary.

Version 6 maps already preserve the climate parameters and saved source needed to
regenerate this derived cover. No second biome cache is written. Old version 6 maps
gain the new appearance without changing their saved heights or climate settings.

## Verification

The climate regression includes hot/cold deserts, boreal and temperate forests,
temperate/tropical rainforests, savanna, tundra and ice; evaporation-sensitive
aridity; water classification; actual rainfall-driven changes to biome IDs and
the climate texture that drives normal terrain; shared palette reuse; base and LOD material propagation; unchanged terrain geometry;
and biome reproduction after real file and JSON reload. GPU captures compare the
same terrain in dry and wet climates using the normal Terrain view, plus an
inland close-up to inspect biome boundaries and surface detail.
