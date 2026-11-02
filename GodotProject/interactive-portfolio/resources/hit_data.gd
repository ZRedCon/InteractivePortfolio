class_name HitData extends RefCounted

var hit_point : Vector3
var hit_normal : Vector3

func _init(point: Vector3, normal: Vector3) -> void:
	hit_point = point
	hit_normal = normal
