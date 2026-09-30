extends Node
## Entwickler-Werkzeug: lädt die Hauptszene, fliegt ein paar Aussichtspunkte an
## und speichert Screenshots nach tools/shots/. Rein zum Prüfen gedacht.

const SHOT_DIR := "res://tools/shots"


func _ready() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	# Der Spieler fängt die Maus ein - beim Testen wollen wir das nicht.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player: Node3D = main.get_node("Player")
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var hud: CanvasLayer = main.get_node("HUD")

	var terrain: Terrain = main.get_node("Terrain")
	var cam := Camera3D.new()
	cam.far = 900.0
	add_child(cam)
	cam.make_current()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	var views := [
		{"name": "01_start", "pos": Vector3(-18, 0, 0), "h": 6.0, "look": Vector3(90, 0, 90), "pitch": -6.0},
		{"name": "02_uebersicht", "pos": Vector3(-170, 0, -170), "h": 150.0, "look": Vector3(60, 0, 80), "pitch": -18.0},
		{"name": "03_gebirge", "pos": Vector3(70, 0, 40), "h": 25.0, "look": Vector3(150, 0, 130), "pitch": -4.0},
		{"name": "04_kueste", "pos": Vector3(-190, 0, 30), "h": 10.0, "look": Vector3(-300, 0, 30), "pitch": -5.0},
		{"name": "05_wueste", "pos": Vector3(-80, 0, 160), "h": 12.0, "look": Vector3(10, 0, 210), "pitch": -5.0},
		{"name": "06_wald", "pos": Vector3(-60, 0, -80), "h": 8.0, "look": Vector3(20, 0, -20), "pitch": -4.0},
	]

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
	cam.global_position = Vector3(-170, 162, -170)
	cam.look_at(Vector3(60, 60, 80), Vector3.UP)
	for i in 30:
		await RenderingServer.frame_post_draw
	var fps_sum := 0.0
	for i in 120:
		await RenderingServer.frame_post_draw
		fps_sum += Engine.get_frames_per_second()
	print("Durchschnitt: %.0f FPS (Weitsicht, %d Objekte)" % [fps_sum / 120.0, 3413])

	get_tree().quit()
