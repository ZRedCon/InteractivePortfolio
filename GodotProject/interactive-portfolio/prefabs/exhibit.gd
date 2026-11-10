class_name ExhibitUI extends Control

@onready var header_name := $Exhibit/Header/EntryName
@onready var header_date := $Exhibit/Header/Date
@onready var skills : SkillsManager = $Exhibit/Skills
@onready var content : ContentAdjuster = $Exhibit/Content
@onready var links : LinksManager = $Exhibit/Links

#var name : String
#var descr : String
#var start_date : String
#var end_date : String
#var skills : int
#var contribution : PackedStringArray
#var notes : PackedStringArray
#var main_image : String
#var slide_show_images : PackedStringArray
#var supplementary_links : Array[ Dictionary ]

func set_values(exhibit_name: String, date_start: String, 
			date_end: String, skills_enum: int, 
			contributions: PackedStringArray, notes: PackedStringArray,
			slide_show: PackedStringArray, sup_links: Array[ Dictionary ]):
	header_name.text = exhibit_name
	header_date.text = date_start + " - " + date_end
	var skillIDs = Entry.to_skills( skills_enum )
	for skill in skillIDs:
		skills.add_skill(skill, Entry.color_from_index(Entry.SKILLS.find(skill)))
	
