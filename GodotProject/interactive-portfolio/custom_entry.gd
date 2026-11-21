@tool
class_name CustomEntry extends Resource

## An entry made for one exhibit (an ExhibitDisplay set to CUSTOM). It's kept in the map instead of the entry
## folder, so the website never lists it. The fields match the entry files in Webfiles/assets/data.

@export var name : String
@export_multiline var description : String
## Like "10/2025"
@export var start_date : String
@export var end_date : String
@export var skills : int
@export var contribution : PackedStringArray
@export var notes : PackedStringArray
## An image in Webfiles/assets/images, without ".png", like "202/FrongChoas"
@export var main_image : String
@export var slide_show : PackedStringArray
## Each link's text, and the address it goes to
@export var links : Dictionary[ String, String ]

func _validate_property(property: Dictionary) -> void:
	# A checkbox for each skill
	if property.name == "skills":
		property.hint = PROPERTY_HINT_FLAGS
		property.hint_string = ",".join( Entry.SKILLS )

## The Entry the game shows
func to_entry() -> Entry:
	var link_list : Array[ Dictionary ] = []
	for text in links: link_list.append( { "display-text": text, "url": links[ text ] } )
	return Entry.new( name, description, [ start_date, end_date ], skills, contribution, notes, main_image, slide_show, link_list )
