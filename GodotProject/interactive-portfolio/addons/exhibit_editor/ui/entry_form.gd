@tool
extends VBoxContainer

# The form an entry is edited in: one field for every value in an entry file, plus where the file
# is saved. It also checks the entry as it's edited. Whatever would break or look wrong is listed
# in `problems`, and the field it's about gets a colored outline with the reason under it (red for
# an error, yellow for a note). Nothing here ever stops an entry from being edited or saved.

signal changed # The user changed the entry, or where it's saved
signal problems_changed

const UiKit := preload( "ui_kit.gd" )
const Settings := preload( "../core/settings.gd" )
const EntryData := preload( "../core/entry_data.gd" )
const ImageLibrary := preload( "../core/image_library.gd" )
const FieldBox := preload( "field_box.gd" )
const DateField := preload( "date_field.gd" )
const SkillsField := preload( "skills_field.gd" )
const TextListField := preload( "text_list_field.gd" )
const ImageField := preload( "image_field.gd" )
const SlideListField := preload( "slide_list_field.gd" )
const LinkListField := preload( "link_list_field.gd" )

const FIELD_FILE := "file"
const FIELD_NAME := "name"
const FIELD_DATES := "dates"
const FIELD_DESCRIPTION := "description"
const FIELD_SKILLS := "skills"
const FIELD_CONTRIBUTIONS := "contributions"
const FIELD_NOTES := "notes"
const FIELD_MAIN_IMAGE := "main-image"
const FIELD_SLIDES := "slide-show"
const FIELD_LINKS := "links"

const FILE_ENDING := ".json"
const BAD_FILE_NAME_CHARACTERS := "\\/:*?\"<>|"
const DESCRIPTION_HEIGHT : int = 110
const MAIN_PICTURE_SIZE : int = 96

# Everything wrong with the entry right now: { "field": one of the FIELD_ names, "level": UiKit.LEVEL_..., "text": String }
var problems : Array[ Dictionary ]

var _settings : Settings
var _library : ImageLibrary
var _boxes : Dictionary[ String, FieldBox ]
var _folder_edit : LineEdit
var _file_edit : LineEdit
var _name_edit : LineEdit
var _start_date : DateField
var _end_date : DateField
var _description : TextEdit
var _skills : SkillsField
var _contributions : TextListField
var _notes : TextListField
var _main_image : ImageField
var _main_picture : TextureRect
var _main_info : Label
var _slides : SlideListField
var _links : LinkListField

var _extra : Dictionary # Fields the file had that this form doesn't show. Carried through untouched.
var _filling : bool # The fields are being filled in by code, which isn't the user editing them
var _file_name_follows_name : bool = true
var _loaded_path : String
var _skills_problem : String
var _image_dialog : EditorFileDialog
var _folder_dialog : EditorFileDialog
var _on_image_picked : Callable
var _on_images_picked : Callable
var _last_pick_dir : String # Where the last image was picked from, so a batch can be picked from the same place
var _message_dialog : AcceptDialog
# Text the website would read as HTML: a tag like <b>, or a symbol code like &amp;
var _html_pattern := RegEx.create_from_string( "<[A-Za-z/!]|&#?[A-Za-z0-9]+;" )

func _init(settings: Settings, library: ImageLibrary) -> void:
	_settings = settings
	_library = library
	add_theme_constant_override( &"separation", 8 )
	_build_file_field()
	_build_text_fields()
	_build_list_fields()
	_settings.changed.connect( _on_setting_changed )
	_apply_date_format()
	set_file( _settings.get_data_dir(), "", true )

#region Building the fields

func _build_file_field() -> void:
	var box := _add_box( FIELD_FILE, "File" )
	var folder_row := HBoxContainer.new()
	box.add_body( folder_row )
	folder_row.add_child( _make_caption( "Folder" ) )
	_folder_edit = LineEdit.new()
	_folder_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_edit.text_changed.connect( func(_text: String) -> void: _on_edited() )
	folder_row.add_child( _folder_edit )
	var browse := UiKit.make_icon_button( &"Folder", "Pick the folder", "..." )
	browse.pressed.connect( _browse_folder )
	folder_row.add_child( browse )

	var file_row := HBoxContainer.new()
	box.add_body( file_row )
	file_row.add_child( _make_caption( "File name" ) )
	_file_edit = LineEdit.new()
	_file_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_edit.tooltip_text = "Follows the exhibit's name until you type one of your own."
	_file_edit.text_changed.connect( func(_text: String) -> void:
		# Once it's been typed in, it stops following the exhibit's name. Emptying it hands it back.
		_file_name_follows_name = _file_edit.text.is_empty()
		_on_edited() )
	file_row.add_child( _file_edit )
	file_row.add_child( _make_caption( FILE_ENDING ) )

func _build_text_fields() -> void:
	_name_edit = LineEdit.new()
	_name_edit.text_changed.connect( func(_text: String) -> void:
		if _file_name_follows_name: _file_edit.text = make_file_name( _name_edit.text )
		_on_edited() )
	_add_box( FIELD_NAME, "Name" ).add_body( _name_edit )

	var dates := VBoxContainer.new()
	_start_date = DateField.new( "Start" )
	_end_date = DateField.new( "End" )
	for date : DateField in [ _start_date, _end_date ]:
		date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		date.changed.connect( func(_text: String) -> void: _on_edited() )
		dates.add_child( date )
	_add_box( FIELD_DATES, "Dates" ).add_body( dates )

	_description = TextEdit.new()
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description.custom_minimum_size.y = DESCRIPTION_HEIGHT * UiKit.get_scale()
	_description.text_changed.connect( _on_edited )
	_add_box( FIELD_DESCRIPTION, "Description" ).add_body( _description )

func _build_list_fields() -> void:
	_skills = SkillsField.new()
	_skills.changed.connect( _on_edited )
	_add_field( FIELD_SKILLS, _skills )

	_contributions = TextListField.new( "Contributions", "contribution" )
	_notes = TextListField.new( "Notes", "note" )
	for list : TextListField in [ _contributions, _notes ]:
		list.changed.connect( _on_edited )
		list.own_problem_changed.connect( validate )
	_add_field( FIELD_CONTRIBUTIONS, _contributions )
	_add_field( FIELD_NOTES, _notes )

	var main_box := _add_box( FIELD_MAIN_IMAGE, "Main Image" )
	_main_image = ImageField.new( _library, _browse_image )
	_main_image.changed.connect( func(_name: String) -> void: _on_edited() )
	main_box.add_body( _main_image )
	var picture_row := HBoxContainer.new()
	main_box.add_body( picture_row )
	_main_picture = ImageField.make_picture( MAIN_PICTURE_SIZE )
	picture_row.add_child( _main_picture )
	_main_info = UiKit.make_hint( "" )
	_main_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture_row.add_child( _main_info )

	_slides = SlideListField.new( _library, _browse_image, _browse_images )
	_slides.changed.connect( _on_edited )
	_slides.own_problem_changed.connect( validate )
	_add_field( FIELD_SLIDES, _slides )

	_links = LinkListField.new()
	_links.changed.connect( _on_edited )
	_links.own_problem_changed.connect( validate )
	_add_field( FIELD_LINKS, _links )

func _add_box(field: String, title: String) -> FieldBox:
	return _add_field( field, FieldBox.new( title ) )

func _add_field(field: String, box: FieldBox) -> FieldBox:
	_boxes[ field ] = box
	add_child( box )
	return box

func _make_caption(text: String) -> Label:
	var caption := Label.new()
	caption.text = text
	return caption

#endregion

#region The entry

func get_entry() -> EntryData:
	var entry := EntryData.new()
	entry.name = _name_edit.text
	entry.start_date = _start_date.text
	entry.end_date = _end_date.text
	entry.description = _description.text
	entry.skills = _skills.skills
	entry.contributions = _contributions.items
	entry.notes = _notes.items
	entry.main_image = _main_image.text
	entry.slide_show = _slides.images
	entry.links = _links.links
	entry.extra = _extra.duplicate( true )
	return entry

func set_entry(entry: EntryData) -> void:
	_filling = true
	_name_edit.text = entry.name
	_start_date.text = entry.start_date
	_end_date.text = entry.end_date
	_description.text = entry.description
	_skills.skills = entry.skills
	_contributions.items = entry.contributions
	_notes.items = entry.notes
	_main_image.text = entry.main_image
	_slides.images = entry.slide_show
	_links.links = entry.links
	_extra = entry.extra.duplicate( true )
	_filling = false
	validate()

# The skills there are to pick from (see skill_list.gd). `problem` says why if they couldn't be
# read properly, or if the game and the website disagree about them.
func set_skill_names(names: PackedStringArray, hue_seed: int, problem: String) -> void:
	_skills.set_skill_names( names, hue_seed )
	_skills_problem = problem
	validate()

func get_box(field: String) -> FieldBox:
	return _boxes.get( field )

#endregion

#region The file

# `follows_name` keeps the file name in step with the exhibit's name, for an entry that's never been saved.
func set_file(folder: String, file_name: String, follows_name: bool) -> void:
	_folder_edit.text = _shorten_folder( folder )
	_file_edit.text = file_name.trim_suffix( FILE_ENDING )
	_file_name_follows_name = follows_name
	if follows_name and file_name.is_empty(): _file_edit.text = make_file_name( _name_edit.text )
	validate()

# The file this entry was loaded from or last saved to ("" if neither). Saving over it doesn't need asking about.
func set_loaded_path(path: String) -> void:
	_loaded_path = path
	validate()

func get_folder() -> String:
	return Settings.to_absolute( _folder_edit.text.strip_edges(), _settings.get_webfiles_dir() )

# A folder inside the website is written from the website folder ("assets/data"), which is shorter to
# read and still right on another computer. Anywhere else is written in full.
func _shorten_folder(folder: String) -> String:
	var site := _settings.get_webfiles_dir()
	folder = Settings.clean_path( folder )
	if folder.to_lower().begins_with( site.to_lower() + "/" ): return Settings.to_relative( folder, site )
	return folder

func get_file_name() -> String:
	return _file_edit.text.strip_edges().trim_suffix( FILE_ENDING )

func is_file_name_following_name() -> bool:
	return _file_name_follows_name

# Where saving would write, or "" while the folder or the name can't be used.
func get_file_path() -> String:
	if _find_file_problem()[ 0 ] == UiKit.LEVEL_ERROR: return ""
	return get_folder().path_join( get_file_name() + FILE_ENDING )

# "Example Game 2" -> "example-game-2": only letters and digits, so it's safe in a web address.
static func make_file_name(entry_name: String) -> String:
	var file_name := ""
	for character in entry_name.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"): file_name += character
		elif not file_name.is_empty() and not file_name.ends_with( "-" ): file_name += "-"
	return file_name.trim_suffix( "-" )

func _browse_folder() -> void:
	if _folder_dialog == null:
		_folder_dialog = EditorFileDialog.new()
		_folder_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		_folder_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_folder_dialog.title = "Pick the folder to save the entry in"
		_folder_dialog.dir_selected.connect( func(folder: String) -> void:
			_folder_edit.text = _shorten_folder( folder )
			_on_edited() )
		add_child( _folder_dialog )
	var folder := get_folder()
	_folder_dialog.current_dir = folder if DirAccess.dir_exists_absolute( folder ) else _settings.get_data_dir()
	_folder_dialog.popup_file_dialog()

#endregion

#region Picking images

# Given to every image field. Opens the file dialog, and later hands the picked image's name to on_picked.
func _browse_image(current_name: String, on_picked: Callable) -> void:
	_on_image_picked = on_picked
	# Opens where the current image is, if it's somewhere real.
	var folder := _settings.get_image_path( current_name ).get_base_dir() if not current_name.is_empty() else ""
	_open_image_dialog( EditorFileDialog.FILE_MODE_OPEN_FILE, "Pick an image", folder )

# Given to the slideshow. Opens the file dialog with several files allowed, and later hands all the
# picked images' names to on_picked.
func _browse_images(on_picked: Callable) -> void:
	_on_images_picked = on_picked
	_open_image_dialog( EditorFileDialog.FILE_MODE_OPEN_FILES, "Pick images (hold Ctrl or Shift to pick several)", "" )

func _open_image_dialog(mode: EditorFileDialog.FileMode, title: String, folder: String) -> void:
	if _image_dialog == null:
		_image_dialog = EditorFileDialog.new()
		_image_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_image_dialog.file_selected.connect( pick_image_file )
		_image_dialog.files_selected.connect( pick_image_files )
		add_child( _image_dialog )
	_image_dialog.file_mode = mode
	_image_dialog.title = title
	_image_dialog.clear_filters()
	_image_dialog.add_filter( "*" + _settings.get_value( Settings.IMAGE_EXTENSION ), "Images" )
	# Failing `folder`, where the last image was picked from, and failing that the top of the images folder.
	for candidate : String in [ folder, _last_pick_dir, _settings.get_images_dir() ]:
		if not candidate.is_empty() and DirAccess.dir_exists_absolute( candidate ):
			_image_dialog.current_dir = candidate
			break
	_image_dialog.popup_file_dialog()

# A file was picked in the dialog. Entries store images by a name inside the images folder, so a file
# from anywhere else can't be used, and that's said instead of filling the field with something broken.
func pick_image_file(path: String) -> void:
	_last_pick_dir = path.get_base_dir()
	var found := _settings.get_image_name( path )
	if not found[ "error" ].is_empty():
		show_message( "That image can't be used", found[ "error" ] )
		return
	if _on_image_picked.is_valid(): _on_image_picked.call( found[ "name" ] )

# Several files were picked at once. They're handed over in name order ("shot2" before "shot10"),
# and any that can't be used are listed in a message instead.
func pick_image_files(paths: PackedStringArray) -> void:
	var sorted := Array( paths )
	sorted.sort_custom( func(a: String, b: String) -> bool: return a.naturalnocasecmp_to( b ) < 0 )
	var names : PackedStringArray = []
	var refused : PackedStringArray = []
	for path : String in sorted:
		_last_pick_dir = path.get_base_dir()
		var found := _settings.get_image_name( path )
		if found[ "error" ].is_empty(): names.append( found[ "name" ] )
		else: refused.append( "%s: %s" % [ path.get_file(), found[ "error" ] ] )
	if not names.is_empty() and _on_images_picked.is_valid(): _on_images_picked.call( names )
	if not refused.is_empty():
		var title := "Those images can't be used" if names.is_empty() else "%d of the images weren't added" % refused.size()
		show_message( title, "\n\n".join( refused ) )

func show_message(title: String, text: String) -> void:
	if _message_dialog == null:
		_message_dialog = AcceptDialog.new()
		_message_dialog.dialog_autowrap = true
		add_child( _message_dialog )
	_message_dialog.title = title
	_message_dialog.dialog_text = text
	# Waits for the end of the frame: when a file dialog reports what was picked it hasn't closed yet,
	# and only one dialog can be open at a time.
	_message_dialog.popup_centered.call_deferred( Vector2i( Vector2( 460, 0 ) * UiKit.get_scale() ) )

#endregion

#region Checking

func count_problems(level: int) -> int:
	var count := 0
	for problem in problems:
		if problem[ "level" ] == level: count += 1
	return count

# Looks the whole entry over, outlines the fields with something wrong and fills in `problems`.
func validate() -> void:
	if _filling: return
	var found : Array[ Dictionary ] = []

	var file_problem := _find_file_problem()
	_note( found, FIELD_FILE, file_problem[ 0 ], file_problem[ 1 ] )
	_folder_edit.tooltip_text = "The folder the entry's .json file is saved in. A path that doesn't start from a drive is inside the website folder.
Right now: " + get_folder()

	if _name_edit.text.strip_edges().is_empty(): _note( found, FIELD_NAME, UiKit.LEVEL_ERROR, "The exhibit needs a name." )
	_note( found, FIELD_NAME, UiKit.LEVEL_NOTE, _find_text_note( _name_edit.text ) )

	var missing_dates : PackedStringArray = []
	if _start_date.text.strip_edges().is_empty(): missing_dates.append( "start" )
	if _end_date.text.strip_edges().is_empty(): missing_dates.append( "end" )
	if not missing_dates.is_empty(): _note( found, FIELD_DATES, UiKit.LEVEL_ERROR, "The %s date is empty. The exhibits show both, as \"start - end\"." % " and the ".join( missing_dates ) )
	_note( found, FIELD_DATES, UiKit.LEVEL_NOTE, _find_text_note( _start_date.text + " " + _end_date.text ) )

	if _description.text.strip_edges().is_empty(): _note( found, FIELD_DESCRIPTION, UiKit.LEVEL_ERROR, "The description is empty." )
	_note( found, FIELD_DESCRIPTION, UiKit.LEVEL_NOTE, _find_text_note( _description.text ) )

	_note( found, FIELD_SKILLS, UiKit.LEVEL_ERROR, _skills_problem )
	if _skills.skills == 0: _note( found, FIELD_SKILLS, UiKit.LEVEL_NOTE, "No skills picked yet." )

	_check_text_list( found, FIELD_CONTRIBUTIONS, _contributions, "contribution" )
	_check_text_list( found, FIELD_NOTES, _notes, "note" )
	_check_main_image( found )
	_check_slides( found )
	_check_links( found )

	# Each field shows its worst problem. The first one found wins a tie.
	for field : String in _boxes:
		var worst := {}
		for problem in found:
			if problem[ "field" ] == field and not problem.get( "row_only", false ) and problem[ "level" ] > worst.get( "level", UiKit.LEVEL_NONE ): worst = problem
		_boxes[ field ].set_problem( worst.get( "level", UiKit.LEVEL_NONE ), worst.get( "text", "" ) )

	if found != problems:
		problems = found
		problems_changed.emit()

func _note(found: Array[ Dictionary ], field: String, level: int, text: String, row_only: bool = false) -> void:
	if not text.is_empty(): found.append( { "field": field, "level": level, "text": text, "row_only": row_only } )

# [ level, text ] for where the file would be saved.
func _find_file_problem() -> Array:
	var folder := get_folder()
	var file_name := get_file_name()
	if _folder_edit.text.strip_edges().is_empty(): return [ UiKit.LEVEL_ERROR, "Pick the folder to save the entry in." ]
	if not DirAccess.dir_exists_absolute( folder ): return [ UiKit.LEVEL_ERROR, "This folder doesn't exist: " + _settings.describe_path( folder ) ]
	if file_name.is_empty(): return [ UiKit.LEVEL_ERROR, "The file needs a name." ]
	for character in BAD_FILE_NAME_CHARACTERS:
		if file_name.contains( character ): return [ UiKit.LEVEL_ERROR, "A file name can't have any of these in it:  \\ / : * ? \" < > |" ]
	if not Settings.is_same_path( folder, _settings.get_data_dir() ):
		return [ UiKit.LEVEL_NOTE, "Saved in this folder, the entry won't show up on the website or in the game. They only read %s." % _settings.describe_path( _settings.get_data_dir() ) ]
	var path := folder.path_join( file_name + FILE_ENDING )
	if FileAccess.file_exists( path ) and not Settings.is_same_path( path, _loaded_path ):
		return [ UiKit.LEVEL_NOTE, "There's already a file called %s there. Saving will ask before replacing it." % path.get_file() ]
	return [ UiKit.LEVEL_NONE, "" ]

# Things that are fine in the game but come out differently on the website. "" if there's nothing to say.
func _find_text_note(text: String) -> String:
	if _html_pattern.search( text ): return "The website reads < > and & codes as HTML, so this won't show there the way it's typed. (The game shows it as typed.)"
	if text.strip_edges().contains( "\n" ): return "The game shows these line breaks. The website runs the lines together into one paragraph."
	return ""

func _check_text_list(found: Array[ Dictionary ], field: String, list: TextListField, noun: String) -> void:
	_note( found, field, UiKit.LEVEL_ERROR, list.own_problem )
	var items := list.items
	if items.is_empty(): _note( found, field, UiKit.LEVEL_NOTE, "No %ss yet." % noun )
	for index in items.size():
		var level := UiKit.LEVEL_NONE
		var text := ""
		if items[ index ].strip_edges().is_empty():
			level = UiKit.LEVEL_ERROR
			text = "This %s is empty." % noun
		else:
			text = _find_text_note( items[ index ] )
			if not text.is_empty(): level = UiKit.LEVEL_NOTE
		list.set_item_problem( index, level, text )
		_note( found, field, level, text, true )

func _check_main_image(found: Array[ Dictionary ]) -> void:
	var image_name := _main_image.text
	var looked_up := _library.check( image_name )
	ImageField.show_in_picture( _main_picture, looked_up, image_name )
	var pixels : Vector2i = looked_up[ "size" ]
	_main_info.text = "%d x %d pixels" % [ pixels.x, pixels.y ] if looked_up[ "ok" ] else ""
	if image_name.is_empty():
		_note( found, FIELD_MAIN_IMAGE, UiKit.LEVEL_ERROR, "No main image yet. The 3D exhibit in the museum shows this picture." )
	elif not looked_up[ "ok" ]:
		_main_info.text = "Showing the stand-in image instead."
		_note( found, FIELD_MAIN_IMAGE, UiKit.LEVEL_ERROR, looked_up[ "problem" ] )

func _check_slides(found: Array[ Dictionary ]) -> void:
	_note( found, FIELD_SLIDES, UiKit.LEVEL_ERROR, _slides.own_problem )
	var images := _slides.images
	for index in images.size():
		var looked_up := _library.check( images[ index ] )
		var text : String = "This slide has no image named." if images[ index ].is_empty() else looked_up[ "problem" ]
		var level := UiKit.LEVEL_NONE if looked_up[ "ok" ] else UiKit.LEVEL_ERROR
		_slides.set_item_problem( index, level, text )
		_note( found, FIELD_SLIDES, level, text, true )

func _check_links(found: Array[ Dictionary ]) -> void:
	_note( found, FIELD_LINKS, UiKit.LEVEL_ERROR, _links.own_problem )
	var links := _links.links
	for index in links.size():
		var shown : String = links[ index ].get( EntryData.LINK_TEXT, "" ).strip_edges()
		var address : String = links[ index ].get( EntryData.LINK_URL, "" ).strip_edges()
		var level := UiKit.LEVEL_ERROR
		var text := ""
		if shown.is_empty(): text = "This link has no text to show, so there'd be nothing to click."
		elif address.is_empty(): text = "This link has no address to open."
		else:
			level = UiKit.LEVEL_NOTE
			if not address.contains( "://" ) and not address.begins_with( "mailto:" ):
				text = "Without https:// at the front, the website looks for this as a page of its own instead of another site."
			else:
				text = _find_text_note( shown )
		if text.is_empty(): level = UiKit.LEVEL_NONE
		_links.set_item_problem( index, level, text )
		_note( found, FIELD_LINKS, level, text, true )

#endregion

func _on_edited() -> void:
	if _filling: return
	validate()
	changed.emit()

func _on_setting_changed(key: String) -> void:
	if key in [ Settings.DATE_FORMAT, Settings.MONTH_FORMAT, Settings.YEAR_FORMAT ]: _apply_date_format()
	validate()

# The calendar's three formats, in the order of its bullets: full date, month, year.
func _apply_date_format() -> void:
	var formats : Array[ String ] = [ _settings.get_value( Settings.DATE_FORMAT ), _settings.get_value( Settings.MONTH_FORMAT ), _settings.get_value( Settings.YEAR_FORMAT ) ]
	_start_date.formats = formats
	_end_date.formats = formats
