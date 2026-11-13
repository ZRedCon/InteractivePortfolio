@tool
extends EditorPlugin

# Adds an "Exhibits" screen to the top of the editor, next to 2D, 3D and Script, for making and
# editing the portfolio's entry files (Webfiles/assets/data/*.json) with live previews of how each
# entry will look on the website and in the game.
#
# Everything on the screen is built by ui/main_screen.gd. This script only puts it in the editor
# and tells it when the project changes.

const MainScreen := preload( "ui/main_screen.gd" )

# Changes inside this folder are the plugin's own files, not the game's.
const OWN_FOLDER := "res://addons/exhibit_editor/"

var _screen : MainScreen

func _enter_tree() -> void:
	_screen = MainScreen.new()
	EditorInterface.get_editor_main_screen().add_child( _screen )
	_screen.set_shown( false )
	# The previews run the game's real scenes and scripts, so they start over when one is saved here,
	# or changed by another program (the editor notices those when its window gets focus back).
	resource_saved.connect( _on_resource_saved )
	scene_saved.connect( _on_path_saved )
	EditorInterface.get_resource_filesystem().filesystem_changed.connect( _screen.notify_project_changed )

func _exit_tree() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect( _screen.notify_project_changed )
	_screen.shut_down()
	_screen.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if _screen: _screen.set_shown( visible )

func _get_plugin_name() -> String:
	return "Exhibits"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon( &"ImageTexture", &"EditorIcons" )

func _on_resource_saved(resource: Resource) -> void:
	_on_path_saved( resource.resource_path )

func _on_path_saved(path: String) -> void:
	if not path.begins_with( OWN_FOLDER ): _screen.notify_project_changed()
