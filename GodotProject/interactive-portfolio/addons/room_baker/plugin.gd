@tool
extends EditorPlugin

# Adds Project > Tools > Bake Room Lighting (see room_baker.gd for what it does)

const RoomBaker := preload( "res://addons/room_baker/room_baker.gd" )
const MENU_ITEM := "Bake Room Lighting"

var _baking := false

func _enter_tree() -> void:
	add_tool_menu_item( MENU_ITEM, _bake )

func _exit_tree() -> void:
	remove_tool_menu_item( MENU_ITEM )

func _bake() -> void:
	if _baking: return
	_baking = true
	await RoomBaker.new().bake_all()
	_baking = false
