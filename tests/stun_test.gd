extends TestCase
## The STUN wire, without a network. `Stun.parse` is the half that can be
## wrong quietly — a misread address is a line the owner pastes to a friend
## that goes nowhere — so the bytes are built here by hand and read back.


## A binding response carrying one address attribute, the way a server sends
## it: header, cookie, transaction id, then the attribute.
func _response(txid: PackedByteArray, kind: int, ip: Array, port: int, cookie := Stun.COOKIE) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(Stun.HEADER + 12)
	b[0] = 0x01
	b[1] = 0x01                                 # binding response
	b[2] = 0x00
	b[3] = 12                                   # one 12-byte attribute follows
	b[4] = (cookie >> 24) & 255
	b[5] = (cookie >> 16) & 255
	b[6] = (cookie >> 8) & 255
	b[7] = cookie & 255
	for i in 12:
		b[8 + i] = txid[i]
	var at := Stun.HEADER
	b[at] = (kind >> 8) & 255
	b[at + 1] = kind & 255
	b[at + 2] = 0
	b[at + 3] = 8                               # reserved, family, port, address
	b[at + 4] = 0
	b[at + 5] = Stun.FAMILY_IPV4
	var a: int = (int(ip[0]) << 24) | (int(ip[1]) << 16) | (int(ip[2]) << 8) | int(ip[3])
	var p := port
	if kind == Stun.XOR_MAPPED_ADDRESS:
		a ^= Stun.COOKIE
		p ^= (Stun.COOKIE >> 16) & 0xFFFF
	b[at + 6] = (p >> 8) & 255
	b[at + 7] = p & 255
	b[at + 8] = (a >> 24) & 255
	b[at + 9] = (a >> 16) & 255
	b[at + 10] = (a >> 8) & 255
	b[at + 11] = a & 255
	return b


func _txid() -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(12)
	for i in 12:
		t[i] = i + 1
	return t


func test_xor_mapped_address_is_unmasked() -> void:
	var t := _txid()
	eq(Stun.parse(_response(t, Stun.XOR_MAPPED_ADDRESS, [199, 250, 232, 186], 41234), t), "199.250.232.186")
	# The obfuscation is the whole point: the bytes on the wire are not the
	# address, so a parser that forgot to XOR would read something else.
	var raw := _response(t, Stun.XOR_MAPPED_ADDRESS, [199, 250, 232, 186], 41234)
	ok(raw[Stun.HEADER + 8] != 199, "the address is masked on the wire")
	# An octet that XORs to zero, and the high bit, both survive the trip.
	eq(Stun.parse(_response(t, Stun.XOR_MAPPED_ADDRESS, [0x21, 0x12, 0xA4, 0x42], 1), t), "33.18.164.66")
	eq(Stun.parse(_response(t, Stun.XOR_MAPPED_ADDRESS, [255, 0, 128, 1], 1), t), "255.0.128.1")


func test_plain_mapped_address_still_reads() -> void:
	var t := _txid()
	eq(Stun.parse(_response(t, Stun.MAPPED_ADDRESS, [8, 8, 4, 4], 3478), t), "8.8.4.4")


func test_an_answer_that_is_not_ours_is_refused() -> void:
	var t := _txid()
	var other := _txid()
	other[0] = 99
	eq(Stun.parse(_response(other, Stun.XOR_MAPPED_ADDRESS, [1, 2, 3, 4], 1), t), "",
		"another socket's answer is not this host's address")
	eq(Stun.parse(_response(t, Stun.XOR_MAPPED_ADDRESS, [1, 2, 3, 4], 1, 0xDEADBEEF), t), "",
		"a response without the magic cookie is not STUN")


func test_junk_is_not_an_address() -> void:
	var t := _txid()
	eq(Stun.parse(PackedByteArray(), t), "")
	eq(Stun.parse(_response(t, Stun.XOR_MAPPED_ADDRESS, [1, 2, 3, 4], 1).slice(0, 12), t), "",
		"a truncated header reads as nothing, not as a crash")
	# A response whose attribute claims more bytes than arrived.
	var short := _response(t, Stun.XOR_MAPPED_ADDRESS, [1, 2, 3, 4], 1)
	short[Stun.HEADER + 3] = 40
	eq(Stun.parse(short, t), "")
	# A request is not a response.
	eq(Stun.parse(Stun.request(t), t), "")


func test_a_request_is_twenty_bytes_and_carries_the_cookie() -> void:
	var t := _txid()
	var r := Stun.request(t)
	eq(r.size(), Stun.HEADER)
	eq((r[0] << 8) | r[1], Stun.BINDING_REQUEST)
	eq((r[2] << 8) | r[3], 0, "no attributes")
	eq((r[4] << 24) | (r[5] << 16) | (r[6] << 8) | r[7], Stun.COOKIE)
	eq(r.slice(8, 20), t, "the transaction id goes out so the answer can be recognised")


func test_a_turn_server_in_the_ice_list_is_not_dialled() -> void:
	# `Config.NET.stun` is an ICE server list, and the WebRTC runbook has the
	# owner adding a `turn:` entry to it the day a pair of friends cannot
	# connect. TURN wants credentials and answers a different question.
	eq(Stun.ask("turn:relay.example.com:3478", 1), "")
	eq(Stun.ask("", 1), "")
	eq(Stun.ask("stun:", 1), "")
