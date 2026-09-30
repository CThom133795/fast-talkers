# Railing collision pass — 0.5

The current harbour coast builds a visible rail at roughly 1.14 m, then adds a 2.8 m tall invisible collision box along the same edge. From a standing eye height (about 1.62 m), bullets strike the invisible box even when the reticle is visibly above the rail. The barrier also makes low quays feel like invisible walls.

Fix the coast, bridge parapets and plaza rails together:

1. Keep solid stone parapets as real cover. Make their collision height and thickness match the visible stone. A low shot should hit stone; a shot above its top should pass.
2. Treat each rail post and top bar as its own thin collider, or use an equivalent simple shape that leaves open space underneath. A projectile striking a visible post may stop; one between posts should pass. Avoid one opaque box enclosing the whole railing.
3. Any separate vehicle safety curb should sit at the visible curb, close to road level. If an invisible safety trigger is still needed, use a dedicated layer excluded from bullet queries while retaining a player/vehicle collision mask, and document where it is used.
4. Use a standing and a crouching camera to raycast from both sides. From eye height 1.62 m, a horizontal shot across a 1.14 m top rail must clear it except when it meets a post. From 0.6 m, a ray into the visible parapet must collide. Confirm a target beyond takes damage, and confirm bridge and quay walkability after the change.
5. Check glass, chain-link fences, stair rails, bridge parapets and decorative railings with the same rule: collision should explain what is seen. Transparent visuals with full opaque collision need an explicit cover reason.

The user asked for this cleanup while the map is being rebuilt. Claude owns the `world.gd` collision implementation in the 0.5 split; Codex will integrate and run the final tests.
