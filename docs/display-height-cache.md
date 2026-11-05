# Display-height cache and fine terrain normals

The renderer prepares a source-resolution float32 field of **display heights in
local world units**. It reads the current base/conditioned ground, raises visible
hydraulic coverage to its surface level, applies world scale, and uploads an R32F (`Image.FORMAT_RF`) texture. Canonical source heights,
carved beds, water elevations, province IDs and saved formats are unchanged.
The existing sea clamp is applied **after interpolation**, in mesh sampling and
normal sampling. Clamping each stored texel first would subtly raise shore geometry;
that ordering is deliberately preserved. The display cache is transient; it is not
another authored world layer.

## Update and ownership

`display_height_field.gd` is a CPU-only job. Packed arrays are explicitly duplicated into isolated input snapshots. The worker creates the full-resolution display field
and samples its bounded relief grid. It never reads nodes or creates GPU resources.

`begin_update()` / `end_update()` batch changes. Heightfield regeneration batches
its initial base, active surface and water configuration into one final request;
ordinary layer refreshes also batch their setters. Large production requests
(above 513×513 samples) use `WorkerThreadPool`. Smaller jobs and standalone renderer
setters remain synchronous. The same full-resolution display field supplies fine
normal shading and the sampling source for the displayed mesh.

Only one worker and one newest queued request are retained. A height-source
revision, surface owner and hydraulic-content fingerprint identify the request.
Obsolete results are discarded. Water content changes invalidate the field even
when the water object is reused. Two prepared variants are cached, so repeating a
water/surface visibility configuration can reuse a field. Source replacement clears
the cache. Zoom, panning, lighting, textures and political colors do not rebake it.

Large replacements hide stale terrain, borders and forests and show **Updating
terrain view…**. Picking returns no hit during replacement. Completion publishes
both height textures on the main thread, restores forest presentation and updates
camera depth/lighting without marking the document dirty. Failed authoring jobs
never replace source data; display jobs only consume already validated inputs.
Tests/callers that need displayed geometry can await `terrain.wait_for_presentation()`.

CPU picking deliberately samples the **displayed mesh triangles**, not arbitrary
full-resolution heights between their vertices. Tree roots and draped borders still
use the same grid and diagonal. Source-resolution displacement/chunked geometry is
a later step; using that field as an unrelated picking surface now would disagree
with the visible mesh. Overview remains a cheap plane and raw height export stays
unchanged.

## Fine normals

`display_normals.gdshaderinc` takes central height differences from the full-resolution
world-height texture and divides by horizontal world distances. Edge derivatives
use the available one-sided interval. The sampling radius grows with the screen
footprint to reduce distant shimmer. These normals remain active at full relief;
the previous coarse-normal replacement has been removed. Existing lighting,
political overlays and terrain material placement remain shared with Play map.

Normals can show detail finer than the mesh; they do not add silhouette or river
channel geometry. The 512-cell mesh cap, coarse hydraulic limitations and colored
water overlay remain. Chunked LOD and separate water surfaces are not part of this
change.

## Measurements and remaining costs

A controlled 2050-square constant-height/wet fixture on the local Godot 4.7.2 setup
measured the old `set_heightfield` + water path at **1788 ms blocking**, versus
**197 ms submission**, **624 ms worker preparation**, **4 ms publication**, and
**830 ms total** for the batched path. Ninety-four scene-processing frames occurred
while waiting. This was one headless comparison, not an FPS or universal speed claim;
concurrent work and renderer state affect times.

The independent cache test observed approximately 172 ms submission, 351 ms worker
preparation and 25 ms publication in another run. Preparation has moved off the
main thread for large requests, not disappeared. Height normalization still scans
the source synchronously; GPU uploads and mesh/resource creation also occur on the
main thread. Height generation, forest reconstruction and file serialization have
separate costs. Maximum-setting frame time and peak process memory remain unprofiled.

At 2050 square each full float field is about 16 MiB. The cache retains at most two
such prepared fields plus their bounded mesh arrays; one active worker/newest queued
snapshot and the active GPU texture add memory. Input snapshots are isolated from producer mutations. Source changes can
temporarily overlap old/new buffers.

## Verification

- `display_height_cache_smoke.gd`: batch count, R32F field, source immutability,
  bed/water visibility, cache reuse, zoom invariance, same-owner hydraulic changes,
  2050-square background preparation and stale-result rejection.
- `display_normals_smoke.gd` (GPU): actual terrain lighting changes with fine normals
  at full relief; analytical world-scale ramp normal.
- `display_height_integration_smoke.gd`: large source replacement gates picking and
  forests, one final build, exact displayed picking and Play map reconstruction.
- Existing zoom/picking, forest, regional, texture, water and surface suites cover
  affected consumers. Async consumers await presentation before inspecting it.

The source-resolution cache is rebuilt from saved source data; terrain document v15
and world manifest v6 remain unchanged. Older document versions still follow the
existing validation/migration path.
