class_name EnetHub
extends PeerHub
## A UDP socket behind the `NetLink` face: `ENetMultiplayerPeer`, which the
## engine ships with. No plugin, no broker, a port. It reaches across a LAN,
## a VPN, or a port the router opened (`NetDoor`), and that is the honest
## extent of it — it does not punch through two home routers on its own.
## `WebRtcHub` is the sibling for that.

## User channels 1 and 2 on top of ENet's own three. `create_*` is told two,
## which is what makes `transfer_channel` 1 and 2 valid — and they are the
## protocol's own channel numbers, so nothing is mapped.
const CHANNELS := 2


## Listens. Returns "" or the reason it could not.
func host(port: int, max_guests: int) -> String:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, max_guests, CHANNELS)
	if err != OK:
		error = "could not listen on UDP port %d (%s) — is another game already hosting?" % [port, error_string(err)]
		return error
	peer = p
	_wire()
	return ""


## Dials. The link for the host (peer 1) exists once `connected()` says so.
func join(address: String, port: int) -> String:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(address, port, CHANNELS)
	if err != OK:
		error = "could not dial %s:%d (%s)" % [address, port, error_string(err)]
		return error
	peer = p
	_wire()
	return ""
