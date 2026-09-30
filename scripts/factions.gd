extends RefCounted
## The four crews of Port Halcyon. Rules are identical for every crew; this data
## only drives identity: colours, wardrobe, silhouette, cars, HUD accent and neon.
## Colours sit ~90 degrees apart on the hue wheel and each crew has a distinct hat
## silhouette so teams stay readable for colour-blind players.

const ORDER: Array[String] = ["morris", "kingsway", "solnegro", "kojimoto"]

const DATA: Dictionary = {
	"morris": {
		"name": "MORRIS MAFIA", "short": "MORRIS", "kind": "Mafia", "district": "MORRIS PARK",
		"motto": "Family first. Business always.",
		"color": Color("c4283f"), "accent": Color("f0e2c4"),
		"jacket": Color("2b2d33"), "pants": Color("24262b"), "shirt": Color("efe6d2"), "tie": Color("c4283f"),
		"skin": Color("d7a883"), "hair": Color("2a1d16"), "shoes": Color("1a1412"), "hat": "fedora", "hat_color": Color("33302c"),
		"sleeve": Color("2b2d33"), "glove": Color("1c1715"),
		"car": Color("1d1c21"), "car_stripe": Color("c4283f"),
	},
	"kingsway": {
		"name": "KINGSWAY ROYALS", "short": "ROYALS", "kind": "Street gang", "district": "KINGSWAY",
		"motto": "Hold the block.",
		"color": Color("19c2b8"), "accent": Color("f4f1ea"),
		"jacket": Color("148f89"), "pants": Color("147a75"), "shirt": Color("f2f2ee"), "tie": Color("e9c24a"),
		"skin": Color("8a5a3c"), "hair": Color("15110f"), "shoes": Color("f4f4f0"), "hat": "cap", "hat_color": Color("19c2b8"),
		"sleeve": Color("148f89"), "glove": Color("15110f"),
		"car": Color("1a6f7a"), "car_stripe": Color("f4f1ea"),
	},
	"solnegro": {
		"name": "CARTEL SOL NEGRO", "short": "SOL NEGRO", "kind": "Cartel", "district": "SOLANA HEIGHTS",
		"motto": "Todo tiene precio.",
		"color": Color("e8a21a"), "accent": Color("2a211b"),
		"jacket": Color("ece4d0"), "pants": Color("2e3a4f"), "shirt": Color("ece4d0"), "tie": Color("e8a21a"),
		"skin": Color("b98160"), "hair": Color("1d1512"), "shoes": Color("5a3a22"), "hat": "cowboy", "hat_color": Color("d9c49a"),
		"sleeve": Color("ece4d0"), "glove": Color("b98160"),
		"car": Color("ede6d6"), "car_stripe": Color("e8a21a"),
	},
	"kojimoto": {
		"name": "KOJIMOTO893", "short": "KOJIMOTO", "kind": "Yakuza", "district": "LANTERN ROW",
		"motto": "Duty is the only debt.",
		"color": Color("8e5cf0"), "accent": Color("f1ecff"),
		"jacket": Color("16161b"), "pants": Color("16161b"), "shirt": Color("7b46e0"), "tie": Color("f1ecff"),
		"skin": Color("e0b894"), "hair": Color("0d0c10"), "shoes": Color("0e0e11"), "hat": "pompadour", "hat_color": Color("0d0c10"),
		"sleeve": Color("16161b"), "glove": Color("e0b894"),
		"car": Color("2a1f45"), "car_stripe": Color("8e5cf0"),
	},
}


static func get_crew(id: String) -> Dictionary:
	return DATA.get(id, DATA["morris"])


static func color(id: String) -> Color:
	return get_crew(id)["color"]


static func next_id(id: String, step: int = 1) -> String:
	var index: int = ORDER.find(id)
	return ORDER[(maxi(index, 0) + step + ORDER.size()) % ORDER.size()]
