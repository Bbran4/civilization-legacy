# Third-party heightmap sources

Inspected repository: https://github.com/Azgaar/Fantasy-Map-Generator

Pinned commit: `4305a1ab74515872db28b00f2f4f9c0c09f2a98c` (local clean checkout).

- [Heightmap operations](https://github.com/Azgaar/Fantasy-Map-Generator/blob/4305a1ab74515872db28b00f2f4f9c0c09f2a98c/src/generators/heightmap-generator.ts)
- [Graph placement](https://github.com/Azgaar/Fantasy-Map-Generator/blob/4305a1ab74515872db28b00f2f4f9c0c09f2a98c/src/generators/grid-generator.ts)
- [Voronoi adjacency](https://github.com/Azgaar/Fantasy-Map-Generator/blob/4305a1ab74515872db28b00f2f4f9c0c09f2a98c/src/generators/voronoi.ts)
- [Templates](https://github.com/Azgaar/Fantasy-Map-Generator/blob/4305a1ab74515872db28b00f2f4f9c0c09f2a98c/src/data/heightmap-templates.ts)
- Supporting helpers: `src/utils/probabilityUtils.ts`, `numberUtils.ts`.
- Display reference: `src/renderers/draw-heightmap.ts`, `heightmap-contours.ts`.
- Bundled source images: `public/heightmaps/{world,europe,mediterranean-sea}.png`.

The pasted user attachment matches the pinned heightmap generator after replacing
`Lattice.findSlot` with `Grid.findCell` and removing its Lattice import. These are
corresponding lattice lookups in the generation path. No attached source has been
silently substituted with a different terrain algorithm.

Azgaar code/data/assets are used under `Heightmap-MIT.txt`. Alea 1.0.1 is
credited under `Alea-MIT.txt`. `tests/reference/alea.cjs` is the original
package implementation, used only for independent development comparisons.

