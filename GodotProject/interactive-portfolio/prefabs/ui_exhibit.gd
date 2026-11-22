class_name ExhibitUI extends Control

@onready var header_name := $Card/Exhibit/Header/EntryName
@onready var header_date := $Card/Exhibit/Header/Date
@onready var skills : SkillsManager = $Card/Exhibit/Skills
@onready var links : LinksManager = $Card/Exhibit/Links
@onready var text_scroll : ScrollContainer = $Card/Exhibit/Content/TextScroll
@onready var description := $Card/Exhibit/Content/TextScroll/Text/TextImportant/ProjDesc/Description
@onready var contribution_holder : UnorderedList = $Card/Exhibit/Content/TextScroll/Text/TextImportant/Contribution/List
@onready var notes_holder : ExhibitNotes = $Card/Exhibit/Content/TextScroll/Text/TextUnimportant/Notes
@onready var slide_frame : AspectRatioContainer = $Card/Exhibit/Content/SlideFrame
@onready var slide_show_holder : SlideShow = $Card/Exhibit/Content/SlideFrame/SlideShow

var tween : Tween

# In the game this UI starts hidden (controller.tscn hides it), so it can't catch clicks meant for the game.
# Sliding it off screen alone wouldn't do that: offset_transform only moves where it's drawn.
func arrive(display: Entry) -> void:
	set_values_from_entry(display)
	if not visible: offset_transform_position.x = size.x # Start off screen to the right, unless it's still on its way out
	show()
	if tween: tween.kill()
	tween = create_tween()
	tween.tween_property(self, "offset_transform_position", Vector2.ZERO, 1.0)\
			.set_trans(Tween.TRANS_EXPO)\
			.set_ease(Tween.EASE_OUT)


func leave() -> void:
	if tween: tween.kill()
	tween = create_tween()
	tween.tween_property(self, "offset_transform_position", Vector2(size.x, 0), 0.5)\
			.set_trans(Tween.TRANS_BACK)\
			.set_ease(Tween.EASE_IN)
	tween.tween_callback(hide)

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
	slide_frame.visible = not slide_show.is_empty()		# no images: the text gets the whole row
	notes_holder.remove_items()							# notes
	for note in notes:
		notes_holder.add_item( note )
	links.remove_items()								# supplementary_links
	links.add_set_of_links( sup_links )
	text_scroll.scroll_vertical = 0						# each entry starts at the top of its text

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
					{ "display-text": "Github3", "url": "https://github.com/ZRedCon/InteractivePortfolio"},
					{ "display-text": "Github4", "url": "https://github.com/ZRedCon/InteractivePortfolio"},
					{ "display-text": "Github5", "url": "https://github.com/ZRedCon/InteractivePortfolio"},
					{ "display-text": "Github6", "url": "https://github.com/ZRedCon/InteractivePortfolio"},
				]
	)
