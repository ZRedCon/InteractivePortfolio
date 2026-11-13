extends CharacterBody3D

const NO_MOUSE = 0
const LEFT_MOUSE = 1
const MIDDLE_MOUSE = 2
const RIGHT_MOUSE = 3

const VALID_COLOR := Color(0.541, 1.0, 0.102, 1.0)
const INVALID_COLOR := Color(1.0,0.15,0.2)

@onready var camera : Camera3D = $Camera3D
@onready var camera_ray : RayCast3D = $Camera3D/RayCast3D
@onready var telenode : Node3D = $Telenode
@onready var mouse_sprite : AnimatedSprite2D = $Camera3D/ContUI/Control/AnimatedSprite2D

var _tele_data : HitData
var material : StandardMaterial3D
var mouse_state : int:
	set( new_val ):
		if mouse_state == new_val: return
		match new_val:
			NO_MOUSE: mouse_sprite.play( "Off" )
			LEFT_MOUSE: mouse_sprite.play( "Left" )
			MIDDLE_MOUSE: mouse_sprite.play( "Middle" )
			RIGHT_MOUSE: mouse_sprite.play( "Right" )
		mouse_state = new_val

func _ready() -> void:
	mouse_state = NO_MOUSE
	material = (telenode.get_child( 0 ) as MeshInstance3D).get_active_material( 0 )
	material.albedo_color = Color( 1,0,1 )
	material.emission = Color( 1,0,1 )

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
	if not collided: 
		mouse_state = NO_MOUSE
		return
	
	var collider := camera_ray.get_collider() as Node3D
	mouse_state = _get_mouse_group( collider, camera_ray.get_collider_shape() )
	
	var on_floor := _is_floor(collider, camera_ray.get_collider_shape())
	material.albedo_color = VALID_COLOR if on_floor else INVALID_COLOR
	material.emission = VALID_COLOR if on_floor else INVALID_COLOR
	
	if teleport_state == 1:
		_tele_data = HitData.new(camera_ray.get_collision_point(),
								camera_ray.get_collision_normal())
		telenode.global_position = _tele_data.hit_point
	elif teleport_state == 2 and on_floor:
		global_position = _tele_data.hit_point

static func _is_in_group(collider: Node3D, shape_index: int, group_name: StringName) -> bool:
	if collider.is_in_group( group_name ): return true
	var body := collider as CollisionObject3D
	if not body: return false
	var shape := body.shape_owner_get_owner( body.shape_find_owner( shape_index ) ) as Node
	return shape != null and shape.is_in_group( group_name )

static func _is_floor(collider: Node3D, shape_index: int) -> bool:
	return _is_in_group(collider, shape_index, &"Floor")

static func _get_mouse_group(collider: Node3D, shape_index: int) -> int:
	# Check raw node hit 
	var collider_group := _get_node_mouse_group( collider )
	if collider_group: return collider_group
	
	# body check
	var body := collider as CollisionObject3D
	if not body: return 0
	
	# Check the actual shape we hit
	var shape := body.shape_owner_get_owner( body.shape_find_owner( shape_index ) ) as Node
	if shape == null: return 0
	return _get_node_mouse_group( shape )

static func _get_node_mouse_group(node: Node) -> int:
	const clickable_groups := [ &"LeftClickable", &"MiddleClickable", &"RightClickable" ]
	var index = 1
	for group in clickable_groups:
		if node.is_in_group( group ): return index
		index += 1
	return 0

func _process(_delta: float) -> void:
	if PIH.is_paused: return
	
	camera.rotation.x = PIH.mouse_x
	rotation.y = PIH.mouse_y
