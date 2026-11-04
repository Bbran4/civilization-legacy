# Zoom-driven terrain relief

The existing map renderer now owns two cached meshes: a four-vertex overview plane
and a relief grid bounded to 512 cells on its longest axis. A source/surface/water
change prepares the relief heights; camera movement and zoom only update uniforms
and select an existing mesh. No saved generation field is modified.

`terrain_map_renderer.gd` constructs presentation heights from the active base or
hydraulic surface, raises visible water to its hydraulic levels, and clamps ocean
relief to the sea datum. It samples source textures with their existing texel-center
convention. The prepared world-height grid is exposed both to CPU picking and to
`map_relief.gdshaderinc`. Both use the displayed mesh's triangle diagonal, avoiding
a separate high-resolution approximation that would disagree with the geometry.

The camera blends overview to relief between zoom 1 and 3. Ray picking intersects
only the map bounds, marches at half-cell horizontal intervals and bisects the first
surface crossing. The flat/raw mode keeps its plane shortcut. Zoom anchoring updates
the anchor's height when relief changes. Culling/depth bounds include raised terrain.

Province ribbons and authoring previews are split at grid edges and triangle
diagonals using `heightmap_grid.gd`, then lifted to the same height grid. Changing
zoom does not rebuild these paths. Ground brushes now use displayed-surface hits.

Lighting blends the existing hillshade normal with a world-scale relief normal.
This retains the map's current palette and paint composition. The material remains
unshaded by Godot lights, so dynamic cast shadows are not claimed. Fine source
features below the capped grid resolution and thin hydraulic features can soften.
There is no chunked distance LOD in this implementation. Source-file loading remains
synchronous. No CPU/memory/frame-time benchmark is claimed.

Validation uses Godot 4.5.1 Mono, including an OpenGL render and captured views.
Exact project-target Godot 4.7 behavior remains unverified. The dedicated zoom smoke
check uses a controlled height/hydraulic fixture; the map-paint integration check
also exercises actual generated water, surface and province layers in the shared
renderer. The engine reports certificate-store and generic OpenGL initialization
diagnostics in this environment; successful assertions are reported separately.

## Executed checks

- `zoom_relief_smoke.gd`: zero failures with graphics rendering. Checks flat,
  intermediate and full relief, CPU/GPU geometry conventions, camera picking,
  painting on a tilted surface, raw-view restoration, water elevations, retained
  source data, cached mesh reuse, bounds and a political border rendered on a ridge.
- `province_geography_alignment_smoke.gd`: zero failures.
- `province_contour_alignment_smoke.gd`: PASS.
- `smooth_province_borders_smoke.gd` and `border_zoom_smoke.gd`: PASS.
- `map_paint_smoke.gd`: zero failures; captured the actual generated world in relief.
- `heightmap_focus_smoke.gd`: PASS headless.
- `git diff --check`: clean.

The complete historical suite was not run. This is geometry and interaction
verification, not a claim of measured performance or finished terrain art.
