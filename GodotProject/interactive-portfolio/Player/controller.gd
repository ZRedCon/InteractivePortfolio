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
	var on_floor := _is_floor(collider, camera_ray.get_collider_shape())
	material.albedo_color = VALID_COLOR if on_floor else INVALID_COLOR
	material.emission = VALID_COLOR if on_floor else INVALID_COLOR
	if teleport_state == 1:
		_tele_data = HitData.new(camera_ray.get_collision_point(),
								camera_ray.get_collision_normal())
		
		telenode.global_position = _tele_data.hit_point
	elif teleport_state == 2 and on_floor:
		global_position = _tele_data.hit_point

# get_collider() only gives the body the ray hit, and for a room that's the whole Room. The "Floor"
# group is on the carpet's own CollisionShape3D, so this also looks up which of the body's shapes was hit.
static func _is_floor(collider: Node3D, shape_index: int) -> bool:
	if collider.is_in_group("Floor"): return true
	var body := collider as CollisionObject3D
	if not body: return false
	var shape := body.shape_owner_get_owner(body.shape_find_owner(shape_index)) as Node
	return shape != null and shape.is_in_group("Floor")

func _process(delta: float) -> void:
	if PIH.is_paused: return
	
	camera.rotation.x = PIH.mouse_x
	rotation.y = PIH.mouse_y
