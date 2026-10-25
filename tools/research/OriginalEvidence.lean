import Eggshell.ObservationContext
import tools.research.RequiredDelivery

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

namespace Eggshell.Research.OriginalEvidence

structure Reference where
  name : String
  path : String
  first : Nat
  last : Nat
  deriving FromJson, ToJson

def fingerprint (bytes : ByteArray) : String := Id.run do
  let mut root := Blake3.digest "eggshell.source.file".toUTF8 [Blake3.u64le bytes.size]
  for page in [:((bytes.size+4095)/4096)] do
    root := SourceEvidence.pageRoot root (bytes.extract (page*4096) (min bytes.size ((page+1)*4096)))
  return Blake3.hex root

/-- Only exact bytes of a saved dependency may supply reference code. This is
an audit input, never input to the recommender or an authority certificate. -/
structure Image where
  private mk ::
  file : File
  text : String
  validFile : file.valid = true
  bytesExact : text.toUTF8.size = file.bytes
  hashExact : fingerprint text.toUTF8 = file.fingerprint

def image? (file : File) (bytes : ByteArray) : Option Image := do
  let text ← String.fromUTF8? bytes
  if valid : file.valid = true then
    if size : text.toUTF8.size = file.bytes then
      if hash : fingerprint text.toUTF8 = file.fingerprint then
        some ⟨file,text,valid,size,hash⟩
      else none
    else none
  else none

def load (workspace : System.FilePath) (file : File) : IO Image := do
  unless file.valid do throw (IO.userError "invalid reference dependency")
  let bytes ← FileSystem.boundedBytes (workspace / file.relative) (16*1024*1024)
  let some image := image? file bytes |
    throw (IO.userError s!"reference source fingerprint differs: {file.relative}")
  return image

def normalized (line : TextLine) : String := (numbered line.text).map (·.2) |>.getD line.text

/-- A literal match binds the real original-output interval. It makes no claim
that a shell command has certified file coordinates or that Work is reusable. -/
structure Witness (doc : Document) (image : Image) (expected : Array String) where
  read : Read
  native : doc.native = true
  dependency : doc.files.contains image.file = true
  raw : String
  original : doc.source = some raw
  observed : Array String
  literal : observed = expected
  source : read.source.subject = .original (ObservationContext.originalSubject doc.work raw)
  owner : read.binding.owner = doc.owner
  work : read.binding.work = doc.work
  valid : read.valid = true

theorem Witness.original_output (witness : Witness doc image expected) :
    ∃ original, witness.read.source.subject = .original original :=
  ⟨_,witness.source⟩

theorem Witness.exact_reference (witness : Witness doc image expected) :
    witness.observed = expected := witness.literal

def locate (database : String) (doc : Document) (image : Image)
    (expected : Array String) : Array (Witness doc image expected) := Id.run do
  if expected.isEmpty || !expected.any (fun line => !line.trimAscii.isEmpty) then return #[]
  if native : doc.native = true then
    if dependency : doc.files.contains image.file = true then
      let some prepared := ObservationContext.prepare? doc | return #[]
      let some occurrence := doc.occurrences[0]? | return #[]
      let mut found : Array (Witness doc image expected) := #[]
      let mut views := #[(prepared.lines,prepared.view.offsets)]
      if let some index := prepared.json then
        for leaf in index.leaves do
          if let some text := leaf.scalar.text then
            views := views.push (textLines text,leaf.scalar.offsets)
      for (lines,offsets) in views do
        for start in [:lines.size] do
          if start+expected.size > lines.size then break
          let observed := (lines.extract start (start+expected.size)).map normalized
          if literal : observed = expected then
            let some firstLine := lines[start]? | continue
            let some lastLine := lines[start+expected.size-1]? | continue
            let some first := offsets[firstLine.first]? | continue
            let some limit := offsets[lastLine.limit]? | continue
            if !(first < limit && limit ≤ prepared.raw.length) then continue
            if found.any (fun prior => prior.read.binding.first == first && prior.read.binding.limit == limit) then continue
            let read : Read := {
              occurrence := occurrence
              source := Range.original prepared.identity first limit
              binding := ⟨database,doc.owner,doc.work,first,limit⟩ }
            if valid : read.valid = true then
              found := found.push {
                read := read
                native := native
                dependency := dependency
                raw := prepared.raw
                original := prepared.original
                observed := observed
                literal := literal
                source := by simp only [read,Range.original]; rw [prepared.identityExact]
                owner := rfl
                work := rfl
                valid := valid }
      return found
    else return #[]
  else return #[]

structure Resolved where
  reads : Array Read
  requirements : Array RequiredDelivery.Requirement
  bindings : Array Json

/-- Resolve all alternatives before opening a handoff. Unknown command syntax
cannot remove literal DB evidence from the denominator. No source bytes are
copied into a candidate, DB, index or delivery packet by this function. -/
def resolve (workspace : System.FilePath) (database : String)
    (docs : Array Document) (rows : Array Read) (required : Array Reference) : IO Resolved := do
  let mut images : Std.HashMap File Image := {}
  let mut result : Resolved := ⟨rows,#[],#[]⟩
  for item in required do
    unless safeRelative item.path && 0 < item.first && item.first ≤ item.last do
      throw (IO.userError "invalid original reference range")
    let files := rows.foldl (fun files row => match row.source.file? with
      | some file => if file.relative == item.path then files.insert file else files
      | none => files) ({} : Std.HashSet File)
    let mut alternatives := files.toArray.map (fun file => Range.mk (.file file) item.first item.last)
    for doc in docs do
      if !doc.native then continue
      for file in doc.files do
        if file.relative != item.path then continue
        let image ← match images[file]? with
          | some image => pure image
          | none => do
            let image ← load workspace file
            images := images.insert file image
            pure image
        let lines := (image.text.splitOn "\n").toArray
        unless item.last ≤ lines.size do throw (IO.userError "reference extends beyond source file")
        let expected := lines.extract (item.first-1) item.last
        for witness in locate database doc image expected do
          result := {result with
            reads := result.reads.push witness.read
            bindings := result.bindings.push (Json.mkObj [("name",toJson item.name),
              ("file",toJson file),("read",toJson witness.read),
              ("referenceFirst",toJson item.first),("referenceLast",toJson item.last)])}
          alternatives := alternatives.push witness.read.source
    result := {result with requirements := result.requirements.push ⟨item.name,alternatives⟩}
  return result

end Eggshell.Research.OriginalEvidence
