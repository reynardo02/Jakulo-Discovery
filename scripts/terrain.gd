extends Node3D
class_name Terrain
## Prozedurales Insel-Terrain mit Klimazonen und vielen Biomen (Landschaften).
##
## Die Höhe entsteht aus Rauschen (Noise). Beim Erzeugen wird sie einmal auf
## einem Gitter ausgewertet und zwischengespeichert; danach beantworten
## height_at()/biome_at() Anfragen direkt aus diesem Gitter - schnell und exakt
## passend zum sichtbaren Mesh. Vor dem Erzeugen (z. B. in Werkzeugen) wird
## direkt aus dem Rauschen gerechnet.
##
## Das Klima folgt einem einfachen Whittaker-Schema: Temperatur (Norden kalt,
## Süden warm, oben kalt) und Feuchtigkeit bestimmen die Landschaft; Hangneigung
## und Wassernähe legen Fels, Strand und Sumpf darüber.

enum Biome {
	OCEAN, BEACH, DESERT, GRASSLAND, FOREST, ROCK, SNOW,
	SAVANNA, STEPPE, MEADOW, TAIGA, JUNGLE, SWAMP, TUNDRA,
}

const BIOME_NAMES := {
	Biome.OCEAN: "Meer",
	Biome.BEACH: "Strand",
	Biome.DESERT: "Wüste",
	Biome.GRASSLAND: "Grasland",
	Biome.FOREST: "Laubwald",
	Biome.ROCK: "Gebirge",
	Biome.SNOW: "Schneegipfel",
	Biome.SAVANNA: "Savanne",
	Biome.STEPPE: "Steppe",
	Biome.MEADOW: "Blumenwiese",
	Biome.TAIGA: "Nadelwald",
	Biome.JUNGLE: "Regenwald",
	Biome.SWAMP: "Sumpf",
	Biome.TUNDRA: "Tundra",
}

## Bodenfarben (sRGB).
const BIOME_COLORS := {
	Biome.OCEAN: Color(0.50, 0.46, 0.34),      # Sandboden unter Wasser
	Biome.BEACH: Color(0.84, 0.78, 0.58),
	Biome.DESERT: Color(0.82, 0.67, 0.42),
	Biome.GRASSLAND: Color(0.39, 0.56, 0.24),
	Biome.FOREST: Color(0.25, 0.38, 0.16),     # dunkler Waldboden
	Biome.ROCK: Color(0.45, 0.43, 0.40),
	Biome.SNOW: Color(0.93, 0.95, 0.98),
	Biome.SAVANNA: Color(0.68, 0.60, 0.33),
	Biome.STEPPE: Color(0.58, 0.58, 0.36),
	Biome.MEADOW: Color(0.44, 0.60, 0.26),
	Biome.TAIGA: Color(0.24, 0.32, 0.20),
	Biome.JUNGLE: Color(0.17, 0.35, 0.13),
	Biome.SWAMP: Color(0.29, 0.32, 0.19),
	Biome.TUNDRA: Color(0.52, 0.51, 0.40),
}

## Klimatabelle: Temperatur-Stufen (kalt -> warm), je mit einer Reihe von
## Feuchtigkeits-Stufen (trocken -> nass). Zwischen den Stufen werden die
## Bodenfarben weich überblendet, die Landschaft selbst ist die nächstgelegene.
const TEMP_STOPS := [0.16, 0.33, 0.52, 0.74]
const MOIST_ROWS := [
	[[0.5, Biome.TUNDRA]],
	[[0.30, Biome.STEPPE], [0.56, Biome.TAIGA]],
	[[0.22, Biome.STEPPE], [0.40, Biome.GRASSLAND], [0.53, Biome.MEADOW], [0.66, Biome.FOREST]],
	[[0.24, Biome.DESERT], [0.42, Biome.SAVANNA], [0.56, Biome.GRASSLAND], [0.70, Biome.JUNGLE]],
]

@export_group("Weltgröße")
@export var world_size := 1536.0       ## Kantenlänge der Welt in Metern
@export var chunk_size := 64.0         ## Kantenlänge eines Terrain-Stücks
@export var quad_size := 2.0           ## Abstand zwischen zwei Gitterpunkten
@export var use_threads := true        ## Gitter auf mehreren Kernen berechnen

@export_group("Relief")
@export var noise_seed := 1337
@export var max_height := 120.0        ## Höhe eines maximalen Gipfels
@export var sea_level := 4.5           ## Wasserhöhe (y)
@export var detail_height := 1.4       ## Amplitude der feinen Bodenunebenheiten
@export var beach_band := 1.8          ## wie hoch der Sandstreifen über dem Wasser reicht
@export var warp_strength := 70.0      ## wie stark Formen verwirbelt werden (m)
@export var river_width := 0.022       ## Breite der Flusstäler (Rausch-Einheiten)

@export_group("Klima")
@export var north_south_gradient := 0.30  ## Norden (−Z) kälter, Süden (+Z) wärmer
@export var lapse_rate := 0.75         ## Abkühlung von Meereshöhe bis max_height
@export var snow_temperature := 0.08   ## darunter liegt Schnee

var _n_base := FastNoiseLite.new()     ## grobe Landmasse
var _n_ridge := FastNoiseLite.new()    ## Bergkämme
var _n_hills := FastNoiseLite.new()    ## sanfte Hügel im Flachland
var _n_detail := FastNoiseLite.new()   ## feine Unebenheiten der Oberfläche
var _n_warp := FastNoiseLite.new()     ## verzieht die Koordinaten -> natürlichere Formen
var _n_river := FastNoiseLite.new()    ## Flussläufe (Nullstellen des Rauschens)
var _n_moist := FastNoiseLite.new()    ## Feuchtigkeit
var _n_temp := FastNoiseLite.new()     ## Temperatur
var _n_coast := FastNoiseLite.new()    ## ausgefranste Küstenlinie
var _n_tint := FastNoiseLite.new()     ## leichte Farbvariation
var _n_patch := FastNoiseLite.new()    ## großflächige Farbflecken

var _material := ShaderMaterial.new()

# Zwischengespeichertes Gitter (nach compute_data()).
var _has_grid := false
var _n := 0                            ## Gitterpunkte pro Kante
var _heights := PackedFloat32Array()   ## (_n + 2)² inkl. Randstreifen
var _colors := PackedColorArray()      ## _n² Bodenfarben (sRGB)
var _biomes := PackedByteArray()       ## _n² Biome
var _rows := []                        ## Zwischenablage für die Threads
var _rows_b := []


# --------------------------------------------------------------------------
# Erzeugen
# --------------------------------------------------------------------------

## Berechnet das Gitter und baut Meshes und Kollision. Wird von world.gd
## aufgerufen, sobald der Ladebildschirm sichtbar ist.
func generate() -> void:
	var t0 := Time.get_ticks_msec()
	compute_data()
	var t1 := Time.get_ticks_msec()
	_setup_material()
	_build()
	print("Terrain: %d x %d m, Gitter %d ms, Meshes %d ms." % [
		int(world_size), int(world_size), t1 - t0, Time.get_ticks_msec() - t1])


## Nur die Daten (Höhen, Farben, Biome) berechnen - ohne Knoten zu erzeugen.
func compute_data() -> void:
	_setup_noise()
	_n = int(round(world_size / quad_size)) + 1
	var w := _n + 2

	_rows.resize(w)
	_run_rows(_height_row, w)
	_heights = PackedFloat32Array()
	for row: PackedFloat32Array in _rows:
		_heights.append_array(row)

	_rows.clear()
	_rows.resize(_n)
	_rows_b.resize(_n)
	_run_rows(_color_row, _n)
	_colors = PackedColorArray()
	_biomes = PackedByteArray()
	for j in _n:
		_colors.append_array(_rows[j])
		_biomes.append_array(_rows_b[j])
	_rows.clear()
	_rows_b.clear()
	_has_grid = true


func _run_rows(fn: Callable, count: int) -> void:
	if use_threads:
		var task := WorkerThreadPool.add_group_task(fn, count, -1, true, "Terrain")
		WorkerThreadPool.wait_group_task_completion(task)
	else:
		for j in count:
			fn.call(j)


## Eine Zeile Höhenwerte (inkl. Randstreifen) - läuft ggf. in einem Thread.
func _height_row(j: int) -> void:
	var w := _n + 2
	var half := world_size * 0.5
	var z := -half + (j - 1) * quad_size
	var row := PackedFloat32Array()
	row.resize(w)
	for i in w:
		row[i] = _noise_height(-half + (i - 1) * quad_size, z)
	_rows[j] = row


## Eine Zeile Bodenfarben und Biome - läuft ggf. in einem Thread.
func _color_row(j: int) -> void:
	var w := _n + 2
	var half := world_size * 0.5
	var z := -half + j * quad_size
	var cols := PackedColorArray()
	cols.resize(_n)
	var bios := PackedByteArray()
	bios.resize(_n)
	for i in _n:
		var x := -half + i * quad_size
		var c := (j + 1) * w + i + 1
		var y := _heights[c]
		var ny := _grid_normal_y(c, w)
		var clim := _climate(x, z, y)
		bios[i] = _classify_climate(y, ny, clim.x, clim.y)
		cols[i] = _ground_color(x, z, y, ny, clim.x, clim.y)
	_rows[j] = cols
	_rows_b[j] = bios


func _grid_normal_y(c: int, w: int) -> float:
	var dx := _heights[c - 1] - _heights[c + 1]
	var dz := _heights[c - w] - _heights[c + w]
	var ny := 2.0 * quad_size
	return ny / sqrt(dx * dx + ny * ny + dz * dz)


# --------------------------------------------------------------------------
# Öffentliche Abfragen
# --------------------------------------------------------------------------

## Geländehöhe an einer Weltposition (exakt auf der Mesh-Oberfläche).
func height_at(x: float, z: float) -> float:
	if not _has_grid:
		return _noise_height(x, z)
	var half := world_size * 0.5
	var fx := (x + half) / quad_size
	var fz := (z + half) / quad_size
	if fx < 0.0 or fz < 0.0 or fx > _n - 1 or fz > _n - 1:
		return _noise_height(x, z)
	var i := mini(int(fx), _n - 2)
	var j := mini(int(fz), _n - 2)
	fx -= i
	fz -= j
	var w := _n + 2
	var a := (j + 1) * w + i + 1
	var ha := _heights[a]
	var hb := _heights[a + 1]
	var hc := _heights[a + w]
	var hd := _heights[a + w + 1]
	# Dieselbe Dreiecksaufteilung wie im Mesh: Diagonale von b nach c.
	if fx + fz <= 1.0:
		return ha + (hb - ha) * fx + (hc - ha) * fz
	return hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)


## Oberflächennormale (zeigt vom Boden weg) - nützlich für Hangprüfungen.
func normal_at(x: float, z: float) -> Vector3:
	var e := quad_size
	return Vector3(
		height_at(x - e, z) - height_at(x + e, z),
		2.0 * e,
		height_at(x, z - e) - height_at(x, z + e)).normalized()


## Feuchtigkeit 0..1 an einer Weltposition.
func moisture_at(x: float, z: float) -> float:
	return _climate(x, z, height_at(x, z)).y


## Temperatur 0..1 an einer Weltposition (0 = eisig, 1 = heiß).
func temperature_at(x: float, z: float) -> float:
	return _climate(x, z, height_at(x, z)).x


## Temperatur als grobe Gradzahl für die Anzeige.
func celsius_at(x: float, z: float) -> float:
	return lerpf(-14.0, 36.0, temperature_at(x, z))


## Welche Landschaft liegt an dieser Stelle?
func biome_at(x: float, z: float) -> Biome:
	var g := _grid_index(x, z)
	if g >= 0:
		return _biomes[g] as Biome
	var y := height_at(x, z)
	return _classify(x, z, y, normal_at(x, z).y)


## Bodenfarbe (sRGB) - damit Gras und Karte zum Boden passen.
func ground_color_at(x: float, z: float) -> Color:
	var g := _grid_index(x, z)
	if g >= 0:
		return _colors[g]
	var y := height_at(x, z)
	var clim := _climate(x, z, y)
	return _ground_color(x, z, y, normal_at(x, z).y, clim.x, clim.y)


func biome_name(b: Biome) -> String:
	return BIOME_NAMES[b]


## Ist diese Position innerhalb der Weltgrenzen?
func is_inside(x: float, z: float) -> bool:
	var half := world_size * 0.5
	return absf(x) < half and absf(z) < half


## Sucht spiralförmig vom Zentrum aus einen angenehmen Startplatz an Land,
## bevorzugt auf offener Wiese.
func find_spawn() -> Vector3:
	var fallback := Vector3.INF
	for radius in range(0, int(world_size * 0.5), 8):
		for step in 32:
			var a := TAU * step / 32.0
			var x := cos(a) * radius
			var z := sin(a) * radius
			var y := height_at(x, z)
			if y < sea_level + beach_band + 2.0:
				continue
			if normal_at(x, z).y < 0.95:
				continue
			var b := biome_at(x, z)
			if b == Biome.GRASSLAND or b == Biome.MEADOW:
				return Vector3(x, y + 0.2, z)
			if fallback == Vector3.INF and b != Biome.ROCK and b != Biome.SNOW and b != Biome.SWAMP:
				fallback = Vector3(x, y + 0.2, z)
	if fallback != Vector3.INF:
		return fallback
	return Vector3(0.0, height_at(0, 0) + 0.2, 0.0)


## Übersichtskarte mit Schummerung, z. B. für die Karte im Spiel.
func map_image(res: int) -> Image:
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	var half := world_size * 0.5
	var step := world_size / res
	var sun := Vector3(0.45, 0.78, -0.45).normalized()
	var w := _n + 2
	for j in res:
		var z := -half + (j + 0.5) * step
		for i in res:
			var x := -half + (i + 0.5) * step
			var y: float
			var nrm: Vector3
			var g := _grid_index(x, z)
			if g >= 0:
				var c := (g / _n + 1) * w + g % _n + 1
				y = _heights[c]
				nrm = Vector3(_heights[c - 1] - _heights[c + 1], 2.0 * quad_size,
					_heights[c - w] - _heights[c + w]).normalized()
			else:
				y = height_at(x, z)
				nrm = normal_at(x, z)
			var col: Color
			if y < sea_level:
				var depth := clampf((sea_level - y) / 8.0, 0.0, 1.0)
				col = Color(0.22, 0.47, 0.60).lerp(Color(0.06, 0.17, 0.33), depth)
			else:
				var light := clampf(sun.dot(nrm), 0.0, 1.0)
				col = ground_color_at(x, z) * (0.55 + 0.6 * light)
			img.set_pixel(i, j, col)
	return img


# --------------------------------------------------------------------------
# Rauschen und Relief
# --------------------------------------------------------------------------

func _setup_noise() -> void:
	_n_base.seed = noise_seed
	_n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_base.frequency = 0.0013
	_n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_base.fractal_octaves = 6

	_n_ridge.seed = noise_seed + 101
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_ridge.frequency = 0.0021
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_ridge.fractal_octaves = 4

	_n_hills.seed = noise_seed + 606
	_n_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_hills.frequency = 0.009
	_n_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_hills.fractal_octaves = 3

	_n_detail.seed = noise_seed + 505
	_n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_detail.frequency = 0.05
	_n_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_detail.fractal_octaves = 2

	_n_warp.seed = noise_seed + 707
	_n_warp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_warp.frequency = 0.0022
	_n_warp.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_warp.fractal_octaves = 2

	_n_river.seed = noise_seed + 808
	_n_river.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_river.frequency = 0.0017
	_n_river.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_river.fractal_octaves = 3

	_n_moist.seed = noise_seed + 202
	_n_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_moist.frequency = 0.0016
	_n_moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_moist.fractal_octaves = 3

	_n_temp.seed = noise_seed + 909
	_n_temp.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_temp.frequency = 0.0011
	_n_temp.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_temp.fractal_octaves = 2

	_n_coast.seed = noise_seed + 404
	_n_coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_coast.frequency = 0.0025
	_n_coast.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_coast.fractal_octaves = 4

	_n_tint.seed = noise_seed + 303
	_n_tint.frequency = 0.08

	_n_patch.seed = noise_seed + 313
	_n_patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_patch.frequency = 0.012
	_n_patch.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_patch.fractal_octaves = 2


## Höhe direkt aus dem Rauschen - Grundlage für das Gitter.
func _noise_height(x: float, z: float) -> float:
	# Koordinaten verwirbeln: Küsten, Täler und Kämme werden unregelmäßiger.
	var wx := x + _n_warp.get_noise_2d(x, z) * warp_strength
	var wz := z + _n_warp.get_noise_2d(z + 517.0, x - 311.0) * warp_strength

	var b := _n_base.get_noise_2d(wx, wz) * 0.5 + 0.5
	b = pow(b, 1.25)
	# Bergkämme nur dort einblenden, wo das Land ohnehin schon hoch liegt.
	var mask := smoothstep(0.28, 0.64, b)
	var r := 1.0 - absf(_n_ridge.get_noise_2d(wx, wz))
	r = r * r
	var e := clampf(b * 0.50 + r * mask * 0.64, 0.0, 1.3)
	# Sanfte Hügel im Flachland, in den Bergen gehen sie im Relief unter.
	e += _n_hills.get_noise_2d(wx, wz) * 0.035 * (1.0 - mask)
	# Täler flacher, Gipfel steiler - wirkt wie abgetragen und aufgeschüttet.
	e = clampf(e, 0.0, 1.2)
	e *= 0.55 + 0.45 * e

	var detail := _n_detail.get_noise_2d(x, z) * detail_height * (0.4 + 1.8 * e)
	var h := (e * max_height + detail) * _island_falloff(x, z)

	# Flusstäler: Nullstellen des Fluss-Rauschens werden bis unter den
	# Meeresspiegel eingegraben - im Flachland fließt dort Wasser, in den
	# Hügeln bleiben breite Täler.
	var rv := absf(_n_river.get_noise_2d(wx, wz))
	var lowland := 1.0 - smoothstep(0.30, 0.56, b)
	var carve := (1.0 - smoothstep(0.0, river_width * 3.5, rv)) * 0.55 \
		+ (1.0 - smoothstep(0.0, river_width, rv)) * 0.45
	carve *= lowland
	var bed := sea_level - 1.6
	if h > bed:
		h = lerpf(h, bed, carve * carve * (3.0 - 2.0 * carve))
	return h


## Lässt das Land zum Rand hin ins Meer abfallen -> die Welt ist eine Insel.
func _island_falloff(x: float, z: float) -> float:
	var half := world_size * 0.5
	# Runder Grundriss, leicht Richtung Quadrat gezogen, damit die Insel nicht
	# wie ein perfekter Kreis wirkt; dazu eine ausgefranste Küstenlinie.
	var round_d := Vector2(x, z).length() / half
	var square_d := maxf(absf(x), absf(z)) / half
	var d := lerpf(round_d, square_d, 0.3)
	d += _n_coast.get_noise_2d(x, z) * 0.10
	return 1.0 - smoothstep(0.60, 1.0, d)


# --------------------------------------------------------------------------
# Klima und Biome
# --------------------------------------------------------------------------

## Temperatur (x) und Feuchtigkeit (y), beide 0..1.
func _climate(x: float, z: float, y: float) -> Vector2:
	var half := world_size * 0.5
	var above := maxf(y - sea_level, 0.0)
	var t := 0.58 + _n_temp.get_noise_2d(x, z) * 0.75 + (z / half) * north_south_gradient
	t -= above / max_height * lapse_rate
	var m := 0.5 + _n_moist.get_noise_2d(x, z) * 1.0
	# In Wassernähe ist es feuchter.
	m += (1.0 - smoothstep(0.0, 6.0, above)) * 0.10
	return Vector2(clampf(t, 0.0, 1.0), clampf(m, 0.0, 1.0))


## Gewicht für Sumpf: sehr feucht, nicht kalt, knapp über dem Wasser.
func _swamp_weight(y: float, t: float, m: float) -> float:
	return smoothstep(0.64, 0.74, m) * smoothstep(0.28, 0.40, t) \
		* (1.0 - smoothstep(sea_level + 1.5, sea_level + 4.5, y))


func _classify(x: float, z: float, y: float, normal_y: float) -> Biome:
	var clim := _climate(x, z, y)
	return _classify_climate(y, normal_y, clim.x, clim.y)


func _classify_climate(y: float, normal_y: float, t: float, m: float) -> Biome:
	if y < sea_level - 0.25:
		return Biome.OCEAN
	if _swamp_weight(y, t, m) > 0.5:
		return Biome.SWAMP
	if y < sea_level + beach_band:
		return Biome.BEACH
	if t < snow_temperature:
		# An steilen Felswänden bleibt kein Schnee liegen.
		return Biome.ROCK if normal_y < 0.55 else Biome.SNOW
	# Steile Hänge tragen keine Vegetation, egal auf welcher Höhe.
	if normal_y < 0.66:
		return Biome.ROCK
	var row: Array = MOIST_ROWS[_nearest_stop(TEMP_STOPS, t)]
	var best: int = row[0][1]
	var best_d := INF
	for s in row:
		var d := absf(m - float(s[0]))
		if d < best_d:
			best_d = d
			best = s[1]
	return best as Biome


func _nearest_stop(stops: Array, v: float) -> int:
	var best := 0
	for k in range(1, stops.size()):
		if absf(v - float(stops[k])) < absf(v - float(stops[best])):
			best = k
	return best


## Farbe entlang einer Reihe von Stufen linear überblenden.
func _row_color(row: Array, m: float) -> Color:
	if m <= float(row[0][0]):
		return BIOME_COLORS[row[0][1]]
	for k in range(1, row.size()):
		var m1 := float(row[k][0])
		if m <= m1:
			var m0 := float(row[k - 1][0])
			var f := smoothstep(m0, m1, m)
			return (BIOME_COLORS[row[k - 1][1]] as Color).lerp(BIOME_COLORS[row[k][1]], f)
	return BIOME_COLORS[row[row.size() - 1][1]]


## Bodenfarbe (sRGB) mit weichen Übergängen zwischen den Landschaften.
func _ground_color(x: float, z: float, y: float, normal_y: float, t: float, m: float) -> Color:
	# Klima-Grundfarbe: erst entlang der Feuchte, dann entlang der Temperatur.
	# Nur die beiden Stufen links und rechts der Temperatur sind beteiligt.
	var k := 1
	while k < TEMP_STOPS.size() - 1 and t > float(TEMP_STOPS[k]):
		k += 1
	var c: Color = _row_color(MOIST_ROWS[k - 1], m).lerp(
		_row_color(MOIST_ROWS[k], m), smoothstep(float(TEMP_STOPS[k - 1]), float(TEMP_STOPS[k]), t))

	# Großflächige Flecken (trockenere und sattere Stellen).
	var patch := _n_patch.get_noise_2d(x, z)
	c = c.lerp(c * Color(1.08, 1.02, 0.86), clampf(patch, 0.0, 1.0) * 0.6)
	c = c.lerp(c * Color(0.86, 0.96, 0.9), clampf(-patch, 0.0, 1.0) * 0.6)

	c = c.lerp(BIOME_COLORS[Biome.SWAMP], _swamp_weight(y, t, m))

	# Fels an steilen Hängen; höher oben etwas heller und kühler.
	var rock := 1.0 - smoothstep(0.60, 0.74, normal_y)
	var rock_col: Color = (BIOME_COLORS[Biome.ROCK] as Color).lerp(Color(0.55, 0.55, 0.56), 1.0 - smoothstep(0.1, 0.4, t))
	c = c.lerp(rock_col, rock)

	# Schnee, der an sehr steilen Wänden nicht liegen bleibt.
	var snow := (1.0 - smoothstep(snow_temperature - 0.035, snow_temperature + 0.035, t)) \
		* smoothstep(0.50, 0.60, normal_y)
	c = c.lerp(BIOME_COLORS[Biome.SNOW], snow)

	# Strand: in kalten Gegenden grauer Kies statt hellem Sand.
	var sand: Color = (BIOME_COLORS[Biome.BEACH] as Color).lerp(Color(0.55, 0.53, 0.49), 1.0 - smoothstep(0.2, 0.4, t))
	var beach := (1.0 - smoothstep(sea_level + beach_band - 0.5, sea_level + beach_band + 0.6, y)) \
		* (1.0 - _swamp_weight(y, t, m))
	c = c.lerp(sand, beach)

	# Unter Wasser: nasser, dunkler Grund.
	c = c.lerp(BIOME_COLORS[Biome.OCEAN], 1.0 - smoothstep(sea_level - 0.8, sea_level + 0.1, y))

	var v := _n_tint.get_noise_2d(x, z) * 0.045
	return Color(clampf(c.r + v, 0.0, 1.0), clampf(c.g + v, 0.0, 1.0), clampf(c.b + v, 0.0, 1.0))


func _grid_index(x: float, z: float) -> int:
	if not _has_grid:
		return -1
	var half := world_size * 0.5
	var i := int(round((x + half) / quad_size))
	var j := int(round((z + half) / quad_size))
	if i < 0 or j < 0 or i >= _n or j >= _n:
		return -1
	return j * _n + i


# --------------------------------------------------------------------------
# Meshes und Kollision
# --------------------------------------------------------------------------

func _setup_material() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed + 11
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.03
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	_material.shader = load("res://shaders/terrain.gdshader")
	_material.set_shader_parameter("detail_noise", tex)


func _build() -> void:
	var qpc := int(round(chunk_size / quad_size))    # Quads pro Chunk-Kante
	var chunks := int(ceil(float(_n - 1) / qpc))
	for cz in chunks:
		for cx in chunks:
			_build_chunk(cx * qpc, cz * qpc, qpc)


func _build_chunk(gi: int, gj: int, qpc: int) -> void:
	var half := world_size * 0.5
	var w := _n + 2
	var side_x := mini(qpc, _n - 1 - gi) + 1
	var side_z := mini(qpc, _n - 1 - gj) + 1
	var ox := -half + gi * quad_size
	var oz := -half + gj * quad_size

	var count := side_x * side_z
	var verts := PackedVector3Array(); verts.resize(count)
	var norms := PackedVector3Array(); norms.resize(count)
	var cols := PackedColorArray();   cols.resize(count)
	var uvs := PackedVector2Array();  uvs.resize(count)

	for j in side_z:
		for i in side_x:
			var c := (gj + j + 1) * w + gi + i + 1
			var y := _heights[c]
			var nrm := Vector3(
				_heights[c - 1] - _heights[c + 1],
				2.0 * quad_size,
				_heights[c - w] - _heights[c + w]).normalized()
			var idx := j * side_x + i
			verts[idx] = Vector3(i * quad_size, y, j * quad_size)   # lokal zum Chunk
			norms[idx] = nrm
			# Vertexfarben landen unkonvertiert im Shader, der linear rechnet.
			cols[idx] = _colors[(gj + j) * _n + gi + i].srgb_to_linear()
			uvs[idx] = Vector2(ox + i * quad_size, oz + j * quad_size) * 0.05

	# Indizes in derselben Reihenfolge wie Godots PlaneMesh (korrekte Winding-Order).
	var indices := PackedInt32Array()
	for j in range(1, side_z):
		var prev := (j - 1) * side_x
		var cur := j * side_x
		for i in range(1, side_x):
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
	body.name = "Chunk_%d_%d" % [gi, gj]
	body.position = Vector3(ox, 0.0, oz)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)

	# Höhenfeld-Kollision: viel günstiger als ein Dreiecksnetz. Das Feld ist
	# zentriert und hat 1 m Abstand - daher skalieren und Höhen teilen.
	var col := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = side_x
	shape.map_depth = side_z
	var data := PackedFloat32Array()
	data.resize(count)
	for k in count:
		data[k] = verts[k].y / quad_size
	shape.map_data = data
	col.shape = shape
	col.scale = Vector3.ONE * quad_size
	col.position = Vector3((side_x - 1) * quad_size * 0.5, 0.0, (side_z - 1) * quad_size * 0.5)
	body.add_child(col)

	add_child(body)
