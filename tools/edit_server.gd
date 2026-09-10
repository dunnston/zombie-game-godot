extends SceneTree
## The content editor's server: `tools\edit` (or `tools/edit.sh`).
##
## Serves `tools/editor/` and reads and writes `data/*.json` on
## http://127.0.0.1:8765, then opens a browser. It runs in Godot because Godot
## is the one thing everyone working on this already has, and because then the
## file is written by `DataTable.encode` — the same code the game and the
## tests use — rather than by a second serializer in JavaScript that could
## drift from it. `EditApi` does the work; this only speaks HTTP.
##
##   --lan        also answer on this machine's LAN address (a phone on the
##                same wifi). Off by default. Never port-forward it.
##   --port=N     default 8765
##   --no-open    do not open a browser
##
## Nothing is ever public: the default bind is loopback, every write needs a
## per-run token that only the served page knows, and a request for any host
## but the ones printed below is refused.

const DEFAULT_PORT := 8765
const STATUS := {200: "OK", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
	413: "Payload Too Large", 422: "Unprocessable Entity", 500: "Internal Server Error"}
const MAX_REQUEST := 8 * 1024 * 1024

var api: EditApi
var server := TCPServer.new()
var conns: Array[Dictionary] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var port := DEFAULT_PORT
	for a: String in args:
		if a.begins_with("--port="):
			port = int(a.substr(7))
	var lan := "--lan" in args
	if server.listen(port, "*" if lan else "127.0.0.1") != OK:
		printerr("Could not listen on port %d. Is the editor already running? Try --port=%d." % [port, port + 1])
		quit(1)
		return
	api = EditApi.new()
	api.token = Crypto.new().generate_random_bytes(16).hex_encode()
	api.allowed_hosts = ["127.0.0.1:%d" % port, "localhost:%d" % port]
	var url := "http://127.0.0.1:%d/" % port
	print("DEADLINE content editor on %s  (Ctrl+C to stop)" % url)
	if lan:
		for ip: String in IP.get_local_addresses():
			if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
				api.allowed_hosts.append("%s:%d" % [ip, port])
				print("  on this wifi: http://%s:%d/" % [ip, port])
	var problems: Array = api.integrity(api.world())
	if not problems.is_empty():
		print("  note: the content already has %d broken reference(s); the page lists them." % problems.size())
	if not "--no-open" in args:
		OS.shell_open(url)


func _process(_delta: float) -> bool:
	while server.is_connection_available():
		conns.append({"peer": server.take_connection(), "buf": PackedByteArray(), "t": Time.get_ticks_msec()})
	for c: Dictionary in conns.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			conns.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_data(n)
			if got[0] == OK:
				# A packed array in a Dictionary is a copy on read: append, then
				# put it back.
				var buf: PackedByteArray = c.buf
				buf.append_array(got[1])
				c.buf = buf
		var req := _parse(c.buf)
		if req.is_empty():
			if Time.get_ticks_msec() - int(c.t) > 15000 or (c.buf as PackedByteArray).size() > MAX_REQUEST:
				_send(peer, {"status": 413, "type": "text/plain", "body": "Request too large or too slow.".to_utf8_buffer()})
				conns.erase(c)
			continue
		var res := api.handle(req.method, req.path, req.headers, req.body, req.get("raw", PackedByteArray()))
		_send(peer, res)
		if res.status >= 400:
			print("  %s %s -> %d" % [req.method, req.path, res.status])
		elif req.method == "PUT" or req.method == "DELETE":
			var info: Variant = JSON.parse_string((res.body as PackedByteArray).get_string_from_utf8())
			if typeof(info) == TYPE_DICTIONARY and info.has("diff"):
				print("  saved %s (+%d -%d lines)" % [info.get("file", "?"), info.diff.added, info.diff.removed])
			elif typeof(info) == TYPE_DICTIONARY:
				print("  %s %s" % ["removed" if req.method == "DELETE" else "saved", info.get("file", "?")])
		conns.erase(c)
	OS.delay_msec(5)
	return false


## A complete request out of the bytes so far, or {} to keep reading.
func _parse(buf: PackedByteArray) -> Dictionary:
	var end := -1
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			end = i
			break
	if end < 0:
		return {}
	var lines := buf.slice(0, end).get_string_from_utf8().split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "/", "headers": {}, "body": ""}
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0:
			headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	if buf.size() < end + 4 + length:
		return {}
	# The raw bytes as well as the text: an image upload is not UTF-8.
	var raw := buf.slice(end + 4, end + 4 + length)
	return {"method": first[0], "path": first[1].uri_decode(), "headers": headers,
		"body": raw.get_string_from_utf8(), "raw": raw}


func _send(peer: StreamPeerTCP, res: Dictionary) -> void:
	var body: PackedByteArray = res.body
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n" % [
		res.status, STATUS.get(res.status, "Error"), res.type, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()
