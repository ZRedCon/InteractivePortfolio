@tool
extends RefCounted

# Talks to the preview browser over the Chrome DevTools Protocol: the same connection Chrome's own
# developer tools use. Every message is JSON over one WebSocket. A command carries an id and the
# browser answers with the same id; things that just happen (a page finished loading, a script logged
# an error) arrive as events with no id.
#
# Protocol reference: https://chromedevtools.github.io/devtools-protocol/

# Something happened in a page. session_id says which page (see Target.attachToTarget).
signal event_received(session_id: String, method: String, params: Dictionary)
# The connection ended, whether we closed it or the browser went away.
signal closed

# Big enough for a screenshot of a tall exhibit, which arrives as one message.
const INBOUND_BUFFER_BYTES : int = 48 * 1024 * 1024
const REQUEST_TIMEOUT_MSEC : int = 15000
# The key a failed request's answer carries instead of a result.
const ERROR_KEY := "cdp_error"

# One command waiting for its answer. request() awaits `done`.
class Reply extends RefCounted:
	signal done(result: Dictionary)
	var sent_at : int
	var method : String

var _socket : WebSocketPeer
var _next_id : int = 1
var _waiting : Dictionary[ int, Reply ]
var _was_open : bool

func open(websocket_url: String) -> Error:
	close()
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = INBOUND_BUFFER_BYTES
	_socket.max_queued_packets = 4096
	_was_open = false
	return _socket.connect_to_url( websocket_url )

func close() -> void:
	if _socket:
		_socket.close()
		_socket = null
		_fail_all( "The connection to the preview browser was closed." )
		if _was_open: closed.emit()
	_was_open = false

func is_open() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func is_connecting() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING

static func failed(result: Dictionary) -> bool:
	return result.has( ERROR_KEY )

# Sends a command and waits for its answer. On failure the answer is { ERROR_KEY: "what went wrong" },
# so callers check failed( result ) instead of this ever throwing.
func request(method: String, params: Dictionary = {}, session_id: String = "") -> Dictionary:
	if not is_open(): return { ERROR_KEY: "Not connected to the preview browser." }
	var id := _next_id
	_next_id += 1
	var message := { "id": id, "method": method, "params": params }
	if not session_id.is_empty(): message[ "sessionId" ] = session_id
	if _socket.send_text( JSON.stringify( message ) ) != OK: return { ERROR_KEY: "Couldn't send %s to the preview browser." % method }

	var reply := Reply.new()
	reply.sent_at = Time.get_ticks_msec()
	reply.method = method
	_waiting[ id ] = reply
	return await reply.done

# Call every frame.
func poll() -> void:
	if _socket == null: return
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_was_open = true
		while _socket != null and _socket.get_available_packet_count() > 0:
			_handle( _socket.get_packet().get_string_from_utf8() )
		_fail_overdue()
	elif state == WebSocketPeer.STATE_CLOSED:
		close()

func _handle(text: String) -> void:
	var message : Variant = JSON.parse_string( text )
	if not message is Dictionary: return

	if message.has( "id" ):
		var id := int( message[ "id" ] )
		var reply : Reply = _waiting.get( id )
		if reply == null: return
		_waiting.erase( id )
		if message.has( "error" ):
			reply.done.emit( { ERROR_KEY: "%s failed: %s" % [ reply.method, message[ "error" ].get( "message", "unknown error" ) ] } )
		else:
			reply.done.emit( message.get( "result", {} ) )
	elif message.has( "method" ):
		event_received.emit( message.get( "sessionId", "" ), message[ "method" ], message.get( "params", {} ) )

func _fail_overdue() -> void:
	var now := Time.get_ticks_msec()
	for id : int in _waiting.keys():
		var reply := _waiting[ id ]
		if now - reply.sent_at > REQUEST_TIMEOUT_MSEC:
			_waiting.erase( id )
			reply.done.emit( { ERROR_KEY: "The preview browser didn't answer %s in time." % reply.method } )

func _fail_all(reason: String) -> void:
	var replies := _waiting.values()
	_waiting.clear()
	for reply : Reply in replies: reply.done.emit( { ERROR_KEY: reason } )
