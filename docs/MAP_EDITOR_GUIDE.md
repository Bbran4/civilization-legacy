# Map editor guide

Press **F5** in Godot to open the editor; hover over an input or button for a
short explanation.

## Choose a map, then Generate

1. **Heightmap:** choose islands, continents, a volcano, or a supplied map.
2. **Width:** choose how wide the world should be.
3. **Height:** choose how tall the world should be.
4. **Seed:** enter a name or number to make that world repeatable.
5. **Island shaping:** lower the map edges toward the sea to surround the land with water.
6. **Elevation (relief):** raise or flatten hills and mountains without moving the coastline.

Press **Generate** to build your map. The editor chooses terrain detail, noise,
smoothing, surface colours, water and three detail levels automatically.
**New seed** picks a different seed and immediately builds another map.

Try **1024 × 1024** for a smaller world or **4096 × 2048** for a large strategy
map. Larger worlds take longer to create. Increasing dimensions enlarges the
actual terrain; the camera initially pulls back to show it all.

## Use your own heightmap

Click **Import heightmap image…**, choose a PNG, EXR, JPEG or WebP, then press
**Generate**. Bright parts become high ground and dark parts become low ground.
Choose matching width and height proportions to avoid stretching the image.
Selecting another built-in heightmap removes the imported image from your next
map's choices.

Changing a choice, including importing an image, leaves the current map visible
until you generate. Saving always saves the map you can see.

## Explore

| Action | Control |
| --- | --- |
| Zoom toward a place | Point at it and turn the mouse wheel |
| Move around | WASD, arrow keys, or middle-button drag |
| Turn or tilt the terrain | Zoom in, then right-button drag |
| Return to the full map | Press F |
| Inspect a cell | Click the map to see its land/water area, coast information and depth |

Fully zooming out gives an overhead, north-up map with flat colours and no 3D
shadows. Zooming in smoothly restores the angled terrain view. The ground keeps
the same generated features while the camera switches among three prebuilt
levels of detail.

There are three live zoom settings; typing a value applies it immediately:

| Setting | What it does |
| --- | --- |
| **Minimum zoom (×)** | How far OUT the wheel can go: 1 fits the map; 0.5 shows twice as much surrounding space. |
| **Maximum zoom (×)** | How far IN the wheel can go, measured as magnification from the full-map view. |
| **Closest view size** | The smallest patch of ground the camera can show, in map units: smaller means closer. |

The last two settings work together: whichever stops zooming first wins. For
example, raising maximum zoom from 2048 to 4096 has no visible effect if the
8-unit closest-view limit is already stopping the camera; lower **Closest view
size** to 4 to get twice as close. The readout shows the effective allowed range
and which setting is limiting zoom-in. These controls set limits, so use the
wheel or **Farthest view / Closest view** buttons to move to them.

Zoom settings are session preferences and are not stored in terrain files.
Island shaping and elevation are stored with the map.

**Show heights** changes the colours to grayscale: dark is low and bright is high.
It is a viewing aid and does not regenerate the world.

## Save or export

**Save terrain…** writes a complete editable `.terrain.json` map, and **Load
terrain…** opens it again. Overwriting keeps the previous file in a `.bak` file.
Loading preserves the saved heights and settings, including older maps. Pressing
Generate creates a new map with the current map choices and automatic defaults.

**Export grayscale PNG…** saves a picture of the current height samples; use the
terrain file to preserve the full editable map.

Save a map you like before generating or loading another one.

## Land and water information

The editor labels enclosed land smaller than 10% of the total map area as an
**Island**, and larger components as **Large landmass**. Land touching the map
border stays a landmass because the map may crop a larger continent. This is a
map-relative game rule, not an Earth continent definition.

The editor automatically groups connected land and water, outlines shores in the
flat overview and shades shallow water lighter than deep water. Click a cell to
see its landmass or water-body ID, area, border contact and approximate distance
from coastal cells. Water cells also show depth in height units, not metres.

**Open water** reaches the map border; **inland water** is enclosed inside the
map. Inland water is labeled a lake candidate because lake levels and outlets
have not been simulated. Enclosed land under 10% of map area is labelled Island; larger or
border-touching land is labelled Large landmass, without claiming continent names.

Current saves include this data; older graph saves gain it when loaded without
changing their saved heights. Shoreline outlines fade away as you zoom into 3D.

## What comes next

Basic climate and biome ground cover are implemented. Drainage, rivers, lake
levels and detailed ice remain later stages. See the
[terrain generation roadmap](TERRAIN_GENERATION_ROADMAP.md).

## Climate gizmo

Use the **bottom-right globe** to set climate. Drag its highlighted band up or down
to move the map toward the equator or poles; reduce **Latitude span** to make a
smaller regional map. Drag the compass arrow to turn the prevailing winds.
Adjust **Warmth** and **Rainfall**, then press **Apply climate**.

The selector below the button switches between terrain, temperature, rainfall
and wind views. Each climate view has a legend. Click cells for their climate
values and biome labels. **Terrain** shows the resulting biome ground colours,
so dry warm land becomes desert and wetter land supports grassland or forest.
**Warmth offset** adjusts temperatures by up to ±20°C, rather than capping them
at 20°C; the climate status shows the actual range.
Climate changes preserve the heightmap, coastlines and LOD meshes.
Applied choices save with the map; pending edits do not.

This is a basic annual climate estimate. Rivers, seasonal weather, lake outlets
and detailed vegetation are later stages. [Detailed climate guide](CLIMATE_REFERENCE.md).
