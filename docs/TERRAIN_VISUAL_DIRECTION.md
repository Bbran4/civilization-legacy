# Terrain visual direction and deferred weather

Recorded from the user's CK3 Egypt/Nile screenshot and discussion on 26 October
2026. This is a visual direction and proposed backlog, not a recovered CK3 renderer
or an implementation report. No CK3 installation/shaders were inspected for this
note; the screenshot cannot establish exact blending, channel or water algorithms.

## Material transitions: first pass implemented

Observed in the screenshot: broad green river-country and sandy desert regions
meet through irregular mottled patches, with smaller ground details inside each
region. This is a useful target for the game's terrain presentation.

The terrain now uses seeded world-space noise at three scales, bounded appearance
warping, normalized material patch weights and micro-height contacts. A shared
broader appearance colour/weight lookup now includes forest/dry-ground and desert
contacts that previously retained narrow, almost straight palette edges. Pigment,
roughness and fine normals use the shared material weights; wet ground, rock,
snow and beach contacts vary locally. Fine noise fades at distance. Source
climate, biome IDs, heights and water data stay authoritative and unchanged.

See [material implementation and executed checks](TERRAIN_MATERIALS.md). This is
original procedural work inspired by the reference, not a recovered CK3 shader.
The starter textures still need authored art and further visual tuning.

## Rivers: connected water and physical channels

Observed in the screenshot: the broad main river has a visible water footprint,
banks, connections to the sea and associated green/wet lowlands. Smaller channels
and irregular wet areas contribute to the floodplain. Bright white outlines also
trace other boundaries; they should not automatically be treated as water foam.

Current rivers are depth-tested, animated surface ribbons trimmed at receiving
water shores. They do not yet excavate a channel through the terrain. Correcting
occlusion and mouth overlap was necessary, but does not finish physical riverbanks.

Proposed channel pass:

1. Preserve the original source heightmap; derive a separate carved/rendered bed
   with explicit generation settings and invalidation.
2. Give major rivers channel width, bed depth, banks and floodplain shoulders from
   drainage/flow and authored constraints. Minor streams can use smaller surface
   meshes over appropriately shaped beds.
3. Treat rivers, lakes and oceans as a connected water system with compatible
   shore/material transitions. Rivers need changing elevation downhill; lakes and
   seas retain their own surface levels.
4. Rebuild affected terrain LODs, normals, water coverage and vegetation exclusions
   from the same derived bed. Recheck drainage receivers, lake sills/outlets,
   confluences and dry basins after carving instead of preserving stale routing.
5. Add explicit cliff-drop geometry and spray/plunge-pool presentation where the
   bed and water profile support a waterfall. Current slope-driven foam is only
   an initial cascade treatment.
6. Consider deltas, distributaries and seasonal floodplain water separately from
   the current single-downstream drainage model. None is implemented by this note.

A channel still needs rendered water geometry/materials. The important change is
that terrain supplies an actual opening and banks, so the water belongs to the
landform instead of appearing painted across its top.

### Later river-authoring reference

The user supplied [a modder's Game of Thrones map video](https://www.youtube.com/watch?v=5Pk-2gKdkSs)
and described rivers being drawn in Photoshop/Illustrator before importing into
the map editor. The video fetch failed, so its contents were not independently
verified. Keep authored river masks/import alongside procedural channel generation
as a future design option. This terrain-blending change includes no river work.

## Deferred: clouds, shadows, storms and rain

User preference: keep these ideas for **after natural terrain is finished**.
This note records the ideas only; no weather code or renderer change is included.

A practical first visual pass for the existing Compatibility renderer could use
layered cloud planes/cards with moving noise/opacity. A shared cloud-coverage
field would drive both visible clouds and soft projected shadows. Shadow placement
would use sun direction and cloud altitude, and terrain/water/vegetation would use
the same coverage timing. The shadows should affect scene lighting while keeping
UI, selection and diagnostic views readable. These would be projected visual
shadows, not a claim of simulated volumetric cloud scattering.

Wind can advect the patterns. Cloud density/type/speed and shadow softness can be
art directed before adding a full atmospheric model. Later weather cells could
supply storm coverage, local rain particles, lightning, sound, wet ground and
wind changes. Local/camera-near particles would avoid filling an entire strategy
map with rain geometry.

Keep annual climate and short-lived weather distinct. Existing rainfall is an
annual estimate, not a storm timer or rain-per-second input. Any eventual storm
feedback into river runoff, lake storage or flooding needs explicit time/units,
water-balance rules and save-state ownership. Begin with visual weather if those
simulation decisions are still pending.

Godot's built-in volumetric fog is available in Forward+, not Compatibility;
[the Godot 4.7 Environment reference](https://docs.godotengine.org/en/4.7/classes/class_environment.html)
documents this limitation. Layered cloud geometry and custom projected shadows
are a proposed alternative for this project. No hardware performance or rendered
prototype has been measured for the cloud proposal.

## Work ordering

The first material transition pass is implemented. Before weather: physical river channels/banks,
water integration and the remaining snow/ice terrain work. Preserve the existing
editor, adjustable assets, seeded generation, fixed LODs and flat overview.
Weather remains a later optional presentation/simulation layer, not a dependency
for completing the terrain.
