import baton/protocol.{
  Binary, Broadcast, FromRelay, PeerJoined, PeerLeft, PeerSet, Text,
}
import baton_ffi
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn binary_split_test() {
  baton_ffi.binary_split(<<"hello\ngoodbye":utf8>>, <<"\n":utf8>>)
  |> should.equal([<<"hello":utf8>>, <<"goodbye":utf8>>])
}

pub fn sent_broadcast_text_message_round_trip_test() {
  let encoded = protocol.encode_sent_peer_message_as_text(Broadcast, "hello")

  protocol.decode_sent_peer_message(Text(encoded))
  |> should.equal(Ok(protocol.SentPeerMessage(Broadcast, Text("hello"))))
}

pub fn sent_broadcast_binary_message_round_trip_test() {
  let encoded =
    protocol.encode_sent_peer_message_as_binary(Broadcast, <<0, 1, 2, 3>>)

  protocol.decode_sent_peer_message(Binary(encoded))
  |> should.equal(
    Ok(protocol.SentPeerMessage(Broadcast, Binary(<<0, 1, 2, 3>>))),
  )
}

pub fn sent_peer_set_text_message_round_trip_test() {
  let peer_a = protocol.new_peer_id()
  let peer_b = protocol.new_peer_id()
  let dest = PeerSet([peer_a, peer_b])
  let encoded = protocol.encode_sent_peer_message_as_text(dest, "hello")

  protocol.decode_sent_peer_message(Text(encoded))
  |> should.equal(Ok(protocol.SentPeerMessage(dest, Text("hello"))))
}

pub fn received_text_message_round_trip_test() {
  let from_peer = protocol.new_peer_id()
  let received = protocol.ReceivedPeerMessage(from_peer, Text("hello"))
  let encoded = protocol.encode_received_peer_message(received)

  protocol.decode_peer_socket_message(encoded)
  |> should.equal(Ok(protocol.FromPeer(received)))
}

pub fn received_binary_message_round_trip_test() {
  let from_peer = protocol.new_peer_id()
  let received = protocol.ReceivedPeerMessage(from_peer, Binary(<<0, 1, 2, 3>>))
  let encoded = protocol.encode_received_peer_message(received)

  protocol.decode_peer_socket_message(encoded)
  |> should.equal(Ok(protocol.FromPeer(received)))
}

pub fn peer_joined_round_trip_test() {
  let event = PeerJoined(protocol.new_peer_id())
  let encoded = protocol.encode_room_event(event)

  protocol.decode_peer_socket_message(Text(encoded))
  |> should.equal(Ok(FromRelay(event)))
}

pub fn peer_left_round_trip_test() {
  let event = PeerLeft(protocol.new_peer_id())
  let encoded = protocol.encode_room_event(event)

  protocol.decode_peer_socket_message(Text(encoded))
  |> should.equal(Ok(FromRelay(event)))
}
