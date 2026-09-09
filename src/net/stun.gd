class_name Stun
extends RefCounted
## What the internet sees when this machine speaks: one UDP question to a
## public STUN server, one answer carrying the address the packet came from.
##
## `NetDoor` asks when UPnP is off or says no. STUN opens nothing — the port
## still has to be forwarded, by the router or by hand — but it is the
## difference between a HOST page that says "friends need a forwarded port"
## and one with a line on it the owner can copy. Nobody remembers their own
## public address, and it changes.
##
## Blocking: resolve, send, wait. Only ever called from `NetDoor`'s thread.
##
## RFC 5389 §6 and §15.2. The wire is twenty bytes out and one attribute back.

const COOKIE := 0x2112A442
const BINDING_REQUEST := 0x0001
const BINDING_RESPONSE := 0x0101
const XOR_MAPPED_ADDRESS := 0x0020
## What servers older than RFC 5389 answer with. Same shape, not obfuscated.
const MAPPED_ADDRESS := 0x0001
const FAMILY_IPV4 := 0x01
const HEADER := 20
const DEFAULT_PORT := 3478


## The public IPv4 this machine appears to have, or "" if nothing answered.
## `servers` is `Config.NET.stun`, which is an ICE server list: entries that
## are not `stun:` — a `turn:` relay, once one is paid for — are skipped
## rather than dialled, because TURN wants credentials and answers a
## different question.
static func public_ip(servers: Array, timeout_ms: int) -> String:
	for s in servers:
		var ip := ask(String(s), timeout_ms)
		if not ip.is_empty():
			return ip
	return ""


## One server, one question. "stun:host" or "stun:host:port".
static func ask(url: String, timeout_ms: int) -> String:
	if not url.begins_with("stun:"):
		return ""
	var rest := url.substr(5)
	var colon := rest.rfind(":")
	var host := rest if colon < 0 else rest.substr(0, colon)
	var port := DEFAULT_PORT if colon < 0 else int(rest.substr(colon + 1))
	if host.is_empty() or port <= 0:
		return ""
	var ip := host if host.is_valid_ip_address() else IP.resolve_hostname(host, IP.TYPE_IPV4)
	if ip.is_empty():
		return ""
	var txid := Crypto.new().generate_random_bytes(12)
	var sock := PacketPeerUDP.new()
	if sock.set_dest_address(ip, port) != OK or sock.put_packet(request(txid)) != OK:
		sock.close()
		return ""
	var out := ""
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		if sock.get_available_packet_count() > 0:
			out = parse(sock.get_packet(), txid)
			if not out.is_empty():
				break
		else:
			OS.delay_msec(10)
	sock.close()
	return out


## A binding request: a type, a zero length, the cookie, and the transaction
## id that tells our answer apart from anyone else's on this socket.
static func request(txid: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(HEADER)
	_put16(b, 0, BINDING_REQUEST)
	_put16(b, 2, 0)
	_put32(b, 4, COOKIE)
	for i in mini(txid.size(), 12):
		b[8 + i] = txid[i]
	return b


## The address out of a binding response, or "" if this is not one, is not
## ours, or carries nothing we can read. Pure, so the wire format is tested
## without a network.
static func parse(buf: PackedByteArray, txid: PackedByteArray) -> String:
	if buf.size() < HEADER or _u16(buf, 0) != BINDING_RESPONSE or _u32(buf, 4) != COOKIE:
		return ""
	if txid.size() == 12 and buf.slice(8, HEADER) != txid:
		return ""                               # somebody else's answer
	# Trailing bytes past the declared length are not ours to read.
	var end: int = mini(HEADER + _u16(buf, 2), buf.size())
	var at := HEADER
	while at + 4 <= end:
		var kind := _u16(buf, at)
		var size := _u16(buf, at + 2)
		var val := at + 4
		if val + size > end:
			break                               # truncated: nothing to trust after it
		if (kind == XOR_MAPPED_ADDRESS or kind == MAPPED_ADDRESS) and size >= 8 and buf[val + 1] == FAMILY_IPV4:
			var a := _u32(buf, val + 4)
			if kind == XOR_MAPPED_ADDRESS:
				a ^= COOKIE                     # §15.2: obfuscated against naive NAT rewriting
			return "%d.%d.%d.%d" % [(a >> 24) & 255, (a >> 16) & 255, (a >> 8) & 255, a & 255]
		at = val + size + (4 - size % 4) % 4    # attributes sit on four-byte boundaries
	return ""


# STUN is big-endian throughout; PackedByteArray's own encoders are not.
static func _u16(b: PackedByteArray, at: int) -> int:
	return (b[at] << 8) | b[at + 1]


static func _u32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


static func _put16(b: PackedByteArray, at: int, v: int) -> void:
	b[at] = (v >> 8) & 255
	b[at + 1] = v & 255


static func _put32(b: PackedByteArray, at: int, v: int) -> void:
	b[at] = (v >> 24) & 255
	b[at + 1] = (v >> 16) & 255
	b[at + 2] = (v >> 8) & 255
	b[at + 3] = v & 255
