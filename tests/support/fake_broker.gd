class_name FakeBroker
extends RefCounted
## `server/signal.js` in-process, for the fast tier: the same room table and
## the same relay rules, with each end a `FakeSignaller` whose inbox this
## fills directly. The slow tier runs the real script under Node.

var rooms := {}          # code -> {host, guests: {gid: signaller}, seq}
var next_code := ["ABCDEF", "GHJKLM", "NPQRST"]
var ends: Array[FakeSignaller] = []


func signaller() -> FakeSignaller:
	var s := FakeSignaller.new()
	s.broker = self
	ends.append(s)
	return s


func _on(s: FakeSignaller, m: Dictionary) -> void:
	var t := String(m.get("t", ""))
	if t == "host" and s.role.is_empty():
		var code: String = next_code.pop_front() if not next_code.is_empty() else "ZZZZZZ"
		s.role = "host"
		s.code = code
		rooms[code] = {"host": s, "guests": {}, "seq": 0}
		s.deliver({"t": "code", "code": code})
		return
	if t == "join" and s.role.is_empty():
		var want := String(m.get("code", "")).to_upper()
		var room: Dictionary = rooms.get(want, {})
		if not WebRtcHub.is_code(want) or room.is_empty():
			s.deliver({"t": "nope", "reason": "no game with that code"})
			return
		if (room.guests as Dictionary).size() >= 3:
			s.deliver({"t": "nope", "reason": "that game is full"})
			return
		room.seq += 1
		var gid := "g%d" % int(room.seq)
		s.role = "guest"
		s.code = want
		s.gid = gid
		room.guests[gid] = s
		s.deliver({"t": "joined", "gid": gid})
		(room.host as FakeSignaller).deliver({"t": "join", "gid": gid})
		return
	var room: Dictionary = rooms.get(s.code, {})
	if room.is_empty() or not (t in ["offer", "answer", "ice"]):
		return
	if s.role == "host":
		var g: FakeSignaller = (room.guests as Dictionary).get(String(m.get("gid", "")), null)
		if g != null:
			g.deliver({"t": t, "sdp": m.get("sdp"), "cand": m.get("cand")})
	else:
		(room.host as FakeSignaller).deliver({"t": t, "gid": s.gid, "sdp": m.get("sdp"), "cand": m.get("cand")})


func _closed(s: FakeSignaller) -> void:
	var room: Dictionary = rooms.get(s.code, {})
	if room.is_empty():
		return
	if s.role == "host":
		for g in (room.guests as Dictionary).values():
			(g as FakeSignaller).deliver({"t": "host-left"})
		rooms.erase(s.code)
	elif s.role == "guest":
		(room.guests as Dictionary).erase(s.gid)
		(room.host as FakeSignaller).deliver({"t": "guest-left", "gid": s.gid})


class FakeSignaller extends WebRtcHub.NetSignaller:
	var broker: FakeBroker
	var role := ""
	var code := ""
	var gid := ""
	var _open := false
	var _box: Array[Dictionary] = []

	func open(_url: String) -> String:
		_open = true
		return ""

	func poll() -> void:
		pass

	func state() -> String:
		return "open" if _open else "closed"

	func take() -> Array[Dictionary]:
		var out := _box
		_box = []
		return out

	func send(m: Dictionary) -> void:
		if _open:
			broker._on(self, m)

	func deliver(m: Dictionary) -> void:
		_box.append(m)

	func close() -> void:
		if _open:
			_open = false
			broker._closed(self)
