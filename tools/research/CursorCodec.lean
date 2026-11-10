module
public import tools.research.CanonicalCodec
public import Init.Data.List.TakeDrop
@[expose] public section
namespace Eggshell.DB.CursorCodec
open Wire

/-- A borrowed byte buffer and a checked offset. No unread-byte list is
constructed by the executable reader. -/
structure Cursor (input : ByteArray) where
  position : Nat
  bounded : position ≤ input.size

def Cursor.rest (cursor : Cursor input) : List UInt8 := input.data.toList.drop cursor.position
def Cursor.next (cursor : Cursor input) (inside : cursor.position < input.size) : Cursor input :=
  ⟨cursor.position+1,by omega⟩

theorem Cursor.rest_cons (cursor : Cursor input) (inside : cursor.position < input.size) :
    cursor.rest = input[cursor.position] :: (cursor.next inside).rest := by
  unfold rest next
  rw [List.drop_eq_getElem_cons (by simpa using inside)]
  rfl

theorem Cursor.rest_empty (cursor : Cursor input) (outside : ¬cursor.position < input.size) :
    cursor.rest = [] := List.drop_eq_nil_of_le (by simpa using Nat.le_of_not_lt outside)

def result (parsed : Except String (α × Cursor input)) : Except String (α × List UInt8) :=
  parsed.map fun (value,next) => (value,next.rest)

/-- The reference codec occurs only in the erased type and certificate. -/
structure Reader (codec : Wire.Codec α) where
  run : {input : ByteArray} → Cursor input → Except String (α × Cursor input)
  exact : ∀ {input} (cursor : Cursor input), result (run cursor) = codec.decode cursor.rest

def Reader.product {a : Wire.Codec α} {b : Wire.Codec β}
    (left : Reader a) (right : Reader b) : Reader (a.product b) where
  run cursor := do
    let (a,next) ← left.run cursor
    let (b,next) ← right.run next
    return ((a,b),next)
  exact cursor := by
    dsimp only [Wire.Codec.product]
    have first := left.exact cursor
    cases parsed : left.run cursor with
    | error message =>
      rw [parsed] at first
      change .error message = a.decode cursor.rest at first
      rw [← first]
      rfl
    | ok pair =>
      rcases pair with ⟨x,next⟩
      rw [parsed] at first
      change Except.ok (x,next.rest) = a.decode cursor.rest at first
      rw [← first]
      dsimp only [bind,Except.bind]
      have second := right.exact next
      cases parsedRight : right.run next with
      | error message =>
        rw [parsedRight] at second
        change .error message = b.decode next.rest at second
        rw [← second]
        rfl
      | ok pair =>
        rcases pair with ⟨y,last⟩
        rw [parsedRight] at second
        change Except.ok (y,last.rest) = b.decode next.rest at second
        rw [← second]
        rfl

def Reader.iso {codec : Wire.Codec β} (reader : Reader codec) (encode : α → β) (decode : β → α)
    (inverse : ∀ value, decode (encode value) = value) : Reader (codec.iso encode decode inverse) where
  run cursor := do
    let (value,next) ← reader.run cursor
    return (decode value,next)
  exact cursor := by
    dsimp only [Wire.Codec.iso]
    have exact := reader.exact cursor
    cases parsed : reader.run cursor with
    | error message =>
      rw [parsed] at exact
      change .error message = codec.decode cursor.rest at exact
      rw [← exact]
      rfl
    | ok pair =>
      rcases pair with ⟨value,next⟩
      rw [parsed] at exact
      change Except.ok (value,next.rest) = codec.decode cursor.rest at exact
      rw [← exact]
      rfl

def octet : Reader Wire.octet where
  run {input} cursor :=
    if inside : cursor.position < _ then .ok (input[cursor.position],cursor.next inside)
    else .error "truncated octet"
  exact cursor := by
    split
    · rename_i inside
      rw [cursor.rest_cons inside]
      rfl
    · rename_i outside
      rw [cursor.rest_empty outside]
      rfl

/-- Continuation digits alone may use a small list; string payload bytes
never pass through it. Arbitrarily large valid integers retain their meaning. -/
def naturalLoop (cursor : Cursor input) (seen : List UInt8) : Except String (Nat × Cursor input) :=
  if inside : cursor.position < input.size then
    let byte := input[cursor.position]
    let next := cursor.next inside
    if byte.toNat < 128 then
      if byte.toNat == 0 && !seen.isEmpty then .error "noncanonical integer"
      else .ok (seen.foldl Wire.natStep byte.toNat,next)
    else naturalLoop next (byte :: seen)
  else .error "truncated integer"
termination_by input.size-cursor.position
decreasing_by simp [Cursor.next]; omega

theorem natural_loop_exact (cursor : Cursor input) (seen : List UInt8) :
    result (naturalLoop cursor seen) = Wire.decodeNatLoop cursor.rest seen := by
  rw [naturalLoop]
  by_cases inside : cursor.position < input.size
  · rw [dif_pos inside,cursor.rest_cons inside,Wire.decodeNatLoop]
    dsimp only
    by_cases small : input[cursor.position].toNat < 128
    · rw [if_pos small,if_pos small]
      simp only [Wire.finishNat,result]
      split <;> rfl
    · rw [if_neg small,if_neg small]
      exact natural_loop_exact (cursor.next inside) (input[cursor.position] :: seen)
  · rw [dif_neg inside,cursor.rest_empty inside]
    rfl
termination_by input.size-cursor.position
decreasing_by simp [Cursor.next]; omega

def natural : Reader Wire.natural where
  run cursor := naturalLoop cursor []
  exact cursor := natural_loop_exact cursor []

theorem Reader.progress {codec : Wire.Codec α} (reader : Reader codec) (cursor next : Cursor input) (value : α)
    (accepted : reader.run cursor = .ok (value,next)) : cursor.position ≤ next.position := by
  have parsed := reader.exact cursor
  simp only [accepted,result,Except.map] at parsed
  have bounded := codec.remaining cursor.rest value next.rest parsed.symm
  have first := cursor.bounded
  have last := next.bounded
  simp only [Cursor.rest,List.length_drop,Array.length_toList] at bounded
  change input.data.size-next.position ≤ input.data.size-cursor.position at bounded
  change cursor.position ≤ input.data.size at first
  change next.position ≤ input.data.size at last
  omega

theorem take_bytes_explicit (count : Nat) (bytes seen : List UInt8) :
    Wire.takeBytes count bytes seen =
      if count ≤ bytes.length then .ok (seen.reverse++bytes.take count,bytes.drop count)
      else .error "truncated byte string" := by
  induction count generalizing bytes seen with
  | zero => simp [Wire.takeBytes]
  | succ count ih =>
    cases bytes with
    | nil => simp [Wire.takeBytes]
    | cons byte rest =>
      simp [Wire.takeBytes,ih,List.reverse_cons,List.append_assoc]

def block (cursor : Cursor input) (count : Nat) : Except String (ByteArray × Cursor input) :=
  if fits : cursor.position+count ≤ input.size then
    .ok (input.extract cursor.position (cursor.position+count),⟨cursor.position+count,fits⟩)
  else .error "truncated byte string"

theorem block_exact (cursor : Cursor input) (count : Nat) :
    result (block cursor count) =
      (Wire.takeBytes count cursor.rest []).map fun (value,rest) => (value.toByteArray,rest) := by
  rw [take_bytes_explicit]
  have length : cursor.rest.length = input.size-cursor.position := by
    simp only [Cursor.rest,List.length_drop,Array.length_toList,ByteArray.size_data]
  have bounded := cursor.bounded
  by_cases fits : cursor.position+count ≤ input.size
  · have enough : count ≤ cursor.rest.length := by omega
    rw [if_pos enough,block,dif_pos fits]
    change Except.ok (_,_) = Except.ok (_, _)
    congr 1
    apply Prod.ext
    · apply ByteArray.ext
      apply Array.toList_inj.mp
      simp [ByteArray.data_extract,Array.toList_extract,List.extract_eq_take_drop,Cursor.rest]
    · simp [Cursor.rest,List.drop_drop]
  · have insufficient : ¬count ≤ cursor.rest.length := by omega
    rw [if_neg insufficient,block,dif_neg fits]
    rfl

def byteBlob : Reader Wire.byteBlob where
  run cursor := do
    let (count,next) ← natural.run cursor
    block next count
  exact cursor := by
    change result (do let (count,next) ← natural.run cursor; block next count) = Wire.decodeByteBlob cursor.rest
    rw [Wire.decodeByteBlob_reference]
    dsimp only [Wire.blob]
    have first := natural.exact cursor
    cases parsed : natural.run cursor with
    | error message =>
      rw [parsed] at first
      change .error message = Wire.natural.decode cursor.rest at first
      rw [← first]
      rfl
    | ok pair =>
      rcases pair with ⟨count,next⟩
      rw [parsed] at first
      change Except.ok (count,next.rest) = Wire.natural.decode cursor.rest at first
      rw [← first]
      exact block_exact next count

def text : Reader Wire.text where
  run cursor := do
    let (encoded,next) ← byteBlob.run cursor
    match String.fromUTF8? encoded with
    | some value => return (value,next)
    | none => throw "invalid UTF-8 in binary index"
  exact cursor := by
    have original := byteBlob.exact cursor
    change result (byteBlob.run cursor) = Wire.decodeByteBlob cursor.rest at original
    rw [Wire.decodeByteBlob_reference] at original
    dsimp only [Wire.text]
    cases direct : byteBlob.run cursor with
    | error message =>
      rw [direct] at original
      cases reference : Wire.blob.decode cursor.rest with
      | error error =>
        rw [reference] at original
        cases original
        rfl
      | ok pair => simp [reference,result,Except.map] at original
    | ok pair =>
      rcases pair with ⟨encoded,next⟩
      rw [direct] at original
      cases reference : Wire.blob.decode cursor.rest with
      | error message => simp [reference,result,Except.map] at original
      | ok pair =>
        rcases pair with ⟨value,rest⟩
        rw [reference] at original
        have same : encoded = value.toByteArray ∧ next.rest = rest := by
          simpa only [result,Except.map,Except.ok.injEq,Prod.mk.injEq] using original
        dsimp only [bind,Except.bind]
        rw [← same.1,← same.2]
        cases String.fromUTF8? encoded <;> rfl

theorem result_map (parsed : Except String (α × Cursor input)) (f : α → β) :
    result (parsed.map fun (value,next) => (f value,next)) =
      (result parsed).map fun (value,rest) => (f value,rest) := by
  cases parsed <;> rfl

def Reader.sum {a : Wire.Codec α} {b : Wire.Codec β}
    (left : Reader a) (right : Reader b) : Reader (Wire.sum a b) where
  run {input} cursor :=
    if inside : cursor.position < input.size then
      let next := cursor.next inside
      if input[cursor.position] = 0 then (left.run next).map fun (value,last) => (Sum.inl value,last)
      else if input[cursor.position] = 1 then (right.run next).map fun (value,last) => (Sum.inr value,last)
      else .error "invalid variant tag"
    else .error "invalid variant tag"
  exact {input} cursor := by
    by_cases inside : cursor.position < input.size
    · rw [dif_pos inside,cursor.rest_cons inside]
      dsimp only
      by_cases zero : input[cursor.position] = 0
      · simp only [zero,↓reduceIte,result_map,left.exact,Wire.sum]
        rfl
      · by_cases one : input[cursor.position] = 1
        · rw [if_neg zero,if_pos one,result_map,right.exact]
          rw [one]
          rfl
        · simp [zero,one,result,Wire.sum,Except.map]
    · rw [dif_neg inside,cursor.rest_empty inside]
      rfl

def listLoop {codec : Wire.Codec α} (reader : Reader codec) (cursor : Cursor input) (seen : List α) :
    Except String (List α × Cursor input) :=
  if inside : cursor.position < input.size then
    let next := cursor.next inside
    if input[cursor.position] = 0 then .ok (seen.reverse,next)
    else if input[cursor.position] = 1 then
      match parsed : reader.run next with
      | .error error => .error error
      | .ok (value,last) => listLoop reader last (value::seen)
    else .error "invalid or truncated list"
  else .error "invalid or truncated list"
termination_by input.size-cursor.position
decreasing_by
  have advanced := reader.progress (cursor.next inside) last value parsed
  simp only [Cursor.next] at advanced
  have bounded := last.bounded
  omega

theorem list_loop_exact {codec : Wire.Codec α} (reader : Reader codec)
    (cursor : Cursor input) (seen : List α) :
    result (listLoop reader cursor seen) = Wire.decodeListStream codec cursor.rest seen := by
  rw [listLoop]
  by_cases inside : cursor.position < input.size
  · rw [dif_pos inside,cursor.rest_cons inside]
    dsimp only
    by_cases zero : input[cursor.position] = 0
    · simp [zero,result,Wire.decodeListStream,Except.map]
    · by_cases one : input[cursor.position] = 1
      · rw [if_neg zero,if_pos one,one,Wire.decodeListStream]
        have exact := reader.exact (cursor.next inside)
        cases parsed : reader.run (cursor.next inside) with
        | error message =>
          rw [parsed] at exact
          change .error message = codec.decode (cursor.next inside).rest at exact
          rw [← exact]
          rfl
        | ok pair =>
          rcases pair with ⟨value,last⟩
          rw [parsed] at exact
          change Except.ok (value,last.rest) = codec.decode (cursor.next inside).rest at exact
          rw [← exact]
          exact list_loop_exact reader last (value::seen)
      · simp [zero,one,result,Wire.decodeListStream,Except.map]
  · rw [dif_neg inside,cursor.rest_empty inside]
    simp [Wire.decodeListStream,result,Except.map]
termination_by input.size-cursor.position
decreasing_by
  have advanced := reader.progress (cursor.next inside) last value parsed
  simp only [Cursor.next] at advanced
  have bounded := last.bounded
  omega

def Reader.list {codec : Wire.Codec α} (reader : Reader codec) : Reader (Wire.list codec) where
  run cursor := listLoop reader cursor []
  exact cursor := list_loop_exact reader cursor []

def Reader.optional {codec : Wire.Codec α} (reader : Reader codec) : Reader (Wire.optional codec) where
  run {input} cursor :=
    if inside : cursor.position < input.size then
      let next := cursor.next inside
      if input[cursor.position] = 0 then .ok (none,next)
      else if input[cursor.position] = 1 then (reader.run next).map fun (value,last) => (some value,last)
      else .error "invalid option tag"
    else .error "invalid option tag"
  exact {input} cursor := by
    by_cases inside : cursor.position < input.size
    · rw [dif_pos inside,cursor.rest_cons inside]
      dsimp only
      by_cases zero : input[cursor.position] = 0
      · simp [zero,result,Wire.optional,Except.map]
      · by_cases one : input[cursor.position] = 1
        · rw [if_neg zero,if_pos one,result_map,reader.exact,one]
          rfl
        · simp [zero,one,result,Wire.optional,Except.map]
    · rw [dif_neg inside,cursor.rest_empty inside]
      rfl

theorem Cursor.empty_iff (cursor : Cursor input) : cursor.rest.isEmpty = true ↔ cursor.position = input.size := by
  rw [List.isEmpty_iff]
  constructor
  · intro empty
    have length : cursor.rest.length = 0 := by rw [empty]; rfl
    simp only [Cursor.rest,List.length_drop,Array.length_toList,ByteArray.size_data] at length
    have bounded := cursor.bounded
    omega
  · intro ended
    exact cursor.rest_empty (by omega)

def Reader.payload {codec : Wire.Codec α} (reader : Reader codec) (bytes : ByteArray)
    (trailing : String) : Except String α := do
  let (value,next) ← reader.run (⟨0,Nat.zero_le _⟩ : Cursor bytes)
  if next.position == bytes.size then return value else throw trailing

theorem Reader.payload_exact {codec : Wire.Codec α} (reader : Reader codec)
    (bytes : ByteArray) (trailing : String) : reader.payload bytes trailing = codec.payload bytes trailing := by
  unfold Reader.payload Wire.Codec.payload
  let initial : Cursor bytes := ⟨0,Nat.zero_le _⟩
  have reference := reader.exact initial
  change result (reader.run initial) = codec.decode (bytes.data.toList.drop 0) at reference
  rw [List.drop_zero,← Wire.byteArray_toList_exact] at reference
  cases parsed : reader.run initial with
  | error message =>
    rw [parsed] at reference
    change .error message = codec.decode bytes.toList at reference
    rw [← reference]
    rfl
  | ok pair =>
    rcases pair with ⟨value,next⟩
    rw [parsed] at reference
    change Except.ok (value,next.rest) = codec.decode bytes.toList at reference
    rw [← reference]
    dsimp only [bind,Except.bind]
    have same : (next.position == bytes.size) = next.rest.isEmpty := by
      apply Bool.eq_iff_iff.mpr
      simp only [beq_iff_eq,next.empty_iff]
    rw [same]
    cases next.rest.isEmpty <;> rfl

#print axioms natural_loop_exact
#print axioms block_exact
#print axioms text
#print axioms list_loop_exact
#print axioms Reader.payload_exact
end Eggshell.DB.CursorCodec
