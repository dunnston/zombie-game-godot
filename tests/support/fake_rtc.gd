class_name FakeRtc
extends WebRTCPeerConnectionExtension
## A WebRTC connection in GDScript, for the tests: two of these find each
## other by the "SDP" they exchange and report themselves connected.
## `WebRTCMultiplayerPeer` — the real engine class — sits on top of them
## exactly as it would on the native ones, so a test of `WebRtcHub`
## exercises the handshake through the broker, the offer and answer, the
## data channels the multiplayer peer creates and the peer-connected signal,
## with nothing native in the project. Bytes are the one thing it cannot
## carry (see the channel below).
##
## An offer's "SDP" is a token; the answering end looks the token up in the
## registry and links the two. ICE candidates are decorative, but one is
## emitted so the hub's relay of them is exercised.

static var _by_token := {}
static var _seq := 0
## Answers the native implementation would give on a later frame. The test
## runner has no frame loop, so `flush()` is what delivers them.
static var _pending: Array = []


static func flush() -> void:
	var batch := _pending
	_pending = []
	for call in batch:
		(call as Callable).call()

var partner: FakeRtc = null
var state: int = WebRTCPeerConnection.STATE_NEW
var channels: Array[FakeChannel] = []
var _token := ""
var _closed := false


func _initialize(_config: Dictionary) -> Error:
	return OK


func _get_connection_state() -> WebRTCPeerConnection.ConnectionState:
	return state as WebRTCPeerConnection.ConnectionState


func _get_gathering_state() -> WebRTCPeerConnection.GatheringState:
	return WebRTCPeerConnection.GATHERING_STATE_COMPLETE


func _get_signaling_state() -> WebRTCPeerConnection.SignalingState:
	return WebRTCPeerConnection.SIGNALING_STATE_STABLE


func _create_data_channel(label: String, config: Dictionary) -> WebRTCDataChannel:
	var ch := FakeChannel.new()
	ch.label_ = label
	ch.id_ = int(config.get("id", channels.size()))
	ch.owner_ = self
	channels.append(ch)
	if partner != null:
		_pair_channels()
	return ch


func _create_offer() -> Error:
	_seq += 1
	_token = "fake-offer-%d" % _seq
	_by_token[_token] = self
	# Later, as the native one is: the caller has not hooked the signal up
	# yet when `create_offer` returns.
	_pending.append(_emit_description.bind("offer", _token))
	return OK


func _emit_description(type: String, sdp: String) -> void:
	session_description_created.emit(type, sdp)
	ice_candidate_created.emit("0", 0, "candidate:fake 1 udp 1 127.0.0.1 1 typ host")


func _set_local_description(_type: String, _sdp: String) -> Error:
	return OK


func _set_remote_description(type: String, sdp: String) -> Error:
	if type == "offer":
		var other: FakeRtc = _by_token.get(sdp, null)
		if other == null:
			return ERR_INVALID_PARAMETER
		_link(other)
		_pending.append(_emit_description.bind("answer", "fake-answer-for-" + sdp))
	elif type == "answer":
		pass                                    # already linked by the offer side
	return OK


func _link(other: FakeRtc) -> void:
	partner = other
	other.partner = self
	_pair_channels()
	state = WebRTCPeerConnection.STATE_CONNECTED
	other.state = WebRTCPeerConnection.STATE_CONNECTED


## Channels are paired by id, the way negotiated channels are.
func _pair_channels() -> void:
	if partner == null:
		return
	for a in channels:
		for b in partner.channels:
			if a.id_ == b.id_:
				a.partner = b
				b.partner = a


func _add_ice_candidate(_sdp_mid_name: String, _sdp_mline_index: int, _sdp_name: String) -> Error:
	return OK


func _poll() -> Error:
	return OK


func _close() -> void:
	_closed = true
	state = WebRTCPeerConnection.STATE_CLOSED
	if partner != null and partner.state != WebRTCPeerConnection.STATE_CLOSED:
		partner.state = WebRTCPeerConnection.STATE_CLOSED


## A data channel over an in-memory queue.
class FakeChannel extends WebRTCDataChannelExtension:
	var label_ := ""
	var id_ := 0
	var owner_: FakeRtc = null
	var partner: FakeChannel = null
	var inbox: Array[PackedByteArray] = []

	func _get_ready_state() -> WebRTCDataChannel.ChannelState:
		if owner_ != null and owner_.state == WebRTCPeerConnection.STATE_CONNECTED and partner != null:
			return WebRTCDataChannel.STATE_OPEN
		if owner_ != null and owner_.state == WebRTCPeerConnection.STATE_CLOSED:
			return WebRTCDataChannel.STATE_CLOSED
		return WebRTCDataChannel.STATE_CONNECTING

	func _get_label() -> String:
		return label_

	func _get_id() -> int:
		return id_

	func _is_ordered() -> bool:
		return true

	func _is_negotiated() -> bool:
		return true

	func _get_max_packet_life_time() -> int:
		return -1

	func _get_max_retransmits() -> int:
		return -1

	func _get_protocol() -> String:
		return ""

	func _get_write_mode() -> WebRTCDataChannel.WriteMode:
		return WebRTCDataChannel.WRITE_MODE_BINARY

	func _set_write_mode(_mode: WebRTCDataChannel.WriteMode) -> void:
		pass

	func _was_string_packet() -> bool:
		return false

	func _get_buffered_amount() -> int:
		return 0

	func _poll() -> Error:
		return OK

	func _close() -> void:
		pass

	func _get_available_packet_count() -> int:
		return inbox.size()

	func _get_max_packet_size() -> int:
		return 65535

	## The engine hands this layer raw pointers, which a script cannot fill:
	## bytes do not cross a fake channel. The handshake and the connection
	## are what this double is for; the byte path over real WebRTC is tested
	## once `tools/fetch-webrtc` has put the native extension in the project.
	func _get_packet(_r_buffer: int, _r_buffer_size: int) -> Error:
		return ERR_UNAVAILABLE

	func _put_packet(_p_buffer: int, _p_buffer_size: int) -> Error:
		return ERR_UNAVAILABLE
