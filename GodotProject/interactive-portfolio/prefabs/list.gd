class_name UnorderedList extends VBoxContainer

const LIST_ITEM := preload("res://prefabs/list_item.tscn")

func add_item(text: String) -> void:
	var item = LIST_ITEM.instantiate() as ListItem
	item.set_values( text )
	add_child( item )

func remove_items() -> void:
	for child in get_children():
		child.queue_free()
