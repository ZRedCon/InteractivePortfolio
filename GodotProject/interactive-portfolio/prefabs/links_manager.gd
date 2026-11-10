class_name LinksManager extends HFlowContainer

const LINK_SEPERATOR := preload("res://prefabs/link_seperator.tscn")
const LINK := preload("res://prefabs/exhibit_link.tscn")

func add_set_of_links(links: Array[ Dictionary ]) -> void:
	await get_tree().process_frame
	for link in links:
		add_item( link )
	
	var index = 1
	while index < get_child_count():
		var seperator = LINK_SEPERATOR.instantiate()
		add_child( seperator )
		move_child( seperator, index )
		index += 2

func add_item(link: Dictionary) -> void:
	var item = LINK.instantiate() as LinkButton
	item.text = link[ "display-text" ]
	item.uri = link[ "url" ]
	add_child( item )

func remove_items() -> void:
	for child in get_children():
		child.queue_free()
