class_name SlideShow extends Control

func add_item(path: String) -> void:
	pass
	
func remove_items() -> void:
	for child in get_children():
		child.queue_free()
