# CK2 asset reference for Civilization Legacy

Inspected 25 October 2026. This is a read-only, static reference investigation of the caller-selected installed CK2 map files and readable shader consumers. **Finish Stage 4 biomes now; apply the broader map-presentation overhaul later.** Hydrology has since been integrated, as supplied in the current task context. The existing [implementation manual](CK2-map-to-Godot-implementation-manual.md), including all 19 chapters and its limitations, was read; its older statements that hydrology is unconnected and its chapter 18 ordering are historical, not the current work order. This reference does not edit that manual.

**Observed** means bytes, decoded image metadata/pixels, parsed configuration or readable shader declarations examined here. **Derived** means reasoning from those observations. **Recommended** describes an original design for this game. **Unknown** marks behavior not established by these artifacts. No CK2 launch, executable decompilation, GPU capture or performance measurement was performed. REA MCP tools were unavailable in this session; the REA skill and connection/recovery guidance were read, and supported Python 3.14/Pillow 12.2.0, BMP/DDS/TGA header parsing, semicolon CSV parsing and a comment-aware brace parser were used. These are ordinary local inspection results, with no REA Evidence IDs. No installation or configuration changes were made.

## What Stage 4 should borrow

**Observed:** CK2 separates elevation, terrain material/class input, province identity, river input, coarse vegetation, broad colour, fine texture/normal detail and seasonal state. `default.map` explicitly names the corresponding files. `terrain.txt` provides categories with gameplay properties, then numbered texture-index mappings; it does not provide a rainfall/temperature biome generator. `climate.txt` is three province-ID winter lists, not a spatial temperature/moisture simulation.

**Derived:** ecosystem identity, surface appearance, canopy density and placed trees are different representations. The useful reference is that separation; CK2's authored bitmap colours are not a climate classifier to port.

**Recommended for Stage 4 now:** keep the existing generated climate as the biome authority and consume the integrated hydrology's water-body, active-channel and local-water-availability facts. Keep rainfall distinct from riparian moisture. Represent wetland/riparian suitability and dry-basin conditions explicitly; exclude open ocean/lakes and active channels from terrestrial vegetation. Keep biome type separate from canopy density and deterministic tree placement. Use stable map/cell identity and seed, habitat, slope and treeline constraints; persist intentional exclusions/overrides. Climate or water edits should update dependent ecology, while camera movement changes presentation only. Original vegetation assets and detailed seasonal rendering can follow the classifier milestone.

Acceptance ideas (proposed, not executed here): deterministic regeneration and save/reload; wet banks in suitable climates without turning every river into tropical forest; dry basins without permanent water; no trees in open water/channels or unsuitable cliffs; climate diagnostics retaining their numeric meaning.

## Terrain and vegetation classification evidence

All six requested BMPs were fully decoded. The five large rasters are 3072 × 2048; `trees.bmp` is 382 × 293. Its aspect ratio also differs, so the exact native sampling transform must not be assumed from dimensions alone. All BMP compression fields are BI_RGB (0). `topology.bmp` has 256 identity-grayscale palette entries and sampled values spanning 0–255. Native conversion of those values into engine elevation was not recovered. `world_normal_height.bmp` is RGB, with no fourth height channel; its name alone does not establish an additional encoded height field.

`terrain.bmp` contains 255 palette entries, not 256. The table combines actually used indices/pixel counts with explicit `terrain.txt` mappings. Display RGB is not the category identity. Configuration also declares index 13/14/15 as coastal desert and index 16 as forest; only 15 occurs among those four in this raster. The native applicability rules, including special water handling, were not recovered, so the mapping alone does not establish the effective terrain of every pixel/province.

| Used index | Pixels | Palette RGB | Configured type |
| --- | ---: | --- | --- |
| 0 | 801,303 | (86, 124, 27) | plains |
| 1 | 14,827 | (138, 11, 26) | farmlands |
| 2 | 128,835 | (130, 158, 75) | plains |
| 3 | 1,269,725 | (206, 169, 99) | desert |
| 4 | 196,523 | (112, 74, 31) | mountain |
| 5 | 409,577 | (255, 186, 0) | steppe |
| 6 | 737,051 | (13, 96, 62) | arctic |
| 7 | 93,648 | (86, 46, 0) | mountain |
| 8 | 332,964 | (0, 86, 6) | hills |
| 9 | 321,452 | (65, 42, 17) | mountain |
| 10 | 65,659 | (155, 155, 155) | mountain |
| 11 | 22,304 | (255, 255, 255) | mountain |
| 12 | 104,843 | (40, 180, 149) | jungle |
| 15 | 1,792,745 | (69, 91, 186) | coastal_desert |

`trees.bmp` uses indices 0, 2–12. `default.map` explicitly identifies **{3, 4, 7, 10}** as trees for automatic terrain assignment: 6,139 of 111,926 source pixels fall in that set. This declaration does not say that the other nonzero indices never render trees, nor that one source pixel equals one tree. Counts are source-image coverage, not canopy percentage or engine instance counts.

| Tree index | Pixels | Palette RGB | Declared automatic tree assignment |
| --- | ---: | --- | --- |
| 0 | 98,609 | (0, 0, 0) | not listed |
| 2 | 2,580 | (30, 139, 109) | not listed |
| 3 | 2,608 | (18, 100, 78) | yes |
| 4 | 2,129 | (8, 58, 44) | yes |
| 5 | 2,246 | (76, 156, 51) | not listed |
| 6 | 1,917 | (47, 120, 24) | not listed |
| 7 | 1,377 | (20, 85, 0) | yes |
| 8 | 145 | (154, 156, 51) | not listed |
| 9 | 55 | (118, 120, 24) | not listed |
| 10 | 25 | (83, 85, 0) | yes |
| 11 | 86 | (255, 255, 0) | not listed |
| 12 | 149 | (213, 160, 0) | not listed |

**Observed shader boundary:** [tree.lua](<D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II/gfx/FX/tree.lua:94>) accepts instance position/Y rotation and slopes, varies vertex height by 0.75–1.25 using supplied instance/UV values, rotates the mesh and adds slope displacement. Diffuse, normal, tint, broad colour and season samplers feed lighting, fog and snow. This establishes a rendering interface, not the CPU placement, species assignment, density conversion, culling, seed or batching algorithm. The season shader also has a map-position fade; it is not evidence of an ecological simulation.

`climate.txt` parses as mild/normal/severe winter lists with respectively 363/361/336 entries and 363/358/335 unique IDs. Duplicates are preserved as observed, not silently corrected. `seasons.txt` has four ground-season intervals plus eight tree-season intervals. Dates include literal `00.02.31`; these are CK2 configuration tokens, not validated Gregorian dates. Ground and tree transitions are distinct inputs. Shared snow functions interpolate seasonal channels and gate coverage using elevation, surface normal and noise; the runtime producer of those channels is unknown.

## Other requested families and later reusable layers

| Family | Observed coverage and implication | Remaining unknown |
| --- | --- | --- |
| Provinces/definitions | Full RGB raster/CSV parse: 2,016 raster colours, of which 2,014 match numeric definitions. White (478,487 pixels) and black (28,520) have no numeric definition match. CSV contains 14,148 unique numeric IDs/colours, IDs 1–14,148, plus blank-ID/blank rows; do not assume every definition is active. `default.map` declares `max_provinces = 2015`. | Native reserved-colour treatment and full runtime lookup production. |
| Rivers | Full indexed decode: used indices 0–12, 14, 15, 254, 255; counts/colours alone do not establish sources, junctions or width meaning. `default.map` separately lists major-river province IDs. `river.lua` samples riverbed/surface textures and animated normals with supplied geometry/tangent data. | Complete palette contract, bitmap-to-geometry algorithm and native routing. |
| Macro normals | `world_normal_height.bmp` is 24-bit RGB. `pdxmap.lua` separately samples `HeightNormal`, swizzles `.rbg`, recenters and normalizes, alongside detail normal samples. | Native sampler binding/normal generation and any filename-implied height semantics. |
| Colour/atlases | Broad terrain and water DDS colours are separate 3072 × 2048 RGBA images. Diffuse and normal atlases are 2048 × 2048 DXT5. `pdxmap.lua` declares 4 × 4 tiles of 512 pixels, combines up to four material samples using diffuse alpha, and overlays macro tint. | Authoring method, native TerrainIDMap production and actual pass selection. |
| Borders/corners/data | Every installed `border0`–`border5` diffuse/corner/data DDS and companion TGA was decoded and hashed. `border.lua` accepts geometry, blends RGB data-mask channels through two groups of tints using alpha, clamps above water, biases depth and adds selection pulse. Corner samplers are declared, but this inspected pixel path samples the main diffuse/data pair. | Native tracing/joins, corner routing and numbered-style meanings. |
| Positions | All 2,014 province blocks parse; each has 14 position numbers, seven rotation numbers and seven height numbers. These supply explicit anchors rather than a recovered automatic settlement placement algorithm. | Every slot's exact engine meaning and automatic label layout. |
| Adjacencies | All 315 semicolon rows parse with nine fields: header plus 314 records, comprising 249 `major_river`, 61 `sea` and four `portage` links. Through IDs and four coordinate fields are explicit data. | Runtime reachability/pathfinding semantics beyond these declarations. |

**Derived for later presentation:** keep stable province IDs independent of political colours, biome colours and mesh triangles; derive picking/borders/normal adjacency from one owner and retain explicit crossing links. Exact identity needs lossless discrete sampling; appearance fields can blend. Material weights, broad tint and fine normals can evolve independently of biome classification. Keep coast, beach, foam, province/realm borders and selection as separate styles. Use original authored textures and vegetation, not CK2's installed assets or shader code.

The border companions are not interchangeable: **`border5cornerdata.dds` is 1 × 1 while `border5cornerdata.tga` is 448 × 64**. Several other 1 × 1 DDS data files share a byte hash while their TGA alternatives differ. This is an observed shipped-file difference; active format preference and intended fallback behavior were not established. Preserve the distinction rather than combining by basename.

## Identity and per-file coverage ledger

Every file below was read in full for SHA-256. All listed images were opened and decoded; metadata is file/header evidence, not a runtime rendering observation. BMP palettes were inspected, including actual index histograms for terrain/rivers/trees. Text configs were parsed structurally; CSV rows were parsed with their delimiter. Shaders were read as shipped text, with no native binary analysis. DDS `mips` records the header value: 0 means no mip count declared, not a claim of zero image levels. TGA format includes image type and pixel depth. All paths are relative to `D:/Program Files (x86)/Steam/steamapps/common/Crusader Kings II`.

| File | Bytes | Format/dimensions | SHA-256 |
| --- | ---: | --- | --- |
| `map/topology.bmp` | 6,292,536 | 3072 × 2048 BMP 8-bit BI_RGB | `d9f587ef36e9760012c75765c0ad0fc21adf0487deddfb6b55e2b48438afae98` |
| `map/terrain.bmp` | 6,292,532 | 3072 × 2048 BMP 8-bit BI_RGB | `6039df4fcc61aad5595e62c78c8c1e7d6f3d707ccfeb1da22cd367fc4c890c02` |
| `map/provinces.bmp` | 18,874,424 | 3072 × 2048 BMP 24-bit BI_RGB | `e8359ec784f0b9f87c2c5ec8e61ebb60a1964f24aa471cddd6f8ee7e74c206f0` |
| `map/definition.csv` | 290,759 | semicolon CSV | `e31da8a80d67f64c730a2833207fbb9664459469f2bb70182125bf389915efe8` |
| `map/rivers.bmp` | 6,292,536 | 3072 × 2048 BMP 8-bit BI_RGB | `34c18f875b0b153b5edb8127a05e9e5e3053945440e01d3d029310c076b10011` |
| `map/world_normal_height.bmp` | 18,874,424 | 3072 × 2048 BMP 24-bit BI_RGB | `344b0bfc9b0462009e653c063b46a01783f9a4e170593032ca1b1f2c9884b9b1` |
| `map/trees.bmp` | 113,592 | 382 × 293 BMP 8-bit BI_RGB | `2ac144783f04ed0b45d5d0ac2b76ac8893bc57d74c675ac722460e493f1d4294` |
| `map/climate.txt` | 5,424 | text | `c7e4c5d67be95586c10b92d497b6b1060100051bbee71bb09e318a6db813ca86` |
| `map/seasons.txt` | 733 | text | `67ce57279d9cd86c5c71a9536b534505875daf78ab0b62caf4524b70172cebbc` |
| `map/positions.txt` | 543,606 | text | `5b65c2f5a037d105c516f2cba4e0f3afb7e213da2eb3e0c41393c639ce9234e8` |
| `map/adjacencies.csv` | 17,031 | semicolon CSV | `c090b1515e8ac155857dd93edfecb10dd785661232a062bea38bb3868b1447f7` |
| `map/default.map` | 2,592 | text | `311a9f00c2aa46d7963dbb368245bedc6dfd21fbd21990ee181727abba97c751` |
| `map/terrain.txt` | 3,512 | text | `3d9bb2e918989814eee9352c2f7132a0cd7a41798cfb2fabd046e173c3d435e6` |
| `map/terrain/colormap.dds` | 25,165,952 | 3072 × 2048 DDS BGRA8, mips 0 | `a29c4a3d9b8714ecf5ef59c1ee994354ddf03b955167bc7a5b65d361d49aaa3d` |
| `map/terrain/colormap_water.dds` | 25,165,952 | 3072 × 2048 DDS BGRA8, mips 0 | `e4ee89aac679a3217bc33034b42c70ead9866b4f513cbe2f18410f829b684677` |
| `map/terrain/atlas0.dds` | 5,592,560 | 2048 × 2048 DDS DXT5, mips 12 | `7140393a860e41c2a52bd5d546225218e32512315a3834b241623b0b0b48a263` |
| `map/terrain/atlas_normal0.dds` | 5,592,528 | 2048 × 2048 DDS DXT5, mips 10 | `81b26615e66e63d0f27e60c46994693b0d571d03e13a7fa8c6a1cf5330039f44` |
| `map/terrain/border0.dds` | 43,856 | 256 × 128 DDS DXT5, mips 9 | `325f8d36112332aaf6c567e7ae7ad84f6885a8f38146c2ab7c8d28ebd3b697df` |
| `map/terrain/border0corner.dds` | 43,856 | 256 × 128 DDS DXT5, mips 9 | `325f8d36112332aaf6c567e7ae7ad84f6885a8f38146c2ab7c8d28ebd3b697df` |
| `map/terrain/border0cornerdata.dds` | 144 | 1 × 1 DDS DXT5, mips 0 | `07398f7280aed1cdbcef6e7a4e91edb88d18369bfb62e317f59d6cfe015d712b` |
| `map/terrain/border0cornerdata.tga` | 48 | 1 × 1 TGA type 2, 32-bit | `43b609f80497959d1127b2a7f3f0fcaaea1322a8bd9f770eceeec4146d2d1ef0` |
| `map/terrain/border0data.dds` | 144 | 1 × 1 DDS DXT5, mips 0 | `07398f7280aed1cdbcef6e7a4e91edb88d18369bfb62e317f59d6cfe015d712b` |
| `map/terrain/border0data.tga` | 48 | 1 × 1 TGA type 2, 32-bit | `43b609f80497959d1127b2a7f3f0fcaaea1322a8bd9f770eceeec4146d2d1ef0` |
| `map/terrain/border1.dds` | 2,896 | 64 × 32 DDS DXT5, mips 7 | `e8709d22a4c7b69bf1a144782c92b681f66bb9173000c231b4d70f3dfbce2ecf` |
| `map/terrain/border1corner.dds` | 2,896 | 64 × 32 DDS DXT5, mips 7 | `e8709d22a4c7b69bf1a144782c92b681f66bb9173000c231b4d70f3dfbce2ecf` |
| `map/terrain/border1cornerdata.dds` | 144 | 1 × 1 DDS DXT5, mips 0 | `07398f7280aed1cdbcef6e7a4e91edb88d18369bfb62e317f59d6cfe015d712b` |
| `map/terrain/border1cornerdata.tga` | 48 | 1 × 1 TGA type 2, 32-bit | `b85ab0871721f062cbceeeafdf598170c9a519cf3395843979a0b0f6596e8b2c` |
| `map/terrain/border1data.dds` | 144 | 1 × 1 DDS DXT5, mips 0 | `07398f7280aed1cdbcef6e7a4e91edb88d18369bfb62e317f59d6cfe015d712b` |
| `map/terrain/border1data.tga` | 48 | 1 × 1 TGA type 2, 32-bit | `b85ab0871721f062cbceeeafdf598170c9a519cf3395843979a0b0f6596e8b2c` |
| `map/terrain/border2.dds` | 11,088 | 128 × 64 DDS DXT5, mips 8 | `fc053b6e9d4cbb9a1619a32e4b9810f505943d476912148f8355cb6dc705de62` |
| `map/terrain/border2corner.dds` | 11,088 | 128 × 64 DDS DXT5, mips 8 | `2a84f7dad26ffeabfa76729387e0bac870a892ec3ab7519a36b05f5d4b018ac7` |
| `map/terrain/border2cornerdata.dds` | 144 | 1 × 1 DDS DXT5, mips 0 | `07398f7280aed1cdbcef6e7a4e91edb88d18369bfb62e317f59d6cfe015d712b` |
| `map/terrain/border2cornerdata.tga` | 48 | 1 × 1 TGA type 2, 32-bit | `b85ab0871721f062cbceeeafdf598170c9a519cf3395843979a0b0f6596e8b2c` |
| `map/terrain/border2data.dds` | 144 | 1 × 1 DDS DXT5, mips 0 | `07398f7280aed1cdbcef6e7a4e91edb88d18369bfb62e317f59d6cfe015d712b` |
| `map/terrain/border2data.tga` | 48 | 1 × 1 TGA type 2, 32-bit | `b85ab0871721f062cbceeeafdf598170c9a519cf3395843979a0b0f6596e8b2c` |
| `map/terrain/border3.dds` | 11,088 | 128 × 64 DDS DXT5, mips 8 | `e3f79a5b9374471ccc5a95ec7526bb4ff55e8455be90e803fad7f2fcd14e99ef` |
| `map/terrain/border3corner.dds` | 11,088 | 128 × 64 DDS DXT5, mips 8 | `3ef15cc8d3631b752ac9b600053dd56449f29561a07563fe2776dfc61d339bac` |
| `map/terrain/border3cornerdata.dds` | 144 | 1 × 1 DDS DXT5, mips 0 | `07398f7280aed1cdbcef6e7a4e91edb88d18369bfb62e317f59d6cfe015d712b` |
| `map/terrain/border3cornerdata.tga` | 48 | 1 × 1 TGA type 2, 32-bit | `b85ab0871721f062cbceeeafdf598170c9a519cf3395843979a0b0f6596e8b2c` |
| `map/terrain/border3data.dds` | 144 | 1 × 1 DDS DXT5, mips 0 | `07398f7280aed1cdbcef6e7a4e91edb88d18369bfb62e317f59d6cfe015d712b` |
| `map/terrain/border3data.tga` | 48 | 1 × 1 TGA type 2, 32-bit | `b85ab0871721f062cbceeeafdf598170c9a519cf3395843979a0b0f6596e8b2c` |
| `map/terrain/border4.dds` | 11,088 | 128 × 64 DDS DXT5, mips 8 | `b9b884fda9c8169ac8430f7123d760e203da67970624c30ac471343e83dbda0f` |
| `map/terrain/border4corner.dds` | 38,448 | 448 × 64 DDS DXT5, mips 9 | `1ebfeb9442086916def61cfa24e6f667e3947f1652b72a722a9990a1622cbb49` |
| `map/terrain/border4cornerdata.dds` | 38,448 | 448 × 64 DDS DXT5, mips 9 | `8eb01e63211bb24a9cec69415affff47bc0931bade8599ca42709e77c4ce1012` |
| `map/terrain/border4cornerdata.tga` | 54,516 | 448 × 64 TGA type 10, 32-bit | `8eae7504ecdd5e932daf73252cf93539e250af2e753ffe5326b2c446d1598461` |
| `map/terrain/border4data.dds` | 11,088 | 128 × 64 DDS DXT5, mips 8 | `dfbbd021bcdaa89d2d3553be132ae521c78c7032c5c374e7296d806da1200666` |
| `map/terrain/border4data.tga` | 32,812 | 128 × 64 TGA type 2, 32-bit | `fb9d8199a6a197f2d0abc6329fdb1d6ea8cd033c4d1f2428e5d4a98dccf88bdd` |
| `map/terrain/border5.dds` | 11,088 | 128 × 64 DDS DXT5, mips 8 | `b8ef627f75846ecdd8293ca3593748ae3ca84538dcb37235bb308669e5aab909` |
| `map/terrain/border5corner.dds` | 38,448 | 448 × 64 DDS DXT5, mips 9 | `1ebfeb9442086916def61cfa24e6f667e3947f1652b72a722a9990a1622cbb49` |
| `map/terrain/border5cornerdata.dds` | 144 | 1 × 1 DDS DXT5, mips 0 | `07398f7280aed1cdbcef6e7a4e91edb88d18369bfb62e317f59d6cfe015d712b` |
| `map/terrain/border5cornerdata.tga` | 54,516 | 448 × 64 TGA type 10, 32-bit | `8eae7504ecdd5e932daf73252cf93539e250af2e753ffe5326b2c446d1598461` |
| `map/terrain/border5data.dds` | 11,088 | 128 × 64 DDS DXT5, mips 8 | `44f41a5fa05799007e81b650abe158cb6e83b1baa62f6868b1568ce6103bd819` |
| `map/terrain/border5data.tga` | 32,812 | 128 × 64 TGA type 2, 32-bit | `64d0ccf16afbb750166cd756b02b152109c8da2812630d53089c3937daa3dee8` |
| `gfx/FX/pdxmap.lua` | 16,575 | text | `b10fe10a987bb8730749085d3c223b952e104a8aac57dd55eca2a74d512142ec` |
| `gfx/FX/tree.lua` | 5,828 | text | `a263edfc6d905e5abd91f44a645723e4ef94734839099d590c4e5d2783bc3a20` |
| `gfx/FX/border.lua` | 4,128 | text | `00f41cd88a49fb7526ad17d78c28a387cc5af64a3cbefb8eb4dc80641f4984b8` |
| `gfx/FX/river.lua` | 6,209 | text | `15e5bbc6976f4110303def4bc327de1d35566e7b4d8545198069e3a3abf3d0c0` |
| `gfx/FX/pdxwater.lua` | 9,772 | text | `dd065cb712f14d67a8280de4cece187558ecff06d3604adbdedb2ff4e79e60bc` |
| `gfx/FX/standardfuncsgfx.fxh` | 7,691 | text | `1f78ae3f7ebc0a7819bfa6544419a837f2e29980156a786a037e54d8e334c97f` |
| `gfx/FX/pdxmap.fxh` | 511 | text | `7eda4814e5f720fe6c501a7cbadd7569510ea46cfb44ac876c684c7e2113c261` |
| `gfx/FX/constants.fxh` | 371 | text | `4406554cf3885dc577faf32ce1dc959c80be254c30fb166b0fe397d7906747e8` |
| `gfx/FX/mapname.lua` | 2,313 | text | `5894a230fa035df158722a20c1f7be787b152b3409aadd6fed7bab567eba2120` |
| `gfx/FX/restorescene.lua` | 4,019 | text | `d1b44149a9574ad2d96710a569d173e93c49b0ae1d3713346dff063cbfbb0fb9` |

No runtime reproduction, performance numbers or recovered native palette/placement algorithms are claimed. The reference is sufficient to guide original Stage 4 ecosystem layers; unresolved CK2 engine internals do not block that milestone. Only this new reference document was written by this investigation; installed CK2 files, current game changes and the existing manual were preserved.
