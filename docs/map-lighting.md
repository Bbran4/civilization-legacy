# Map lighting and atmosphere

The terrain and foliage use unshaded map shaders to retain control over province
overlays and raw-height inspection. Previously their unrelated hardcoded light
directions ignored the scene Sun, while the camera managed unused shadow maps.

`rendering/map_lighting.gd` now owns one presentation snapshot per renderer. It
reads the Sun's world direction, color and energy, plus the Environment's ambient
color/energy. `map_lighting.gdshaderinc` applies this same warm key/cool fill model
to terrain and trees. Both scenes have matching defaults and a downward-pointing
sun. The old camera shadow toggles and unused scene shadow maps are removed.

The terrain estimates shallow cavities from the existing relief-neighbor samples,
with at most 14% attenuation, and forest coverage supplies at most 12% soft contact
shading in full relief. These are local artistic shading approximations; there
are no moving cast shadows, horizon tracing, screen-space AO or additional shadow
textures. No terrain geometry, tree placement or saved data changes.

Distance haze blends at most 10%, reduced by the viewing angle and relief blend.
An overhead overview receives none. The focus is anchored to the displayed ground
under the camera target, since the rig itself may retain overview altitude while
relief rises. Pan/orbit/zoom/resize refresh the snapshot using the existing camera
path; no extra per-frame forest rebuild is introduced. Scene-light edits are read
on the next camera/presentation synchronization, not polled independently.

Ground and foliage share haze. River/lake colors also receive it; water has a
muted palette and open sea uses source-height depth coloring. Political fills and
border ink are composed after the ground effects for legibility. Raw-height
inspection bypasses the tint, cavity shading and atmosphere. No engine fog,
volumetrics or new texture samplers are used by this pass.

`tests/map_lighting_smoke.gd` checks actual scene-sun direction, matching foliage
uniforms, clear overview, bounded oblique haze, ground-anchored pan focus, material
reuse, unchanged heights, gameplay bindings and GPU sun-direction/haze/raw-view
behavior. Captures are under `.test-runtime/lighting-relief.png`. Existing texture,
forest and raised-province-border checks cover the other shader consumers.

Validation uses the installed Godot 4.5.1 Mono/OpenGL Compatibility engine; exact
target 4.7 behavior and performance benchmarks remain unverified. This environment
emits generic OpenGL-startup and certificate-store diagnostics.

Executed: GPU map-lighting, automatic-texture, forest and zoom-relief checks all
completed with zero failures. The zoom-relief GPU check includes border ink over
raised terrain. `git diff --check` passed.
