extends CharacterBody3D
## Third-Person-Spieler: WASD bewegen, Maus schaut, Shift rennt, Leertaste springt.
##
## Gegen Feststecken: Doppelsprung in der Luft, Wandsprung an steilen Hängen
## und Hindernissen (geht immer, auch ohne festen Boden), kurze Nachsicht beim
## Absprung (Coyote-Time) und Taste R, die den Spieler zum nächsten freien,
## ebenen Platz bringt. Fällt er durch den Boden, wird er automatisch gerettet.

@export var walk_speed := 5.0
@export var run_speed := 11.0
@export var jump_velocity := 5.0
@export var air_jumps := 1              ## zusätzliche Sprünge in der Luft (1 = Doppelsprung)
@export var wall_jump_push := 4.0       ## wie stark ein Wandsprung vom Hang wegdrückt
@export var coyote_time := 0.15         ## so lange nach dem Verlassen des Bodens zählt er noch
@export var jump_buffer := 0.15         ## zu früh gedrückter Sprung wird so lange gemerkt
@export var terrain_path: NodePath = ^"../Terrain"
@export var turn_speed := 10.0          ## wie schnell sich die Figur in Laufrichtung dreht
@export var mouse_sensitivity := 0.003
@export var zoom_min := 2.0
@export var zoom_max := 10.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var model: Node3D = $Model

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _terrain: Terrain
var _air_jumps_left := 0
var _since_floor := 0.0
var _jump_pressed_ago := 1.0
var _stuck_time := 0.0                  ## wie lange er schon laufen will, aber nicht vorankommt
var _stuck_start := Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Kamera soll nicht mit dem eigenen Körper kollidieren
	spring_arm.add_excluded_object(get_rid())
	_terrain = get_node_or_null(terrain_path) as Terrain
	# Etwas steilere Hänge gelten noch als Boden, und beim Bergablaufen
	# bleibt die Figur am Boden statt kleine Hüpfer zu machen.
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.5
	floor_constant_speed = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity
		camera_pivot.rotation.x = clamp(
			camera_pivot.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-70), deg_to_rad(30))
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			spring_arm.spring_length = max(zoom_min, spring_arm.spring_length - 0.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			spring_arm.spring_length = min(zoom_max, spring_arm.spring_length + 0.5)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_R:
		rescue()


## Sekunden, die der Spieler schon feststeckt (für einen Hinweis im HUD).
func stuck_seconds() -> float:
	return _stuck_time


## Bringt den Spieler zum nächsten freien, ebenen Platz an Land.
func rescue() -> void:
	if _terrain == null:
		return
	var origin := global_position
	for radius in range(0, 90, 3):
		var steps := 1 if radius == 0 else 16
		for k in steps:
			var a := TAU * k / steps
			var x := origin.x + cos(a) * radius
			var z := origin.z + sin(a) * radius
			if not _terrain.is_inside(x * 1.02, z * 1.02):
				continue
			var y := _terrain.height_at(x, z)
			if y < _terrain.sea_level + 0.3 or _terrain.normal_at(x, z).y < 0.88:
				continue
			# Die eigene Stelle nur, wenn er unter den Boden gerutscht ist -
			# sonst steckt er dort ja gerade fest.
			if radius == 0 and origin.y > y - 0.5:
				continue
			var spot := Vector3(x, y + 0.3, z)
			if _blocked(spot):
				continue
			global_position = spot
			velocity = Vector3.ZERO
			_stuck_time = 0.0
			return


## Ist an dieser Stelle etwas im Weg (Baum, Fels)?
func _blocked(spot: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), spot + Vector3.UP * 1.0)
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _physics_process(delta: float) -> void:
	if is_on_floor():
		_since_floor = 0.0
		_air_jumps_left = air_jumps
	else:
		_since_floor += delta
		velocity.y -= gravity * delta

	_jump_pressed_ago += delta
	if Input.is_action_just_pressed("jump"):
		_jump_pressed_ago = 0.0
	if _jump_pressed_ago <= jump_buffer:
		_try_jump()

	# Eingabe relativ zur Kamerablickrichtung
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0, input_dir.y).rotated(Vector3.UP, camera_pivot.rotation.y)
	var speed := run_speed if Input.is_action_pressed("run") else walk_speed

	if direction.length() > 0.01:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		# Figur in Laufrichtung drehen (Modell schaut nach -Z)
		var target_angle := atan2(-direction.x, -direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_angle, turn_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	var before := global_position
	move_and_slide()
	_update_stuck(direction, before, delta)

	# Durch den Boden gefallen? Dann zurück nach oben.
	if _terrain and global_position.y < _terrain.height_at(global_position.x, global_position.z) - 2.0:
		rescue()


func _try_jump() -> bool:
	var jumped := false
	if is_on_floor() or _since_floor < coyote_time:
		velocity.y = jump_velocity
		jumped = true
	elif is_on_wall() or _touches_steep():
		# Wandsprung: vom Hang bzw. Hindernis weg und nach oben. Geht immer,
		# damit man aus Mulden und Spalten herauskommt.
		var n := get_wall_normal() if is_on_wall() else _steep_normal()
		n.y = 0.0
		velocity.y = jump_velocity * 1.1
		if n.length() > 0.01:
			velocity += n.normalized() * wall_jump_push
		_air_jumps_left = air_jumps
		jumped = true
	elif _air_jumps_left > 0:
		_air_jumps_left -= 1
		velocity.y = jump_velocity * 0.95
		jumped = true
	if jumped:
		_jump_pressed_ago = 1.0
		_since_floor = coyote_time
	return jumped


## Berührt die Figur gerade einen zu steilen Hang (kein Boden, aber Kontakt)?
func _touches_steep() -> bool:
	return get_slide_collision_count() > 0 and not is_on_floor()


func _steep_normal() -> Vector3:
	var n := Vector3.ZERO
	for i in get_slide_collision_count():
		n += get_slide_collision(i).get_normal()
	return n


## Merkt, wenn der Spieler laufen will, aber kaum vorankommt.
func _update_stuck(direction: Vector3, before: Vector3, delta: float) -> void:
	if direction.length() < 0.01:
		_stuck_time = 0.0
		return
	if _stuck_time == 0.0:
		_stuck_start = before
	_stuck_time += delta
	# Kommt er in 1,5 s mehr als 1,5 m voran, ist alles gut.
	var moved := Vector2(global_position.x - _stuck_start.x, global_position.z - _stuck_start.z).length()
	if moved > 1.5:
		_stuck_time = 0.0
