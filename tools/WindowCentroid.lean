module

public import Eggshell.Blake3

@[expose] public section

namespace Eggshell.WindowCentroid

/-- Experimental scoring projection. Keep every encoded segment, but give one
original DB window one normalized vector. Weights count newly covered source
tokens, so a short overflow tail cannot acquire the weight of a full segment.
No cache or source bytes change. Adoption requires matched token/quality trials. -/
def weights (tokens capacity overlap count : Nat) : Except String (Array Nat) := do
  unless 0 < capacity && overlap < capacity && 0 < count && count ≤ 512 do
    throw "invalid segment geometry"
  let step := capacity - overlap
  let expected := if tokens ≤ capacity then 1 else 1 + (tokens - capacity + step - 1) / step
  unless count == expected do throw "segment count disagrees with source token coverage"
  if tokens == 0 then return #[1]
  let mut result := #[]
  for index in [:count] do
    let length := min capacity (tokens - index * step)
    let carried := if index == 0 then 0 else overlap
    unless carried < length do throw "segment adds no source tokens"
    result := result.push (length - carried)
  unless result.foldl (· + ·) 0 == tokens do throw "source token weights are incomplete"
  return result

def digit (byte : UInt8) : Except String UInt64 :=
  if 48 ≤ byte && byte ≤ 57 then .ok (byte - 48).toUInt64
  else if 97 ≤ byte && byte ≤ 102 then .ok (byte - 87).toUInt64
  else .error "noncanonical packed vector"

def unpack (packed : String) : Except String (Array Float) := do
  let bytes := packed.toUTF8
  unless 0 < bytes.size && bytes.size % 16 == 0 && bytes.size / 16 ≤ 4096 do
    throw "invalid packed vector shape"
  let mut values := #[]
  for word in [:bytes.size / 16] do
    let mut bits : UInt64 := 0
    for byte in [:8] do
      let offset := word * 16 + byte * 2
      let value := (← digit bytes[offset]!) * 16 + (← digit bytes[offset + 1]!)
      bits := bits ||| (value <<< (byte * 8).toUInt64)
    let value := Float.ofBits bits
    unless !value.isNaN && !value.isInf do throw "nonfinite packed vector"
    values := values.push value
  return values

def pack (values : Array Float) : String := Id.run do
  let mut bytes := ByteArray.empty
  for value in values do
    for byte in [:8] do bytes := bytes.push ((value.toBits >>> (byte * 8).toUInt64).toUInt8)
  return Blake3.hex bytes

def project (vectors : Array String) (tokens capacity overlap : Nat) : Except String String := do
  let counts ← weights tokens capacity overlap vectors.size
  let decoded ← vectors.mapM unpack
  let dimension := decoded[0]!.size
  unless decoded.all (·.size == dimension) do throw "segment dimensions disagree"
  -- A one-segment window retains its exact original numerical representation.
  if vectors.size == 1 then return vectors[0]!
  let mut sum := Array.replicate dimension (0.0 : Float)
  for index in [:vectors.size] do
    let weight := counts[index]!.toFloat
    for coordinate in [:dimension] do
      sum := sum.set! coordinate (sum[coordinate]! + weight * decoded[index]![coordinate]!)
  let norm := Float.sqrt (sum.foldl (fun total value => total + value * value) 0.0)
  unless 0.0 < norm && !norm.isInf && !norm.isNaN do throw "undefined window centroid"
  return pack (sum.map (· / norm))

end Eggshell.WindowCentroid
