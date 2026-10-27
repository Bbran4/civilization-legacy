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
flat overview and angled terrain view, and shades shallow water lighter than deep water. Click a cell to
see its landmass or water-body ID, area, border contact and approximate distance
from coastal cells. Water cells also show depth in height units, not metres.

**Open water** reaches the map border; **inland water** is enclosed inside the
map. The geographic label identifies an inland-water candidate; hydrology adds
its active lake level, depth and outlet. Enclosed land under 10% of map area is labelled Island; larger or
border-touching land is labelled Large landmass, without claiming continent names.

Current saves include this data; older graph saves gain it when loaded without
changing their saved heights. Shoreline outlines stay visible in 3D, soften at the edges and hide behind foreground terrain.

## What comes next

Basic climate, biome ground cover and the first lakes/rivers pass are implemented.
Partial/seasonal lake levels, erosion, wetlands and detailed ice remain later work. See the
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

## Lakes and rivers

Generate a map to create water drainage automatically. Rivers collect rainfall,
join into larger channels, feed lakes and reach the sea or the edge of a cropped
map. Lakes have their own spill elevations and may have an outlet or be closed.
The current lake surfaces use spill-capacity levels; seasonal filling and smaller
water surfaces for underfed lakes are not simulated yet.

Choose **Drainage basins** in the climate panel to colour areas by their shared
outlet. Return to **Terrain** to see water surfaces and river ribbons. Click water
or land to see its basin, river-flow strength, lake level and outlet information.
**Apply climate** recalculates flows; zero rainfall dries generated inland water
while preserving the ocean and original terrain. **Show heights** hides water
presentation for inspecting the source heightmap.

Maps save in version 9; earlier files still load. See the
[hydrology model and verification](HYDROLOGY_REFERENCE.md) for details and limits.

## Biomes and tree suitability

Choose **Biomes** in the bottom-right view menu to see habitat categories.
Click terrain to read the exact biome, potential tree cover and nearby-water
influence. Wetlands prefer flat wet ground; suitable river and lake banks can
support woodland even when the surrounding country is dry. Rainfall remains
the amount falling from the sky. Potential tree cover is a habitat estimate;
actual tree models are now placed separately, with their cell count shown below. Use **Terrain** to
return to blended natural ground colours.

## Ground surface detail

In **Terrain**, zoom close to see repeating grass, soil, sand, wet ground, rock and
snow textures, with small bumps affecting their lighting. Their size stays the
same when you generate a wider map. Zooming out fades fine texture into the broad
biome colours. No extra settings are required. The diagnostic views still show
their original data. Grass, soil and sand now mix through seeded patches at several sizes, with
irregular contacts instead of only smooth colour bands. Forest and desert edges
now share the same broader colour-and-texture transition zone. Beaches and
water-fed green margins also use larger coverage patches, allowing sand and
vegetation to break into each other along their edges. This happens automatically
in Terrain; the same seed recreates the pattern, and wider maps keep the same
patch size. It changes appearance only. See [terrain material notes](TERRAIN_MATERIALS.md).

## Coastline outlines

In **Terrain**, coast outlines automatically keep a thin visible width as you
zoom. They follow the current terrain detail and respect foreground mountains
and objects. The coloured line is separate from the sandy beach; it is not foam
or a political border. Diagnostic views and Show heights hide it. No new settings
are needed. See [coastline notes](COASTLINE_RENDERING.md).

## Trees and forests

Zoom into **Terrain** to see miniature trees: conifers, broadleaf, dry-climate,
tropical and wetland varieties follow the biome. Forests have seeded clusters
and clearings. Applying a wetter/drier climate changes where trees can grow;
loading the same saved map recreates the same placement. Zooming changes only
visible detail. Individual trees disappear in the flat overview and in diagnostic
views. The inspector's **Placed trees** count is separate from potential cover.
See [vegetation rules and limits](VEGETATION.md).

## Choose tree population and edit assets

Scroll to **TREES**, enter **Requested tree population**, then press **Apply trees**.
Zero removes trees. The status compares actual and requested counts because water,
cliffs and crowded ground can prevent full planting. This also reloads saved tree
scenes without rebuilding the map. The applied count is saved with the terrain.
Open the `.tscn` files under `assets/trees/` to edit geometry/materials; use
`catalog.tres` and its definitions to add desert, snowy or other variants.
See [step-by-step asset instructions](VEGETATION.md).

Rivers now respect foreground terrain, animate downstream and stop at receiving
water shores. Steep reaches have a cascade effect; detached waterfalls and carved
channels remain future work. Terrain now also uses a fixed detailed macro-normal
field. See [presentation status](PRESENTATION_REFINEMENTS.md).

## Inspecting lake edges

Clicking now reports the surface and biome at the clicked spot. A lake-labelled
map cell can include exposed ground outside the visible water, so the inspector
also shows the cell classification separately when it differs. Refreshing climate
keeps inspecting the same position. Cell area, basin, tree count and cell height
still describe the whole cell; the clicked position, temperature, rainfall,
water support and biome describe the point. Surface picking follows the same
clipped lake footprint used for drawing, instead of assuming the entire cell is
underwater.

Nearby freshwater can support greener ground even when the wider area is desert.
Cold conditions still limit vegetation. Decorative patches can cross a biome
boundary, so a texture colour is not an exact categorical biome map; choose
**Biomes** to see the native cell classification.
