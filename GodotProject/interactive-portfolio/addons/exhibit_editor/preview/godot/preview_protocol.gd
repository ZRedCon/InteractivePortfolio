@tool
extends RefCounted

# The messages the editor and the preview helper send each other (see message_stream.gd for how).
# Every message is a Dictionary whose TYPE says which of these it is.

const TYPE := "type"

# Editor -> helper
const SETUP := "setup"		# { "parser_script", "parser_method" }: where Entry objects come from
const PANE := "pane"		# { "id", "scene", "method", "size" }: a scene to show, and how to fill it
const ENTRY := "entry"		# { "rev", "json" }: the entry to show, as the text of its file
const ACTIVE := "active"	# { "on" }: whether anyone is looking at the previews
const INPUT := "input"		# { "pane", "pressed", "moved", "position", "relative", "button", "buttons" }
const QUIT := "quit"

# Helper -> editor
const HELLO := "hello"		# { "token", "pid" }: must come first, with the token the editor handed out
const STATE := "state"		# { "pane", "rev", "data" }: a scene_snapshot.gd snapshot, as bytes
const TEXTURE := "texture"	# { "id", "width", "height", "format", "mipmaps", "size", "data" }: an image's pixels
const REPORT := "report"	# { "pane", "rev", "kind", "text", "where" }: an error or warning
const ALIVE := "alive"		# Sent every second or so, so a stuck helper is noticed

# How the helper is told where to connect, after the "--" on its command line.
const ARG_PORT := "--exhibit-preview-port="
const ARG_TOKEN := "--exhibit-preview-token="
