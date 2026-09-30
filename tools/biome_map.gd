extends SceneTree
## Entwickler-Werkzeug: druckt die Biom-Verteilung und speichert eine
## Übersichtskarte der Welt als PNG.
##
## Aufruf:
##   godot --headless --path . --script res://tools/biome_map.gd

const RES := 512   ## Pixel pro Kante der Karte


func _initialize() -> void:
	var t: Terrain = (load("res://scripts/terrain.gd") as GDScript).new()
	t._setup_noise()

	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	var counts := {}
	var half := t.world_size * 0.5
	var step := t.world_size / RES
	var spawn := t.find_spawn()

	for j in RES:
		var z := -half + (j + 0.5) * step
		for i in RES:
			var x := -half + (i + 0.5) * step
			var y := t.height_at(x, z)
			var nrm := t.normal_at(x, z)
			var b: int = t._classify(x, z, y, nrm.y)
			counts[b] = counts.get(b, 0) + 1

			var c: Color = t.BIOME_COLORS[b]
			if b == t.Biome.OCEAN:
				# Wasser einfärben, Tiefe andeuten
				var depth := clampf((t.sea_level - y) / 6.0, 0.0, 1.0)
				c = Color(0.18, 0.38, 0.55).lerp(Color(0.06, 0.16, 0.32), depth)
			else:
				# Schlichtes Hillshading, damit das Relief sichtbar wird
				var light := clampf(Vector3(0.45, 0.78, -0.45).normalized().dot(nrm), 0.0, 1.0)
				c = c * (0.55 + 0.6 * light)
			img.set_pixel(i, j, c)

	# Startpunkt markieren
	var sx := int((spawn.x + half) / step)
	var sz := int((spawn.z + half) / step)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if absi(dx) + absi(dy) > 4:
				continue
			var px := clampi(sx + dx, 0, RES - 1)
			var py := clampi(sz + dy, 0, RES - 1)
			img.set_pixel(px, py, Color(1, 0.1, 0.1))

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
