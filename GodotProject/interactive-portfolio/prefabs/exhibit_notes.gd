class_name ExhibitNotes extends VBoxContainer

const NOTE_ITEM := preload("res://prefabs/exhibit_note.tscn")

func add_item(text: String) -> void:
	var item = NOTE_ITEM.instantiate() as Label
	item.text = text
	add_child( item )

func remove_items() -> void:
	for child in get_children():
		child.queue_free()
