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

See `examples/` for usage.

Further documentation can be found at <https://hexdocs.pm/baton>.
