extends RefCounted
## Walk-in starter motel: reception, two furnished rooms and two exterior exits.
## M2 still needs the upper walkway, additional rooms and drained pool.

const Rooms = preload("res://scripts/buildings/neighborhood_rooms.gd")


static func build(world: Node3D, plot: Dictionary) -> void:
	Rooms.motel(world, plot)
