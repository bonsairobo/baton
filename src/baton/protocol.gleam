//// On-the-wire message format.
////
//// This format serves two functions:
////   1. to route payloads from peer to peer via the relay
////   2. to notify peers of the presence of other peers in the same room
////
//// As such, messages fall into two categories:
////   1. messages originating from a peer
////   2. messages originating from the relay service
////
//// The encoding is fundamentally the same as HTTP: a set of headers separated
//// by newlines, then an empty newline separating the headers from the optional
//// body. Our headers contain metadata and routing information and the body
//// contains the payload.
////
//// ```text
//// <headers>
////
//// <body>
//// ```
////
//// When a message is sent, the sender only needs to include the destination
//// peers, since the sender's peer ID is already known by the relay. The relay
//// then adds the source peer ID to the message before forwarding it to the
//// destination.
////
//// Messages are sent over web sockets, so the application may choose to send
//// text frames or binary frames. In either case, everything preceding the body
//// must be UTF-8 encoded. An arbitrary binary message body may only be sent in
//// a binary frame.
////
//// ## Sent Format
////
//// ```text
//// to: <peer_id_1>
//// to: <peer_id_2>
//// ...
//// to: <peer_id_N>
////
//// <payload>
//// ```
////
//// OR
////
//// ```text
//// broadcast:
////
//// <payload>
//// ```
////
//// where
////   1. The "to" header indicates one recipient of the message.
////   2. Peer IDs are base64-encoded integers randomly assigned by the relay
////      service.
////   3. The "broadcast" header indicates that this message should be sent to
////      all peers in the same room. The value of this header is empty, and
////      that's OK.
////   4. `payload` is the actual content of the message, in any format desired
////      by the application.
////
//// ## Received Format
////
//// Peer messages forward by the relay will look like this when received:
////
//// ```text
//// message_from: <peer_id>
////
//// <payload>
//// ```
////
//// A "peer joined" event sent from the relay:
////
//// ```text
//// peer_joined: <peer_id>
//// ```
////
//// A "peer left" event sent from the relay:
////
//// ```text
//// peer_left: <peer_id>
//// ```

import baton_ffi
import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/result
import gleam/string

/// Identifies a room.
///
/// A `baton` protocol channel only functions within a single room at a time.
pub type RoomId =
  String

pub type RawContent {
  Binary(BitArray)
  Text(String)
}

pub type RawMessage =
  RawContent

pub type RawBody =
  RawContent

pub type PeerId =
  String

/// Generate a random peer ID.
pub fn new_peer_id() -> PeerId {
  let bytes = crypto.strong_random_bytes(16)
  bit_array.base64_encode(bytes, True)
}

/// The sending-side format for a message originating from a peer.
pub type SentPeerMessage {
  SentPeerMessage(to: Destination, content: RawContent)
}

/// Message type received by a peer socket.
pub type PeerSocketMessage {
  FromPeer(ReceivedPeerMessage)
  FromRelay(RoomEvent)
}

/// The receiving-side format for a message originating from a peer.
pub type ReceivedPeerMessage {
  ReceivedPeerMessage(from: PeerId, content: RawContent)
}

/// The destination peers for a single message.
pub type Destination {
  Broadcast
  PeerSet(to: List(PeerId))
}

/// An event that originates from the relay.
pub type RoomEvent {
  /// A peer joined the room.
  PeerJoined(id: PeerId)
  /// A peer left the room.
  PeerLeft(id: PeerId)
}

pub type ParseError {
  InvalidDelimiter
  InvalidHeaderEncoding
  NoRecipients
  UnknownHeader
}

/// Encode a `RoomEvent` as text.
pub fn encode_room_event(event: RoomEvent) -> String {
  case event {
    PeerJoined(id) -> "peer_joined:" <> id
    PeerLeft(id) -> "peer_left:" <> id
  }
}

/// Encode a `ReceivedPeerMessage` as either text or binary, depending on the
/// content type.
///
/// Only the relay server needs this, but it's provided for completeness.
pub fn encode_received_peer_message(message: ReceivedPeerMessage) -> RawMessage {
  let ReceivedPeerMessage(from, content) = message
  case content {
    Binary(body) -> {
      let headers = bit_array.from_string("message_from:" <> from)
      Binary(<<headers:bits, "\n\n":utf8, body:bits>>)
    }
    Text(body) -> {
      let headers = "message_from:" <> from
      Text(headers <> "\n\n" <> body)
    }
  }
}

/// Decode a `PeerSocketMessage` from a text or binary WebSocket message.
///
/// Clients should use this when they receive a message from the relay server.
pub fn decode_peer_socket_message(
  message: RawMessage,
) -> Result(PeerSocketMessage, ParseError) {
  use MessageParts(headers, body) <- result.try(decode_message_parts(message))

  use #(type_key, type_value) <- result.try(
    list.find(headers, fn(header) {
      let #(key, _) = header
      key == "peer_joined" || key == "peer_left" || key == "message_from"
    })
    |> result.replace_error(UnknownHeader),
  )

  case type_key, type_value {
    "peer_joined", peer_id -> {
      Ok(FromRelay(PeerJoined(peer_id)))
    }
    "peer_left", peer_id -> {
      Ok(FromRelay(PeerLeft(peer_id)))
    }
    "message_from", peer_id -> {
      Ok(FromPeer(ReceivedPeerMessage(from: peer_id, content: body)))
    }
    _, _ -> Error(UnknownHeader)
  }
}

/// Encode a text message to other peers.
///
/// Clients should use this when sending messages to the relay service.
pub fn encode_sent_peer_message_as_text(to: Destination, body: String) -> String {
  let headers_text = encode_destination(to)
  headers_text <> "\n\n" <> body
}

/// Encode a binary message to other peers.
///
/// Clients should use this when sending messages to the relay service.
pub fn encode_sent_peer_message_as_binary(
  to: Destination,
  body: BitArray,
) -> BitArray {
  let headers_text = encode_destination(to)
  <<headers_text:utf8, "\n\n":utf8, body:bits>>
}

fn encode_destination(to: Destination) -> String {
  let headers = case to {
    Broadcast -> list.wrap("broadcast:")
    PeerSet(peer_ids) -> list.map(peer_ids, fn(peer_id) { "to: " <> peer_id })
  }
  string.join(headers, "\n")
}

/// Decode a `SentPeerMessage` from a text or binary WebSocket message.
///
/// Only the relay server needs this, but it's provided for completeness.
pub fn decode_sent_peer_message(
  message: RawMessage,
) -> Result(SentPeerMessage, ParseError) {
  use MessageParts(headers, body) <- result.try(decode_message_parts(message))
  use dest <- result.try(decode_destination(headers))
  Ok(SentPeerMessage(dest, body))
}

fn decode_destination(
  headers: List(#(String, String)),
) -> Result(Destination, ParseError) {
  // Conveniently, there are only two schemas for peer message headers.
  case
    list.any(headers, fn(header) {
      let #(key, _) = header
      key == "broadcast"
    })
  {
    True -> Ok(Broadcast)
    False -> {
      // Parse all recipients
      let recipients = list.filter_map(headers, decode_recipient)
      case list.length(recipients) {
        0 -> Error(NoRecipients)
        _ -> Ok(PeerSet(recipients))
      }
    }
  }
}

fn decode_recipient(header: #(String, String)) -> Result(PeerId, Nil) {
  let #(key, value) = header
  case key == "to" {
    True -> Ok(value)
    False -> Error(Nil)
  }
}

type MessageParts {
  MessageParts(headers: List(#(String, String)), body: RawContent)
}

fn decode_message_parts(message: RawMessage) -> Result(MessageParts, ParseError) {
  use #(headers_text, body) <- result.try(split_headers_and_body(message))
  let headers = decode_headers(headers_text)
  Ok(MessageParts(headers, body))
}

fn decode_headers(headers_text: String) -> List(#(String, String)) {
  string.split(headers_text, "\n")
  |> list.filter_map(fn(line) {
    use #(key, value) <- result.try(string.split_once(line, ":"))
    Ok(#(string.trim(key), string.trim(value)))
  })
}

fn split_headers_and_body(
  message: RawMessage,
) -> Result(#(String, RawBody), ParseError) {
  case message {
    Binary(bin) -> {
      case baton_ffi.binary_split_once(bin, <<"\n\n":utf8>>) {
        Ok(#(headers_bin, body_bin)) -> {
          use headers_text <- result.try(decode_headers_string(headers_bin))
          Ok(#(headers_text, Binary(body_bin)))
        }
        Error(Nil) -> {
          // No body, only headers.
          use headers_text <- result.try(decode_headers_string(bin))
          Ok(#(headers_text, Binary(<<>>)))
        }
      }
    }
    Text(text) -> {
      case string.split_once(text, "\n\n") {
        Ok(#(headers_text, body_text)) -> {
          Ok(#(headers_text, Text(body_text)))
        }
        Error(Nil) -> {
          Ok(#(text, Text("")))
        }
      }
    }
  }
}

fn decode_headers_string(bin: BitArray) -> Result(String, ParseError) {
  bit_array.to_string(bin)
  |> result.replace_error(InvalidHeaderEncoding)
}
