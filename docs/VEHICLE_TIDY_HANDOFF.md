# Vehicle and surface tidy pass

This pass is ready on the existing `cloud/map-integration` branch for Claude Desktop review.

## Changes

- Vehicle lower coachwork no longer closes a solid painted sheet across the cabin. The cabin opening preserves the bonnet, trunk, sills, wheel arches and outer side panels while leaving the occupant space open.
- Added a simple cabin floor, inner sill/door panels, restrained dashboard details and a forward-positioned steering wheel. Pickup and sedan sight lines were checked with actual seat-eye cameras.
- Added `tests/capture_cabins.gd` for driver, passenger and exterior views of sedan, coupe, SUV and pickup.
- Added vehicle-art assertions that check no paint triangle crosses the occupant torso/leg segment. The suite now reports 64 checks, 0 failures.
- Reduced accumulated road-ribbon height offsets to avoid visible stepped intersections. Texture noise now tiles its hash domain; brick mortar, asphalt cracks and plank repetition are less harsh.

## Validation

- `vehicle_art.gd`: 64/64.
- `integration.gd`: 66/66.
- `vehicles_06.gd`: 24 checks, but two settings persistence assertions failed in the restricted runner because the temporary settings file could not be written. Rerun that suite with normal local file access before treating the branch as fully verified.
- No executable was replaced by this pass. The local Windows export still needs the normal-permission validation and a smoke test.

## Claude Desktop pickup

Fetch this branch, review the diff, run `tests/capture_cabins.gd` with a GPU, then run the Windows vehicle suite with ordinary settings-file access. Inspect the driver, passenger and pickup views for remaining pillar/dashboard clipping. Keep the vehicle APIs and deterministic world order unchanged. Do not merge into `master` until the local validation succeeds.

## Overnight pass

Presentation-only. The public vars, method names and signatures, TYPES handling numbers, seat order and counts, door and glass indices, collision hull and net code in `scripts/car.gd` did not change. Everything new is built deterministically from the type tables, and it uses the existing trim, cloth, paint and well materials, so it merges into the surfaces that were already there.

Fixes (`scripts/car.gd`):
- **Footwell and toe board.** Before this pass there was open space under the dash, so you could see the road and the front tyres from the driver and passenger seats. A cloth footwell floor, a trim toe board and kick panels now close that gap.
- **Seat bases.** In the SUV and pickup, the cushions floated 13 to 16 cm above the cabin floor. Each seat now has a pedestal down to the floor. The shared helpers `_cabin_floor_y`, `_seat_centre` and `_cushion_y` are also used by the tests.
- **Steering wheel.** The wheel sits 3 cm lower, tilts slightly more and has a steering column, so its rim stays below the driver's straight-ahead sight line.
- **Wheels tucked in (visual only).** The wheel pivots now use `_wheel_x()` instead of `spec.track`, so hub faces sit flush with the body side (the SUV's sit under its flares). Before, they stood 3 to 8 cm proud of the arches. `spec.track` itself is unchanged.
- **Wheel-well liners.** Each liner used to be a 22 cm block that ran through the tyre. It is now a 4 cm plate just inboard of the tyre.
- **Wheel-arch tunnels removed.** The extruded lower body used to carry each wheel-arch roof as a paint tunnel across the whole width. It ran through the front footwell and up through the rear seat cushions. `VehicleKit.profile` now takes an optional `arch_inner` argument (default 0, so existing calls are unchanged). With it set, each arch roof stops at its own wheel well and the taller liner plate closes the well.
- **Door shut-lines.** A seam that crosses a wheel arch now stops at the arch. Before, the sedan's front seam hung in front of the tyre.
- **Z-fighting removed.**
  - The sedan's amber tail-lamp inserts shared top and bottom faces with the red bar. They are now taller and sit further out.
  - The coupe air dam shared the floor-pan plane. It now hangs 1.5 cm lower.
- **Motorcycle mudguards.** The flat planks that floated over the tyres are now curved bands that follow each tyre.

Lived-in details (same merged materials, placed clear of the sight lines):
- Rear-view mirror on a stalk, two sun visors, and a folded map on the passenger side of the dash top.
- Seven-segment plate legends front and rear. The registrations are original and fixed per type: `PH 4127`, `PH 9030`, `PH 5518`, `PH 2264`.
- Mud flaps behind all four wheels on the pickup.
- Not done: a weathered or dirty lower-body tint. It needs vertex colour or a second paint material, which adds a draw call per car.
- Cost: surfaces per car are unchanged (sedan 25, coupe 24, SUV 30, pickup 31, bike 14). Triangles rise about 5%: sedan 23.9k to 25.2k, SUV 30.0k to 31.4k. The bike drops from 8.5k to 8.2k. The new small parts use a one-segment bevel (`_block`).

New checks in `tests/vehicle_art.gd` (now 110 checks, up from 64):
- Tyres touch the ground plane.
- Tyres sit inside their arches.
- Seats rest on the cabin floor.
- The front row has a clear forward sight line through the windscreen, with no solid geometry in the way.
- The footwell is closed.
- Wheel arches are clear in front of the tyres.
- No paint arch tunnel crosses the car between the wheel wells.
- No coplanar overlapping faces between different materials.

The footwell, seat-base, arch and tunnel checks were confirmed to fail when their fix is removed. The coplanar check caught the two z-fights described above.

`tests/capture_cabins.gd` now:
- renders all five types over a ground plane with shadows,
- adds rear-seat, low front-wheel and rear three-quarter views,
- writes to `work/captures/cabins/`.

It renders under Xvfb with Mesa llvmpipe (software GL, not a GPU). Curated results are in `docs/captures/overnight/vehicles/`.

Remaining:
- The dash-top map reads as a dark hole at low resolution.
- The bike mirrors are tall.
- `capture_vehicles.gd` loads the full game and writes outside the repo (`res://../../work/captures`). It was not run in this pass.
- GPU and Windows validation are still needed.
