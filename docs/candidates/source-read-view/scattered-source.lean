module
public import Eggshell.ObservedRecords
public import Eggshell.ContentMetadata
public import Eggshell.SynapticTopology
@[expose] public section

namespace Eggshell.Synapses.SourceReadView
open Lean DB Persistence.Store _root_.Eggshell.Synapses.Extraction

/-- Only a native publisher compiles this view. Its rows are advisory
original coordinates, never Work equality, Union or completion authority. -/
def bound (database : String) (doc : Document) (read : Read) : Bool :=
  read.valid && read.binding.database == database && read.binding.owner == doc.owner &&
    read.binding.work == doc.work && doc.occurrences.contains read.occurrence

structure Prepared (database : String) (doc : Document) where
  rows : Array Read
  checked : rows.all (bound database doc) = true

def prepare (database : String) (doc : Document) (raw : String)
    (records : ObservedRecords.Prepared raw) (capture : Option ContentCapture.Captured) :
    Except String (Prepared database doc) := do
  unless doc.native && doc.source == some raw do throw "read view lost its native original"
  let original ← ObservedRecords.catalog database doc records.records
  let captured ← match capture with
    | some capture => do
      unless digest capture.implementation && (capture.complete || capture.aliases.isEmpty) &&
          capture.aliases.all (ContentMetadata.validAlias capture.inputs raw.toList.toArray) do
        throw "read view contains unverified file correspondences"
      ContentMetadata.catalog database doc capture
    | none => pure ({} : ObservationContext.Catalog)
  let files := (recordedReads database doc).toOption.getD #[]
  let located := files ++ captured.located ++ original.located
  let rows := located.map (·.read) ++ located.flatMap (·.originalRows)
  let unique := rows.foldl (fun (seen : Std.HashSet Read) row => seen.insert row) {}
  let rows := (unique.toArray.map (fun row => (Index.contentKey (Fact.read row),row))).qsort
    (fun a b => a.1 < b.1) |>.map (·.2)
  if checked : rows.all (bound database doc) = true then return ⟨rows,checked⟩
  else throw "read view contains a foreign original row"

theorem prepared_row_bound (prepared : Prepared database doc) (row : Read)
    (member : row ∈ prepared.rows) : bound database doc row = true := by
  exact (Array.all_eq_true_iff_forall_mem.mp prepared.checked) row member

def implementation : String := Blake3.hex (Blake3.digest "eggshell.source-read-view".toUTF8 [
  (include_str "SourceReadView.lean").toUTF8,ObservedRecords.implementation.toUTF8,
  ContentCapture.implementation.toUTF8,(include_str "SynapseSource.lean").toUTF8])

structure Header where
  database : String
  authority : String
  owner : String
  work : String
  original : Original
  occurrences : Array Occurrence
  producer : String
  rows : Nat
  blocks : Array String
  deriving BEq,ToJson,FromJson

structure Posting where
  owner : Nat
  ordinal : Nat
  deriving BEq,ToJson,FromJson

def ownerKey (id : Nat) := "memo:" ++ ("source-read-view:owner:" ++ toString id)
def blockKey (digest : String) := "memo:" ++ ("source-read-view:block:" ++ digest)
def subjectBase (subject : Subject) := "memo:" ++ ("source-read-view:subject:" ++ Index.contentKey subject)
def postingKey (read : Read) := subjectBase read.source.subject ++ ":" ++ Index.contentKey (Fact.read read)
def blockRows : Nat := 64

private theorem memo_key (suffix : String) : PageMap.derivedKey ("memo:" ++ suffix) = true :=
  String.startsWith_string_iff.mpr ⟨suffix.toList,by simp only [String.toList_append]⟩

theorem owner_key_derived (id : Nat) : PageMap.derivedKey (ownerKey id) = true := memo_key _
theorem block_key_derived (digest : String) : PageMap.derivedKey (blockKey digest) = true := memo_key _
theorem posting_key_derived (read : Read) : PageMap.derivedKey (postingKey read) = true := by
  simpa only [postingKey,subjectBase,String.append_assoc] using
    memo_key ("source-read-view:subject:" ++ Index.contentKey read.source.subject ++ ":" ++ Index.contentKey (Fact.read read))

/-- The owner header commits bounded content-addressed row blocks. A subject
posting is only a position in those blocks, not a second copy of every Read. -/
def stage (writer : PageMap.Writer) (id : Nat) (doc : Document) (raw : String)
    (prepared : Prepared writer.base.head.identity doc) : IO Bool := do
  unless doc.native && doc.source == some raw && (← writer.get (key "member" id)).isSome do
    throw (IO.userError "read view owner is not a staged native original")
  let mut changed := false
  let mut blocks := #[]
  for page in [: (prepared.rows.size+blockRows-1)/blockRows] do
    let rows := prepared.rows.extract (page*blockRows) ((page+1)*blockRows)
    let bytes := (toJson rows).compress.toUTF8
    let digest := Sha256.hex bytes
    if ← MetadataBytes.put writer (blockKey digest) (← IO.ofExcept (MetadataBytes.checked bytes)) true then changed := true
    blocks := blocks.push digest
  for ordinal in [:prepared.rows.size] do
    let row := prepared.rows[ordinal]!
    let bytes := (toJson ({owner := id,ordinal} : Posting)).compress.toUTF8
    let name := postingKey row
    unless (← writer.get name).any (· == bytes) do
      if (← writer.get name).isSome then throw (IO.userError "source read posting changed its immutable owner")
      writer.put name (some bytes)
      changed := true
  let header : Header := {
    database := writer.base.head.identity,authority := writer.base.head.authority
    owner := doc.owner,work := doc.work,original := ObservationContext.originalSubject doc.work raw
    occurrences := doc.occurrences,producer := implementation,rows := prepared.rows.size,blocks}
  if let some previous ← MetadataBytes.pending? writer (ownerKey id) then
    let old ← ObservedRecords.decode (α := Header) previous.bytes
    -- A producer is historical provenance. Re-publishing identical original
    -- rows does not replace it just because the running implementation changed.
    unless digest old.producer && {old with producer := implementation} == header do
      throw (IO.userError "source read view changed its immutable original")
  else
    let bytes := (toJson header).compress.toUTF8
    if ← MetadataBytes.put writer (ownerKey id) (← IO.ofExcept (MetadataBytes.checked bytes)) true then changed := true
  return changed

structure Reader (source : PageMap.Snapshot) where
  headers : IO.Ref (Std.HashMap Nat Header)
  blocks : IO.Ref (Std.HashMap String (Array Read))
  charged : IO.Ref Nat
  maxBytes : Nat := 16*1024*1024

def reader (source : PageMap.Snapshot) : IO (Reader source) := return {
  headers := ← IO.mkRef {},blocks := ← IO.mkRef {},charged := ← IO.mkRef 0}

def Reader.retain (reader : Reader source) (encodedBytes : Nat) (store : IO Unit) : IO Unit := do
  let charge := 4096+4*encodedBytes
  if (← reader.charged.get)+charge ≤ reader.maxBytes &&
      (← reader.headers.get).size+(← reader.blocks.get).size < 1024 then
    store
    reader.charged.modify (·+charge)

def Reader.row (reader : Reader source) (posting : Posting) : IO Read := do
  let header ← match (← reader.headers.get)[posting.owner]? with
    | some header => pure header
    | none => do
      let some payload ← MetadataBytes.get? source (ownerKey posting.owner) |
        throw (IO.userError "source read posting lost its owner directory")
      let header ← ObservedRecords.decode (α := Header) payload.bytes
      unless header.database == source.head.identity && header.authority == source.head.authority &&
          digest header.producer && header.original.valid && header.original.work == header.work &&
          header.occurrences.all Occurrence.valid &&
          header.blocks.size == (header.rows+blockRows-1)/blockRows do
        throw (IO.userError "source read directory has another DB, scope or extent")
      reader.retain payload.bytes.size (reader.headers.modify (·.insert posting.owner header))
      pure header
  unless posting.ordinal < header.rows do throw (IO.userError "source read posting exceeds its owner")
  let page := posting.ordinal/blockRows
  let hash := header.blocks[page]!
  let block ← match (← reader.blocks.get)[hash]? with
    | some block => pure block
    | none => do
      unless digest hash do throw (IO.userError "invalid source read block address")
      let some payload ← MetadataBytes.get? source (blockKey hash) |
        throw (IO.userError "source read posting lost its original block")
      unless Sha256.hex payload.bytes == hash do throw (IO.userError "source read block checksum differs")
      let block ← ObservedRecords.decode (α := Array Read) payload.bytes
      unless block.size == min blockRows (header.rows-page*blockRows) do
        throw (IO.userError "source read block differs from its extent")
      reader.retain payload.bytes.size (reader.blocks.modify (·.insert hash block))
      pure block
  let row := block[posting.ordinal%blockRows]!
  unless row.valid && row.binding.database == header.database && row.binding.owner == header.owner &&
      row.binding.work == header.work && header.occurrences.contains row.occurrence do
    throw (IO.userError "source read block contains another original")
  return row

structure Result where
  rows : Array Read := #[]
  pages : Nat := 0
  inspected : Nat := 0
  complete : Bool := true
  deriving ToJson

def Reader.scan (reader : Reader source) (subject : Subject) (range : PageMap.KeyRange) (ref : PageMap.Ref)
    (limit deadline : Nat) (initial : Result) : IO Result := do
  if !initial.complete then return initial
  if initial.inspected ≥ limit || (← IO.monoMsNow) ≥ deadline then return {initial with complete := false}
  unless range.overlaps ref do return initial
  let loaded ← source.load ref
  let mut result := {initial with pages := initial.pages+1}
  match loaded.page with
  | .leaf rows =>
    for (name,encoded) in range.select rows do
      if result.inspected ≥ limit || (← IO.monoMsNow) ≥ deadline then return {result with complete := false}
      let some encoded := encoded | continue
      let posting ← ObservedRecords.decode (α := Posting) encoded
      result := {result with inspected := result.inspected+1}
      -- Retired owners are absent in this exact source snapshot. An older
      -- pinned source retains both its membership and its immutable view.
      if (← source.get (key "member" posting.owner)).isNone then continue
      let row ← reader.row posting
      unless row.source.subject == subject && name == postingKey row do
        throw (IO.userError "source read posting has another subject or row digest")
      result := {result with rows := result.rows.push row}
    return result
  | .branch children =>
    for child in children do
      if range.overlaps child then
        if _smaller : child.height < ref.height then result ← reader.scan subject range child limit deadline result
        else throw (IO.userError "source read index height did not decrease")
        if !result.complete then return result
    return result
termination_by ref.height

def Reader.lookup (reader : Reader source) (subject : Subject) (limit deadline : Nat) : IO Result := do
  unless subject.valid do throw (IO.userError "invalid source read subject")
  let base := subjectBase subject
  let range : PageMap.KeyRange := ⟨base ++ ":",base ++ ";"⟩
  match source.head.root with
  | none => return {}
  | some root => reader.scan subject range root limit deadline {}

end Eggshell.Synapses.SourceReadView
