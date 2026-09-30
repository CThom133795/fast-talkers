extends RefCounted
## Sixth-gen texture kit: small procedural greyscale textures (128 px, patterns laid
## out on a 64-cell grid) with bilinear filtering, as the PS2 did, and world-space
## triplanar mapping, so plain boxes read as brick, stucco, asphalt or corrugated metal
## without UVs or asset files. Walls get rain-streak grime for a lived-in city.
## Textures are light (~0.85 mean) so albedo colours keep their intended hue.

const SIZE: int = 128
const GRIMY: Array[String] = ["brick", "stucco", "panel", "metal"]
## Metres covered by one texture repeat for each kind.
const TILE_METRES: Dictionary = {
	"brick": 2.4, "stucco": 3.0, "panel": 4.0, "asphalt": 3.0, "tiles": 2.0, "planks": 1.6,
	"metal": 2.0, "roof": 3.0, "grass": 4.0, "water": 6.0, "cobble": 1.6, "tatami": 2.0,
}

var _textures: Dictionary = {}
var _materials: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func material(kind: String, color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var key: String = kind + str(color) + str(roughness)
	if _materials.has(key):
		return _materials[key] as StandardMaterial3D
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.albedo_texture = texture(kind)
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	result.uv1_triplanar = true
	result.uv1_world_triplanar = true
	var scale: float = 1.0 / float(TILE_METRES.get(kind, 3.0))
	result.uv1_scale = Vector3(scale, scale, scale)
	if kind == "water":
		result.roughness = 0.08
		result.metallic = 0.35
	_materials[key] = result
	return result


func texture(kind: String) -> ImageTexture:
	if _textures.has(kind):
		return _textures[kind] as ImageTexture
	_rng.seed = hash(kind)
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var grimy: bool = GRIMY.has(kind)
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var value: float = _sample(kind, x / 2, y / 2) + _noise(x * 3 + 1, y * 5 + 2, 0.05)
			if grimy:
				value -= _grime(x, y)
			image.set_pixel(x, y, Color(value, value, value))
	image.generate_mipmaps()
	var result: ImageTexture = ImageTexture.create_from_image(image)
	_textures[kind] = result
	return result


## Rain streaks: dark drips that start at random columns and fade as they run down.
func _grime(x: int, y: int) -> float:
	var column: int = x / 3
	var start: float = (_noise(column, 91, 1.0) + 0.5) * float(SIZE)
	var strength: float = maxf(0.0, _noise(column, 17, 1.0)) * 0.34
	var run: float = float(y) - start
	if run < 0.0:
		run += float(SIZE)
	var fade: float = clampf(1.0 - run / (float(SIZE) * 0.55), 0.0, 1.0)
	return strength * fade * fade + maxf(0.0, _noise(x / 9, y / 9, 1.0)) * 0.06


func _noise(x: int, y: int, amount: float) -> float:
	# Hash noise that tiles cleanly on the 64 px grid.
	var n: int = (x * 73856093) ^ (y * 19349663) ^ 83492791
	n = (n ^ (n >> 13)) * 1274126177
	return (float(n & 1023) / 1023.0 - 0.5) * amount


func _sample(kind: String, x: int, y: int) -> float:
	var base: float = 0.86 + _noise(x, y, 0.1)
	match kind:
		"brick":
			var row: int = y / 8
			var offset: int = 8 if row % 2 == 1 else 0
			var mortar: bool = y % 8 == 0 or (x + offset) % 16 == 0
			var brick_tone: float = 0.8 + _noise((x + offset) / 16, row, 0.22)
			return 1.0 if mortar else brick_tone + _noise(x, y, 0.07)
		"stucco":
			return 0.88 + _noise(x / 3, y / 3, 0.12) + _noise(x, y, 0.05) - (0.1 if (x * 7 + y * 3) % 61 == 0 else 0.0)
		"panel":
			if x % 32 == 0 or y % 32 == 0:
				return 0.6
			return 0.84 + _noise(x / 2, y / 2, 0.08) - float(y % 32) * 0.002
		"asphalt":
			var speck: float = 0.14 if _noise(x, y, 1.0) > 0.44 else 0.0
			var crack: float = -0.25 if (x + y * 2) % 47 == 0 and y % 5 < 3 else 0.0
			return 0.78 + _noise(x, y, 0.12) + speck + crack
		"tiles":
			if x % 16 == 0 or y % 16 == 0:
				return 0.66
			return 0.9 + _noise(x / 16, y / 16, 0.12) + _noise(x, y, 0.04)
		"cobble":
			var cell_x: int = (x + (4 if (y / 8) % 2 == 1 else 0)) % 8
			if cell_x == 0 or y % 8 == 0:
				return 0.55
			return 0.82 + _noise((x + 4) / 8, y / 8, 0.2)
		"planks":
			if x % 11 == 0:
				return 0.58
			return 0.8 + _noise(x / 11, 0, 0.14) + sin(float(y) * 0.45 + float(x / 11)) * 0.04
		"metal":
			return 0.8 + sin(float(x) * 0.785) * 0.12 + _noise(x, y, 0.04)
		"roof":
			return 0.8 + _noise(x, y, 0.28)
		"grass":
			return 0.78 + _noise(x, y, 0.3) + _noise(x / 4, y / 4, 0.12)
		"water":
			return 0.8 + sin(float(x) * 0.4 + sin(float(y) * 0.3) * 2.0) * 0.12
		"tatami":
			if y % 32 == 0 or x % 64 == 0:
				return 0.62
			return 0.88 + (0.04 if x % 2 == 0 else -0.02)
	return base
