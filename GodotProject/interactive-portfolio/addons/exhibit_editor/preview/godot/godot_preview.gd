@tool
extends Node

# Runs the Godot previews: starts the preview helper (a windowless second copy of the game, see
# preview_host.gd), sends it the entry being edited, and keeps a PreviewStage per scene showing
# what the helper sends back.
#
# Nothing from the game runs in the editor. If the game's scripts hit an error, hang or crash, that
# happens in the helper: the error text is shown beside the preview and the helper can be restarted.

signal changed # The status line, or what there is to report, is different now

const Settings := preload( "../../core/settings.gd" )
const Protocol := preload( "preview_protocol.gd" )
const MessageStream := preload( "message_stream.gd" )
const Stage := preload( "preview_stage.gd" )

const HOST_SCENE := "res://addons/exhibit_editor/preview/godot/preview_host.tscn"
const PANE_UI := "ui"
const PANE_ENTRY := "entry"
const PANE_IDS : Array[ String ] = [ PANE_UI, PANE_ENTRY ]

const STOPPED := 0
const STARTING := 1
const RUNNING := 2
const FAILED := 3

const START_TIMEOUT_MSEC : int = 20000
# The helper says it's alive every second. This long without a word means its scripts are stuck.
const SILENCE_TIMEOUT_MSEC : int = 8000
# Saving a scene often saves several files in a row, so a restart waits for them all.
const RESTART_DELAY_MSEC : int = 700
const MAX_REPORTS : int = 12
const LOG_TAIL_LINES : int = 6
const TEXTURE_CLEANUP_EVERY : int = 120 # States received

var state : int = STOPPED
# One line saying what the helper is doing, or why it isn't.
var status : String = "Not started"

var _settings : Settings
var _log_path : String
var _server : TCPServer
var _stream : MessageStream
var _pid : int = -1
var _token : String
var _started_at : int
var _last_heard : int
var _restart_at : int
var _stale : bool # The project changed while nobody was looking; restart when they look again
var _active : bool

var _stages : Dictionary[ String, Stage ]
var _textures : Dictionary # texture id -> ImageTexture, shared by both stages
var _states_received : int
var _entry_json : String
var _entry_rev : int
var _shown_rev : Dictionary[ String, int ]
var _needs_rebuild : Dictionary[ String, bool ] # Panes still showing a picture from a helper that's gone
var _reports : Dictionary[ String, Array ] # pane id ("" = not about one scene) -> [ { "kind", "text", "where", "rev" } ]

func setup(settings: Settings, cache_dir: String) -> void:
	_settings = settings
	_log_path = cache_dir.path_join( "preview_helper.log" )
	for id in PANE_IDS:
		var stage := Stage.new( _textures )
		stage.name = "Stage_" + id
		add_child( stage )
		_stages[ id ] = stage
		_reports[ id ] = []
	_reports[ "" ] = []
	_stages[ PANE_UI ].virtual_size = Vector2i(
			ProjectSettings.get_setting( "display/window/size/viewport_width", 1152 ),
			ProjectSettings.get_setting( "display/window/size/viewport_height", 648 ) )
	_settings.changed.connect( _on_setting_changed )

func get_stage(pane_id: String) -> Stage:
	return _stages[ pane_id ]

# Whether the pane is showing the entry as it is now, rather than still catching up.
func is_up_to_date(pane_id: String) -> bool:
	return state == RUNNING and _shown_rev.get( pane_id, -1 ) == _entry_rev

# What went wrong showing the current entry in this pane, most recent last.
func get_reports(pane_id: String) -> Array:
	return _reports[ pane_id ] + _reports[ "" ]

#region Starting and stopping

func start() -> void:
	if state == STARTING or state == RUNNING: return
	_close()
	_server = TCPServer.new()
	if _server.listen( 0, "127.0.0.1" ) != OK:
		_fail( "Couldn't open a local connection for the preview helper." )
		return
	_token = "%08x%08x" % [ randi(), randi() ]
	var arguments := PackedStringArray( [
		"--headless", "--path", _settings.get_project_dir(), "--scene", HOST_SCENE, "--log-file", _log_path,
		"--", Protocol.ARG_PORT + str( _server.get_local_port() ), Protocol.ARG_TOKEN + _token,
	] )
	_pid = OS.create_process( OS.get_executable_path(), arguments )
	if _pid <= 0:
		_fail( "Couldn't start a second copy of Godot for the previews." )
		return
	_started_at = Time.get_ticks_msec()
	_stale = false
	_restart_at = 0
	# A new helper numbers its textures from scratch, so nothing kept from the last one can be trusted.
	# The stages keep showing their last picture until the new helper's first one arrives.
	_textures.clear()
	_shown_rev.clear()
	for id : String in _reports: _reports[ id ].clear()
	for id in PANE_IDS: _needs_rebuild[ id ] = true
	_set_state( STARTING, "Starting the game in the background..." )

func stop() -> void:
	_close()
	_set_state( STOPPED, "Stopped" )

func restart() -> void:
	_close()
	state = STOPPED
	start()

# The project's scenes or scripts changed, so what the helper has loaded is out of date.
func notify_project_changed() -> void:
	if state == STOPPED: return
	if _active: _restart_at = Time.get_ticks_msec() + RESTART_DELAY_MSEC
	else: _stale = true

# Whether anyone can see the previews. While nobody can, the helper idles and nothing is redrawn.
func set_active(on: bool) -> void:
	_active = on
	for stage : Stage in _stages.values(): stage.set_drawing( on )
	if on and _stale: restart()
	elif state == RUNNING: _stream.send( { Protocol.TYPE: Protocol.ACTIVE, "on": on } )

func _close() -> void:
	if _stream:
		_stream.send( { Protocol.TYPE: Protocol.QUIT } )
		_stream.close()
		_stream = null
	if _server:
		_server.stop()
		_server = null
	# The helper has nothing to save, so there's no need to wait for it to leave by itself.
	if _pid > 0 and OS.is_process_running( _pid ): OS.kill( _pid )
	_pid = -1

func _fail(reason: String) -> void:
	var tail := _read_log_tail()
	_close()
	_set_state( FAILED, reason + ("\n" + tail if not tail.is_empty() else "") )

func _set_state(new_state: int, new_status: String) -> void:
	state = new_state
	status = new_status
	changed.emit()

func _read_log_tail() -> String:
	if not FileAccess.file_exists( _log_path ): return ""
	var lines := FileAccess.get_file_as_string( _log_path ).strip_edges().split( "\n" )
	return "\n".join( lines.slice( maxi( lines.size() - LOG_TAIL_LINES, 0 ) ) )

func _exit_tree() -> void:
	_close()

#endregion

#region Talking to the helper

func set_entry_json(json: String) -> void:
	if json == _entry_json: return
	_entry_json = json
	_entry_rev += 1
	# What went wrong with the last version isn't true of this one until the helper says so again.
	for id in PANE_IDS: _reports[ id ].clear()
	if state == RUNNING: _send_entry()
	changed.emit()

func set_virtual_size(pane_id: String, size: Vector2i) -> void:
	var stage := _stages[ pane_id ]
	if stage.virtual_size == size: return
	stage.virtual_size = size
	if state == RUNNING: _send_pane( pane_id, false )

# Throws the scene away and makes a fresh one, the way restarting the game would.
func reset_pane(pane_id: String) -> void:
	if state == RUNNING: _send_pane( pane_id, true )

# A mouse press, release or move inside a preview, in the scene's own coordinates.
func send_mouse(pane_id: String, position: Vector2, relative: Vector2, moved: bool, button: MouseButton, pressed: bool, buttons: int) -> void:
	if state != RUNNING: return
	_stream.send( { Protocol.TYPE: Protocol.INPUT, "pane": pane_id, "position": position, "relative": relative, "moved": moved, "button": button, "pressed": pressed, "buttons": buttons } )

func _send_setup() -> void:
	_stream.send( { Protocol.TYPE: Protocol.SETUP, "parser_script": _settings.get_value( Settings.PARSER_SCRIPT ), "parser_method": _settings.get_value( Settings.PARSER_METHOD ) } )
	for id in PANE_IDS: _send_pane( id, false )
	_stream.send( { Protocol.TYPE: Protocol.ACTIVE, "on": _active } )
	if _entry_rev > 0: _send_entry()

func _send_pane(pane_id: String, restart_scene: bool) -> void:
	var is_ui := pane_id == PANE_UI
	_stream.send( {
		Protocol.TYPE: Protocol.PANE, "id": pane_id, "restart": restart_scene,
		"scene": _settings.get_value( Settings.UI_SCENE if is_ui else Settings.ENTRY_SCENE ),
		"method": _settings.get_value( Settings.UI_METHOD if is_ui else Settings.ENTRY_METHOD ),
		"size": _stages[ pane_id ].virtual_size,
	} )

func _send_entry() -> void:
	_stream.send( { Protocol.TYPE: Protocol.ENTRY, "rev": _entry_rev, "json": _entry_json } )

func _on_setting_changed(key: String) -> void:
	if state != RUNNING: return
	if key in [ Settings.PARSER_SCRIPT, Settings.PARSER_METHOD, Settings.UI_SCENE, Settings.UI_METHOD, Settings.ENTRY_SCENE, Settings.ENTRY_METHOD ]:
		for id in PANE_IDS: _reports[ id ].clear()
		_reports[ "" ].clear()
		_send_setup()
		for id in PANE_IDS: _send_pane( id, true )

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _restart_at > 0 and now >= _restart_at:
		restart()
		return

	if state == STARTING:
		if _stream == null and _server.is_connection_available(): _stream = MessageStream.new( _server.take_connection() )
		if _stream:
			for message in _stream.receive():
				# Only the helper this editor started knows the token.
				if message.get( Protocol.TYPE ) == Protocol.HELLO and message.get( "token" ) == _token:
					_last_heard = now
					_server.stop()
					_set_state( RUNNING, "Running" )
					_send_setup()
					return
				_stream.close()
				_stream = null
				break
		if not OS.is_process_running( _pid ): _fail( "The preview helper closed as soon as it started (exit code %d)." % OS.get_process_exit_code( _pid ) )
		elif now - _started_at > START_TIMEOUT_MSEC: _fail( "The preview helper didn't start within %d seconds." % (START_TIMEOUT_MSEC / 1000) )

	elif state == RUNNING:
		if not _stream.is_open():
			_fail( "The preview helper closed (exit code %d). The game's scripts may have crashed it." % OS.get_process_exit_code( _pid ) )
			return
		for message in _stream.receive():
			_last_heard = now
			_handle( message )
		if now - _last_heard > SILENCE_TIMEOUT_MSEC: _fail( "The preview helper stopped answering. One of the game's scripts may be stuck in a loop." )

func _handle(message: Dictionary) -> void:
	match message.get( Protocol.TYPE, "" ):
		Protocol.TEXTURE:
			var pixels : PackedByteArray = message[ "data" ].decompress( message[ "size" ], FileAccess.COMPRESSION_ZSTD )
			var image := Image.create_from_data( message[ "width" ], message[ "height" ], message[ "mipmaps" ], message[ "format" ], pixels )
			if image: _textures[ message[ "id" ] ] = ImageTexture.create_from_image( image )
		Protocol.STATE:
			var pane_id : String = message.get( "pane", "" )
			if not _stages.has( pane_id ): return
			var snapshot : Variant = bytes_to_var( message[ "data" ] )
			if not snapshot is Dictionary: return
			var stage := _stages[ pane_id ]
			if _needs_rebuild.get( pane_id, false ):
				_needs_rebuild[ pane_id ] = false
				stage.clear()
			stage.apply_state( snapshot )
			_shown_rev[ pane_id ] = message.get( "rev", -1 )
			if stage.mirror:
				for problem in stage.mirror.problems: _add_report( pane_id, { "kind": "error", "text": problem, "where": "", "rev": _entry_rev } )
			_states_received += 1
			if _states_received % TEXTURE_CLEANUP_EVERY == 0: _drop_unused_textures()
			changed.emit()
		Protocol.REPORT:
			var pane_id : String = message.get( "pane", "" )
			if not _reports.has( pane_id ): pane_id = ""
			# A report about a version of the entry that's since been replaced isn't true of this one.
			# (-1 is a scene that never got an entry: a problem with the scene itself, which still stands.)
			var about_rev : int = message.get( "rev", -1 )
			if not pane_id.is_empty() and about_rev != -1 and about_rev < _entry_rev: return
			_add_report( pane_id, message )
			changed.emit()

func _add_report(pane_id: String, report: Dictionary) -> void:
	var list : Array = _reports[ pane_id ]
	for existing : Dictionary in list:
		if existing[ "text" ] == report[ "text" ] and existing[ "where" ] == report[ "where" ]: return
	list.append( report )
	if list.size() > MAX_REPORTS: list.pop_front()

func _drop_unused_textures() -> void:
	var used := {}
	for stage : Stage in _stages.values():
		if stage.mirror: stage.mirror.collect_texture_ids( used )
	for id : Variant in _textures.keys():
		if not used.has( id ): _textures.erase( id )

#endregion
