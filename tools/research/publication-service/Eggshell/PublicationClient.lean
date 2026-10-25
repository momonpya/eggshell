module

public import Eggshell.PublicationWire
public import Eggshell.Numerical

@[expose] public section

namespace Eggshell.Plugin.Publication.Client
open Lean DB

def endpoint? : IO (Option Daemon.Endpoint) := do
  readJson? ((← directory) / "endpoint.json") []

def ready (endpoint : Daemon.Endpoint) : IO Unit := do
  unless endpoint.session == "publisher" && endpoint.compatible (← generation) do
    throw (IO.userError "publisher executable identity differs from this caller")
  let _ ← Daemon.exchange endpoint "ping" (budget := 500)
  pure ()

def resolve : IO Daemon.Endpoint := do
  let root ← directory
  Persistence.withLockWithin (root / "starting") 10000 do
    if let some endpoint ← endpoint? then
      let live ← Numerical.alive endpoint.pid
      if live then
        if endpoint.compatible (← generation) then
          ready endpoint
          return endpoint
        let _ ← Daemon.exchange endpoint "shutdown" (budget := 500)
        let deadline := (← IO.monoMsNow)+10000
        while (← endpoint?).isSome do
          unless (← IO.monoMsNow) < deadline do throw (IO.userError "old publisher did not release its ownership")
          IO.sleep 5
      else removeIfExists (root / "endpoint.json")
    let child ← IO.Process.spawn {
      cmd := (← IO.appPath).toString,args := #["codex-publication-daemon"]
      stdin := .null,stdout := .null,stderr := .inherit,setsid := true }
    let deadline := (← IO.monoMsNow)+10000
    repeat
      unless (← child.tryWait).isNone do throw (IO.userError "publisher exited during startup")
      if let some endpoint ← endpoint? then
        unless endpoint.pid == child.pid.toNat do throw (IO.userError "publisher startup returned another owner")
        ready endpoint
        return endpoint
      unless (← IO.monoMsNow) < deadline do throw (IO.userError "publisher startup expired")
      IO.sleep 5
    throw (IO.userError "unreachable publisher startup")

def register (endpoint : Daemon.Endpoint) (path : System.FilePath) (identity : String) : IO Project := do
  let response ← Daemon.exchange endpoint "register" (Json.mkObj [
    ("directory",toJson path.toString),("database",toJson identity)]) (budget := 5000)
  let project ← IO.ofExcept (Json.parse response >>= fromJson? (α := Project))
  unless project.database == identity && Synapses.digest project.capability do
    throw (IO.userError "publisher granted another database")
  return project

def submit (endpoint : Daemon.Endpoint) (project : Project) (capsule : Capsule) : IO NativePublication.SourceReceipt := do
  let peer := {endpoint with secret := project.capability}
  let response ← Daemon.exchange peer "publish" (Json.mkObj [
    ("database",toJson project.database),("capsule",toJson capsule)]) (budget := maxBudgetMs)
  let receipt ← IO.ofExcept (Json.parse response >>= fromJson? (α := NativePublication.SourceReceipt))
  unless receipt.accounted && receipt.head.identity == project.database do
    throw (IO.userError "publisher returned an unrelated source ACK")
  return receipt

/-- Reconstruct only the submitted view from the authenticated durable ACK.
The service does not send the whole DB or duplicate every graph Value. -/
def restore (request : NativePublication.Prepared) (receipt : NativePublication.SourceReceipt) : IO NativePublication.Published := do
  let expected := NativePublication.receipt request.items receipt.head
  unless (toJson expected).compress == (toJson receipt).compress do
    throw (IO.userError "publisher source coverage differs from the native request")
  let authority ← IO.ofExcept (Json.parse receipt.head.authority >>=
    Persistence.valueFromJson (receipt.head.authority.length+1))
  let header := {Graph.empty authority with revision := receipt.head.revision}
  let (transaction,promotion) ← IO.ofExcept (NativePublication.compilePrepared header request.target request)
  let submitted : Graph := {
    authority,revision := receipt.head.revision,values := transaction.stagedValues,unions := []
    values_wellFormed := transaction.stagedValues_wellFormed }
  return ⟨← prepareCommitted submitted promotion,receipt⟩

def run (pending : PendingTurn) (target : System.FilePath) (checkpoint : Bool) : IO NativePublication.Published := do
  let target ← PageMap.absolute target
  let source ← match ← PageMap.open? target with
    | some source => pure source
    | none => Persistence.withLock target (Persistence.ensureSnapshot target)
  let request ← NativePublication.prepare pending target checkpoint
  let endpoint ← resolve
  let project ← register endpoint target source.head.identity
  let receipt ← submit endpoint project (Capsule.ofPrepared request)
  restore request receipt

def control (kind : String) : IO String := do
  unless #["stats","shutdown"].contains kind do throw (IO.userError "unknown publication control operation")
  let some endpoint ← endpoint? | return "null"
  Daemon.exchange endpoint kind (budget := 5000)

end Eggshell.Plugin.Publication.Client

namespace Eggshell.Plugin

def promote (pending : PendingTurn) (target : System.FilePath) : IO NativePublication.Published :=
  Publication.Client.run pending target false

def promoteObservations (pending : PendingTurn) (target : System.FilePath) : IO NativePublication.Published :=
  Publication.Client.run pending target true

end Eggshell.Plugin
