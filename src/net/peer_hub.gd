class_name PeerHub
extends RefCounted
## A `MultiplayerPeer` behind the `NetLink` face. One peer serves every
## connection on this machine — a host's listening port or room, or a
## guest's single dial-out — and the hub deals its packets out to one
## `PeerLink` per remote peer.
##
## ENet (`EnetHub`) and WebRTC (`WebRtcHub`) both stand behind this. The
## sessions above never learn which: bytes in on a channel, bytes out with
## the channel they came on. The peer is polled by hand rather than handed
## to a `MultiplayerAPI`, because nothing here is an RPC.

var peer: MultiplayerPeer = null
var links := {}                 # peer id -> PeerLink
var joined: Array[int] = []     # peer ids that connected since the last poll
var left: Array[int] = []       # peer ids that dropped since the last poll
var error := ""
var _ever_connected := false


func _wire() -> void:
	peer.peer_connected.connect(_on_connected)
	peer.peer_disconnected.connect(_on_disconnected)


func connecting() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING


func connected() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## The guest's one link — to the host, peer 1 — or null until the dial lands.
func host_link() -> PeerLink:
	return links.get(1, null)


func _on_connected(id: int) -> void:
	var l := PeerLink.new()
	l.hub = self
	l.peer_id = id
	links[id] = l
	joined.append(id)
	_ever_connected = true


func _on_disconnected(id: int) -> void:
	var l: PeerLink = links.get(id, null)
	if l != null:
		l.opened = false
	links.erase(id)
	left.append(id)


## Pumps the peer and deals every packet to its link. Call once per step,
## before the session reads its links. Subclasses pump their own signalling
## first and then call this.
func poll() -> void:
	if peer == null:
		return
	# A peer that has hung up (or never got through) is inactive, and the
	# engine refuses to poll an inactive one. Its status says so first.
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		# "No answer" is for a dial nobody picked up. A line that was up and
		# dropped is the link's business: it closes, and the session says so.
		if not _ever_connected and error.is_empty():
			error = "no answer"
		for l: PeerLink in links.values():
			l.opened = false
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var ch := _incoming_channel()
		var bytes := peer.get_packet()
		var l: PeerLink = links.get(from, null)
		if l != null:
			l.inbox.append([ch, bytes])


## Which of the protocol's two channels the packet at the head of the queue
## arrived on. Read before `get_packet`.
func _incoming_channel() -> int:
	return peer.get_packet_channel()


## The peer's own channel number for one of ours.
func _outgoing_channel(channel: int) -> int:
	return channel


func send_to(id: int, channel: int, bytes: PackedByteArray) -> void:
	if peer == null or not links.has(id):
		return
	peer.set_target_peer(id)
	peer.set_transfer_channel(_outgoing_channel(channel))
	peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE if channel == NetProtocol.RELIABLE
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	peer.put_packet(bytes)


func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	for l: PeerLink in links.values():
		l.opened = false
		l.hub = null                    # break the cycle so both can be freed
	links.clear()


## One remote peer.
class PeerLink extends NetLink:
	var hub: PeerHub
	var peer_id := 0
	var inbox: Array = []
	var opened := true

	func send(channel: int, bytes: PackedByteArray) -> void:
		if opened and hub != null:
			hub.send_to(peer_id, channel, bytes)

	func receive() -> Array:
		var out := inbox
		inbox = []
		return out

	func is_open() -> bool:
		return opened

	func close() -> void:
		if opened and hub != null and hub.peer != null \
				and hub.peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			hub.peer.disconnect_peer(peer_id)
		opened = false

	func describe() -> String:
		return "peer %d" % peer_id
