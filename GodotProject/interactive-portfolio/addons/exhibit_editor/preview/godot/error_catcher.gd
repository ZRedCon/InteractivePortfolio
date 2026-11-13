extends Logger

# Runs in the preview helper process. Collects every error and warning the engine reports while the
# game's scripts fill in the exhibit scenes, so the editor can show them beside the preview instead
# of them being lost in a log nobody sees.

const KIND_ERROR := "error"
const KIND_WARNING := "warning"

var _mutex := Mutex.new() # The engine may report from any thread
var _caught : Array[ Dictionary ]

# Everything caught since the last call, oldest first. Each is { "kind", "text", "where" }.
func take() -> Array[ Dictionary ]:
	_mutex.lock()
	var caught := _caught
	_caught = []
	_mutex.unlock()
	return caught

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ ScriptBacktrace ]) -> void:
	# For the engine's own checks `code` is the C++ condition that failed and `rationale` is the sentence
	# written for people. Script errors only have `code`.
	var text := rationale if not rationale.is_empty() else code
	# Says where in the game's scripts it happened, when a script was running, rather than where in the engine.
	var where := "%s:%d in %s()" % [ file.get_file(), line, function ]
	for backtrace in script_backtraces:
		if backtrace.get_frame_count() > 0:
			where = "%s:%d in %s()" % [ backtrace.get_frame_file( 0 ).get_file(), backtrace.get_frame_line( 0 ), backtrace.get_frame_function( 0 ) ]
			break
	_add( KIND_WARNING if error_type == ERROR_TYPE_WARNING else KIND_ERROR, text, where )

# printerr() arrives here with error = true. That's how file_parser.gd reports a bad image.
func _log_message(message: String, error: bool) -> void:
	if error: _add( KIND_ERROR, message.strip_edges(), "" )

func _add(kind: String, text: String, where: String) -> void:
	_mutex.lock()
	_caught.append( { "kind": kind, "text": text, "where": where } )
	_mutex.unlock()
