# Heightmap generation: behavior and verification

## Source provenance

Source attribution, pinned revision and links are retained in
[third-party source notices](../licenses/HEIGHTMAP_SOURCES.md).

## What the source actually does

The graph and heightmap each start from a fresh Alea sequence using the same seed.
Site spacing is rounded to two decimals from `sqrt(width * height / points)`.
Sites are placed near lattice centers, jittered by up to 45% of spacing on each
axis, and rounded to two decimals. Boundary pseudo-sites close the diagram.
Delaunay edges give the adjacency of real Voronoi cells; boundary sites are not
terrain cells. Logical width, height, requested point count and viewport size are
independent inputs. Actual cell count is approximate.

The heightmap is a Uint8 cell array (0–100), with land beginning at 20. The 14
ordered recipes operate on that graph:

| Operation | Source behavior preserved in the port |
| --- | --- |
| Hill | Select a peak, then queue neighboring cells with random power attenuation; quantize influence as Uint8 before adding it |
| Pit | Prefer land, traverse neighbors, decay the current pit strength across the traversal, subtract quantized heights |
| Range / Trough | Choose endpoints within distance constraints, find a randomly perturbed neighbor path, affect successive neighbor rings, then walk downhill to create prominences |
| Strait | Follow a perturbed cross-map path and lower adjacent heights using powers; preserve the source's accumulated query behavior |
| Add / Multiply | Affect all, land or a specified elevation band, preserving the special land datum arithmetic |
| Smooth | One weighted neighbor-average pass; `Smooth 3` means one-third blending toward the mean, not three blurs |
| Mask | Weight the interior or edges from normalized site position |
| Invert | Probability-controlled reflection through lattice slots |

Fractional counts are probabilistic integers. Integer limits do not consume extra
random numbers. Percentage placement uses the upstream inclusive random helper,
including fractional range bounds. Uint8 truncation matters at each operation;
retaining arbitrary float heights instead changes subsequent terrain generation.
Density-specific hill/range powers use the same lookup values and source fallbacks.

Supplied/imported images are resized to the cell lattice. The red channel `r`
maps to `floor(100*r)` below 0.2, otherwise
`floor(100*(0.2+(r-0.2)^0.8))`, clamped to 0–100. This is a source-height conversion,
not direct linear elevation. Browser Canvas and Godot resampling can differ.

The source renderer displays smoothed vector boundaries and contours; its browser screenshot
is not a 3D mesh. SVG curve quality is separate from graph density.

## Why the previous terrain was flat and streaked

The preceding implementation propagated heights across a regular eight-neighbor
grid. Those fixed directions introduced directional structure despite randomized
amplitudes. Mesh refinement could not remove it. Its extra crater and atoll ring
also departed from the source recipes. Those implementations are removed.

Previously map size was also literal 3D X/Z scale, while vertical elevation stayed
fixed. Increasing both horizontal dimensions therefore reduced apparent relief.
Version 3 then fitted the longest edge into 192 display units, preserving relief
but preventing a larger physical world. Version 4 restores actual world X/Z
dimensions and scales vertical relief uniformly with them. Automatic cell density
and prebuilt terrain levels address the separate geographic/display limits.

## Native ownership and display

- `alea.gd` owns Alea/Mash and UTF-16 seed interpretation.
- `terrain_graph.gd` owns sites, Delaunay topology, cyclic neighbors, integer cell
  heights, Voronoi polygons and display-field interpolation.
- `heightmap_recipe.gd` ports the source recipe operations and image-height curve.
- `heightmap_terrain.gd` owns graph caching, optional cell edits, mesh sampling,
  materials, image-input provenance and surface picking.
- `terrain_generation_profile.gd` owns deterministic automatic choices for new maps.
- `terrain_editor.gd` stages the map inputs, files and geographic/climate cell inspection.
- `terrain_document.gd` validates and restores portable versioned state.

The native graph uses `Geometry2D.triangulate_delaunay`, not fixed grid links.
Godot's float32 sites, triangulator, and cyclic-neighbor starting/order conventions
differ from browser Delaunator. Identical seed strings are reproducible here but
are not promised to yield pixel-identical browser maps. The underlying graph is
Voronoi; it is not the preceding regular-grid approximation.

Points control geographic data, bounded to 1,000–100,000 requested cells. With
automatic density enabled, this is a reference count per 1024×1024 map area;
disabling it selects an explicit total. Map dimensions are actual world X/Z
extents, with relief scaled uniformly by the longest edge divided by 192. Mesh resolution (16–1024 along the
longest edge) controls the display sampling grid and reuses the graph geometry.
Surface smoothing (0–4) is explicitly separate: zero uses linear triangles;
positive settings average displayed heights and use bounded cubic Bezier patches
with shared edge controls. The cubic display is our 3D interpolation, not an
source algorithm. It does not change authoritative cell heights or invent cell
features. Fields outside the boundary-site hull use nearest-site extension; the
production graph test checks zero uncovered samples on its normal rectangular map.

Additional noise is off by default. When requested, noise, contrast and falloff
are applied at the cell-data boundary, so inspector data remains owned by the
graph. Source recipes do not include that optional layer. Normalized height `h`
is displayed at `(h-0.2)*elevation+height_offset`; changing relief with zero offset
keeps height 20 at sea level. Legacy restored surfaces retain their saved heights
and their earlier grayscale encoding until regenerated.

The runtime editor exposes only heightmap, seed, width and height. The automatic
profile selects density (10,000 reference cells per 1024², bounded to about 100,000),
heightmap resolution (256–1024), three LOD levels with 128 high cells per chunk,
source-preserving height contrast, balanced relief, colours and noise defaults.
Startup and new generation apply the profile; document loading preserves saved
settings. Inspector properties remain developer controls, not runtime inputs.

The viewport can resize without changing the graph. Zoom is relative to the fitted
view, default 1–2048 with an additional absolute closest span of 8 world units; horizontal orbit and the requested reversed tilt are retained.
Picking intersects the visible mesh/water surface and resolves the actual nearest
Voronoi site. Inspector area is clipped Voronoi area in logical map units squared.
No real-world kilometer/meter or geographic-coordinate model is claimed.

## Close views and world scale

A runtime-only chunk renderer samples one fixed high-resolution graph field at
generation time, then prebuilds exactly three meshes per chunk. Lower levels use
subsets of the highest grid. Default cells per chunk are 32/64/128. Chunk counts
follow roughly 256 world units per chunk, capped at eight along the longest edge;
the other axis follows the map proportions. The maximum setting uses 256 high
cells per chunk. Cosmetic seeded micro variation is generated once in world
coordinates and shared by every level, including grayscale display.

Normals are computed over whole-map grids before splitting into chunks, avoiding
one-sided edge derivatives and visible lighting seams. The shader morphs vertex
heights and normals toward their parent level. Both levels share triangle diagonal
orientation, so the parent surface can be represented by the fine grid without a
height jump. Picking samples that same morphed surface. Separate entry/exit zoom
thresholds prevent level chatter. No graph rasterization or mesh construction
occurs during zooming or panning. Orthographic scale is equal across chunks;
Godot performs normal per-chunk frustum culling. The old region queries, spatial
triangle bins, moving patch and base-fragment clipping have been removed.

The base grid remains the owner of saved height samples, image exports, legacy
surfaces without graph data, and the fallback view when chunk LOD is disabled.
Its resolution is independently labeled in the editor to avoid implying that it
controls the prebuilt high-level surface. A finite fixed high-resolution surface
cannot produce unlimited geographic detail at arbitrarily deep zoom.

The camera anchors wheel zoom to the visible terrain and supports an absolute
local view size. At full zoom-out, pitch is exactly 90 degrees and yaw is north-up.
From relative zoom 1 to 3 it smoothly restores the stored close-view pitch/yaw.
The same blend moves material colour from unlit emission to normal lighting and
restores sun shadows. Map heights remain unchanged. Pan uses camera-up projected
onto the map, so movement stays well-defined at exactly overhead pitch. The 4096×2048
preset uses roughly 80,000 cells at the default reference density. The 100,000-cell
cap still applies to larger worlds: increasing dimensions beyond that budget does
not keep adding geographic information. This is terrain infrastructure, not a
claim of finished Europa Universalis art or simulation.

## Documents and compatibility

Version 6 terrain files store graph sites, triangles and integer heights in
addition to exact final float32 surface samples, seed/density and editor settings.
Neighbors/polygons are derived from their topology on load. Custom source images
are embedded as red-channel samples at saved mesh resolution, with their original
path/dimensions retained as metadata. This is not an archive of all original pixels.

Version 1/2 files load without regenerating or changing their final samples,
including legacy square sampling on rectangular maps. They have no historical
cell graph: generating creates current cell data. Re-saving a legacy surface
without generation retains its absence of a graph and original generator version.
Version 3/4 graph documents also remain loadable, retaining their saved point
density mode (version 3 uses an explicit total). Version 4 introduced the density mode and
local-detail settings. Saved canonical mesh heights remain unchanged by world
scaling; prebuilt LOD meshes are derived and are not serialized. The existing
version 4 detail fields now configure fixed chunk detail rather than a moving patch.
Version 6 adds validated climate settings; fields regenerate from the saved graph.
Version 5 added geographic feature IDs, areas, coast/depth/distance arrays and
ordered display shoreline paths. They are a bounded, validated derived cache: load
reconstructs facts from saved graph data. See the [geography reference](GEOGRAPHY_REFERENCE.md).
The format is not the source generator’s `.map` format.

Complete document validation precedes mutation. Counts, indices, numeric types,
finite values, integer cell heights and sample layouts are bounded. Input/output
size is capped at 64 MiB. Overwrites use a temporary file and preserve `.bak`.
Saved graph structure is validated; this is not a mathematical proof of Delaunay
validity for arbitrary externally edited files.

## Verification actually executed

On Godot `4.7.2.stable.steam.ed1daf0bf`:

- `heightmap_parity.gd`: 42 template cases (14 templates, two seeds at 1,000 requested
  cells and one at 10,000). Every integer cell height matches execution of the
  original upstream TypeScript on the same graphs. Alea matches original uint32
  outputs, including a non-BMP Unicode seed. Original graph-generator placement
  and boundary coordinates match within float32 precision. This establishes
  operation parity on these graphs, not identical browser Delaunator ordering.
- `terrain_smoke.gd`: reproducibility, nested-noise rebuilds, source-image heights,
  inversion/interpolation, water, transient generated meshes, resolution bounds.
- `terrain_editor_smoke.gd`: all recipes, seed variation, real UI handlers/dialogs,
  exact save/load, backups, malformed-file rejection, embedded image input,
  grayscale export and camera directions. GPU mode captures selected templates
  and a supplied world heightmap for inspection.
- `terrain_quality_smoke.gd`: rectangular topology/export, matching heights when
  refining the mesh, a full 1024² mesh, maximum-resolution embedded-image round
  trip, legacy layouts and malformed sample dimensions.
- `terrain_graph_smoke.gd`: graph caching, non-flattening map enlargement,
  reciprocal irregular adjacency, positive cell areas, full clipped-cell area
  coverage, exact graph restore, malformed indices, cell picking/UI, bounded deep zoom,
  and a graph near 100,000 real cells.

- `strategy_zoom_smoke.gd`: fourfold physical scale and relief, area-based cell
  budgets, equal absolute closest view sizes, three prebuilt levels with matching
  heights/normals at chunk boundaries, shared source samples, morph continuity,
  GPU attributes consistent with picking, stable thresholds, cached mesh reuse,
  unchanged source data, version 4/3 compatibility, and cursor zoom anchoring. GPU mode also exercises a 4096×2048 world and captures near/far
  views.

Earlier observed individual headless runs with other checks active: about 1.14 seconds
for a 1024×512 mesh, 2.27 seconds for a 1024² mesh, and 26.18 seconds for
100,352 real cells with a 256-edge mesh. A maximum-resolution constant-image save
with its graph occupied 24.73 MiB. These are not benchmark averages or frame-rate
claims; CPU/peak memory were not measured. Godot's native triangulator is slower
than browser Delaunator at large point counts. Use a modest total cell budget for fast edits. Prebuilding three terrain levels adds
CPU time and memory before interaction; no steady frame-rate guarantee is established.

Regenerate independent references with Godot's `tests/export_heightmap_graphs.gd`,
then Node 24's `tests/reference/compare-upstream.cjs <pinned-upstream-checkout>`.
The script executes the original TypeScript using Node's type stripping, not a
rewritten JS generator. Fixture metadata records the commit and source digests.
No Node installation or upstream checkout is required to run the game or the
checked-in parity test.

Province simulation, rivers, erosion, brushes, background generation,
full-world chunk streaming and the full grand-strategy game remain outside this terrain slice.

The fixed-LOD strategy test passes on Godot 4.7.2. The final small-graph test
prebuilt sixteen chunks in about 1.54 seconds on one run. An earlier GPU check of
the new renderer exercised a 4096×2048 world with 80,000 cells and roughly 533×
zoom; its prebuild was 6.91 seconds with concurrent checks active, before the final
shared-normal optimization. These are individual observations, not averages or
comparisons of equivalent cold/warm benchmarks. No frame-rate claim is made.

Shadows use an orthogonal directional map, 4096-pixel resolution, 32-bit depth,
medium filter quality and blur 1.5. The camera fits depth to the visible span plus
relief, then tightens close views using the fixed high-level heightfield. Its
conservative footprint includes both global height extremes and a four-cell halo
for coarse triangles. Queries above 8,192 samples retain broad safe coverage to
bound camera-update CPU cost. The range updates on zoom, pan and tilt. Existing 4× MSAA is preserved.
Optional GPU captures compare the previous broad camera range/split mode against
the tightened range/single map on identical terrain; the comparison does not
isolate the separate precision/filter project settings. Reference:
[Godot 4.7 shadows](https://docs.godotengine.org/en/4.7/tutorials/3d/lights_and_shadows.html).

Immediate headless editor shutdown previously logged two native transform errors;
clean immediate editor shutdown remains unverified. Runtime tests use real scene
initialization and teardown separately from this editor shutdown limitation.

Final GPU visual check: 32 chunks/three levels at 4096×2048, 80,000 saved cells,
5.09 seconds observed prebuild; the examined close view tightened from the earlier
696-unit far plane to about 185, with a 24-unit near plane. The remaining shadow
edge steps were visibly smaller in the captured steep-slope example; this does
not establish artifact-free shadows everywhere. The projection-coverage regression
checks all fine vertices visible in four overview/zoom/orbit/tilt configurations.

A preceding single run of the cached-world GPU comparison workflow measured
17.8 seconds wall time, 15.8 seconds sampled process CPU and 396.2 MiB sampled peak
Godot-process memory at 500 ms intervals. This includes startup, JSON validation,
initial terrain, cached-world loading, LOD generation and captures; it excludes
new 80,000-cell triangulation. Child-process/GPU memory and steady frame rate were
not measured. Cold/warm comparisons and agent-token costs were not measured.

The editor regression verifies that earlier hidden tuning cannot change
a newly generated map with identical inputs, custom image import stages safely,
original image metadata survives generation/loading, the overview is overhead and
flat, panning has a valid north/south axis, and zoom-in restores lighting and tilt.
Terrain quality, legacy document, source-image and fixed-LOD/camera checks passed
on Godot 4.7.2 after these changes. GPU captures also verified the simplified UI
and 2D/3D transition on the saved 80,000-cell 4096×2048 world.

The geographic stage now runs after height generation and before rendering. Its
height/smoothing source fingerprint permits reuse on unchanged terrain, while
LOD and camera movement do not touch component IDs or shoreline geometry. The
editor also exposes island shaping, relief and three live zoom controls. Shoreline outlines appear only with the
flat overview, and the ocean material uses the fixed geographic display-height
texture for depth colour. Temperature, wind and rainfall now come from the
[climate model](CLIMATE_REFERENCE.md) and bottom-right gizmo. Rivers and lake
outlets remain unimplemented.
