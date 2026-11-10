class_name ExhibitUI extends Control

@onready var header_name := $Exhibit/Header/EntryName
@onready var header_date := $Exhibit/Header/Date
@onready var skills : SkillsManager = $Exhibit/Skills
@onready var content : ContentAdjuster = $Exhibit/Content
@onready var links : LinksManager = $Exhibit/Links
@onready var slide_show_holder : SlideShow = $Exhibit/Content/SlideShow
@onready var description := $Exhibit/Content/TextImportant/ProjDesc/Description
@onready var contribution_holder : UnorderedList = $Exhibit/Content/TextImportant/Contribution/List
@onready var notes_holder : ExhibitNotes = $Exhibit/Content/TextUnimportant/Notes

#@var name : String
#var descr : String
#@var start_date : String
#@var end_date : String
#@var skills : int
#var contribution : PackedStringArray
#var notes : PackedStringArray
#var main_image : String
#var slide_show_images : PackedStringArray
#var supplementary_links : Array[ Dictionary ]

func set_values_from_entry(entry: Entry) -> void:
	set_values(entry.name, entry.descr, entry.start_date, 
				entry.end_date, entry.skills, entry.contribution,
				entry.notes, entry.slide_show_images, entry.supplementary_links)

func set_values(exhibit_name: String, desc: String,
			date_start: String, date_end: String, 
			skills_enum: int, contributions: PackedStringArray, 
			notes: PackedStringArray, slide_show: PackedStringArray, 
			sup_links: Array[ Dictionary ]):
	header_name.text = exhibit_name						# item name
	header_date.text = date_start + " - " + date_end	# start & end date
	skills.remove_skills()								# skills
	for skill in Entry.to_indecies( skills_enum ):
		skills.add_from_index( skill )
	description.text = desc								# description
	contribution_holder.remove_items()					# contributions
	for contri in contributions:
		contribution_holder.add_item( contri )
	slide_show_holder.remove_items()					# slideshow
	for slide in slide_show:
		slide_show_holder.add_item( slide )
	notes_holder.remove_items()							# notes
	for note in notes:
		notes_holder.add_item( note )
	links.remove_items()								# supplementary_links
	for link in sup_links:
		links.add_item( link )
	

func _ready() -> void:
	set_values("Name", 
				"Desc", 
				"start", 
				"end", 
				511, 
				PackedStringArray([ "contribution1", "contribution1" ]), 
				PackedStringArray([ "note1", "note2" ]), 
				PackedStringArray([ "Debug/Debug1/pair0", "Debug/Debug1/pair1" ]),
				[
					{ "display-text": "Github", "url": "https://github.com/ZRedCon/InteractivePortfolio"},
					{ "display-text": "Github2", "url": "https://github.com/ZRedCon/InteractivePortfolio"},
				]
	)
