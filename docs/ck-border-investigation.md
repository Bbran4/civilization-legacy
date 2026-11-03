# Installed CK border investigation

Inspected local shipped files on 2026-11-03. Static evidence only; neither game
was launched and native geometry generation was not recovered. Game installation
paths are under `D:/Program Files (x86)/Steam/steamapps/common/`.

## CK3: named styles and zoom rules

`Crusader Kings III/game/gfx/map/borders/settings.txt:6-12` explicitly maps:

| Style | Texture | zoom_min | zoom_max |
| --- | --- | --- | --- |
| water | border_water.dds | 0 | 7 |
| province | border_province.dds | 0 | 10 |
| county | border_county.dds | 0 | 15 |
| domain | border_domain.dds | 0 | 20 |
| other_realm | border_other_realm.dds | 0 | 15 |
| sub_realm | border_sub_realm.dds | 0 | 9 |

These are game zoom values, not Godot camera multipliers.
`game/common/defines/graphic/00_graphics.txt:229-235` disables province/county
and sub-realm borders in flat-map mode, enables shoreline gradient borders,
and sets BORDER_POINT_MIN_HEIGHT to 3.0.

Decoded DDS observations (Pillow): province, county and other_realm textures
are each 85 x 86. Province artwork contains five small soft oval dashes across
the horizontal repeat. County artwork is a distressed thin double stroke;
other_realm has a broad distressed colored band and dark edges. These styles
are materially different, rather than one line with different thicknesses.

SHA-256:
- border_province.dds: d5133755ec5efabce21067c7c0118a0e6f4a853e83de56d1ab7ccef6eb4fd933
- border_county.dds: 2209e528fa3a0617912cbedb0a208d6d596b8e51008bb465700b98f0e0f85dc1
- border_other_realm.dds: 0a829cf58d5d2d5f329c7e80b60eaa32bc0dbef3ef66eafb0c8cdbd0bb762a64

`game/gfx/FX/pdxborder.shader` receives position and UV geometry, samples a
linear/mip-filtered border texture with U wrapping and V clamping, multiplies
alpha by _Alpha, blends terrain heights toward FlatMapHeight and adds
_HeightOffset. It enables depth testing, disables depth writes and uses depth
bias -30000 and slope-scale bias -2. These bias values are backend-specific.
`jomini/gfx/FX/jomini/jomini_flat_border.fxh` declares _HeightOffset, _UserId
and _Alpha plus input geometry, not geometry generation or width assignment.

## CK2: earlier evidence confirmed

`Crusader Kings II/gfx/FX/border.lua` samples diffuse and data textures at
(Input.uv.y * 0.1, Input.uv.x), blends two groups of RGB-mask tint colors using
data alpha, applies selection pulse and clamps vertices above water with a
camera-directed depth offset. This confirms longitudinal textured ribbons.
Decoded border0 (256 x 128), border1 (64 x 32) and border2 (128 x 64) are
continuous bands; their numbered gameplay assignments are not established.
See CK2_ASSET_REFERENCE.md for their prior hashes and the remaining inventory.

## Reconstruction implications and unknowns

For the requested tiny dashed look, CK3's named province texture is a direct
reference: short soft ovals with substantial gaps. The current Godot box-dash
pattern remains an approximation. Reconstructing an original oval opacity
profile and a separate county/realm style would be closer than shortening the
same rectangular dash. Source textures were inspected, not bundled as assets.

Native width, UV-distance scale, joins, fade interpolation and exact screen
appearance at each zoom remain unknown. Static texture dimensions do not
establish world-space dash length. No exact-match runtime claim is made.

## Paused CK2 realm-view observation, 2026-11-03

Live window capture timed out. Steam F12 screenshots succeeded after the user
started a paused game in realm view. Captures are 1920 x 1080. The date remains
1 January 769. Close, medium and wide views show shrinking realm ribbons and
internal borders as map coverage increases. This supports world-scaled geometry;
it does not recover a CPU width function or exact camera parameters. Keyboard
zoom events were not instrumented, so no numeric zoom ratio is attributed to them.

Screenshot sources below are local Steam screenshot files, not committed assets:

- D:\Program Files (x86)\Steam\userdata\151252713\760\remote\203770\screenshots\20261103222722_1.jpg SHA-256 513d317e0a806dc5ed35d922805f5c60d1f45c10d11329f4a9e1ddb1081eb9bb
- D:\Program Files (x86)\Steam\userdata\151252713\760\remote\203770\screenshots\20261103222802_1.jpg SHA-256 502988d66fa96a806d04ae73f74f08395e083ff45494ecbeb97791fbc48c1d63
- D:\Program Files (x86)\Steam\userdata\151252713\760\remote\203770\screenshots\20261103222828_1.jpg SHA-256 6f8b024b610a73f6017a2204a60a8015f880cc7cf6b90b31d17facaa25c75242

The close view visibly contains alternating heraldic colors on each side, rather
than one nation tint. Texture equality alone cannot reproduce those colors.
Exact six-tint assignment, UV scale, width and joins remain unresolved. No
pixel-identical replica claim is made.

Implementation correction: remove the 24-screen-pixel minimum; use a projected
24-reference-world-pixel ribbon. The latter is an authored value to address the
user's thin-band report, not a measured CK2 constant. Keep the narrow readability
seam but reduce its antialias footprint so it does not consume distant pigment.

Godot 4.7.2 GPU verification:
- smooth_province_borders_smoke.gd: PASS (colors, side orientation, dark cores).
- border_zoom_smoke.gd: PASS at orthographic camera sizes 96, 48, 24. Measured
  chromatic coverage per averaged scanline: 3.6705, 8.3723, 17.2497. Ratios are
  approximately 2.28 and 2.06 when map scale doubles. These are rendered color
  coverage measurements, not geometric widths or CK2 measurements. Texture
  filtering and alpha compositing affect this metric. Test accepts 1.6-2.4.
- Certificate-store and shader-cache write errors were emitted by the environment.
- Exact CK2 calibration, far subpixel comparison and performance are unverified.


## Superseding readability correction

The unbounded world-width implementation produced overlapping ribbons on the
user's tight real-map bends. It is superseded by bevel joins, an 8-18 pixel
screen-width range with an 8-reference-pixel world width, and a local curvature
limit. Province dashes are 2.4 pixels wide. The previous zoom-ratio test is
superseded by a rendered bounded-width test; no claim of exact CK2 scaling is
made for these authored limits.


## Final direction: nation fill and exact generated edges

The user superseded textured ribbons with nation-colored province fills and
solid national lines. The active renderer no longer references CK textures.
Borders follow every generated raster turn (collinear simplification only),
matching fill and picking. Ocean lines are thick and solid. Earlier tuning
measurements above document exploration, not current rendering constants.
