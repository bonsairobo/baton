# baton

[![Package Version](https://img.shields.io/hexpm/v/baton)](https://hex.pm/packages/baton)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/baton/)

`baton` is a library for implementing relays over WebSockets. Users may
encapsulate an arbitrary message format.

For example, you could use `baton` to implement a WebRTC handshake where clients
must first exchange SCTP endpoint information before they can establish a
peer-to-peer connection. Or you could just implement an ephemeral chat room that
only relays through the WebSocket server.

```sh
gleam add baton
```

Further documentation can be found at <https://hexdocs.pm/baton>.

## How it works (briefly)

WebSocket clients can send text or binary messages to each other via a central
relay service. When a client connects, it is assigned a random peer ID by the
service. After a successful connection, the client is notified of all peer IDs
in the same room. When a client sends a message, it may either broadcast or
specify the peer IDs of the recipients.

Implementing a service takes three steps:

1. Call `baton/server/relay.start` to start the relay actor which manages room
   membership and forwards messages.
2. Implement an HTTP endpoint with `mist`
3. In the API handler, call `baton/server/socket.connect_peer` with a room ID.
   This upgrades the HTTP connection to a WebSocket connection, which is used as
   the transport mechanism for the Baton protocol.

See the docs in `baton/protocol` and `examples/` for more details.
