class_name LinksManager extends HFlowContainer

const ENABLE_WIDGETS := false;

const LINK_SEPERATOR := preload("res://prefabs/link_seperator.tscn")
const LINK := preload("res://prefabs/exhibit_link.tscn")

func add_set_of_links(links: Array[ Dictionary ]) -> void:
	for link in links:
		add_item( link )
	
	var index = 1
	while index < get_child_count():
		var seperator = LINK_SEPERATOR.instantiate()
		add_child( seperator )
		move_child( seperator, index )
		index += 2

func parse_widget(text: String) -> String:
	var split := text.split( ";;", false )
	if split.size() == 0: return ""
	elif split.size() == 1: return split[ 0 ]
	elif not ENABLE_WIDGETS: return split[ 1 ]
	
	#TODO implement widge parsing
	var widget = "TODO"
	return widget + "  " + split[1]

func add_item(link: Dictionary) -> void:
	var item = LINK.instantiate() as LinkButton
	item.text = parse_widget( link[ "display-text" ] )
	item.uri = link[ "url" ]
	add_child( item )

# Taken out of the tree right away: queue_free alone leaves them in until the end of the frame, and
# add_set_of_links would put separators between them
func remove_items() -> void:
	for child in get_children():
		remove_child( child )
		child.queue_free()
