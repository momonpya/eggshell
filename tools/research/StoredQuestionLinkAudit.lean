module
import all Eggshell.SynapseBuild
import all Eggshell.SynapseJournal
public meta import Lean
open Lean Eggshell Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

public def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "new report required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve original question evidence"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let source ← DB.PageMap.pin (study / "study/seed-2/work.egg")
  let frozen ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  check (source.head == frozen.head) "source differs from the frozen snapshot"
  let privateRoot := study / "study/seed-2/data/read-cache" / System.FilePath.mk source.head.identity / "synapses"
  let journal ← DB.PageMap.pin (privateRoot / "events")
  let usage ← DB.PageMap.pin (privateRoot / "usage")
  let some metadata ← Index.manifest? usage | throw (IO.userError "original usage manifest missing")
  check (metadata.scope == .usage && metadata.source.identity == source.head.identity &&
    metadata.source.authority == source.head.authority) "original usage belongs to another DB"
  let facts ← Index.allFacts usage
  let mut recordedQueries : Std.HashSet String := {}
  for ordinal in [:← Persistence.Store.getNat journal.get "count"] do
    match (← Journal.entry journal ordinal).payload with
    | .start _ _ query _ | .answer _ query _ _ => recordedQueries := recordedQueries.insert query
    | .finish .. => pure ()
  let reader ← Persistence.Store.NodeReader.new source
  let mut questions := #[]
  let mut matched := 0
  let mut nativeOwners := 0
  for entry in ← Build.entries source do
    let origin ← reader.workOrigin (← reader.locateOutcome entry.id)
    if origin.native then nativeOwners := nativeOwners+1; continue
    let doc ← Build.document reader entry.id
    let some original := QueryLinks.original? doc | continue
    let link := original.link source.head.identity entry.id
    check link.valid "original question link is invalid"
    let usages := facts.countP fun fact => match fact with
      | .used value => value.query == link.query
      | _ => false
    check (recordedQueries.contains link.query) "saved Outcome Work differs from recorded native question"
    matched := matched+usages
    questions := questions.push (Json.mkObj [("link",toJson link),("recordedQuestionExact",toJson true),
      ("originalPrivateUsages",toJson usages)])
  check (!questions.isEmpty && matched > 0 && nativeOwners > 0) "stored question bridge audit was vacuous"
  check ((← DB.PageMap.pin source.directory).head == source.head &&
    (← DB.PageMap.pin journal.directory).head == journal.head &&
    (← DB.PageMap.pin usage.directory).head == usage.head) "read-only question audit changed original data"
  let result := Json.mkObj [("source",toJson source.head),("questions",Json.arr questions),
    ("nativeOwnersSkipped",toJson nativeOwners),("matchedOriginalUsages",toJson matched),
    ("sourceJournalAndUsageUnchanged",toJson true),("humanReferenceInputs",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("actualHookCalls",toJson (0 : Nat))]
  IO.FS.writeFile output result.pretty
  IO.println result.compress
