class_name LinksManager extends HFlowContainer

const LINK := preload("res://prefabs/exhibit_link.tscn")

func add_item(link: Dictionary) -> void:
	var item = LINK.instantiate() as Button
	item.text = link[ "display-text" ]
	#TODO Set item values
	add_child( item )
