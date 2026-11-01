# Ground textures and painting

You can give each land biome three textures and choose how they form patches.
You can also paint those textures onto individual places. Painting changes the
look of the ground, not its elevation, climate, drainage or native biome.

## Choose textures for a biome

1. Run the game and scroll the left panel to **GROUND PAINTING**.
2. Open **Ground textures…** and choose a biome at the top, such as **Hot desert**.
3. Configure its three texture cards. Use a built-in starter, or press **Colour
   image…** to choose a PNG, JPG or WebP file. Each card shows its current image.
4. Choose a built-in coverage pattern or supply your own **Pattern image…**.
   White means more of that texture; black means less. In a biome mix the three
   masks compete for coverage, so at least one texture always supplies the ground.
5. Press **Apply textures**. Every area using that biome updates without generating
   a new map. Beaches, mountain rock, snow cover and wet soil have separate rows.

For a desert, try sand dunes in slot 1, rough soil in slot 2 and rocky sand in
slot 3. Give them different repeat sizes and amounts to make broad sand patches,
smaller gravel islands and occasional exposed stone. The starters are original
procedural art; you can replace them with your own images.

![Runtime texture palette](images/ground-texture-editor.png)

Scroll inside the window for rotation, amount, roughness and the individual
**Paint this texture** buttons. Ocean and lake-water rows are reserved: the water
surface still uses its separate water material.

| Option | What it does |
| --- | --- |
| Starter texture | Picks an original built-in grass, dry grass, soil, dune, rock, snow or wet-ground texture. |
| Starter colour | Changes a built-in texture's colour; imported colour images keep their own colours. |
| Colour image | Supplies the actual colour and markings you want to see on the ground. |
| Normal image | Changes how little bumps catch the light without moving the land. |
| Pattern image | Uses a black-and-white image to decide where this texture appears. |
| Built-in pattern | Chooses broad blotches, small islands or bands when no pattern image is supplied. |
| Texture repeat size | Makes the image repeat over a larger or smaller patch of ground. |
| Pattern repeat size | Makes the coverage pattern repeat over a larger or smaller area. |
| Rotation | Turns the texture and its coverage pattern. |
| Amount | Changes how often this texture wins space in the biome mix; zero excludes it from the mix. |
| Roughness | Makes the surface more matte at high values and shinier at low values. |

A supplied pattern image overrides the built-in pattern selector. Use **Use
built-in pattern** to switch back. Supplied normal images override the starter
normal. The colour image's alpha is ignored: use the separate pattern image for
coverage instead of transparency.

## Paint individual areas

1. In the texture window choose **Paint this biome mix**, or scroll to a card and
   choose **Paint this texture**. This applies your choices and closes the window.
2. In the left panel, **Paint ground** is now enabled. You can also enable it there
   directly and choose a biome/surface and **Biome mix** or one numbered slot.
3. Set **Brush radius** and **Brush strength**. Move over the map to see the brush
   footprint, then hold the **left mouse button** and drag. The strokes connect
   continuously even when the pointer moves quickly.
4. Enable **Erase paint** to reveal the generated ground. **Undo paint stroke** or
   **Ctrl+Z** undoes the last stroke, including a whole drag or erasing stroke.
5. **Clear ground paint** removes the whole layer; Undo can restore it.
6. Turn **Paint ground** off to return left-clicks to cell inspection.

Painting works in **Terrain** view with **Show heights** off. Camera movement,
wheel zoom and right-mouse orbit/tilt remain available. The brush follows the
height of the visible surface and its outline respects depth. Water surfaces
are unchanged; paint applies to the terrain bed, including any ground hidden by
water. A single-slot brush uses that slot's coverage pattern too; black holes
reveal the generated ground. A mix brush places the three textures using their
relative masks and amounts.

![Ground painting controls and a grass stroke over desert](images/ground-paint-brush.png)

This preview uses an intentionally warm, dry test map so the painted grass is
visible. The native biome remains desert. Clicking a painted point with painting
off shows the **Paint layer** separately from its climate/biome information.
Paint does not place trees or change habitats.

## Save and load

**Save terrain…** writes version **10** maps with the palette settings and a
lossless embedded paint layer. Earlier versions 1–9 load with the new default
palette and an empty paint layer. Loading and climate changes retain the chosen
materials and paint; generating a new map clears its strokes but keeps your
current palette. Save your map before generating another one.

Colour, normal and pattern images are **linked assets**, not embedded in the JSON.
Keep them at their selected paths. For a portable project, put them under
`assets/terrain/` and select their `res://` assets; include those files when moving
the project. If a dependency is missing, loading stops before replacing the open
map. Palette edits and brush strokes are saved; undo history is only for the
current editing session.

The default palette is also editable in Godot as
`assets/terrain/default_ground_palette.tres`. Each row has three material resource
slots, including Texture2D fields for colour, normal and coverage images. Runtime
edits use a deep copy and do not overwrite that default resource. Image textures
are baked to 256 x 256 layers for this Compatibility implementation; original
image files are not modified. Use seamless/tileable art to avoid repeated seams.

## How blending now works

The previous regional colour multipliers, pigment ratios and broadened colour
lookups are removed. Ground colour comes directly from the chosen texture images.
Coverage masks determine which texture appears in each patch; only a narrow
contact band blends the neighbouring textures. Climate selects the underlying
biome, and mountains, beaches, snow and wet ground select their own material rows.
Lighting, normals and cavity shading still affect brightness. Diagnostic views
show their original data instead of painted appearance.

See [material implementation and validation](TERRAIN_MATERIALS.md).
