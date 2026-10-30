module
public import Eggshell.SynapseIndex
public import Eggshell.HashDistinct
@[expose] public section

namespace Eggshell.Research.SourceBindingReference
open Lean DB _root_.Eggshell.Synapses

/-- Source bindings already exist in source postings. Quotation selector keys
do not distinguish original observations or duplicate their payload. -/
abbrev candidate? := Index.bindingCandidate?

structure Origin (database : String) (allowed : Std.HashSet String) (source : Range) where
  read : Read
  valid : read.valid = true
  sourceExact : read.source = source
  databaseExact : read.binding.database = database
  admitted : allowed.contains read.binding.owner = true

def checkRead? (database : String) (allowed : Std.HashSet String) (source : Range) (read : Read) :
    Option (Origin database allowed source) := do
  if valid : read.valid = true then
    if same : read.source = source then
      if sameDatabase : read.binding.database = database then
        if admitted : allowed.contains read.binding.owner = true then
          some ⟨read,valid,same,sameDatabase,admitted⟩ else none
      else none
    else none
  else none

def check? (database : String) (allowed : Std.HashSet String) (source : Range) (fact : Fact) :
    Option (Origin database allowed source) := do
  if !fact.valid then none else do
    let read ← candidate? fact
    checkRead? database allowed source read

theorem Origin.only_admitted_owner (origin : Origin database allowed source) :
    allowed.contains origin.read.binding.owner = true := origin.admitted

theorem Origin.same_source (origin : Origin database allowed source) :
    origin.read.source = source := origin.sourceExact

theorem Origin.same_database (origin : Origin database allowed source) :
    origin.read.binding.database = database := origin.databaseExact

structure Lookup (database : String) (allowed : Std.HashSet String) (source : Range) where
  origins : Array (Origin database allowed source)
  complete : Bool
  index : PageMap.Head
  inspected : Nat
  bytes : Nat
  unusable : Nat

structure Scan where
  rows : Array Index.StoredBinding := #[]
  inspected : Nat := 0
  bytes : Nat := 0
  complete : Bool := true

def scanAt (snapshot : PageMap.Snapshot) (ref : PageMap.Ref) (source : Range) (keyRange : PageMap.KeyRange)
    (deadline byteLimit : Nat) (initial : Scan) : IO Scan := do
  if !initial.complete then return initial
  if (← IO.monoMsNow) ≥ deadline then return {initial with complete := false}
  let loaded ← snapshot.load ref
  let mut result := initial
  match loaded.page with
  | .leaf rows =>
    for row in keyRange.select rows do
      let some bytes := row.2 | continue
      if result.inspected ≥ 32768 || result.bytes+bytes.size > byteLimit || (← IO.monoMsNow) ≥ deadline then
        return {result with complete := false}
      let binding ← Index.decode (α := Index.StoredBinding) bytes
      unless row.1 == keyRange.lower ++ binding.fact && binding.read.source == source && binding.read.valid do
        throw (IO.userError "prepared binding differs from its pinned source posting")
      result := {result with
        rows := result.rows.push binding
        inspected := result.inspected+1
        bytes := result.bytes+bytes.size}
    return result
  | .branch children =>
    for child in children do
      if keyRange.overlaps child then
        if _smaller : child.height < ref.height then
          result ← scanAt snapshot child source keyRange deadline byteLimit result
        else throw (IO.userError "prepared binding directory height did not decrease")
        if !result.complete then return result
    return result
termination_by ref.height

/-- One exact source-posting lookup, no Work/body restoration or source
parser. This returns advisory metadata, never a Match or completion proof. -/
def lookup (reader : Index.Reader) (source : Range) (allowed : Std.HashSet String)
    (deadline : Nat) (byteLimit : Nat := 8*1024*1024) :
    IO (Lookup reader.manifest.source.identity allowed source) := do
  let base := "binding:" ++ Index.contentKey source
  let range : PageMap.KeyRange := ⟨base ++ ":",base ++ ";"⟩
  let found ← match reader.index.head.root with
    | none => pure ({} : Scan)
    | some root => scanAt reader.index root source range deadline byteLimit {}
  let mut origins := #[]
  let mut seen : Std.HashSet Read := {}
  let mut unusable := 0
  for stored in found.rows do
    if !stored.read.valid then unusable := unusable+1
    let some origin := checkRead? reader.manifest.source.identity allowed source stored.read | continue
    if seen.contains origin.read then continue
    seen := seen.insert origin.read
    origins := origins.push origin
  return ⟨origins,found.complete && unusable == 0,reader.index.head,found.inspected,found.bytes,unusable⟩

structure Resolved where
  rows : Std.HashMap Range (Array Read) := {}
  complete : Bool := true
  requests : Nat := 0
  inspected : Nat := 0
  bytes : Nat := 0
  unresolved : Nat := 0
  unusable : Nat := 0

structure Projection where
  identity : Json
  index : PageMap.Head
  rows : Array (Range × Array Read)
  complete : Bool
  requests : Nat
  bytes : Nat
  unresolved : Nat
  unusable : Nat
  deriving ToJson,FromJson

def resolve (reader : Index.Reader) (wanted : Array Range) (allowed : Std.HashSet String)
    (deadline : Nat) : IO Resolved := do
  let mut result : Resolved := {}
  for source in (hashDistinct wanted.toList).toArray do
    if (← IO.monoMsNow) ≥ deadline || result.bytes ≥ 32*1024*1024 then
      return {result with complete := false}
    let found ← lookup reader source allowed deadline (32*1024*1024-result.bytes)
    let rows := found.origins.map (·.read)
    result := {
      rows := result.rows.insert source rows
      complete := result.complete && found.complete
      requests := result.requests+1
      inspected := result.inspected+found.inspected
      bytes := result.bytes+found.bytes
      unusable := result.unusable+found.unusable
      unresolved := result.unresolved + if rows.isEmpty then 1 else 0}
  return result

end Eggshell.Research.SourceBindingReference
