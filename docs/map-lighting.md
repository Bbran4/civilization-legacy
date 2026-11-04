# Map lighting and atmosphere

Terrain and foliage retain custom map lighting for stable province colors and
raw-height inspection. They now use Godot's directional light pass to receive
actual shadow attenuation, instead of bypassing it with `unshaded` materials.

`rendering/map_lighting.gd` now owns one presentation snapshot per renderer. It
reads the Sun's world direction, color and energy, plus the Environment's ambient
color/energy. `map_lighting.gdshaderinc` applies this same warm key/cool fill model
to terrain and trees. Both scenes have matching defaults and a downward-pointing
sun. The engine ambient/specular passes are disabled to avoid applying lighting
twice. Emission supplies the unshadowed fill; the custom light function supplies
the remaining palette color multiplied by directional shadow visibility. A single
Sun is the supported lighting setup; additional directional lights would add fill.

The terrain estimates shallow cavities from the existing relief-neighbor samples,
with at most 14% attenuation. The older forest-coverage contact darkening has been
removed now that actual tree meshes cast shadows. Terrain displacement and tree
root displacement run in the shadow pass as well. No terrain geometry, tree
placement or saved data changes.

Both scenes enable the Sun's filtered orthographic shadow map. Its atlas is 4096
pixels; bias/normal bias avoid the visible stripes observed with lower bias on
flat ground. The camera fits shadow distance to its existing depth range, turns
shadow rendering off in flat/raw overview, and restores it in relief. Shadow
opacity blends with relief. Maximum attenuation is 52% for ground/foliage and
political fills alike, so toggling provinces cannot change the underlying water's
shadow brightness in borders-only or unassigned areas. Border ribbons remain crisp. This
adds an actual shadow rendering pass; large-world frame-time cost is unmeasured.

Distance haze blends at most 10%, reduced by the viewing angle and relief blend.
An overhead overview receives none. The focus is anchored to the displayed ground
under the camera target, since the rig itself may retain overview altitude while
relief rises. Pan/orbit/zoom/resize refresh the snapshot using the existing camera
path; no extra per-frame forest rebuild is introduced. Scene-light edits are read
on the next camera/presentation synchronization, not polled independently.

Ground and foliage share haze. River/lake colors also receive it; water has a
muted palette and open sea uses source-height depth coloring. Political fills and
border ink are composed after the ground effects for legibility. Raw-height
inspection bypasses the tint, cavity shading, cast-shadow attenuation and atmosphere.
There is no engine fog or volumetrics. Shadow textures are managed by Godot.

`tests/map_lighting_smoke.gd` checks actual scene-sun direction, matching foliage
uniforms, clear overview, bounded oblique haze, ground-anchored pan focus, material
reuse, unchanged heights, gameplay bindings and GPU sun-direction/haze/raw-view
behavior. Captures are under `.test-runtime/lighting-relief.png`. Existing texture,
forest and raised-province-border checks cover the other shader consumers.

Validation uses the installed Godot 4.5.1 Mono/OpenGL Compatibility engine; exact
target 4.7 behavior and performance benchmarks remain unverified.

For cast-shadow verification, the process's `APPDATA` is redirected to
`<repo>/.test-runtime/godot-profile` before launching Godot. This gives the engine
a writable shader cache inside the test workspace; production cache settings are
unchanged. Earlier restricted-cache runs rendered even a minimal lit plane/cube
without working directional lighting and cannot establish cast-shadow behavior.
The writable-cache runs have no OpenGL initialization errors; the unrelated
certificate-store diagnostic remains.

`tests/cast_shadows_smoke.gd` requires a GPU. It compares mountain casting on/off
over separate flat ground, and tree casting on/off over ground pixels outside
visible leaves/trunks. The light and receiving material stay active in both
captures, so global darkening or slope lighting cannot pass as a cast shadow.
Captures: `.test-runtime/mountain-shadows.png` and `tree-shadows.png` with matching
no-shadow comparisons. This test completed with zero failures on the stated engine.
GPU texture, forest, lighting and zoom/border checks also completed with zero
failures using the writable test cache.

Executed: GPU map-lighting, automatic-texture, forest and zoom-relief checks all
completed with zero failures. The zoom-relief GPU check includes border ink over
raised terrain. `git diff --check` passed.
