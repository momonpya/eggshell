import Eggshell.PreparationRegistry
import Eggshell.PluginProjectContext
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.DB
structure Count where
  source : String
  directory : System.FilePath
  head : PageMap.Head
  rows : Nat
  native : Nat

def sources (root : System.FilePath) : IO (Array PageMap.Snapshot × Array (String × String)) := do
  let text ← IO.FS.readFile (root/"captured-turn.json")
  let pending ← IO.ofExcept (Json.parse text >>= fromJson? (α := PendingTurn))
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "no captured scope")
  let snapshots ← context.reads.sources.mapM fun source => PageMap.pin source.directory
  let allowed := snapshots.filterMap fun source =>
    let owner := Sidecar.Owner.ofSnapshot source
    if context.canPrepare owner then some (owner.database,owner.directory) else none
  return (snapshots,allowed)

def countSource (source : PageMap.Snapshot) : IO (Option Count) := do
  let some journal ← Journal.open? source | return none
  let count ← Persistence.Store.getNat journal.get "count"
  let mut native := 0
  for ordinal in [:count] do
    if (← journal.get (Journal.referenceKey ordinal)).isNone then native := native+1
  return some ⟨source.head.identity,journal.directory,journal.head,count,native⟩

def feed (counts : Array Count) (allowed : Array (String × String)) (target : Journal.Target) : IO (Option Json) := do
  let some ingress := target.ingress | return none
  let some found := counts.find? (·.source == ingress.database) | throw (IO.userError "foreign ingress")
  let source ← target.owner.pin
  let journal ← Journal.open? source
  let raw ← journal.bindM (fun journal => journal.get (Journal.importKey ingress))
  let cursor : Option Journal.ImportCursor ← raw.mapM (Index.decode (α := Journal.ImportCursor))
  let eligible := target.storage != .database || allowed.contains (target.owner.database,target.owner.directory)
  return some (Json.mkObj [("source",toJson target.owner.database),("ingress",toJson ingress.database),
    ("allRows",toJson found.rows),("nativeRows",toJson found.native),("indirectRows",toJson (found.rows-found.native)),
    ("cursor",toJson (cursor.map (·.next))),("eligible",toJson eligible),
    ("currentlyRequired",toJson (← Journal.feedRequired source ingress)),
    ("legacySlices32",toJson ((found.rows+31)/32)),
    ("nativeSlices32",toJson ((found.native+31)/32))])

def audit (root : System.FilePath) : IO Unit := do
  let (snapshots,allowed) ← sources root
  let counts := (← snapshots.mapM countSource).filterMap id
  let targets ← Journal.targets (some (snapshots.map (·.head.identity)))
  let values := (← targets.mapM fun (_,target) => feed counts allowed target).filterMap id
  for found in counts do
    unless (← PageMap.pin found.directory).head == found.head do throw (IO.userError "census changed journal head")
  let result := Json.mkObj [("feeds",toJson values),("journalHeadsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (root/"feed-census.json") (result.pretty++"\n")
  IO.println (Json.mkObj [("feeds",toJson values.size),("readOnly",toJson true)]).compress

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "controlled fixture required")
  audit (.mk directory)
