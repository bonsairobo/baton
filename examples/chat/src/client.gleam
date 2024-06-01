import baton/protocol
import gleam/erlang/process
import gleam/function
import gleam/http/request
import gleam/io
import gleam/option.{None}
import gleam/otp/actor
import gleam/string
import repeatedly
import stratus

pub fn main() {
  let alice = run_chat_socket("alice")
  let bob = run_chat_socket("bob")
  wait(alice)
  wait(bob)
}

type Msg {
  Close
  BroadcastBinary(BitArray)
  BroadcastText(String)
}

fn run_chat_socket(name: String) {
  let assert Ok(req) = request.to("http://localhost:8000/rooms/foo")

  let builder =
    stratus.websocket(
      request: req,
      init: fn() { #(Nil, None) },
      loop: fn(msg, state, conn) {
        case msg {
          stratus.Text(message) -> {
            let assert Ok(message) =
              protocol.decode_peer_socket_message(protocol.Text(message))
            io.println(
              name <> " got message:\n" <> string.inspect(message) <> "\n",
            )
            actor.continue(state)
          }
          stratus.Binary(message) -> {
            let assert Ok(message) =
              protocol.decode_peer_socket_message(protocol.Binary(message))
            io.println(
              name <> " got message:\n" <> string.inspect(message) <> "\n",
            )
            actor.continue(state)
          }
          stratus.User(user) -> {
            case user {
              BroadcastBinary(content) -> {
                let bin =
                  protocol.encode_sent_peer_message_as_binary(
                    protocol.Broadcast,
                    content,
                  )
                let assert Ok(_resp) = stratus.send_binary_message(conn, bin)
                actor.continue(state)
              }
              BroadcastText(content) -> {
                let text =
                  protocol.encode_sent_peer_message_as_text(
                    protocol.Broadcast,
                    content,
                  )
                let assert Ok(_resp) = stratus.send_text_message(conn, text)
                actor.continue(state)
              }
              Close -> {
                let assert Ok(_) = stratus.close(conn)
                actor.Stop(process.Normal)
              }
            }
          }
        }
      },
    )
    |> stratus.on_close(fn(_state) { io.println("closing...") })

  let assert Ok(subj) = stratus.initialize(builder)

  repeatedly.call(1000, Nil, fn(_state, count) {
    case count % 2 {
      0 -> {
        stratus.send_message(
          subj,
          BroadcastBinary(<<"binary hello from ":utf8, name:utf8>>),
        )
      }
      1 -> {
        stratus.send_message(subj, BroadcastText("text hello from " <> name))
      }
      _ -> Nil
    }
  })

  process.start(
    fn() {
      process.sleep(6000)
      stratus.send_message(subj, Close)
    },
    True,
  )

  subj
}

fn wait(subj: process.Subject(a)) {
  let done =
    process.new_selector()
    |> process.selecting_process_down(
      process.monitor_process(process.subject_owner(subj)),
      function.identity,
    )
    |> process.select_forever

  io.debug(#("WebSocket process exited", done))
}
