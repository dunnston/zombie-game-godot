extends TestCase
## The real broker under Node, the real WebSocket, and — if the native
## extension is in the project — real WebRTC on localhost, with a guest
## walking over it. Without the extension the connection is `FakeRtc`, and
## what is proved is the wire to the broker: it is `server/signal.js`
## itself that answers here, not a stand-in.
##
## Needs `node` on PATH and `npm install` run in `server/`; the test does the
## install itself the first time, which needs the network once.

const DT := 1.0 / 60.0

var _pid := -1
var _port := 0


func before_each() -> void:
	NetGuest.reuse_world = TestCase.world()
	if not WebRtcHub.available():
		WebRtcHub.make_connection = func() -> WebRTCPeerConnection: return FakeRtc.new()


func after_each() -> void:
	NetGuest.reuse_world = null
	WebRtcHub.make_connection = Callable()
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1


func _start_broker() -> bool:
	var server := ProjectSettings.globalize_path("res://server")
	if not DirAccess.dir_exists_absolute(server.path_join("node_modules")):
		var out := []
		var exe := "npm"
		var args := ["install", "--no-audit", "--no-fund", "--prefix", server]
		# On Windows npm is `npm.cmd`, a batch file CreateProcess will not
		# launch by bare name; cmd.exe resolves it. Node is a real .exe, and
		# stays a direct child below so `OS.kill` reaches it.
		if OS.get_name() == "Windows":
			exe = "cmd.exe"
			args = ["/c", "npm"] + args
		var code := OS.execute(exe, args, out, true)
		if code != 0:
			_fail("npm install in server/ failed (%d): %s" % [code, "".join(out).right(300)])
			return false
	_port = 8800 + (Time.get_ticks_msec() % 100)
	OS.set_environment("PORT", str(_port))
	_pid = OS.create_process("node", [server.path_join("signal.js")])
	if _pid <= 0:
		_fail("could not start node — is it on PATH?")
		return false
	OS.delay_msec(600)                          # a moment to bind the port
	return true


func _flush() -> void:
	if not WebRtcHub.available():
		FakeRtc.flush()


func test_the_real_broker_seats_a_guest() -> void:
	if not _start_broker():
		return
	var url := "ws://127.0.0.1:%d" % _port
	var h := WebRtcHub.new()
	eq(h.host(url), "")
	var t0 := Time.get_ticks_msec()
	while h.code.is_empty() and h.error.is_empty() and Time.get_ticks_msec() - t0 < 5000:
		h.poll()
		_flush()
		OS.delay_msec(5)
	eq(h.error, "", h.error)
	ok(WebRtcHub.is_code(h.code), "the broker handed out a code: '%s'" % h.code)
	var g := WebRtcHub.new()
	eq(g.join(url, h.code.to_lower()), "")
	t0 = Time.get_ticks_msec()
	while (not h.links.has(2) or g.host_link() == null) and g.error.is_empty() and h.error.is_empty() \
			and Time.get_ticks_msec() - t0 < 8000:
		h.poll()
		g.poll()
		_flush()
		OS.delay_msec(5)
	eq(g.error, "", g.error)
	ok(h.links.has(2), "the host has a link to the guest: %s" % str(h.links.keys()))
	ne(g.host_link(), null, "the guest has a link to the host (%s)" % g.status)
	if not WebRtcHub.available():
		print("webrtc: handshake through the real broker with a fake connection; bytes need tools/fetch-webrtc")
		h.close()
		g.close()
		return
	# The native extension is here: a session over real WebRTC, on localhost.
	var sim := TestCase.new_sim()
	var host := NetHost.new(sim, "Ryan")
	host.attach(h.links[2])
	var guest := NetGuest.new(g.host_link(), "guest-rtc", "Dee")
	var t := {"host": host, "guest": guest}
	t0 = Time.get_ticks_msec()
	while not guest.joined() and guest.status == "connecting" and Time.get_ticks_msec() - t0 < 8000:
		h.poll()
		g.poll()
		guest.poll()
		guest.tick(DT)
		host.poll()
		sim.tick(DT)
		host.after_tick(DT)
		sim.events.clear()
		host.on_events_cleared()
		OS.delay_msec(2)
	ok(guest.joined(), "joined over WebRTC: %s %s" % [guest.status, guest.reason])
	if guest.joined():
		var gp := sim.player_by_identity("guest-rtc")
		var plot := TestCase.tile_centre(TestCase.clear_plot(6))
		gp.pos = plot
		guest.me.pos = plot
		guest.me.intent.mx = 1.0
		for i in range(90):
			h.poll()
			g.poll()
			guest.poll()
			guest.tick(DT)
			host.poll()
			sim.tick(DT)
			host.after_tick(DT)
			sim.events.clear()
			host.on_events_cleared()
			OS.delay_msec(1)
		gt(gp.pos.x - plot.x, 60.0, "walked over WebRTC")
		ok(guest.me.pos.distance_to(gp.pos) < Config.NET.snap_over)
	h.close()
	g.close()
	ok(t != null)
