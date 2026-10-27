module
public import Eggshell.GraphStore
public import Eggshell.MetadataBytes
public import Eggshell.ObservationContext
@[expose] public section

namespace Eggshell.Synapses.ObservedRecords
open Lean DB Persistence.Store _root_.Eggshell.Synapses.Extraction

/-- These describe literal representations, not tools or source semantics. -/
inductive Projection where
  | raw | rawLine | string | stringBody | stringBodyLine
  deriving Repr, DecidableEq, BEq, Hashable, ToJson, FromJson

structure Spelling where
  first : Nat
  limit : Nat
  projection : Projection
  deriving Repr, DecidableEq, BEq, Hashable

instance : ToJson Spelling where
  toJson spelling := toJson (spelling.first,spelling.limit,spelling.projection)
instance : FromJson Spelling where
  fromJson? json := do
    let (first,limit,projection) ← fromJson? (α := Nat × Nat × Projection) json
    return ⟨first,limit,projection⟩

structure Record where
  first : Nat
  limit : Nat
  field : Option Nat := none
  spellings : Array Spelling := #[]
  deriving BEq, Inhabited

instance : ToJson Record where
  toJson record := toJson (record.first,record.limit,record.field,record.spellings)
instance : FromJson Record where
  fromJson? json := do
    let (first,limit,field,spellings) ← fromJson? (α := Nat × Nat × Option Nat × Array Spelling) json
    return ⟨first,limit,field,spellings⟩

def project (characters : Array Char) (spelling : Spelling) : Option String := do
  if spelling.first ≥ spelling.limit || spelling.limit > characters.size then none else do
    let raw := String.ofList (characters.extract spelling.first spelling.limit).toList
    let line := fun text : String => if text.endsWith "\n" then (text.dropEnd 1).copy else text
    let body := do
      let text ← (Json.parse ("\"" ++ raw ++ "\"") >>= Json.getStr?).toOption
      if String.ofList ((toJson text).compress.toList.drop 1 |>.dropLast) == raw then some text else none
    match spelling.projection with
    | .raw => some raw
    | .rawLine => some (line raw)
    | .string => do
        let text ← (Json.parse raw >>= Json.getStr?).toOption
        if (toJson text).compress == raw then some text else none
    | .stringBody => body
    | .stringBodyLine => line <$> body

def chunkChars : Nat := 2048

/-- The base partition always retains every original character. Detailed
records add selectable structure; none can delete a base interval. -/
def base (size : Nat) : Array Record :=
  (Array.range (size/chunkChars+1)).filterMap fun index =>
    let first := index*chunkChars
    let limit := min size (first+chunkChars)
    if first < limit then some ⟨first,limit,none,#[]⟩ else none

theorem base_covers (size position : Nat) (inside : position < size) :
    ∃ record ∈ base size, record.first ≤ position ∧ position < record.limit := by
  let index := position/chunkChars
  have quotient : index < size/chunkChars+1 := by
    have := Nat.div_le_div_right (c := chunkChars) (Nat.le_of_lt inside)
    dsimp [index] at *
    omega
  have positive : 0 < chunkChars := by decide
  have divide := Nat.mod_add_div position chunkChars
  rw [Nat.mul_comm chunkChars (position/chunkChars)] at divide
  have remainder := Nat.mod_lt position positive
  have lower : index*chunkChars ≤ position := by dsimp [index]; omega
  have upper : position < index*chunkChars+chunkChars := by dsimp [index]; omega
  let record : Record := ⟨index*chunkChars,min size (index*chunkChars+chunkChars),none,#[]⟩
  have ordered : index*chunkChars < min size (index*chunkChars+chunkChars) := by omega
  refine ⟨record,?_,by dsimp [record]; omega⟩
  apply Array.mem_filterMap.mpr
  refine ⟨index,by simpa using quotient,?_⟩
  simp only [record,if_pos ordered]

def add (records : Array Record) (directory : Std.HashMap (Nat × Nat) Nat)
    (record : Record) : Array Record × Std.HashMap (Nat × Nat) Nat :=
  match directory[(record.first,record.limit)]? with
  | none => (records.push record,directory.insert (record.first,record.limit) records.size)
  | some index =>
      (records.modify index fun old => {
        old with
        field := old.field.or record.field
        spellings := hashDistinct (old.spellings.toList ++ record.spellings.toList) |>.toArray },directory)

/-- Only the original data determines record layout. No shell/input parser,
file alias, current question, model or external workspace is consulted. -/
def normalize (raw : String) : Array Record := Id.run do
  let characters := raw.toList.toArray
  let mut records := base characters.size
  let mut directory : Std.HashMap (Nat × Nat) Nat := {}
  for index in [:records.size] do
    directory := directory.insert (records[index]!.first,records[index]!.limit) index
  if let some json := JsonScalars.prepare? raw then
    for index in List.finRange json.leaves.size do
      let scalar := json.leaves[index].scalar
      let spellings := #[⟨scalar.contextFirst,scalar.limit,.raw⟩,
        ⟨scalar.first,scalar.limit,.raw⟩] ++
        (if scalar.text.isSome then #[⟨scalar.first,scalar.limit,.string⟩] else #[])
      let next := add records directory ⟨scalar.contextFirst,scalar.limit,some index.val,spellings⟩
      records := next.1; directory := next.2
      if let some text := scalar.text then
        if text.contains '\n' then
          for line in textLines text do
            let some first := scalar.offsets[line.first]? | continue
            let some limit := scalar.offsets[line.limit]? | continue
            let next := add records directory ⟨first,limit,some index.val,
              #[⟨first,limit,.raw⟩,⟨first,limit,.stringBodyLine⟩]⟩
            records := next.1; directory := next.2
  else
    for line in textLines raw do
      let next := add records directory ⟨line.first,line.limit,none,
        #[⟨line.first,line.limit,.raw⟩,⟨line.first,line.limit,.rawLine⟩]⟩
      records := next.1; directory := next.2
  return records

structure Prepared (raw : String) where
  records : Array Record

def prepare (raw : String) : Except String (Prepared raw) := do
  let records := normalize raw
  let characters := raw.toList.toArray
  for record in records do
    unless record.first < record.limit && record.limit ≤ characters.size do throw "invalid original record"
    for spelling in record.spellings do
      unless record.first ≤ spelling.first && spelling.limit ≤ record.limit do throw "foreign spelling interval"
      match project characters spelling with
      | some _ => pure ()
      | none => throw "spelling is not an original data projection"
  return ⟨records⟩

def implementation : String := Blake3.hex (Blake3.digest "eggshell.observed-records".toUTF8 [
  (include_str "ObservedRecords.lean").toUTF8,(include_str "JsonScalars.lean").toUTF8,
  (include_str "SynapseSource.lean").toUTF8])

structure Header where
  database : String
  owner : String
  work : String
  original : Original
  implementation : String
  records : Nat
  chunks : Array String
  deriving BEq, ToJson, FromJson

def keyPrefix := "memo:observed-record:"
def ownerKey (id : Nat) := keyPrefix ++ "owner:" ++ toString id
def chunkKey (digest : String) := keyPrefix ++ "chunk:" ++ digest
def chunkRecords : Nat := 64

def decode [ToJson α] [FromJson α] (bytes : ByteArray) : IO α := do
  unless bytes.size ≤ 262144 do throw (IO.userError "original record metadata exceeds its block bound")
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid original metadata UTF-8")
  let value ← IO.ofExcept (Json.parse text >>= fromJson? (α := α))
  unless (toJson value).compress.toUTF8 == bytes do throw (IO.userError "noncanonical original metadata")
  return value

def stage (writer : PageMap.Writer) (id : Nat) (doc : Document) : IO Bool := do
  unless doc.native do throw (IO.userError "record publication requires its original native owner")
  let some raw := doc.source | throw (IO.userError "native record publication lost its original body")
  let prepared ← IO.ofExcept (prepare raw)
  let mut chunks := #[]
  let mut changed := false
  for index in [: (prepared.records.size+chunkRecords-1)/chunkRecords] do
    let records := prepared.records.extract (index*chunkRecords) ((index+1)*chunkRecords)
    let bytes := (toJson records).compress.toUTF8
    let payload ← IO.ofExcept (MetadataBytes.checked bytes)
    let digest := Sha256.hex bytes
    let key := chunkKey digest
    if ← MetadataBytes.put writer key payload true then changed := true
    chunks := chunks.push digest
  let pinned ← writer.snapshot
  let header : Header := ⟨pinned.head.identity,doc.owner,doc.work,
    ObservationContext.originalSubject doc.work raw,implementation,prepared.records.size,chunks⟩
  let bytes := (toJson header).compress.toUTF8
  let payload ← IO.ofExcept (MetadataBytes.checked bytes)
  if ← MetadataBytes.put writer (ownerKey id) payload then changed := true
  return changed

def catalog (database : String) (doc : Document) (records : Array Record) : Except String ObservationContext.Catalog := do
  let some raw := doc.source | throw "missing native record body"
  let characters := raw.toList.toArray
  let some occurrence := doc.occurrences[0]? | throw "missing original record occurrence"
  let original := ObservationContext.originalSubject doc.work raw
  let quoteSource : QuotationContext.Source := ⟨raw,characters,rfl,original.content,rfl⟩
  let mut result : ObservationContext.Catalog := {}
  for record in records do
    unless record.first < record.limit && record.limit ≤ characters.size do throw "invalid original record interval"
    let texts ← record.spellings.mapM fun spelling => do
      unless record.first ≤ spelling.first && spelling.limit ≤ record.limit do throw "foreign original spelling"
      match project characters spelling with
      | some text => pure text
      | none => throw "invalid original spelling projection"
    let texts := hashDistinct texts.toList |>.toArray
    let read : Read := {
      occurrence
      source := Range.original original record.first record.limit
      binding := ⟨database,doc.owner,doc.work,record.first,record.limit⟩
      quotations := texts.filter (!·.isEmpty) |>.map Quotes.digest }
    unless read.valid do throw "invalid original record binding"
    let payload := String.ofList (characters.extract record.first record.limit).toList
    result := {
      located := result.located.push ⟨read,#[⟨read.source,record.first,record.limit⟩],#[read],payload⟩
      quotations := result.quotations ++ record.spellings.filterMap (fun spelling => do
        let text ← project characters spelling
        if text.isEmpty then none else
          some (ObservationContext.Quotation.prepare quoteSource read spelling.first spelling.limit text)) }
  return result

/-- One source-owned directory lookup; no source repair or external file read.
An old source may be normalized by explicit background preparation instead. -/
def load? (source : PageMap.Snapshot) (id : Nat) (doc : Document) : IO (Option ObservationContext.Catalog) := do
  let some payload ← MetadataBytes.get? source (ownerKey id) | return none
  let header ← decode (α := Header) payload.bytes
  if header.implementation != implementation then return none
  let some raw := doc.source | throw (IO.userError "original record header lost its source")
  unless doc.native && header.database == source.head.identity && header.owner == doc.owner &&
      header.work == doc.work && header.original == ObservationContext.originalSubject doc.work raw do
    throw (IO.userError "original record directory belongs to another observation")
  let mut records := #[]
  for digest in header.chunks do
    let some payload ← MetadataBytes.get? source (chunkKey digest) | throw (IO.userError "missing original record block")
    unless Sha256.hex payload.bytes == digest do throw (IO.userError "original record block digest mismatch")
    let block ← decode (α := Array Record) payload.bytes
    unless block.size ≤ chunkRecords do throw (IO.userError "oversized original record block")
    records := records ++ block
  unless records.size == header.records do throw (IO.userError "original record directory count mismatch")
  let spans := records.foldl (fun known record => known.insert (record.first,record.limit)) ({} : Std.HashSet (Nat × Nat))
  unless (base raw.length).all (fun record => spans.contains (record.first,record.limit)) do
    throw (IO.userError "original record domain omits its complete base partition")
  return some (← IO.ofExcept (catalog source.head.identity doc records))

theorem metadata_preserves_authority (before : String → Option ByteArray) (id : Nat)
    (bytes : ByteArray) (key : String) (outside : PageMap.derivedKey key = false) :
    PageMap.applyRows [(ownerKey id,some bytes)] before key = before key := by
  apply PageMap.derived_rows_preserve _ _ _ key outside
  simp [ownerKey,keyPrefix,PageMap.derivedKey]

theorem block_preserves_authority (before : String → Option ByteArray) (digest : String)
    (bytes : ByteArray) (key : String) (outside : PageMap.derivedKey key = false) :
    PageMap.applyRows [(chunkKey digest,some bytes)] before key = before key := by
  apply PageMap.derived_rows_preserve _ _ _ key outside
  simp [chunkKey,keyPrefix,PageMap.derivedKey]

end Eggshell.Synapses.ObservedRecords
