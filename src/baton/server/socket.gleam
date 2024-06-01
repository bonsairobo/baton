//// Logic for the actor that manages a peer's web socket.

import baton/protocol.{
  type PeerId, type PeerSocketMessage, type RoomId, type SentPeerMessage,
  FromPeer, FromRelay, SentPeerMessage,
}
import baton/server/mist_types.{type MistRequest, type MistResponse}
import baton/server/relay.{
  type RelayMessage, AddPeer, RelayPeerMessage, RemovePeer,
}
import gleam/erlang/process.{type Subject}
import gleam/function.{identity}
import gleam/option.{Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import logging
import mist.{Binary, Closed, Custom, Shutdown, Text}

/// Create a WebSocket connection to the given `room_id`.
///
/// `relay` must have been returned from `baton/relay.start`, and the relay
/// actor must be running for this WebSocket to function.
///
/// `request` must be the HTTP request/connection that will be upgraded to a
/// WebSocket connection.
///
/// This socket connection allows the client to:
///   1. send messages to peers in the room 
///   2. receive messages from peers in the room 
///   3. receive events from the server about the presence of peers in the room
pub fn connect_peer(
  relay: Subject(RelayMessage),
  request: MistRequest,
  room_id: RoomId,
) -> MistResponse {
  // This peer ID is valid for the duration of the websocket connection.
  let peer_id = protocol.new_peer_id()

  let on_init = fn(_conn) {
    logging.log(logging.Info, "[peer " <> peer_id <> "] starting web socket")

    // TODO: I find it odd that we must create a new subject and inject a
    // selector instead of getting the subject created for this actor.
    //
    // The relay can route messages to this subject.
    let peer_subject = process.new_subject()
    let selector =
      process.new_selector()
      |> process.selecting(peer_subject, identity)

    // Tell the relay actor about this websocket actor so it becomes routable.
    process.send(relay, AddPeer(room_id, peer_id, peer_subject))

    #(Nil, Some(selector))
  }

  let on_close = fn(_state) {
    // Tell the relay actor to remove this peer.
    process.send(relay, RemovePeer(room_id, peer_id))

    logging.log(logging.Info, "[peer " <> peer_id <> "] socket closed")
  }

  mist.websocket(
    request: request,
    on_init: on_init,
    on_close: on_close,
    handler: fn(_state, conn, message) {
      handle_ws_message(relay, conn, room_id, peer_id, message)
    },
  )
}

fn handle_ws_message(
  relay: Subject(RelayMessage),
  conn: mist.WebsocketConnection,
  room_id: RoomId,
  my_peer_id: PeerId,
  message: mist.WebsocketMessage(PeerSocketMessage),
) -> actor.Next(PeerSocketMessage, Nil) {
  let result = case message {
    // From client
    Binary(bin) -> {
      // NOTE: We do header decoding here to keep the relay process minimal
      use SentPeerMessage(to, content) <- result.try(
        protocol.decode_sent_peer_message(protocol.Binary(bin)),
      )
      process.send(
        relay,
        RelayPeerMessage(
          room_id: room_id,
          from: my_peer_id,
          to: to,
          content: content,
        ),
      )
      Ok(Nil)
    }
    Text(txt) -> {
      // NOTE: We do header decoding here to keep the relay process minimal
      use SentPeerMessage(to, content) <- result.try(
        protocol.decode_sent_peer_message(protocol.Text(txt)),
      )
      process.send(
        relay,
        RelayPeerMessage(
          room_id: room_id,
          from: my_peer_id,
          to: to,
          content: content,
        ),
      )
      Ok(Nil)
    }

    // From server
    Custom(event) -> {
      let send_result = case event {
        FromPeer(message) -> {
          case protocol.encode_received_peer_message(message) {
            protocol.Binary(bin) -> {
              mist.send_binary_frame(conn, bin)
            }
            protocol.Text(txt) -> {
              mist.send_text_frame(conn, txt)
            }
          }
        }
        FromRelay(room_event) -> {
          mist.send_text_frame(conn, protocol.encode_room_event(room_event))
        }
      }

      // TODO: should we retry? maybe need a send queue?
      case send_result {
        Error(err) -> {
          logging.log(
            logging.Error,
            "[peer "
              <> my_peer_id
              <> "] Failed to send: "
              <> string.inspect(err),
          )
        }
        _ -> Nil
      }

      Ok(Nil)
    }

    // TODO: actor.Stop?
    // TODO: why do we even have this variant if we must use the on_close callback?
    Closed -> Ok(Nil)

    // TODO: actor.Stop?
    Shutdown -> Ok(Nil)
  }

  case result {
    Ok(Nil) -> actor.continue(Nil)
    Error(err) -> {
      logging.log(
        logging.Error,
        "[socket handler] Error: " <> string.inspect(err),
      )
      actor.continue(Nil)
    }
  }
}
