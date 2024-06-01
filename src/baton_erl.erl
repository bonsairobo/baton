-module(baton_erl).

-export([binary_split/2]).

binary_split(Bits, Delimeter) ->
  binary:split(Bits, Delimeter).
