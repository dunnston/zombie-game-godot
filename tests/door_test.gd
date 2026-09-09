extends TestCase
## The door's decisions, without a router. What the door does with the
## router's answer is a choice, and two of those choices are the difference
## between an address a friend can use and one that sends them elsewhere.


func test_a_conflicting_mapping_is_never_advertised() -> void:
	# Another device on this network already holds the external port. The
	# public address reaches them, not this host, so there is nothing here
	# worth handing out — however well STUN answered.
	ok(not NetDoor.may_advertise(UPNP.UPNP_RESULT_CONFLICT_WITH_OTHER_MAPPING),
		"a port another device holds is not this host's to give away")
	# Every other refusal leaves the port unclaimed: the host may still have
	# forwarded it by hand, and the address is worth showing hedged.
	ok(NetDoor.may_advertise(UPNP.UPNP_RESULT_NOT_AUTHORIZED))
	ok(NetDoor.may_advertise(UPNP.UPNP_RESULT_ACTION_FAILED))
	ok(NetDoor.may_advertise(UPNP.UPNP_RESULT_SUCCESS))


func test_the_hedge_leads_and_names_the_port() -> void:
	# The panel clips the tail of a long note, so what survives has to be the
	# caveat: an address shown without it reads as a promise.
	var note := NetDoor.by_hand_note(27333, "UPnP is off at your router")
	ok(note.begins_with("works only if you forwarded"), note)
	ok(note.contains("27333"), "the port a friend has to have forwarded")
	ok(note.contains("UPnP is off at your router"), "and why we are guessing")
	ok(note.length() < 80, "short enough that click-to-copy still fits: %d" % note.length())


func test_a_door_starts_before_it_has_asked_anything() -> void:
	var door := NetDoor.new()
	eq(door.state, "asking")
	eq(door.public, "", "no address until something answers")
	eq(door.use_upnp, bool(Config.NET.upnp), "the config decides, and a test can override it")
