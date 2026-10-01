extends Node3D
class_name Achievements
## Erfolge fürs Erkunden.
##
## Beim Start werden aus dem Gelände besondere Orte bestimmt (höchster Gipfel,
## die äußersten Punkte der Insel, das Herz jeder großen Landschaft). Jeder Ort
## bekommt eine Steinsäule mit einem weithin sichtbaren Lichtstrahl. Wer einen
## Ort erreicht, eine neue Landschaft betritt, weit läuft oder extreme Kälte
## und Hitze erlebt, schaltet Erfolge frei. Der Fortschritt wird pro Insel
## (noise_seed) in user://erfolge.cfg gespeichert.

signal unlocked(title: String, description: String)

const SAVE_PATH := "user://erfolge.cfg"
const REACH_RADIUS := 14.0             ## so nah muss man an einen Ort heran
const MIN_SPACING := 140.0             ## Mindestabstand zwischen zwei Orten
const CHECK_INTERVAL := 0.25

## Erfolg für das erste Betreten einer Landschaft: Titel, Beschreibung.
const BIOME_ACHIEVEMENTS := {
	Terrain.Biome.BEACH: ["Sand zwischen den Zehen", "Betritt einen Strand."],
	Terrain.Biome.DESERT: ["Wüstenwanderer", "Betritt die Wüste."],
	Terrain.Biome.GRASSLAND: ["Weites Land", "Betritt das Grasland."],
	Terrain.Biome.FOREST: ["Unter Blättern", "Betritt einen Laubwald."],
	Terrain.Biome.ROCK: ["Bergsteiger", "Betritt das Gebirge."],
	Terrain.Biome.SNOW: ["Ewiges Eis", "Betritt ein Schneefeld."],
	Terrain.Biome.SAVANNA: ["Safari", "Betritt die Savanne."],
	Terrain.Biome.STEPPE: ["Steppenwind", "Betritt die Steppe."],
	Terrain.Biome.MEADOW: ["Blumenmeer", "Betritt eine Blumenwiese."],
	Terrain.Biome.TAIGA: ["Unter Nadeln", "Betritt einen Nadelwald."],
	Terrain.Biome.JUNGLE: ["Grüne Hölle", "Betritt den Regenwald."],
	Terrain.Biome.SWAMP: ["Nasse Füße", "Betritt einen Sumpf."],
	Terrain.Biome.TUNDRA: ["Kalte Weite", "Betritt die Tundra."],
}

## Landschaften, deren Mitte ein eigener Ort wird: Name des Ortes.
const BIOME_HEARTS := {
	Terrain.Biome.DESERT: "Herz der Wüste",
	Terrain.Biome.JUNGLE: "Tiefer Regenwald",
	Terrain.Biome.SWAMP: "Nebelsumpf",
	Terrain.Biome.SAVANNA: "Akazienebene",
	Terrain.Biome.TAIGA: "Stiller Nadelwald",
	Terrain.Biome.MEADOW: "Blütental",
	Terrain.Biome.TUNDRA: "Frostebene",
	Terrain.Biome.FOREST: "Alter Hain",
	Terrain.Biome.STEPPE: "Windige Steppe",
}

@export var terrain_path: NodePath = ^"../Terrain"
@export var player_path: NodePath = ^"../Player"

## Orte: { id, name, pos: Vector3 }
var landmarks: Array[Dictionary] = []
## Erfolge in Anzeigereihenfolge: { id, title, desc }
var defs: Array[Dictionary] = []

var _terrain: Terrain
var _player: Node3D
var _done := {}                        ## id -> true
var _visited_biomes := {}              ## Biome -> true
var _land_biomes := {}                 ## Biome -> true (kommt auf der Insel vor)
var _distance := 0.0
var _last_pos := Vector3.INF
var _summit_height := 0.0
var _time := 0.0
var _save_timer := 0.0
var _active := false
var _beams := {}                       ## Ort-id -> MeshInstance3D
var _beam_open := StandardMaterial3D.new()
var _beam_done := StandardMaterial3D.new()


# --------------------------------------------------------------------------
# Einrichten
# --------------------------------------------------------------------------

## Bestimmt die Orte - vor dem Bewuchs aufrufen, damit dort Platz bleibt.
func find_landmarks() -> Array[Vector3]:
	_terrain = get_node_or_null(terrain_path) as Terrain
	_player = get_node_or_null(player_path) as Node3D
	var t0 := Time.get_ticks_msec()
	_scan()
	print("Erfolge: %d Orte bestimmt in %d ms." % [landmarks.size(), Time.get_ticks_msec() - t0])
	var out: Array[Vector3] = []
	for l in landmarks:
		out.append(l["pos"])
	return out


## Erfolge aufbauen, Spielstand laden, Säulen setzen und loslegen.
func start() -> void:
	_build_defs()
	_load()
	_build_markers()
	_active = true


func total() -> int:
	return defs.size()


func unlocked_count() -> int:
	return _done.size()


func is_unlocked(id: String) -> bool:
	return _done.has(id)


func is_landmark_found(l: Dictionary) -> bool:
	return _done.has("ort_" + String(l["id"]))


# --------------------------------------------------------------------------
# Orte finden
# --------------------------------------------------------------------------

func _scan() -> void:
	var half := _terrain.world_size * 0.5
	var step := 12.0
	var sea := _terrain.sea_level
	var summit := Vector3(0, -INF, 0)
	var extremes := {"n": Vector3.INF, "s": Vector3.INF, "w": Vector3.INF, "o": Vector3.INF}
	var best_heart := {}               ## Biome -> [Reinheit, Position]

	var z := -half + step
	while z < half - step:
		var x := -half + step
		while x < half - step:
			var y := _terrain.height_at(x, z)
			if y > sea + 2.5:
				var b := _terrain.biome_at(x, z)
				_land_biomes[b] = true
				var p := Vector3(x, y, z)
				if y > summit.y:
					summit = p
				if b != Terrain.Biome.ROCK and b != Terrain.Biome.SNOW:
					if extremes["n"] == Vector3.INF or z < extremes["n"].z: extremes["n"] = p
					if extremes["s"] == Vector3.INF or z > extremes["s"].z: extremes["s"] = p
					if extremes["w"] == Vector3.INF or x < extremes["w"].x: extremes["w"] = p
					if extremes["o"] == Vector3.INF or x > extremes["o"].x: extremes["o"] = p
				if BIOME_HEARTS.has(b):
					var purity := _purity(x, z, b)
					if not best_heart.has(b) or purity > best_heart[b][0]:
						best_heart[b] = [purity, p]
			x += step
		z += step
	# Strand zählt auch, wenn er knapp unter der Schwelle liegt.
	_land_biomes[Terrain.Biome.BEACH] = true

	_summit_height = summit.y
	_add_landmark("gipfel", "Höchster Gipfel", summit)
	_add_landmark("nord", "Nordkap", extremes["n"])
	_add_landmark("sued", "Südspitze", extremes["s"])
	_add_landmark("west", "Westküste", extremes["w"])
	_add_landmark("ost", "Ostküste", extremes["o"])
	for b in BIOME_HEARTS:
		if best_heart.has(b) and best_heart[b][0] >= 10:
			_add_landmark("herz_%d" % b, BIOME_HEARTS[b], best_heart[b][1])


## Wie viele Punkte rund um (x, z) zur selben Landschaft gehören (0..16).
func _purity(x: float, z: float, b: int) -> int:
	var n := 0
	for r in [30.0, 60.0]:
		for k in 8:
			var a := TAU * k / 8.0
			if _terrain.biome_at(x + cos(a) * r, z + sin(a) * r) == b:
				n += 1
	return n


func _add_landmark(id: String, title: String, pos: Vector3) -> void:
	if pos == Vector3.INF or not pos.is_finite():
		return
	for l in landmarks:
		if Vector2(pos.x, pos.z).distance_to(Vector2(l["pos"].x, l["pos"].z)) < MIN_SPACING:
			return
	landmarks.append({"id": id, "name": title, "pos": pos})


# --------------------------------------------------------------------------
# Erfolge
# --------------------------------------------------------------------------

func _build_defs() -> void:
	defs.clear()
	for l in landmarks:
		defs.append({"id": "ort_" + String(l["id"]), "title": l["name"],
			"desc": "Erreiche den Ort „%s“." % l["name"]})
	for b in BIOME_ACHIEVEMENTS:
		if _land_biomes.has(b):
			defs.append({"id": "biom_%d" % b, "title": BIOME_ACHIEVEMENTS[b][0],
				"desc": BIOME_ACHIEVEMENTS[b][1]})
	defs.append({"id": "alle_biome", "title": "Weltenbummler", "desc": "Betritt jede Landschaft der Insel."})
	defs.append({"id": "alle_orte", "title": "Kartograph", "desc": "Erreiche alle besonderen Orte."})
	defs.append({"id": "weg_1", "title": "Spaziergänger", "desc": "Lege 1 km zurück."})
	defs.append({"id": "weg_5", "title": "Wanderer", "desc": "Lege 5 km zurück."})
	defs.append({"id": "weg_15", "title": "Langstreckenläufer", "desc": "Lege 15 km zurück."})
	defs.append({"id": "hoehe", "title": "Höhenluft", "desc": "Steige höher als %d m." % int(_summit_height * 0.7)})
	defs.append({"id": "kalt", "title": "Zähneklappern", "desc": "Stehe an einem Ort mit −5 °C oder kälter."})
	defs.append({"id": "heiss", "title": "Hitzewelle", "desc": "Stehe an einem Ort mit 32 °C oder wärmer."})
	defs.append({"id": "wasser", "title": "Wasserratte", "desc": "Geh baden – tiefer als einen Meter."})


func _process(delta: float) -> void:
	if not _active or _player == null:
		return
	var p := _player.global_position
	if _last_pos != Vector3.INF:
		var step := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
		if step < 20.0:                  # Sprünge (z. B. Teleport) nicht mitzählen
			_distance += step
	_last_pos = p

	_time += delta
	_save_timer += delta
	if _save_timer > 10.0:
		_save_timer = 0.0
		_save()
	if _time < CHECK_INTERVAL:
		return
	_time = 0.0
	_check(p)


func _check(p: Vector3) -> void:
	for l in landmarks:
		var lp: Vector3 = l["pos"]
		if Vector2(p.x - lp.x, p.z - lp.z).length() < REACH_RADIUS:
			if _unlock("ort_" + String(l["id"])):
				_mark_found(l)

	var b := _terrain.biome_at(p.x, p.z)
	if p.y > _terrain.sea_level - 0.3 and _land_biomes.has(b):
		_visited_biomes[b] = true
		_unlock("biom_%d" % b)

	if _distance >= 1000.0: _unlock("weg_1")
	if _distance >= 5000.0: _unlock("weg_5")
	if _distance >= 15000.0: _unlock("weg_15")
	if p.y > _summit_height * 0.7: _unlock("hoehe")
	var c := _terrain.celsius_at(p.x, p.z)
	if c <= -5.0: _unlock("kalt")
	if c >= 32.0: _unlock("heiss")
	if p.y < _terrain.sea_level - 1.0: _unlock("wasser")

	var all_biomes := true
	for d in defs:
		if String(d["id"]).begins_with("biom_") and not _done.has(d["id"]):
			all_biomes = false
			break
	if all_biomes: _unlock("alle_biome")
	var all_places := true
	for l in landmarks:
		if not is_landmark_found(l):
			all_places = false
			break
	if all_places: _unlock("alle_orte")


## Schaltet einen Erfolg frei. Gibt true zurück, wenn er neu ist.
func _unlock(id: String) -> bool:
	if _done.has(id):
		return false
	for d in defs:
		if d["id"] == id:
			_done[id] = true
			_save()
			unlocked.emit(d["title"], d["desc"])
			print("Erfolg: %s" % d["title"])
			return true
	return false


# --------------------------------------------------------------------------
# Speichern
# --------------------------------------------------------------------------

func _section() -> String:
	return "insel_%d" % _terrain.noise_seed


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var ids: Array = cfg.get_value(_section(), "erfolge", [])
	for id in ids:
		_done[String(id)] = true
	_distance = float(cfg.get_value(_section(), "strecke", 0.0))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)                # andere Inseln behalten
	cfg.set_value(_section(), "erfolge", _done.keys())
	cfg.set_value(_section(), "strecke", _distance)
	cfg.save(SAVE_PATH)


func _exit_tree() -> void:
	if _active:
		_save()


# --------------------------------------------------------------------------
# Säulen und Lichtstrahlen
# --------------------------------------------------------------------------

func _build_markers() -> void:
	for m in [_beam_open, _beam_done]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true           # durch den Dunst hindurch sichtbar
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_open.albedo_color = Color(0.35, 0.8, 1.0, 0.35)
	_beam_done.albedo_color = Color(1.0, 0.78, 0.25, 0.18)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.53, 0.5)
	stone.roughness = 1.0
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.4, 0.85, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.4, 0.85, 1.0)
	glow.emission_energy_multiplier = 2.0

	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.25
	beam_mesh.bottom_radius = 0.7
	beam_mesh.height = 160.0
	beam_mesh.radial_segments = 10
	beam_mesh.rings = 1
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false

	for l in landmarks:
		var root := Node3D.new()
		root.name = "Ort_" + String(l["id"])
		root.position = l["pos"]
		add_child(root)
		# Steinmännchen aus drei flachen Steinen und ein leuchtender Kristall.
		var sizes := [[1.0, 0.45, 0.25], [0.75, 0.35, 0.75], [0.5, 0.3, 1.15]]
		for s in sizes:
			var rock := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = s[0]
			sm.height = s[1] * 2.0
			sm.radial_segments = 8
			sm.rings = 4
			sm.material = stone
			rock.mesh = sm
			rock.position.y = s[2]
			root.add_child(rock)
		var crystal := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.35, 0.8, 0.35)
		pm.material = glow
		crystal.mesh = pm
		crystal.position.y = 1.85
		root.add_child(crystal)

		var beam := MeshInstance3D.new()
		beam.mesh = beam_mesh
		beam.position.y = beam_mesh.height * 0.5 + 1.0
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)
		_beams[l["id"]] = beam
		var col := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.9
		shape.height = 1.6
		cs.shape = shape
		cs.position.y = 0.8
		col.add_child(cs)
		root.add_child(col)
		_set_beam(l, is_landmark_found(l))


func _mark_found(l: Dictionary) -> void:
	_set_beam(l, true)


func _set_beam(l: Dictionary, found: bool) -> void:
	var beam: MeshInstance3D = _beams.get(l["id"])
	if beam == null:
		return
	beam.material_override = _beam_done if found else _beam_open
	# Gefundene Orte leuchten nur noch schwach und niedrig.
	beam.scale = Vector3(1.0, 0.25, 1.0) if found else Vector3.ONE
	beam.position.y = (beam.mesh as CylinderMesh).height * 0.5 * beam.scale.y + 1.0
