extends CanvasLayer
class_name Hud
## Anzeige: aktuelle Landschaft, Position, Temperatur, Steuerung - dazu ein
## Ladehinweis beim Start und eine Übersichtskarte (Taste M).

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


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as Terrain
	_player = get_node_or_null(player_path) as Node3D
	_help_label.text = "WASD laufen · Shift rennen · Leertaste springen · Maus schauen · Mausrad zoomen · M Karte · Esc Maus frei"
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


func world_ready() -> void:
	if _loading:
		_loading.queue_free()
		_loading = null
	_build_map()
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
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_M:
		_map.visible = not _map.visible
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

	# Pfeil für den Spieler, zeigt in Blickrichtung der Kamera.
	_marker = Polygon2D.new()
	_marker.polygon = PackedVector2Array([Vector2(0, -11), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)])
	_marker.color = Color(1.0, 0.18, 0.12)
	_map_rect.add_child(_marker)


func _update_marker() -> void:
	var p := _player.global_position
	var half := _terrain.world_size * 0.5
	_marker.position = Vector2((p.x + half) / _terrain.world_size, (p.z + half) / _terrain.world_size) * map_size
	var cam := get_viewport().get_camera_3d()
	if cam:
		var f := -cam.global_basis.z
		_marker.rotation = atan2(f.x, -f.z)
