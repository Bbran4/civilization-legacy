# Basic climate

The bottom-right climate panel controls a deterministic annual climate estimate.
It generates temperature, prevailing wind direction and rainfall. It does not
simulate daily weather, seasons, ocean currents, rivers or lake levels.
Climate now also drives [first-pass biome cover](BIOMES_REFERENCE.md) in normal terrain.

## Using the gizmo

- Drag the globe vertically to move the map's latitude centre. North is at the
  top of the map. The highlighted band shows the latitude range the map covers.
- Reduce **Latitude span** for a regional map, allowing its centre to move closer
  to a pole. A band cannot cross a pole. A 180-degree band covers the whole planet
  and must remain centred on the equator.
- Drag the compass arrow to rotate all the prevailing wind bands. This is an
  offset from their normal directions, not one uniform wind for the whole world.
- **Warmth offset** adds or removes degrees Celsius everywhere, up to ±20°C;
  it is not a 20°C cap on actual temperatures. The status shows the calculated
  temperature range, including elevation effects.
- **Rainfall** multiplies estimated rainfall: 0 is dry, 1 normal, 2 twice as wet.
- Press **Apply climate**. Editing controls stages a new climate until this button
  is pressed; saving writes the climate currently applied to the visible map.
- Choose **Temperature**, **Rainfall** or **Winds** below the button to inspect
  the fields. Each view includes its own legend. Arrows point where air travels,
  rather than where the wind comes from, and do not indicate speed.
- **Terrain** shows climate-driven desert, grassland, forest, tundra and ice colours. **Show heights** takes visual
  precedence over climate overlays; turn it off to see climate colours again.
- Click the map for latitude, temperature, rainfall wind direction and biome in the
  scrollable top-right cell inspector.

## Model and ownership

`scripts/domain/terrain_climate.gd` owns all climate fields and settings validation.
It samples the fixed smoothed geographic heightfield onto an aspect-correct grid
with at most 129 samples on its longest edge. It never edits source heights,
geographic components, coastlines or prebuilt LOD meshes. Climate is independent of
camera zoom and map view. Climate changes update one field texture and material
parameters; they do not rebuild terrain geometry.

The five controls are latitude centre, latitude span, temperature bias, rainfall
multiplier and wind rotation. Default latitude is 70°N to 70°S, warmth is zero,
rainfall multiplier is one and wind rotation is zero. Map-coordinate units do not
imply kilometres or geographical area. Canonical height 20..100 is mapped to
0..6000 climate metres as a documented internal calibration. The terrain's
**Elevation (relief)** control is visual and does not change climate altitude.

Temperature declines from the equator to the poles using a smooth latitude curve,
with 6.5°C cooling per climate kilometre, then the warmth offset. Values are bounded
to −80..60°C. Trades, midlatitude westerlies and polar easterlies use fixed latitude
bands at 30° and 60°, with hemisphere-specific meridional components. The compass
rotates these vectors. North is map −Y; east is +X.

Rainfall uses 64 fixed Jacobi transport passes, sampling moisture upwind in physical
map coordinates. Each transport step spans 1/32 of the longest map dimension.
Water replenishes moisture according to temperature; land removes moisture through
background precipitation and upslope uplift. Latitude controls a wet equatorial
belt, dry subtropics and wetter midlatitudes. Rain shadows emerge from moisture
loss while crossing high terrain. Open boundaries supply incoming maritime air at
0.6 relative moisture; the regional map does not wrap east/west. Rainfall is an
annualised game estimate, bounded to 0..6000 mm/year. The coefficients are gameplay
choices, not calibration to historical precipitation observations.

Very thin mountain barriers below the climate grid/transport scale may be missed.
The model does not conserve a full atmospheric energy budget and is not a weather
forecast. Rainfall is a field suitable for the next runoff stage; no catchments,
river paths, lake outlets or runoff accumulation are generated yet.
The derived biome cover is a visible response to climate; forest objects and
vegetation simulation remain future work.

The broad relationships follow [NOAA's global circulation overview](https://www.noaa.gov/jetstream/global/global-atmospheric-circulations)
and [UCAR's explanation of altitude and temperature](https://scied.ucar.edu/learning-zone/atmosphere/change-atmosphere-altitude).
The formulas, numerical resolution and precipitation scaling above are our own
simplified implementation.

## Saving

Version 6 terrain documents save climate algorithm version 1 and the five applied
settings. Fields are regenerated from the saved geographic source on load instead
of persisting another large derived cache. Versions 1–5 remain supported and gain
default climate on load when they contain a cell graph. Old graphless terrain
retains its saved surface and needs Generate before climate can be derived.
Invalid values and latitude ranges are rejected before terrain mutation. View
selection and pending gizmo edits are session UI state rather than map data.

## Verification

`tests/terrain_climate_smoke.gd` checks temperature by latitude/elevation, unit
wind directions, latitude wind bands and reversal, windward rainfall/rain shadows,
zero rainfall, bounded fields, deterministic repetition, invalid/nonfinite settings,
real gizmo interaction, terrain/LOD preservation, actual file and JSON round-trips,
version 5 migration, rejection before mutation and base/LOD shader updates.
The optional GPU run captures all three overlays and exercises the cell inspector.

The synthetic ridge case produced approximately 1469 mm/year on its windward slope
and 24 mm/year on its leeward side; this is a regression observation, not a claim of
real-world rainfall accuracy. One GPU capture reported about 1.2 seconds for the
128-cell-long climate grid; this is a single UI timing, not a controlled benchmark.
