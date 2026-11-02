extends CharacterBody3D

const VALID_COLOR := Color(0.8,1,0.1)
const INVALID_COLOR := Color(1.0,0.15,0.2)

@onready var camera : Camera3D = $Camera3D
@onready var camera_ray : RayCast3D = $Camera3D/RayCast3D
@onready var telenode : Node3D = $Telenode

var _tele_data : HitData
var material : StandardMaterial3D

func _ready() -> void:
	material = (telenode.get_child( 0 ) as MeshInstance3D).get_active_material( 0 )
	material.albedo_color = Color(1,0,1)
	material.emission = Color(1,0,1)

func _physics_process(delta: float) -> void:
	if PIH.is_paused: return
	
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
		
	var dir := transform.basis * PIH.move_planar
	
	velocity.x = dir.x * PIH.move_speed * delta
	velocity.z = dir.z * PIH.move_speed * delta
	move_and_slide()
	
	_handle_floor_cast()

func _handle_floor_cast() -> void:
	var teleport_state = PIH.teleport_state
	var collided = camera_ray.is_colliding()
	
	
	telenode.visible = bool(teleport_state) and collided
	if not collided: return
	var collider := camera_ray.get_collider() as Node3D
	var on_floor := collider.is_in_group("Floor")
	material.albedo_color = VALID_COLOR if on_floor else INVALID_COLOR
	material.emission = VALID_COLOR if on_floor else INVALID_COLOR
	if teleport_state == 1:
		_tele_data = HitData.new(camera_ray.get_collision_point(),
								camera_ray.get_collision_normal())
		
		telenode.global_position = _tele_data.hit_point
	elif teleport_state == 2 and on_floor:
		global_position = _tele_data.hit_point

func _process(delta: float) -> void:
	if PIH.is_paused: return
	
	camera.rotation.x = PIH.mouse_x
	rotation.y = PIH.mouse_y
