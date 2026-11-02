extends RigidBody3D

@onready var camera : Camera3D = $Camera3D

func _ready() -> void:
	pass


func _process(delta: float) -> void:
	camera.rotation = PIH.mouse
