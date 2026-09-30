extends Node3D
## Setzt die Welt zusammen: Spieler auf einen gültigen Startplatz, Wasserfläche
## auf Meereshöhe, unsichtbare Wände an den Weltgrenzen.

@onready var terrain: Terrain = $Terrain
@onready var player: CharacterBody3D = $Player
@onready var water: MeshInstance3D = $Water


func _ready() -> void:
	var spawn := terrain.find_spawn()
	player.global_position = spawn + Vector3.UP * 1.0

	water.position.y = terrain.sea_level
	var plane := PlaneMesh.new()
	# Weit über die Insel hinaus, damit am Horizont kein Rand sichtbar wird.
	plane.size = Vector2.ONE * 3000.0
	plane.material = _water_material()
	water.mesh = plane

	_build_world_bounds()
	print("Welt bereit. Start bei %s (%s)." % [
		spawn.round(), terrain.biome_name(terrain.biome_at(spawn.x, spawn.z))])


func _water_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.38, 0.55, 0.72)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Unsichtbare Mauern, damit man nicht aus der Welt hinausläuft.
func _build_world_bounds() -> void:
	var half := terrain.world_size * 0.5
	var walls := StaticBody3D.new()
	walls.name = "WorldBounds"
	add_child(walls)
	for i in 4:
		var shape := BoxShape3D.new()
		shape.size = Vector3(terrain.world_size + 8.0, 200.0, 4.0)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0, 60, -half - 2.0).rotated(Vector3.UP, TAU * i / 4.0)
		cs.rotation.y = TAU * i / 4.0
		walls.add_child(cs)
