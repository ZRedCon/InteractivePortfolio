class_name Entry extends RefCounted

static var SKILLS : Array[ String ] = [
	"Game Design",
	"Game Dev",
	"Programming",
	"Web Design & Dev",
	"Music Comp",
	"Audio Design",
	"Art",
	"UI/UX",
	"Production"
]

const SEED = 951;

static func get_hue(index: int) -> float:
	return ((SEED * (index+1)) % 360) / 360.0

static func color_from_index(index: int) -> Color:
	return Color.from_hsv(get_hue(index), 1.0, 1.0)

static func to_skills(from: int) -> Array[ String ]:
	var labels : Array[ String ]
	var index : int = 0
	while from > 0:
		if from & 1 == 1:
			labels.append( SKILLS[ index ] )
		index += 1
		from >>= 1
	
	return labels

static func to_indecies(from: int) -> Array[ int ]:
	var indecies : Array[ int ]
	var index : int = 0
	while from > 0:
		if from & 1 == 1: indecies.append( index )
		index += 1
		from >>= 1
	
	return indecies

static func to_int(from: Array[ String ]) -> int:
	var val : int = 0
	for item in from:
		var index = SKILLS.find( item )
		if index != -1:
			val += int( pow(2, index) )
	return val

var name : String
var descr : String
var start_date : String
var end_date : String
var skills : int
var contribution : PackedStringArray
var notes : PackedStringArray
var main_image : String
var slide_show_images : PackedStringArray
var supplementary_links : Array[ Dictionary ]

func _init(_name: String, _decsr: String, 
	time: PackedStringArray, _skills: Variant, 
	contri: PackedStringArray, _notes: PackedStringArray,
	main_img: String, slide_show: PackedStringArray,
	supple_links: Array) -> void:
	name = _name
	descr = _decsr
	start_date = time[ 0 ]
	end_date = time[ 1 ]
	skills = to_int( _skills ) if _skills is PackedStringArray else _skills
	contribution = contri
	notes = _notes
	main_image = main_img
	slide_show_images = slide_show
	supplementary_links.assign(supple_links)

func _to_string() -> String:
	return ("Name: " + name + 
			"\n  Desc: " + descr + 
			"\n  Delta time ( " + start_date + " -> " + end_date + 
			" )\n  Skills: " + str( to_skills( skills ) ) + 
			"\n  Contribution: " + str( contribution ) + 
			"\n  Notes: " + str( notes ) +
			"\n  Main Image: " + main_image +
			"\n  Slide show: " + str( slide_show_images ) +
			"\n  Links: " + str( supplementary_links ))
