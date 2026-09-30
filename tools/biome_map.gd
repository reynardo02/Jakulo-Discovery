extends SceneTree
## Entwickler-Werkzeug: druckt die Biom-Verteilung und speichert eine
## Übersichtskarte der Welt als PNG.
##
## Aufruf:
##   godot --headless --path . --script res://tools/biome_map.gd

const RES := 768   ## Pixel pro Kante der Karte


func _initialize() -> void:
	var t: Terrain = (load("res://scripts/terrain.gd") as GDScript).new()
	var t0 := Time.get_ticks_msec()
	t.compute_data()
	print("Gitter berechnet in %d ms." % (Time.get_ticks_msec() - t0))

	var img := t.map_image(RES)
	var counts := {}
	var half := t.world_size * 0.5
	var step := t.world_size / RES
	for j in RES:
		var z := -half + (j + 0.5) * step
		for i in RES:
			var b: int = t.biome_at(-half + (i + 0.5) * step, z)
			counts[b] = counts.get(b, 0) + 1

	# Startpunkt markieren
	var spawn := t.find_spawn()
	var sx := int((spawn.x + half) / step)
	var sz := int((spawn.z + half) / step)
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if absi(dx) + absi(dy) > 5:
				continue
			img.set_pixel(clampi(sx + dx, 0, RES - 1), clampi(sz + dy, 0, RES - 1), Color(1, 0.1, 0.1))

	var out := "res://tools/biome_map.png"
	img.save_png(out)

	var total := RES * RES
	print("--- Biom-Verteilung (%d x %d m) ---" % [t.world_size, t.world_size])
	var keys := counts.keys()
	keys.sort()
	for b in keys:
		print("%-14s %5.1f %%" % [t.biome_name(b), 100.0 * counts[b] / total])
	print("Start: %s" % [spawn.round()])
	print("Karte: %s" % ProjectSettings.globalize_path(out))

	t.free()
	quit()
