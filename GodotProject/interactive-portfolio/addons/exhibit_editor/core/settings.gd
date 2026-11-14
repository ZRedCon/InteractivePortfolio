@tool
extends RefCounted

# Every path and name the Exhibit Editor depends on, in one place, so that when a file moves or a
# function is renamed there's a setting to change instead of code. The Settings tab edits these.
#
# Values that differ from the defaults are saved in settings.cfg next to the plugin, so they travel
# with the project. The one exception is the browser's location, which belongs to this computer and
# is kept in the editor's own per-project notes instead.

signal changed(key: String)

const JsonText := preload( "json_text.gd" )
const DateText := preload( "date_text.gd" )

const FILE_PATH := "res://addons/exhibit_editor/settings.cfg"
const SECTION := "exhibit_editor"

# What kind of value a setting holds, which decides how the Settings tab lets you pick one.
const KIND_TEXT := 0
const KIND_PROJECT_DIR := 1		# a folder, written relative to the Godot project folder
const KIND_SITE_DIR := 2		# a folder inside the website folder
const KIND_SITE_FILE := 3		# a file inside the website folder
const KIND_IMAGE := 4			# an image name, the way entries store them
const KIND_RES_FILE := 5		# a res:// file
const KIND_PROGRAM := 6			# a program on this computer

const WEBFILES_DIR := "webfiles_dir"
const DATA_DIR := "data_dir"
const INDEX_FILE := "index_file"
const IMAGES_DIR := "images_dir"
const IMAGE_EXTENSION := "image_extension"
const FALLBACK_IMAGE := "fallback_image"
const SITE_PAGE := "site_page"
const EXHIBIT_SELECTOR := "exhibit_selector"
const BLANK_FOLDERS := "blank_folders"
const SITE_SKILLS := "site_skills_script"
const BROWSER_PATH := "browser_path"
const UI_SCENE := "ui_scene"
const UI_METHOD := "ui_method"
const ENTRY_SCENE := "entry_scene"
const ENTRY_METHOD := "entry_method"
const PARSER_SCRIPT := "parser_script"
const PARSER_METHOD := "parser_method"
const GAME_SKILLS := "game_skills_script"
const DATE_FORMAT := "date_format"
const MONTH_FORMAT := "month_format"
const YEAR_FORMAT := "year_format"

const GROUP_FILES := "Website files"
const GROUP_SITE := "Website previews"
const GROUP_GAME := "Godot previews"
const GROUP_EDITING := "Editing"

const DEFINITIONS : Array[ Dictionary ] = [
	{ "key": WEBFILES_DIR, "group": GROUP_FILES, "label": "Website folder", "default": "../../Webfiles", "kind": KIND_PROJECT_DIR,
		"help": "The folder that holds index.html. Written from the Godot project's folder, so it still works on another computer." },
	{ "key": DATA_DIR, "group": GROUP_FILES, "label": "Entry folder", "default": "assets/data", "kind": KIND_SITE_DIR,
		"help": "Where the entry .json files live, inside the website folder. New entries are saved here unless you pick another folder." },
	{ "key": INDEX_FILE, "group": GROUP_FILES, "label": "Entry index file", "default": "assets/data-index.json", "kind": KIND_SITE_FILE,
		"help": "The list of entry files the website and the web build download. It's rewritten whenever an entry is saved into the entry folder." },
	{ "key": IMAGES_DIR, "group": GROUP_FILES, "label": "Images folder", "default": "assets/images", "kind": KIND_SITE_DIR,
		"help": "Entries store image names relative to this folder." },
	{ "key": IMAGE_EXTENSION, "group": GROUP_FILES, "label": "Image file ending", "default": ".png", "kind": KIND_TEXT,
		"help": "Added to every image name by the website and the game, so it's left out of the names entries store." },
	{ "key": FALLBACK_IMAGE, "group": GROUP_FILES, "label": "Stand-in image", "default": "Debug/Debug1/pair1", "kind": KIND_IMAGE,
		"help": "Shown in this editor in place of an image that's missing or won't load." },

	{ "key": SITE_PAGE, "group": GROUP_SITE, "label": "Page to preview", "default": "index.html", "kind": KIND_SITE_FILE,
		"help": "The website previews open this page for real, with the entry being edited as its only entry. Whatever scripts and stylesheets the page loads are used as they are." },
	{ "key": EXHIBIT_SELECTOR, "group": GROUP_SITE, "label": "Exhibit CSS selector", "default": ".exhibit", "kind": KIND_TEXT,
		"help": "Which element on that page is the exhibit. The preview shows just this element." },
	{ "key": BLANK_FOLDERS, "group": GROUP_SITE, "label": "Folders to leave out", "default": "godot", "kind": KIND_TEXT,
		"help": "Folders inside the website folder that the preview answers with an empty page, separated by commas. Keeps the preview from loading the whole Godot web build." },
	{ "key": SITE_SKILLS, "group": GROUP_SITE, "label": "Website skill list", "default": "src/entryToExhibit.js", "kind": KIND_SITE_FILE,
		"help": "The script whose SKILLS = [ ... ] list the website uses. Checked against the game's list." },
	{ "key": BROWSER_PATH, "group": GROUP_SITE, "label": "Browser", "default": "", "kind": KIND_PROGRAM, "per_computer": true,
		"help": "Chrome or Edge, run without a window to draw the website previews. Leave empty to find one automatically. (This one is remembered for this computer only.)" },

	{ "key": UI_SCENE, "group": GROUP_GAME, "label": "Exhibit UI scene", "default": "res://prefabs/ui_exhibit.tscn", "kind": KIND_RES_FILE,
		"help": "The scene the game shows an entry's full details in." },
	{ "key": UI_METHOD, "group": GROUP_GAME, "label": "Its fill function", "default": "set_values_from_entry", "kind": KIND_TEXT,
		"help": "The function on that scene's root that takes an Entry and fills the scene in." },
	{ "key": ENTRY_SCENE, "group": GROUP_GAME, "label": "3D exhibit scene", "default": "res://prefabs/Entry.tscn", "kind": KIND_RES_FILE,
		"help": "The scene that stands in the museum for an entry." },
	{ "key": ENTRY_METHOD, "group": GROUP_GAME, "label": "Its fill function", "default": "set_entry", "kind": KIND_TEXT,
		"help": "The function on that scene's root that takes an Entry and fills the scene in." },
	{ "key": PARSER_SCRIPT, "group": GROUP_GAME, "label": "Entry parser script", "default": "res://file_parser.gd", "kind": KIND_RES_FILE,
		"help": "The autoload script that turns entry files into Entry objects. The previews find the autoload by this script." },
	{ "key": PARSER_METHOD, "group": GROUP_GAME, "label": "Its entry function", "default": "_make_entry_from_dict", "kind": KIND_TEXT,
		"help": "The function on that autoload that takes one parsed entry file (a Dictionary) and returns the Entry." },
	{ "key": GAME_SKILLS, "group": GROUP_GAME, "label": "Game skill list", "default": "res://game_entry.gd", "kind": KIND_RES_FILE,
		"help": "The script whose SKILLS = [ ... ] list the game uses. The Skills field offers these." },

	{ "key": DATE_FORMAT, "group": GROUP_EDITING, "label": "Calendar: full date", "default": "M/D/YYYY", "kind": KIND_TEXT,
		"help": "How the calendar writes a whole date (its Full date bullet). D DD = day, M MM = month number, MMM MMMM = month name, YY YYYY = year. Dates typed by hand are kept as they're typed." },
	{ "key": MONTH_FORMAT, "group": GROUP_EDITING, "label": "Calendar: month", "default": "M/YYYY", "kind": KIND_TEXT,
		"help": "How the calendar writes a date that's only a month (its Month bullet). The year has four digits by default, because 11/26 would read as November 26th." },
	{ "key": YEAR_FORMAT, "group": GROUP_EDITING, "label": "Calendar: year", "default": "YYYY", "kind": KIND_TEXT,
		"help": "How the calendar writes a date that's only a year (its Year bullet)." },
]

const BROWSER_CANDIDATES : Array[ String ] = [
	"C:/Program Files/Google/Chrome/Application/chrome.exe",
	"C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
	"C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
	"C:/Program Files/Microsoft/Edge/Application/msedge.exe",
	"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
	"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
	"/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser", "/usr/bin/microsoft-edge",
]

var _values : Dictionary[ String, String ] # Only the settings that differ from their default
var _definitions : Dictionary[ String, Dictionary ]

func _init() -> void:
	for definition in DEFINITIONS: _definitions[ definition[ "key" ] ] = definition

#region Reading and changing

func get_value(key: String) -> String:
	return _values.get( key, _definitions[ key ][ "default" ] )

func get_default(key: String) -> String:
	return _definitions[ key ][ "default" ]

func get_definition(key: String) -> Dictionary:
	return _definitions[ key ]

func is_default(key: String) -> bool:
	return not _values.has( key )

func set_value(key: String, value: String) -> void:
	value = value.strip_edges()
	if value == get_value( key ): return
	if value == get_default( key ): _values.erase( key )
	else: _values[ key ] = value
	save()
	changed.emit( key )

func reset_all() -> void:
	var keys := _values.keys()
	_values.clear()
	save()
	for key : String in keys: changed.emit( key )

func load_saved() -> void:
	_values.clear()
	var file := ConfigFile.new()
	var has_file := file.load( FILE_PATH ) == OK
	for definition in DEFINITIONS:
		var key : String = definition[ "key" ]
		var value : Variant = null
		if definition.get( "per_computer", false ):
			if Engine.is_editor_hint(): value = EditorInterface.get_editor_settings().get_project_metadata( SECTION, key, "" )
		elif has_file:
			value = file.get_value( SECTION, key, null )
		if value is String and value != definition[ "default" ]: _values[ key ] = value

func save() -> void:
	var file := ConfigFile.new()
	for definition in DEFINITIONS:
		var key : String = definition[ "key" ]
		if definition.get( "per_computer", false ):
			if Engine.is_editor_hint(): EditorInterface.get_editor_settings().set_project_metadata( SECTION, key, _values.get( key, "" ) )
		elif _values.has( key ):
			file.set_value( SECTION, key, _values[ key ] )
	# With everything back on its default there's nothing to keep, so the file goes too.
	if file.has_section( SECTION ): file.save( FILE_PATH )
	elif FileAccess.file_exists( FILE_PATH ): DirAccess.remove_absolute( ProjectSettings.globalize_path( FILE_PATH ) )

#endregion

#region Paths worked out from the settings

func get_project_dir() -> String:
	return clean_path( ProjectSettings.globalize_path( "res://" ) )

func get_webfiles_dir() -> String:
	return to_absolute( get_value( WEBFILES_DIR ), get_project_dir() )

func get_data_dir() -> String:
	return to_absolute( get_value( DATA_DIR ), get_webfiles_dir() )

func get_index_path() -> String:
	return to_absolute( get_value( INDEX_FILE ), get_webfiles_dir() )

func get_images_dir() -> String:
	return to_absolute( get_value( IMAGES_DIR ), get_webfiles_dir() )

func get_site_page_path() -> String:
	return to_absolute( get_value( SITE_PAGE ), get_webfiles_dir() )

func get_site_skills_path() -> String:
	return to_absolute( get_value( SITE_SKILLS ), get_webfiles_dir() )

# A path written for a person to read. Inside the website folder it starts at that folder's name
# ("Webfiles/assets/images/x.png"), which is a lot shorter than the whole thing and just as clear.
func describe_path(path: String) -> String:
	var site := get_webfiles_dir()
	path = clean_path( path )
	if path.to_lower().begins_with( site.to_lower() + "/" ): return site.get_file().path_join( to_relative( path, site ) )
	return path

# Where on disk the image an entry calls `image_name` is.
func get_image_path(image_name: String) -> String:
	return get_images_dir().path_join( image_name + get_value( IMAGE_EXTENSION ) )

# The address the website asks for that same image at, like "/assets/images/Debug/pair0.png".
func get_image_url_path(image_name: String) -> String:
	return "/" + clean_path( get_value( IMAGES_DIR ) ).path_join( image_name + get_value( IMAGE_EXTENSION ) )

# Turns a file picked on disk into the name an entry stores: no images folder in front, no ".png" behind.
# { "name": String, "error": String }
func get_image_name(file_path: String) -> Dictionary:
	var path := clean_path( file_path )
	var folder := get_images_dir() + "/"
	if not path.to_lower().begins_with( folder.to_lower() ):
		return { "name": "", "error": "That file isn't inside the images folder (%s), so the website and the game couldn't find it." % describe_path( get_images_dir() ) }
	var extension := get_value( IMAGE_EXTENSION )
	if not path.to_lower().ends_with( extension.to_lower() ):
		return { "name": "", "error": "Images have to be %s files." % extension }
	return { "name": path.substr( folder.length(), path.length() - folder.length() - extension.length() ), "error": "" }

# The folders the preview's web server answers with an empty page, as URL paths: [ "/godot/" ]
func get_blank_folders() -> PackedStringArray:
	var folders : PackedStringArray = []
	for folder in get_value( BLANK_FOLDERS ).split( ",", false ):
		folder = clean_path( folder.strip_edges() ).trim_prefix( "/" ).trim_suffix( "/" )
		if not folder.is_empty(): folders.append( "/" + folder + "/" )
	return folders

# The chosen browser, or the first one found in the usual places. "" when there's none.
func find_browser() -> String:
	var chosen := get_value( BROWSER_PATH )
	if not chosen.is_empty(): return clean_path( chosen ) if FileAccess.file_exists( chosen ) else ""
	for candidate in BROWSER_CANDIDATES:
		if FileAccess.file_exists( candidate ): return candidate
	return ""

#endregion

#region Checking

# "" when the setting's value can be used, otherwise what's wrong with it.
func find_problem(key: String) -> String:
	var value := get_value( key )
	match key:
		WEBFILES_DIR:
			if not DirAccess.dir_exists_absolute( get_webfiles_dir() ): return "Folder not found: " + get_webfiles_dir()
		DATA_DIR:
			if not DirAccess.dir_exists_absolute( get_data_dir() ): return "Folder not found: " + describe_path( get_data_dir() )
		IMAGES_DIR:
			if not DirAccess.dir_exists_absolute( get_images_dir() ): return "Folder not found: " + describe_path( get_images_dir() )
		INDEX_FILE:
			var path := get_index_path()
			if not DirAccess.dir_exists_absolute( path.get_base_dir() ): return "Folder not found: " + describe_path( path.get_base_dir() )
			if not FileAccess.file_exists( path ): return "%s doesn't exist yet. Saving an entry into the entry folder makes it." % path.get_file()
			var listed : Variant = JsonText.parse_quietly( FileAccess.get_file_as_string( path ) )
			if not listed is Array: return "%s exists but isn't a list of file names. Saving an entry will replace it." % path.get_file()
			# The website only loads what's listed, so a file missing from the list is an entry missing from the site.
			if DirAccess.dir_exists_absolute( get_data_dir() ) and listed != Array( DirAccess.get_files_at( get_data_dir() ) ):
				return "%s doesn't match what's in the entry folder (a file was added or removed outside this editor). Saving any entry here puts it right." % path.get_file()
		IMAGE_EXTENSION:
			if not value.begins_with( "." ) or value.length() < 2: return "Should start with a dot, like .png"
		FALLBACK_IMAGE:
			var path := get_image_path( value )
			if not FileAccess.file_exists( path ): return "File not found: " + describe_path( path )
			if Image.load_from_file( path ) == null: return "Can't read this as an image: " + describe_path( path )
		SITE_PAGE:
			if not FileAccess.file_exists( get_site_page_path() ): return "File not found: " + describe_path( get_site_page_path() )
		EXHIBIT_SELECTOR:
			if value.is_empty(): return "The previews need to know which element is the exhibit."
		BLANK_FOLDERS:
			for folder in get_blank_folders():
				if not DirAccess.dir_exists_absolute( get_webfiles_dir() + folder ): return "Folder not found: " + describe_path( get_webfiles_dir() + folder )
		SITE_SKILLS:
			if not FileAccess.file_exists( get_site_skills_path() ): return "File not found: " + describe_path( get_site_skills_path() )
		BROWSER_PATH:
			if not value.is_empty() and not FileAccess.file_exists( value ): return "File not found: " + value
			if find_browser().is_empty(): return "No Chrome or Edge found. Pick the browser's .exe to get website previews."
		UI_SCENE, ENTRY_SCENE:
			if not ResourceLoader.exists( value, "PackedScene" ): return "Scene not found: " + value
		UI_METHOD:
			return _find_scene_method_problem( get_value( UI_SCENE ), value )
		ENTRY_METHOD:
			return _find_scene_method_problem( get_value( ENTRY_SCENE ), value )
		PARSER_SCRIPT, GAME_SKILLS:
			if not ResourceLoader.exists( value, "Script" ): return "Script not found: " + value
		PARSER_METHOD:
			return _find_script_method_problem( get_value( PARSER_SCRIPT ), value )
		DATE_FORMAT:
			return _find_format_problem( value, "DMY", "a day, a month and a year" )
		MONTH_FORMAT:
			return _find_format_problem( value, "MY", "a month and a year, and no day" )
		YEAR_FORMAT:
			return _find_format_problem( value, "Y", "only a year" )
	return ""

# Which settings can't be used right now: { key: what's wrong }
func find_problems() -> Dictionary[ String, String ]:
	var problems : Dictionary[ String, String ] = {}
	for definition in DEFINITIONS:
		var problem := find_problem( definition[ "key" ] )
		if not problem.is_empty(): problems[ definition[ "key" ] ] = problem
	return problems

# "" when a calendar format writes exactly the parts it should (`wanted`, like "MY"; see DateText.get_parts).
static func _find_format_problem(format: String, wanted: String, described: String) -> String:
	if DateText.get_parts( format ) == wanted: return ""
	return "Should write %s. (D DD = day, M MM MMM MMMM = month, YY YYYY = year.)" % described

static func _find_scene_method_problem(scene_path: String, method: String) -> String:
	if method.is_empty(): return "The previews need a function to call."
	if not ResourceLoader.exists( scene_path, "PackedScene" ): return "" # Reported on the scene's own setting
	var scene := ResourceLoader.load( scene_path ) as PackedScene
	if scene == null: return ""
	# The root is node 0. Its script is one of its saved properties.
	var state := scene.get_state()
	for i in state.get_node_property_count( 0 ):
		if state.get_node_property_name( 0, i ) != &"script": continue
		var script := state.get_node_property_value( 0, i ) as Script
		if script and _has_method( script, method ): return ""
		return "%s's root script has no function called %s." % [ scene_path.get_file(), method ]
	return "%s's root has no script, so there's no %s to call." % [ scene_path.get_file(), method ]

static func _find_script_method_problem(script_path: String, method: String) -> String:
	if method.is_empty(): return "The previews need a function to call."
	if not ResourceLoader.exists( script_path, "Script" ): return ""
	var script := ResourceLoader.load( script_path ) as Script
	if script == null or _has_method( script, method ): return ""
	return "%s has no function called %s." % [ script_path.get_file(), method ]

static func _has_method(script: Script, method: String) -> bool:
	while script:
		for info in script.get_script_method_list():
			if info[ "name" ] == method: return true
		script = script.get_base_script()
	return false

#endregion

#region Path helpers

# Forward slashes, no "..", no trailing slash: one spelling per place, so paths can be compared.
static func clean_path(path: String) -> String:
	return path.replace( "\\", "/" ).simplify_path().trim_suffix( "/" )

static func to_absolute(path: String, base_dir: String) -> String:
	path = path.replace( "\\", "/" )
	return clean_path( path if path.is_absolute_path() else base_dir.path_join( path ) )

# How to get to `path` starting from `base_dir`, like "../../Webfiles". If they're on different drives
# there's no such route, and the full path comes back unchanged.
static func to_relative(path: String, base_dir: String) -> String:
	var target := clean_path( path ).split( "/" )
	var base := clean_path( base_dir ).split( "/" )
	if target.is_empty() or base.is_empty() or target[ 0 ].to_lower() != base[ 0 ].to_lower(): return clean_path( path )
	var shared := 0
	while shared < target.size() and shared < base.size() and target[ shared ].to_lower() == base[ shared ].to_lower(): shared += 1
	var steps : PackedStringArray = []
	for i in base.size() - shared: steps.append( ".." )
	steps.append_array( target.slice( shared ) )
	return "/".join( steps ) if not steps.is_empty() else "."

# Whether two paths name the same place. Windows doesn't tell capital letters apart in file names.
static func is_same_path(a: String, b: String) -> bool:
	return clean_path( a ).to_lower() == clean_path( b ).to_lower()

#endregion
