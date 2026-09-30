extends Node3D
class_name Scatter
## Verteilt Bäume, Kakteen, Büsche und Felsen passend zum jeweiligen Biom.
##
## Alle Objekte eines Typs landen in einem MultiMeshInstance3D - dadurch kostet
## auch ein dichter Wald nur einen Zeichenaufruf pro Teilmesh.

@export var terrain_path: NodePath = ^"../Terrain"
@export var grid_step := 5.0        ## Rasterabstand der Streupunkte in Metern
@export var jitter := 0.9           ## 0 = starres Raster, 1 = voll zufällig versetzt
@export var scatter_seed := 7
@export var clear_radius := 6.0     ## Freifläche um den Startpunkt
@export var clear_center := Vector3.ZERO

var _terrain: Terrain
var _rng := RandomNumberGenerator.new()
var _buckets := {}                  ## Mesh-Name -> Array[Transform3D]
var _meshes := {}                   ## Mesh-Name -> Mesh
var _obstacles := StaticBody3D.new()


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as Terrain
	if _terrain == null:
		push_error("Scatter: kein Terrain unter '%s' gefunden." % terrain_path)
		return

	_rng.seed = scatter_seed
	if clear_center.is_zero_approx():
		clear_center = _terrain.find_spawn()   # Startplatz freihalten
	_build_meshes()

	_obstacles.name = "Obstacles"
	add_child(_obstacles)

	_place_all()
	_flush_buckets()


# --------------------------------------------------------------------------
# Platzierung
# --------------------------------------------------------------------------

func _place_all() -> void:
	var half := _terrain.world_size * 0.5 - grid_step
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var px := x + _rng.randf_range(-0.5, 0.5) * grid_step * jitter
			var pz := z + _rng.randf_range(-0.5, 0.5) * grid_step * jitter
			_try_place(px, pz)
			z += grid_step
		x += grid_step


func _try_place(x: float, z: float) -> void:
	if Vector2(x - clear_center.x, z - clear_center.z).length() < clear_radius:
		return

	var y := _terrain.height_at(x, z)
	if y < _terrain.sea_level + 0.3:
		return                                   # nichts im Wasser

	var slope := _terrain.normal_at(x, z).y      # 1.0 = eben, 0.0 = senkrecht
	if slope < 0.55:
		return                                   # zu steil für alles

	var pos := Vector3(x, y, z)
	var biome := _terrain.biome_at(x, z)
	var r := _rng.randf()

	match biome:
		Terrain.Biome.FOREST:
			if slope < 0.8: _maybe_rock(pos, r)
			elif r < 0.50: _add_conifer(pos, false)
			elif r < 0.68: _add_broadleaf(pos)
			elif r < 0.88: _add_bush(pos)
		Terrain.Biome.GRASSLAND:
			if r < 0.06: _add_broadleaf(pos)
			elif r < 0.10: _add_conifer(pos, false)
			elif r < 0.28: _add_bush(pos)
			elif r < 0.32: _add_rock(pos, 0.6)
		Terrain.Biome.DESERT:
			if r < 0.10: _add_cactus(pos)
			elif r < 0.18: _add_rock(pos, 0.8)
			elif r < 0.23: _add_deadwood(pos)
			elif r < 0.27: _add_bush(pos)
		Terrain.Biome.ROCK:
			if r < 0.20: _add_rock(pos, 1.3)
			elif r < 0.25 and slope > 0.85: _add_conifer(pos, false)
		Terrain.Biome.SNOW:
			if r < 0.10: _add_conifer(pos, true)
			elif r < 0.22: _add_rock(pos, 1.1)
		Terrain.Biome.BEACH:
			if r < 0.03: _add_rock(pos, 0.7)
			elif r < 0.05: _add_deadwood(pos)
		_:
			pass


func _maybe_rock(pos: Vector3, r: float) -> void:
	if r < 0.15:
		_add_rock(pos, 1.0)


# --------------------------------------------------------------------------
# Einzelne Objekttypen
# --------------------------------------------------------------------------

func _yaw(pos: Vector3, scale_xyz: Vector3) -> Transform3D:
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(scale_xyz)
	return Transform3D(b, pos)


func _add(key: String, xform: Transform3D) -> void:
	if not _buckets.has(key):
		_buckets[key] = []
	_buckets[key].append(xform)


func _add_conifer(pos: Vector3, snowy: bool) -> void:
	var s := _rng.randf_range(0.8, 1.7)
	var xf := _yaw(pos, Vector3(s, s * _rng.randf_range(0.9, 1.3), s))
	_add("conifer_trunk", xf)
	_add("conifer_snow_crown" if snowy else "conifer_crown", xf)
	_collider_cylinder(pos, 0.3 * s, 3.0 * s)


func _add_broadleaf(pos: Vector3) -> void:
	var s := _rng.randf_range(0.9, 1.6)
	var xf := _yaw(pos, Vector3(s, s * _rng.randf_range(0.9, 1.2), s))
	_add("broadleaf_trunk", xf)
	_add("broadleaf_crown", xf)
	_collider_cylinder(pos, 0.35 * s, 3.0 * s)


func _add_bush(pos: Vector3) -> void:
	var s := _rng.randf_range(0.6, 1.3)
	_add("bush", _yaw(pos, Vector3(s, s * _rng.randf_range(0.6, 1.0), s)))


func _add_cactus(pos: Vector3) -> void:
	var s := _rng.randf_range(0.8, 1.5)
	var xf := _yaw(pos, Vector3(s, s, s))
	_add("cactus_body", xf)
	# Ein bis zwei Arme, die seitlich am Stamm ansetzen.
	for side in [1.0, -1.0]:
		if _rng.randf() > 0.62:
			continue
		var h := _rng.randf_range(1.0, 1.7) * s
		var arm_scale := _rng.randf_range(0.45, 0.6)
		var b := xf.basis.scaled(Vector3(arm_scale, arm_scale, arm_scale))
		_add("cactus_arm", Transform3D(b, pos + xf.basis.x * 0.28 * s * side + Vector3.UP * h))
	_collider_cylinder(pos, 0.35 * s, 2.5 * s)


func _add_rock(pos: Vector3, size_mul: float) -> void:
	var s := _rng.randf_range(0.5, 1.8) * size_mul
	var xf := Transform3D(
		Basis(Vector3.UP, _rng.randf() * TAU).scaled(
			Vector3(s, s * _rng.randf_range(0.5, 0.9), s * _rng.randf_range(0.7, 1.2))),
		pos - Vector3.UP * 0.2 * s)
	_add("rock", xf)
	if s > 1.0:
		var shape := SphereShape3D.new()
		shape.radius = 0.8 * s
		_collider(shape, pos + Vector3.UP * 0.2 * s)


func _add_deadwood(pos: Vector3) -> void:
	var s := _rng.randf_range(0.7, 1.2)
	var b := Basis(Vector3.UP, _rng.randf() * TAU) \
		* Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(65.0, 95.0)))
	_add("deadwood", Transform3D(b.scaled(Vector3(s, s, s)), pos + Vector3.UP * 0.2))


# --------------------------------------------------------------------------
# Kollision
# --------------------------------------------------------------------------

func _collider_cylinder(pos: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_collider(shape, pos + Vector3.UP * height * 0.5)


func _collider(shape: Shape3D, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	_obstacles.add_child(cs)


# --------------------------------------------------------------------------
# Meshes und MultiMesh-Ausgabe
# --------------------------------------------------------------------------

func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _cone(radius: float, height: float, mat: StandardMaterial3D, segments := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	c.material = mat
	return c


func _cyl(r_top: float, r_bot: float, height: float, mat: StandardMaterial3D, segments := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	c.material = mat
	return c


func _capsule(radius: float, height: float, mat: StandardMaterial3D, segments := 8) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 3
	c.material = mat
	return c


func _blob(radius: float, mat: StandardMaterial3D, rings := 4, segments := 7) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = rings
	s.material = mat
	return s


## Alle Teilmeshes liegen mit ihrem Fußpunkt auf y=0, damit dieselbe
## Instanz-Transform für Stamm und Krone verwendet werden kann.
func _build_meshes() -> void:
	var bark := _mat(Color(0.33, 0.22, 0.13))
	var dead := _mat(Color(0.52, 0.45, 0.36))
	var needle := _mat(Color(0.13, 0.33, 0.18))
	var leaf := _mat(Color(0.25, 0.48, 0.20))
	var snow := _mat(Color(0.90, 0.93, 0.97), 0.8)
	var green := _mat(Color(0.30, 0.52, 0.30))
	var cactus := _mat(Color(0.28, 0.50, 0.28))
	var stone := _mat(Color(0.44, 0.43, 0.41), 1.0)

	_meshes["conifer_trunk"] = _offset(_cyl(0.13, 0.22, 1.6, bark), 0.8)
	_meshes["conifer_crown"] = _offset(_cone(1.1, 3.6, needle), 3.0)
	_meshes["conifer_snow_crown"] = _offset(_cone(1.1, 3.6, snow), 3.0)
	_meshes["broadleaf_trunk"] = _offset(_cyl(0.16, 0.26, 2.2, bark), 1.1)
	_meshes["broadleaf_crown"] = _offset(_blob(1.5, leaf, 5, 9), 3.4)
	_meshes["bush"] = _offset(_blob(0.8, green, 4, 7), 0.55)
	_meshes["cactus_body"] = _offset(_capsule(0.28, 2.8, cactus, 9), 1.4)
	_meshes["cactus_arm"] = _offset(_capsule(0.24, 1.6, cactus, 8), 0.4)
	_meshes["rock"] = _offset(_blob(1.0, stone, 3, 6), 0.4)
	_meshes["deadwood"] = _offset(_cyl(0.08, 0.14, 2.4, dead, 6), 1.2)


## Verschiebt ein Primitiv nach oben, sodass es auf dem Boden steht.
func _offset(mesh: PrimitiveMesh, y: float) -> ArrayMesh:
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += y
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, mesh.material)
	return out


func _flush_buckets() -> void:
	var total := 0
	for key: String in _buckets:
		var xforms: Array = _buckets[key]
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[key]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		add_child(mmi)
		total += xforms.size()
	_buckets.clear()
	print("Scatter: %d Objekte verteilt, %d Kollisionskörper." % [total, _obstacles.get_child_count()])
