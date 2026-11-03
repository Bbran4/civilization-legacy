# Independent rivers/lakes layer and expanded resolution

## Workflow

1. Generate the heightmap. Output resolution now accepts any whole number from
   256 through 2050 pixels on its longest edge; aspect ratio is preserved. The
   existing document stores grid cells, so the chosen pixel count minus one is
   stored as resolution. The default remains 1025 pixels.
2. Select **Rivers / lakes** in the layer stack. Choose drainage detail, density,
   width and lake filters, then press **Generate rivers / lakes**.
3. Use the visibility checkboxes to inspect terrain alone, water alone, or both.
   Lock the approved heightmap while generating water. Locking water also protects
   its source from being regenerated through the editor.
4. **Play map** loads the same height and water data with the shared renderer.
   Editor raw-height inspection hides water and does not change gameplay shading.
5. Save terrain/world normally. **Export water PNG** writes transparent blue water
   artwork separately; heightmap PNG export remains raw grayscale elevation.

Water generation is explicit. Creating/loading a heightmap with no water layer
never automatically generates rivers or lakes. Trees, climate/biomes, ground
painting and provinces remain disabled.

## Water controls

- Drainage detail: 257, 513 or 1025 routing samples along the longest edge, capped
  at the source map's resolution. Higher values follow smaller valleys. The final
  water image always matches the full heightmap resolution, up to 2050 x 2050.
- River density: includes more or fewer tributaries by changing the contributing
  runoff area required to form a visible channel.
- River width: base headwater width, widening with accumulated downstream flow.
  Width scales with output resolution, preserving geographic appearance; its
  reference unit is pixels at 1025 output, with a small antialiasing minimum.
- Minimum lake depth: normalized elevation difference needed to retain a lake.
- Minimum lake area (%): filters small puddles by fraction of the whole map.

The count shown is river sections between starts, joins and endpoints, rather
than a count of individually named rivers. Water settings are staged until the
Generate button is pressed.

## Generation and appearance

`terrain_water_layer.gd` reads the shared renderer's canonical normalized height
field. It resamples that field onto a bounded drainage grid, identifies connected
sea, and uses priority-flood routing for depressions and flats. Uniform runoff
accumulates downstream on an acyclic drainage network. This stage does not depend
on climate or alter any height sample.

Candidate lakes are re-flooded against the full-resolution saved heightmap, so
shorelines follow actual elevation contours rather than enlarged drainage cells.
Candidates that escape their local basin on the detailed raster are rejected.
River chains retain shared confluence endpoints, use corner-cut smoothing, and
are rasterized as antialiased variable-width channels. Inlets/outlets connect to
retained lakes, and river drawing stops at the sea datum.

The shared editor/gameplay shader composites the water mask over shaded terrain.
Relief contrast is normalized to output resolution; the existing 1025-pixel
appearance is unchanged. No water geometry is baked into the heightmap or terrain
PNG. Blue PNG export uses transparency outside water; project storage retains a
lossless RGBA coverage mask independently from the height data.

## Changes, locks and background work

Generation runs on a worker thread using an immutable copy of the source field.
The editor stays responsive. Play map waits for generation to finish. A result is
installed only if it still matches the current terrain and document, and the layer
is currently visible and unlocked. Opening a new document invalidates the pending job even when the
new document has identical heights.

If the heightmap changes after water was generated, the existing artwork is
retained but hidden as stale. The stack shows an asterisk and the layer panel
explains that regeneration is needed. Saving preserves this retained artwork;
loading does not present stale water as current. Restoring identical source data
can make the retained layer current again. No generated layer silently rewrites
another layer's payload.

## Storage and compatibility

Terrain documents retain version 10 with an optional `water_layer` section:
versioned settings, source fingerprint, dimensions, counts and a lossless mask PNG.
Loading/restoring a generated layer does not reroute it. Old documents without
water remain readable. Existing world snapshots and legacy source saves are not
overwritten by Save world.

The bounded terrain document limit increases from 64 to 256 MiB to accommodate
2050-pixel float fields, optional imported source data and water artwork. Layer PNG
size/dimensions are checked before decoding. Focused raster rendering supports the
new maximum, while the retained legacy mesh pipeline stays capped at 1024 cells
and rejects higher-resolution documents before applying them.

Maximum-size roundtrip testing exposed a pre-existing signed-zero boundary
fingerprint problem in the geographic cache: JSON represents -0.0 as 0.0. Graph
fingerprints now canonicalize these equivalent coordinates. A narrowly verified
legacy-boundary compatibility path also accepts older affected caches without
relaxing source-graph integrity checks. Height values and geometry are unchanged.

## Validation

- `terrain_water_layer_smoke.gd`: deterministic drainage, downhill/cycle-free
  routing, runoff conservation, real lake basins, variable widths, immutable
  heights, independent visibility/locks, disk roundtrip, stale-state retention,
  gameplay handoff and actual GPU overlay visibility.
- `terrain_water_resolution_smoke.gd`: exact 2050 x 2050 output and matching water,
  bounded plane rendering, disk restoration at maximum size, changed-source and
  replaced-document background safeguards, signed-zero cache compatibility and
  rejection of tampered cache geometry. Minimum 256-pixel output is also covered.
- Shared-renderer GPU parity, focused heightmap, world save workflow, terrain
  editor, legacy terrain/hydrology, geography cache and native-template parity
  regression scripts.

## Remaining work

Routing currently uses uniform rainfall and filled-depression drainage, not a
climate/water-budget simulation. Drainage detail is deliberately bounded at 1025
samples even when the rendered artwork is 2050 pixels. Rivers are visual channels;
they do not carve the terrain. Manual river/lake painting, vector editing,
per-feature naming, deltas and waterfalls are future work. Visual/performance
review and approved map benchmarks remain with the user.
