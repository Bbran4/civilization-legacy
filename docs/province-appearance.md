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

## Alignment and ownership

Border paths trace the generated province ID raster. Only exactly collinear
points are removed; no smoothing or corner-cutting moves the border. Fill,
selection and picking use those same discrete IDs. This prioritizes agreement
with generated coverage; raster stair steps remain visible at extreme zoom.
Lines use bevel joins and fixed screen widths so they remain readable without
expanding into large overlapping bands at close zoom.

A cached 256 x 256 color lookup holds assigned nation colors by province ID.
It refreshes when the layer identity or border revision changes, including
nation assignment. Numeric IDs never interpolate. Province saves and editing
semantics are unchanged.

## Verification

On Godot 4.7.2, OpenGL compatibility:
- smooth_province_borders_smoke.gd: PASS, including exact raster-edge paths,
  nation-colored fills, correct color sides, dark lines, save metadata, editing,
  preview fallback and geometry caching.
- border_zoom_smoke.gd: PASS, checking continuous solid national and ocean
  borders at orthographic sizes 24, 12 and 6. Ocean lines are visibly thicker.
- git diff --check: PASS.

The environment logs certificate-store and shader-cache write failures. The
rendered assertions pass. Complex authored maps and performance have not been
measured by these fixtures.
