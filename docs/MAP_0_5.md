# Port Halcyon 0.5 — map, interiors, railings, fleet

Written by Claude for the 0.5 pass. It covers `scripts/world.gd`, `scripts/interiors.gd`, `scripts/breakable_glass.gd`, `scripts/car.gd` and `scripts/vehicle_kit.gd`.
Review renders are in `work/captures/city_*.png` and `veh_*.png`.

## City layout
- **Shape:** one continuous mainland, roughly 520 × 530 m.
  - Coastline: headlands at Lantern Point and the Solana bluff, plus bays along the east and west shores.
  - Water inside the city: exactly one canal (the Canal Market inlet, a dead end with a boat basin) and the West Slip marina.
  - Crossings: one road bridge and one footbridge. There are no channels between districts.
- **Neighbourhoods** keep their 0.4 art. Each is placed by a rigid transform (`KITS`: from, to, yaw) with a small skew, so every district has its own street angle.
  - Map records are converted to world space as they are built: footprints, landmarks, crew bases, parked cars, payphones and lamps.
- **Midtown:** Codex's downtown keeps the Exchange, the armory and every test position. Its grid is broken up in three ways:
  - Canal Walk: the west half of Canal Street, now pedestrian, with bollards at both ends.
  - Two diagonal avenues: Broadway (NE) and Park Row (SW).
  - Two small squares where the diagonals cross: Eastbank Square and Corner Park.
  - Painted "meeting point" and "safehouse" markings are removed; meetings happen anywhere.
- **Open space:** Fountain Square (a roundabout) inside Eastside Park, West Bank Plaza, Slip Park, the Canal Market square and the beach.

| Crew | District | Direction from Midtown | HQ (doorstep) | Route to Exchange |
|---|---|---|---|---|
| Kojimoto893 | Lantern Row | West | (-191, -23) | 229 m |
| Cartel Sol Negro | Solana Heights | North-east bluff | (167, -120) | 229 m |
| Kingsway Royals | Kingsway | East waterfront | (178, 2) | 228 m |
| Morris Mafia | Morris Park | South | (-79, 114) | 234 m |

- Route lengths are measured over the road graph by `world.route_length()`; the spread is 2.5%.
- Neutral districts: Harbor (N), Canal Market (NW), West Bank (W), Union Station (SW), the Strip and Halcyon Beach (S/SE), and Eastgate (E).
- Every crew district has 3+ road entries. Most also have pedestrian ways in: alleys, plazas, the footbridge and Canal Walk.

## World API (additions; everything from 0.4 is kept)
- **Routing**
  - `route(from, to) -> PackedVector3Array`: shortest drive along the streets. Useful for a GPS line on the radar.
  - `route_length(from, to)`
  - `wheelman_path(from)`: the streets to the ring, then round `road_loop`.
- **Map data**
  - `footprint_polys`: exact building outlines. `footprints` stays as bounding Rect2s.
  - `plazas`
  - `is_on_land(at)`
  - `kit_transform(kit)`
- **Crew bases:** `crew_spawns[crew]` gains `spawn`, `spawn_yaw` and `door`.
  - `spawn` is the point outside the HQ door, facing down the street.
  - main.gd's current rule (2.5 m towards the map centre) is also verified clear for all four crews.
- **Doors:** `interactable_doors[i]` = `{index, label, kind, position, inside, outside, open, district, width}`.
  - Methods: `set_door_open(i, open)`, `toggle_door(i)`, `door_near(at, radius = 2.2) -> int`.
  - Doors start open. The garage has a roller shutter.
- **Glass:** `glass_panes[i]` = `{body, shop}` and `reset_glass()`.
  - Panes have `take_damage`, so main.gd's existing shot code already breaks them.

## Walk-in businesses (12 of the 13 signed Midtown storefronts)

| Business | Room |
|---|---|
| Northline Exchange | Banking hall: teller line, vault door, queue ropes |
| Meridian Imports | Racking, forklift and site office |
| Mercury Logistics | Counter, conveyor, parcel racks and cages |
| Port Authority | Reception, turnstiles and seating |
| Eastbank Freight | Counter, desks and filing |
| The Brass Rail | Bar, booths, pool table and jukebox |
| Hotel Carlyle | Desk and key rack, lounge, lifts and chandelier |
| Lucky Star Pawn | Cases, guitars and TVs |
| Rosa's Cafe | Counter and tables |
| Kwon's 24/7 | Aisles and fridges |
| Midtown Garage | Lift and benches, with a drivable coupe inside |
| Suds Laundromat | Washers and dryers |

- CARGO 04 stays sealed because it is the armory range's backstop.
- Rooms are capped at a believable size. Partitions and a STAFF ONLY door mark the back of house.
- Each room's lamp lights only render layer 2 (the room's own meshes), and furnishings draw within 45 m.

## Railings and barriers
- **Quay edges:** a solid 0.34 m coping plus a thin solid rail at 1.12 m, on posts.
  - The 2.8 m invisible barrier is gone.
  - Tested: a standing shot clears the rail, a crouched shot passes between the coping and the rail, and a ground-level shot hits the coping.
  - People can't walk or jump off (the jump peak is 0.5 m).
- **Beach:** a 0.72 m rock revetment.
- **Chain-link:** a 1.2 m solid windbreak screen at the bottom, with shoot-through mesh above.
- **Road-bridge parapet:** solid steel plate, which is cover and looks like it. The footbridge has an open rail.

## Fleet (late-90s/early-00s)
- **Bodies:** side-profile extrusions (`vehicle_kit.gd`) with real wheel-arch cut-outs, bevelled shoulders and tumblehome.
- **Glasshouse:** pillars, roof and glass follow the same profile lines. The glass is tinted and reflective. Side panes still roll down per seat.
- **Details:** clear-lens lamps with amber corners, a grille per type, and tail lamps per type (a full-width bar on the sedan, twin lamps on the coupe, tall lamps on the SUV and pickup).
- **Wheels:** one family — hubcap (sedan), 5-spoke alloy (coupe), off-road 6-spoke (SUV and pickup), cast 3-spoke (bike).
- **Type details:**
  - Coupe: a wing and side skirts.
  - SUV: flares, step bars, roof rails and a spare wheel.
  - Pickup: a chrome bumper and an open bed with wheel tubs.
  - Bike: tank and tail profiles, a finned engine and an exhaust.
- **Hull numbers changed** (collision only): sedan roof 1.5 and cabin (-1.1, 1.25); coupe roof 1.3; SUV roof 1.92.
- **Wheel radii:** 0.34 / 0.33 / 0.40 / 0.39.
- **Unchanged:** seat eyes, doors, panes and handling.

## Known compromises
- Sol Negro (NE) and Kingsway (E) HQs are both on the east side, 123 m apart. Routes stay equal, and the other two bases are W and S.
- Midtown is still a downtown grid at heart: three avenues and four streets. It's broken by the diagonals, squares and Canal Walk rather than rebuilt, because every Midtown test position depends on it.
- Whole shop windows stop bullets and bot line of sight until they break.
- Interiors are ground floor only.
- Draw calls in Midtown are about 1,550 (0.4 was about 1,300); frame time is about 9 ms on the dev GPU. The next step is the queued district chunking and vehicle atlas task.
