extends CanvasLayer
class_name Hud
## Anzeige: aktuelle Landschaft, Position, Temperatur, Steuerung - dazu ein
## Ladehinweis beim Start, eine Übersichtskarte (Taste M), Einblendungen für
## neue Erfolge und die Erfolgsliste (Taste J).

@export var terrain_path: NodePath = ^"../Terrain"
@export var player_path: NodePath = ^"../Player"
@export var update_interval := 0.2
@export var map_resolution := 512      ## Pixel pro Kante der Kartentextur
@export var map_size := 640.0          ## Kantenlänge der Karte auf dem Bildschirm

@onready var _panel: Control = $Panel
@onready var _biome_label: Label = $Panel/VBox/BiomeLabel
@onready var _info_label: Label = $Panel/VBox/InfoLabel
@onready var _help_label: Label = $Panel/VBox/HelpLabel

var _terrain: Terrain
var _player: Node3D
var _time := 0.0
var _ready_to_show := false

var _loading: ColorRect
var _map: Control
var _map_rect: TextureRect
var _marker: Polygon2D
var _achievements: Achievements
var _place_dots := []                  ## [Ort, Polygon2D]
var _toasts: VBoxContainer
var _journal: Control
var _journal_list: VBoxContainer


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as Terrain
	_player = get_node_or_null(player_path) as Node3D
	_help_label.text = "WASD laufen · Shift rennen · Leertaste springen · Maus schauen · Mausrad zoomen · M Karte · J Erfolge · Esc Maus frei"
	_panel.visible = false


func show_loading(text: String) -> void:
	_loading = ColorRect.new()
	_loading.color = Color(0.05, 0.07, 0.09)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_child(label)
	add_child(_loading)


func world_ready(achievements: Achievements = null) -> void:
	if _loading:
		_loading.queue_free()
		_loading = null
	_achievements = achievements
	_build_map()
	_build_toasts()
	_build_journal()
	if _achievements:
		_achievements.unlocked.connect(_on_unlocked)
	_panel.visible = true
	_ready_to_show = true
	_refresh()


func _process(delta: float) -> void:
	if not _ready_to_show:
		return
	_time += delta
	if _time >= update_interval:
		_time = 0.0
		_refresh()
	if _map.visible:
		_update_marker()


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_show:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_M:
		_map.visible = not _map.visible
		_journal.visible = false
		if _map.visible:
			_update_place_dots()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_J:
		_journal.visible = not _journal.visible
		_map.visible = false
		if _journal.visible:
			_fill_journal()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if _terrain == null or _player == null:
		return
	var p := _player.global_position
	var biome := _terrain.biome_at(p.x, p.z)
	var under_water := p.y < _terrain.sea_level
	_biome_label.text = "Meer" if under_water else _terrain.biome_name(biome)
	_info_label.text = "X %.0f   Z %.0f   Höhe %.1f m   %.0f °C" % [
		p.x, p.z, p.y, _terrain.celsius_at(p.x, p.z)]
	if _achievements:
		_info_label.text += "\nErfolge %d / %d" % [_achievements.unlocked_count(), _achievements.total()]


# --------------------------------------------------------------------------
# Karte
# --------------------------------------------------------------------------

func _build_map() -> void:
	_map = Control.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.visible = false
	add_child(_map)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(dim)

	_map_rect = TextureRect.new()
	_map_rect.texture = ImageTexture.create_from_image(_terrain.map_image(map_resolution))
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.anchor_left = 0.5
	_map_rect.anchor_right = 0.5
	_map_rect.anchor_top = 0.5
	_map_rect.anchor_bottom = 0.5
	_map_rect.offset_left = -map_size * 0.5
	_map_rect.offset_right = map_size * 0.5
	_map_rect.offset_top = -map_size * 0.5
	_map_rect.offset_bottom = map_size * 0.5
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(_map_rect)

	var title := Label.new()
	title.text = "Karte  (M schließt)"
	title.add_theme_font_size_override("font_size", 18)
	title.position = Vector2(0, -30)
	_map_rect.add_child(title)

	# Besondere Orte: Raute, grau solange unentdeckt, golden wenn gefunden.
	if _achievements:
		for l in _achievements.landmarks:
			var dot := Polygon2D.new()
			dot.polygon = PackedVector2Array([Vector2(0, -7), Vector2(7, 0), Vector2(0, 7), Vector2(-7, 0)])
			dot.position = _map_pos(l["pos"])
			var name_label := Label.new()
			name_label.text = l["name"]
			name_label.add_theme_font_size_override("font_size", 12)
			name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
			name_label.add_theme_constant_override("outline_size", 4)
			name_label.position = Vector2(9, -9)
			dot.add_child(name_label)
			_map_rect.add_child(dot)
			_place_dots.append([l, dot])

	# Pfeil für den Spieler, zeigt in Blickrichtung der Kamera.
	_marker = Polygon2D.new()
	_marker.polygon = PackedVector2Array([Vector2(0, -11), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)])
	_marker.color = Color(1.0, 0.18, 0.12)
	_map_rect.add_child(_marker)


func _map_pos(p: Vector3) -> Vector2:
	var half := _terrain.world_size * 0.5
	return Vector2((p.x + half) / _terrain.world_size, (p.z + half) / _terrain.world_size) * map_size


func _update_place_dots() -> void:
	for entry in _place_dots:
		var found := _achievements.is_landmark_found(entry[0])
		(entry[1] as Polygon2D).color = Color(1.0, 0.8, 0.25) if found else Color(0.75, 0.9, 1.0)


func _update_marker() -> void:
	_marker.position = _map_pos(_player.global_position)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var f := -cam.global_basis.z
		_marker.rotation = atan2(f.x, -f.z)


# --------------------------------------------------------------------------
# Erfolge
# --------------------------------------------------------------------------

func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.offset_left = -220.0
	_toasts.offset_right = 220.0
	_toasts.offset_top = 24.0
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)


func _on_unlocked(title: String, description: String) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.04, 0.85)
	style.border_color = Color(1.0, 0.78, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := Label.new()
	head.text = "★ Erfolg: " + title
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", Color(1.0, 0.84, 0.4))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var body := Label.new()
	body.text = description
	body.add_theme_font_size_override("font_size", 14)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	_toasts.add_child(panel)

	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.35)
	tw.tween_interval(4.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(panel.queue_free)
	_update_place_dots()
	_refresh()


func _build_journal() -> void:
	_journal = Control.new()
	_journal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_journal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journal.visible = false
	add_child(_journal)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journal.add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.09, 0.92)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300.0
	panel.offset_right = 300.0
	panel.offset_top = -340.0
	panel.offset_bottom = 340.0
	_journal.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var title := Label.new()
	title.text = "Erfolge  (J schließt)"
	title.add_theme_font_size_override("font_size", 22)
	outer.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_journal_list = VBoxContainer.new()
	_journal_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_journal_list)


func _fill_journal() -> void:
	for c in _journal_list.get_children():
		c.queue_free()
	if _achievements == null:
		return
	var head := Label.new()
	head.text = "%d von %d freigeschaltet" % [_achievements.unlocked_count(), _achievements.total()]
	head.add_theme_color_override("font_color", Color(0.7, 0.78, 0.85))
	_journal_list.add_child(head)
	for d in _achievements.defs:
		var done := _achievements.is_unlocked(d["id"])
		var line := Label.new()
		line.text = "%s  %s\n      %s" % ["★" if done else "☆", d["title"], d["desc"]]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 15)
		line.add_theme_color_override("font_color",
			Color(1.0, 0.84, 0.4) if done else Color(0.62, 0.66, 0.7))
		_journal_list.add_child(line)
