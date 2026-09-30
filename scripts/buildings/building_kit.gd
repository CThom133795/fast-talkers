extends RefCounted
## BuildingKit: the shared construction helpers for the eight trademark buildings (high-rise,
## hotel, parking garage, motel, night club, strip club, burger joint, gun store). Every M2
## session builds on this file: ADD functions, never change existing ones.
##
## Frame. A kit works in the plot's local frame, exactly like scripts/interiors.gd:
##   origin = the plot's centre at street level, +Z = out of the front door (the plot's `front`),
##   +X = along the facade, +Y = up. All positions and sizes you pass in are local. The kit's
##   Node3D carries the plot's transform, so the meshes and colliders you add are ordinary children.
##   Anything registered with the world (doors, lifts, footprints, landmarks) is converted to
##   world space for you (`to_world`). The world's own helpers (`world._box_with`, `_tower`, `_neon`,
##   `_label`, `_car_prop`, `_landmark`, ...) also work between `focus()` calls.
##
## Pattern for a builder file (scripts/buildings/<key>.gd):
##   static func build(world: Node3D, plot: Dictionary) -> void:
##       var kit := BuildingKit.new(world, "Hotel", plot)
##       kit.floor_slab(...); kit.wall(...); kit.stairs_straight(...); kit.lift(...)
##       kit.begin_interior()          # furnishings + lamps go on render layer 2 (INTERIOR_LAYER)
##       ...
##       kit.finish()                  # merges meshes; call it once, last
##
## Rules the helpers keep (docs/tasks/MAP_0_6_PLAN.md): collision matches what you see; stairs rise
## <= 0.18 m and run >= 0.28 m (or ramps <= 30 degrees); rails follow the 0.5 quay rules (a solid
## kick-board, a thin solid rail at 1.12 m, nothing invisible above it); lifts are scripted
## AnimatableBody3D movers registered as interactable_doors entries with kind "lift"; at most one
## OmniLight per room group on the interior render layer.

const GlassScript = preload("res://scripts/breakable_glass.gd")

const STEP_RISE_MAX: float = 0.18
const STEP_RUN_MIN: float = 0.28
const STEP_RUN: float = 0.30
const FLOOR_HEIGHT: float = 3.4
const SLAB: float = 0.3
const WALL: float = 0.3
const DOOR_HEIGHT: float = 2.6
const RAMP_MAX_DEGREES: float = 30.0
const RAIL_HEIGHT: float = 1.12
const KICK_HEIGHT: float = 0.34

var world: Node3D
var plot: Dictionary
var node: Node3D
var interior: Node3D = null
var district: String = ""
var yaw: float = 0.0
var size: Vector2 = Vector2.ZERO
var _current: Node3D
var _finished: bool = false


func _init(owner: Node3D, title: String, plot_spec: Dictionary) -> void:
	world = owner
	plot = plot_spec
	district = str(plot_spec.get("district", ""))
	size = plot_spec.get("size", Vector2(20, 20))
	var front: Vector3 = plot_spec.get("front", Vector3.BACK)
	yaw = float(plot_spec.get("yaw", atan2(front.x, front.z)))
	node = world._begin(title)
	var center: Vector2 = plot_spec["center"]
	node.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, 0, center.y))
	_current = node
	focus()


## Points the world's construction helpers at this kit's node again (call after using another builder).
func focus() -> void:
	world._target = _current
	world._xf = node.transform
	world._xf_yaw = yaw


func to_world(local: Vector3) -> Vector3:
	return node.transform * local


func to_local(world_point: Vector3) -> Vector3:
	return node.transform.affine_inverse() * world_point


## World-space outline of a local rectangle (for footprints and the map).
func outline(rect: Rect2) -> PackedVector2Array:
	var poly: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var at: Vector3 = to_world(Vector3(corner.x, 0, corner.y))
		poly.append(Vector2(at.x, at.z))
	return poly


## Registers a building outline (local rect) for the radar/map and the street-life clearance.
func footprint(rect: Rect2) -> void:
	focus()
	world._footprint(rect)


func mat(color: Color, tex: String = "", roughness: float = 0.85) -> StandardMaterial3D:
	return world._material(color, roughness, tex)


func glow(color: Color, energy: float = 1.6) -> StandardMaterial3D:
	return world._glow(color, energy)


func box(center: Vector3, box_size: Vector3, material: Material, solid: bool = false, angle: float = 0.0) -> MeshInstance3D:
	focus()
	return world._box_with(center, box_size, material, solid, angle)


## Collision only.
func collider(center: Vector3, box_size: Vector3, angle: float = 0.0) -> void:
	focus()
	world._collider(center, box_size, angle)


## A box-shaped bar between two local points (rails, cables, ramps' edges). Visible and solid.
func bar(from: Vector3, to: Vector3, thickness: float, material: Material, solid: bool = true) -> void:
	focus()
	var span: Vector3 = to - from
	if span.length() < 0.01:
		return
	var basis: Basis = Basis.looking_at(span.normalized(), Vector3.UP if absf(span.normalized().y) < 0.99 else Vector3.RIGHT)
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, span.length())
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = Transform3D(basis, (from + to) * 0.5)
	_current.add_child(instance)
	if solid:
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = mesh.size
		shape.shape = box_shape
		body.add_child(shape)
		body.transform = instance.transform
		_current.add_child(body)


# --- Walls, floors and ceilings -----------------------------------------------------------------

## An opening description for wall(): `at` is the distance along the wall (from a) to the opening's
## centre. kind "door" and "gap" leave the hole open (use add_door for a leaf), "window" fills it
## with breakable glass.
static func opening(at: float, width: float, sill: float = 0.0, top: float = 2.6, kind: String = "door") -> Dictionary:
	return {"at": at, "width": width, "sill": sill, "top": top, "kind": kind}


## A straight solid wall from plan point a to b (local x/z), `height` tall from `base`, with openings.
func wall(a: Vector2, b: Vector2, height: float, material: Material, openings: Array = [], base: float = 0.0, thickness: float = WALL) -> void:
	focus()
	var span: Vector2 = b - a
	var length: float = span.length()
	if length < 0.05:
		return
	var direction: Vector2 = span / length
	var angle: float = atan2(direction.x, direction.y)
	var sorted: Array = openings.duplicate()
	sorted.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["at"]) < float(q["at"]))
	var cursor: float = 0.0
	for spec: Dictionary in sorted:
		var x0: float = clampf(float(spec["at"]) - float(spec["width"]) * 0.5, 0.0, length)
		var x1: float = clampf(float(spec["at"]) + float(spec["width"]) * 0.5, 0.0, length)
		if x0 > cursor + 0.01:
			_wall_piece(a, direction, angle, cursor, x0, base, base + height, thickness, material)
		var sill: float = float(spec["sill"])
		var top: float = float(spec["top"])
		if sill > 0.01:
			_wall_piece(a, direction, angle, x0, x1, base, base + sill, thickness, material)
		if top < height - 0.01:
			_wall_piece(a, direction, angle, x0, x1, base + top, base + height, thickness, material)
		if str(spec["kind"]) == "window":
			var mid: Vector2 = a + direction * ((x0 + x1) * 0.5)
			glass_pane(Vector3(mid.x, base + (sill + top) * 0.5, mid.y), Vector3(thickness * 0.25, top - sill, x1 - x0), angle)
		cursor = maxf(cursor, x1)
	if cursor < length - 0.01:
		_wall_piece(a, direction, angle, cursor, length, base, base + height, thickness, material)


func _wall_piece(a: Vector2, direction: Vector2, angle: float, s0: float, s1: float, y0: float, y1: float, thickness: float, material: Material) -> void:
	if s1 - s0 < 0.01 or y1 - y0 < 0.01:
		return
	var mid: Vector2 = a + direction * ((s0 + s1) * 0.5)
	world._box_with(Vector3(mid.x, (y0 + y1) * 0.5, mid.y), Vector3(thickness, y1 - y0, s1 - s0), material, true, angle)


## A floor or ceiling plate whose top surface is at `top_y`, with rectangular holes (stairwells, lift
## shafts, atria). Solid.
func floor_slab(rect: Rect2, top_y: float, material: Material, holes: Array = [], thickness: float = SLAB) -> void:
	focus()
	var zs: Array[float] = [rect.position.y, rect.end.y]
	for hole: Rect2 in holes:
		var clipped: Rect2 = hole.intersection(rect)
		if clipped.size.x > 0.01 and clipped.size.y > 0.01:
			zs.append(clipped.position.y)
			zs.append(clipped.end.y)
	zs.sort()
	for index: int in range(zs.size() - 1):
		var z0: float = zs[index]
		var z1: float = zs[index + 1]
		if z1 - z0 < 0.01:
			continue
		var mid: float = (z0 + z1) * 0.5
		var blocked: Array[Vector2] = []
		for hole: Rect2 in holes:
			if hole.position.y <= mid and hole.end.y >= mid:
				blocked.append(Vector2(maxf(hole.position.x, rect.position.x), minf(hole.end.x, rect.end.x)))
		blocked.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
		var cursor: float = rect.position.x
		for span: Vector2 in blocked:
			if span.x > cursor + 0.01:
				_slab_piece(cursor, span.x, z0, z1, top_y, thickness, material)
			cursor = maxf(cursor, span.y)
		if cursor < rect.end.x - 0.01:
			_slab_piece(cursor, rect.end.x, z0, z1, top_y, thickness, material)


func _slab_piece(x0: float, x1: float, z0: float, z1: float, top_y: float, thickness: float, material: Material) -> void:
	world._box_with(Vector3((x0 + x1) * 0.5, top_y - thickness * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, thickness, z1 - z0), material, true)


## Breakable glass in a local box (centre, size with the thin axis along local X or Z after `angle`).
func glass_pane(center: Vector3, pane_size: Vector3, angle: float = 0.0) -> void:
	focus()
	var body: StaticBody3D = GlassScript.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = pane_size
	shape.shape = box_shape
	body.add_child(shape)
	var pane: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = pane_size
	pane.mesh = mesh
	pane.material_override = glass_material()
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pane.visibility_range_end = 80.0
	body.add_child(pane)
	body.pane = pane
	body.position = center
	body.rotation.y = angle
	_current.add_child(body)
	world.glass_panes.append({"body": body, "shop": str(plot.get("district", "")) + " " + node.name})


func glass_material() -> StandardMaterial3D:
	if world._materials.has("shop_glass"):
		return world._materials["shop_glass"] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.62, 0.66, 0.24)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.05
	material.metallic = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	world._materials["shop_glass"] = material
	return material


## A grid of glowing/dark window boxes on one facade of an upper block. `along` is the facade's
## plan direction (local x/z unit vector), `origin` its start point on the wall line, `normal`
## points out of the wall. Rows start at `first_y` every `pitch`.
func window_grid(origin: Vector3, along: Vector3, normal: Vector3, length: float, first_y: float, rows: int, pitch: float = 3.4, column_pitch: float = 3.4, lit: float = 0.35, window: Vector2 = Vector2(1.65, 1.55)) -> void:
	focus()
	var dark: StandardMaterial3D = world._material(Color(0.16, 0.24, 0.29), 0.3)
	var warm: StandardMaterial3D = world._glow(Color(1.0, 0.78, 0.46), 1.3)
	var columns: int = maxi(1, int(length / column_pitch))
	var angle: float = atan2(normal.x, normal.z)
	for row: int in range(rows):
		for column: int in range(columns):
			var at: Vector3 = origin + along * ((column + 0.5) * length / columns) + normal * 0.05 + Vector3(0, first_y + row * pitch, 0)
			world._box_with(at, Vector3(window.x, window.y, 0.1), warm if world._rng.randf() < lit and row > 0 else dark, false, angle)


# --- Stairs and ramps ---------------------------------------------------------------------------

## One flight of `steps` solid steps of rise `rise` and run `run`. `start` is the middle of the first
## riser at floor level; `heading` is the horizontal direction of ascent. Visible steps merge with
## the building; one StaticBody3D carries the box colliders.
func _flight(start: Vector3, heading: Vector3, steps: int, rise: float, width: float, run: float, material: Material) -> void:
	focus()
	var angle: float = atan2(heading.x, heading.z)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Flight"
	_current.add_child(body)
	for index: int in range(steps):
		var top: float = (index + 1) * rise
		var center: Vector3 = start + heading * ((index + 0.5) * run) + Vector3(0, top * 0.5, 0)
		world._box_with(center, Vector3(width, top, run), material, false, angle)
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = Vector3(width, top, run)
		shape.shape = box_shape
		shape.transform = Transform3D(Basis(Vector3.UP, angle), center)
		body.add_child(shape)


## A straight flight of stairs. Returns {bottom, top, steps, rise, run, heading, length, width}; `top`
## is the point on the upper floor where the last step ends (walk on from there).
func stairs_straight(start: Vector3, heading: Vector3, total_rise: float, width: float, material: Material, rails: bool = true, run: float = STEP_RUN) -> Dictionary:
	assert(run >= STEP_RUN_MIN)
	var direction: Vector3 = Vector3(heading.x, 0, heading.z).normalized()
	var steps: int = maxi(1, int(ceil(total_rise / STEP_RISE_MAX - 0.0001)))
	var rise: float = total_rise / steps
	_flight(start, direction, steps, rise, width, run, material)
	var top: Vector3 = start + direction * (steps * run) + Vector3(0, total_rise, 0)
	if rails:
		var lateral: Vector3 = Vector3.UP.cross(direction)
		for side: float in [-1.0, 1.0]:
			var offset: Vector3 = lateral * side * (width * 0.5 - 0.05)
			stair_rail(start + offset, top + offset, steps)
	return {"bottom": start, "top": top, "steps": steps, "rise": rise, "run": run, "heading": direction, "length": steps * run, "width": width}


## A U-return stair: a flight, a half landing, and a flight back the other way, side by side. The
## returned `top` is above `start` (offset sideways by width + gap).
func stairs_u(start: Vector3, heading: Vector3, total_rise: float, width: float, gap: float, material: Material, rails: bool = true, run: float = STEP_RUN) -> Dictionary:
	var direction: Vector3 = Vector3(heading.x, 0, heading.z).normalized()
	var lateral: Vector3 = Vector3.UP.cross(direction)
	var steps: int = maxi(2, int(ceil(total_rise / STEP_RISE_MAX - 0.0001)))
	var rise: float = total_rise / steps
	var first: int = steps / 2
	var second: int = steps - first
	_flight(start, direction, first, rise, width, run, material)
	var landing_depth: float = maxf(width, 1.2)
	var landing_top: float = first * rise
	var landing_size: Vector3 = Vector3(width * 2.0 + gap, landing_top, landing_depth)
	var landing_center: Vector3 = start + direction * (first * run + landing_depth * 0.5) + lateral * ((width + gap) * 0.5) + Vector3(0, landing_top * 0.5, 0)
	var angle: float = atan2(direction.x, direction.z)
	world._box_with(landing_center, landing_size, material, true, angle)
	var second_start: Vector3 = start + lateral * (width + gap) + direction * (first * run + landing_depth) + Vector3(0, landing_top, 0)
	_flight(second_start, -direction, second, rise, width, run, material)
	var top: Vector3 = second_start - direction * (second * run) + Vector3(0, second * rise, 0)
	if rails:
		var outer_a: Vector3 = start - lateral * (width * 0.5 - 0.05)
		stair_rail(outer_a, outer_a + direction * (first * run) + Vector3(0, landing_top, 0), first)
		var outer_b: Vector3 = second_start + lateral * (width * 0.5 - 0.05)
		stair_rail(outer_b, outer_b - direction * (second * run) + Vector3(0, second * rise, 0), second)
	return {"bottom": start, "top": top, "landing": landing_center + Vector3(0, landing_top * 0.5, 0), "steps": steps, "rise": rise, "run": run, "heading": direction, "width": width}


## A sloped handrail along a flight (thin, visible and solid: it is where the rail is).
func stair_rail(from: Vector3, to: Vector3, steps: int) -> void:
	var steel: StandardMaterial3D = mat(Color(0.2, 0.21, 0.22), "metal", 0.5)
	var up: Vector3 = Vector3(0, RAIL_HEIGHT - 0.1, 0)
	bar(from + up, to + up, 0.07, steel, true)
	var span: Vector3 = to - from
	var posts: int = maxi(1, steps / 4)
	for index: int in range(posts + 1):
		var at: Vector3 = from + span * (float(index) / posts)
		world._box_with(at + Vector3(0, (RAIL_HEIGHT - 0.1) * 0.5, 0), Vector3(0.05, RAIL_HEIGHT - 0.1, 0.05), steel)


## A ramp (walkable/drivable slab) from `bottom` to `top` (local points), `width` wide. Slopes steeper
## than 30 degrees are refused. Returns {bottom, top, degrees, length}.
func ramp(bottom: Vector3, top: Vector3, width: float, material: Material, thickness: float = 0.35) -> Dictionary:
	focus()
	var span: Vector3 = top - bottom
	var flat: float = Vector2(span.x, span.z).length()
	var degrees: float = rad_to_deg(atan2(absf(span.y), flat))
	if degrees > RAMP_MAX_DEGREES:
		push_error("BuildingKit.ramp: %.1f degrees is steeper than %.0f" % [degrees, RAMP_MAX_DEGREES])
	var heading: Vector3 = Vector3(span.x, 0, span.z).normalized()
	var angle: float = atan2(heading.x, heading.z)
	var length: float = span.length()
	var center: Vector3 = (bottom + top) * 0.5 - Vector3(0, thickness * 0.5 / cos(deg_to_rad(degrees)), 0)
	var basis: Basis = Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, -atan2(span.y, flat))
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width, thickness, length)
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = Transform3D(basis, center)
	_current.add_child(instance)
	var body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = mesh.size
	shape.shape = box_shape
	body.add_child(shape)
	body.transform = instance.transform
	_current.add_child(body)
	return {"bottom": bottom, "top": top, "degrees": degrees, "length": length}


# --- Railings and parapets ------------------------------------------------------------------------

## A guard rail between two local points at the same height, following the 0.5 quay rules: a solid
## 0.34 m kick-board (coping), a thin solid rail at 1.12 m on posts, and open air between (shots
## pass through; nobody walks through).
func railing(a: Vector3, b: Vector3, kick: bool = true) -> void:
	focus()
	var steel: StandardMaterial3D = mat(Color(0.18, 0.19, 0.2), "", 0.6)
	var span: Vector3 = b - a
	var length: float = span.length()
	if length < 0.1:
		return
	var direction: Vector3 = span / length
	var angle: float = atan2(direction.x, direction.z)
	var mid: Vector3 = (a + b) * 0.5
	if kick:
		world._box_with(mid + Vector3(0, KICK_HEIGHT * 0.5, 0), Vector3(0.3, KICK_HEIGHT, length + 0.1), mat(Color(0.66, 0.64, 0.58), "", 0.8), true, angle)
	var posts: int = maxi(1, int(length / 2.0))
	for index: int in range(posts + 1):
		var at: Vector3 = a + span * (float(index) / posts)
		world._box_with(at + Vector3(0, (KICK_HEIGHT + RAIL_HEIGHT) * 0.5, 0), Vector3(0.07, RAIL_HEIGHT - KICK_HEIGHT, 0.07), steel)
	world._box_with(mid + Vector3(0, RAIL_HEIGHT, 0), Vector3(0.07, 0.07, length), steel, true, angle)


## A solid parapet wall (rooftops, garage decks): cover, and it looks it.
func parapet(a: Vector3, b: Vector3, height: float = 1.1, thickness: float = 0.4, material: Material = null) -> void:
	focus()
	var span: Vector3 = b - a
	var length: float = span.length()
	if length < 0.1:
		return
	var direction: Vector3 = span / length
	var wall_material: Material = material if material != null else mat(Color(0.5, 0.49, 0.46), "panel", 0.9)
	world._box_with((a + b) * 0.5 + Vector3(0, height * 0.5, 0), Vector3(thickness, height, length), wall_material, true, atan2(direction.x, direction.z))


# --- Doors ----------------------------------------------------------------------------------------

## A hinged door (or a pair) in a local wall opening, registered in world.interactable_doors. `center`
## is the opening's centre at floor level, `facing` the local direction out of the room's front
## (the side people arrive from). Returns the door's index in interactable_doors.
func add_door(center: Vector3, width: float, height: float, facing: Vector3, label: String, kind: String = "door", material: Material = null, leaves: int = 0) -> int:
	focus()
	var out: Vector3 = Vector3(facing.x, 0, facing.z).normalized()
	var along: Vector3 = Vector3.UP.cross(out)
	var face_yaw: float = atan2(out.x, out.z)
	var count: int = leaves if leaves > 0 else (2 if width > 2.0 else 1)
	var leaf_width: float = width / count
	var door_material: Material = material if material != null else mat(Color(0.3, 0.2, 0.13), "planks", 0.7)
	var nodes: Array = []
	for index: int in range(count):
		var hinge_side: float = -1.0 if index == 0 else 1.0
		if count == 1:
			hinge_side = -1.0
		var hinge: Node3D = Node3D.new()
		_current.add_child(hinge)
		hinge.position = center + along * (hinge_side * width * 0.5)
		var swing: float = 1.7 if hinge_side < 0.0 else -1.7
		hinge.set_meta("closed_yaw", face_yaw)
		hinge.set_meta("swing", swing)
		hinge.rotation.y = face_yaw + swing
		var body: StaticBody3D = StaticBody3D.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = Vector3(leaf_width - 0.04 + 0.06, height - 0.04, 0.06)
		shape.shape = box_shape
		body.add_child(shape)
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(leaf_width - 0.04, height - 0.04, 0.06)
		mesh_instance.mesh = mesh
		mesh_instance.material_override = door_material
		mesh_instance.visibility_range_end = 80.0
		body.add_child(mesh_instance)
		body.position = Vector3(-hinge_side * leaf_width * 0.5, height * 0.5, 0)
		hinge.add_child(body)
		nodes.append(hinge)
	var index_out: int = world.interactable_doors.size()
	world.interactable_doors.append({"index": index_out, "label": label, "kind": kind, "position": to_world(center), "inside": to_world(center - out * 1.6),
		"outside": to_world(center + out * 1.6), "open": true, "district": district, "width": width})
	world._door_nodes.append(nodes)
	return index_out


# --- Lifts ----------------------------------------------------------------------------------------

## A lift: a shaft, a car (AnimatableBody3D with sync_to_physics, moved deterministically by the
## world), sliding landing doors and call buttons. `shaft` is the clear shaft rectangle (local x/z,
## about 2.4 x 2.6), `floors` the landing heights (top surface of each floor, local y, ascending),
## `door_side` the local direction the doors face (Vector3.BACK = +Z etc.). The shaft walls run from
## just below the first landing to just above the last; cut the floor slabs with the shaft as a hole.
## Registers one interactable_doors entry per landing ({kind "lift", lift, floor}) plus one in the
## car ({floor -1}, sends the car to the next floor), and returns the lift's index in world.lifts.
func lift(shaft: Rect2, floors: Array, door_side: Vector3, label: String, wall_material: Material = null) -> int:
	focus()
	var side: Vector3 = Vector3(door_side.x, 0, door_side.z).normalized()
	var along: Vector3 = Vector3.UP.cross(side)
	var center2: Vector2 = shaft.get_center()
	var center: Vector3 = Vector3(center2.x, 0, center2.y)
	var half_depth: float = (shaft.size.y if absf(side.z) > 0.5 else shaft.size.x) * 0.5
	var half_width: float = (shaft.size.x if absf(side.z) > 0.5 else shaft.size.y) * 0.5
	var bottom: float = float(floors[0]) - 0.4
	var top: float = float(floors[floors.size() - 1]) + DOOR_HEIGHT + 0.9
	var steel: Material = wall_material if wall_material != null else mat(Color(0.42, 0.44, 0.46), "metal", 0.6)
	var dark: StandardMaterial3D = mat(Color(0.12, 0.13, 0.14), "", 0.6)
	var angle: float = atan2(side.x, side.z)
	# Shaft: the back and both sides are solid walls; the door side has piers and a header over every landing.
	var back: Vector3 = center - side * (half_depth + WALL * 0.5)
	world._box_with(back + Vector3(0, (top + bottom) * 0.5, 0), Vector3(half_width * 2.0 + WALL * 2.0, top - bottom, WALL), steel, true, angle)
	for lateral: float in [-1.0, 1.0]:
		var wall_center: Vector3 = center + along * lateral * (half_width + WALL * 0.5)
		world._box_with(wall_center + Vector3(0, (top + bottom) * 0.5, 0), Vector3(WALL, top - bottom, half_depth * 2.0), steel, true, angle)
	var opening_width: float = minf(half_width * 2.0 - 0.5, 1.5)
	var pier: float = (half_width * 2.0 - opening_width) * 0.5
	var front: Vector3 = center + side * (half_depth + WALL * 0.5)
	for lateral: float in [-1.0, 1.0]:
		world._box_with(front + along * lateral * (opening_width * 0.5 + pier * 0.5) + Vector3(0, (top + bottom) * 0.5, 0), Vector3(pier, top - bottom, WALL), steel, true, angle)
	var cursor: float = bottom
	for landing_y: Variant in floors:
		var y: float = float(landing_y)
		if y > cursor + 0.01:
			world._box_with(front + Vector3(0, (cursor + y) * 0.5, 0), Vector3(opening_width, y - cursor, WALL), steel, true, angle)
		cursor = y + DOOR_HEIGHT
	if top > cursor + 0.01:
		world._box_with(front + Vector3(0, (cursor + top) * 0.5, 0), Vector3(opening_width, top - cursor, WALL), steel, true, angle)
	# Landing doors: two sliding leaves per floor, closed unless the car is there.
	var doors: Array = []
	var open: Array = []
	var index: int = world.lifts.size()
	for landing_y: Variant in floors:
		var y: float = float(landing_y)
		var root: Node3D = Node3D.new()
		_current.add_child(root)
		root.position = front + Vector3(0, y, 0) - side * (WALL * 0.5 - 0.06)
		root.rotation.y = angle
		var leaves: Array = []
		for lateral: float in [-1.0, 1.0]:
			var leaf: StaticBody3D = StaticBody3D.new()
			var shape: CollisionShape3D = CollisionShape3D.new()
			var box_shape: BoxShape3D = BoxShape3D.new()
			box_shape.size = Vector3(opening_width * 0.5, DOOR_HEIGHT, 0.06)
			shape.shape = box_shape
			shape.position = Vector3(0, DOOR_HEIGHT * 0.5, 0)
			leaf.add_child(shape)
			var mesh_instance: MeshInstance3D = MeshInstance3D.new()
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = box_shape.size
			mesh_instance.mesh = mesh
			mesh_instance.material_override = mat(Color(0.7, 0.72, 0.74), "metal", 0.4)
			mesh_instance.position = shape.position
			leaf.add_child(mesh_instance)
			leaf.position = Vector3(lateral * opening_width * 0.25, 0, 0)
			leaf.set_meta("closed_x", leaf.position.x)
			leaf.set_meta("slide", lateral * (opening_width * 0.5 - 0.02))
			root.add_child(leaf)
			leaves.append(leaf)
		doors.append(leaves)
		open.append(0.0)
	# The car.
	var car: AnimatableBody3D = AnimatableBody3D.new()
	car.name = "LiftCar%d" % index
	car.sync_to_physics = true
	_current.add_child(car)
	car.position = Vector3(center.x, float(floors[0]), center.z)
	car.rotation.y = angle
	var car_width: float = half_width * 2.0 - 0.3
	var car_depth: float = half_depth * 2.0 - 0.3
	var plate: StandardMaterial3D = mat(Color(0.5, 0.52, 0.5), "metal", 0.5)
	_car_part(car, Vector3(0, -0.08, 0), Vector3(car_width, 0.16, car_depth), mat(Color(0.3, 0.3, 0.32), "panel", 0.8))
	_car_part(car, Vector3(0, DOOR_HEIGHT + 0.1, 0), Vector3(car_width, 0.12, car_depth), plate)
	_car_part(car, Vector3(0, DOOR_HEIGHT * 0.5, -car_depth * 0.5 + 0.03), Vector3(car_width, DOOR_HEIGHT, 0.06), plate)
	for lateral: float in [-1.0, 1.0]:
		_car_part(car, Vector3(lateral * (car_width * 0.5 - 0.03), DOOR_HEIGHT * 0.5, 0), Vector3(0.06, DOOR_HEIGHT, car_depth), plate)
	var lamp_box: MeshInstance3D = MeshInstance3D.new()
	var lamp_mesh: BoxMesh = BoxMesh.new()
	lamp_mesh.size = Vector3(car_width * 0.6, 0.04, car_depth * 0.5)
	lamp_box.mesh = lamp_mesh
	lamp_box.material_override = world._glow(Color(1.0, 0.95, 0.8), 1.4)
	lamp_box.position = Vector3(0, DOOR_HEIGHT - 0.02, 0)
	car.add_child(lamp_box)
	# Registration with the world.
	var entry: Dictionary = {"index": index, "label": label, "car": car, "floors": floors.duplicate(), "floor": 0, "from_floor": 0, "t": 1.0, "queued": -1,
		"doors": doors, "open": open, "buttons": [], "panel": -1, "shaft": shaft, "side": side, "node": node}
	world.lifts.append(entry)
	for landing: int in range(floors.size()):
		var y: float = float(floors[landing])
		var button_at: Vector3 = center + side * (half_depth + WALL + 1.0) + along * (opening_width * 0.5 + 0.5) + Vector3(0, y, 0)
		var door_index: int = world.interactable_doors.size()
		world.interactable_doors.append({"index": door_index, "label": "%s  -  FLOOR %d" % [label, landing], "kind": "lift", "position": to_world(button_at),
			"inside": to_world(center + Vector3(0, y, 0)), "outside": to_world(button_at + side * 1.0), "open": false, "district": district, "width": opening_width,
			"lift": index, "floor": landing})
		world._door_nodes.append([])
		(entry["buttons"] as Array).append(door_index)
	var panel_local: Vector3 = center + along * (half_width - 0.35) - side * (half_depth - 0.4)
	var panel_index: int = world.interactable_doors.size()
	world.interactable_doors.append({"index": panel_index, "label": "%s  -  CAR PANEL" % label, "kind": "lift", "position": to_world(panel_local + Vector3(0, float(floors[0]), 0)),
		"inside": to_world(center + Vector3(0, float(floors[0]), 0)), "outside": to_world(center + Vector3(0, float(floors[0]), 0)), "open": false, "district": district, "width": 0.4,
		"lift": index, "floor": -1})
	world._door_nodes.append([])
	entry["panel"] = panel_index
	entry["panel_local"] = Vector3(panel_local.x, 0, panel_local.z)
	world.set_physics_process(true)
	world.set_lift_state(index, 0, 1.0, 0)
	return index


func _car_part(car: Node3D, at: Vector3, part_size: Vector3, material: Material) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = part_size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	car.add_child(instance)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = part_size
	shape.shape = box_shape
	shape.position = at
	car.add_child(shape)


# --- Signs, lights and interiors ------------------------------------------------------------------

## Glowing sign text on a dark board (see FastWorld._neon); `angle` turns it about Y (0 faces local +Z).
func neon_sign(words: String, at: Vector3, angle: float, color: Color, font_size: int = 72, light: bool = false, vertical: bool = false) -> void:
	focus()
	world._neon(words, at, angle, color, font_size, light, vertical)


## Flat painted text (no glow).
func sign_label(words: String, at: Vector3, font_size: int, color: Color, angle: float = 0.0) -> void:
	focus()
	world._label(words, at, font_size, color, angle)


## From here on, geometry goes into a second node whose meshes sit on render layer 2 (INTERIOR_LAYER),
## lit only by interior lamps and drawn within 45 m. Call before furnishing; `end_interior()` goes back.
func begin_interior() -> void:
	if interior == null:
		interior = Node3D.new()
		interior.name = "Interior"
		node.add_child(interior)
	_current = interior
	focus()


func end_interior() -> void:
	_current = node
	focus()


## An interior lamp: an OmniLight3D that lights only the interior render layer. Keep it to one per room group.
func interior_light(at: Vector3, color: Color = Color(1.0, 0.86, 0.62), energy: float = 2.3, light_range: float = 14.0) -> OmniLight3D:
	focus()
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = light_range
	lamp.omni_attenuation = 0.9
	lamp.shadow_enabled = false
	lamp.light_cull_mask = 1 << (world.INTERIOR_LAYER - 1)
	lamp.position = at
	(interior if interior != null else node).add_child(lamp)
	world._interior_lights.append(lamp)
	return lamp


## Merges the meshes (one draw call per material), batches repeats, and puts the interior node's
## geometry on the interior render layer. Call it once, last.
func finish() -> void:
	if _finished:
		return
	_finished = true
	world._finish(node)
	if interior != null:
		world._finish(interior)
		for child: Node in interior.get_children():
			if child is GeometryInstance3D:
				var geometry: GeometryInstance3D = child as GeometryInstance3D
				geometry.layers = 1 << (world.INTERIOR_LAYER - 1)
				geometry.visibility_range_end = 45.0
				geometry.visibility_range_end_margin = 5.0


# --- Placeholder shells (the M1 stubs) -------------------------------------------------------------

## A plain solid shell with a sign and a window grid, filling the plot: what every plot shows until
## its M2 builder replaces the stub. `windows` false leaves the walls blank (clubs).
func stub_shell(shell_height: float, color: Color, tex: String, title: String, sign_color: Color, windows: bool = true, lit: float = 0.4) -> void:
	focus()
	if windows:
		world._tower(Vector2.ZERO, Vector3(size.x, shell_height, size.y), color, tex, Vector3.BACK, title, sign_color, Color(0.29, 0.31, 0.3), lit)
	else:
		world._footprint(Rect2(-size.x * 0.5, -size.y * 0.5, size.x, size.y))
		world._box(Vector3(0, shell_height * 0.5, 0), Vector3(size.x, shell_height, size.y), color, true, tex)
		world._box(Vector3(0, shell_height + 0.16, 0), Vector3(size.x + 0.45, 0.32, size.y + 0.45), Color(0.29, 0.31, 0.3), false, "roof")
		world._neon(title, Vector3(0, 4.6, size.y * 0.5 + 0.3), 0.0, sign_color, clampi(int(size.x * 3.0), 40, 84), false)
	var landmark_at: Vector3 = Vector3(0, 0, size.y * 0.5 + 5.0)
	world._landmark(title.replace("  ", " "), landmark_at)
