module

public import Lean.Data.Json
import Init.Data.ByteArray.Lemmas

@[expose] public section
namespace Eggshell.DB.Wire

private theorem ok_bind (value : α) (next : α → Except String β) :
    ((Except.ok value : Except String α) >>= next) = next value := rfl
private theorem ok_map (value : α) (next : α → β) :
    next <$> (Except.ok value : Except String α) = .ok (next value) := rfl
attribute [local simp] ok_bind ok_map

/-- A codec recovers an encoded value without altering following bytes, and
a successful decode cannot grow the unread input. Composition preserves both
certificates in the same codec used by the runtime. -/
structure Codec (α : Type) where
  encode : α → List UInt8
  decode : List UInt8 → Except String (α × List UInt8)
  roundtrip : ∀ value tail, decode (encode value ++ tail) = .ok (value, tail)
  /-- Successful decoding never grows the unread input. List tags consume
  one byte even when the element codec itself consumes none. This certificate
  replaces rescanning the entire unread suffix to manufacture loop fuel. -/
  remaining : ∀ bytes value rest, decode bytes = .ok (value, rest) → rest.length ≤ bytes.length
  /-- Capacity accounting is a certified interpretation of the same encoding.
  Composed codecs can add exact costs without serializing discarded bytes. -/
  encodedSize : α → Nat := fun value => (encode value).length
  encodedSizeExact : ∀ value, encodedSize value = (encode value).length := by intros; rfl

theorem Codec.encode_injective (codec : Codec α) : Function.Injective codec.encode := by
  intro left right same
  have a := codec.roundtrip left []
  have b := codec.roundtrip right []
  simp only [List.append_nil] at a b
  rw [same, b] at a
  have pair : (right, []) = (left, []) := Except.ok.inj a
  exact (congrArg Prod.fst pair).symm

def Codec.product (a : Codec α) (b : Codec β) : Codec (α × β) where
  encode value := a.encode value.1 ++ b.encode value.2
  encodedSize value := a.encodedSize value.1 + b.encodedSize value.2
  encodedSizeExact := by
    intro value
    simp only [a.encodedSizeExact, b.encodedSizeExact, List.length_append]
  decode bytes := do
    let (left, rest) ← a.decode bytes
    let (right, rest) ← b.decode rest
    pure ((left, right), rest)
  roundtrip := by
    intro value tail
    simp [List.append_assoc, a.roundtrip, b.roundtrip]
  remaining := by
    intro bytes value rest accepted
    cases first : a.decode bytes with
    | error message => simp [first, bind, Except.bind] at accepted
    | ok left =>
      cases second : b.decode left.2 with
      | error message => simp [first, second, bind, Except.bind] at accepted
      | ok right =>
        have leftBound := a.remaining bytes left.1 left.2 first
        have rightBound := b.remaining left.2 right.1 right.2 second
        simp only [first, second, ok_bind, pure, Except.pure, Except.ok.injEq,
          Prod.mk.injEq] at accepted
        simpa [← accepted.2] using Nat.le_trans rightBound leftBound

def Codec.iso (codec : Codec β) (encode : α → β) (decode : β → α)
    (inverse : ∀ value, decode (encode value) = value) : Codec α where
  encode value := codec.encode (encode value)
  encodedSize value := codec.encodedSize (encode value)
  encodedSizeExact := by intro value; exact codec.encodedSizeExact (encode value)
  decode bytes := do
    let (value, rest) ← codec.decode bytes
    pure (decode value, rest)
  roundtrip := by intro value tail; simp [codec.roundtrip, inverse]
  remaining := by
    intro bytes value rest accepted
    cases decoded : codec.decode bytes with
    | error message => simp [decoded, bind, Except.bind] at accepted
    | ok pair =>
      have bounded := codec.remaining bytes pair.1 pair.2 decoded
      simp only [decoded, ok_bind, pure, Except.pure, Except.ok.injEq,
        Prod.mk.injEq] at accepted
      simpa [← accepted.2] using bounded

def octet : Codec UInt8 where
  encode value := [value]
  encodedSize _ := 1
  encodedSizeExact := by intro value; rfl
  decode
    | [] => .error "truncated octet"
    | value :: rest => .ok (value, rest)
  roundtrip := by intros; rfl
  remaining := by
    intro bytes value rest accepted
    cases bytes with
    | nil => contradiction
    | cons byte tail => cases accepted; simp

def encodeNat (value : Nat) : List UInt8 :=
  if value < 128 then [UInt8.ofNat value]
  else UInt8.ofNat (value % 128 + 128) :: encodeNat (value / 128)
termination_by value

def decodeNatSpec : List UInt8 → Except String (Nat × List UInt8)
  | [] => .error "truncated integer"
  | byte :: rest =>
    if byte.toNat < 128 then .ok (byte.toNat, rest)
    else do
      let (value, rest) ← decodeNatSpec rest
      if value == 0 then throw "noncanonical integer"
      pure (byte.toNat - 128 + 128 * value, rest)

theorem nat_spec_roundtrip (value : Nat) (tail : List UInt8) :
    decodeNatSpec (encodeNat value ++ tail) = .ok (value, tail) := by
  rw [encodeNat]
  split
  · rename_i small
    have exact : (UInt8.ofNat value).toNat = value :=
      UInt8.toNat_ofNat_of_lt' (by change value < 256; omega)
    simp [decodeNatSpec, exact, small]
  · rename_i large
    have digitBound : value % 128 + 128 < 256 := by omega
    have exact : (UInt8.ofNat (value % 128 + 128)).toNat = value % 128 + 128 :=
      UInt8.toNat_ofNat_of_lt' digitBound
    have high : ¬value % 128 + 128 < 128 := by omega
    have positive : value / 128 ≠ 0 := by omega
    simp only [List.cons_append, decodeNatSpec, exact, if_neg high]
    rw [nat_spec_roundtrip (value / 128) tail]
    simp only [ok_bind, beq_iff_eq, positive, ↓reduceIte, pure, Except.pure]
    have division := Nat.mod_add_div value 128
    have total : value % 128 + 128 - 128 + 128 * (value / 128) = value := by omega
    rw [total]
termination_by value

def natStep (value : Nat) (byte : UInt8) : Nat := byte.toNat - 128 + 128 * value

def finishNat (seen : List UInt8) (value : Nat) (rest : List UInt8) : Except String (Nat × List UInt8) :=
  if value == 0 && !seen.isEmpty then .error "noncanonical integer"
  else .ok (seen.foldl natStep value, rest)

/-- Accumulate continuation digits in a tail call and fold them iteratively.
Even a malformed full-size page does not grow the native call stack once per
continuation byte. No fixed-width limit is imposed on valid ordinals. -/
def decodeNatLoop : List UInt8 → List UInt8 → Except String (Nat × List UInt8)
  | [], _ => .error "truncated integer"
  | byte :: rest, seen =>
    if byte.toNat < 128 then finishNat seen byte.toNat rest
    else decodeNatLoop rest (byte :: seen)

theorem nat_loop_exact (bytes seen : List UInt8) :
    decodeNatLoop bytes seen = (decodeNatSpec bytes).bind (fun (value, rest) => finishNat seen value rest) := by
  induction bytes generalizing seen with
  | nil => rfl
  | cons byte rest ih =>
    simp only [decodeNatLoop, decodeNatSpec]
    split
    · rfl
    · rw [ih]
      cases decoded : decodeNatSpec rest with
      | error message => rfl
      | ok pair =>
        rcases pair with ⟨value, tail⟩
        cases value with
        | zero => simp [finishNat, bind, Except.bind, throw, throwThe]; rfl
        | succ value =>
          simp [finishNat, natStep, bind, Except.bind, pure, Except.pure]

def decodeNat (bytes : List UInt8) : Except String (Nat × List UInt8) := decodeNatLoop bytes []

theorem nat_decode_exact (bytes : List UInt8) : decodeNat bytes = decodeNatSpec bytes := by
  rw [decodeNat, nat_loop_exact]
  cases decodeNatSpec bytes with
  | error => rfl
  | ok value => cases value; simp [finishNat, Except.bind]

theorem nat_roundtrip (value : Nat) (tail : List UInt8) :
    decodeNat (encodeNat value ++ tail) = .ok (value, tail) := by
  rw [nat_decode_exact, nat_spec_roundtrip]

theorem nat_remaining (bytes : List UInt8) (value : Nat) (tail : List UInt8)
    (accepted : decodeNat bytes = .ok (value, tail)) : tail.length ≤ bytes.length := by
  rw [nat_decode_exact] at accepted
  induction bytes generalizing value tail with
  | nil => simp [decodeNatSpec] at accepted
  | cons byte rest ih =>
    simp only [decodeNatSpec] at accepted
    split at accepted
    · cases accepted; simp
    · cases decoded : decodeNatSpec rest with
      | error message => simp [decoded, bind, Except.bind] at accepted
      | ok pair =>
        have bounded := ih pair.1 pair.2 decoded
        simp only [decoded, ok_bind] at accepted
        split at accepted
        · contradiction
        · simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at accepted
          simp only [List.length_cons]
          simpa [← accepted.2] using Nat.le_succ_of_le bounded

def natural : Codec Nat where
  encode := encodeNat
  decode := decodeNat
  roundtrip := nat_roundtrip
  remaining := nat_remaining

/-- Canonical lowercase hexadecimal for the existing UTF-8 metadata envelope.
Only the coordinate payload is armored; references remain explicit graph edges. -/
def hexDigit : Nat → Char
  | 0 => '0' | 1 => '1' | 2 => '2' | 3 => '3'
  | 4 => '4' | 5 => '5' | 6 => '6' | 7 => '7'
  | 8 => '8' | 9 => '9' | 10 => 'a' | 11 => 'b'
  | 12 => 'c' | 13 => 'd' | 14 => 'e' | _ => 'f'

def hexValue : Char → Option Nat
  | '0' => some 0 | '1' => some 1 | '2' => some 2 | '3' => some 3
  | '4' => some 4 | '5' => some 5 | '6' => some 6 | '7' => some 7
  | '8' => some 8 | '9' => some 9 | 'a' => some 10 | 'b' => some 11
  | 'c' => some 12 | 'd' => some 13 | 'e' => some 14 | 'f' => some 15
  | _ => none

theorem hex_digit_exact (value : Nat) (small : value < 16) :
    hexValue (hexDigit value) = some value := by
  have choices : value = 0 ∨ value = 1 ∨ value = 2 ∨ value = 3 ∨
      value = 4 ∨ value = 5 ∨ value = 6 ∨ value = 7 ∨ value = 8 ∨
      value = 9 ∨ value = 10 ∨ value = 11 ∨ value = 12 ∨ value = 13 ∨
      value = 14 ∨ value = 15 := by omega
  rcases choices with h | h | h | h | h | h | h | h | h | h | h | h | h | h | h | h <;>
    subst value <;> rfl

def hexChars (bytes : List UInt8) : List Char :=
  bytes.flatMap fun byte => [hexDigit (byte.toNat / 16), hexDigit (byte.toNat % 16)]

def unhex : List Char → List UInt8 → Except String (List UInt8)
  | [], seen => .ok seen.reverse
  | high :: low :: rest, seen => do
      let some high := hexValue high | throw "invalid hexadecimal digit"
      let some low := hexValue low | throw "invalid hexadecimal digit"
      unhex rest (UInt8.ofNat (high * 16 + low) :: seen)
  | _, _ => .error "incomplete hexadecimal byte"

theorem unhex_exact (bytes seen : List UInt8) :
    unhex (hexChars bytes) seen = .ok (seen.reverse ++ bytes) := by
  induction bytes generalizing seen with
  | nil => simp [hexChars, unhex]
  | cons byte rest ih =>
    have high : byte.toNat / 16 < 16 := by have := byte.toNat_lt; omega
    have low : byte.toNat % 16 < 16 := by omega
    have assembled : byte.toNat / 16 * 16 + byte.toNat % 16 = byte.toNat := by omega
    simp only [hexChars, List.flatMap_cons, List.cons_append, List.nil_append, unhex,
      hex_digit_exact _ high, hex_digit_exact _ low]
    simp only [assembled, UInt8.ofNat_toNat]
    rw [show rest.flatMap (fun byte => [hexDigit (byte.toNat / 16), hexDigit (byte.toNat % 16)]) =
      hexChars rest from rfl, ih]
    simp

def hex (bytes : List UInt8) : String := String.ofList (hexChars bytes)
def fromHex (text : String) : Except String (List UInt8) := unhex text.toList []

theorem hex_exact (bytes : List UInt8) : fromHex (hex bytes) = .ok bytes := by
  simp [fromHex, hex, String.toList_ofList, unhex_exact]

/-- Consume only the requested prefix, without scanning the remainder for
every string field. The accumulator grows only when an input byte is removed;
an untrusted count cannot cause a corresponding allocation. -/
def takeBytes : Nat → List UInt8 → List UInt8 → Except String (List UInt8 × List UInt8)
  | 0, rest, seen => .ok (seen.reverse, rest)
  | _ + 1, [], _ => .error "truncated byte string"
  | count + 1, byte :: rest, seen => takeBytes count rest (byte :: seen)

theorem take_bytes_prefix (bytes tail seen : List UInt8) :
    takeBytes bytes.length (bytes ++ tail) seen = .ok (seen.reverse ++ bytes, tail) := by
  induction bytes generalizing seen with
  | nil => simp [takeBytes]
  | cons byte rest ih => simp [takeBytes, ih, List.reverse_cons, List.append_assoc]

theorem take_bytes_bounded (count : Nat) (bytes seen value tail : List UInt8)
    (accepted : takeBytes count bytes seen = .ok (value, tail)) :
    value.length ≤ seen.length + bytes.length := by
  induction count generalizing bytes seen with
  | zero =>
    simp only [takeBytes, Except.ok.injEq, Prod.mk.injEq] at accepted
    rw [← accepted.1, List.length_reverse]
    omega
  | succ count ih =>
    cases bytes with
    | nil => simp [takeBytes] at accepted
    | cons byte rest =>
      have bound := ih rest (byte :: seen) accepted
      simp only [List.length_cons] at bound ⊢
      omega

theorem take_bytes_remaining (count : Nat) (bytes seen value tail : List UInt8)
    (accepted : takeBytes count bytes seen = .ok (value, tail)) :
    tail.length ≤ bytes.length := by
  induction count generalizing bytes seen with
  | zero => cases accepted; exact Nat.le_refl _
  | succ count ih =>
    cases bytes with
    | nil => contradiction
    | cons byte rest => exact Nat.le_succ_of_le (ih rest (byte :: seen) accepted)

def blob : Codec (List UInt8) where
  encode bytes := natural.encode bytes.length ++ bytes
  encodedSize bytes := natural.encodedSize bytes.length + bytes.length
  encodedSizeExact := by intro bytes; simp only [natural.encodedSizeExact, List.length_append]
  decode bytes := do
    let (count, rest) ← natural.decode bytes
    takeBytes count rest []
  roundtrip := by
    intro value tail
    simp [List.append_assoc, natural.roundtrip, take_bytes_prefix]
  remaining := by
    intro bytes value rest accepted
    cases decoded : natural.decode bytes with
    | error message => simp [decoded, bind, Except.bind] at accepted
    | ok pair =>
      simp only [decoded, ok_bind] at accepted
      exact Nat.le_trans (take_bytes_remaining pair.1 pair.2 [] value rest accepted)
        (natural.remaining bytes pair.1 pair.2 decoded)

theorem bytes_roundtrip (bytes : ByteArray) : bytes.data.toList.toByteArray = bytes := by
  apply ByteArray.ext
  apply Array.toList_inj.mp
  simp

/-- The bounded prefix is collected directly into an unboxed byte array.
Only bytes consumed from the supplied list can grow the accumulator. -/
def takeByteArray : Nat → List UInt8 → ByteArray → Except String (ByteArray × List UInt8)
  | 0, rest, seen => .ok (seen, rest)
  | _ + 1, [], _ => .error "truncated byte string"
  | count + 1, byte :: rest, seen => takeByteArray count rest (seen.push byte)

/-- Exact old prefix interpretation for every count, suffix and accumulator,
including truncation. The reference parser occurs only in this erased proof. -/
theorem takeByteArray_reference (count : Nat) (input : List UInt8) (seen : ByteArray) :
    takeByteArray count input seen =
      (takeBytes count input seen.data.toList.reverse).map
        (fun (value, rest) => (value.toByteArray, rest)) := by
  induction count generalizing input seen with
  | zero => simp [takeByteArray, takeBytes, Except.map, bytes_roundtrip]
  | succ count ih =>
    cases input with
    | nil => rfl
    | cons byte rest =>
      simpa [takeByteArray, takeBytes, ByteArray.data_push, Array.toList_push,
        List.reverse_append] using
        ih rest (seen.push byte)

theorem takeByteArray_bounded (count : Nat) (input : List UInt8) (seen value : ByteArray)
    (rest : List UInt8) (accepted : takeByteArray count input seen = .ok (value, rest)) :
    value.size ≤ seen.size + input.length := by
  induction count generalizing input seen with
  | zero => cases accepted; simp
  | succ count ih =>
    cases input with
    | nil => contradiction
    | cons byte tail =>
      have bound := ih tail (seen.push byte) accepted
      simpa only [ByteArray.size_push, List.length_cons, Nat.add_assoc,
        Nat.add_comm, Nat.add_left_comm] using bound

def decodeByteBlob (input : List UInt8) : Except String (ByteArray × List UInt8) := do
  let (count, rest) ← natural.decode input
  takeByteArray count rest ByteArray.empty

theorem decodeByteBlob_reference (input : List UInt8) :
    decodeByteBlob input =
      (blob.decode input).map (fun (value, rest) => (value.toByteArray, rest)) := by
  cases first : natural.decode input with
  | error message => simp [decodeByteBlob, blob, first, bind, Except.bind, Except.map]
  | ok pair =>
    rcases pair with ⟨count, suffix⟩
    simp [decodeByteBlob, blob, first, takeByteArray_reference, bind, Except.bind]

/-- Same canonical wire bytes as `blob`, with dense payloads at read time.
No second prefix list or retained neighbor expansion is constructed. -/
def byteBlob : Codec ByteArray where
  encode value := blob.encode value.data.toList
  encodedSize value := natural.encodedSize value.size + value.size
  encodedSizeExact := by
    intro value
    simp [blob, natural.encodedSizeExact]
  decode := decodeByteBlob
  roundtrip := by
    intro value tail
    rw [decodeByteBlob_reference, blob.roundtrip]
    simp [Except.map, bytes_roundtrip]
  remaining := by
    intro input value rest accepted
    rw [decodeByteBlob_reference] at accepted
    cases decoded : blob.decode input with
    | error message => simp [decoded, Except.map] at accepted
    | ok pair =>
      have bounded := blob.remaining input pair.1 pair.2 decoded
      simp only [decoded, Except.map, Except.ok.injEq, Prod.mk.injEq] at accepted
      simpa [← accepted.2] using bounded

def text : Codec String where
  encode value := blob.encode value.toUTF8.data.toList
  encodedSize value := natural.encodedSize value.utf8ByteSize + value.utf8ByteSize
  encodedSizeExact := by
    intro value
    simp [blob, natural.encodedSizeExact]
  decode bytes := do
    let (encoded, rest) ← blob.decode bytes
    match String.fromUTF8? encoded.toByteArray with
    | some value => pure (value, rest)
    | none => throw "invalid UTF-8 in binary index"
  roundtrip := by
    intro value tail
    simp [blob.roundtrip, bytes_roundtrip, String.fromUTF8?,
      String.toUTF8_eq_toByteArray, value.isValidUTF8, String.fromUTF8, pure, Except.pure]
  remaining := by
    intro bytes value rest accepted
    cases decoded : blob.decode bytes with
    | error message => simp [decoded, bind, Except.bind] at accepted
    | ok pair =>
      simp only [decoded, ok_bind] at accepted
      split at accepted
      · simp only [pure, Except.pure, Except.ok.injEq, Prod.mk.injEq] at accepted
        simpa [← accepted.2] using blob.remaining bytes pair.1 pair.2 decoded
      · contradiction

def optional (codec : Codec α) : Codec (Option α) where
  encode
    | none => [0]
    | some value => 1 :: codec.encode value
  encodedSize
    | none => 1
    | some value => codec.encodedSize value + 1
  encodedSizeExact := by
    intro value
    cases value <;> simp [codec.encodedSizeExact]
  decode
    | 0 :: rest => .ok (none, rest)
    | 1 :: rest => do
      let (value, rest) ← codec.decode rest
      pure (some value, rest)
    | _ => .error "invalid option tag"
  roundtrip := by intro value tail; cases value <;> simp [codec.roundtrip]
  remaining := by
    intro bytes value rest accepted
    split at accepted
    · cases accepted; simp
    · rename_i tail
      cases decoded : codec.decode tail with
      | error message => simp [decoded, bind, Except.bind] at accepted
      | ok pair =>
        simp only [decoded, ok_bind, pure, Except.pure, Except.ok.injEq,
          Prod.mk.injEq] at accepted
        simpa [← accepted.2] using Nat.le_succ_of_le (codec.remaining tail pair.1 pair.2 decoded)
    · contradiction

def sum (left : Codec α) (right : Codec β) : Codec (Sum α β) where
  encode
    | .inl value => 0 :: left.encode value
    | .inr value => 1 :: right.encode value
  encodedSize
    | .inl value => 1 + left.encodedSize value
    | .inr value => 1 + right.encodedSize value
  encodedSizeExact := by
    intro value
    cases value <;> simp [left.encodedSizeExact, right.encodedSizeExact, Nat.add_comm]
  decode
    | 0 :: rest => do
      let (value, rest) ← left.decode rest
      pure (.inl value, rest)
    | 1 :: rest => do
      let (value, rest) ← right.decode rest
      pure (.inr value, rest)
    | _ => .error "invalid variant tag"
  roundtrip := by intro value tail; cases value <;> simp [left.roundtrip, right.roundtrip]
  remaining := by
    intro bytes value rest accepted
    split at accepted
    · rename_i tail
      cases decoded : left.decode tail with
      | error message => simp [decoded, bind, Except.bind] at accepted
      | ok pair =>
        simp only [decoded, ok_bind, pure, Except.pure, Except.ok.injEq,
          Prod.mk.injEq] at accepted
        simpa [← accepted.2] using Nat.le_succ_of_le (left.remaining tail pair.1 pair.2 decoded)
    · rename_i tail
      cases decoded : right.decode tail with
      | error message => simp [decoded, bind, Except.bind] at accepted
      | ok pair =>
        simp only [decoded, ok_bind, pure, Except.pure, Except.ok.injEq,
          Prod.mk.injEq] at accepted
        simpa [← accepted.2] using Nat.le_succ_of_le (right.remaining tail pair.1 pair.2 decoded)
    · contradiction

def encodeList (codec : Codec α) : List α → List UInt8
  | [] => [0]
  | head :: rest => 1 :: codec.encode head ++ encodeList codec rest

def encodedListSize (codec : Codec α) : List α → Nat
  | [] => 1
  | head :: rest => 1 + codec.encodedSize head + encodedListSize codec rest

theorem encodedListSize_exact (codec : Codec α) (values : List α) :
    encodedListSize codec values = (encodeList codec values).length := by
  induction values with
  | nil => rfl
  | cons value rest ih =>
      simp only [encodedListSize, encodeList, codec.encodedSizeExact,
        List.length_append, List.length_cons, ih]
      omega

def decodeListSpec (codec : Codec α) (fuel : Nat) (bytes : List UInt8) : Except String (List α × List UInt8) :=
  match fuel, bytes with
  | _, 0 :: rest => .ok ([], rest)
  | fuel + 1, 1 :: rest => do
    let (value, rest) ← codec.decode rest
    let (values, rest) ← decodeListSpec codec fuel rest
    pure (value :: values, rest)
  | _, _ => .error "invalid or truncated list"

theorem list_spec_roundtrip (codec : Codec α) (value : List α) (tail : List UInt8)
    (enough : value.length ≤ fuel) :
    decodeListSpec codec fuel (encodeList codec value ++ tail) = .ok (value, tail) := by
  induction value generalizing fuel with
  | nil => cases fuel <;> rfl
  | cons head rest ih =>
    cases fuel with
    | zero => simp at enough
    | succ fuel =>
      simp only [encodeList, List.cons_append, List.append_assoc, decodeListSpec, codec.roundtrip,
        ok_bind]
      rw [ih (by simpa using enough)]
      rfl

def decodeListLoop (codec : Codec α) (fuel : Nat) (bytes : List UInt8) (seen : List α) :
    Except String (List α × List UInt8) :=
  match fuel, bytes with
  | _, 0 :: rest => .ok (seen.reverse, rest)
  | fuel + 1, 1 :: rest => do
    let (value, rest) ← codec.decode rest
    decodeListLoop codec fuel rest (value :: seen)
  | _, _ => .error "invalid or truncated list"

theorem list_loop_exact (codec : Codec α) (fuel : Nat) (bytes : List UInt8) (seen : List α) :
    decodeListLoop codec fuel bytes seen =
      (decodeListSpec codec fuel bytes).map (fun (values, rest) => (seen.reverse ++ values, rest)) := by
  induction fuel generalizing bytes seen with
  | zero =>
    cases bytes with
    | nil => rfl
    | cons byte rest =>
      by_cases zero : byte = 0
      · subst byte; simp [decodeListLoop, decodeListSpec, Except.map]
      · simp [decodeListLoop, decodeListSpec, zero, Except.map]
  | succ fuel ih =>
    cases bytes with
    | nil => rfl
    | cons byte rest =>
      by_cases zero : byte = 0
      · subst byte; simp [decodeListLoop, decodeListSpec, Except.map]
      · by_cases one : byte = 1
        · subst byte
          simp only [decodeListLoop, decodeListSpec]
          cases decoded : codec.decode rest with
          | error => rfl
          | ok pair =>
            rcases pair with ⟨value, tail⟩
            simp only [ok_bind]
            rw [ih]
            cases decodeListSpec codec fuel tail with
            | error => rfl
            | ok pair =>
              rcases pair with ⟨values, rest⟩
              simp [Except.map, List.reverse_cons, List.append_assoc, pure, Except.pure]
        · simp [decodeListLoop, decodeListSpec, zero, one, Except.map]

def decodeList (codec : Codec α) (fuel : Nat) (bytes : List UInt8) : Except String (List α × List UInt8) :=
  decodeListLoop codec fuel bytes []

theorem list_roundtrip (codec : Codec α) (value : List α) (tail : List UInt8)
    (enough : value.length ≤ fuel) :
    decodeList codec fuel (encodeList codec value ++ tail) = .ok (value, tail) := by
  rw [decodeList, list_loop_exact, list_spec_roundtrip codec value tail enough]
  rfl

theorem list_bytes (codec : Codec α) (value : List α) : value.length ≤ (encodeList codec value).length := by
  induction value with
  | nil => simp [encodeList]
  | cons head rest ih => simp only [encodeList, List.length_cons, List.length_append]; omega

/-- Each list marker consumes a byte; the element's erased certificate
ensures that its successful result cannot restore it. No suffix-length scan
is performed by this executable loop. -/
def decodeListStream (codec : Codec α) (bytes : List UInt8) (seen : List α) :
    Except String (List α × List UInt8) :=
  match bytes with
  | 0 :: rest => .ok (seen.reverse, rest)
  | 1 :: rest =>
    match _decoded : codec.decode rest with
    | .error error => .error error
    | .ok (value, tail) => decodeListStream codec tail (value :: seen)
  | _ => .error "invalid or truncated list"
termination_by bytes.length
decreasing_by exact Nat.lt_succ_of_le (codec.remaining _ _ _ _decoded)

theorem list_stream_exact (codec : Codec α) (fuel : Nat) (bytes : List UInt8) (seen : List α)
    (enough : bytes.length ≤ fuel) :
    decodeListStream codec bytes seen = decodeListLoop codec fuel bytes seen := by
  induction fuel generalizing bytes seen with
  | zero =>
    have empty : bytes = [] := List.eq_nil_of_length_eq_zero (by omega)
    subst bytes
    simp [decodeListStream, decodeListLoop]
  | succ fuel ih =>
    cases bytes with
    | nil => simp [decodeListStream, decodeListLoop]
    | cons byte rest =>
      by_cases zero : byte = 0
      · subst byte; simp [decodeListStream, decodeListLoop]
      · by_cases one : byte = 1
        · subst byte
          rw [decodeListStream]
          simp only [decodeListLoop]
          cases decoded : codec.decode rest with
          | error message => rfl
          | ok pair =>
            have bounded := codec.remaining rest pair.1 pair.2 decoded
            simp only [ok_bind]
            exact ih pair.2 (pair.1 :: seen) (by simp only [List.length_cons] at enough; omega)
        · simp [decodeListStream, decodeListLoop, zero, one]

theorem list_loop_remaining (codec : Codec α) (fuel : Nat) (bytes : List UInt8)
    (seen value : List α) (tail : List UInt8)
    (accepted : decodeListLoop codec fuel bytes seen = .ok (value, tail)) :
    tail.length ≤ bytes.length := by
  induction fuel generalizing bytes seen with
  | zero =>
    cases bytes with
    | nil => simp [decodeListLoop] at accepted
    | cons byte rest =>
      by_cases zero : byte = 0
      · subst byte; cases accepted; simp
      · simp [decodeListLoop, zero] at accepted
  | succ fuel ih =>
    cases bytes with
    | nil => simp [decodeListLoop] at accepted
    | cons byte rest =>
      by_cases zero : byte = 0
      · subst byte; cases accepted; simp
      · by_cases one : byte = 1
        · subst byte
          simp only [decodeListLoop] at accepted
          cases decoded : codec.decode rest with
          | error message => simp [decoded, bind, Except.bind] at accepted
          | ok pair =>
            simp only [decoded, ok_bind] at accepted
            exact Nat.le_succ_of_le (Nat.le_trans (ih pair.2 (pair.1 :: seen) accepted)
              (codec.remaining rest pair.1 pair.2 decoded))
        · simp [decodeListLoop, zero, one] at accepted

def list (codec : Codec α) : Codec (List α) where
  encode := encodeList codec
  encodedSize := encodedListSize codec
  encodedSizeExact := encodedListSize_exact codec
  decode bytes := decodeListStream codec bytes []
  roundtrip := by
    intro value tail
    rw [list_stream_exact codec (encodeList codec value ++ tail).length _ _ (Nat.le_refl _)]
    change decodeList codec _ _ = _
    apply list_roundtrip
    have := list_bytes codec value
    simp only [List.length_append]
    omega
  remaining := by
    intro bytes value rest accepted
    rw [list_stream_exact codec bytes.length bytes [] (Nat.le_refl _)] at accepted
    exact list_loop_remaining codec bytes.length bytes [] value rest accepted


end Eggshell.DB.Wire
