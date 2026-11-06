module
public import Eggshell.PublicationService
public import Eggshell.TaskDeadline
@[expose] public section

namespace Eggshell.Research.ReadBoundaryChecks
open Lean Eggshell.Synapses Eggshell.Plugin.Publication.Service

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

/-- Independent copy of the parent acceptance policy. This is a control only,
never a product fallback. -/
def parentAccepts (server : Server) (secret : String) (requests : Array SourceViewBatch.Request) : IO Bool := do
  try
    let some first := requests[0]? | return false
    unless requests.size ≤ 4096 && secret == first.access.capability &&
        requests.foldl (fun total part => total+part.owners.size) 0 ≤ 65536 do return false
    for request in requests do
      let scope ← scopedSource server request.access.capability (Json.mkObj [
        ("database",toJson request.access.database),("scope",toJson request.access.scope)])
      unless request.owners.size ≤ 4096 && request.owners.all (fun owner => owner.utf8ByteSize ≤ 256) &&
          request.access.source.identity == scope.database && request.access.metadata.source.identity == scope.database &&
          request.access.metadata.implementation == CanonicalSource.Cache.implementation && digest request.access.metadata.payload do
        return false
      if let some focus := request.focus then
        unless focus.question.utf8ByteSize ≤ Eggshell.Plugin.Publication.Stream.maxBytes && focus.rows.size ≤ request.owners.size &&
            focus.rows.all (fun row => request.owners.contains row.owner && row.work.utf8ByteSize ≤ 256 && row.windows.all digest) &&
            focus.rows.foldl (fun n row => n+row.windows.length+row.semantic.length) 0 ≤ 65536 do return false
    return true
  catch _ => return false

def run (server : Server) (requests : Array SourceViewBatch.Request) (root : System.FilePath) : IO Unit := do
  let some first := requests[0]? | throw (IO.userError "boundary control requires actual sources")
  let secret := first.access.capability
  let captured ← authorizeBatch server secret requests
  let mut tested := 0
  let variants : Array (Array SourceViewBatch.Request) := #[requests,#[],requests.reverse,
    requests.map (fun r => {r with access := {r.access with capability := "foreign"}}),
    requests.map (fun r => {r with access := {r.access with scope := "foreign"}}),
    requests.map (fun r => {r with access := {r.access with database := "foreign"}}),
    requests.map (fun r => {r with access := {r.access with source := {r.access.source with identity := "foreign"}}}),
    requests.map (fun r => {r with access := {r.access with metadata := {r.access.metadata with
      source := {r.access.metadata.source with identity := "foreign"}}}}),
    requests.map (fun r => {r with access := {r.access with metadata := {r.access.metadata with implementation := "foreign"}}}),
    requests.map (fun r => {r with access := {r.access with metadata := {r.access.metadata with payload := "invalid"}}}),
    requests.map (fun r => {r with owners := Array.replicate 4097 "owner"}),
    requests.map (fun r => {r with owners := #[String.ofList (List.replicate 257 'x')]}),
    requests.map (fun r => {r with focus := some ⟨"question",#[⟨"foreign","work",[],[]⟩]⟩}),
    requests.map (fun r => {r with focus := some ⟨"question",#[⟨r.owners[0]?.getD "","work",["invalid"],[]⟩]⟩}),
    requests.map (fun r => {r with focus := some ⟨"question",#[⟨r.owners[0]?.getD "",
      String.ofList (List.replicate 257 'x'),[],[]⟩]⟩}),
    requests.map (fun r => {r with focus := none})]
  for variant in variants do
    for key in #[secret,"foreign"] do
      let expected ← parentAccepts server key variant
      check ((ReadBoundary.prepare captured.sources key variant).isOk == expected)
        "immutable authorization differs from the parent policy"
      tested := tested+1
  let some selected := captured.entries[0]? | throw (IO.userError "missing authorized control source")
  let duplicate := {selected.binding.source with capability := "later-duplicate"}
  let extended ← IO.ofExcept (ReadBoundary.resolve (captured.sources.push duplicate) selected.request)
  check (extended.source.capability == selected.binding.source.capability)
    "append-only registration changed a selected capability"
  let before ← server.sources.atomically get
  let began ← IO.monoMsNow
  server.sources.atomically do
    let actors ← (Array.range 80).mapM fun _ => IO.asTask (do
      let batch ← IO.ofExcept (ReadBoundary.prepare captured.sources secret requests)
      check (batch.entries.size == requests.size) "immutable boundary lost sources"
      for entry in batch.entries do
        let expected := ReadBoundary.lookup captured.sources entry.request.access.database entry.request.access.scope
        check (expected.isSome && entry.binding.source.capability == entry.request.access.capability)
          "immutable source binding crossed its capability"
        withBatchSource server entry ((← IO.monoMsNow)+10000) fun loaded _ => do
          check (loaded.metadata == entry.request.access.metadata) "immutable binding changed the prepared manifest") .dedicated
    try
      for actor in actors do TaskDeadline.wait actor ((← IO.monoMsNow)+10000)
    finally
      for actor in actors do IO.cancel actor
      for actor in actors do discard <| IO.wait actor
  let elapsed := (← IO.monoMsNow)-began
  let after ← server.sources.atomically get
  let identity := fun source : ReadSource =>
    (source.directory.toString,source.database,source.storage,source.scope,source.capability)
  check (before.map identity == after.map identity && before.size == captured.sources.size)
    "read changed the source registry"
  IO.FS.writeFile (root/"read-boundary.json") (Json.mkObj [("parentAcceptanceComparisons",toJson tested),
    ("parallelReaders",toJson (80 : Nat)),("sourceCount",toJson requests.size),
    ("registryMutexHeldThroughoutPreparedReads",toJson true),("elapsedMs",toJson elapsed),
    ("requestOrderPreserved",toJson true),("registryUnchanged",toJson true),
    ("wholeSearchLockFree",toJson false),("adopted",toJson false)]).compress

end Eggshell.Research.ReadBoundaryChecks
