# Zoom-driven terrain relief

The renderer retains a four-vertex overview plane and a bounded relief-grid fallback.
Large sources now use [camera-dependent patches](chunked-terrain.md) with source-scale
close detail and matching CPU/GPU triangle sampling. The original fallback grid
remains bounded to 512 cells on its longest axis. A source/surface/water
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

Lighting now uses full-resolution display-height normals in world units at every
relief amount. The coarse grid still defines silhouettes, picking and draped lines;
fine normals improve shading without adding geometry. Dynamic cast shadows are
supported by the shared lighting path. Thin hydraulic geometry can still soften;
chunked distance LOD is implemented; separate water geometry remains later work.

Display preparation now batches source changes, caches two surface/water variants,
and prepares large fields in a worker. See [display-height caching](display-height-cache.md)
for implementation, measurements and update behavior. Source-file loading and height
normalization remain synchronous. This update is checked on Godot 4.7.2 with OpenGL.
The older executed-check list below records the original relief implementation.

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
