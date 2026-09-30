extends CanvasLayer
## Kleine Anzeige: aktuelle Landschaft, Position, Steuerung.

@export var terrain_path: NodePath = ^"../Terrain"
@export var player_path: NodePath = ^"../Player"
@export var update_interval := 0.2

@onready var _biome_label: Label = $Panel/VBox/BiomeLabel
@onready var _info_label: Label = $Panel/VBox/InfoLabel
@onready var _help_label: Label = $Panel/VBox/HelpLabel

var _terrain: Terrain
var _player: Node3D
var _time := 0.0


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path) as Terrain
	_player = get_node_or_null(player_path) as Node3D
	_help_label.text = "WASD laufen · Shift rennen · Leertaste springen · Maus schauen · Mausrad zoomen · Esc Maus frei"
	_refresh()


func _process(delta: float) -> void:
	_time += delta
	if _time >= update_interval:
		_time = 0.0
		_refresh()


func _refresh() -> void:
	if _terrain == null or _player == null:
		return
	var p := _player.global_position
	var biome := _terrain.biome_at(p.x, p.z)
	var under_water := p.y < _terrain.sea_level
	_biome_label.text = "Meer" if under_water else _terrain.biome_name(biome)
	_info_label.text = "X %.0f   Z %.0f   Höhe %.1f m" % [p.x, p.z, p.y]
