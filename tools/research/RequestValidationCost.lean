import tools.research.ReplayReadinessChecks
import tools.research.MemoryCapacity
import tools.research.NativeTrialAudit
open Lean Eggshell Eggshell.Synapses DB
namespace Eggshell.Research.RequestValidationCost

structure Input where
  database : String
  document : Extraction.Document
  metadata : PreparedSourceView.OwnerReady

@[noinline,nospecialize] def identityCost (values : Array Input) : Nat :=
  values.foldl (fun n value =>
    match ObservationContext.OriginalOwner.prepare? value.document with
    | none => n
    | some owner => n+owner.identity.content.length+owner.identity.chars) 0

@[noinline,nospecialize] def scopeCost (values : Array Input) : Nat :=
  values.foldl (fun n value => n+if value.metadata.stored.descriptor.inScope
    value.database value.document.owner then 1 else 0) 0

@[noinline,nospecialize] def readCost (values : Array Input) : Nat :=
  values.foldl (fun n value => n+((PreparedPlanMetadata.reads value.metadata.stored.descriptor).map
    (fun rows => rows.size)).getD 0) 0

@[noinline,nospecialize] def shellCost (values : Array Input) : Nat :=
  values.foldl (fun n value => n+((PreparedPlanMetadata.describe value.document.owner
    value.metadata.stored.descriptor).map (fun shell => shell.keys.size)).getD 0) 0

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

def measured (name : String) (action : Array Input → Nat) (input : IO.Ref (Array Input)) : IO Json := do
  let sink ← IO.mkRef (0 : Nat)
  let mut rows : Array Json := #[]
  for repetition in [:3] do
    let began ← IO.monoNanosNow
    let allocated ← IO.getNumHeartbeats
    for _ in [:4] do
      sink.set (action (← input.get))
    let elapsed := ((← IO.monoNanosNow)-began)/1000
    let heartbeats := (← IO.getNumHeartbeats)-allocated
    rows := rows.push (Json.mkObj [("repetition",toJson repetition),("wholeInventoryPasses",toJson (4 : Nat)),
      ("elapsedUs",toJson elapsed),("smallAllocationHeartbeats",toJson heartbeats),("sink",toJson (← sink.get))])
  return Json.mkObj [("operation",toJson name),("trials",toJson rows)]

def run (project output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve immutable validation-cost evidence"
  IO.FS.createDirAll output
  let source ← PageMap.pin project
  let mut found : Option PageMap.Snapshot := none
  for storage in [Sidecar.Storage.database,.user] do
    let path ← CanonicalSource.Cache.directory source storage
    let some ready ← CanonicalSource.Cache.open? source storage | continue
    let some snapshot ← CanonicalSource.Cache.preparedAt? source path ready.metadata | continue
    found := some snapshot
    break
  let some snapshot := found | throw (IO.userError "existing canonical preparation required")
  let documents ← Persistence.Store.searchDocuments source
  check (documents.length == 40) "fixed original owner domain changed"
  let mut inputs : Array Input := #[]
  for document in documents do
    let original ← Persistence.Store.readLocatedOutcome source
      (← Persistence.Store.locateOutcome source document.owner)
    let owner : Transport.Owner := ⟨source.head.identity,original,[]⟩
    let doc ← IO.ofExcept owner.document
    let ready ← PreparedSourceView.readOwner snapshot source.head.identity doc.owner
    inputs := inputs.push ⟨source.head.identity,doc,ready⟩
  let input ← IO.mkRef inputs
  let mut operations := #[]
  for (name,action) in [("original-identity",identityCost),("descriptor-scope",scopeCost),
    ("descriptor-read-expansion",readCost),("descriptor-shell-expansion",shellCost)] do
    operations := operations.push (← measured name action input)
  IO.FS.writeFile (output/"result.json") (Json.mkObj [("source",toJson source.head),
    ("owners",toJson inputs.size),("operations",toJson operations),
    ("nativeOriginals",toJson (inputs.countP (·.document.native))),
    ("sourceBytes",toJson (inputs.foldl (fun n value => n+(value.document.source.map (·.utf8ByteSize)).getD 0) 0)),
    ("noQueryOrModelCalls",toJson true),("notFullHookOrActualCrossRequestRetention",toJson true),
    ("provenanceFilesNotNeededByMeasuredFunctions",toJson true),("adopted",toJson false)]).compress
end Eggshell.Research.RequestValidationCost

def main (args : List String) : IO UInt32 := do
  match args with
  | ["validation-cost",project,output] =>
    Eggshell.Research.RequestValidationCost.run (.mk project) (.mk output)
    return 0
  | other => Eggshell.Research.ReplayReadinessChecks.main other
