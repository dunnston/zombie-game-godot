extends TestCase
## Room codes over WebRTC, through the real `WebRTCMultiplayerPeer` with the
## broker and the connection both stood in for: `FakeBroker` is signal.js
## in-process, `FakeRtc` is a connection that finds its partner by the SDP
## it is handed. What is asserted is the handshake: a code, a seat, an
## offer relayed one way and an answer the other, and both hubs reporting a
## connected peer with a link the sessions could use. Bytes over WebRTC
## need the native extension; see webrtc_slow_test.


var broker: FakeBroker


func before_each() -> void:
	broker = FakeBroker.new()
	WebRtcHub.make_connection = func() -> WebRTCPeerConnection: return FakeRtc.new()


func after_each() -> void:
	WebRtcHub.make_connection = Callable()


func _pump(hubs: Array, frames := 12) -> void:
	for i in range(frames):
		for h in hubs:
			(h as WebRtcHub).poll()
		# The fake defers its answers the way the native one does; the
		# runner has no frame loop, so flush the deferred calls by hand.
		await_deferred()


## Deferred calls in a SceneTree-less run only fire when something pumps
## the message queue; `Callable.call_deferred` lands on the main loop's
## next iteration, and the test runner has none. Asking a fresh object to
## do nothing deferred is not enough — so the fake is flushed directly.
func await_deferred() -> void:
	FakeRtc.flush()


func _host() -> WebRtcHub:
	var h := WebRtcHub.new()
	h.signaller = broker.signaller()
	eq(h.host("ws://fake"), "")
	return h


func _guest(code: String) -> WebRtcHub:
	var g := WebRtcHub.new()
	g.signaller = broker.signaller()
	eq(g.join("ws://fake", code), "")
	return g


func test_codes_and_ids() -> void:
	ok(WebRtcHub.is_code("ABC234"))
	ok(not WebRtcHub.is_code("ABC0O1"), "no zero, no O, no one, no I")
	ok(not WebRtcHub.is_code("ABCDE"))
	eq(WebRtcHub.normalise_code(" ab-c2 34 "), "ABC234")
	eq(WebRtcHub.gid_to_id("g1"), 2, "the host is 1; the first guest is 2")
	eq(WebRtcHub.gid_to_id("g3"), 4)
	ok(not WebRtcHub.available(), "no native extension in a bare checkout — the switch stays off")


func test_a_room_opens_and_a_guest_is_seated_through_the_broker() -> void:
	var h := _host()
	_pump([h])
	eq(h.code, "ABCDEF", "the broker handed out a code")
	ok(h.connected(), "a host with a code is open for business")
	var g := _guest("abcdef")
	_pump([h, g], 30)
	eq(g.error, "", g.error)
	eq(h.error, "", h.error)
	ok(h.links.has(2), "the host has a link to guest 2: %s" % str(h.links.keys()))
	ne(g.host_link(), null, "the guest has a link to the host")
	ok(g.connected())
	eq(h.joined, [2])
	# Two more seats, then the broker says full.
	var g2 := _guest("ABCDEF")
	var g3 := _guest("ABCDEF")
	_pump([h, g, g2, g3], 30)
	ok(h.links.has(3) and h.links.has(4), "three guests: %s" % str(h.links.keys()))
	var g4 := _guest("ABCDEF")
	_pump([h, g4], 6)
	eq(g4.error, "that game is full")


func test_a_wrong_code_is_refused_in_words() -> void:
	var g := WebRtcHub.new()
	g.signaller = broker.signaller()
	ne(g.join("ws://fake", "abc"), "", "a short code is refused before dialling")
	var g2 := _guest("QQQQQQ")
	_pump([g2], 6)
	eq(g2.error, "no game with that code")


func test_a_guest_leaving_is_heard_and_the_host_leaving_ends_it() -> void:
	var h := _host()
	_pump([h])
	var g := _guest(h.code)
	_pump([h, g], 30)
	ok(h.links.has(2))
	g.close()
	_pump([h], 6)
	ok(not h.links.has(2), "the broker's guest-left removed the peer: %s" % str(h.links.keys()))
	var g2 := _guest(h.code)
	_pump([h, g2], 6)
	h.close()
	_pump([g2], 6)
	eq(g2.error, "the host left")
