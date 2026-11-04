import Main

open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.SourcePreparationChecks

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- A causal intervention on the failed immutable source cuts. Private future
events and their replay debt must survive, while both source frames become ready. -/
def audit (root : System.FilePath) : IO Unit := do
  let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "source-only check lost its fixed cut")
  let before ← context.reads.sources.mapM fun source => DB.PageMap.pin source.directory
  let targets ← registeredIndexTargets
  let mut rows := #[]
  for source in context.reads.sources do
    if (← Persistence.Store.getNat source.get "candidates") == 0 then continue
    let some (_,registered) := targets.find? (fun (_,target) => target.owner.database == source.head.identity) |
      throw (IO.userError "source-only check lost a static target")
    let journalBefore ← Synapses.Journal.open? source
    check (journalBefore.isSome && (← Synapses.Journal.required source registered.storage))
      "fixture no longer has private replay debt"
    check ((← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract).isNone)
      "fixture source frame was already ready before the intervention"
    let result ← Warm.runTarget source {registered with sourceHead := some source.head}
    check (result.complete && result.prepared.isSome && result.journal.isNone)
      "source-only preparation did not complete independently of private replay"
    check (result.after.missing == 0 && result.after.invalid == 0)
      "source-only preparation omitted numerical rows"
    let journalAfter ← Synapses.Journal.open? source
    check (journalAfter.map (·.head) == journalBefore.map (·.head) &&
      (← Synapses.Journal.required source registered.storage))
      "source-only preparation changed or acknowledged unrelated private replay"
    check ((← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract).isSome)
      "source-only preparation did not publish its exact source frame"
    rows := rows.push (Json.mkObj [("source",toJson source.head),("elapsedMs",toJson result.elapsedMs),
      ("journalHeadUnchanged",toJson true),("privateReplayStillRequired",toJson true),
      ("preparedReferencePresent",toJson true),("requestedPrivateReplay",toJson false),
      ("coverage",toJson result.after)])
  check (rows.size == 2) "source-only regression did not cover both missing source frames"
  for original in before do
    check ((← DB.PageMap.pin original.directory).head == original.head)
      "source-only preparation modified acknowledged originals"
  let result := Json.mkObj [("sources",toJson rows),("originalHeadsUnchanged",toJson true),
    ("privateJournalUntouched",toJson true),("sourceFramesPublished",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"source-only-intervention.json") (result.pretty++"\n")
  IO.println "both historical source frames completed; future private replay and all original heads unchanged"

end Eggshell.Research.SourcePreparationChecks
