extends CharacterBody3D

@onready var camera : Camera3D = $Camera3D
@onready var camera_ray : RayCast3D = $Camera3D/RayCast3D
@onready var telenode : Node3D = $Telenode

var _ray_collided : bool = false
var _tele_data : HitData

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
		
	var dir := transform.basis * PIH.move_planar
	
	velocity.x = dir.x * PIH.move_speed * delta
	velocity.z = dir.z * PIH.move_speed * delta
	move_and_slide()

func _process(delta: float) -> void:
	camera.rotation.x = PIH.mouse_x
	rotation.y = PIH.mouse_y
	
	var teleport_state = PIH.teleport_state
	_ray_collided = camera_ray.is_colliding()
	
	telenode.visible = bool(teleport_state)
	if teleport_state == 1:
		telenode.global_position = Vector3.ZERO
	
