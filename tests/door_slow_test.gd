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
