extends Node3D
## Setzt die Welt zusammen: Gelände, Bewuchs und Gras erzeugen, Spieler auf
## einen gültigen Startplatz, Wasserfläche auf Meereshöhe, unsichtbare Wände an
## den Weltgrenzen. Solange das läuft, zeigt das HUD einen Ladehinweis.

signal world_ready

@onready var terrain: Terrain = $Terrain
@onready var scatter: Scatter = $Scatter
@onready var grass: Grass = $Grass
@onready var player: CharacterBody3D = $Player
@onready var water: MeshInstance3D = $Water
@onready var hud: Hud = $HUD


func _ready() -> void:
	player.set_physics_process(false)
	hud.show_loading("Welt wird erzeugt …")
	# Erst ein Bild zeichnen lassen, damit der Ladehinweis sichtbar ist.
	await RenderingServer.frame_post_draw

	var t0 := Time.get_ticks_msec()
	terrain.generate()
	var spawn := terrain.find_spawn()
	scatter.generate(spawn)
	grass.start(spawn)

	player.global_position = spawn + Vector3.UP * 1.0
	player.set_physics_process(true)

	water.position.y = terrain.sea_level
	var plane := PlaneMesh.new()
	# Weit über die Insel hinaus, damit am Horizont kein Rand sichtbar wird.
	plane.size = Vector2.ONE * (terrain.world_size * 5.0)
	plane.material = _water_material()
	water.mesh = plane

	_build_world_bounds()
	hud.world_ready()
	print("Welt bereit in %d ms. Start bei %s (%s)." % [
		Time.get_ticks_msec() - t0, spawn.round(),
		terrain.biome_name(terrain.biome_at(spawn.x, spawn.z))])
	world_ready.emit()


func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("normal_a", _wave_texture(11, 0.02))
	m.set_shader_parameter("normal_b", _wave_texture(12, 0.035))
	var foam := NoiseTexture2D.new()
	foam.seamless = true
	var fn := FastNoiseLite.new()
	fn.seed = 13
	fn.frequency = 0.03
	foam.noise = fn
	m.set_shader_parameter("foam_noise", foam)
	return m


func _wave_texture(noise_seed: int, freq: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	n.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 4.0
	t.noise = n
	return t


## Unsichtbare Mauern, damit man nicht aus der Welt hinausläuft.
func _build_world_bounds() -> void:
	var half := terrain.world_size * 0.5
	var walls := StaticBody3D.new()
	walls.name = "WorldBounds"
	add_child(walls)
	for i in 4:
		var shape := BoxShape3D.new()
		shape.size = Vector3(terrain.world_size + 8.0, 400.0, 4.0)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0, 100, -half - 2.0).rotated(Vector3.UP, TAU * i / 4.0)
		cs.rotation.y = TAU * i / 4.0
		walls.add_child(cs)
