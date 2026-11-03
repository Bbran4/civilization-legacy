# Province colors and borders

In Colored provinces view, assigned land provinces use their nation's color,
with terrain shading retained. Unassigned land keeps its generated province tint.
Borders only hides land fill. Editor and Play map share the same renderer.

Use Create nation color, select a land province, choose its nation, and press
Assign nation to selected province. Unassigned removes the assignment. These
edits respect the province lock, dirty the world, and survive save/load. Splits
inherit their source assignment and merges retain the kept province's assignment.

## Line styles

- Internal land boundaries: 2.4-pixel soft oval dashes.
- Boundaries between different nations, including assigned versus unassigned
  land: 3.5-pixel solid dark lines.
- Ocean-region borders and coast/water boundaries: 4.5-pixel solid dark lines.
- Unassigned deep ocean has no internal region borders.

National colors are province fills; there are no colored nation ribbons or
CK texture dependencies in the renderer.

## Thickness and natural contours

Under Provinces > Border appearance, set province dash, nation line and ocean
line thickness independently, and choose the zoomed-out percentage. Press Apply
border appearance and save the world. Zero hides that line type. The settings
are stored in terrain snapshots, including Play map, and older saves load defaults.

Natural contours reconstruct shared polygon boundaries across neighboring
province samples. Colored fills and lines use the same reconstruction; editing
and picking retain the original raster IDs. Turn it off to display exact pixel
edges. The reconstruction softens raster stair steps within generated regions;
it does not move boundaries to new rivers or ridges.

A cached 256 x 256 color lookup holds assigned nation colors by province ID.
It refreshes when the layer identity or border revision changes, including
nation assignment. Numeric IDs never interpolate. Province saves and editing
semantics are unchanged.

## Verification

On Godot 4.7.2, OpenGL compatibility:
- smooth_province_borders_smoke.gd: PASS, including optional exact raster-edge paths,
  nation-colored fills, correct color sides, dark lines, save metadata, editing,
  preview fallback and geometry caching.
- border_zoom_smoke.gd: PASS, checking continuous solid national and ocean
  borders at orthographic sizes 24, 12 and 6. Ocean lines are visibly thicker.
- border_appearance_smoke.gd: PASS, including controls and old/new save loading.
- province_contour_alignment_smoke.gd: PASS, including GPU fill/line side alignment.
- git diff --check: PASS.

The environment logs certificate-store and shader-cache write failures. The
rendered assertions pass. Complex authored maps and performance have not been
measured by these fixtures.
