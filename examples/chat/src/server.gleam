import baton/server/mist_types.{type MistRequest, type MistResponse}
import baton/server/relay.{type RelayMessage}
import baton/server/socket
import gleam/erlang/process.{type Subject}
import gleam/http/request
import mist
import wisp.{type Request, type Response}

pub fn main() {
  wisp.configure_logger()

  let secret_key_base = wisp.random_string(64)

  let assert Ok(relay) = relay.start()

  let assert Ok(_) =
    handle_request(secret_key_base, relay, _)
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  process.sleep_forever()
}

fn handle_request(
  secret_key_base: String,
  relay: Subject(RelayMessage),
  request: MistRequest,
) -> MistResponse {
  case request.path {
    // Handling websockets directly with Mist instead of Wisp.
    // TODO: Wisp should have a websockets API
    // TODO: would like to use wisp.route.path_segments but we have the wrong type
    "/rooms/" <> room_id -> {
      socket.connect_peer(relay, request, room_id)
    }
    _ ->
      request
      |> wisp.mist_handler(wisp_handler, secret_key_base)
  }
}

fn wisp_handler(req: Request) -> Response {
  case request.path_segments(req) {
    // ["foo"] -> todo
    _ -> wisp.not_found()
  }
}
