extends CharacterBody3D
## Third-Person-Spieler: WASD bewegen, Maus schaut, Shift rennt, Leertaste springt.

@export var walk_speed := 5.0
@export var run_speed := 9.0
@export var jump_velocity := 5.0
@export var turn_speed := 10.0          ## wie schnell sich die Figur in Laufrichtung dreht
@export var mouse_sensitivity := 0.003
@export var zoom_min := 2.0
@export var zoom_max := 10.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var model: Node3D = $Model

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Kamera soll nicht mit dem eigenen Körper kollidieren
	spring_arm.add_excluded_object(get_rid())


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


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

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

	move_and_slide()
