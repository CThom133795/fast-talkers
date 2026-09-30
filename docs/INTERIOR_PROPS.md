# Interior props (trade dressing)

Small, collision-free set dressing that says what each business is: display guns on the gun-store
wall, ketchup and pie at the diner, binders and 1999 calendars in the office. None of it is usable
or interactable. Late-1999 "paused" mood; all text and brands are original.

## How it is built

- **Landmark buildings** (`scripts/buildings/*.gd`) use the kit helpers added to
  `building_kit.gd`: `begin_props()` / `end_props()` route geometry into a `Props` node (under the
  building's `Interior` node when there is one); `prop()` adds a collision-free box; `display_gun()`,
  `prop_carton()`, `prop_bottle()` and `prop_crt()` build common items from a few boxes;
  `finish_props()` (call it just before `finish()`) merges the props into one mesh per material,
  moves them to the interior render layer, turns their shadows off, sets
  `visibility_range_end = PROP_RANGE` (34 m, 3 m margin), adds the node to `potato_optional` and
  tags it with meta `prop_node`.
- **Midtown walk-in shops** (`scripts/interiors.gd`) do the same in `_dress()` / `_finish_props()`:
  a wall clock, a 1999 calendar and a notice board in every room, plus a `_props_<kind>()` per trade.
  No `world._rng` calls, so the seeded city is unchanged.
- Materials come from the world's cache (`kit.mat` / `world._material`), so every prop in a building
  collapses into a handful of merged meshes.

## Rules

- Props never get collision. Anything that must stop a player or a bullet (counters, cases, booths)
  is built as before with `box(..., solid = true)` and is not in the props node.
- Potato mode (`world.set_potato_mode`) hides every `potato_optional` node, props included; since
  none of them collide, routes, cover and gameplay are identical in both modes.
- Keep walk routes, doors and landings clear (props sit on walls, shelves and table tops).

## What each building has

| Building | Dressing |
| --- | --- |
| Halcyon Arms (gun store) | 3 rows of long guns on the pegboard (rifle, shotgun, lever, carbine; wood/blued/black) on hooks with price tags, a handgun row, pistols on red felt in both glass counters with tags, 80 ammunition cartons on the side shelves, holsters, cleaning kits, paper targets, a hunter-safety poster, "NO LOADED FIREARMS BEYOND THIS POINT" and "LAYAWAY AVAILABLE" signs. `display_guns` meta records the count. |
| Big Boy Burgers (diner) | Napkin dispensers, ketchup/mustard, salt and pepper, plates, mugs of coffee and menus on every booth; pie case, coffee pots, milkshake mixer, straw dispenser, stacked plates and two lit menu boards at the counter. |
| Sea Breeze Motel (upper rooms) | Phone and Bible on the nightstand, ice bucket and brochure fan on the dresser, folded towels on the bed, a DO NOT DISTURB hanger by the door, towels on the bathroom rail. |
| Club Voltage | Glasses, beers, bottles, ashtrays, napkins and cash on the bar; bottles, glasses and ashtrays on the lounge and cocktail tables; coats and hangers on the coat-check rail. |
| The Velvet Room | Bills on the tip rail, glasses/ashtrays/bottles on the bar, drink menus and bottles in the booths, cocktail-table glasses and cash. |
| Hotel Meridian | Brochure stand, key cards, fruit bowl, "please ring" card and a pen on the reception desk; bags on the luggage cart. |
| Halcyon Trust (office floor) | Binders, beige phones, in/out trays with paper, keyboards and mugs on every desk; 1999 calendars on the partitions; a fax on the filing wall; papers, mugs and a speakerphone on the conference table. |
| Central Parking | Ticket dispenser at the entry, a lost-and-found box on the booth island, oil drums and an absorbent pail in the front-east corner. |
| Midtown shops | Every room: clock, calendar, notice board. Offices (exchange, imports, logistics, authority, freight): binder shelf and archive boxes. Brass Rail: glasses, ashtrays, pool balls and a cue. Hotel Carlyle: bell, brochures, register book, bag on the cart. Lucky Star Pawn: watches/rings/cameras in the cases with tags, cameras on the wall. Rosa's Cafe: cups, pastries, table settings. Kwon's 24/7: cigarette rack, counter candy, newspapers. Midtown Garage: tools on the pegboard, oil cans and parts boxes. Suds: detergent boxes, basket and folded laundry. |

## Tests

`tests/building_landmarks.gd` (`_check_props`) checks every building and Midtown shop has a Props
node in `potato_optional`, that the props have no collision and draw within 40 m, that the gun wall
shows >= 20 display guns, that no door or lift lives in the props and none sits on the gun wall, and
that potato mode hides and restores them. `tests/capture_interiors.gd` has `gun_wall`,
`gun_counter`, `diner_counter` and `tower_desk` views; `compare=1` also prints the draw calls with
potato mode on (props hidden).
