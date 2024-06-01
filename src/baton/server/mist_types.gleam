import gleam/http/request
import gleam/http/response
import mist

pub type MistRequest =
  request.Request(mist.Connection)

pub type MistResponse =
  response.Response(mist.ResponseData)
