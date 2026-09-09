class_name WebRtcHub
extends PeerHub
## Room codes behind the `NetLink` face: `WebRTCMultiplayerPeer` over
## connections that a broker introduces. Built and tested, and **switched
## off** until `Config.NET.broker` names a broker — the switch for when a
## router will not open a port (PROJECT.md §6).
##
## Two halves. The signalling half talks to `server/signal.js` over a
## WebSocket the engine ships with: the host registers and gets a six-letter
## code, a guest joins with the code, and the broker relays the offer, the
## answer and the ICE candidates until the two machines are talking to each
## other directly. After that it is out of the loop. The data half is the
## engine's own `WebRTCMultiplayerPeer`, which the base class already knows
## how to deal packets from.
##
## The one thing the engine does not ship is the WebRTC *implementation*:
## `WebRTCPeerConnection.new()` is a stub until the `webrtc-native` extension
## is in `addons/webrtc/` (`tools/fetch-webrtc`). `available()` says whether
## it is. Both halves are pluggable — `signaller` and `make_connection` — so
## the tests run the whole handshake through the real broker and the real
## multiplayer peer with a GDScript connection standing in for the native one.

const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LEN := 6

## "host" or "guest".
var role := ""
var code := ""
## One sentence for the HOST or JOIN page.
var status := ""
var signaller: NetSignaller = null
## Makes a `WebRTCPeerConnection`, initialised. Replaced by the tests.
static var make_connection: Callable = Callable()
var _conns := {}          # peer id -> WebRTCPeerConnection
var _gids := {}           # peer id -> gid, host side
var _my_id := 0
var _said_hello := false
var _code_wanted := ""
var _host_left := false


## Whether the native implementation is in the project. Without it the
## engine hands back the extension base class, which does nothing.
static func available() -> bool:
	var c := WebRTCPeerConnection.new()
	return c.get_class() != "WebRTCPeerConnectionExtension"


static func is_code(s: String) -> bool:
	if s.length() != CODE_LEN:
		return false
	for ch in s:
		if not CODE_ALPHABET.contains(ch):
			return false
	return true


static func normalise_code(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		if CODE_ALPHABET.contains(ch):
			out += ch
	return out.left(CODE_LEN)


## The broker numbers guests g1, g2, …; peer ids start at 2 (1 is the host).
static func gid_to_id(gid: String) -> int:
	return 1 + int(gid.trim_prefix("g"))


func _new_connection() -> WebRTCPeerConnection:
	if make_connection.is_valid():
		return make_connection.call()
	var c := WebRTCPeerConnection.new()
	var servers: Array = []
	for s in Config.NET.stun:
		servers.append({"urls": [String(s)]})
	c.initialize({"iceServers": servers})
	return c


# ------------------------------------------------------------------- host --

## Opens a room. The code arrives through `poll`; `code` is "" until then.
func host(url: String) -> String:
	role = "host"
	var p := WebRTCMultiplayerPeer.new()
	var err := p.create_server()
	if err != OK:
		error = "could not start WebRTC (%s)" % error_string(err)
		return error
	peer = p
	_wire()
	return _dial(url)


## Joins a room. The link to the host exists once `connected()` says so.
func join(url: String, code_: String) -> String:
	role = "guest"
	_code_wanted = normalise_code(code_)
	if not is_code(_code_wanted):
		error = "a room code is six letters or digits"
		return error
	return _dial(url)


func _dial(url: String) -> String:
	if signaller == null:
		signaller = NetSignaller.new()
	var err := signaller.open(url)
	if not err.is_empty():
		error = err
		return err
	status = "contacting the broker…"
	return ""


func poll() -> void:
	_poll_signalling()
	super.poll()


func _poll_signalling() -> void:
	if signaller == null:
		return
	signaller.poll()
	if signaller.state() == "open" and not _said_hello:
		_said_hello = true
		signaller.send({"t": "host"} if role == "host" else {"t": "join", "code": _code_wanted})
	for m in signaller.take():
		_on_signal(m)
	if _host_left and not connected() and error.is_empty():
		error = "the host left"
	if signaller.state() == "closed" and error.is_empty():
		if role == "host" and not code.is_empty():
			# The broker going away mid-game costs nothing: nobody new can
			# join, and everyone already here is talking directly.
			status = "the broker is gone — nobody new can join; current players are fine"
		elif role == "guest" and not connected():
			error = "the broker closed the connection"


func _on_signal(m: Dictionary) -> void:
	var t := String(m.get("t", ""))
	match t:
		"code":
			code = String(m.get("code", ""))
			status = "room %s open — friends type this code" % code
		"nope":
			error = String(m.get("reason", "the broker said no"))
		"join":
			# Host: a guest has arrived at the broker. Offer them a line.
			var gid := String(m.get("gid", ""))
			var id := gid_to_id(gid)
			var c := _new_connection()
			_conns[id] = c
			_gids[id] = gid
			_hook(c, id)
			peer.add_peer(c, id)
			c.create_offer()
		"joined":
			# Guest: seated at the broker; the host's offer follows.
			_my_id = gid_to_id(String(m.get("gid", "")))
			var p := WebRTCMultiplayerPeer.new()
			var err := p.create_client(_my_id)
			if err != OK:
				error = "could not start WebRTC (%s)" % error_string(err)
				return
			peer = p
			_wire()
			status = "seated — waiting for the host's offer…"
		"offer":
			var c := _new_connection()
			_conns[1] = c
			_hook(c, 1)
			peer.add_peer(c, 1)
			# Setting a remote offer makes the engine create the answer; it
			# comes back through `session_description_created`.
			c.set_remote_description("offer", String(m.get("sdp", "")))
			status = "answering the host…"
		"answer":
			var id := gid_to_id(String(m.get("gid", "")))
			if _conns.has(id):
				_conns[id].set_remote_description("answer", String(m.get("sdp", "")))
		"ice":
			var id := 1 if role == "guest" else gid_to_id(String(m.get("gid", "")))
			var cand = m.get("cand", {})
			if _conns.has(id) and cand is Dictionary:
				_conns[id].add_ice_candidate(String(cand.get("mid", "")), int(cand.get("index", 0)), String(cand.get("sdp", "")))
		"guest-left":
			var id := gid_to_id(String(m.get("gid", "")))
			if peer != null and peer.has_peer(id):
				peer.remove_peer(id)
			_conns.erase(id)
			_gids.erase(id)
		"host-left":
			# Said once the line is down too: the broker's word may arrive a
			# frame before the peer notices the connection has gone.
			_host_left = true


func _hook(c: WebRTCPeerConnection, id: int) -> void:
	c.session_description_created.connect(_on_description.bind(id))
	c.ice_candidate_created.connect(_on_candidate.bind(id))


func _on_description(type: String, sdp: String, id: int) -> void:
	var c: WebRTCPeerConnection = _conns.get(id, null)
	if c == null:
		return
	c.set_local_description(type, sdp)
	var m := {"t": type, "sdp": sdp}
	if role == "host":
		m["gid"] = _gids.get(id, "")
	signaller.send(m)


func _on_candidate(media: String, index: int, name_: String, id: int) -> void:
	var m := {"t": "ice", "cand": {"mid": media, "index": index, "sdp": name_}}
	if role == "host":
		m["gid"] = _gids.get(id, "")
	signaller.send(m)


func connected() -> bool:
	if role == "guest":
		return links.has(1)
	return peer != null and not code.is_empty()


func close() -> void:
	if signaller != null:
		signaller.close()
		signaller = null
	for c in _conns.values():
		c.close()
	_conns.clear()
	_gids.clear()
	super.close()


## The broker, over the engine's own WebSocket, JSON text frames, one
## message per frame — `server/signal.js`'s wire. Kept apart from the hub
## so a test can put an in-process relay in its place.
class NetSignaller extends RefCounted:
	var ws: WebSocketPeer = null
	var _inbox: Array[Dictionary] = []
	var _closed := false

	func open(url: String) -> String:
		ws = WebSocketPeer.new()
		var err := ws.connect_to_url(url)
		if err != OK:
			return "could not dial the broker at %s (%s)" % [url, error_string(err)]
		return ""

	func poll() -> void:
		if ws == null:
			return
		ws.poll()
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			var v = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if v is Dictionary and v.has("t"):
				_inbox.append(v)
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_closed = true

	## "connecting", "open" or "closed".
	func state() -> String:
		if ws == null or _closed:
			return "closed"
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN: return "open"
			WebSocketPeer.STATE_CONNECTING: return "connecting"
		return "closed"

	func take() -> Array[Dictionary]:
		var out := _inbox
		_inbox = []
		return out

	func send(m: Dictionary) -> void:
		if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(JSON.stringify(m))

	func close() -> void:
		if ws != null and not _closed:
			ws.close()
		_closed = true
