import tools.research.StudyHistory
import Eggshell.SynapseIndex

open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def usageFacts (source : DB.PageMap.Snapshot) (path : System.FilePath) : IO (Array Fact) := do
  let some index ← DB.PageMap.open? path | return #[]
  unless index.head.authority == "advisory:" ++ source.head.identity ++ ":usage" do
    throw (IO.userError "usage history belongs to another private database")
  let facts ← Index.allFacts index
  Index.checkFacts source.head.identity .usage facts
  return facts

private def counts (facts : Array Fact) : Json :=
  Json.mkObj (([UsageKind.omittedThenRead,.omittedThenConsumed,.deliveredThenCited]).map fun kind =>
    (kind.label,toJson ((facts.filter fun fact => match fact with
      | .used usage => usage.kind == kind
      | _ => false).size)))

/-- Read observed private usage only. This tool neither creates a label from
the reference answers nor changes the source, postings, router or selector. -/
def main (args : List String) : IO Unit := do
  let [initialHistory,database,data,prompt,run,output] := args |
    throw (IO.userError "INITIAL-HISTORY SOURCE DATA PROMPT RUN NEW-REPORT")
  let target := System.FilePath.mk output
  unless !(← target.pathExists) do throw (IO.userError "keep prior usage evidence")
  let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk initialHistory / "history.json")) >>=
    fromJson? (α := StudyHistory.Snapshot))
  let source ← DB.PageMap.pin (.mk database)
  unless source.head.identity == original.database do throw (IO.userError "source identity changed")
  let before ← usageFacts source (.mk initialHistory / "private/usage")
  let after ← usageFacts source (.mk data / "read-cache" / source.head.identity / "synapses/usage")
  let base := before.foldl (fun found fact => found.insert fact) ({} : Std.HashSet Fact)
  let final := after.foldl (fun found fact => found.insert fact) ({} : Std.HashSet Fact)
  let missing := before.filter (!final.contains ·)
  unless missing.isEmpty do throw (IO.userError "old private usage disappeared; do not call this an additive contrast")
  let added := after.filter (!base.contains ·)
  let query := Sha256.hex (← IO.FS.readFile (.mk prompt)).toUTF8
  let thread ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk run / "thread.json")) >>=
    (·.getObjVal? "thread") >>= (·.getObjValAs? String "id"))
  let observed := added.filter fun fact => match fact with
    | .used usage => usage.query == query && (usage.event.occurrence.session == thread ||
        usage.event.consumption.any (·.consumer.session == thread))
    | _ => false
  let other := added.filter fun fact => !observed.contains fact
  let report := Json.mkObj [
    ("sourceHead",toJson source.head),("sourceFiles",toJson (← StudyRuntime.files source.directory)),
    ("queryDigest",toJson query),("session",toJson thread),
    ("baseline",counts before),("after",counts after),("added",counts added),
    ("thisAnswer",counts observed),("otherAdded",counts other),
    ("beforeFacts",toJson before),("addedFacts",toJson added),("observedFacts",toJson observed),
    ("baselinePreserved",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("syntheticLabelsInserted",toJson (0 : Nat)),("productionAdoption",toJson false)]
  IO.FS.writeFile target (report.compress ++ "\n")
  IO.println (Json.mkObj [("thisAnswer",counts observed),("added",counts added),
    ("baselinePreserved",toJson true)]).compress
