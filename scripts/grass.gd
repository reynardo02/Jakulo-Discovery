extends Node3D
class_name Grass
## Gras, Schilf und Blumen rund um die Kamera.
##
## Die Welt ist in quadratische Zellen eingeteilt. Nur Zellen in der Nähe der
## Kamera tragen Gras; sie werden beim Laufen nach und nach erzeugt (höchstens
## ein paar pro Bild, damit nichts ruckelt) und hinter dem Spieler wieder
## entfernt. Jede Zelle ist deterministisch - kehrt man zurück, sieht sie
## wieder gleich aus.

@export var terrain_path: NodePath = ^"../Terrain"
@export var cell_size := 16.0
@export var radius := 64.0             ## bis hierhin werden Zellen erzeugt
@export var density := 2.2             ## Büschel pro m² bei voller Dichte
@export var cells_per_frame := 2

## Pro Landschaft: Dichte (0..1), Halmhöhe min/max, Farbe (sRGB) - mit der
## Bodenfarbe gemischt -, Blumen-Anteil, Schilf-Anteil.
const BIOME_GRASS := {
	Terrain.Biome.GRASSLAND: [1.0, 0.35, 0.65, Color(0.40, 0.60, 0.22), 0.03, 0.0],
	Terrain.Biome.MEADOW: [1.0, 0.40, 0.75, Color(0.44, 0.64, 0.24), 0.20, 0.0],
	Terrain.Biome.FOREST: [0.35, 0.25, 0.45, Color(0.28, 0.46, 0.18), 0.02, 0.0],
	Terrain.Biome.TAIGA: [0.25, 0.2, 0.4, Color(0.30, 0.42, 0.22), 0.0, 0.0],
	Terrain.Biome.JUNGLE: [0.6, 0.5, 0.95, Color(0.20, 0.44, 0.14), 0.05, 0.0],
	Terrain.Biome.SAVANNA: [0.9, 0.6, 1.15, Color(0.76, 0.67, 0.34), 0.0, 0.0],
	Terrain.Biome.STEPPE: [0.7, 0.35, 0.6, Color(0.64, 0.63, 0.37), 0.01, 0.0],
	Terrain.Biome.SWAMP: [0.8, 0.5, 0.9, Color(0.36, 0.44, 0.20), 0.0, 0.35],
	Terrain.Biome.TUNDRA: [0.45, 0.12, 0.25, Color(0.54, 0.53, 0.36), 0.02, 0.0],
	Terrain.Biome.BEACH: [0.06, 0.3, 0.55, Color(0.62, 0.64, 0.40), 0.0, 0.0],
	Terrain.Biome.DESERT: [0.03, 0.2, 0.4, Color(0.70, 0.62, 0.38), 0.0, 0.0],
}

const FLOWER_COLORS := [
	Color(0.98, 0.86, 0.18), Color(0.97, 0.97, 0.95), Color(0.66, 0.42, 0.86),
	Color(0.90, 0.22, 0.20), Color(0.35, 0.52, 0.95), Color(0.98, 0.60, 0.20),
]

var _terrain: Terrain
var _active := false
var _cells := {}                       ## Vector2i -> Node3D
var _queue: Array[Vector2i] = []
var _last_center := Vector2i(1 << 30, 0)
var _grass_mesh: ArrayMesh
var _reed_mesh: ArrayMesh
var _flower_mesh: ArrayMesh
var _grass_mat := ShaderMaterial.new()
var _flower_mat := ShaderMaterial.new()


## Startet das Gras und füllt die Umgebung von `around` sofort.
func start(around: Vector3) -> void:
	_terrain = get_node_or_null(terrain_path) as Terrain
	if _terrain == null:
		push_error("Grass: kein Terrain unter '%s' gefunden." % terrain_path)
		return
	var shader: Shader = load("res://shaders/grass.gdshader")
	_grass_mat.shader = shader
	_flower_mat.shader = shader
	_flower_mat.set_shader_parameter("flowers", true)
	for m in [_grass_mat, _flower_mat]:
		m.set_shader_parameter("fade_end", radius - cell_size * 0.75)
		m.set_shader_parameter("fade_start", radius - cell_size * 0.75 - 18.0)
	_grass_mesh = _blade_clump(5, 0.06, 0.14, 11)
	_reed_mesh = _blade_clump(5, 0.035, 0.08, 12)
	_flower_mesh = _flower()
	_active = true
	_update_cells(around)
	while not _queue.is_empty():
		_build_cell(_queue.pop_front())


func _process(_delta: float) -> void:
	if not _active:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_update_cells(cam.global_position)
	for i in cells_per_frame:
		if _queue.is_empty():
			break
		_build_cell(_queue.pop_front())


func _update_cells(pos: Vector3) -> void:
	var center := Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))
	if center == _last_center:
		return
	_last_center = center
	var reach := int(ceil(radius / cell_size))
	var want := {}
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := center + Vector2i(dx, dz)
			var mid := (Vector2(c) + Vector2(0.5, 0.5)) * cell_size
			if mid.distance_to(Vector2(pos.x, pos.z)) < radius:
				want[c] = true
	# Nicht mehr benötigte Zellen weg, fehlende in die Warteschlange.
	for c: Vector2i in _cells.keys():
		if not want.has(c):
			_cells[c].queue_free()
			_cells.erase(c)
	_queue.clear()
	for c: Vector2i in want:
		if not _cells.has(c):
			_queue.append(c)
	# Nächste Zellen zuerst.
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())


func _build_cell(c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) ^ 0x5F3759DF
	var ox := c.x * cell_size
	var oz := c.y * cell_size
	var sea := _terrain.sea_level
	var attempts := int(cell_size * cell_size * density)

	var grass_x := []
	var grass_c := []
	var reed_x := []
	var reed_c := []
	var flower_x := []
	var flower_c := []
	var flower_head := []

	for k in attempts:
		var x := ox + rng.randf() * cell_size
		var z := oz + rng.randf() * cell_size
		if not _terrain.is_inside(x, z):
			continue
		var biome := _terrain.biome_at(x, z)
		if not BIOME_GRASS.has(biome):
			continue
		var cfg: Array = BIOME_GRASS[biome]
		if rng.randf() > float(cfg[0]):
			continue
		var y := _terrain.height_at(x, z)
		var is_reed: bool = rng.randf() < float(cfg[5])
		# Schilf darf im flachen Wasser stehen, Gras nicht.
		if y < sea + (-0.7 if is_reed else 0.08):
			continue
		var ground := _terrain.ground_color_at(x, z)
		var col: Color = ground.lerp(cfg[3], 0.55)
		var v := rng.randf_range(-0.06, 0.06)
		col = Color(col.r + v, col.g + v * 1.2, col.b + v * 0.5).srgb_to_linear()
		var h := rng.randf_range(cfg[1], cfg[2])
		var rot := Basis(Vector3.UP, rng.randf() * TAU)
		if is_reed:
			h = rng.randf_range(1.2, 2.0)
			var reed_col := Color(0.42, 0.46, 0.24).lerp(Color(0.55, 0.50, 0.30), rng.randf())
			reed_x.append(Transform3D(rot.scaled(Vector3(1.0, h, 1.0)), Vector3(x, y, z)))
			reed_c.append(reed_col.srgb_to_linear())
		elif rng.randf() < float(cfg[4]):
			var fh := rng.randf_range(0.3, 0.55)
			flower_x.append(Transform3D(rot.scaled(Vector3(1.0, fh, 1.0)), Vector3(x, y, z)))
			flower_c.append(col)
			var fc: Color = FLOWER_COLORS[rng.randi() % FLOWER_COLORS.size()]
			flower_head.append(fc.srgb_to_linear())
		else:
			var wscale := rng.randf_range(0.8, 1.3)
			grass_x.append(Transform3D(rot.scaled(Vector3(wscale, h, wscale)), Vector3(x, y, z)))
			grass_c.append(col)

	var node := Node3D.new()
	node.name = "Cell_%d_%d" % [c.x, c.y]
	_add_mm(node, _grass_mesh, _grass_mat, grass_x, grass_c, [])
	_add_mm(node, _reed_mesh, _grass_mat, reed_x, reed_c, [])
	_add_mm(node, _flower_mesh, _flower_mat, flower_x, flower_c, flower_head)
	add_child(node)
	_cells[c] = node


func _add_mm(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array, colors: Array, custom: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
		if not custom.is_empty():
			mm.set_instance_custom_data(i, custom[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)


# --------------------------------------------------------------------------
# Meshes (Höhe 1, werden pro Instanz in y skaliert)
# --------------------------------------------------------------------------

## Ein Büschel aus schmalen, sich verjüngenden und leicht gebogenen Halmen.
func _blade_clump(blades: int, width: float, spread: float, clump_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = clump_seed
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	var levels := [0.0, 0.4, 0.75, 1.0]
	for b in blades:
		var root := Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		var yaw := rng.randf() * TAU
		var side := Vector3(cos(yaw), 0.0, sin(yaw))
		var lean_dir := Vector3(-side.z, 0.0, side.x) * rng.randf_range(0.1, 0.35)
		var h := rng.randf_range(0.7, 1.0)
		var base := verts.size()
		for li in levels.size():
			var t: float = levels[li]
			var center := root + Vector3(0.0, t * h, 0.0) + lean_dir * t * t
			if li == levels.size() - 1:
				verts.append(center)
				uvs.append(Vector2(0.5, t))
			else:
				var wdt := width * (1.0 - t * 0.85)
				verts.append(center - side * wdt)
				verts.append(center + side * wdt)
				uvs.append(Vector2(0.0, t))
				uvs.append(Vector2(1.0, t))
		# Streifen aus Vierecken, oben ein Spitzendreieck.
		for li in levels.size() - 2:
			var a := base + li * 2
			indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
		var last := base + (levels.size() - 2) * 2
		indices.append_array([last, last + 1, last + 2])
	for i in verts.size():
		cols.append(Color(1, 1, 1))
		norms.append(Vector3.UP)
	return _mesh(verts, norms, uvs, cols, indices)


## Blume: Stängel wie ein Halm, darauf ein Kopf aus zwei gekreuzten Blättchen.
## Die Kopf-Vertices tragen UV.x = 2 - daran erkennt der Shader sie.
func _flower() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var w := 0.012
	verts.append_array([Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(-w * 0.6, 1, 0), Vector3(w * 0.6, 1, 0)])
	uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	indices.append_array([0, 1, 2, 1, 3, 2])
	var r := 0.07
	for k in 2:
		var d := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		var o := Vector3(0, 0, 1) if k == 0 else Vector3(1, 0, 0)
		var base := verts.size()
		# Kopf flach liegend (in xz), damit er von oben gut sichtbar ist.
		verts.append_array([
			Vector3(0, 1.0, 0) - d * r - o * r * 0.5, Vector3(0, 1.0, 0) + d * r - o * r * 0.5,
			Vector3(0, 1.0, 0) - d * r + o * r * 0.5, Vector3(0, 1.0, 0) + d * r + o * r * 0.5])
		for q in 4:
			uvs.append(Vector2(2.0, 1.0))
		indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for i in verts.size():
		cols.append(Color(1, 1, 1))
		norms.append(Vector3.UP)
	return _mesh(verts, norms, uvs, cols, indices)


func _mesh(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		cols: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
