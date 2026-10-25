# From Crusader Kings II to Civilization Legacy: map implementation manual

> Status update: hydrology is now connected to visible lakes and rivers. Stage 4
> biome/habitat generation now consumes climate and water availability. The audit
> observations below describe the earlier snapshot; their missing-hydrology
> statements are historical. The user's current order is to finish Stage 4 first,
> then begin this manual's layered-material and presentation work. See
> [current biome scope](BIOMES_REFERENCE.md) and [asset inspection](CK2_ASSET_REFERENCE.md).

> Material update: chapter 6 now has an initial implementation with seven original
> procedural surfaces, packed normals/roughness, regional tint and distance fading.
> See [current material scope and checks](TERRAIN_MATERIALS.md). Historical audit
> observations below are retained; coast outlines and later presentation remain next.

Prepared 25 October 2026. No implementation code is included. Neither game project was changed.

## 1. What the investigation establishes

**Your next major improvement should be a layered map renderer built on your existing generator.** Keep your geography, climate, terrain LODs and camera. Connect hydrology, then add surface materials, proper outline geometry, vegetation and province presentation.

CK2's map appearance comes from several independently controlled layers: a height surface, map-scale colour, repeating surface textures and normals, water, river geometry, province colours, textured borders, vegetation, seasonal coverage, labels, visibility and final colour treatment. Adding more heightmap detail alone will not reproduce that appearance.

Evidence labels throughout this manual:

- **Observed:** directly read from the installed assets, shader declarations or your project source. Shader observations describe the shipped implementation, not proof that every shader variant runs in a particular frame.
- **Derived:** an explanation supported by those observations, with its reasoning stated.
- **Recommended:** a proposed design for your Godot game; it is not a recovered CK2 algorithm.
- **Unknown:** engine behavior that these files do not establish.

The CK2 installation reports Steam build **7399341**. Its executable SHA-256 is `A0CC8E92287AC900B0552F5CCA20DF5ACEDF4773244923A77B15BCDBE143B13D`. The executable's version resource says only `1.0`, so it is not used to identify a CK2 patch release.

This was static inspection of the installed map resources, readable shipped shader source, and your Godot source. The existing editor screenshot was inspected; neither game was launched. No executable decompilation, GPU frame capture, performance measurement or gameplay reproduction was performed. REA's tools were unavailable in this session and its local CLI reported a missing compiled runtime; useful analysis continued through ordinary read-only file and image inspection. There are no REA Evidence IDs to cite.

The investigation covers all requested map-rendering categories, but does not recover CK2's complete native renderer or its original authoring workflow. Engine-side border generation, label layout, runtime pass selection and exact zoom thresholds remain unknown.

## 2. What CK2's map files actually contain

**Observed:** [default.map](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/default.map:1>) names separate inputs for terrain, elevation, provinces, rivers, trees, climate, seasons, positions, adjacency and regions. BMP and DDS headers give the following dimensions.

| Input | Installed representation | Responsibility |
| --- | --- | --- |
| `topology.bmp` | 3072 × 2048, 8-bit indexed BMP | Elevation input named by the map configuration. Visually contains broad relief, mountain ridges, depressions and channels. |
| `terrain.bmp` | 3072 × 2048, 8-bit indexed BMP | Terrain classification input. Palette indices are meaningful data, not simply display colours. |
| `provinces.bmp` | 3072 × 2048, 24-bit RGB BMP | Spatial province identity encoded as exact colours. |
| `definition.csv` | Province ID, red, green, blue, name fields | Connects province identity to those RGB values. These colours are not ruler colours. |
| `rivers.bmp` | 3072 × 2048, 8-bit indexed BMP | Separate river input. Exact engine interpretation of every palette index was not recovered. |
| `world_normal_height.bmp` | 3072 × 2048, 24-bit BMP | Visually a map-scale normal image. The terrain shader samples macro normals; all filename-implied channel semantics are not assumed. |
| `trees.bmp` | 382 × 293, 8-bit indexed BMP | Much coarser vegetation input. Configuration explicitly names several palette indices that count as trees for automatic terrain assignment. |
| `terrain/colormap.dds` | 3072 × 2048 DDS | Map-scale terrain colour asset, alongside the shader's terrain-tint sampler. |
| `terrain/colormap_water.dds` | 3072 × 2048 DDS | Separate broad water-colour asset. |
| `terrain/atlas0.dds`, `atlas_normal0.dds` | 2048 × 2048 DDS each | Detail diffuse and normal atlases. Shader addressing uses a 4 × 4 grid of 512-pixel tiles. |
| `terrain/border*.dds` and companion data/corner assets | Several sizes and styles | Border art. The border shader consumes colour masks; exact native selection of each numbered style is unknown. |
| `climate.txt`, `seasons.txt` | Text definitions | Winter classifications by province and calendar intervals, including separate tree-season transitions. |
| `positions.txt` | Per-province position, rotation and height arrays | Explicit object anchors. Every array slot's engine meaning was not recovered. |
| `adjacencies.csv` | Explicit links, including sea crossings | Gameplay connections that cannot always be obtained from touching polygons alone. |

Sources: [map configuration](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/default.map>), [terrain definitions](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/terrain.txt>), [province definitions](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/definition.csv>), [positions](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/positions.txt>), [adjacency](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/adjacencies.csv>).

**Derived:** CK2 does not need every map layer to have the same resolution or update frequency. Province identity can stay exact while colours change; coarse vegetation instructions can drive many visible trees; fine surface normals can enrich a comparatively modest height surface.

**Recommended:** borrow this separation, using original textures and assets appropriate to your game. Your game does not need CK2's file formats, fixed dimensions or engine-unit constants.

## 3. What to preserve in your existing project

Your project is **Godot 4.7 with the Compatibility renderer**, not Godot 3.x. Its current source already provides:

- Deterministic terrain generation and imported heightmaps.
- Connected geography, coastline extraction, climate and biome classification.
- Three prebuilt terrain LODs, shared edge normals and shader morphing.
- Orthographic camera control and a transition between overhead and angled views.
- Versioned terrain saves and source data preservation.
- A substantive hydrology prototype with separate bed/routing surfaces, basins, reservoirs, runoff and river segments.

The hydrology prototype is **not connected to the inspected main terrain runtime**. Existing test assertions were read, not executed. Biome ground colours are already implemented; trees and other vegetation assets are not. Your current terrain shader uses palette colours and procedural colour noise, without a tiled material texture library or detail normal maps. Your ocean is an unshaded, depth-coloured global plane. Coast outlines are primitive lines for overview, with depth testing disabled.

Sources: [project settings](<D:/GodotGames/WorldWarGame/CivilizationLegacy/project.godot:16>), [terrain shader](<D:/GodotGames/WorldWarGame/CivilizationLegacy/scripts/rendering/terrain.gdshader:45>), [runtime composition](<D:/GodotGames/WorldWarGame/CivilizationLegacy/scripts/rendering/heightmap_terrain.gd:245>), [hydrology prototype](<D:/GodotGames/WorldWarGame/CivilizationLegacy/scripts/domain/terrain_hydrology.gd:38>), [LOD system](<D:/GodotGames/WorldWarGame/CivilizationLegacy/scripts/rendering/terrain_lod.gd:72>), [coast display](<D:/GodotGames/WorldWarGame/CivilizationLegacy/scripts/rendering/terrain_geography_view.gd:18>).

Do not restart these systems to imitate CK2's older engine. Concentrate effort on connecting data and improving how it is presented.

## 4. Establish the shared map layers first

**Recommended implementation instructions:**

1. Define one map-coordinate convention for geography cells, normalized texture coordinates, world X/Z, world elevation and image row direction. Document the conversion between your normalized height values, the domain sea datum and displayed relief.
2. Keep original elevation separate from drainage routing elevation and visible mesh LOD. Raising a depression for routing must not silently fill its visible lake basin with terrain.
3. Have each simulation system own its interpreted facts. The renderer should consume basin IDs, downstream links, lake levels, biome coverage and province IDs instead of rediscovering them from colours.
4. Produce presentation fields from these facts: macro tint, material weights, macro normals, water coverage/depth, snow, forest density and political colour lookup.
5. Keep discrete identity fields separate from continuous appearance fields. Use exact sampling for IDs; smooth filtering is appropriate for continuous weights and colour.
6. Treat hand-painted changes as explicit saved overrides on generated defaults. A climate adjustment should not erase authored province boundaries or settlement anchors.

| Layer | Authority | Typical reason to rebuild |
| --- | --- | --- |
| Bed elevation and topology | Terrain/geography | Height edit or new map |
| Drainage and reservoir topology | Hydrology | Relevant terrain/topology change |
| Runoff, active water and flow | Hydrology using climate | Rainfall/evaporation change |
| Biome and vegetation suitability | Biome/ecology model | Climate, water or authored land-cover change |
| Macro tint and material weights | Presentation derivation | Relevant biome, terrain or paint change |
| Province identity and adjacency | Province system | Province edit |
| Realm colour and border style | Political state | Ownership, map mode or selection change |
| Mesh visibility and detail | Camera/rendering | Camera movement |

**Done when:** changing political ownership does not regenerate terrain; zooming does not regenerate geography; climate edits refresh dependent water/biome facts while preserving source terrain and authored identity.

## 5. Terrain shape: improve landforms before increasing density

**Observed in CK2:** terrain vertices carry alternate height information; patch offsets/scales and edge snapping support matching different detail levels. Its shaders distinguish macro normals from tiled material normals. This establishes a patch/LOD interface, not the engine's complete mesh-generation algorithm. [Terrain vertex shader](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/pdxmap.lua:258>).

**Recommended:**

1. Preserve your current LOD morphing and shared normals.
2. Judge generated terrain by recognizable forms: connected mountain chains, foothills, plateaus, lowlands, valleys, coastal shelves and islands. Fine noise should support those forms rather than cover every plain in equal bumps.
3. Keep physical elevation and visual exaggeration distinct. A relief slider should not accidentally change a river's drainage direction, temperature lapse calculation or lake spill level.
4. Derive broad shading normals consistently across chunk boundaries. Add fine material normals later; they do not create a mountain silhouette.
5. Give steep ground a different material and texture projection. Top-down UVs work well on plains; cliffs benefit from slope-oriented or triplanar rock.
6. Where rivers need carved channels, make carving an intentional terrain operation with clear hydrology invalidation. Shader ripples should never modify drainage.

**Done when:** mountain chains remain understandable in overview, the same valley is recognizable at every LOD, and camera movement produces no cracks or moving coastlines.

## 6. Terrain shading: the largest visual upgrade

**Observed in CK2:** a 4 × 4 atlas supplies repeating diffuse and normal detail. The shader can blend four neighboring material samples; diffuse alpha modifies their transition weights. A separate broad terrain tint is applied with strength 0.75. Macro and detail normals are combined, then snow, political patterns, lighting and fog are applied. Atlas sampling uses explicit mip selection and mip-aware inset to reduce tile bleed. [Atlas sampling and terrain composition](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/pdxmap.lua:128>).

This is more than a grass colour beside a desert colour: broad geography supplies regional character, while repeating materials supply local texture and surface lighting.

**Recommended implementation instructions:**

1. Start with a restrained original material set: grass, dry grass, soil, sand, rock, snow and wet ground. Add forest floor and farmland when their placement data exists.
2. For each, prepare tileable albedo, normal and roughness assets. Keep albedo lighting-neutral: heavy baked sunlight fights the game's directional light.
3. Generate a broad colour field from your climate/biome palette, elevation, drainage moisture and optional painting. This controls regional appearance at all zooms.
4. Derive continuous material weights. Biome describes the ecosystem; slope exposes rock, local wetness exposes mud, and snow deposition covers suitable surfaces. One biome can contain several surface materials.
5. Normalize the competing weights. Blend adjacent materials using a controlled transition mask; texture height or artist-authored alpha can roughen the edge. Define what that channel means instead of treating any existing alpha as height.
6. Combine macro terrain normals and detail normals in a consistent coordinate space. Avoid simply averaging incompatible world-space and tangent-space vectors.
7. Keep detail scale fixed in world units. A grass tile should not grow because the whole map became wider.
8. Fade small-scale texture/normal contrast as its projected size becomes subpixel. Preserve broad colour and relief when zoomed out.
9. If using an atlas, protect tile edges through every mip level. A texture array is another design option to evaluate in the actual renderer; CK2's atlas layout is not mandatory.
10. Apply map-mode and seasonal changes after establishing the base surface. Diagnostic rainfall or height views should bypass decorative tinting when it would distort the data.

**Godot-specific rule:** colour textures and numeric data need different import/sampling treatment. Use colour-space conversion for colour assets, not province IDs, material weights or height data. Keep identity textures lossless and nearest-sampled; avoid ordinary averaged ID mipmaps. Godot documents `source_color`, filtering and sampler types in its [4.7 shading reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html).

**Done when:** one temperate region contains recognizable grass, exposed rock and wet banks without hard rectangular texture transitions; close detail disappears cleanly into coherent distant colour.

## 7. Coasts and outlines: build distinct systems

**Observed in CK2:** borders consume explicit geometry, a diffuse texture and colour-mask data. Their height is clamped above water; the shader biases depth toward the camera and adds pulsing selection. This supports a textured-ribbon interpretation. The native boundary extraction and join construction remain unknown. The declared `WaterFoam` pixel shader merely returns white, so it does not establish an animated foam algorithm. [Border shader](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/border.lua:94>).

Your current overview lines are useful diagnostics but provide neither a stable visible width nor terrain-aware 3D rendering.

**Recommended implementation instructions:**

1. Keep one authoritative coast boundary derived from land/water facts. Generate independent display representations from it.
2. Replace primitive presentation lines with triangle ribbons or an equivalent mask-based treatment that supports controllable width and soft edges.
3. Separate six styles: coast outline, foam/water transition, beach substrate, province border, realm border and selection highlight. A beach is ground; foam belongs to water; a political border expresses identity.
4. Give ribbons continuous distance along their length for texture repetition. Handle caps, sharp turns, narrow channels, island loops and junctions explicitly.
5. Preserve topology when simplifying. Do not close a strait, merge nearby islands or delete a small island because the overview representation is coarse.
6. Use camera-aware width limits so borders remain readable without covering small provinces at distance. Define whether each style prioritizes world width or screen width.
7. Follow the displayed terrain for inland borders; water-edge effects follow the appropriate water level. Manage depth with a small controlled bias and suitable geometry, rather than globally disabling depth tests.
8. Maintain stable geometry across zoom transitions. Select or blend precomputed detail levels instead of retracing every frame.

Your display coast sampling is capped around 512 samples on the major axis. Assess whether visible small coves need a finer presentation field; retain the separation from authoritative geography. [Geography sampling](<D:/GodotGames/WorldWarGame/CivilizationLegacy/scripts/domain/terrain_geography.gd:66>).

**Done when:** coast and fill agree in overview and angled views; thin isthmuses survive; outlines never appear through mountains; sharp corners do not create spikes.

## 8. Finish Stage 3: connect lakes and rivers before polishing them

**Observed in your project:** the hydrology prototype retains original bed heights and a separate filled routing surface, builds receivers, identifies reservoir candidates, calculates climate-fed flow and exposes basin/river records. It already has meaningful regression assertions for determinism, mass balance and routing properties. These are a foundation to connect and verify, not a reason to start a second hydrology solution. [Prototype](<D:/GodotGames/WorldWarGame/CivilizationLegacy/scripts/domain/terrain_hydrology.gd:1>), [existing assertions](<D:/GodotGames/WorldWarGame/CivilizationLegacy/tests/terrain_hydrology_smoke.gd:44>).

One important audit point: the prototype samples bed values from `geography.display_heights` using `contour_size`. Verify that this resolution is suitable for intended drainage features. A reduced display field can erase a narrow sill or channel. If routing needs finer data, give the owning terrain system an explicit shared elevation representation rather than silently increasing only the visual coast resolution.

**Observed in CK2:** rivers have their own geometry and tangent-oriented animated normals. The shader combines riverbed and surface textures, distorted bed sampling, edge/specular fading, snow, lighting and fog. Configuration separately lists major-river province IDs; not every river is just one decorative blue line. The shader does not establish a rainfall-driven generator. [River shader](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/river.lua:118>), [major-river configuration](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/default.map>).

**Recommended implementation instructions:**

1. Connect existing hydrology results to the inspector and runtime map. Show basin, downstream receiver, flow, lake level and outlet so errors can be explained.
2. Distinguish ocean connectivity from all ground below sea datum. The global ocean must not flood every isolated depression.
3. Give each active lake a horizontal surface at its own resolved level. Clip its footprint to terrain and connectivity; a lake above sea level cannot use the ocean plane.
4. Retain explicit dry/inactive reservoir candidates where the water model produces them. A depression does not automatically imply a permanent lake.
5. Generate a river centerline from the drainage network. Any smoothing must remain within the intended channel and preserve downstream elevation and connectivity.
6. Convert flow to a legible, bounded width curve. Very small streams can appear only near the camera; major rivers should remain readable in overview.
7. Build river ribbons with downstream orientation, continuous UV distance and clean confluences. Avoid a stack of unrelated strips that darkens or gaps at junctions.
8. Render a bed beneath a moving surface. Begin with modest normal animation and darker/wetter banks; add screen refraction only after basic alignment works.
9. Join rivers cleanly to lake levels and the sea. Flatten the final water surface as appropriate, cover geometry gaps and avoid visible upward steps.
10. Feed river/lake proximity and water availability back into biome moisture and vegetation suitability. Keep this distinct from rainfall itself.

Major navigable rivers, crossings and ports can later be gameplay systems with their own identity and adjacency. Do not require every visible stream to be a province.

**Done when:** a high-altitude lake has a correct flat surface and outlet; tributaries join downstream; zero-rainfall cases have defined behavior; no visible river climbs a ridge or ends above the water it enters.

## 9. Water: keep the surface simple and enrich its shading

**Observed in CK2:** the water vertex shader places water at a fixed height of 19 engine units. Two scrolling normal samples create motion. The surface combines authored water colour, reflection cubemap, distorted screen refraction, Fresnel, specular and height-based coastal alpha. The observed water shader does not simulate physical surface waves. The seabed has its own water-tint/depth-fog treatment. [Water](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/pdxwater.lua:151>), [seabed](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/pdxmap.lua:488>).

**Recommended implementation instructions:**

1. Retain a flat ocean surface as the starting point. Ensure coverage and lake/ocean separation are correct first.
2. Keep broad deep/shallow water tint, but derive depth relative to the applicable local water surface and bed elevation. Distinguish depth from distance to shore: steep coasts can become deep immediately.
3. Add two gentle normal layers moving in different directions/speeds. Use restrained amplitude at strategy scale.
4. Add a consistent sun highlight, subtle reflection and a Fresnel response. Keep large seas visually quiet so borders, ships and shorelines remain legible.
5. Add a narrow water-edge blend and selective foam. Use shoreline distance and exposure/slope to avoid an identical bright ring around every lake and sheltered inlet.
6. Give ocean, lakes and rivers different motion. River detail follows downstream tangents; lakes should not inherit ocean-scale movement by default.
7. Prefer a reliable opaque or mostly opaque baseline. Treat transparency, refraction and screen effects as optional quality layers with known sorting/coverage limitations.

Your Compatibility renderer is a deliberate constraint. If you add depth-dependent effects, follow its projection/depth conventions and test orthographic cameras, angled views and shore intersections. Do not paste a Forward+ depth reconstruction unchanged. Godot's [depth reconstruction documentation](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html) documents renderer differences. [Rendering limitations](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_rendering_limitations.html) also cover depth precision and colour precision.

**Done when:** water reads as water in a still image and in motion, shorelines remain stable, and water effects do not obscure crossings or settlement anchors.

## 10. Biomes and vegetation: turn ground colour into ecosystems

**Observed in CK2:** trees use instanced position/rotation/slope data, randomized height, diffuse/normal textures, broad tint and seasonal maps. Snow and shared lighting/fog help trees belong to the terrain. The shader establishes the instance interface, not the placement or culling algorithm. [Tree shader](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/tree.lua:94>).

**Recommended implementation instructions:**

1. Preserve your existing climate-driven biome classification. Add hydrology-aware wetlands, riparian vegetation and dry-basin distinctions.
2. Separate biome type, canopy density and actual tree instances. A forest biome need not be filled uniformly with trees, and grassland can contain scattered trees.
3. Build a small coherent tree set: deciduous, conifer, dry/savanna, tropical and bare/dead variants as needed. Add shrubs and reeds only where they noticeably improve habitat identity.
4. Use deterministic placement from stable seed and region/cell identity. Apply density, slope, local moisture, altitude, snow/treeline and authored exclusion masks.
5. Reject ocean/lake surfaces, active river channels, unsuitable cliffs and reserved settlement/road footprints. Blend forest edges with clearings and clustered density.
6. Add controlled variation in scale, rotation and tint. Keep a common palette with the terrain and a consistent miniature scale relative to settlements.
7. Use spatially chunked `MultiMeshInstance3D` groups for repeated assets. Godot culls a MultiMesh as a group, so one world-sized forest prevents useful per-area culling. [Godot MultiMesh documentation](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html).
8. Reduce tree detail and shadows with distance. In overview, let forest identity survive through broad canopy tint/texture even when individual trees disappear.

**Done when:** forests have edges, clearings and habitat-dependent character; trees stay out of water and cliffs; camera movement does not respawn a different forest.

## 11. Snow, seasons and frozen water

**Observed in CK2:** shared shader functions interpolate seasonal values, gate snow using height and upward-facing normals, add noise and blend colour/normals toward snow. Trees have their own seasonal transitions. Water ice uses seasonal input/noise plus a hard northern map-coordinate threshold of 0.74. That is an art-directed regional rule, not evidence of simulated freezing. The political-water shader does not call the same ice function. [Snow functions](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/standardfuncsgfx.fxh:184>), [ice function](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/pdxwater.lua:187>), [calendar](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/seasons.txt>).

**Recommended implementation instructions:**

1. Decide whether the first release needs a static annual map or an actual seasonal calendar. Do not require a weather simulation to finish the map editor.
2. For static presentation, derive persistent snow/ice suitability from your existing temperature and elevation fields, with explicit artistic overrides.
3. For seasons, add seasonal temperature and a snow-coverage state. Accumulation/melt persistence prevents snow flickering whenever temperature crosses one threshold.
4. Prefer snow on suitable upper surfaces; reduce coverage on steep exposed rock. Modify colour, roughness and small-scale normals together.
5. Give trees matching leaf/colour/snow states so white ground does not sit beneath an unrelated summer forest.
6. Model water ice separately from land snow. Define freezing/melting hysteresis, water-body type and flow influence if the simulation needs them. Slow lakes and fast rivers need different rules.
7. Decide explicitly whether ice affects travel. A visual ice mask must not silently grant gameplay access.
8. Keep snow/ice visibility consistent across terrain and political modes, even where CK2's shipped variants differ.

**Done when:** seasonal changes are smooth and reproducible; warm deserts do not freeze because of image position; ice never changes navigability without an explicit rule.

## 12. Provinces, political colours, borders and picking

This is a new layer beyond your five geographic stages, and essential if the goal includes CK2's political-map readability.

**Observed in CK2:** exact RGB province input is separate from province colour consumed by the terrain shader. The political shader retains relief/lighting while mixing terrain luminance with province colour. Secondary colour and occupation pattern logic are separate from the basic terrain path. The native process that produces those runtime colour textures was not recovered. [Political terrain variant](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/pdxmap.lua:387>), [secondary patterns](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/pdxmap.lua:189>).

**Recommended implementation instructions:**

1. Add stable province IDs independent of terrain triangle, geography cell index, colour and ruler. Your intended province layer should own province identity.
2. Support generated defaults and deliberate province painting/correction. Rivers, mountains and coastlines can guide boundaries, but should not silently redefine IDs after every climate edit.
3. Derive province borders, picking and normal adjacency from the same authoritative province representation. Add explicit crossing/port links where mere contact is insufficient.
4. Maintain a small lookup from province ID to active map-mode colour and state. Recolouring a realm should update that state rather than repaint the whole terrain source or rebuild geometry.
5. Choose a politically readable terrain treatment: muted surface colour, retained broad relief and limited tiny texture contrast. Avoid opaque flat colour that erases mountain passes needed for decisions.
6. Derive realm borders by comparing the owners/groups of adjacent provinces. Internal province boundaries can remain faint; external borders should carry stronger emphasis.
7. Add hover/selection as independent masks or border styles. Selection must remain visible in every map mode.
8. Add occupation/dispute stripes as a separate pattern layer with stable scale and direction. Do not encode them into the permanent land-cover texture.
9. Handle islands, enclaves, holes and disconnected pieces explicitly. A province centroid may lie in water or outside the main usable area.

**Done when:** clicking the same location identifies the same province across zoom levels; ruler changes recolour instantly; borders match fills; political colour does not leak into adjacent IDs through filtering.

## 13. Labels, settlements and map furniture

**Observed in CK2:** label rendering uses textured geometry, alpha, opacity/fade controls, disabled depth writes and a depth bias. This does not reveal how names are curved, sized or placed. Separate position records provide explicit map anchors, and a static-map definition includes a frame object. [Label shader](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/mapname.lua:73>), [positions](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/positions.txt>), [static map objects](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/statics/00_static.txt>).

**Recommended implementation instructions:**

1. Add a shared label manager with priorities: realm names in overview, province/region names at intermediate zoom, settlements and local features close up.
2. Fit names inside usable areas, avoiding water, holes and very narrow pieces. Curved realm names are an optional polish step after basic placement works.
3. Perform overlap rejection in screen space and use stable decisions/hysteresis to prevent names flickering during small camera movements.
4. Use terrain-aware anchors, modest depth treatment and clear fading. Keep map labels distinct from always-visible interface text.
5. Reserve settlement anchors and exclusion footprints before placing vegetation. Start with a few readable silhouettes rather than many detailed buildings.
6. Treat ports, bridges and crossing markers as consumers of geographic/gameplay facts. Their art should not create an adjacency by itself.
7. Keep distant units and icons readable against both terrain and political backgrounds. Add a minimap and map-edge treatment only after the main visual hierarchy works.

**Done when:** overview communicates realms without clutter; nearby settlements do not overlap critical river crossings; selected names remain understandable during camera transitions.

## 14. Lighting, haze, fog of war and colour treatment

**Observed in CK2:** common functions provide stylized squared half-Lambert lighting, ambient contribution, distance/angle haze and noisy fog of war. Terrain passes zero specular into the shared lighting function. Visibility data also carries seasonal channels. A restore shader reduces saturation to 0.72, adjusts red balance and remaps levels; an optional bloom variant exists. Runtime activation and exact frame ordering were not captured. [Lighting/fog](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/standardfuncsgfx.fxh:114>), [grading](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/restorescene.lua:50>).

**Recommended implementation instructions:**

1. Use one coherent broad lighting direction, generous ambient fill, rough ground and restrained terrain highlights. Judge mountain readability rather than physical realism alone.
2. Adapt the look to Godot's material lighting. Do not apply CK2's lighting calculation into albedo and then accidentally light it a second time.
3. Preserve your existing transition toward a clearer, flatter overhead map. Apply the same transition policy to water, borders, trees, labels and shadows.
4. Add subtle distance haze for angled views if it helps depth. Preserve useful contrast at overview distance.
5. Give fog of war its own authoritative visibility/exploration states. Haze is a camera presentation effect; visibility is gameplay information.
6. If visibility is added, apply it consistently to terrain decorations, units, labels and relevant overlays so they do not reveal hidden state.
7. Grade toward a restrained common palette only after terrain, water and vegetation agree. Do not copy CK2's numeric grading values as universal settings.
8. Treat bloom as optional. Bright bloom on every coast or snowfield can reduce the map's usefulness.

Godot Compatibility has lower colour precision and lacks the same internal HDR behavior as the other renderers; assess banding and the intended palette in your actual renderer. [Godot rendering limitations](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_rendering_limitations.html).

**Done when:** terrain remains legible under political colour, snow retains form, forest silhouettes fit the light, and unexplored regions do not leak information through labels or decorations.

## 15. Coordinate all layers through the camera

Your existing camera already supplies the foundation. Define a single presentation policy that the map layers share.

| View | Prioritize | Reduce or hide |
| --- | --- | --- |
| Whole world | Land/water silhouette, broad biome or political tint, realm borders, major rivers, large labels | Tiny streams, fine normals, individual tree shadows, minor labels |
| Region | Relief, forest masses, province borders, river networks, settlements | Very fine ground detail and unimportant local markers |
| Close | Surface textures, tree shapes, riverbeds, shoreline detail, local names | Excessive distant labels and oversized political lines |

Transition smoothly using camera scale and projected size. With an orthographic camera, camera height alone is not a sufficient measure of visible scale. Retain stable thresholds and hysteresis for discrete object changes.

**Done when:** slow continuous zoom feels like one map gaining detail, with no sudden switch to a different palette, forest density or coastline shape.

## 16. Editor tools and persistence to add

Add these as the corresponding systems become usable; do not build every panel in advance.

| Authoring tool | Purpose |
| --- | --- |
| Material and macro-tint painting | Correct visually important areas without changing their climate facts |
| Vegetation density/exclusion painting | Create clearings, managed forests and settlement space |
| River/lake inspection and correction | Explain routing and correct selected source constraints |
| Province painting and split/merge tools | Create stable political geography |
| Settlement/port/label anchors | Resolve placements that automatic rules cannot make attractive |
| Snow/ice presentation overrides | Support exceptional regions without hard-coded image coordinates |
| Layer debugging | View IDs, water body, flow, material weights, depth, normals and invalid areas |

Keep generated defaults and authored overrides separately identifiable in saves. Preserve the world seed, generator version, stable IDs, relevant simulation inputs and any source samples required for reproducibility. Version new data and retain your existing backup/migration behavior. Campaign ownership, visibility and history belong above reusable terrain geography.

Define invalidation explicitly: terrain edits can affect drainage, water, biomes and placement; climate edits can affect flow, snow and habitat; province edits affect political geometry; camera movement affects presentation only. Cached output must include the inputs and version that determine it.

## 17. Performance instructions and acceptance checks

No performance figures were measured during this investigation. The following are planned checks, not claims of speed or target hardware capacity.

1. Choose a small debugging map, a representative regional map and the largest supported map. Include dense forest, complex coastlines, many rivers and political boundaries.
2. Record complete generation time, main-thread stalls, CPU time, peak process memory, GPU frame time where available, draw calls and VRAM/texture use. Separate first generation/import from warmed reuse.
3. Capture matching overhead, regional and close camera positions before and after each rendering feature. Measure finished interactions, including recolouring a realm and adjusting climate, not only isolated shader work.
4. Keep geography generation, surface-texture resolution, mesh density and instance density independent. Increase the resource that fixes the observed defect.
5. Chunk vegetation and long geometry spatially. Avoid one node per tree and one unbounded world-wide batch.
6. Bound texture memory deliberately. A 4096 × 2048 RGBA8 field is 32 MiB before mipmaps; a full mip chain adds roughly a third. Several such fields plus copies, normals and render targets add up. These are arithmetic estimates, not measured Godot residency.
7. Use suitable precision per field; do not pack unrelated values together if that causes filtering, colour-space or update conflicts.
8. Keep the existing terrain tests. Add targeted regressions for newly introduced behavior rather than duplicating shader arithmetic in tests.

| Check | Required result |
| --- | --- |
| Narrow strait, tiny island, enclosed sea | Topology, water fill and outline remain consistent |
| Above-sea lake and closed depression below sea | Correct local lake level; no ocean-plane leakage |
| Tributary, confluence, lake outlet and estuary | Continuous surface with downstream motion and correct joins |
| Flat terrain, dry climate and extreme rainfall | Defined routing/water outcome without cycles or unbounded geometry |
| Terrain LOD transition and steep border | No cracks, swimming textures, floating rivers or border penetration |
| Province recolour and selection | Stable identity; correct fill/border/hover without terrain rebuild |
| Forest near cliff, river and settlement | Correct placement exclusions and reproducibility |
| Snow/ice transition | Stable coverage and explicit gameplay behavior |
| Diagnostic map modes | Numeric meaning remains readable and unaltered by decoration |
| Save, reload and generator upgrade | Identity and authored changes survive; migrations are explicit |

## 18. Recommended work order for your current five stages

| Order | Work package | Concrete deliverable |
| --- | --- | --- |
| 1 | Finish Stage 3 integration | Existing hydrology connected to inspector, separate lake surfaces and river geometry; audit routing elevation resolution |
| 2 | Upgrade terrain presentation | Original material library, broad tint, continuous material weights and detail normals |
| 3 | Upgrade coast presentation | Stable ribbons/masks, separate coast/beach/foam styles and depth-aware rendering |
| 4 | Extend Stage 4 | Wetlands/riparian data plus deterministic chunked vegetation |
| 5 | Complete basic Stage 5 | Quiet animated water, coherent land snow, data-driven ice and restrained lighting |
| 6 | Add political geography | Stable province IDs, picking, lookup colours, adjacency and border hierarchy |
| 7 | Add labels and settlements | Shared zoom hierarchy, collision-aware names and editable anchors |
| 8 | Polish and profile | Unified transitions, optional haze/refraction/visibility and measured resource budgets |

If you want one small visual milestone before finishing hydrology, apply the new terrain-material treatment to one representative region. Avoid polishing a whole world's water before its lake levels and river paths are authoritative.

The minimum useful art pack is a small terrain-material set, compatible normal/roughness textures, a few coherent trees, riverbed/surface textures, subtle water normals, border masks/styles and a readable label font. Settlements and landmarks can follow. Create assets in your game's own style rather than making the project dependent on CK2's installed files.

## 19. Evidence coverage and remaining unknowns

| Requested area | Coverage achieved | Remaining limit |
| --- | --- | --- |
| Terrain/elevation | Input headers, visual inspection, material and vertex shader inspection | Original height authoring process and native patch builder unknown |
| Materials/shaders | Atlas layout, blending, normals, tint, political variants and common functions read | GPU frame/pass selection not observed |
| Outlines/borders | Border geometry interface, textures, masks, selection and depth handling read | Native tracing, joins and numbered-style assignment unknown |
| Water | Plane, normals, reflection/refraction, tint, ice and seabed paths read | Actual render-target setup and runtime settings unknown |
| Rivers/lakes | Separate inputs, major-river declarations and river surface shader read | Complete native bitmap-to-geometry conversion and palette contract unknown |
| Climate/biomes | Terrain categories and province winter lists read | No recovered procedural climate/biome-generation algorithm for CK2 |
| Trees | Input image, instance interface and seasonal shading read | CPU placement, density interpretation and culling algorithm unknown |
| Snow/ice | Shared snow and water-ice shader rules read | Exact runtime producer of seasonal fields unknown |
| Provinces/politics | RGB/ID definitions and colour shader variants read | Full native lookup production and border hierarchy selection unknown |
| Labels/objects | Label shader, position records and static configuration read | Curving/layout algorithm and all anchor-slot meanings unknown |
| Lighting/fog/grading | Shared formulas and restore variants read | Active frame configuration and measured appearance unknown |
| Your Godot project | Source integration, rendering, domain layers and existing screenshot inspected | No runtime verification or executed tests in this investigation |

For an exact CK2 reproduction, a later investigation would need targeted native analysis or a declared runtime/GPU capture for these unknowns. They do not need to be resolved to implement the proposed Godot design.

### Source identity ledger

These hashes identify key local files examined on the stated date. Links in each chapter point to the relevant source; hashes establish file identity, not runtime proof.

| Shipped file | SHA-256 |
| --- | --- |
| `map/default.map` | `311A9F00C2AA46D7963DBB368245BEDC6DFD21FBD21990EE181727ABBA97C751` |
| `gfx/FX/pdxmap.lua` | `B10FE10A987BB8730749085D3C223B952E104A8AAC57DD55ECA2A74D512142EC` |
| `gfx/FX/pdxwater.lua` | `DD065CB712F14D67A8280DE4CECE187558ECFF06D3604ADBDEDB2FF4E79E60BC` |
| `gfx/FX/border.lua` | `00F41CD88A49FB7526AD17D78C28A387CC5AF64A3CBEFB8EB4DC80641F4984B8` |
| `gfx/FX/river.lua` | `15E5BBC6976F4110303DEF4BC327DE1D35566E7B4D8545198069E3A3ABF3D0C0` |
| `gfx/FX/tree.lua` | `A263EDFC6D905E5ABD91F44A645723E4EF94734839099D590C4E5D2783BC3A20` |
| `gfx/FX/standardfuncsgfx.fxh` | `1F78AE3F7EBC0A7819BFA6544419A837F2E29980156A786A037E54D8E334C97F` |

Useful local visual references: [CK2 elevation](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/topology.bmp>), [terrain classes](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/terrain.bmp>), [province identity](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/provinces.bmp>), [macro normals](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/world_normal_height.bmp>), [coarse vegetation input](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/map/trees.bmp>), and [your existing editor screenshot](<D:/GodotGames/WorldWarGame/CivilizationLegacy/docs/images/terrain-editor.png>). The screenshot is an existing project artifact, not a newly observed runtime frame.
