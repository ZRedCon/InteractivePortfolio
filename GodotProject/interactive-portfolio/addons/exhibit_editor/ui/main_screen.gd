@tool
extends TabContainer

# The Exhibit Editor's whole window (what shows when the "Exhibits" tab at the top of the editor is
# picked). Two tabs of its own: Entry, with the form on the left and the four previews on the
# right, and Settings.
#
# This is where the pieces meet: it loads and saves entry files, keeps the previews showing what's
# in the form, and remembers the entry being worked on between editor sessions.

const UiKit := preload( "ui_kit.gd" )
const Settings := preload( "../core/settings.gd" )
const EntryData := preload( "../core/entry_data.gd" )
const DataIndex := preload( "../core/data_index.gd" )
const SkillList := preload( "../core/skill_list.gd" )
const JsonText := preload( "../core/json_text.gd" )
const ImageLibrary := preload( "../core/image_library.gd" )
const GodotPreview := preload( "../preview/godot/godot_preview.gd" )
const WebPreview := preload( "../preview/web/web_preview.gd" )
const EntryForm := preload( "entry_form.gd" )
const PreviewArea := preload( "preview_area.gd" )
const SettingsTab := preload( "settings_tab.gd" )

# Typing stops for this long before the previews are told, so they aren't redone for every letter.
const PREVIEW_DELAY_MSEC : int = 150
const SESSION_DELAY_MSEC : int = 1000
const SESSION_FILE := "session.json"
# With the Exhibits screen out of sight this long, the browser and the helper are closed until it's back.
const IDLE_STOP_MSEC : int = 5 * 60 * 1000
const FORM_MIN_WIDTH : int = 380
const FORM_START_WIDTH : int = 470

var _settings := Settings.new()
var _library : ImageLibrary
var _godot : GodotPreview
var _web : WebPreview
var _cache_dir : String

var _form : EntryForm
var _form_scroll : ScrollContainer
var _area : PreviewArea
var _settings_tab : SettingsTab
var _file_label : Label
var _status_label : Label
var _problems_button : Button
var _open_dialog : EditorFileDialog
var _confirm_dialog : ConfirmationDialog
var _on_confirmed : Callable

var _skill_names : PackedStringArray
# The entry as it was last loaded or saved. Empty for an entry that never has been.
var _baseline : Dictionary
var _loaded_path : String
var _shown : bool
var _preview_due : int
var _session_due : int
var _hidden_at : int

func _init() -> void:
	name = "ExhibitEditor"
	# The editor stacks its screens in a column, and this one should take all the height there is.
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings.load_saved()
	_library = ImageLibrary.new( _settings )
	_cache_dir = _find_cache_dir()
	DirAccess.make_dir_recursive_absolute( _cache_dir )

	_godot = GodotPreview.new()
	_godot.name = "GodotPreview"
	add_child( _godot, false, Node.INTERNAL_MODE_BACK )
	_godot.setup( _settings, _cache_dir )
	_web = WebPreview.new()
	_web.name = "WebPreview"
	add_child( _web, false, Node.INTERNAL_MODE_BACK )
	_web.setup( _settings, _cache_dir )
	_web.link_clicked.connect( _on_link_clicked )

	_build_entry_tab()
	_settings_tab = SettingsTab.new( _settings )
	_settings_tab.name = "Settings"
	add_child( _settings_tab )

	_settings.changed.connect( _on_setting_changed )
	tab_changed.connect( func(_tab: int) -> void: _settings_tab.refresh() )
	_read_skills()
	_restore_session()
	_update_file_label()

func _find_cache_dir() -> String:
	# One folder per project, in the editor's own cache: nothing here belongs in the project or in Git.
	var project_tag := _settings.get_project_dir().md5_text().left( 8 )
	var base := EditorInterface.get_editor_paths().get_cache_dir() if Engine.is_editor_hint() else OS.get_cache_dir()
	return base.path_join( "exhibit_editor" ).path_join( project_tag )

func _build_entry_tab() -> void:
	var split := HSplitContainer.new()
	split.name = "Entry"
	add_child( split )

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = FORM_MIN_WIDTH * UiKit.get_scale()
	split.add_child( left )

	var toolbar := HBoxContainer.new()
	left.add_child( toolbar )
	var new_button := UiKit.make_button( "New", &"New", "Start a new, empty entry" )
	new_button.pressed.connect( request_new )
	toolbar.add_child( new_button )
	var open_button := UiKit.make_button( "Open...", &"Load", "Open an entry's .json file to edit it" )
	open_button.pressed.connect( request_open )
	toolbar.add_child( open_button )
	var save_button := UiKit.make_button( "Save", &"Save", "Save the entry to the folder and file name in the File box, and update the entry index" )
	save_button.pressed.connect( request_save )
	toolbar.add_child( save_button )
	_file_label = Label.new()
	_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_file_label.clip_text = true
	_file_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toolbar.add_child( _file_label )

	_form_scroll = ScrollContainer.new()
	_form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child( _form_scroll )
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override( &"margin_right", 8 )
	_form_scroll.add_child( margin )
	_form = EntryForm.new( _settings, _library )
	margin.add_child( _form )
	_form.changed.connect( _on_form_changed )
	_form.problems_changed.connect( _update_problem_summary )

	var status_bar := HBoxContainer.new()
	left.add_child( status_bar )
	_problems_button = Button.new()
	_problems_button.flat = true
	_problems_button.tooltip_text = "Show the first field with a problem"
	_problems_button.pressed.connect( _show_first_problem )
	status_bar.add_child( _problems_button )
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	status_bar.add_child( _status_label )

	_area = PreviewArea.new( _godot, _web, _get_scene_titles() )
	_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child( _area )
	# Only the previews stretch, so this offset is simply how wide the form starts out.
	split.split_offset = int( FORM_START_WIDTH * UiKit.get_scale() )
	_update_problem_summary()

func _get_scene_titles() -> Dictionary:
	return { "ui": _settings.get_value( Settings.UI_SCENE ).get_file(), "entry": _settings.get_value( Settings.ENTRY_SCENE ).get_file() }

#region Showing, hiding and closing

# The plugin calls this when the Exhibits screen is switched to or away from.
func set_shown(on: bool) -> void:
	_shown = on
	visible = on
	if on:
		_refresh_from_disk()
		_godot.start()
		_web.start()
		_send_to_previews()
	else:
		_hidden_at = Time.get_ticks_msec()
	_godot.set_active( on )
	_web.set_active( on )
	_area.refresh()

# The project's scenes or scripts changed, so what the previews run is out of date.
func notify_project_changed() -> void:
	_godot.notify_project_changed()
	_read_skills()

# The plugin calls this as the editor closes or the plugin is switched off.
func shut_down() -> void:
	_save_session()
	_godot.stop()
	_web.stop()

func _notification(what: int) -> void:
	# Coming back to the editor: files may have been added, renamed or fixed in the meantime.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and _shown and _form: _refresh_from_disk()

func _refresh_from_disk() -> void:
	_library.forget()
	_read_skills()
	_form.validate()
	_settings_tab.refresh()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _preview_due > 0 and now >= _preview_due:
		_preview_due = 0
		_send_to_previews()
	if _session_due > 0 and now >= _session_due:
		_session_due = 0
		_save_session()
	if not _shown and _hidden_at > 0 and now - _hidden_at > IDLE_STOP_MSEC:
		_hidden_at = 0
		_godot.stop()
		_web.stop()

func _send_to_previews() -> void:
	var json := _form.get_entry().to_json()
	_godot.set_entry_json( json )
	_web.set_entry_json( json )

func _on_setting_changed(key: String) -> void:
	if key in [ Settings.GAME_SKILLS, Settings.SITE_SKILLS, Settings.WEBFILES_DIR ]: _read_skills()
	if key in [ Settings.UI_SCENE, Settings.ENTRY_SCENE ]:
		var titles := _get_scene_titles()
		_area.set_scene_titles( titles[ "ui" ], titles[ "entry" ] )

func _on_link_clicked(url: String) -> void:
	# The preview stays put, and the link opens in the normal browser, as it would for a visitor.
	OS.shell_open( url )
	_set_status( "Opened " + url )

# Reads the skill list from the game's script and from the website's, and checks they agree.
func _read_skills() -> void:
	var game := SkillList.read( _settings.get_value( Settings.GAME_SKILLS ) )
	var site := SkillList.read( _settings.get_site_skills_path() )
	var problem := ""
	if not game[ "error" ].is_empty(): problem = "Couldn't read the game's skill list. %s. (It's set in the Settings tab.)" % game[ "error" ]
	elif not site[ "error" ].is_empty(): problem = "Couldn't read the website's skill list to compare. %s. (It's set in the Settings tab.)" % site[ "error" ]
	else:
		var difference := SkillList.describe_difference( game[ "skills" ], site[ "skills" ] )
		if not difference.is_empty(): problem = "The game and the website list different skills, so an entry's skills would mean different things in each. " + difference
	# The game's list is the one that counts. The website's stands in only if the game's can't be read.
	var usable : Dictionary = game if game[ "error" ].is_empty() else site
	_skill_names = usable[ "skills" ]
	if _form: _form.set_skill_names( _skill_names, usable[ "seed" ], problem )

#endregion

#region New, open and save

func is_dirty() -> bool:
	return _form.get_entry().to_dictionary() != _baseline

func request_new() -> void:
	_ask_if_dirty( "Start a new entry", start_new )

func request_open() -> void:
	if _open_dialog == null:
		_open_dialog = EditorFileDialog.new()
		_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_open_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_open_dialog.title = "Open an entry"
		_open_dialog.add_filter( "*.json", "Entry files" )
		_open_dialog.file_selected.connect( func(path: String) -> void: _ask_if_dirty( "Open " + path.get_file(), open_file.bind( path ) ) )
		add_child( _open_dialog, false, Node.INTERNAL_MODE_BACK )
	var folder := _form.get_folder()
	_open_dialog.current_dir = folder if DirAccess.dir_exists_absolute( folder ) else _settings.get_data_dir()
	_open_dialog.popup_file_dialog()

func request_save() -> void:
	var path := _form.get_file_path()
	if path.is_empty():
		_set_status( "Not saved: the folder or file name in the File box can't be used yet.", UiKit.LEVEL_ERROR )
		_form_scroll.ensure_control_visible( _form.get_box( EntryForm.FIELD_FILE ) )
		return
	# Replacing the file this entry came from is just saving. Replacing any other file gets asked about.
	if FileAccess.file_exists( path ) and not Settings.is_same_path( path, _loaded_path ):
		_ask( "Replace file", "%s already exists and holds a different entry.\n\nReplace it with this one?" % path.get_file(), "Replace", save_to.bind( path ) )
	else:
		save_to( path )

func start_new() -> void:
	# An untouched blank entry has nothing to lose, so it doesn't count as having changes.
	_baseline = EntryData.new().to_dictionary()
	_loaded_path = ""
	_form.set_entry( EntryData.new() )
	_form.set_file( _settings.get_data_dir(), "", true )
	_form.set_loaded_path( "" )
	_after_entry_replaced( "New entry." )

func open_file(path: String) -> void:
	path = Settings.clean_path( path )
	var loaded := EntryData.load_file( path, _skill_names )
	var entry : EntryData = loaded[ "entry" ]
	if entry == null:
		_set_status( loaded[ "error" ], UiKit.LEVEL_ERROR )
		_form.show_message( "That file couldn't be opened", loaded[ "error" ] )
		return
	_loaded_path = path
	_baseline = entry.to_dictionary()
	_form.set_entry( entry )
	_form.set_file( path.get_base_dir(), path.get_file(), false )
	_form.set_loaded_path( path )

	var notes : PackedStringArray = loaded[ "notes" ]
	if notes.is_empty():
		_after_entry_replaced( "Opened %s." % path.get_file() )
	else:
		# Whatever had to be patched up is spelled out, and the entry counts as changed, since saving it
		# now would write something different from what's in the file.
		_baseline = {}
		_after_entry_replaced( "Opened %s, with %d thing%s to know about (hover to read)." % [ path.get_file(), notes.size(), "" if notes.size() == 1 else "s" ], UiKit.LEVEL_NOTE )
		_status_label.tooltip_text = "\n".join( notes )
		_form.show_message( "Opened %s, with some things to know" % path.get_file(), "\n\n".join( notes ) )

func save_to(path: String) -> void:
	var entry := _form.get_entry()
	var problem := entry.save_file( path )
	if not problem.is_empty():
		_set_status( problem, UiKit.LEVEL_ERROR )
		_form.show_message( "The entry wasn't saved", problem )
		return
	_loaded_path = path
	_baseline = entry.to_dictionary()
	_form.set_loaded_path( path )

	var message := "Saved %s" % path.get_file()
	var level := UiKit.LEVEL_NONE
	if Settings.is_same_path( path.get_base_dir(), _settings.get_data_dir() ):
		var index := DataIndex.update( _settings.get_data_dir(), _settings.get_index_path() )
		var index_name := _settings.get_index_path().get_file()
		if not index[ "error" ].is_empty():
			message += ", but %s couldn't be updated: %s" % [ index_name, index[ "error" ] ]
			level = UiKit.LEVEL_ERROR
		elif index[ "changed" ]: message += " and updated %s." % index_name
		else: message += ". (%s already listed it.)" % index_name
	else:
		message += ". It's outside the entry folder, so %s wasn't touched." % _settings.get_index_path().get_file()
		level = UiKit.LEVEL_NOTE
	var errors := _form.count_problems( UiKit.LEVEL_ERROR )
	if errors > 0 and level == UiKit.LEVEL_NONE:
		message += " It still has %s." % UiKit.describe_counts( errors, 0 )
		level = UiKit.LEVEL_NOTE
	_update_file_label()
	_queue_session_save()
	_set_status( message, level )

func _after_entry_replaced(status: String, level: int = UiKit.LEVEL_NONE) -> void:
	_form_scroll.scroll_vertical = 0
	_update_file_label()
	_send_to_previews()
	_queue_session_save()
	_set_status( status, level )

func _on_form_changed() -> void:
	_preview_due = Time.get_ticks_msec() + PREVIEW_DELAY_MSEC
	_queue_session_save()
	_update_file_label()

#endregion

#region Status and questions

func _set_status(text: String, level: int = UiKit.LEVEL_NONE) -> void:
	_status_label.text = text
	_status_label.tooltip_text = text
	if level == UiKit.LEVEL_NONE: _status_label.remove_theme_color_override( &"font_color" )
	else: _status_label.add_theme_color_override( &"font_color", UiKit.get_level_color( level ) )

# The file's name on the toolbar, with a * while there are changes that aren't saved.
func _update_file_label() -> void:
	var file_name := _form.get_file_name()
	var shown := (file_name + EntryForm.FILE_ENDING) if not file_name.is_empty() else "(no file name yet)"
	_file_label.text = shown + (" *" if is_dirty() else "")
	_file_label.tooltip_text = (_loaded_path if not _loaded_path.is_empty() else "Not saved yet") + ("\nHas changes that aren't saved" if is_dirty() else "")

func _update_problem_summary() -> void:
	var errors := _form.count_problems( UiKit.LEVEL_ERROR )
	var notes := _form.count_problems( UiKit.LEVEL_NOTE )
	_problems_button.visible = errors + notes > 0
	_problems_button.text = UiKit.describe_counts( errors, notes )
	_problems_button.add_theme_color_override( &"font_color", UiKit.get_level_color( UiKit.LEVEL_ERROR if errors > 0 else UiKit.LEVEL_NOTE ) )
	var lines : PackedStringArray = []
	for problem in _form.problems: lines.append( problem[ "text" ] )
	_problems_button.tooltip_text = "\n".join( lines )

func _show_first_problem() -> void:
	var worst := {}
	for problem in _form.problems:
		if problem[ "level" ] > worst.get( "level", UiKit.LEVEL_NONE ): worst = problem
	if not worst.is_empty(): _form_scroll.ensure_control_visible( _form.get_box( worst[ "field" ] ) )

# Runs `action`, after asking first if the entry has changes that would be lost.
func _ask_if_dirty(what: String, action: Callable) -> void:
	if is_dirty(): _ask( what, "This entry has changes that haven't been saved. They'll be lost.", "Discard changes", action )
	else: action.call()

func _ask(title: String, text: String, confirm_text: String, action: Callable) -> void:
	if _confirm_dialog == null:
		_confirm_dialog = ConfirmationDialog.new()
		_confirm_dialog.dialog_autowrap = true
		_confirm_dialog.confirmed.connect( func() -> void:
			if _on_confirmed.is_valid(): _on_confirmed.call() )
		add_child( _confirm_dialog, false, Node.INTERNAL_MODE_BACK )
	_on_confirmed = action
	_confirm_dialog.title = title
	_confirm_dialog.dialog_text = text
	_confirm_dialog.ok_button_text = confirm_text
	_confirm_dialog.popup_centered( Vector2i( Vector2( 440, 0 ) * UiKit.get_scale() ) )

#endregion

#region Remembering the entry between sessions

func _queue_session_save() -> void:
	_session_due = Time.get_ticks_msec() + SESSION_DELAY_MSEC

func _save_session() -> void:
	var session := {
		"entry": _form.get_entry().to_dictionary(),
		"folder": _form.get_folder(),
		"file": _form.get_file_name(),
		"follows_name": _form.is_file_name_following_name(),
		"loaded_path": _loaded_path,
		"baseline": _baseline,
	}
	var file := FileAccess.open( _cache_dir.path_join( SESSION_FILE ), FileAccess.WRITE )
	if file: file.store_string( JSON.stringify( session ) )

# Picks up where the last editor session left off, unsaved changes included.
func _restore_session() -> void:
	var path := _cache_dir.path_join( SESSION_FILE )
	var session : Variant = JsonText.parse_quietly( FileAccess.get_file_as_string( path ) ) if FileAccess.file_exists( path ) else null
	if not session is Dictionary or not session.get( "entry" ) is Dictionary:
		start_new()
		_set_status( "" )
		return
	var ignored_notes : PackedStringArray = []
	var entry := EntryData.from_dictionary( session[ "entry" ], _skill_names, ignored_notes )
	_loaded_path = str( session.get( "loaded_path", "" ) )
	var baseline : Variant = session.get( "baseline" )
	# Run back through an entry so numbers come out as the same types the form's entry has.
	_baseline = EntryData.from_dictionary( baseline, _skill_names, ignored_notes ).to_dictionary() if baseline is Dictionary and not baseline.is_empty() else {}
	_form.set_entry( entry )
	_form.set_file( str( session.get( "folder", _settings.get_data_dir() ) ), str( session.get( "file", "" ) ), bool( session.get( "follows_name", false ) ) )
	_form.set_loaded_path( _loaded_path )
	_set_status( "Picked up where you left off%s." % (", with changes that aren't saved yet" if is_dirty() else "") )

#endregion
