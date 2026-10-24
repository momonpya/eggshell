module
public import Eggshell.CanonicalSourceCache
public import Eggshell.CandidateDomain
public import Eggshell.WorkPostings
public import Eggshell.SourceDelta

public import Eggshell.PluginModel
public import Eggshell.SearchProvider
public import Eggshell.SynapseJournal
public import tools.FocusWindows
public import tools.RetrievalIndex

@[expose] public section

namespace Eggshell.Warm
open Lean

def planningContract := Sha256.hex ((include_str "Warm.lean").toUTF8 ++
  (include_str "SourceDelta.lean").toUTF8)

structure Checkpoint where
  source : DB.PageMap.Head
  change : Nat
  roots : Nat
  candidates : Nat
  model : String
  encoderContract : String
  focusContract : String
  projectionContract : String
  planningContract : String
  projection : Option DB.PageMap.Head
  deriving BEq, ToJson, FromJson

def model (command : List String) : IO String := do
  let _ :: "search-provider" :: args := command | throw (IO.userError "unsupported warm provider")
  let parsed ← IO.ofExcept (SearchProvider.parse {cache := .mk ".", models := .mk "."} args)
  return parsed.model

def checkpoint (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO Checkpoint := do
  let model ← model target.command
  let sidecar ← DB.Sidecar.locate snapshot target.storage
  let projection ← try VectorMatrix.open? sidecar.semantic model SearchProvider.encoderContract catch _ => pure none
  return {
    source := snapshot.head
    change := ← Persistence.Store.getNat snapshot.get "sourceChange"
    roots := ← Persistence.Store.getNat snapshot.get "roots"
    candidates := ← Persistence.Store.getNat snapshot.get "candidates"
    model := model
    encoderContract := SearchProvider.encoderContract
    focusContract := Plugin.focusWindowContract
    projectionContract := VectorMatrix.implementation
    planningContract := planningContract
    projection := projection.map (·.snapshot.head) }

def Checkpoint.sameContract (previous current : Checkpoint) : Bool :=
  previous.source.identity == current.source.identity && previous.source.authority == current.source.authority &&
    previous.model == current.model && previous.encoderContract == current.encoderContract &&
    previous.focusContract == current.focusContract && previous.projectionContract == current.projectionContract &&
    previous.planningContract == current.planningContract

/-- Root ordinals grow on insertion; the live candidate count also detects
deletion. Derived query/matcher memo writes do not change these source counters. -/
def Checkpoint.sameSources (previous current : Checkpoint) : Bool :=
  previous.sameContract current && previous.change == current.change &&
    previous.roots == current.roots && previous.candidates == current.candidates

def Checkpoint.retainsProjection (previous current : Checkpoint) : Bool :=
  match previous.projection, current.projection with
  | some before, some after =>
    before.identity == after.identity && before.authority == after.authority &&
      before.revision ≤ after.revision && before.bytes ≤ after.bytes
  | none, _ => previous.candidates == 0
  | _, _ => false

def checkpointPath (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO System.FilePath := do
  let key := Sha256.hex (toJson [← model target.command, SearchProvider.encoderContract,
    Plugin.focusWindowContract, VectorMatrix.implementation, planningContract]).compress.toUTF8
  return (← DB.Sidecar.locate snapshot target.storage).indexes / "warm" / key

def lexicalOnly (command : List String) : Bool :=
  match command with
  | _ :: "search-provider" :: args =>
    match SearchProvider.parse {cache := .mk ".", models := .mk "."} args with
    | .ok options => options.mode == "lexical"
    | .error _ => false
  | _ => false

/-- A rebuildable scheduling hint only. Actual numerical reads validate their
inputs and record private repair events; search deadlines leave it intact. -/
def required (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO Bool := do
  unless ← CandidateDomain.ready snapshot do return true
  unless ← WorkPostings.ready snapshot do return true
  unless ← RetrievalResearch.Index.ready snapshot do return true
  if lexicalOnly target.command then return false
  let _ :: "search-provider" :: _ := target.command | return false
  try
    let previous ← (Plugin.readBoundedJson (← checkpointPath target snapshot) 65536 : IO Checkpoint)
    let current ← checkpoint target snapshot
    unless previous.sameSources current && previous.retainsProjection current do return true
    if previous.source != current.source then
      let some delta ← SourceDelta.read? snapshot previous.source | return true
      unless delta.owners.isEmpty do return true
    if ← PreparationDebt.pending target.owner current.model SearchProvider.encoderContract then return true
    -- An empty publication has no numerical rows to prepare. Its completed
    -- checkpoint must not enqueue the same impossible matrix forever.
    if previous.candidates == 0 then return false
    return current.projection.isNone
  catch _ => pure true

def mark (target : Plugin.IndexTarget) (snapshot : DB.PageMap.Snapshot) : IO Unit := do
  let sidecar ← DB.Sidecar.prepare target.owner target.storage
  let _ ← DB.Sidecar.childDirectory sidecar.indexes "warm"
  let path ← checkpointPath target snapshot
  let value ← checkpoint target snapshot
  unless value.candidates == 0 || value.projection.isSome do
    throw (IO.userError "cannot mark unprepared projections")
  let previous ← try some <$> (Plugin.readBoundedJson path 65536 : IO Checkpoint) catch _ => pure none
  if previous.any (fun old => (old.source == value.source && old.sameSources value && old.retainsProjection value) ||
      (old.sameContract value && old.source.revision > value.source.revision)) then return
  FileSystem.atomicExistingBytes path (toJson value).compress.toUTF8

structure Window where
  document : Persistence.Store.SearchDocument
  index : Nat
  key : String
  start : Nat

inductive InputState where
  | missing
  | invalid
  | valid (coverage : SearchProvider.EncodingCoverage)

structure WindowCoverage where
  windows : Nat := 0
  valid : Nat := 0
  missing : Nat := 0
  invalid : Nat := 0
  input : SearchProvider.InputTotals := {}
  deriving ToJson

def WindowCoverage.observe (counts : WindowCoverage) (state : InputState) : WindowCoverage :=
  let counts := {counts with windows := counts.windows + 1}
  match state with
  | .missing => {counts with missing := counts.missing + 1}
  | .invalid => {counts with invalid := counts.invalid + 1}
  | .valid coverage => {counts with valid := counts.valid + 1, input := counts.input.add coverage}

structure Coverage where
  database : DB.Sidecar.Owner
  revision : Nat
  model : String
  windows : Nat
  valid : Nat
  missing : Nat
  invalid : Nat
  encoderContract : String
  input : SearchProvider.InputTotals
  focusContract : String
  discovery : WindowCoverage
  focus : WindowCoverage
  deriving ToJson

structure Inspection where
  coverage : Coverage
  needed : List Window

/-- Read the configured numerical cache format without starting the provider.
The DB owner overrides a command's process scratch path, as at indexed search. -/
def options (snapshot : DB.PageMap.Snapshot) (command : List String)
    (storage : DB.Sidecar.Storage := .database) : IO SearchProvider.Options := do
  let _ :: "search-provider" :: arguments := command |
    throw (IO.userError "cache inspection requires the Eggshell numerical provider")
  DB.Sidecar.observe snapshot
  let sidecar ← DB.Sidecar.locate snapshot storage
  let other ← DB.Sidecar.locate snapshot (if storage == .database then .user else .database)
  let parsed ← IO.ofExcept (SearchProvider.parse {
    cache := sidecar.semantic, models := (MiniLM.layout (← Paths.installRoot)).models } arguments)
  if parsed.mode == "lexical" then
    throw (IO.userError "lexical-only providers do not maintain numerical window caches")
  pure {parsed with
    cache := sidecar.semantic, fallback := some other.semantic
    owner := some (DB.Sidecar.Owner.ofSnapshot snapshot)}

def inspectInput (options : SearchProvider.Options) (key : String) : IO InputState := do
  let paths := SearchProvider.vectorPaths options (SearchProvider.windowCacheKey options.model key)
  if ← paths.allM (fun path => return (← FileSystem.symlinkMetadata? path).isNone) then return .missing
  try
    let cached ← SearchProvider.indexedWindow options key
    pure (.valid cached.coverage)
  catch _ => pure .invalid

def planDocuments (snapshot : DB.PageMap.Snapshot) (documents : List Persistence.Store.SearchDocument)
    (work : Persistence.Store.SearchDocument → IO Value) : IO (List Window × List Window) := do
  let mut discovery : Array Window := #[]
  let mut focus : Array Window := #[]
  for document in documents do
    let some text := Matcher.atomText? (← work document) | throw (IO.userError "warm Work is not indexed text")
    for (key, index) in document.windows.zipIdx do
      let original : Window := ⟨document, index, key, 0⟩
      discovery := discovery.push original
      let start := Plugin.evidenceWindowStart text.length index
      if start == 0 then focus := focus.push original else
        let originalText ← Persistence.Store.readSearchWindow snapshot document index
        let view := Plugin.evidenceWindowText text.length index originalText
        focus := focus.push ⟨document, index, Persistence.Store.windowKey view, start⟩
  pure (discovery.toList, focus.toList)

/-- Only prefixes intersecting Work need an original bounded read. -/
def planWindows (snapshot : DB.PageMap.Snapshot) (cached : Bool := true) : IO (List Window × List Window) := do
  let reader ← Persistence.Store.NodeReader.new snapshot
  let domain ← if cached then CandidateDomain.openShared? snapshot else pure none
  let documents ← match domain with
    | some ready => pure ready.documents
    | none => Persistence.Store.searchDocuments snapshot
  planDocuments snapshot documents fun document =>
    match domain.bind (fun ready => ready.owners[document.owner]?) with
    | some row => pure row.origin.work
    | none => reader.read document.work

structure Plan where
  scope : String
  reason : String
  publications : Nat := 0
  owners : Nat := 0
  windows : List Window × List Window

/-- Reuse requires the same source/storage/encoding contract and retained
projection incarnation. A discontinuous journal always selects full planning. -/
def plan (snapshot : DB.PageMap.Snapshot) (target : Plugin.IndexTarget)
    (verify : Bool) (repair : Bool) : IO Plan := do
  let current ← checkpoint target snapshot
  let previous ← try some <$> (Plugin.readBoundedJson (← checkpointPath target snapshot) 65536 : IO Checkpoint)
    catch _ => pure none
  if !verify && !repair then
    if let some previous := previous then
      if previous.sameContract current && previous.retainsProjection current then
        if previous.source == current.source && previous.sameSources current then
          return {scope := "publication-delta",reason := "source-unchanged",windows := ([],[])}
        if let some delta ← SourceDelta.read? snapshot previous.source then
          let some history ← DB.PageMap.HistoryReader.make? snapshot previous.source |
            throw (IO.userError "verified warm history was not retained")
          if previous.roots == (← Persistence.Store.getNat history.snapshot.get "roots") &&
              previous.candidates == (← Persistence.Store.getNat history.snapshot.get "candidates") &&
              previous.change == (← Persistence.Store.getNat history.snapshot.get "sourceChange") then
            let documents ← SourceDelta.documents snapshot delta.owners
            let reader ← Persistence.Store.NodeReader.new snapshot
            let windows ← planDocuments snapshot documents fun document => reader.read document.work
            return {
              scope := "publication-delta"
              reason := "verified-source-history"
              publications := delta.records
              owners := documents.length
              windows := windows }
  return {
    scope := "full-source"
    reason := if verify then "explicit-verification" else if repair then "observed-unavailable-input" else "no-usable-history"
    windows := ← planWindows snapshot false }

def viewCoverage (known : Std.HashMap String InputState) (windows : List Window) : IO WindowCoverage := do
  let mut seen : Std.HashSet String := {}
  let mut result : WindowCoverage := {}
  for window in windows do
    unless seen.contains window.key do
      seen := seen.insert window.key
      let some state := known[window.key]? | throw (IO.userError "warm input coverage lost a planned key")
      result := result.observe state
  pure result

/-- All original and focus-view keys are inspected once. Query vectors and
retired keys do not enter either live-view denominator. -/
def inspectWindows (snapshot : DB.PageMap.Snapshot) (options : SearchProvider.Options)
    (discovery focus : List Window) : IO Inspection := do
  let mut known : Std.HashMap String InputState := {}
  let mut needed : Array Window := #[]
  let mut union : WindowCoverage := {}
  for window in discovery ++ focus do
    unless known.contains window.key do
      let state ← inspectInput options window.key
      known := known.insert window.key state
      union := union.observe state
      match state with
      | .valid _ => pure ()
      | _ => needed := needed.push window
  pure {
    coverage := {
      database := DB.Sidecar.Owner.ofSnapshot snapshot, revision := snapshot.head.revision
      model := options.model, windows := union.windows, valid := union.valid
      missing := union.missing, invalid := union.invalid, input := union.input
      encoderContract := SearchProvider.encoderContract, focusContract := Plugin.focusWindowContract
      discovery := ← viewCoverage known discovery, focus := ← viewCoverage known focus }
    needed := needed.toList }

def inspect (snapshot : DB.PageMap.Snapshot) (options : SearchProvider.Options) : IO Inspection := do
  let (discovery,focus) ← planWindows snapshot
  inspectWindows snapshot options discovery focus


structure Result where
  before : Coverage
  after : Coverage
  requested : Nat
  batches : Nat
  elapsedMs : Nat
  lexical : RetrievalResearch.Index.Result
  domain : CandidateDomain.Result
  scope : String := "full-source"
  planReason : String := "full-source"
  changedOwners : Nat := 0
  publications : Nat := 0
  projections : Option VectorMatrix.Result := none
  deriving ToJson

/-- Background preparation uses verified publication deltas; explicit CLI work
also verifies the complete source. Neither runs inside a cold search hook.
Hydrate missing original windows in bounded batches and require exact ACKs. A
failed batch leaves completed cache writes for a subsequent invocation. -/
def runTarget (snapshot : DB.PageMap.Snapshot) (target : Plugin.IndexTarget)
    (verify : Bool := false) : IO Result := do
  let started ← IO.monoMsNow
  let _ ← Synapses.Journal.refresh snapshot target.storage ((← IO.monoMsNow)+60000)
  let _ ← Synapses.CanonicalSource.Cache.refresh snapshot target.storage
  let domain ← CandidateDomain.refresh snapshot target.storage
  let _ ← WorkPostings.refresh snapshot target.storage
  let lexical ← RetrievalResearch.Index.warm snapshot target.storage
  if lexicalOnly target.command then
    let empty : Coverage := {
      database := DB.Sidecar.Owner.ofSnapshot snapshot
      revision := snapshot.head.revision, model := "lexical-only", windows := 0
      valid := 0, missing := 0, invalid := 0
      encoderContract := SearchProvider.encoderContract, input := {}
      focusContract := Plugin.focusWindowContract, discovery := {}, focus := {}}
    return {
      before := empty
      after := empty
      requested := 0
      batches := 0
      elapsedMs := (← IO.monoMsNow)-started
      lexical := lexical
      domain := domain
      scope := "lexical-only" }
  let settings ← options snapshot target.command target.storage
  DB.Sidecar.withIndexClaim (DB.Sidecar.Owner.ofSnapshot snapshot) (fun _ => do
    let debt ← PreparationDebt.capture target.owner settings.model SearchProvider.encoderContract
    let selected ← plan snapshot target verify (!debt.isEmpty)
    let (discovery,focus) := selected.windows
    let before ← inspectWindows snapshot settings discovery focus
    let batches ← if before.needed.isEmpty then pure 0 else
      SemanticMatcher.withIndexProvider target.command fun running => do
        let mut remaining := before.needed
        let mut batches := 0
        while !remaining.isEmpty do
          let batch := remaining.take 32
          remaining := remaining.drop 32
          let items ← batch.mapM fun window => do
            let original ← Persistence.Store.readSearchWindow snapshot window.document window.index
            let text := (original.drop window.start).copy
            unless Persistence.Store.windowKey text == window.key do
              throw (IO.userError "warm input disagrees with its pinned original suffix")
            pure ({id := window.key, text} : SemanticMatcher.Item)
          let _ ← SemanticMatcher.indexWindows running items (DB.Sidecar.Owner.ofSnapshot snapshot) target.storage
          batches := batches + 1
        pure batches
    let after ← if before.needed.isEmpty then pure before else inspectWindows snapshot settings discovery focus
    unless after.needed.isEmpty do throw (IO.userError "provider acknowledged windows without valid DB cache records")
    let projections ← SearchProvider.prepareMatrix settings ((discovery ++ focus).map (·.key))
    mark target snapshot
    PreparationDebt.acknowledge target.owner settings.model SearchProvider.encoderContract debt
    return {
      before := before.coverage
      after := after.coverage
      requested := before.needed.length
      batches := batches
      elapsedMs := (← IO.monoMsNow)-started
      lexical := lexical
      domain := domain
      scope := selected.scope
      planReason := selected.reason
      changedOwners := selected.owners
      publications := selected.publications
      projections := some projections }) target.storage

def run (snapshot : DB.PageMap.Snapshot) (command : List String) (writable : Bool := true) : IO Result := do
  let target ← Plugin.registerIndexTarget snapshot command writable
  runTarget snapshot target true

end Eggshell.Warm
