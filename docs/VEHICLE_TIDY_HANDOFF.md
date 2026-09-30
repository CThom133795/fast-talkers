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
