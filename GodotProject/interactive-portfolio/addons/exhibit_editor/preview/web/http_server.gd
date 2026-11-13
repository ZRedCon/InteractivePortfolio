@tool
extends RefCounted

# A very small web server for the website previews. It serves the real Webfiles folder to the
# preview browser, with a few differences from opening the site for real:
#   - "virtual" files answer from memory instead of disk. That's how the entry being edited (not yet
#     saved) becomes the only entry the page finds: the data index and the entry file are virtual.
#   - "blank" folders answer with an empty page, so the preview doesn't load the whole Godot web build.
#   - nothing is cached, so an edit to a .js or .css file shows up on the next reload.
#   - file names must match capital letters exactly, the way they must on nearly every web host.
#     Windows itself doesn't care, which is how a site can work at home and break once it's uploaded.
#
# It only listens on 127.0.0.1, so nothing outside this computer can reach it.

const MAX_REQUEST_BYTES : int = 16384
const CLIENT_TIMEOUT_MSEC : int = 5000

const MIME_TYPES : Dictionary[ String, String ] = {
	"html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8", "css": "text/css; charset=utf-8",
	"js": "text/javascript; charset=utf-8", "mjs": "text/javascript; charset=utf-8", "json": "application/json; charset=utf-8",
	"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp",
	"svg": "image/svg+xml", "ico": "image/x-icon", "avif": "image/avif",
	"woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf",
	"mp4": "video/mp4", "webm": "video/webm", "ogv": "video/ogg", "mp3": "audio/mpeg", "ogg": "audio/ogg", "wav": "audio/wav",
	"txt": "text/plain; charset=utf-8", "wasm": "application/wasm",
}

# The folder that plays the part of the website's root.
var root_dir : String
# Folders (as URL paths ending in "/", like "/godot/") that answer with an empty page.
var blank_folders : PackedStringArray
# What the browser asked for and didn't get, since the last clear_missing(): URL path -> why not.
var missing : Dictionary[ String, String ]

var _server := TCPServer.new()
var _clients : Array[ Dictionary ] # { "peer": StreamPeerTCP, "data": PackedByteArray, "since": msec }
var _virtual_files : Dictionary # URL path -> { "body": PackedByteArray, "type": String }
var _served : Dictionary[ String, int ] # File on disk -> when it was last changed, as of serving it

func start() -> Error:
	stop()
	# Port 0 asks the system for any free port.
	return _server.listen( 0, "127.0.0.1" )

func stop() -> void:
	for client in _clients: client[ "peer" ].disconnect_from_host()
	_clients.clear()
	if _server.is_listening(): _server.stop()

func is_running() -> bool:
	return _server.is_listening()

func get_port() -> int:
	return _server.get_local_port()

func get_url(path: String = "") -> String:
	return "http://127.0.0.1:%d/%s" % [ get_port(), path.trim_prefix( "/" ) ]

func set_virtual_file(url_path: String, body: PackedByteArray, type: String = "application/json; charset=utf-8") -> void:
	_virtual_files[ "/" + url_path.trim_prefix( "/" ) ] = { "body": body, "type": type }

func clear_virtual_files() -> void:
	_virtual_files.clear()

func clear_missing() -> void:
	missing.clear()

# Whether any file handed to the browser has been edited (or removed) since. Forgets what it handed
# out when it says yes, since the reload that follows asks for everything again.
func take_files_changed() -> bool:
	for path : String in _served:
		if not FileAccess.file_exists( path ) or FileAccess.get_modified_time( path ) != _served[ path ]:
			_served.clear()
			return true
	return false

# Call every frame.
func poll() -> void:
	if not _server.is_listening(): return
	while _server.is_connection_available():
		_clients.append( { "peer": _server.take_connection(), "data": PackedByteArray(), "since": Time.get_ticks_msec() } )

	for i in range( _clients.size() - 1, -1, -1 ):
		if _serve( _clients[ i ] ): _clients.remove_at( i )

# Returns true once the client is finished with (answered, gone or too slow).
func _serve(client: Dictionary) -> bool:
	var peer : StreamPeerTCP = client[ "peer" ]
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: return true

	var available := peer.get_available_bytes()
	if available > 0:
		var chunk : Array = peer.get_partial_data( available )
		if chunk[ 0 ] != OK: return true
		client[ "data" ].append_array( chunk[ 1 ] )

	var data : PackedByteArray = client[ "data" ]
	var text := data.get_string_from_utf8()
	if not text.contains( "\r\n\r\n" ):
		var too_slow : bool = Time.get_ticks_msec() - client[ "since" ] > CLIENT_TIMEOUT_MSEC
		if data.size() > MAX_REQUEST_BYTES or too_slow:
			peer.disconnect_from_host()
			return true
		return false

	_answer( peer, text.get_slice( "\r\n", 0 ) )
	peer.disconnect_from_host()
	return true

func _answer(peer: StreamPeerTCP, request_line: String) -> void:
	var parts := request_line.split( " " )
	if parts.size() < 2 or (parts[ 0 ] != "GET" and parts[ 0 ] != "HEAD"):
		_send( peer, 405, "text/plain; charset=utf-8", "Only GET is supported.".to_utf8_buffer(), true )
		return
	var with_body := parts[ 0 ] == "GET"
	# "/src/main.js?v=2#top" -> "/src/main.js"
	var url_path := parts[ 1 ].get_slice( "#", 0 ).get_slice( "?", 0 ).uri_decode()
	if url_path.ends_with( "/" ) and not _is_blank( url_path ): url_path += "index.html"

	if _virtual_files.has( url_path ):
		var file : Dictionary = _virtual_files[ url_path ]
		_send( peer, 200, file[ "type" ], file[ "body" ], with_body )
		return
	if _is_blank( url_path ):
		_send( peer, 200, MIME_TYPES[ "html" ], "<!DOCTYPE html><title>(left out of the preview)</title>".to_utf8_buffer(), with_body )
		return

	var problem := _find_problem( url_path )
	if not problem.is_empty():
		# Browsers ask for /favicon.ico by themselves when a page doesn't name an icon. Nobody's mistake.
		if url_path != "/favicon.ico": missing[ url_path ] = problem
		_send( peer, 404, "text/plain; charset=utf-8", problem.to_utf8_buffer(), with_body )
		return
	var disk_path := root_dir.path_join( url_path.trim_prefix( "/" ) )
	_served[ disk_path ] = FileAccess.get_modified_time( disk_path )
	_send( peer, 200, MIME_TYPES.get( url_path.get_extension().to_lower(), "application/octet-stream" ), FileAccess.get_file_as_bytes( disk_path ), with_body )

# "" when the file is there to send. Otherwise why a web host wouldn't send it.
func _find_problem(url_path: String) -> String:
	# ".." would climb out of the website's folder.
	if url_path.contains( ".." ) or url_path.contains( "\\" ): return "Not found: " + url_path
	if not FileAccess.file_exists( root_dir.path_join( url_path.trim_prefix( "/" ) ) ): return "Not found: " + url_path

	# The file exists as far as Windows is concerned. Checks each part of the path against the real
	# names on disk, since a web host would only find it if the capital letters match too.
	var dir := root_dir
	var parts := url_path.trim_prefix( "/" ).split( "/" )
	for i in parts.size():
		var is_last := i == parts.size() - 1
		var names := DirAccess.get_files_at( dir ) if is_last else DirAccess.get_directories_at( dir )
		if not names.has( parts[ i ] ):
			for real_name in names:
				if real_name.to_lower() == parts[ i ].to_lower():
					return "Not found: %s (on disk it's spelled \"%s\", not \"%s\". Windows doesn't mind, but a web host does.)" % [ url_path, real_name, parts[ i ] ]
			return "Not found: " + url_path
		dir = dir.path_join( parts[ i ] )
	return ""

func _is_blank(url_path: String) -> bool:
	for folder in blank_folders:
		if url_path.begins_with( folder ): return true
	return false

func _send(peer: StreamPeerTCP, status: int, type: String, body: PackedByteArray, with_body: bool) -> void:
	var reason := "OK" if status == 200 else "Not Found" if status == 404 else "Method Not Allowed"
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [ status, reason, type, body.size() ]
	peer.put_data( head.to_utf8_buffer() )
	if with_body and not body.is_empty(): peer.put_data( body )
