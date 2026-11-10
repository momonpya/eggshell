module
public import Eggshell.DB.Wire
import Init.Data.ByteArray.Lemmas
@[expose] public section

namespace Eggshell.DB.Wire

private theorem canonical_ok_bind (value : α) (next : α → Except String β) :
    ((Except.ok value : Except String α) >>= next) = next value := rfl
private theorem canonical_error_bind (message : String) (next : α → Except String β) :
    ((Except.error message : Except String α) >>= next) = .error message := rfl
private theorem canonical_ok_map (value : α) (next : α → β) :
    next <$> (Except.ok value : Except String α) = .ok (next value) := rfl
private theorem canonical_error_map (message : String) (next : α → β) :
    next <$> (Except.error message : Except String α) = .error message := rfl
attribute [local simp] canonical_ok_bind canonical_error_bind canonical_ok_map canonical_error_map
set_option linter.unusedSimpArgs false

/-- Successful decoding accounts for every consumed byte. This is stronger
than roundtrip: it rules out alternate encodings of the same value. -/
def Codec.Canonical (codec : Codec α) : Prop :=
  ∀ input value rest, codec.decode input = .ok (value,rest) → codec.encode value ++ rest = input

theorem Codec.Canonical.product {left : Codec α} {right : Codec β}
    (a : left.Canonical) (b : right.Canonical) : (left.product right).Canonical := by
  intro input value rest accepted
  cases first : left.decode input with
  | error message => simp [Codec.product,first,Except.bind] at accepted
  | ok pair =>
    rcases pair with ⟨x,middle⟩
    cases second : right.decode middle with
    | error message => simp [Codec.product,first,second,Except.bind] at accepted
    | ok pair =>
      rcases pair with ⟨y,tail⟩
      simp only [Codec.product,first,second,canonical_ok_bind,canonical_ok_map,Except.ok.injEq,Prod.mk.injEq] at accepted
      rcases accepted with ⟨rfl,rfl⟩
      simpa only [Codec.product,List.append_assoc,b middle y rest second] using a input x middle first

theorem Codec.Canonical.iso {codec : Codec β} (original : codec.Canonical)
    (encode : α → β) (decode : β → α) (inverse : ∀ value, decode (encode value) = value)
    (back : ∀ value, encode (decode value) = value) : (codec.iso encode decode inverse).Canonical := by
  intro input value rest accepted
  cases parsed : codec.decode input with
  | error message => simp [Codec.iso,parsed,Except.bind] at accepted
  | ok pair =>
    rcases pair with ⟨found,tail⟩
    simp only [Codec.iso,parsed,canonical_ok_map,Except.ok.injEq,Prod.mk.injEq] at accepted
    rcases accepted with ⟨rfl,rfl⟩
    simpa only [Codec.iso,back] using original input found tail parsed

theorem octet_canonical : octet.Canonical := by
  intro input value rest accepted
  cases input with
  | nil => contradiction
  | cons byte tail => cases accepted; rfl

theorem nat_spec_canonical (input : List UInt8) (value : Nat) (tail : List UInt8)
    (accepted : decodeNatSpec input = .ok (value,tail)) : encodeNat value ++ tail = input := by
  induction input generalizing value tail with
  | nil => contradiction
  | cons byte rest ih =>
    simp only [decodeNatSpec] at accepted
    split at accepted
    · rename_i small
      cases accepted
      simp [encodeNat,small,UInt8.ofNat_toNat]
    · rename_i large
      cases parsed : decodeNatSpec rest with
      | error message => simp [parsed,Except.bind] at accepted
      | ok pair =>
        rcases pair with ⟨high,suffix⟩
        simp only [parsed,canonical_ok_bind] at accepted
        split at accepted
        · contradiction
        · rename_i nonzero
          have highPositive : high ≠ 0 := by simpa using nonzero
          simp only [pure,Except.pure,Except.ok.injEq,Prod.mk.injEq] at accepted
          rcases accepted with ⟨rfl,rfl⟩
          have byteBound := byte.toNat_lt
          have totalLarge : ¬ byte.toNat-128+128*high < 128 := by omega
          have quotient : (byte.toNat-128+128*high)/128 = high := by omega
          have remainder : (byte.toNat-128+128*high)%128+128 = byte.toNat := by omega
          rw [encodeNat,if_neg totalLarge,quotient,remainder,UInt8.ofNat_toNat,List.cons_append,ih high suffix parsed]

theorem natural_canonical : natural.Canonical := by
  intro input value tail accepted
  apply nat_spec_canonical input value tail
  simpa only [natural,nat_decode_exact] using accepted

theorem take_bytes_partition (count : Nat) (input seen value tail : List UInt8)
    (accepted : takeBytes count input seen = .ok (value,tail)) :
    value.length = seen.length+count ∧ seen.reverse++input = value++tail := by
  induction count generalizing input seen with
  | zero =>
    cases accepted
    simp
  | succ count ih =>
    cases input with
    | nil => contradiction
    | cons byte rest =>
      have found := ih rest (byte::seen) accepted
      constructor
      · simpa only [List.length_cons,Nat.add_assoc,Nat.add_comm,Nat.add_left_comm] using found.1
      · simpa only [List.reverse_cons,List.append_assoc,List.singleton_append] using found.2

theorem blob_canonical : blob.Canonical := by
  intro input value tail accepted
  cases parsed : natural.decode input with
  | error message => simp [blob,parsed,Except.bind] at accepted
  | ok pair =>
    rcases pair with ⟨count,rest⟩
    simp only [blob,parsed,canonical_ok_bind] at accepted
    have partition := take_bytes_partition count rest [] value tail accepted
    have size : value.length = count := by simpa using partition.1
    have split : rest = value++tail := by simpa using partition.2
    simpa only [blob,size,List.append_assoc,← split] using natural_canonical input count rest parsed

theorem byteBlob_canonical : byteBlob.Canonical := by
  intro input value tail accepted
  simp only [byteBlob,decodeByteBlob_reference] at accepted
  cases parsed : blob.decode input with
  | error message => simp [parsed,Except.map] at accepted
  | ok pair =>
    rcases pair with ⟨bytes,rest⟩
    simp only [parsed,Except.map,Except.ok.injEq,Prod.mk.injEq] at accepted
    rcases accepted with ⟨rfl,rfl⟩
    simpa only [byteBlob,List.toList_data_toByteArray] using blob_canonical input bytes rest parsed

theorem text_canonical : text.Canonical := by
  intro input value tail accepted
  cases parsed : blob.decode input with
  | error message => simp [text,parsed,Except.bind] at accepted
  | ok pair =>
    rcases pair with ⟨bytes,rest⟩
    cases decoded : String.fromUTF8? bytes.toByteArray with
    | none => simp [text,parsed,decoded,Except.bind] at accepted
    | some found =>
      simp only [text,parsed,decoded,canonical_ok_bind,pure,Except.pure,Except.ok.injEq,Prod.mk.injEq] at accepted
      rcases accepted with ⟨rfl,rfl⟩
      have encoded : found.toUTF8 = bytes.toByteArray := by
        unfold String.fromUTF8? at decoded
        split at decoded
        · cases decoded; simp [String.fromUTF8]
        · contradiction
      simpa only [text,encoded,List.toList_data_toByteArray] using blob_canonical input bytes rest parsed

theorem Codec.Canonical.optional {codec : Codec α} (original : codec.Canonical) :
    (Wire.optional codec).Canonical := by
  intro input value rest accepted
  simp only [Wire.optional] at accepted
  split at accepted
  · cases accepted; rfl
  · rename_i tail
    cases parsed : codec.decode tail with
    | error message => simp [parsed,Except.map] at accepted
    | ok pair =>
      rcases pair with ⟨found,suffix⟩
      simp only [parsed,canonical_ok_map,Except.ok.injEq,Prod.mk.injEq] at accepted
      rcases accepted with ⟨rfl,rfl⟩
      simpa only [Wire.optional,List.cons_append] using congrArg (List.cons (1 : UInt8)) (original _ _ _ parsed)
  · contradiction

theorem Codec.Canonical.sum {left : Codec α} {right : Codec β}
    (a : left.Canonical) (b : right.Canonical) : (Wire.sum left right).Canonical := by
  intro input value rest accepted
  simp only [Wire.sum] at accepted
  split at accepted
  · rename_i tail
    cases parsed : left.decode tail with
    | error message => simp [parsed] at accepted
    | ok pair =>
      rcases pair with ⟨found,suffix⟩
      simp only [parsed,canonical_ok_map,Except.ok.injEq,Prod.mk.injEq] at accepted
      rcases accepted with ⟨rfl,rfl⟩
      simpa only [Wire.sum,List.cons_append] using congrArg (List.cons (0 : UInt8)) (a _ _ _ parsed)
  · rename_i tail
    cases parsed : right.decode tail with
    | error message => simp [parsed] at accepted
    | ok pair =>
      rcases pair with ⟨found,suffix⟩
      simp only [parsed,canonical_ok_map,Except.ok.injEq,Prod.mk.injEq] at accepted
      rcases accepted with ⟨rfl,rfl⟩
      simpa only [Wire.sum,List.cons_append] using congrArg (List.cons (1 : UInt8)) (b _ _ _ parsed)
  · contradiction

theorem list_spec_canonical {codec : Codec α} (original : codec.Canonical)
    (fuel : Nat) (input : List UInt8) (values : List α) (tail : List UInt8)
    (accepted : decodeListSpec codec fuel input = .ok (values,tail)) :
    encodeList codec values ++ tail = input := by
  induction fuel generalizing input values tail with
  | zero =>
    cases input with
    | nil => contradiction
    | cons byte rest =>
      by_cases zero : byte = 0
      · subst byte; cases accepted; rfl
      · simp [decodeListSpec,zero] at accepted
  | succ fuel ih =>
    cases input with
    | nil => contradiction
    | cons byte rest =>
      by_cases zero : byte = 0
      · subst byte; cases accepted; rfl
      · by_cases one : byte = 1
        · subst byte
          cases parsed : codec.decode rest with
          | error message => simp [decodeListSpec,parsed] at accepted
          | ok pair =>
            rcases pair with ⟨found,middle⟩
            cases next : decodeListSpec codec fuel middle with
            | error message => simp [decodeListSpec,parsed,next] at accepted
            | ok pair =>
              rcases pair with ⟨foundValues,suffix⟩
              simp only [decodeListSpec,parsed,next,canonical_ok_bind,canonical_ok_map,
                Except.ok.injEq,Prod.mk.injEq] at accepted
              rcases accepted with ⟨rfl,rfl⟩
              simpa only [encodeList,List.cons_append,List.append_assoc,ih middle foundValues tail next] using
                congrArg (List.cons (1 : UInt8)) (original rest found middle parsed)
        · simp [decodeListSpec,zero,one] at accepted

theorem Codec.Canonical.list {codec : Codec α} (original : codec.Canonical) :
    (Wire.list codec).Canonical := by
  intro input values tail accepted
  have exact := list_stream_exact codec input.length input [] (Nat.le_refl _)
  rw [list_loop_exact] at exact
  have spec : decodeListSpec codec input.length input = .ok (values,tail) := by
    simp only [Wire.list,exact,List.reverse_nil,List.nil_append] at accepted
    cases parsed : decodeListSpec codec input.length input with
    | error message => simp [parsed,Except.map] at accepted
    | ok pair =>
      have same : pair = (values,tail) := by simpa only [parsed,Except.map,Prod.eta,Except.ok.injEq] using accepted
      exact congrArg Except.ok same
  exact list_spec_canonical original input.length input values tail spec

theorem byteArray_list_loop (bytes : ByteArray) (index : Nat) (seen : List UInt8) :
    ByteArray.toList.loop bytes index seen = seen.reverse ++ bytes.data.toList.drop index := by
  fun_induction ByteArray.toList.loop bytes index seen with
  | case1 index seen inside ih =>
    rw [ih]
    have bound : index < bytes.data.toList.length := by simpa using inside
    rw [List.drop_eq_getElem_cons bound]
    have inData : index < bytes.data.size := by simpa using bound
    simp [List.reverse_cons,List.append_assoc,ByteArray.get!,getElem!_pos,inData]
    exact getElem!_pos bytes.data index inData
  | case2 index seen outside =>
    have bound : bytes.data.toList.length ≤ index := by simpa using Nat.le_of_not_lt outside
    simp [List.drop_eq_nil_of_le bound]

theorem byteArray_toList_exact (bytes : ByteArray) : bytes.toList = bytes.data.toList := by
  simpa only [ByteArray.toList,List.reverse_nil,List.nil_append,List.drop_zero] using byteArray_list_loop bytes 0 []

theorem byteArray_beq_self (bytes : ByteArray) : (bytes == bytes) = true := by
  change (bytes.data == bytes.data) = true
  exact beq_self_eq_true _

theorem Codec.Canonical.full {codec : Codec α} (canonical : codec.Canonical)
    (bytes : ByteArray) (value : α) (accepted : codec.decode bytes.toList = .ok (value,[])) :
    (codec.encode value).toByteArray = bytes := by
  have exact := canonical bytes.toList value [] accepted
  simp only [List.append_nil] at exact
  rw [exact]
  rw [byteArray_toList_exact]
  exact bytes_roundtrip bytes

def Codec.checkedPayload (codec : Codec α) (bytes : ByteArray) (trailing noncanonical : String) : Except String α := do
  let (value,tail) ← codec.decode bytes.toList
  unless tail.isEmpty do throw trailing
  unless (codec.encode value).toByteArray == bytes do throw noncanonical
  pure value

def Codec.payload (codec : Codec α) (bytes : ByteArray) (trailing : String) : Except String α := do
  let (value,tail) ← codec.decode bytes.toList
  unless tail.isEmpty do throw trailing
  pure value

theorem Codec.Canonical.payload_exact {codec : Codec α} (canonical : codec.Canonical)
    (bytes : ByteArray) (trailing noncanonical : String) :
    codec.payload bytes trailing = codec.checkedPayload bytes trailing noncanonical := by
  cases parsed : codec.decode bytes.toList with
  | error message => simp [Codec.payload,Codec.checkedPayload,parsed]
  | ok pair =>
    rcases pair with ⟨value,tail⟩
    cases tail with
    | nil => simp [Codec.payload,Codec.checkedPayload,parsed,canonical.full bytes value parsed,byteArray_beq_self]
    | cons byte rest =>
      simp [Codec.payload,Codec.checkedPayload,parsed,throw,throwThe,bind,Except.bind]
      rfl

#print axioms natural_canonical
#print axioms text_canonical
#print axioms Codec.Canonical.list
#print axioms Codec.Canonical.payload_exact

end Eggshell.DB.Wire
