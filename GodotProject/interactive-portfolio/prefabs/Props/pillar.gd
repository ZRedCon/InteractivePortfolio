class_name Pillar extends Node3D

static var locations_prexisting : Array[ Vector3 ] = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for location in locations_prexisting:
		if location.is_equal_approx( global_position ):
			queue_free()
			return
		
	locations_prexisting.append( global_position )
