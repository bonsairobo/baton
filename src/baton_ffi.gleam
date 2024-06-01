// TODO: this should be in the standard lib
pub fn binary_split_once(
  bits: BitArray,
  delimiter: BitArray,
) -> Result(#(BitArray, BitArray), Nil) {
  case binary_split(bits, delimiter) {
    [first, second] -> Ok(#(first, second))
    _ -> Error(Nil)
  }
}

@external(erlang, "baton_erl", "binary_split")
pub fn binary_split(bits: BitArray, delimiter: BitArray) -> List(BitArray)
