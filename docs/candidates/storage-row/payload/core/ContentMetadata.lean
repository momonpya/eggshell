module
public import Eggshell.ContentCapture
public import Eggshell.MetadataBytes
@[expose] public section

namespace Eggshell.ContentMetadata
open Lean DB Synapses Synapses.Extraction Persistence.Store

structure Header where
  database : String
  owner : String
  work : String
  original : String
  implementation : String
  inputs : Array SourceEvidence.File
  complete : Bool
  failure : Option String
  aliases : Nat
  chunks : Array String
  deriving ToJson, FromJson

def ownerKey (id : Nat) := "memo:content-alias:owner:" ++ toString id
def chunkKey (digest : String) := "memo:content-alias:chunk:" ++ digest
def chunkCount : Nat := 64

structure Line (raw : String) where
  alias : ContentCapture.Alias
  code : String
  original : ContentCapture.code? raw.toList.toArray alias = some code
  within : alias.first < alias.limit ∧ alias.limit ≤ raw.length

def line? (raw : String) (alias : ContentCapture.Alias) : Option (Line raw) := do
  if within : alias.first < alias.limit ∧ alias.limit ≤ raw.length then
    match original : ContentCapture.code? raw.toList.toArray alias with
    | some code => some ⟨alias,code,original,within⟩
    | none => none
  else none

theorem Line.original_projection (line : Line raw) :
    ContentCapture.code? raw.toList.toArray line.alias = some line.code := line.original

theorem Line.original_bounds (line : Line raw) :
    line.alias.first < line.alias.limit ∧ line.alias.limit ≤ raw.length := line.within

def validAlias (inputs : Array SourceEvidence.File) (characters : Array Char)
    (alias : ContentCapture.Alias) : Bool :=
  alias.file.valid && 0 < alias.line && alias.first < alias.limit && alias.limit ≤ characters.size &&
    (ContentCapture.code? characters alias).isSome && inputs.any (fun file =>
      file.relative == alias.file.relative && file.content == some ⟨alias.file.bytes,alias.file.fingerprint⟩)

/-- Source metadata joins original bytes and portable origins in their one
existing transaction. No second writer, source reopen or derived repair. -/
def stage (writer : PageMap.Writer) (id : Nat) (doc : Document)
    (captured : ContentCapture.Captured) : IO Bool := do
  unless doc.native && captured.implementation == ContentCapture.implementation do
    throw (IO.userError "content correspondence is not from the selected native capture")
  let some raw := doc.source | throw (IO.userError "content correspondence lost its original body")
  let characters := raw.toList.toArray
  unless (captured.complete || captured.aliases.isEmpty) &&
      captured.aliases.all (validAlias captured.inputs characters) do
    throw (IO.userError "invalid content correspondence projection")
  let mut chunks := #[]
  let mut changed := false
  for index in [: (captured.aliases.size+chunkCount-1)/chunkCount] do
    let aliases := captured.aliases.extract (index*chunkCount) ((index+1)*chunkCount)
    let bytes := (toJson aliases).compress.toUTF8
    let payload ← IO.ofExcept (MetadataBytes.checked bytes)
    let digest := Sha256.hex bytes
    if ← MetadataBytes.put writer (chunkKey digest) payload true then changed := true
    chunks := chunks.push digest
  let pinned ← writer.snapshot
  let header : Header := ⟨pinned.head.identity,doc.owner,doc.work,Sha256.hex raw.toUTF8,
    captured.implementation,captured.inputs,captured.complete,captured.failure,captured.aliases.size,chunks⟩
  let bytes := (toJson header).compress.toUTF8
  let payload ← IO.ofExcept (MetadataBytes.checked bytes)
  if ← MetadataBytes.put writer (ownerKey id) payload true then changed := true
  return changed

def load? (source : PageMap.Snapshot) (id : Nat) (doc : Document) : IO (Option ContentCapture.Captured) := do
  let some payload ← MetadataBytes.get? source (ownerKey id) | return none
  let header ← ObservedRecords.decode (α := Header) payload.bytes
  if header.implementation != ContentCapture.implementation then return none
  let some raw := doc.source | throw (IO.userError "content metadata lost original native output")
  unless doc.native && header.database == source.head.identity && header.owner == doc.owner &&
      header.work == doc.work && header.original == Sha256.hex raw.toUTF8 do
    throw (IO.userError "content correspondence belongs to another original")
  let mut aliases := #[]
  for digest in header.chunks do
    unless Synapses.digest digest do throw (IO.userError "invalid content block address")
    let some payload ← MetadataBytes.get? source (chunkKey digest) | throw (IO.userError "missing content block")
    unless Sha256.hex payload.bytes == digest do throw (IO.userError "changed content block")
    let rows ← ObservedRecords.decode (α := Array ContentCapture.Alias) payload.bytes
    unless rows.size ≤ chunkCount do throw (IO.userError "foreign content block extent")
    aliases := aliases ++ rows
  let characters := raw.toList.toArray
  unless aliases.size == header.aliases && (header.complete || aliases.isEmpty) &&
      aliases.all (validAlias header.inputs characters) do
    throw (IO.userError "incomplete content correspondence directory")
  return some ⟨header.implementation,header.inputs,header.complete,aliases,header.failure⟩

def catalog (database : String) (doc : Document) (captured : ContentCapture.Captured) :
    Except String ObservationContext.Catalog := do
  let some raw := doc.source | throw "missing original content body"
  let some occurrence := doc.occurrences[0]? | throw "missing original occurrence"
  let characters := raw.toList.toArray
  let mut result : ObservationContext.Catalog := {}
  let quoteSource := QuotationContext.Source.make raw
  for alias in captured.aliases do
    let some code := ContentCapture.code? characters alias | throw "content alias lost literal equality"
    let read : Read := {
      occurrence,source := ⟨.file alias.file,alias.line,alias.line⟩
      binding := ⟨database,doc.owner,doc.work,alias.first,alias.limit⟩
      quotations := #[Quotes.digest code]}
    unless read.valid do throw "content alias has an invalid original binding"
    result := {
      located := result.located.push ⟨read,#[⟨read.source,alias.first,alias.limit⟩],#[read],code⟩
      quotations := result.quotations.push
        (ObservationContext.Quotation.prepare quoteSource read alias.first alias.limit code)}
  return result

end Eggshell.ContentMetadata
