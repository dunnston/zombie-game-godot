extends TestCase
## The UPnP door. There is no router in a test, so what is asserted is that
## asking for one comes back — in words, within the timeout, on its thread —
## rather than hanging the host at START HOSTING. The happy path needs a
## real router and is the owner's to see on the HOST page.


func test_no_router_is_an_answer_not_a_hang() -> void:
	var door := NetDoor.new()
	var t0 := Time.get_ticks_msec()
	door.open(Config.NET.port)
	ok(not door.done(), "discovery runs on a thread, not on the caller")
	eq(door.state, "asking")
	# Discovery can outlast its own timeout by a few seconds on a machine
	# with no route out: the multicast has to fail, then each fallback.
	while not door.done() and Time.get_ticks_msec() - t0 < 20000:
		door.poll()
		OS.delay_msec(20)
	ok(door.done(), "the thread finished within twenty seconds")
	ok(door.state in ["none", "refused", "open"], "an answer: %s" % door.state)
	ok(not door.status.is_empty(), "with a sentence for the screen")
	if door.state == "open":
		ok(door.public.ends_with(":%d" % Config.NET.port))
	door.close()
	eq(door.state, "closed")
	# Closing a door still asking does not wait for the router.
	var early := NetDoor.new()
	early.open(Config.NET.port)
	var t1 := Time.get_ticks_msec()
	early.close()
	ok(Time.get_ticks_msec() - t1 < 500, "close did not block on discovery")
	eq(early.state, "closed")
	t1 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 20000:
		NetDoor.reap()
		if NetDoor._orphans.is_empty():
			break
		OS.delay_msec(20)
	ok(NetDoor._orphans.is_empty(), "the orphaned thread was reaped")


func test_lan_addresses_are_typeable() -> void:
	for a in NetDoor.lan_addresses(27333):
		ok(a.ends_with(":27333"), a)
		ok(not a.begins_with("127."), "loopback is not an address a friend can dial")
		ok(not a.contains("::"), "no IPv6")
	eq(NetDoor.reason(UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MAPPING), "another device has that port")


func test_stun_finds_the_public_address() -> void:
	# The real thing, against a public server. A machine with no route out
	# has nothing to assert and says so rather than failing the suite.
	var ip := Stun.public_ip(Config.NET.stun, int(Config.NET.stun_timeout_ms))
	if ip.is_empty():
		ok(true, "no STUN server answered — offline, or UDP 3478 is blocked")
		return
	ok(ip.is_valid_ip_address(), "an address, not a fragment: %s" % ip)
	ok(not ip.contains(":"), "IPv4")
	ok(not ip.begins_with("10.") and not ip.begins_with("192.168.") and not ip.begins_with("127."),
		"what the internet sees is not a LAN address: %s" % ip)


func test_a_door_that_upnp_could_not_open_still_names_an_address() -> void:
	# The owner's own case: UPnP off at the router, UDP 27333 forwarded by
	# hand. Whatever the router says, a `public` that is set has to be
	# something a friend can type — the HOST page turns it into a
	# click-to-copy row and nothing downstream checks it again.
	var door := NetDoor.new()
	door.open(Config.NET.port)
	var t0 := Time.get_ticks_msec()
	while not door.done() and Time.get_ticks_msec() - t0 < 25000:
		door.poll()
		OS.delay_msec(20)
	ok(door.done(), "answered within the timeout even with STUN in the path")
	if not door.public.is_empty():
		var half := door.public.split(":")
		eq(half.size(), 2, "host:port, not a bare address")
		ok(String(half[0]).is_valid_ip_address(), "a dialable host: %s" % door.public)
		eq(int(half[1]), int(Config.NET.port), "the port the host is actually listening on")
		ok(not door.status.is_empty(), "an address never appears without a sentence saying what it is")
	door.close()
