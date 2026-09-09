class_name NetLink
extends RefCounted
## One connection to one peer, as the host and guest sessions see it: bytes
## go in on a channel, bytes come out with the channel they arrived on.
##
## Two things stand behind this. `Loopback` is a pair of in-memory queues,
## optionally lossy and out of order, and is what the tests and the smoke run
## connect a guest through — no socket, no thread, deterministic. `EnetHub`
## (enet_hub.gd) stands a real `ENetMultiplayerPeer` behind the same face.
## Anything else the engine offers as a `MultiplayerPeer` — WebRTC, once the
## extension is dropped in — plugs in the same way.

## Sends `bytes` on `channel` (NetProtocol.RELIABLE or STATE).
func send(_channel: int, _bytes: PackedByteArray) -> void:
	pass


## Everything that has arrived since the last call, oldest first, as
## `[channel, bytes]` pairs.
func receive() -> Array:
	return []


func is_open() -> bool:
	return false


func close() -> void:
	pass


## Where the other end is, for the roster and the log. Loopback says so.
func describe() -> String:
	return "loopback"


## In-memory link. `pair()` makes two joined ends; what one sends the other
## receives on its next `receive()`.
##
## `loss` drops that fraction of STATE packets and `reorder` swaps that
## fraction of adjacent STATE packets, from a seeded stream so a failing test
## fails the same way twice. RELIABLE is never touched: that is what the word
## means, and ENet keeps that promise for real.
class Loopback extends NetLink:
	var other: Loopback = null
	var inbox: Array = []
	var opened := true
	var loss := 0.0
	var reorder := 0.0
	var rng := Rng.new(0x10CA1)
	var sent_bytes := 0
	var received_bytes := 0
	var name := "loopback"

	static func pair(loss_ := 0.0, reorder_ := 0.0) -> Array:
		var a := Loopback.new()
		var b := Loopback.new()
		a.other = b
		b.other = a
		a.name = "host-end"
		b.name = "guest-end"
		for l: Loopback in [a, b]:
			l.loss = loss_
			l.reorder = reorder_
		return [a, b]

	func send(channel: int, bytes: PackedByteArray) -> void:
		if not opened or other == null or not other.opened:
			return
		sent_bytes += bytes.size()
		if channel == NetProtocol.STATE:
			if loss > 0.0 and rng.chance(loss):
				return
			if reorder > 0.0 and not other.inbox.is_empty() and rng.chance(reorder):
				var last: Array = other.inbox.back()
				if int(last[0]) == NetProtocol.STATE:
					other.inbox[other.inbox.size() - 1] = [channel, bytes]
					other.inbox.append(last)
					return
		other.inbox.append([channel, bytes])

	func receive() -> Array:
		var out := inbox
		inbox = []
		for m in out:
			received_bytes += (m[1] as PackedByteArray).size()
		return out

	func is_open() -> bool:
		return opened and other != null

	func close() -> void:
		opened = false
		# The pair is a reference cycle; one end letting go is what lets
		# both be freed once nobody else holds them.
		if other != null:
			other.other = null
		other = null

	func describe() -> String:
		return name
