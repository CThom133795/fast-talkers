extends RefCounted
## Walk-in diner: booths, service counter, kitchen and two exits.
## Drive-through and pole sign remain for a later pass. Keep static build(world, plot).

const Rooms = preload("res://scripts/buildings/neighborhood_rooms.gd")


static func build(world: Node3D, plot: Dictionary) -> void:
	Rooms.diner(world, plot)
