@abstract
class_name Prop extends Node3D

func _ready() -> void:
	_category_ready()
	_prop_ready()

@abstract
func _category_ready() -> void

func _prop_ready() -> void: pass
