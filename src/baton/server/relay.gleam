//// The relay actor manages the state of all rooms on a server.

import baton/protocol.{
  type Destination, type PeerId, type PeerSocketMessage, type RawContent,
  type RoomId, Broadcast, FromPeer, FromRelay, PeerJoined, PeerLeft, PeerSet,
  ReceivedPeerMessage,
}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result

/// Message type received by the relay actor.
pub type RelayMessage {
  AddPeer(room_id: RoomId, peer_id: PeerId, subject: Subject(PeerSocketMessage))
  RelayPeerMessage(
    room_id: RoomId,
    from: PeerId,
    to: Destination,
    content: RawContent,
  )
  RemovePeer(room_id: RoomId, peer_id: PeerId)
}

/// Start the relay actor.
///
/// The returned `Subject` must be used for sending `RelayMessage`s to this
/// actor.
pub fn start() -> Result(Subject(RelayMessage), actor.StartError) {
  actor.start(new_state(), handle_message)
}

fn new_state() -> State {
  State(rooms: dict.new())
}

type State {
  State(rooms: Dict(RoomId, Room))
}

fn new_room() -> Room {
  Room(dict.new())
}

type Room {
  // PERF: using a BitArray instead of the base64-encoded String for the key
  // might be faster, but we'd need to parse it before insertion
  Room(peers: Dict(PeerId, PeerInfo))
}

type PeerInfo {
  PeerInfo(subject: Subject(PeerSocketMessage))
}

fn handle_message(
  message: RelayMessage,
  state: State,
) -> actor.Next(RelayMessage, State) {
  let State(rooms) = state

  let get_room = fn(room_id) {
    dict.get(rooms, room_id)
    |> result.lazy_unwrap(new_room)
  }

  let new_state = case message {
    AddPeer(room_id, subject: added_subject, peer_id: added_id) -> {
      let room = get_room(room_id)

      // Add peer to room.
      let peers = dict.insert(room.peers, added_id, PeerInfo(added_subject))
      let rooms = dict.insert(rooms, room_id, Room(peers))

      // Make all peers in the room aware of each other.
      dict.each(room.peers, fn(peer_id, peer) {
        process.send(peer.subject, FromRelay(PeerJoined(added_id)))
        process.send(added_subject, FromRelay(PeerJoined(peer_id)))
      })

      State(rooms)
    }
    RemovePeer(room_id, peer_id) -> {
      let room = get_room(room_id)

      // Remove peer from room.
      let remaining_peers = dict.delete(room.peers, peer_id)
      let rooms = dict.insert(rooms, room_id, Room(remaining_peers))

      // Notify all remaining peers.
      dict.each(remaining_peers, fn(_, peer) {
        process.send(peer.subject, FromRelay(PeerLeft(peer_id)))
      })

      State(rooms)
    }
    RelayPeerMessage(room_id, from, to, content) -> {
      let room = get_room(room_id)

      // Send the message to all recipients.
      let dest_subjects = case to {
        Broadcast ->
          list.filter_map(dict.to_list(room.peers), fn(kv) {
            let #(peer_id, info) = kv
            case peer_id == from {
              True -> Error(Nil)
              False -> Ok(info.subject)
            }
          })
        PeerSet(peer_ids) ->
          list.filter_map(peer_ids, fn(peer_id) {
            use info <- result.try(dict.get(room.peers, peer_id))
            Ok(info.subject)
          })
      }
      list.each(dest_subjects, fn(subject) {
        process.send(subject, FromPeer(ReceivedPeerMessage(from, content)))
      })

      State(rooms)
    }
  }

  actor.continue(new_state)
}
