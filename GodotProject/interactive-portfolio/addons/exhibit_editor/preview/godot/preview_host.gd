extends Node

# The preview helper: a second, windowless run of this project that the Exhibit Editor starts
# (see godot_preview.gd). It exists so the game's own scenes and scripts can show an entry without
# any of that code running inside the editor:
#
#   1. it instantiates the real exhibit scenes, with the project's autoloads running as in the game
#   2. it turns the entry the editor sends into an Entry with the game's own parser, and hands it
#      to each scene's own fill function
#   3. it sends back what the scenes look like afterwards, as plain data (scene_snapshot.gd)
#
# Whatever goes wrong in the game's code happens here: the errors are caught and sent to the editor
# to show, and even a crash only ends this helper.

const Protocol := preload( "preview_protocol.gd" )
const Snapshot := preload( "scene_snapshot.gd" )
const MessageStream := preload( "message_stream.gd" )
const ErrorCatcher := preload( "error_catcher.gd" )

const ACTIVE_FPS : int = 30
const IDLE_FPS : int = 5
const CONNECT_TIMEOUT_MSEC : int = 10000
const ALIVE_EVERY_MSEC : int = 1000
# A new scene gets this many frames to finish its own _ready work before the entry goes in.
# (ExhibitUI's _ready fills in test values, and part of that waits a frame.)
const SETTLE_FRAMES : int = 3
# After an entry goes in, the result is held back this long, so the half-built frames in between aren't shown.
const HOLD_FRAMES : int = 3
# How often to look up again which properties each node stores (see Snapshot.forget_property_lists).
const PROPERTY_REFRESH_FRAMES : int = 30
# Looking a whole scene over takes a few milliseconds, so it's only done every frame while the scene is
# moving. After this many frames of nothing changing it drops to every few frames, until something does.
const QUIET_AFTER_FRAMES : int = 20
const QUIET_LOOK_EVERY : int = 6

class Pane:
	var id : String
	var scene_path : String
	var method : String
	var viewport : SubViewport
	var instance : Node
	var snapshot : Snapshot
	var needs_instance : bool = true
	var frames_alive : int
	var applied_rev : int = -1
	var last_state : PackedByteArray
	var frames_unchanged : int

var _stream : MessageStream
var _catcher := ErrorCatcher.new()
var _started_at : int
var _said_hello : bool
var _token : String
var _last_alive : int
var _active : bool = true
var _frame : int

var _panes : Dictionary[ String, Pane ]
var _parser_script : String
var _parser_method : String
var _entry_rev : int
var _entry_json : String
var _entry : Variant # What the game's parser made of _entry_json, or null if it couldn't
var _entry_built_rev : int = -1

# The pane whose scene is being filled right now, and how long ago that started. Only one at a time,
# so an error can be pinned on the scene that caused it.
var _busy_pane : String
var _busy_frames : int

func _ready() -> void:
	OS.add_logger( _catcher )
	Engine.max_fps = ACTIVE_FPS
	_started_at = Time.get_ticks_msec()

	var port := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with( Protocol.ARG_PORT ): port = argument.trim_prefix( Protocol.ARG_PORT ).to_int()
		elif argument.begins_with( Protocol.ARG_TOKEN ): _token = argument.trim_prefix( Protocol.ARG_TOKEN )
	if port <= 0:
		# Started by hand, with no editor to talk to.
		print( "This scene is the Exhibit Editor's preview helper. The editor starts it by itself." )
		get_tree().quit()
		return
	var peer := StreamPeerTCP.new()
	peer.connect_to_host( "127.0.0.1", port )
	_stream = MessageStream.new( peer )

func _exit_tree() -> void:
	OS.remove_logger( _catcher )

func _process(_delta: float) -> void:
	if _stream == null: return
	_frame += 1
	if not _stream.is_open():
		# The editor closed, or never answered. Either way there's nobody to preview for.
		if _said_hello or not _stream.is_connecting() or Time.get_ticks_msec() - _started_at > CONNECT_TIMEOUT_MSEC: get_tree().quit()
		return
	if not _said_hello:
		_said_hello = true
		_stream.send( { Protocol.TYPE: Protocol.HELLO, "token": _token, "pid": OS.get_process_id() } )

	for message in _stream.receive(): _handle( message )
	_send_reports()

	var now := Time.get_ticks_msec()
	if now - _last_alive > ALIVE_EVERY_MSEC:
		_last_alive = now
		_stream.send( { Protocol.TYPE: Protocol.ALIVE } )

	if not _busy_pane.is_empty():
		_busy_frames += 1
		if _busy_frames > HOLD_FRAMES: _busy_pane = ""
	for pane : Pane in _panes.values(): _advance( pane )

#region Messages from the editor

func _handle(message: Dictionary) -> void:
	match message.get( Protocol.TYPE, "" ):
		Protocol.SETUP:
			_parser_script = message.get( "parser_script", "" )
			_parser_method = message.get( "parser_method", "" )
			_entry_built_rev = -1
		Protocol.PANE:
			_set_pane( message )
		Protocol.ENTRY:
			_entry_rev = message.get( "rev", 0 )
			_entry_json = message.get( "json", "" )
		Protocol.ACTIVE:
			_active = message.get( "on", true )
			Engine.max_fps = ACTIVE_FPS if _active else IDLE_FPS
		Protocol.INPUT:
			_push_input( message )
		Protocol.QUIT:
			get_tree().quit()

func _set_pane(message: Dictionary) -> void:
	var id : String = message.get( "id", "" )
	var pane : Pane = _panes.get( id )
	if pane == null:
		pane = Pane.new()
		pane.id = id
		pane.snapshot = Snapshot.new()
		pane.viewport = SubViewport.new()
		pane.viewport.name = "Pane_" + id
		# Its own 3D world, so a 3D exhibit doesn't share lights or physics with the other pane.
		pane.viewport.own_world_3d = true
		add_child( pane.viewport )
		_panes[ id ] = pane

	var size : Vector2i = message.get( "size", pane.viewport.size )
	var scene_path : String = message.get( "scene", "" )
	# A different size starts over with a fresh scene, because that's what the game would do: scenes read
	# their size once when they're made (ContentAdjuster picks thin or wide that way).
	if size != pane.viewport.size or scene_path != pane.scene_path or message.get( "restart", false ): pane.needs_instance = true
	pane.viewport.size = size
	pane.scene_path = scene_path
	if pane.method != message.get( "method", "" ):
		pane.method = message.get( "method", "" )
		pane.applied_rev = -1

func _push_input(message: Dictionary) -> void:
	var pane : Pane = _panes.get( message.get( "pane", "" ) )
	if pane == null: return
	var event : InputEventMouse
	if message.get( "moved", false ):
		var motion := InputEventMouseMotion.new()
		motion.relative = message.get( "relative", Vector2.ZERO )
		event = motion
	else:
		var button := InputEventMouseButton.new()
		button.button_index = message.get( "button", MOUSE_BUTTON_LEFT )
		button.pressed = message.get( "pressed", false )
		event = button
	event.position = message.get( "position", Vector2.ZERO )
	event.global_position = event.position
	event.button_mask = message.get( "buttons", 0 )
	pane.viewport.push_input( event, true )
	pane.frames_unchanged = 0 # Whatever the click did should show at once

#endregion

#region Showing the entry

func _advance(pane: Pane) -> void:
	if pane.needs_instance:
		_instantiate( pane )
		return
	pane.frames_alive += 1
	if pane.instance == null or pane.frames_alive < SETTLE_FRAMES: return

	if pane.applied_rev != _entry_rev and _entry_rev > 0:
		# One scene at a time, and never while the last entry is still settling into this one.
		if not _busy_pane.is_empty(): return
		_apply( pane )
		return
	if _busy_pane == pane.id or not _active: return

	pane.frames_unchanged += 1
	if pane.frames_unchanged > QUIET_AFTER_FRAMES and _frame % QUIET_LOOK_EVERY != 0: return
	if _frame % PROPERTY_REFRESH_FRAMES == 0: pane.snapshot.forget_property_lists()
	var state := var_to_bytes( pane.snapshot.take( pane.instance ) )
	if state == pane.last_state: return
	pane.last_state = state
	pane.frames_unchanged = 0
	_send_new_textures( pane )
	_stream.send( { Protocol.TYPE: Protocol.STATE, "pane": pane.id, "rev": pane.applied_rev, "data": state } )

func _instantiate(pane: Pane) -> void:
	pane.needs_instance = false
	pane.frames_alive = 0
	pane.applied_rev = -1
	pane.snapshot.forget_property_lists()
	if pane.instance:
		pane.viewport.remove_child( pane.instance )
		pane.instance.queue_free()
		pane.instance = null

	var scene : PackedScene = null
	if ResourceLoader.exists( pane.scene_path, "PackedScene" ): scene = load( pane.scene_path ) as PackedScene
	if scene: pane.instance = scene.instantiate()
	if pane.instance:
		pane.viewport.add_child( pane.instance )
	else:
		_report( pane.id, ErrorCatcher.KIND_ERROR, "Couldn't open the scene %s. (It's set in the Exhibit Editor's Settings tab.)" % pane.scene_path, "" )
		# An empty snapshot clears whatever the editor was still showing.
		pane.last_state = PackedByteArray()
		_stream.send( { Protocol.TYPE: Protocol.STATE, "pane": pane.id, "rev": _entry_rev, "data": var_to_bytes( { "tree": {} } ) } )

func _apply(pane: Pane) -> void:
	pane.applied_rev = _entry_rev
	# The editor counts the pane as up to date when it gets a state for this entry, so one is sent even if
	# the scene comes out exactly as before (a change it doesn't show, or a fill function that stops early).
	pane.last_state = PackedByteArray()
	_send_reports() # Anything caught before now isn't this scene's doing
	_busy_pane = pane.id
	_busy_frames = 0

	var entry : Variant = _get_entry()
	if entry == null: return
	if not pane.instance.has_method( pane.method ):
		_report( pane.id, ErrorCatcher.KIND_ERROR, "%s's root has no function called %s. (It's set in the Exhibit Editor's Settings tab.)" % [ pane.scene_path.get_file(), pane.method ], "" )
		return
	pane.instance.call( pane.method, entry )
	pane.snapshot.forget_property_lists()
	pane.frames_unchanged = 0

# The Entry for the current text, made by the game's own parser so it's exactly what the game would get.
func _get_entry() -> Variant:
	if _entry_built_rev == _entry_rev: return _entry
	_entry_built_rev = _entry_rev
	_entry = null

	var parser := _find_parser()
	if parser == null:
		_report( _busy_pane, ErrorCatcher.KIND_ERROR, "No autoload uses the script %s, so there's nothing to make an Entry with. (It's set in the Exhibit Editor's Settings tab.)" % _parser_script, "" )
		return null
	if not parser.has_method( _parser_method ):
		_report( _busy_pane, ErrorCatcher.KIND_ERROR, "%s has no function called %s. (It's set in the Exhibit Editor's Settings tab.)" % [ _parser_script.get_file(), _parser_method ], "" )
		return null
	# Read the same way file_parser.gd reads a file, so numbers and lists arrive as the same types.
	var data : Variant = JSON.parse_string( _entry_json )
	if not data is Dictionary:
		_report( _busy_pane, ErrorCatcher.KIND_ERROR, "The entry couldn't be read as JSON.", "" )
		return null
	_entry = parser.call( _parser_method, data )
	if _entry == null: _report( _busy_pane, ErrorCatcher.KIND_ERROR, "%s() didn't return an Entry." % _parser_method, "" )
	return _entry

# Autoloads are the root's children. The parser is found by its script, so its autoload name doesn't matter.
func _find_parser() -> Node:
	for node in get_tree().root.get_children():
		var script := node.get_script() as Script
		while script:
			if script.resource_path == _parser_script: return node
			script = script.get_base_script()
	return null

func _send_new_textures(pane: Pane) -> void:
	for texture : ImageTexture in pane.snapshot.take_new_textures():
		var image := texture.get_image()
		if image == null or image.is_empty(): continue
		var pixels := image.get_data()
		_stream.send( {
			Protocol.TYPE: Protocol.TEXTURE, "id": texture.get_instance_id(),
			"width": image.get_width(), "height": image.get_height(), "format": image.get_format(), "mipmaps": image.has_mipmaps(),
			"size": pixels.size(), "data": pixels.compress( FileAccess.COMPRESSION_ZSTD ),
		} )

#endregion

#region Errors

func _send_reports() -> void:
	for caught in _catcher.take(): _report( _busy_pane, caught[ "kind" ], caught[ "text" ], caught[ "where" ] )

func _report(pane_id: String, kind: String, text: String, where: String) -> void:
	# Says which version of the entry it was about, so the editor can tell a late report about an old
	# version from one about what's showing now.
	var pane : Pane = _panes.get( pane_id )
	_stream.send( { Protocol.TYPE: Protocol.REPORT, "pane": pane_id, "rev": pane.applied_rev if pane else _entry_rev, "kind": kind, "text": text, "where": where } )

#endregion
