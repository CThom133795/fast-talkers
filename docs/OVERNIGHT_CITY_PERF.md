# Overnight city pass: draw calls, audit, lived-in clutter

Branch `cloud/overnight-heavy-lift`. Cloud container, **no GPU**: every number below comes from
`tests/capture_perf.gd` under Xvfb with Mesa llvmpipe (software OpenGL 4.5, Godot's
Compatibility renderer, the project's configured renderer). Draw-call, object and primitive
counts are renderer-side counts and are meaningful here: the baseline midtown figure (1,741)
matches the lead's earlier GPU figure (1,746). **Frame times are software-rendered and NOT
representative** of any real GPU; they are listed only for completeness. Nothing here was
validated on a GPU or on Windows.

## What costs draw calls in this city

A headless proxy (visible surfaces inside each view's frustum) counts only ~370 surfaces for
the midtown view, yet the renderer reported 1,741 calls. The difference is the sun's
shadow pass (4 PSSM splits at the default "high" shadow setting, 95 m range): every
shadow-casting surface of every merged district mesh is drawn again per split, and a merged
district has one surface per material (often 10-30). The Compatibility renderer also adds a
lighting pass per surface for each omni light (neon signs) touching an object.

## Changes

| Change | File | Why |
|---|---|---|
| `MeshMerge.shadow_proxy(node)`: after merging, all direct static shadow casters of a node (merged meshes and the instanced window/kerb batches) are copied into one positions+normals mesh drawn `SHADOWS_ONLY`; the visible pieces stop casting. | `scripts/mesh_merge.gd`, called from `world._finish` | Same shadow silhouette, but the shadow pass costs one draw per split per node instead of one per material per split. Pieces with children (doors, pivots), a visibility range, alpha, or a non-default layer keep their own shadows. |
| Clutter renders on `CLUTTER_LAYER` (3); the neon street lights' `light_cull_mask` skips that layer. Clutter never casts sun shadows; solid clutter gets a contact patch. | `scripts/world.gd`, `scripts/city_detail.gd` | A merged 60 m clutter cell otherwise takes an extra light pass per surface for every nearby neon (measured: +250 calls in Lantern Row, down to +8). |
| Clutter uses five shared materials. | `scripts/city_detail.gd` | Each cell merges to at most five surfaces. |
| `world.set_potato_mode(enabled)` + group `potato_optional` on decor cells. | `scripts/world.gd`, `scripts/city_detail.gd` | Minimum-PC toggle (lead wires the button): hides collision-free dressing and shortens detail ranges; colliders untouched. |
| `capture_perf.gd` accepts `-- views=a,b settle=N sample=N`. | `tests/capture_perf.gd` | Quick A/B runs of the counts in about 40 s instead of ~5 min. Defaults unchanged. |

## Before / after (software GL, 1280x720, dusk, default settings)

Before = the lead's baseline run on this branch (`scratchpad/perf_baseline.txt`, settle 30 /
sample 60; it timed out before the last two views, whose GPU figure from
`docs/CITY_DETAIL_HANDOFF.md` is given in brackets). After = this pass including the new
clutter (settle 10 / sample 5; counts do not depend on the sample length). The After column
also contains the lead's concurrent club-interior work in `scripts/buildings/*`.

| View | Before (baseline) | Shadow proxy removed (A/B, same tree) | After (proxy, first clutter) | **Final** | Final vs before |
|---|---:|---:|---:|---:|---:|
| midtown | 1,741 | 1,769 | 1,231 | **1,235** | -506 (-29 %) |
| midtown_north_long | 2,027 | 2,042 | 1,495 | **1,499** | -528 (-26 %) |
| harbor | 904 | 926 | 632 | **639** | -265 |
| strip_beach | 1,264 | 1,338 | 828 | **832** | -432 |
| lantern_row | 835 | 861 | 623 | **648** | -187 |
| uptown | 906 | 960 | 616 | **639** | -267 |
| motor_mile | 1,739 | 1,816 | 1,069 | **1,237** | -502 (-29 %) |
| nightlife | 1,360 | 1,462 | 882 | **892** | -468 |
| gunstore | 1,593 | 1,620 | 1,059 | **1,079** | -514 (-32 %) |
| exchange_interior | [1,693 GPU] | 1,699 | 1,090 | **1,094** | -599 vs GPU figure |
| aerial | (not reached) | 1,831 | 1,402 | **1,495** | -336 vs A/B |

Final objects per frame: midtown 2,181 (before 2,377), motor_mile 1,877 (2,379), gunstore
1,714 (2,228). The "shadow proxy removed" column is an intermediate tree (with the first
clutter and the lead's club work) with only `MeshMerge.shadow_proxy` disabled; it isolates
the proxy's effect at 500-770 calls in the busy views. Motor Mile rose 1,069 -> 1,237 between
my runs while the lead's plot work (garage/motel/burger, next to that view) landed; an A/B with
all clutter disabled on the final tree gives 1,219, so the clutter itself costs +18 there.
Software frame times (not representative): 250-550 ms.

Clutter cost on Lantern Row: +250 calls before the clutter layer / neon cull-mask change, +8
after it; the final full-density dressing (posters, window AC units, shutters, clocks...)
costs about +20-25 calls in the views where it is dense.

Old target: every street view at or below ~1,550 draw calls; all measured views now meet it.
The user has since relaxed the budget to "RTX 3080 at 60+ fps"; the savings leave room for
detail and a potato mode (below) covers minimum PCs.
Primitive counts rise slightly (~5-10 %) because the shadow proxy also carries the
instanced windows; triangles are cheap next to draw calls here.

## Anti-slop audit: `tests/city_audit.gd`

Headless, `extends SceneTree`, prints `CITY AUDIT RESULT: N checks, M failures`
(run with `bash tests/run_all.sh city_audit`; it is not yet in run_all's default list).
Checks:

1. Every public-space prop's lowest solid rests on the surface around it (sampled just
   outside the prop); alley dumpsters sit on their ground; payphones stand on pavement.
2. Road centrelines have no physical step (kerb/plinth/berm on the carriageway), bridges and
   road ends excluded.
3. Every non-lift, unlocked door: a 0.28 m capsule sweeps from `inside` to `outside` with the
   door leaf's own bodies excluded.
4. No large (font >= 40) sign text appears more than three times.
5. Every public space has at least four pieces of furniture.
6. At least 40 clutter pieces, and none on a road, within 2.5 m of a door, within 4 m of a
   crew spawn/car/HQ, or within 3 m of a parked car (oil stains may sit in bays).
7. Coast rails: a horizontal 1.62 m (standing eye) shot across each mainland edge clears the
   1.12 m rail; a 0.2 m shot meets the coping (docs/RAILING_COLLISION_NOTES.md).
8. No solid prop (box up to 3 m tall / 8 m long, not a thin wall) starts below a 0.16 m
   plinth's top; props inside trademark plots are printed as REPORT lines for the lead.
9. Potato mode: decor cells are grouped, carry no collision, are hidden by
   `set_potato_mode(true)` and the collision-body count is unchanged; clutter has >= 12 kinds.
10. Static districts use a single shadow proxy.

### Found and fixed

- **Plinth on North Shore Road** (world.gd, Canal Market): both bank blocks' plinths reached
  onto the road's curve at x -228/z -206 and x -104..-95/z -210..-203 (a 0.16 m kerb on the
  carriageway). Blocks now stop at z -205 (west) and z -201 (east); the fish hall and lofts
  still sit inside them.
- **Floating furniture on Sunset Picnic Lawn** (city_detail.gd): benches, cart, bin and path
  sat 0.16 m above open grass (they assumed a plinth). Each site now lifts to the recorded
  surface height (`world.surface_height`, fed by every `_slab`).
- **Copy-pasted shop signs** (world.gd `_fill_block`): DELI and TIMBER YARD each appeared 4x.
  Same random draw as before; a third copy of a generic sign becomes the least-used option.
- **Empty West Bank Promenade** (city_detail.gd): only a cart and a newsstand; now three
  benches and a bin along the walk.
- **Coplanar cross paths** (city_detail.gd): the two paving arms of each park shared a top
  plane over their 2.4 m crossing; the second arm now sits 4 mm higher.
- **Sunk props** (world.gd): Old Wharf and South Docks container yard stacks, three Midtown
  street trees, the Fish Hall loading counters and the West Bank Plaza statue started at y 0
  inside a 0.16 m plinth; they now stand on it (`_container` lifts ground-level stacks by the
  surface height).
- **Rooftop plant overlap** avoided: new condensers take the roof quadrant opposite the
  existing `_rooftop` tank/box (recorded per roof).

### Found, not fixed (outside this pass's files or needing a layout decision)

- **Gun store range berm on Coast Road** (`scripts/buildings/gunstore.gd` line ~125,
  `kit.box(Vector3(YARD_X0 - 3.0, 0.7, ...), Vector3(4.0, 1.4, YARD_DEPTH), earth, true)`):
  the solid 4 x 1.4 x 80 m berm centred at world (332.0, 0.7, -95.0) spans x 330-334,
  z -135..-55, and Coast Road's carriageway (centre x ~336.5, 12 m wide) covers x ~330.5-342.5
  there: a 1.4 m wall inside the road's west lane. Lead-owned file; audit lists it as KNOWN.
- **Strip ring's south-west corner vs beach revetment** (world, road layout): the rock
  revetment (1.0 x 0.72 m, centre (30.3, 0.36, 405.2), along the beach edge (37,410)-(24,400))
  crosses the STRIP RING road's corner at (24, 400). The ring is derived from the Strip kit
  frame; fixing it means moving the ring or clipping the road ribbon at the coast. Left as
  KNOWN in the audit.
- **Plot props sunk into the 0.16 m plinth** (lead-owned `scripts/buildings/*`, reported by
  the audit as REPORT lines, not failures): burger (108.0, 0.5, 70.0), (114.0, 0.4, 52.0),
  (126.0, 0.4, 52.0); nightclub (91.0, 0.5, 226.0); motel (176.0, 0.4, 21.0),
  (164.0, 0.4, 21.0); hotel (181.0, 0.3, -162.0), (169.0, 0.3, -162.0), (163.5, 0.4, -162.0).
  Each is a solid box whose bottom is at y 0 on a 0.16 m plinth (planters/props set 16 cm
  into the pavement). Cosmetic.
- **Velvet Room backstage door** (index 27 at the time): on the first audit run a capsule
  from inside to outside was blocked by a Stripclub StaticBody at (147.4, 0.1, 250.3); it
  passed on later runs while the lead was editing `stripclub.gd`, so re-check after that work
  lands (the audit covers every door).
- Harsh texture tiling and CRT TVs in shop windows were not addressed.

## Lived-in clutter (static, deterministic)

Everything below is built in `CityDetail._clutter()` after every other builder (seeded
`world._rng`, fixed creation order; parked vehicles untouched), placed through the existing
`can_place` rejection (roads plus shoulders, footprints, doors, crew spawns, parked cars, other
props), and merged into 60 m cells: **Clutter** cells (anything with collision) and **Decor**
cells (collision-free, group `potato_optional`). All of it renders on `CLUTTER_LAYER`,
which neon street lights skip. No clutter casts a sun shadow (letting solid cells cast
measured +140 calls on Motor Mile); dumpsters, tyre and pallet stacks get a flat dark
contact patch in the cell's shared dark material instead (no extra draw). Visibility range
90 m (solid) / 70 m (decor), labels 38 m.

The theme is "a world paused in time": a late-1999 city frozen mid-moment, all text original.

| Piece | Count (current seed) | Collision | Notes |
|---|---:|---|---|
| Rooftop plant (condensers with fan discs, vent pipe) | 113 roofs | no | Quadrant opposite existing tanks. |
| Bill posters (0.6 x 0.84 m, faded, some peeled) | ~195 | no | Between ground-floor windows, above the base course. Y2K READY?, GRAND OPENING 1998, MILLENNIUM EVE BASH DEC 31, LOST CAT, PAGERS 50% OFF, FOR LEASE... |
| Window air-conditioners | ~94 | no | Under upper-floor windows of low/mid blocks; businesses only at the back (clear of neon boards). |
| Lit back doors (door panel + glowing lamp box, no dynamic light) | ~55 | no | Back wall of signed businesses. |
| Roller shutters with FOR LEASE 555-0199 card | ~15 | no | Over one ground-floor shop window. |
| Stopped clocks (hands at 11:59) | ~13 | no | Over shop entrances. |
| Boarded first-floor windows | ~12 | no | Non-business older blocks. |
| Alley dumpsters | ~7-11 | yes | Behind businesses when there is room; `y` recorded for the audit. |
| Trash bags, cardboard, newspaper bundles | ~8 groups | no | Beside the dumpster. |
| Tyre stacks | ~9 | yes (one box) | Motor Mile lot edges and back yards in dock districts. |
| Pallet stacks (+ occasional crate) | ~6 | yes | Old Wharf and South Docks plinths. |
| Party bunting on poles | 5 sites | no | Plazas, gardens, picnic lawn; poles beside the path entrances. |
| Leaf and litter drifts | ~12 | no | Inset site corners. |
| Oil stains in parking bays | ~20 | no | Both lots. |

**Potato mode.** `world.set_potato_mode(enabled)` hides every `potato_optional` node and
scales the range of distance-culled detail (`world._detail_ranges`: public-space props and
clutter) to 60 %. It never hides or removes a collider, so cover and routes are identical in
both modes (audited: the body count is unchanged and no `potato_optional` node contains a
CollisionObject3D). The settings button is for the lead to wire in `main.gd`.

## Captures (software GL, after)

`docs/captures/overnight/city/`: `trust.jpg` (Trust Plaza with bunting), `garden.jpg` (West End
Gardens), `alley_canal.jpg` (lit back door and dumpster behind Canal Lofts), `motor_tyres.jpg`
(tyre stacks by Big Boy Burgers), `wharf_yard.jpg` (Old Wharf pallets). 960x540 JPEG from
`tests/capture_map06.gd -- only=detail` (three new detail views added there).

## Tests (headless, final tree)

city_audit 67/0, city_detail 207/0, map_06 150/0, map_interiors 97/0, free_roam 137/0,
integration 66/0 (checks/failures). free_roam failed twice mid-evening ("round goes live when
the buy timer runs out" and the next check) and passed on the two later runs; the check waits
only 6 process frames for a 0.05 s timer, so it is timing-sensitive under load.

## Remaining

- GPU and Windows validation (numbers here are llvmpipe renderer counts only).
- Add `city_audit` to `tests/run_all.sh`'s default list and the Windows launcher (not owned here).
- The two KNOWN road steps above; the plot plinth-sinking reports.
- Neon light passes: the Compatibility renderer draws each surface once more per omni light
  touching it; big merged district meshes near neon pay this. Splitting district merges by
  area (or baking neon spill into emissive ground decals) is the next lever if needed.
- More 1999 set-dressing that did not fit tonight: CRT TVs in shop windows, payphone clutter,
  shop-window displays, a few more leaf drifts along kerbs, per-district poster sets.

## Anti-slop pass 2 (park rails, street signs, macro texture variation)

User ask: another anti-slop pass; hand rails round the parks where they make sense, so the
world feels kept and alive and vehicles get a natural barrier. Late-1999 "paused" mood.

**Park/plaza perimeter rails** (`CityDetail._perimeter_rails`, built last, no RNG). Along every
road-facing edge of Trust Plaza, West End Gardens, Old Town Green, Nightlife Commons and the
Sunset Picnic Lawn: a 0.3 m concrete curb (sunk 0.1 m so it never floats), green steel pipe
posts every <= 2.2 m, a mid rail at 0.62 m and a top rail at 1.0 m. The parks abut the
carriageway, so the rail line is 1.3 m inside the site edge behind a walkable verge; a run
starts and ends on the neighbouring edge's rail line so corners meet. Sampled every 0.5 m, a
run skips any spot within 1.0 m of a road edge, in a footprint, within 4 m of a door or parked
car, 6 m of a crew spawn/car/HQ, 1.1 m of placed furniture/clutter, or within 3.2 m of an edge
midpoint (the path entrances stay open on all four sides). Result: 44 runs over the 5 sites.
Collision matches what is seen (RAILING_COLLISION_NOTES): one StaticBody per run holding a
solid curb box, a thin box per post, and thin top and mid rails; eye-height (1.62 m) shots
clear, low shots meet the curb. Not `potato_optional` (collision, identical in both modes);
one merged node per site (a single city-wide merge put the bounds centre off-site and the
range cull hid it), CLUTTER_LAYER, range 150 m, shares two materials. `world.park_rails`
records runs for the tests.

**Street name signs** (`CityDetail._street_signs`, end of `_clutter`, no RNG): one post per
named crossing (world.roads segment intersections, merged within 18 m, crossings under 30
degrees skipped), on the first corner that passes `can_place`; two green blades naming both
streets (AVENUE -> AVE, STREET -> ST, ...), labelled both sides, labels cull at 40 m. 98 signs,
74 distinct names. Collision-free thin pole, so it is Decor (`potato_optional`).

**Texture macro variation** (`retro_textures.gd`): big-surface kinds (brick, stucco, panel,
asphalt, tiles, roof, grass, cobble, metal) get a detail layer: a fixed-seed seamless
FastNoiseLite blotch texture (64 px, 0.86..1.0, multiplied) on a second world-triplanar UV
repeating every ~23 m, so the 2-4 m tiles no longer march in an obvious grid across lots and
long walls. No extra materials or draw calls; +3 texture samples per pixel on those surfaces.

**Tests added.** city_detail: rails built (>= 10 runs, >= 4 sites), off roads and shoulders,
every run has a solid curb, eye-height shots clear every run, each park keeps >= 2 walkable
openings (all 5 keep 4), and a sedan (car.gd, full throttle 4 s) driven square at the
longest rail from 7 m out on the road side stops outside it (centre 2.32 m short of the rail
line, speed 0). city_audit: >= 12 street signs, every sign label is a real street from
world.roads, rails on every park clear of doors and parked cars.

**Draw calls** (software GL, 1280x720, `capture_perf.gd`; "before" is pass 1's Final column):

| View | Pass 1 final | Pass 2 (signs, rails culled by bug) | Pass 2 final |
|---|---:|---:|---:|
| midtown | 1,235 | 1,334 | **1,322** |
| midtown_north_long | 1,499 | 1,596 | **1,582** |
| motor_mile | 1,237 | 1,309 | **1,298** |
| nightlife | 892 | 918 | **929** |

Pass 1's column predates other agents' concurrent work (buildings/interiors, voice), so the
delta is not all this pass; the middle run (settle 30 / sample 60) had the rails invisible
(the cull bug above) and the final run (settle 10 / sample 5) includes them, each site's rails
costing a handful of calls. Most of the +60..+100 is the street-sign labels near crossings
(each Label3D is a draw; they cull at 40 m and hide in potato mode). Objects per frame rose
~300 (midtown 2,268). Acceptable for the RTX 3080 60 fps target; if needed, the next lever is
baking sign text into one atlas-textured quad per blade instead of Label3D.

Captures (`tests/capture_map06.gd -- only=pass2`, 640x360 JPEG q82 in
`docs/captures/overnight/city/`): `pass2_rails_trust.jpg`, `pass2_rails_picnic.jpg`,
`pass2_signs_halcyon.jpg` (Halcyon Ave / Union St sign), `pass2_avenue.jpg`.

Not done this pass (time): bus shelters with timetables, hydrant/newspaper-box audit on the
avenues, avenue planters with trees, manhole/drain decals, crosswalk paint audit,
floating-prop audit beyond what city_audit already covers.
