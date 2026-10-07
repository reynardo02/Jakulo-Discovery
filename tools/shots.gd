extends Node
## Entwickler-Werkzeug: lädt die Hauptszene, fliegt ein paar Aussichtspunkte an
## und speichert Screenshots nach tools/shots/. Rein zum Prüfen gedacht.

const SHOT_DIR := "res://tools/shots"


func _ready() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await main.world_ready

	# Der Spieler fängt die Maus ein - beim Testen wollen wir das nicht.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player: Node3D = main.get_node("Player")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var hud: CanvasLayer = main.get_node("HUD")

	var terrain: Terrain = main.get_node("Terrain")
	var cam := Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	cam.make_current()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	# Aussichtspunkte relativ zum Startplatz und zu gefundenen Landschaften.
	var spawn := terrain.find_spawn()
	var views := [
		{"name": "01_start", "pos": spawn + Vector3(-14, 0, 0), "h": 2.5, "look": spawn + Vector3(60, 0, 40), "pitch": -6.0},
		{"name": "02_uebersicht", "pos": Vector3(-600, 0, -600), "h": 320.0, "look": Vector3(0, 0, 0), "pitch": -20.0},
	]
	# Für jede Landschaft einen Blickpunkt suchen.
	var wanted := [Terrain.Biome.MEADOW, Terrain.Biome.FOREST, Terrain.Biome.TAIGA, Terrain.Biome.JUNGLE,
		Terrain.Biome.SAVANNA, Terrain.Biome.DESERT, Terrain.Biome.SWAMP, Terrain.Biome.TUNDRA,
		Terrain.Biome.SNOW, Terrain.Biome.BEACH]
	var half := terrain.world_size * 0.5
	for b in wanted:
		var found := false
		for z in range(int(-half) + 40, int(half) - 40, 24):
			for x in range(int(-half) + 40, int(half) - 40, 24):
				if terrain.biome_at(x, z) == b and terrain.biome_at(x + 30, z + 30) == b:
					views.append({"name": "%02d_%s" % [views.size() + 1, terrain.biome_name(b).to_lower()],
						"pos": Vector3(x, 0, z), "h": 3.0, "look": Vector3(x + 60, 0, z + 60), "pitch": -5.0})
					found = true
					break
			if found:
				break

	for v in views:
		hud.visible = v["name"] == "01_start"   # HUD nur einmal mit abbilden
		var p: Vector3 = v["pos"]
		p.y = maxf(terrain.height_at(p.x, p.z), terrain.sea_level) + float(v["h"])
		cam.global_position = p
		var target: Vector3 = v["look"]
		target.y = p.y
		cam.look_at(target, Vector3.UP)
		cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(v["pitch"])))

		for i in 8:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [SHOT_DIR, v["name"]])
		print("Screenshot: %-14s Kamera %s  Boden: %s" % [
			v["name"], p.round(), terrain.biome_name(terrain.biome_at(p.x, p.z))])

	# Kurze Leistungsmessung von einem weiten Blickpunkt aus.
	hud.visible = false
	cam.global_position = Vector3(-600, 330, -600)
	cam.look_at(Vector3(0, 40, 0), Vector3.UP)
	for i in 30:
		await RenderingServer.frame_post_draw
	var fps_sum := 0.0
	for i in 120:
		await RenderingServer.frame_post_draw
		fps_sum += Engine.get_frames_per_second()
	print("Durchschnitt: %.0f FPS (Weitsicht)" % [fps_sum / 120.0])

	get_tree().quit()
