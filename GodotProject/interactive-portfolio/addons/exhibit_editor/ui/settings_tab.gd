@tool
extends ScrollContainer

# The Settings tab: one row for every path and name in settings.gd. A setting that can't be used
# as it stands says why in red under its row, and nothing else stops working because of it.
#
# A change takes effect when Enter is pressed, when the box loses focus, or after a short pause in
# typing. (Not on every key, or half-typed paths would restart the previews over and over.)

const UiKit := preload( "ui_kit.gd" )
const Settings := preload( "../core/settings.gd" )
const SkillList := preload( "../core/skill_list.gd" )
const DateText := preload( "../core/date_text.gd" )

const LABEL_WIDTH : int = 190
const APPLY_DELAY_MSEC : int = 700

var _settings : Settings
var _rows : Dictionary[ String, Dictionary ] # key -> { "edit": LineEdit, "problem": Label, "info": Label, "reset": Button }
var _typed_key : String # The setting being typed into, waiting for a pause
var _typed_at : int
var _dialog : EditorFileDialog
var _dialog_key : String

func _init(settings: Settings) -> void:
	_settings = settings
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side : String in [ "left", "right", "top", "bottom" ]: margin.add_theme_constant_override( "margin_" + side, 12 )
	add_child( margin )
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override( &"separation", 6 )
	margin.add_child( rows )

	rows.add_child( UiKit.make_hint( "Where the Exhibit Editor finds things. If a file or folder moves, or a function gets renamed, change it here. Anything that differs from its default is saved in %s." % Settings.FILE_PATH ) )

	var group := ""
	for definition in Settings.DEFINITIONS:
		if definition[ "group" ] != group:
			group = definition[ "group" ]
			rows.add_child( HSeparator.new() )
			var heading := Label.new()
			heading.text = group
			heading.theme_type_variation = &"HeaderMedium"
			rows.add_child( heading )
		rows.add_child( _make_row( definition ) )

	rows.add_child( HSeparator.new() )
	var reset_all := UiKit.make_button( "Put every setting back to its default", &"Reload", "" )
	reset_all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset_all.pressed.connect( func() -> void:
		_typed_key = ""
		_settings.reset_all()
		refresh() )
	rows.add_child( reset_all )

	_settings.changed.connect( func(_key: String) -> void: refresh() )
	refresh()

# Re-reads every value and checks each one again. Files can appear and disappear behind the editor's back.
func refresh() -> void:
	for key : String in _rows:
		var row := _rows[ key ]
		var edit : LineEdit = row[ "edit" ]
		if key != _typed_key and edit.text != _settings.get_value( key ): edit.text = _settings.get_value( key )
		row[ "reset" ].visible = not _settings.is_default( key )
		var problem := _settings.find_problem( key )
		row[ "problem" ].text = problem
		row[ "problem" ].visible = not problem.is_empty()
		var info := _get_info( key ) if problem.is_empty() else ""
		row[ "info" ].text = info
		row[ "info" ].visible = not info.is_empty()

func _process(_delta: float) -> void:
	if not _typed_key.is_empty() and Time.get_ticks_msec() - _typed_at >= APPLY_DELAY_MSEC: _apply_typed()

func _make_row(definition: Dictionary) -> Control:
	var key : String = definition[ "key" ]
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override( &"separation", 1 )

	var line := HBoxContainer.new()
	holder.add_child( line )
	var label := Label.new()
	label.text = definition[ "label" ]
	label.custom_minimum_size.x = LABEL_WIDTH * UiKit.get_scale()
	label.tooltip_text = definition[ "help" ]
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child( label )
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = "Found automatically" if definition[ "default" ].is_empty() else definition[ "default" ]
	edit.text_changed.connect( func(_text: String) -> void:
		if _typed_key != key: _apply_typed()
		_typed_key = key
		_typed_at = Time.get_ticks_msec() )
	edit.text_submitted.connect( func(_text: String) -> void: _apply_typed() )
	edit.focus_exited.connect( _apply_typed )
	line.add_child( edit )
	if definition[ "kind" ] != Settings.KIND_TEXT:
		var browse := UiKit.make_icon_button( &"Folder", "Pick it from disk", "..." )
		browse.pressed.connect( _browse.bind( key ) )
		line.add_child( browse )
	var reset := UiKit.make_icon_button( &"Reload", "Put this setting back to its default: %s" % ("(found automatically)" if definition[ "default" ].is_empty() else definition[ "default" ]), "Reset" )
	reset.pressed.connect( func() -> void:
		_typed_key = ""
		_settings.set_value( key, _settings.get_default( key ) )
		refresh() )
	line.add_child( reset )

	var details := VBoxContainer.new()
	details.add_theme_constant_override( &"separation", 1 )
	var indent := MarginContainer.new()
	indent.add_theme_constant_override( &"margin_left", int( LABEL_WIDTH * UiKit.get_scale() ) + 4 )
	indent.add_child( details )
	holder.add_child( indent )
	details.add_child( UiKit.make_hint( definition[ "help" ] ) )
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child( info )
	var problem := Label.new()
	problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	problem.add_theme_color_override( &"font_color", UiKit.get_level_color( UiKit.LEVEL_ERROR ) )
	details.add_child( problem )

	_rows[ key ] = { "edit": edit, "problem": problem, "info": info, "reset": reset }
	return holder

func _apply_typed() -> void:
	if _typed_key.is_empty(): return
	var key := _typed_key
	_typed_key = ""
	_settings.set_value( key, _rows[ key ][ "edit" ].text )
	refresh()

# What a setting that's fine currently amounts to, where that isn't obvious from its value.
func _get_info(key: String) -> String:
	match key:
		Settings.WEBFILES_DIR:
			return _settings.get_webfiles_dir()
		Settings.BROWSER_PATH:
			if _settings.get_value( key ).is_empty(): return "Using " + _settings.find_browser()
		Settings.DATE_FORMAT, Settings.MONTH_FORMAT, Settings.YEAR_FORMAT:
			var today := DateText.get_today()
			return "Today comes out as " + DateText.format_date( today[ "year" ], today[ "month" ], today[ "day" ], _settings.get_value( key ) )
		Settings.GAME_SKILLS:
			return _describe_skills( SkillList.read( _settings.get_value( key ) ) )
		Settings.SITE_SKILLS:
			var site := SkillList.read( _settings.get_site_skills_path() )
			var game := SkillList.read( _settings.get_value( Settings.GAME_SKILLS ) )
			var difference := SkillList.describe_difference( game[ "skills" ], site[ "skills" ] ) if game[ "error" ].is_empty() and site[ "error" ].is_empty() else ""
			return _describe_skills( site ) if difference.is_empty() else "Doesn't match the game's list. " + difference
	return ""

static func _describe_skills(found: Dictionary) -> String:
	if not found[ "error" ].is_empty(): return found[ "error" ]
	return "%d skills: %s" % [ found[ "skills" ].size(), ", ".join( found[ "skills" ] ) ]

#region Picking from disk

func _browse(key: String) -> void:
	if _dialog == null:
		_dialog = EditorFileDialog.new()
		_dialog.file_selected.connect( _on_picked )
		_dialog.dir_selected.connect( _on_picked )
		add_child( _dialog )
	_dialog_key = key
	var kind : int = _settings.get_definition( key )[ "kind" ]
	var picks_folder := kind == Settings.KIND_PROJECT_DIR or kind == Settings.KIND_SITE_DIR
	_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR if picks_folder else EditorFileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = EditorFileDialog.ACCESS_RESOURCES if kind == Settings.KIND_RES_FILE else EditorFileDialog.ACCESS_FILESYSTEM
	_dialog.title = "Pick: " + _settings.get_definition( key )[ "label" ]
	_dialog.clear_filters()
	match kind:
		Settings.KIND_RES_FILE:
			if key in [ Settings.UI_SCENE, Settings.ENTRY_SCENE ]: _dialog.add_filter( "*.tscn, *.scn", "Scenes" )
			else: _dialog.add_filter( "*.gd", "Scripts" )
			_dialog.current_dir = _settings.get_value( key ).get_base_dir() if ResourceLoader.exists( _settings.get_value( key ) ) else "res://"
		Settings.KIND_IMAGE:
			_dialog.add_filter( "*" + _settings.get_value( Settings.IMAGE_EXTENSION ), "Images" )
			_dialog.current_dir = _settings.get_images_dir()
		Settings.KIND_PROGRAM:
			if OS.get_name() == "Windows": _dialog.add_filter( "*.exe", "Programs" )
			var browser := _settings.find_browser()
			if not browser.is_empty(): _dialog.current_dir = browser.get_base_dir()
		Settings.KIND_PROJECT_DIR:
			_dialog.current_dir = _settings.get_webfiles_dir() if DirAccess.dir_exists_absolute( _settings.get_webfiles_dir() ) else _settings.get_project_dir()
		_:
			_dialog.current_dir = _settings.get_webfiles_dir()
	_dialog.popup_file_dialog()

# Writes what was picked the way the setting is meant to be written: relative to the project folder,
# relative to the website folder, as an image name, or as it is.
func _on_picked(path: String) -> void:
	var key := _dialog_key
	var value := path
	match _settings.get_definition( key )[ "kind" ]:
		Settings.KIND_PROJECT_DIR:
			value = Settings.to_relative( path, _settings.get_project_dir() )
		Settings.KIND_SITE_DIR, Settings.KIND_SITE_FILE:
			value = Settings.to_relative( path, _settings.get_webfiles_dir() )
		Settings.KIND_IMAGE:
			var found := _settings.get_image_name( path )
			if not found[ "error" ].is_empty():
				_rows[ key ][ "problem" ].text = found[ "error" ]
				_rows[ key ][ "problem" ].visible = true
				return
			value = found[ "name" ]
		Settings.KIND_PROGRAM:
			value = Settings.clean_path( path )
	_typed_key = ""
	_settings.set_value( key, value )
	refresh()

#endregion
