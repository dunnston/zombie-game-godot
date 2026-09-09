class_name NetDoor
extends RefCounted
## The cheap way onto the internet: ask the router to open the port itself.
##
## Godot ships a `UPNP` class. Most home routers answer it, and when one
## does, friends across the internet dial the host's public address with no
## port forwarding by hand and no server of ours in between. Some routers
## have it switched off, and carrier-grade NAT defeats it entirely — so this
## reports what happened, in words, and the LAN address beside it either way.
##
## When it does not work, `Stun` still finds the public address, so a host who
## forwarded the port by hand has a line to copy rather than a shrug. Nobody
## remembers their own public address.
##
## Discovery blocks for up to two seconds, so it runs on a thread; the scene
## polls `status` each frame. Nothing here touches the sim.

var port := 0
## "asking", "open", "refused", "none", "closed".
var state := "asking"
## One sentence for the HOST page.
var status := "asking the router to open the port…"
## The address friends type, once the router said yes: "203.0.113.5:27333".
var public := ""
var _thread: Thread = null
var _mutex := Mutex.new()
var _upnp: UPNP = null
var _mapped := false
## Closed while discovery was still running: the thread takes the mapping
## down itself when it gets there, and `reap()` joins it later.
var _closing := false
## Threads whose door was closed before they finished. A Thread must be
## joined before it is freed, and nobody should wait several seconds at
## STOP HOSTING for a router that is not answering.
static var _orphans: Array[Thread] = []


func open(port_: int) -> void:
	port = port_
	_thread = Thread.new()
	_thread.start(_work)


## Called every frame while hosting. Joins the thread once it is done.
func poll() -> void:
	if _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null


func done() -> bool:
	return _thread == null


## Joins any abandoned discovery thread that has since finished. The scene
## calls it every frame; it costs nothing when there are none.
static func reap() -> void:
	for i in range(_orphans.size() - 1, -1, -1):
		if not _orphans[i].is_alive():
			_orphans[i].wait_to_finish()
			_orphans.remove_at(i)


func _report(state_: String, status_: String, public_ := "") -> void:
	_mutex.lock()
	state = state_
	status = status_
	public = public_
	_mutex.unlock()


func _work() -> void:
	var u := UPNP.new()
	var r := u.discover(int(Config.NET.upnp_timeout_ms), 2, "InternetGatewayDevice")
	# `discover` answers SUCCESS having found nothing at all when the router
	# has UPnP switched off, and `get_gateway` then raises an engine error
	# rather than returning null. Counting the devices first is what keeps a
	# switched-off router a sentence on screen instead of an error in the log.
	var gateway: UPNPDevice = null
	if r == UPNP.UPNP_RESULT_SUCCESS and u.get_device_count() > 0:
		gateway = u.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		var by_hand := _outside()
		if by_hand.is_empty():
			_report("none", "no UPnP router answered — friends on the internet need a forwarded port, or a VPN")
		else:
			_report("none", by_hand_note(port, "UPnP is off at your router"), by_hand)
		return
	if _closing:
		return                                  # nobody is hosting any more
	var m := u.add_port_mapping(port, port, "DEADLINE", "UDP", int(Config.NET.upnp_lease_s))
	if m != UPNP.UPNP_RESULT_SUCCESS:
		var refused := _outside()
		if refused.is_empty():
			_report("refused", "the router refused to open UDP %d (%s) — forward it by hand, or use a VPN" % [port, reason(m)])
		else:
			_report("refused", by_hand_note(port, "the router refused: %s" % reason(m)), refused)
		return
	if _closing:
		u.delete_port_mapping(port, "UDP")
		return
	_upnp = u
	_mapped = true
	var ip := u.query_external_address()
	if not ip.is_empty():
		_report("open", "open to the internet — friends type this address", "%s:%d" % [ip, port])
		return
	# The router opened the port and then would not name itself. It is open
	# either way, so ask the internet what it sees instead of showing nothing.
	var seen := _outside()
	if seen.is_empty():
		_report("open", "the router opened UDP %d, but would not say its public address" % port)
	else:
		_report("open", "open to the internet — friends type this address", seen)


## The address the internet would reach this machine's port at, asked of a
## STUN server rather than of the router. "" when none answers.
##
## STUN sees the source port of its own socket, never the game's, so only the
## IP half is its to report; the port is ours. That pairing is right exactly
## when the mapping is one-to-one, which is what UPnP and a hand-written
## forward both make and what ENet needs anyway. It is a guess about the
## router's rules, so every sentence that carries one says so.
func _outside() -> String:
	if _closing:
		return ""
	var ip := Stun.public_ip(Config.NET.stun, int(Config.NET.stun_timeout_ms))
	return "" if ip.is_empty() else "%s:%d" % [ip, port]




## The sentence that goes beside an address STUN found rather than the router.
## Short on purpose, and the caveat leads: the row appends "click to copy"
## and the panel clips the tail, so what is lost is the cause, not the warning.
##
## It hedges because it has to. STUN reports the address the internet sees,
## which is true whether or not anything is listening behind it — only a
## forward makes it dialable, and this cannot see one.
static func by_hand_note(port_: int, cause: String) -> String:
	return "works only if you forwarded UDP %d — %s" % [port_, cause]


## Takes the mapping down again. Never waits on a router: a discovery still
## running is orphaned and cleans up after itself.
func close() -> void:
	_closing = true
	if _thread != null:
		if _thread.is_alive():
			_orphans.append(_thread)
		else:
			_thread.wait_to_finish()
		_thread = null
	if _mapped and _upnp != null:
		_upnp.delete_port_mapping(port, "UDP")
	_mapped = false
	_upnp = null
	_report("closed", "")


## What the router's answer means, for the one line on screen.
static func reason(code: int) -> String:
	match code:
		UPNP.UPNP_RESULT_NOT_AUTHORIZED: return "not authorised"
		UPNP.UPNP_RESULT_PORT_MAPPING_NOT_FOUND: return "mapping not found"
		UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MAPPING: return "another device has that port"
		UPNP.UPNP_RESULT_ACTION_FAILED: return "action failed"
		UPNP.UPNP_RESULT_NO_GATEWAY: return "no gateway"
		UPNP.UPNP_RESULT_NO_DEVICES: return "no devices"
	return "error %d" % code


## The addresses friends on the same network type: every IPv4 this machine
## has that is not loopback or link-local, with the port on.
static func lan_addresses(port_: int) -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.contains(":"):
			continue                              # IPv6: right, but nobody types it
		if s.begins_with("127.") or s.begins_with("169.254.") or s == "0.0.0.0":
			continue
		out.append("%s:%d" % [s, port_])
	return out
