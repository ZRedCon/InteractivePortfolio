class_name PIH extends Node

signal on_pause_change

const MOVE_WALK : float = 200.0
const MOVE_SPRINT : float = 800.0
const MOVE_RUN : float = 1600.0

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

static var is_paused : bool:
	get(): return Instance._paused

var _paused : bool:
	set(val):
		_paused = val
		on_pause_change.emit()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not val else Input.MOUSE_MODE_VISIBLE

var _captured : bool:
	get(): return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

var _was_captured : bool
var _mouse_total : Vector2
var _sensitivity : float:
	set(val): _sensitivity = val / 10000

func _ready() -> void:
	Instance = self
	_sensitivity = 50

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _captured:
		_mouse_event_handler_fps( event )

func _unhandled_input(event: InputEvent) -> void:
	if (not _paused and not _captured and event is InputEventMouseButton and
		event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _pause_handler() -> void:
	if Input.is_action_just_pressed("Pause"): _paused = not _paused
	elif _was_captured and not _captured and not _paused: _paused = true
	_was_captured = _captured

func _mouse_event_handler_fps(event: InputEventMouseMotion) -> void:
	var raw_vector : Vector2 = Vector2(event.relative.y, event.relative.x) * _sensitivity
	_mouse_total.x = clampf(_mouse_total.x + raw_vector.x, 
							-MAX_LOOK_ANGLE_VERTICAL, 
							MAX_LOOK_ANGLE_VERTICAL)
	_mouse_total.y += raw_vector.y

func _process(delta: float) -> void:
	_pause_handler()
