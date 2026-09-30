extends Node3D
class_name Terrain
## Prozedurales Insel-Terrain mit mehreren Biomen (Landschaften).
##
## Die Höhe wird aus Rauschen (Noise) berechnet, nicht gespeichert. Dadurch kann
## jedes andere Skript jederzeit mit height_at()/biome_at() nachfragen, wie die
## Welt an einer Stelle aussieht - ohne die Mesh-Daten durchsuchen zu müssen.

enum Biome { OCEAN, BEACH, DESERT, GRASSLAND, FOREST, ROCK, SNOW }

const BIOME_NAMES := {
	Biome.OCEAN: "Meer",
	Biome.BEACH: "Strand",
	Biome.DESERT: "Wüste",
	Biome.GRASSLAND: "Grasland",
	Biome.FOREST: "Wald",
	Biome.ROCK: "Gebirge",
	Biome.SNOW: "Schneegipfel",
}

const BIOME_COLORS := {
	Biome.OCEAN: Color(0.52, 0.47, 0.34),      # Sandboden unter Wasser
	Biome.BEACH: Color(0.83, 0.77, 0.56),
	Biome.DESERT: Color(0.78, 0.66, 0.40),
	Biome.GRASSLAND: Color(0.42, 0.60, 0.26),
	Biome.FOREST: Color(0.21, 0.42, 0.20),
	Biome.ROCK: Color(0.42, 0.41, 0.39),
	Biome.SNOW: Color(0.92, 0.94, 0.97),
}

@export_group("Weltgröße")
@export var world_size := 512.0        ## Kantenlänge der Welt in Metern
@export var chunk_size := 64.0         ## Kantenlänge eines Terrain-Stücks
@export var quad_size := 2.0           ## Abstand zwischen zwei Gitterpunkten

@export_group("Relief")
@export var noise_seed := 1337
@export var max_height := 70.0         ## Höhe eines maximalen Gipfels
@export var sea_level := 4.5           ## Wasserhöhe (y)
@export var rock_height := 26.0        ## ab hier kahler Fels
@export var snow_height := 42.0        ## ab hier Schnee
@export var desert_max_height := 20.0  ## oberhalb davon keine Wüste mehr
@export var detail_height := 1.1       ## Amplitude der feinen Bodenunebenheiten
@export var beach_band := 1.6          ## wie hoch der Sandstreifen über dem Wasser reicht

var _n_base := FastNoiseLite.new()     ## grobe Landmasse
var _n_ridge := FastNoiseLite.new()    ## Bergkämme
var _n_detail := FastNoiseLite.new()   ## feine Unebenheiten der Oberfläche
var _n_moist := FastNoiseLite.new()    ## Feuchtigkeit -> Wüste/Gras/Wald
var _n_coast := FastNoiseLite.new()    ## ausgefranste Küstenlinie
var _n_tint := FastNoiseLite.new()     ## leichte Farbvariation

var _material := StandardMaterial3D.new()


func _ready() -> void:
	_setup_noise()
	_setup_material()
	_build()


# --------------------------------------------------------------------------
# Öffentliche Abfragen
# --------------------------------------------------------------------------

## Geländehöhe an einer Weltposition.
func height_at(x: float, z: float) -> float:
	var e := _elevation01(x, z)
	# Feine Unebenheiten, im Gebirge kräftiger als im Flachland.
	var detail := _n_detail.get_noise_2d(x, z) * detail_height * (0.5 + 1.8 * e)
	return (e * max_height + detail) * _island_falloff(x, z)


## Oberflächennormale (zeigt vom Boden weg) - nützlich für Hangprüfungen.
func normal_at(x: float, z: float) -> Vector3:
	var e := quad_size * 0.5
	return Vector3(
		height_at(x - e, z) - height_at(x + e, z),
		2.0 * e,
		height_at(x, z - e) - height_at(x, z + e)).normalized()


## Feuchtigkeit 0..1 an einer Weltposition.
func moisture_at(x: float, z: float) -> float:
	return _n_moist.get_noise_2d(x, z) * 0.5 + 0.5


## Welche Landschaft liegt an dieser Stelle?
func biome_at(x: float, z: float) -> Biome:
	return _classify(x, z, height_at(x, z), normal_at(x, z).y)


func biome_name(b: Biome) -> String:
	return BIOME_NAMES[b]


## Ist diese Position innerhalb der Weltgrenzen?
func is_inside(x: float, z: float) -> bool:
	var half := world_size * 0.5
	return absf(x) < half and absf(z) < half


## Sucht spiralförmig vom Zentrum aus einen angenehmen Startplatz an Land.
func find_spawn() -> Vector3:
	for radius in range(0, int(world_size * 0.5), 6):
		for step in 24:
			var a := TAU * step / 24.0
			var x := cos(a) * radius
			var z := sin(a) * radius
			var y := height_at(x, z)
			if y < sea_level + beach_band + 2.0 or y > rock_height:
				continue
			if normal_at(x, z).y < 0.94:
				continue
			return Vector3(x, y + 0.2, z)
	return Vector3(0.0, height_at(0, 0) + 0.2, 0.0)


# --------------------------------------------------------------------------
# Interna
# --------------------------------------------------------------------------

func _setup_noise() -> void:
	_n_base.seed = noise_seed
	_n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_base.frequency = 0.0035
	_n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_base.fractal_octaves = 5

	_n_ridge.seed = noise_seed + 101
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_ridge.frequency = 0.0055
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_ridge.fractal_octaves = 3

	_n_detail.seed = noise_seed + 505
	_n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_detail.frequency = 0.055
	_n_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_detail.fractal_octaves = 2

	_n_moist.seed = noise_seed + 202
	_n_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_moist.frequency = 0.004
	_n_moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_moist.fractal_octaves = 3

	_n_coast.seed = noise_seed + 404
	_n_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_coast.frequency = 0.006
	_n_coast.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_coast.fractal_octaves = 3

	_n_tint.seed = noise_seed + 303
	_n_tint.frequency = 0.08


func _setup_material() -> void:
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.95
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED


## Geländehöhe normiert auf ca. 0..1, vor Skalierung und Insel-Abfall.
func _elevation01(x: float, z: float) -> float:
	var b := _n_base.get_noise_2d(x, z) * 0.5 + 0.5
	b = pow(b, 1.25)
	# Bergkämme nur dort einblenden, wo das Land ohnehin schon hoch liegt.
	var mask := smoothstep(0.26, 0.62, b)
	var r := 1.0 - absf(_n_ridge.get_noise_2d(x, z))
	r = r * r
	return clampf(b * 0.52 + r * mask * 0.62, 0.0, 1.3)


## Lässt das Land zum Rand hin ins Meer abfallen -> die Welt ist eine Insel.
func _island_falloff(x: float, z: float) -> float:
	var half := world_size * 0.5
	# Runder Grundriss, leicht Richtung Quadrat gezogen, damit die Insel nicht
	# wie ein perfekter Kreis wirkt; dazu eine ausgefranste Küstenlinie.
	var round_d := Vector2(x, z).length() / half
	var square_d := maxf(absf(x), absf(z)) / half
	var d := lerpf(round_d, square_d, 0.3)
	d += _n_coast.get_noise_2d(x, z) * 0.07
	return 1.0 - smoothstep(0.62, 1.02, d)


func _classify(x: float, z: float, y: float, normal_y: float) -> Biome:
	if y < sea_level - 0.25:
		return Biome.OCEAN
	if y < sea_level + beach_band:
		return Biome.BEACH
	if y > snow_height:
		# An steilen Felswänden bleibt kein Schnee liegen.
		return Biome.ROCK if normal_y < 0.55 else Biome.SNOW
	# Steile Hänge tragen keine Vegetation, egal auf welcher Höhe.
	if y > rock_height or normal_y < 0.62:
		return Biome.ROCK
	var m := moisture_at(x, z)
	if m < 0.40 and y < desert_max_height:
		return Biome.DESERT
	if m < 0.56:
		return Biome.GRASSLAND
	return Biome.FOREST


func _build() -> void:
	var chunks := int(ceil(world_size / chunk_size))
	var origin := -world_size * 0.5
	for cz in chunks:
		for cx in chunks:
			_build_chunk(origin + cx * chunk_size, origin + cz * chunk_size)


func _build_chunk(ox: float, oz: float) -> void:
	var n := int(round(chunk_size / quad_size))     # Quads pro Kante
	var side := n + 1                               # Vertices pro Kante
	var w := n + 3                                  # Höhenfeld inkl. Randstreifen

	# Höhen einmal samplen - inklusive eines Rands, damit die Normalen an den
	# Chunk-Grenzen exakt zu den Nachbarn passen (keine sichtbaren Nähte).
	var h := PackedFloat32Array()
	h.resize(w * w)
	for j in w:
		var z := oz + (j - 1) * quad_size
		for i in w:
			h[j * w + i] = height_at(ox + (i - 1) * quad_size, z)

	var verts := PackedVector3Array(); verts.resize(side * side)
	var norms := PackedVector3Array(); norms.resize(side * side)
	var cols := PackedColorArray();   cols.resize(side * side)
	var uvs := PackedVector2Array();  uvs.resize(side * side)

	for j in side:
		var z := oz + j * quad_size
		for i in side:
			var x := ox + i * quad_size
			var bi := i + 1
			var bj := j + 1
			var y := h[bj * w + bi]
			var nrm := Vector3(
				h[bj * w + bi - 1] - h[bj * w + bi + 1],
				2.0 * quad_size,
				h[(bj - 1) * w + bi] - h[(bj + 1) * w + bi]).normalized()
			var idx := j * side + i
			verts[idx] = Vector3(x - ox, y, z - oz)   # lokal zum Chunk
			norms[idx] = nrm
			cols[idx] = _vertex_color(x, z, y, nrm.y)
			uvs[idx] = Vector2(x, z) * 0.05

	# Indizes in derselben Reihenfolge wie Godots PlaneMesh (korrekte Winding-Order).
	var indices := PackedInt32Array()
	for j in range(1, side):
		var prev := (j - 1) * side
		var cur := j * side
		for i in range(1, side):
			indices.append(prev + i - 1)
			indices.append(prev + i)
			indices.append(cur + i - 1)
			indices.append(prev + i)
			indices.append(cur + i)
			indices.append(cur + i - 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)

	var body := StaticBody3D.new()
	body.name = "Chunk_%d_%d" % [int(ox), int(oz)]
	body.position = Vector3(ox, 0.0, oz)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)

	var col := CollisionShape3D.new()
	col.shape = mesh.create_trimesh_shape()
	body.add_child(col)

	add_child(body)


## Vertexfarben landen unkonvertiert im Renderer, der linear rechnet. Die in
## BIOME_COLORS notierten sRGB-Werte müssen daher selbst umgerechnet werden -
## sonst wirkt das ganze Gelände ausgebleicht.
func _vertex_color(x: float, z: float, y: float, normal_y: float) -> Color:
	var c: Color = BIOME_COLORS[_classify(x, z, y, normal_y)]
	var v := _n_tint.get_noise_2d(x, z) * 0.05
	return Color(clampf(c.r + v, 0.0, 1.0),
			clampf(c.g + v, 0.0, 1.0),
			clampf(c.b + v, 0.0, 1.0)).srgb_to_linear()
