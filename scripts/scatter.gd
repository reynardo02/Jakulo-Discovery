extends Node3D
class_name Scatter
## Verteilt Bäume, Palmen, Kakteen, Büsche, Farne und Felsen passend zum Biom.
##
## Alle Objekte eines Typs landen - aufgeteilt in Regionen - in
## MultiMeshInstance3D-Knoten. So kostet ein dichter Wald nur wenige
## Zeichenaufrufe, und Regionen außerhalb der Sicht oder jenseits ihrer
## Sichtweite werden gar nicht gezeichnet.

@export var terrain_path: NodePath = ^"../Terrain"
@export var grid_step := 4.5        ## Rasterabstand der Streupunkte in Metern
@export var jitter := 0.9           ## 0 = starres Raster, 1 = voll zufällig versetzt
@export var scatter_seed := 7
@export var clear_radius := 8.0     ## Freifläche um den Startpunkt
@export var region_size := 128.0    ## Kantenlänge einer Sichtbarkeits-Region

## Sichtweite je Objekttyp in Metern (danach wird ausgeblendet).
const VIEW_RANGE := {
	"conifer": 700.0, "conifer_snow": 700.0, "broadleaf": 700.0, "jungle_tree": 650.0,
	"palm": 600.0, "acacia": 700.0, "dead_tree": 450.0, "bush": 240.0, "dry_bush": 200.0,
	"fern": 130.0, "cactus": 400.0, "cactus_arm": 400.0, "rock": 300.0, "boulder": 900.0,
	"log": 200.0,
}

var _terrain: Terrain
var _rng := RandomNumberGenerator.new()
var _buckets := {}                  ## Typ -> { Vector2i Region -> [Array[Transform3D], Array[Color]] }
var _meshes := {}                   ## Typ -> Mesh
var _bodies := {}                   ## Vector2i Region -> RID (statischer Physikkörper)
var _shapes := []                   ## hält die Kollisionsformen am Leben
var _clear_center := Vector3.ZERO
var _blocked := {}                  ## Vector2i (4-m-Raster) -> true: hier bleibt es frei
var _count := 0


func generate(clear_center: Vector3, keep_free: Array[Vector3] = []) -> void:
	_terrain = get_node_or_null(terrain_path) as Terrain
	if _terrain == null:
		push_error("Scatter: kein Terrain unter '%s' gefunden." % terrain_path)
		return
	var t0 := Time.get_ticks_msec()
	_rng.seed = scatter_seed
	_clear_center = clear_center
	# Rund um besondere Orte (Erfolge) nichts hinstellen.
	for p in keep_free:
		var c := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				_blocked[c + Vector2i(dx, dz)] = true
	_build_meshes()
	_place_all()
	_flush_buckets()
	print("Scatter: %d Objekte, %d Kollisionskörper in %d ms." % [
		_count, _shapes.size(), Time.get_ticks_msec() - t0])


func _exit_tree() -> void:
	for rid: RID in _bodies.values():
		PhysicsServer3D.free_rid(rid)
	_bodies.clear()


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
	if Vector2(x - _clear_center.x, z - _clear_center.z).length() < clear_radius:
		return
	if _blocked.has(Vector2i(floori(x / 4.0), floori(z / 4.0))):
		return

	var y := _terrain.height_at(x, z)
	if y < _terrain.sea_level + 0.3:
		return                                   # nichts im Wasser

	var biome := _terrain.biome_at(x, z)
	if biome == Terrain.Biome.OCEAN:
		return
	var slope := _terrain.normal_at(x, z).y      # 1.0 = eben, 0.0 = senkrecht
	if slope < 0.55:
		return                                   # zu steil für alles

	var pos := Vector3(x, y, z)
	var r := _rng.randf()

	match biome:
		Terrain.Biome.FOREST:
			if slope < 0.8:
				if r < 0.15: _add_rock(pos, 1.0)
			elif r < 0.40: _add_broadleaf(pos, Color(1, 1, 1))
			elif r < 0.50: _add_conifer(pos, false, 1.0)
			elif r < 0.66: _add_bush(pos)
			elif r < 0.78: _add_fern(pos)
			elif r < 0.81: _add_log(pos)
			elif r < 0.83: _add_rock(pos, 0.8)
		Terrain.Biome.TAIGA:
			if slope < 0.8:
				if r < 0.18: _add_rock(pos, 1.0)
			elif r < 0.55: _add_conifer(pos, false, 1.15)
			elif r < 0.59: _add_dead_tree(pos)
			elif r < 0.67: _add_bush(pos)
			elif r < 0.76: _add_fern(pos)
			elif r < 0.81: _add_rock(pos, 0.9)
			elif r < 0.84: _add_log(pos)
		Terrain.Biome.JUNGLE:
			if r < 0.34: _add_jungle_tree(pos)
			elif r < 0.44: _add_palm(pos)
			elif r < 0.70: _add_fern(pos)
			elif r < 0.88: _add_bush(pos)
			elif r < 0.90: _add_log(pos)
		Terrain.Biome.GRASSLAND:
			if r < 0.035: _add_broadleaf(pos, Color(1.05, 1.02, 0.95))
			elif r < 0.05: _add_conifer(pos, false, 1.0)
			elif r < 0.14: _add_bush(pos)
			elif r < 0.17: _add_rock(pos, 0.6)
		Terrain.Biome.MEADOW:
			if r < 0.02: _add_broadleaf(pos, Color(1.08, 1.05, 0.95))
			elif r < 0.07: _add_bush(pos)
			elif r < 0.08: _add_rock(pos, 0.5)
		Terrain.Biome.SAVANNA:
			if r < 0.03: _add_acacia(pos)
			elif r < 0.10: _add_dry_bush(pos)
			elif r < 0.12: _add_rock(pos, 0.8)
			elif r < 0.125: _add_dead_tree(pos)
		Terrain.Biome.STEPPE:
			if r < 0.08: _add_dry_bush(pos)
			elif r < 0.11: _add_rock(pos, 0.8)
			elif r < 0.115: _add_boulder(pos)
		Terrain.Biome.DESERT:
			if r < 0.07: _add_cactus(pos)
			elif r < 0.13: _add_rock(pos, 0.8)
			elif r < 0.15: _add_log(pos)
			elif r < 0.19: _add_dry_bush(pos)
			elif r < 0.195: _add_boulder(pos)
		Terrain.Biome.SWAMP:
			if r < 0.09: _add_dead_tree(pos)
			elif r < 0.20: _add_broadleaf(pos, Color(0.75, 0.85, 0.7))
			elif r < 0.36: _add_bush(pos)
			elif r < 0.50: _add_fern(pos)
			elif r < 0.55: _add_log(pos)
		Terrain.Biome.TUNDRA:
			if r < 0.04: _add_conifer(pos, false, 0.6)
			elif r < 0.16: _add_rock(pos, 0.9)
			elif r < 0.17: _add_boulder(pos)
			elif r < 0.25: _add_dry_bush(pos)
		Terrain.Biome.ROCK:
			if r < 0.16: _add_rock(pos, 1.3)
			elif r < 0.20: _add_boulder(pos)
			elif r < 0.24 and slope > 0.85: _add_conifer(pos, false, 0.9)
		Terrain.Biome.SNOW:
			if r < 0.08: _add_conifer(pos, true, 1.0)
			elif r < 0.20: _add_rock(pos, 1.1)
		Terrain.Biome.BEACH:
			if r < 0.035 and _terrain.temperature_at(x, z) > 0.55: _add_palm(pos)
			elif r < 0.055: _add_rock(pos, 0.7)
			elif r < 0.075: _add_log(pos)
		_:
			pass


# --------------------------------------------------------------------------
# Einzelne Objekttypen
# --------------------------------------------------------------------------

func _yaw(pos: Vector3, scale_xyz: Vector3) -> Transform3D:
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(scale_xyz)
	return Transform3D(b, pos)


## Leichte Schräglage - echte Bäume stehen selten kerzengerade.
func _tilted(pos: Vector3, scale_xyz: Vector3, max_deg: float) -> Transform3D:
	var tilt := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(),
		deg_to_rad(_rng.randf_range(0.0, max_deg)))
	var b := tilt * Basis(Vector3.UP, _rng.randf() * TAU).scaled(scale_xyz)
	return Transform3D(b, pos)


func _vary(base: Color, amount: float) -> Color:
	var v := _rng.randf_range(-amount, amount)
	return Color(base.r + v + _rng.randf_range(-amount, amount) * 0.5,
		base.g + v, base.b + v * 0.6)


func _add(key: String, xform: Transform3D, color := Color(1, 1, 1)) -> void:
	var rs := _terrain.world_size * 0.5
	var region := Vector2i(int((xform.origin.x + rs) / region_size), int((xform.origin.z + rs) / region_size))
	if not _buckets.has(key):
		_buckets[key] = {}
	var by_region: Dictionary = _buckets[key]
	if not by_region.has(region):
		by_region[region] = [[], []]
	by_region[region][0].append(xform)
	by_region[region][1].append(color)


func _add_conifer(pos: Vector3, snowy: bool, size: float) -> void:
	var s := _rng.randf_range(0.75, 1.6) * size
	var xf := _tilted(pos, Vector3(s, s * _rng.randf_range(0.9, 1.35), s), 3.0)
	_add("conifer_snow" if snowy else "conifer", xf, _vary(Color(1, 1, 1), 0.1))
	_collider_cylinder(pos, 0.3 * s, 4.0 * s)


func _add_broadleaf(pos: Vector3, tint: Color) -> void:
	var s := _rng.randf_range(0.85, 1.5)
	var xf := _tilted(pos, Vector3(s, s * _rng.randf_range(0.85, 1.2), s), 5.0)
	_add("broadleaf", xf, _vary(tint, 0.12))
	_collider_cylinder(pos, 0.35 * s, 3.0 * s)


func _add_jungle_tree(pos: Vector3) -> void:
	var s := _rng.randf_range(0.9, 1.5)
	var xf := _tilted(pos, Vector3(s, s * _rng.randf_range(0.9, 1.3), s), 4.0)
	_add("jungle_tree", xf, _vary(Color(1, 1, 1), 0.12))
	_collider_cylinder(pos, 0.45 * s, 4.0 * s)


func _add_palm(pos: Vector3) -> void:
	var s := _rng.randf_range(0.8, 1.25)
	_add("palm", _yaw(pos, Vector3(s, s * _rng.randf_range(0.9, 1.25), s)), _vary(Color(1, 1, 1), 0.08))
	_collider_cylinder(pos, 0.25 * s, 3.0 * s)


func _add_acacia(pos: Vector3) -> void:
	var s := _rng.randf_range(0.85, 1.4)
	_add("acacia", _tilted(pos, Vector3(s, s * _rng.randf_range(0.85, 1.1), s), 6.0), _vary(Color(1, 1, 1), 0.08))
	_collider_cylinder(pos, 0.3 * s, 3.0 * s)


func _add_dead_tree(pos: Vector3) -> void:
	var s := _rng.randf_range(0.7, 1.3)
	_add("dead_tree", _tilted(pos, Vector3(s, s, s), 8.0), _vary(Color(1, 1, 1), 0.08))
	_collider_cylinder(pos, 0.22 * s, 3.0 * s)


func _add_bush(pos: Vector3) -> void:
	var s := _rng.randf_range(0.6, 1.3)
	_add("bush", _yaw(pos, Vector3(s, s * _rng.randf_range(0.6, 1.0), s)), _vary(Color(1, 1, 1), 0.12))


func _add_dry_bush(pos: Vector3) -> void:
	var s := _rng.randf_range(0.5, 1.1)
	_add("dry_bush", _yaw(pos, Vector3(s, s * _rng.randf_range(0.5, 0.9), s)), _vary(Color(1, 1, 1), 0.1))


func _add_fern(pos: Vector3) -> void:
	var s := _rng.randf_range(0.6, 1.3)
	_add("fern", _yaw(pos, Vector3(s, s, s)), _vary(Color(1, 1, 1), 0.12))


func _add_cactus(pos: Vector3) -> void:
	var s := _rng.randf_range(0.8, 1.5)
	var xf := _yaw(pos, Vector3(s, s, s))
	_add("cactus", xf)
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
	var s := _rng.randf_range(0.4, 1.6) * size_mul
	var b := Basis(Vector3.UP, _rng.randf() * TAU) \
		* Basis(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3))
	var xf := Transform3D(b.scaled(
			Vector3(s, s * _rng.randf_range(0.5, 0.9), s * _rng.randf_range(0.7, 1.2))),
		pos - Vector3.UP * 0.25 * s)
	_add("rock", xf, _vary(Color(1, 1, 1), 0.1))
	if s > 1.0:
		var shape := SphereShape3D.new()
		shape.radius = 0.8 * s
		_collider(shape, pos + Vector3.UP * 0.1 * s)


func _add_boulder(pos: Vector3) -> void:
	var s := _rng.randf_range(2.2, 4.5)
	var b := Basis(Vector3.UP, _rng.randf() * TAU) \
		* Basis(Vector3.FORWARD, _rng.randf_range(-0.25, 0.25))
	var xf := Transform3D(b.scaled(
			Vector3(s, s * _rng.randf_range(0.55, 0.85), s * _rng.randf_range(0.75, 1.15))),
		pos - Vector3.UP * 0.3 * s)
	_add("boulder", xf, _vary(Color(1, 1, 1), 0.1))
	var shape := SphereShape3D.new()
	shape.radius = 0.75 * s
	_collider(shape, pos + Vector3.UP * 0.05 * s)


func _add_log(pos: Vector3) -> void:
	var s := _rng.randf_range(0.7, 1.3)
	var b := Basis(Vector3.UP, _rng.randf() * TAU) \
		* Basis(Vector3.RIGHT, deg_to_rad(_rng.randf_range(80.0, 95.0)))
	_add("log", Transform3D(b.scaled(Vector3(s, s, s)), pos + Vector3.UP * 0.15), _vary(Color(1, 1, 1), 0.1))


# --------------------------------------------------------------------------
# Kollision
# --------------------------------------------------------------------------

func _collider_cylinder(pos: Vector3, radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_collider(shape, pos + Vector3.UP * height * 0.5)


## Kollisionsformen gehen direkt an den PhysicsServer - ein Körper pro Region
## statt zehntausender CollisionShape3D-Knoten.
func _collider(shape: Shape3D, pos: Vector3) -> void:
	var rs := _terrain.world_size * 0.5
	var region := Vector2i(int((pos.x + rs) / region_size), int((pos.z + rs) / region_size))
	var body: RID
	if _bodies.has(region):
		body = _bodies[region]
	else:
		body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, get_world_3d().space)
		PhysicsServer3D.body_set_collision_layer(body, 1)
		PhysicsServer3D.body_set_collision_mask(body, 1)
		_bodies[region] = body
	PhysicsServer3D.body_add_shape(body, shape.get_rid(), Transform3D(Basis(), pos))
	_shapes.append(shape)


# --------------------------------------------------------------------------
# Meshes
# --------------------------------------------------------------------------

func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.vertex_color_use_as_albedo = true   # Instanzfarbe = leichte Variation
	return m


func _cyl(r_top: float, r_bot: float, height: float, segments := 8) -> Array:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c.get_mesh_arrays()


func _cone(radius: float, height: float, segments := 9) -> Array:
	return _cyl(0.0, radius, height, segments)


func _capsule(radius: float, height: float, segments := 9) -> Array:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 3
	return c.get_mesh_arrays()


func _box(size: Vector3) -> Array:
	var b := BoxMesh.new()
	b.size = size
	return b.get_mesh_arrays()


## Verbeulte Kugel. flat = kantige Flächen (Fels), sonst weiche Normalen (Laub).
func _lumpy(radius: float, rings: int, segments: int, amount: float, lump_seed: int, flat: bool) -> Array:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.rings = rings
	s.radial_segments = segments
	var arr := s.get_mesh_arrays()
	var noise := FastNoiseLite.new()
	noise.seed = lump_seed
	noise.frequency = 0.9 / radius
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i] *= 1.0 + noise.get_noise_3dv(v[i] * 1.0) * amount
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	if not flat:
		var n := PackedVector3Array()
		n.resize(v.size())
		for i in v.size():
			n[i] = v[i].normalized()
		out[Mesh.ARRAY_VERTEX] = v
		out[Mesh.ARRAY_NORMAL] = n
		out[Mesh.ARRAY_INDEX] = idx
		return out
	# Kantig: jedes Dreieck bekommt eigene Eckpunkte mit Flächennormale.
	var fv := PackedVector3Array()
	var fn := PackedVector3Array()
	var fi := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var a := v[idx[t]]
		var b := v[idx[t + 1]]
		var c := v[idx[t + 2]]
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10:
			continue
		nrm = nrm.normalized()
		if nrm.dot(a + b + c) < 0.0:
			nrm = -nrm
		for p in [a, b, c]:
			fi.append(fv.size())
			fv.append(p)
			fn.append(nrm)
	out[Mesh.ARRAY_VERTEX] = fv
	out[Mesh.ARRAY_NORMAL] = fn
	out[Mesh.ARRAY_INDEX] = fi
	return out


## Fügt Einzelteile ([Arrays, Transform3D, Material]) zu einem Mesh zusammen,
## eine Oberfläche pro Material. Alle Teile stehen mit dem Fußpunkt auf y=0.
func _merge(parts: Array) -> ArrayMesh:
	var groups := {}
	var order := []
	for p in parts:
		if not groups.has(p[2]):
			groups[p[2]] = []
			order.append(p[2])
		groups[p[2]].append(p)

	var mesh := ArrayMesh.new()
	for mat: Material in order:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var cols := PackedColorArray()
		var indices := PackedInt32Array()
		for p in groups[mat]:
			var arr: Array = p[0]
			var xf: Transform3D = p[1]
			var nb := xf.basis.inverse().transposed()
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var base := verts.size()
			for i in v.size():
				verts.append(xf * v[i])
				norms.append((nb * n[i]).normalized())
				cols.append(Color(1, 1, 1))
			for k in idx:
				indices.append(base + k)
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = norms
		a[Mesh.ARRAY_COLOR] = cols
		a[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


func _at(pos: Vector3, basis := Basis()) -> Transform3D:
	return Transform3D(basis, pos)


func _build_meshes() -> void:
	var bark := _mat(Color(0.30, 0.21, 0.13))
	var pale_bark := _mat(Color(0.52, 0.45, 0.36))
	var dead := _mat(Color(0.50, 0.46, 0.40))
	var needle := _mat(Color(0.12, 0.30, 0.16), 0.85)
	var snow_needle := _mat(Color(0.78, 0.84, 0.86), 0.7)
	var leaf := _mat(Color(0.24, 0.45, 0.18), 0.8)
	var jungle_leaf := _mat(Color(0.12, 0.36, 0.12), 0.75)
	var palm_leaf := _mat(Color(0.26, 0.48, 0.16), 0.75)
	var acacia_leaf := _mat(Color(0.34, 0.44, 0.17), 0.85)
	var green := _mat(Color(0.28, 0.48, 0.24), 0.85)
	var fern_green := _mat(Color(0.22, 0.46, 0.16), 0.8)
	var dry := _mat(Color(0.50, 0.46, 0.26), 0.95)
	var cactus := _mat(Color(0.28, 0.50, 0.28))
	var stone := _mat(Color(0.47, 0.45, 0.42), 1.0)

	# Nadelbaum: Stamm und drei gestaffelte Kegel.
	var conifer_parts := [[_cyl(0.12, 0.24, 3.0, 7), _at(Vector3(0, 1.5, 0)), bark]]
	var snow_parts := conifer_parts.duplicate()
	var layers := [[1.45, 2.6, 2.1], [1.1, 2.3, 3.3], [0.7, 2.0, 4.4]]   # Radius, Höhe, Mitte
	for l in layers:
		conifer_parts.append([_cone(l[0], l[1]), _at(Vector3(0, l[2], 0)), needle])
		snow_parts.append([_cone(l[0], l[1]), _at(Vector3(0, l[2], 0)), snow_needle])
	_meshes["conifer"] = _merge(conifer_parts)
	_meshes["conifer_snow"] = _merge(snow_parts)

	# Laubbaum: Stamm mit Ästen, Krone aus mehreren verbeulten Laubbällen.
	_meshes["broadleaf"] = _merge([
		[_cyl(0.14, 0.26, 2.6, 7), _at(Vector3(0, 1.3, 0)), bark],
		[_cyl(0.05, 0.10, 1.4, 5), _at(Vector3(0.4, 2.8, 0), Basis(Vector3.BACK, -0.7)), bark],
		[_lumpy(1.45, 5, 9, 0.22, 1, false), _at(Vector3(0, 3.9, 0)), leaf],
		[_lumpy(1.05, 4, 8, 0.25, 2, false), _at(Vector3(0.9, 3.4, 0.4)), leaf],
		[_lumpy(1.0, 4, 8, 0.25, 3, false), _at(Vector3(-0.8, 3.5, -0.5)), leaf],
		[_lumpy(0.9, 4, 8, 0.25, 4, false), _at(Vector3(0.1, 4.8, 0.2)), leaf],
	])

	# Urwaldriese: hoher, schlanker Stamm, Brettwurzeln, breite Schirmkrone.
	_meshes["jungle_tree"] = _merge([
		[_cyl(0.22, 0.38, 7.0, 8), _at(Vector3(0, 3.5, 0)), pale_bark],
		[_box(Vector3(1.6, 1.0, 0.1)), _at(Vector3(0, 0.45, 0)), pale_bark],
		[_box(Vector3(0.1, 1.0, 1.6)), _at(Vector3(0, 0.45, 0)), pale_bark],
		[_lumpy(1.0, 5, 10, 0.2, 5, false), _at(Vector3(0, 7.4, 0), Basis.from_scale(Vector3(2.4, 0.8, 2.4))), jungle_leaf],
		[_lumpy(1.0, 4, 8, 0.25, 6, false), _at(Vector3(1.2, 6.6, 0.8), Basis.from_scale(Vector3(1.4, 0.7, 1.4))), jungle_leaf],
		[_lumpy(1.0, 4, 8, 0.25, 7, false), _at(Vector3(-1.1, 6.8, -0.9), Basis.from_scale(Vector3(1.3, 0.7, 1.3))), jungle_leaf],
	])

	# Palme: gebogener Stamm aus Segmenten, oben ein Kranz hängender Wedel.
	var palm_parts := []
	var top := Vector3.ZERO
	var lean := 0.0
	for k in 6:
		lean += 0.05
		var seg_basis := Basis(Vector3.BACK, -lean)
		var seg_len := 1.05
		var center := top + seg_basis.y * seg_len * 0.5
		palm_parts.append([_cyl(0.15 - k * 0.01, 0.2 - k * 0.01, seg_len, 7), _at(center, seg_basis), pale_bark])
		top += seg_basis.y * seg_len
	for k in 8:
		var yaw := TAU * k / 8.0 + 0.2
		var droop := deg_to_rad(20.0 + (k % 3) * 12.0)
		var frond_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -droop)
		palm_parts.append([_box(Vector3(0.45, 0.03, 2.6)), _at(top + frond_basis * Vector3(0, 0, -1.25), frond_basis), palm_leaf])
	_meshes["palm"] = _merge(palm_parts)

	# Akazie: schräger Stamm, zwei Äste, flache weite Schirmkrone.
	_meshes["acacia"] = _merge([
		[_cyl(0.12, 0.22, 2.8, 7), _at(Vector3(0.2, 1.35, 0), Basis(Vector3.BACK, -0.15)), bark],
		[_cyl(0.06, 0.1, 1.8, 5), _at(Vector3(0.9, 3.0, 0.2), Basis(Vector3.BACK, -0.8)), bark],
		[_cyl(0.06, 0.1, 1.6, 5), _at(Vector3(-0.2, 3.0, -0.4), Basis(Vector3.RIGHT, -0.7)), bark],
		[_lumpy(1.0, 4, 10, 0.18, 8, false), _at(Vector3(0.6, 3.8, 0), Basis.from_scale(Vector3(3.0, 0.45, 2.6))), acacia_leaf],
	])

	# Abgestorbener Baum: kahler Stamm mit ein paar Aststummeln.
	_meshes["dead_tree"] = _merge([
		[_cyl(0.1, 0.22, 4.2, 6), _at(Vector3(0, 2.1, 0)), dead],
		[_cyl(0.03, 0.07, 1.6, 5), _at(Vector3(0.45, 3.0, 0), Basis(Vector3.BACK, -0.9)), dead],
		[_cyl(0.03, 0.06, 1.3, 5), _at(Vector3(-0.35, 3.6, 0.1), Basis(Vector3.BACK, 0.8)), dead],
		[_cyl(0.02, 0.05, 1.1, 5), _at(Vector3(0, 2.4, 0.4), Basis(Vector3.RIGHT, 0.9)), dead],
	])

	_meshes["bush"] = _merge([
		[_lumpy(0.8, 4, 8, 0.25, 9, false), _at(Vector3(0, 0.55, 0)), green],
		[_lumpy(0.6, 4, 7, 0.25, 10, false), _at(Vector3(0.55, 0.4, 0.2)), green],
		[_lumpy(0.55, 4, 7, 0.25, 11, false), _at(Vector3(-0.45, 0.38, -0.3)), green],
	])
	_meshes["dry_bush"] = _merge([
		[_lumpy(0.6, 4, 7, 0.35, 12, false), _at(Vector3(0, 0.35, 0)), dry],
		[_lumpy(0.45, 3, 6, 0.35, 13, false), _at(Vector3(0.4, 0.28, 0.25)), dry],
	])

	# Farn: Wedel, die schräg nach außen stehen.
	var fern_parts := []
	for k in 7:
		var b := Basis(Vector3.UP, TAU * k / 7.0) * Basis(Vector3.RIGHT, deg_to_rad(40.0 + (k % 2) * 15.0))
		fern_parts.append([_box(Vector3(0.22, 0.02, 1.0)), _at(b * Vector3(0, 0, -0.5), b), fern_green])
	_meshes["fern"] = _merge(fern_parts)

	_meshes["cactus"] = _merge([[_capsule(0.28, 2.8), _at(Vector3(0, 1.4, 0)), cactus]])
	_meshes["cactus_arm"] = _merge([[_capsule(0.24, 1.6, 8), _at(Vector3(0, 0.4, 0)), cactus]])
	_meshes["rock"] = _merge([[_lumpy(1.0, 5, 8, 0.35, 14, true), _at(Vector3(0, 0.4, 0)), stone]])
	_meshes["boulder"] = _merge([[_lumpy(1.0, 6, 10, 0.3, 15, true), _at(Vector3(0, 0.4, 0)), stone]])
	_meshes["log"] = _merge([[_cyl(0.16, 0.2, 2.6, 7), _at(Vector3(0, 1.3, 0)), dead]])


# --------------------------------------------------------------------------
# MultiMesh-Ausgabe
# --------------------------------------------------------------------------

func _flush_buckets() -> void:
	for key: String in _buckets:
		var by_region: Dictionary = _buckets[key]
		for region: Vector2i in by_region:
			var xforms: Array = by_region[region][0]
			var colors: Array = by_region[region][1]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = _meshes[key]
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
				mm.set_instance_color(i, colors[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%d_%d" % [key, region.x, region.y]
			mmi.multimesh = mm
			mmi.visibility_range_end = VIEW_RANGE.get(key, 500.0)
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if key in ["fern", "dry_bush"]:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			_count += xforms.size()
	_buckets.clear()
