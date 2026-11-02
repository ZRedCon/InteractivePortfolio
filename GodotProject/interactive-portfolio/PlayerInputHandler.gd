class_name PIH extends Node

const SENSATIVITY : float = 0.005
const MAX_LOOK_ANGLE_VERTICAL : float = PI / 2 - 0.1

static var Instance : PIH

static var mouse_x : float:
	get(): return -Instance._mouse_total.x

static var mouse_y : float:
	get(): return -Instance._mouse_total.y

static var mouse : Vector3:
	get(): return Vector3(mouse_x, mouse_y, 0.0)

var _paused : bool:
	set(val):
		_paused = val
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not val else Input.MOUSE_MODE_VISIBLE

var _mouse_total : Vector2
var _input_vector_raw : Vector2

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

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("Pause"):
		_paused = not _paused
