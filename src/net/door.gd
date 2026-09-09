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
	if r != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		_report("none", "no UPnP router answered — friends on the internet need a forwarded port, or a VPN")
		return
	if _closing:
		return                                  # nobody is hosting any more
	var m := u.add_port_mapping(port, port, "DEADLINE", "UDP", int(Config.NET.upnp_lease_s))
	if m != UPNP.UPNP_RESULT_SUCCESS:
		_report("refused", "the router refused to open UDP %d (%s) — forward it by hand, or use a VPN" % [port, reason(m)])
		return
	if _closing:
		u.delete_port_mapping(port, "UDP")
		return
	_upnp = u
	_mapped = true
	var ip := u.query_external_address()
	if ip.is_empty():
		_report("open", "the router opened UDP %d, but would not say its public address" % port)
	else:
		_report("open", "open to the internet — friends type this address", "%s:%d" % [ip, port])


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
