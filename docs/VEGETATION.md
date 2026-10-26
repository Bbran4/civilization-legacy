# Tree population and editable assets

## Choose the number of trees

In the left map-editor sidebar, scroll to **TREES**, enter **Requested tree
population**, then press **Apply trees**. Zero removes all trees. The supported
range is 0-250,000. This replants vegetation and reloads the project's saved tree
assets without changing terrain, climate, drainage or the map seed.

The status shows **placed / requested**. The requested number is a target, not a
promise to fill water, cliffs or overcrowded ground. Suitable habitats, crown
clearance, root spacing and the placement work budget can reduce the actual count.
The earlier fixed/sparse population is replaced by sampling driven by the requested
count. The same small regression world that had 56 trees now has about 1,800 at a
20,000 target; a 6,000 target produced about 1,350. These are examples from one
terrain/climate, not a density guarantee or a measured Paradox comparison.

Version **9** map files save the applied population. Versions 1-8 still load,
using a 20,000 requested-tree default without changing saved source heights.
Apply pending changes before saving. The asset catalog belongs to the project,
not the portable map file; custom assets are not embedded in terrain documents.

## Edit a tree in Godot

The shipped models are ordinary editable scenes:

- `assets/trees/broadleaf.tscn`
- `assets/trees/conifer.tscn`
- `assets/trees/dry_woodland.tscn`
- `assets/trees/tropical.tscn`
- `assets/trees/wetland.tscn`

1. Open a scene in the Godot editor.
2. Edit the MeshInstance3D children under **Detailed**: move crowns/branches,
   change primitive meshes, assign imported meshes or change materials.
3. Edit **Distant** for the simplified version used farther out (hidden in the
   editor preview so it does not overlap Detailed). If it is absent,
   the renderer falls back to Detailed; an ordinary scene without either branch
   uses its root as the model.
4. Keep the trunk base at the scene origin, with Y pointing up. Scale the asset
   for the existing miniature world, not the map width.
5. Save it, return to the running map and press **Apply trees** to reload/rebake.

Static Node3D/MeshInstance3D geometry and transforms are baked for batched rendering.
StandardMaterial3D albedo colours, albedo textures, vertex colours and roughness
are supported; texture alpha is cut out for leaf cards. Arbitrary custom shaders,
scene scripts, skeletal animation and full PBR-material features are not replayed
per tree. These are batched static assets, not thousands of separately running nodes.

## Add desert, snowy or other variants

Open `assets/trees/catalog.tres`. Its **Definitions** array lists the available
TreeDefinition resources. The five matching `.tres` files beside the scenes are
editable examples.

1. Duplicate a tree scene and its definition, or create another definition using
   `scripts/rendering/tree_definition.gd`.
2. Assign the new scene and a readable label.
3. Tick its allowed biomes in **Biome mask**. Multiple definitions may share a
   biome; placement chooses seeded variants.
4. For places whose normal canopy is zero, such as deserts, tundra or icy peaks,
   set a small **Canopy floor** (for example 0.1-0.3). This is an explicit artistic
   override, not a change to the climate or biome label.
5. Set temperature limits and **Maximum slope** for the intended habitat. Ocean,
   active lake and river-channel exclusions remain enforced.
6. Set **Footprint radius** to cover the crown of the edited asset so it clears
   water and map edges, then add the definition to the catalog and Apply trees.

For snowy peaks, start with a conifer scene, edit its crown materials, enable Ice
and/or Tundra land, give it a nonzero canopy floor and restrict its temperature.
This does not add seasonal snow or put trees in frozen ocean cells. For dry regions,
start with dry_woodland and enable Hot desert/Cold desert as appropriate.

The Terrain node exposes **Tree catalog** if a project needs a different catalog.
Scene edits are reloaded from project resources. Maps do not load arbitrary asset
paths from terrain JSON.

![Dense scene-based trees and a nearby river](images/vegetation-close.png)

## Placement and rendering

Native cell identity plus the seed gives independent deterministic candidate
streams. Candidates are area sampled inside cell polygons, with continuous noise
creating clusters/clearings. Work targets twelve attempts per requested tree,
limited to one million overall target attempts and 8,192 per cell. The existing
0.6-world-unit root spacing prevents coincident trunks. If accepted instances exceed
the requested count, seeded priority selects the requested subset.

Biome canopy and per-definition overrides drive suitability. Trees require dry
footprints, valid slope and clearance from all three terrain height levels and
the actual rounded/clipped river corridors. Close models, simplified models,
spatial MultiMesh chunks, fading and shadows update without regenerating placement
on camera motion. In the flat overview, ground cover preserves habitat identity
while individual trees disappear. Diagnostic views and Show heights hide trees.
The inspector distinguishes potential canopy from the actual placed cell count.

Roots use full instance transforms, avoiding reduced-precision custom colour data
for large-map positioning. Tree and coast shaders share terrain height sampling.

## Verification and remaining work

Godot 4.7.2 Compatibility graphics checks cover deterministic JSON/file reload,
zero population, typed population controls, increased density, no terrain rebuild,
editable scene geometry, adding a desert asset with a canopy override, fixed zoom
placement, water/channel clearance, model detail, diagnostic visibility and
large-coordinate root following. Run:

```text
godot --path . --script res://tests/terrain_vegetation_smoke.gd
godot --path . --script res://tests/terrain_presentation_controls_smoke.gd
```

The dense 256 by 192 scenario took about 1.5 seconds for layout in one local run;
this is not a large-map or frame-rate benchmark. More trees increase generation,
instance, draw and shadow work. No exact Paradox quantity/visual parity is claimed.

Authored clearing masks, roads/settlement exclusions, growth, harvesting, fire,
seasonal snow/leaves and richer botanical art remain separate features. Project
asset edits intentionally change how existing maps appear. See
[presentation refinements](PRESENTATION_REFINEMENTS.md) for river and terrain status.

Godot references: [MultiMesh](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html),
[spatial MultiMesh groups](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html).
