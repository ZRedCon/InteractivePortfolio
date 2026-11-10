class_name LinksManager extends HFlowContainer

const LINK := preload("res://prefabs/exhibit_link.tscn")

func add_item(link: Dictionary) -> void:
	var item = LINK.instantiate() as LinkButton
	item.text = link[ "display-text" ]
	item.uri = link[ "url" ]
	item.pressed.connect( func(): print("Clicked!") )
	add_child( item )

func remove_items() -> void:
	for child in get_children():
		child.queue_free()
