class_name EnetHub
extends RefCounted
## A real socket behind the `NetLink` face. One `ENetMultiplayerPeer` serves
## every connection on this machine — a host's listening port, or a guest's
## single dial-out — and the hub deals its packets out to one `EnetLink` per
## remote peer.
##
## ENet is what the engine ships with: no plugin, no broker, a UDP port. It
## reaches across a LAN, a VPN, or a port somebody forwarded, and that is the
## honest extent of it — it does not punch through two home routers on its
## own. WebRTC would, and is the same `MultiplayerPeer` face once the
## extension is in the project (PROJECT.md §6); this file would not change.
##
## The peer is polled by hand rather than handed to a `MultiplayerAPI`,
## because nothing here is an RPC: every message is a Dictionary the two
## session objects already know how to read.

## User channels 1 and 2 on top of ENet's own three. `create_*` is told two,
## which is what makes `transfer_channel` 1 and 2 valid.
const CHANNELS := 2

var peer: ENetMultiplayerPeer = null
var links := {}                 # peer id -> EnetLink
var joined: Array[int] = []     # peer ids that connected since the last poll
var left: Array[int] = []       # peer ids that dropped since the last poll
var error := ""


## Listens. Returns "" or the reason it could not.
func host(port: int, max_guests: int) -> String:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_guests, CHANNELS)
	if err != OK:
		error = "could not listen on UDP port %d (%s) — is another game already hosting?" % [port, error_string(err)]
		peer = null
		return error
	peer.peer_connected.connect(_on_connected)
	peer.peer_disconnected.connect(_on_disconnected)
	return ""


## Dials. The link for the host (peer 1) exists once `connected()` says so.
func join(address: String, port: int) -> String:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, CHANNELS)
	if err != OK:
		error = "could not dial %s:%d (%s)" % [address, port, error_string(err)]
		peer = null
		return error
	peer.peer_connected.connect(_on_connected)
	peer.peer_disconnected.connect(_on_disconnected)
	return ""


func connecting() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING


func connected() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## The guest's one link — to the host, peer 1 — or null until the dial lands.
func host_link() -> EnetLink:
	return links.get(1, null)


func _on_connected(id: int) -> void:
	var l := EnetLink.new()
	l.hub = self
	l.peer_id = id
	links[id] = l
	joined.append(id)


func _on_disconnected(id: int) -> void:
	var l: EnetLink = links.get(id, null)
	if l != null:
		l.opened = false
	links.erase(id)
	left.append(id)


## Pumps the socket and deals every packet to its link. Call once per step,
## before the session reads its links.
func poll() -> void:
	if peer == null:
		return
	# A peer that has hung up (or never got through) is inactive, and ENet
	# refuses to poll an inactive one. Its status says so first.
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if links.is_empty() and error.is_empty():
			error = "no answer"
		for l: EnetLink in links.values():
			l.opened = false
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var ch := peer.get_packet_channel()
		var bytes := peer.get_packet()
		var l: EnetLink = links.get(from, null)
		if l != null:
			l.inbox.append([ch, bytes])


func send_to(id: int, channel: int, bytes: PackedByteArray) -> void:
	if peer == null or not links.has(id):
		return
	peer.set_target_peer(id)
	peer.set_transfer_channel(channel)
	peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE if channel == NetProtocol.RELIABLE
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	peer.put_packet(bytes)


func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	for l: EnetLink in links.values():
		l.opened = false
		l.hub = null                    # break the cycle so both can be freed
	links.clear()


## One remote peer.
class EnetLink extends NetLink:
	var hub: EnetHub
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
