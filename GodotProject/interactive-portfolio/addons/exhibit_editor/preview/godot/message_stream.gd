@tool
extends RefCounted

# The line between the editor and the preview helper: Dictionaries sent whole, one after another,
# over a TCP connection that never leaves this computer.
#
# On the wire each message is 4 bytes giving its length, then the Dictionary as var_to_bytes() wrote
# it. Objects are never decoded, so nothing arriving here can carry a script.

const MAX_MESSAGE_BYTES : int = 256 * 1024 * 1024

var _peer : StreamPeerTCP
var _buffer : PackedByteArray

func _init(peer: StreamPeerTCP) -> void:
	_peer = peer
	_peer.set_no_delay( true ) # Small messages go out at once instead of waiting to be bundled

func is_open() -> bool:
	_peer.poll()
	return _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED

func is_connecting() -> bool:
	_peer.poll()
	return _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING

func close() -> void:
	_peer.disconnect_from_host()

func send(message: Dictionary) -> bool:
	if not is_open(): return false
	var data := var_to_bytes( message )
	_peer.put_32( data.size() )
	return _peer.put_data( data ) == OK

# Every whole message that has arrived since the last call.
func receive() -> Array[ Dictionary ]:
	var messages : Array[ Dictionary ] = []
	if not is_open(): return messages
	var available := _peer.get_available_bytes()
	if available > 0:
		var chunk : Array = _peer.get_partial_data( available )
		if chunk[ 0 ] == OK: _buffer.append_array( chunk[ 1 ] )

	var start := 0
	while _buffer.size() - start >= 4:
		var length := _buffer.decode_u32( start )
		if length > MAX_MESSAGE_BYTES:
			# Not something either side ever sends, so whatever is on the other end isn't ours.
			close()
			_buffer.clear()
			return messages
		if _buffer.size() - start - 4 < length: break
		var message : Variant = bytes_to_var( _buffer.slice( start + 4, start + 4 + length ) )
		if message is Dictionary: messages.append( message )
		start += 4 + length
	if start > 0: _buffer = _buffer.slice( start )
	return messages
