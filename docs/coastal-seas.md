# Coastal seas and borderless open ocean

Ocean provinces occupy a finite band near land. Unassigned water retains its
original depth colors and has no province IDs or internal borders. Borders-only
adds no water fill, even inside assigned provinces. Filled mode adds a 45% blue
tint only inside assigned sea regions. Vector borders remain crisp in either mode.
Province visibility never changes the underlying water's shadow strength.

After the height/water/surface/land workflow, select Provinces, choose Coastal seas
+ borderless open ocean, and Generate ocean borders. Reach controls the band width
in reference pixels at a 1025-pixel output; it scales with output resolution.
The supported reach is 8–256, default 64. Full-ocean modes partition all sea water.

## Enclosed regional seas

`sea_coverage.gd` owns the shared drainage/province rule. Edge-connected low water
is ocean. An enclosed below/equal-sea-level component covering at least 1% of the
map (minimum 16 samples) is a regional sea. This is an artistic map-generation
heuristic, not identification of named geographic seas. Large above-sea-level
lakes remain lakes. Smaller low-water basins retain inland-water provinces;
ordinary generated hydraulic lakes remain excluded from ocean provinces.

Drainage now treats regional seas as sea-level outlets instead of flooding them
to their surrounding land elevation. Province generation partitions these seas
with the same reach/count choices as open seas. One continuous sea can therefore
be surrounded by land without being skipped as a hydraulic lake.

Province payload v9 saves `enclosed_seas`. Older payloads load under their original
classification without rewriting IDs. Generate ocean borders explicitly upgrades
the sea policy, including old lake-masked low-elevation regional seas. Land IDs and
small inland-water IDs remain intact; obsolete large-basin inland IDs are retired
where ocean IDs replace them. Coastal reach still limits ocean coverage only.

For an existing world whose enclosed sea was flooded as a generated lake,
regenerate Rivers/lakes, Terrain surface, and Provinces, then Generate ocean borders
to rebuild the whole pipeline. Ocean-only regeneration can assign the sea-level
area against an older water mask, but does not rewrite saved water artwork.

## Data and validation

A source sea mask distinguishes unassigned sea from lakes and inland water, but
no longer supplies a backdrop color. Coastal-band growth uses a chamfer-distance
envelope. Coverage validation checks assigned coastal water, ID-free deep water,
land/inland/lake separation and exact source-mask coverage. Drafts own their mask
copies. Save/load retains exact IDs, archived records, names and edits.

`coastal_seas_smoke.gd` checks reach, finite coverage, land preservation, masks,
JSON/disk storage, legacy modes, and editor/gameplay parity. Its GPU path compares
assigned/unassigned water against the actual original artwork.
`enclosed_seas_smoke.gd` generates real enclosed-sea drainage plus a small lake,
checks coastal/full-sea provinces, legacy upgrade and JSON round-trip, then renders
both filled and borders-only views against the original water colors. Captures
are under `.test-runtime/enclosed-sea-{filled,borders}.png`.

Small-basin coverage is checked by `inland_water_provinces_smoke.gd`. Province
[split/merge tools](province-split-merge.md) retain their connectivity rules.
Validation uses installed Godot 4.5.1 Compatibility; target 4.7 is unverified.

Executed: enclosed-sea GPU checks passed, including both shipped Mediterranean
inputs; the full coastal editor/gameplay GPU workflow also passed. Inland-water,
water generation, ocean border editing, world-province and island/maritime checks
passed headless. Some older suites retain resource-cleanup warnings. GPU runs used
a writable test shader cache; the certificate-store diagnostic remains unrelated.
`git diff --check` passed. Maximum-resolution performance was not benchmarked.
