class_name PIH extends Node

const MOVE_WALK : float = 200.0
const MOVE_SPRINT : float = 800.0
const MOVE_RUN : float = 1600.0

const SENSATIVITY : float = 0.005
const MAX_LOOK_ANGLE_VERTICAL : float = PI / 2 - 0.1

static var Instance : PIH

static var mouse_x : float:
	get(): return -Instance._mouse_total.x

static var mouse_y : float:
	get(): return -Instance._mouse_total.y

static var mouse : Vector3:
	get(): return Vector3(mouse_x, mouse_y, 0.0)

static var move_planar : Vector3:
	get():
		var input_vector := Input.get_vector("Left", "Right", "Forward", "Backward")
		return Vector3(input_vector.x, 0, input_vector.y)

static var move_speed : float:
	get():
		return (MOVE_WALK if Input.is_action_pressed("Slow") else 
				MOVE_RUN if Input.is_action_pressed("Sprint") else 
				MOVE_SPRINT)

static var teleport_state : int:
	get():
		if Input.is_action_pressed("Teleclick"):
			return 1
		if Input.is_action_just_released("Teleclick"):
			return 2
		return 0

var _paused : bool:
	set(val):
		_paused = val
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not val else Input.MOUSE_MODE_VISIBLE

var _mouse_total : Vector2

func _ready() -> void:
	Instance = self
	_paused = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not _paused:
		_mouse_event_handler_fps( event )

func _mouse_event_handler_fps(event: InputEventMouseMotion) -> void:
	var raw_vector : Vector2 = Vector2(event.relative.y, event.relative.x) * SENSATIVITY
	_mouse_total.x = clampf(_mouse_total.x + raw_vector.x, -MAX_LOOK_ANGLE_VERTICAL, MAX_LOOK_ANGLE_VERTICAL)
	_mouse_total.y += raw_vector.y

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("Pause"):
		_paused = not _paused
