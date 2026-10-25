import Eggshell.KeyedSearchProvider
import Eggshell.PluginModel
import Lean

open Lean Eggshell Eggshell.DB Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

run_meta do
  for name in #[``LexicalAdvice.rank_prepared_exact,``LexicalReads.OwnerWitness.original_checks] do
    for axiomName in ← Lean.collectAxioms name do
      unless #[``propext,``Classical.choice,``Quot.sound].contains axiomName do
        throwError "Unapproved lexical advice axiom: {name}: {axiomName}"
  logInfo "Original Float term order, primary/auxiliary scores and original witness contracts checked"

/-- Retained pre-change provider implementation, with its original scalar
validation and original source ordinal. Used only as an independent oracle. -/
private def reference (source : Snapshot) (text : String) : IO (List Nat × List Nat) := do
  let query ← LexicalReads.coarseQuery source
  let mut postings : Std.HashMap String (Std.HashSet Nat) := {}
  let mut frequency : Std.HashMap String Nat := {}
  let mut owners : Std.HashSet Nat := {}
  for term in SearchRank.terms text do
    let (found,count) ← query.posting term
    postings := postings.insert term (Std.HashSet.ofList found)
    frequency := frequency.insert term count
    for owner in found do owners := owners.insert owner
  let ordered ← owners.toList.mapM fun owner => do pure (← query.ordinal owner,owner)
  let rows := ((ordered.mergeSort (fun a b => a.1 ≤ b.1)).map Prod.snd).toArray
  let population ← getNat source.get "candidates"
  let contains := fun owner term => (postings.getD term {}).contains owner
  let ranked := SearchRank.rankRows text rows.toList contains (frequency.getD · 0) false population
  let anchors := SearchRank.rankRows text rows.toList contains (frequency.getD · 0) true population
  query.report
  return (ranked.filterMap (rows[·]?),anchors.filterMap (rows[·]?))

private def publish (source : Snapshot) (values : List Value) : IO Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let roots ← values.mapM intern.root
    writeChange writer ⟨roots,[],false⟩
  PageMap.pin source.directory

private def value (index : Nat) : IO Value :=
  IO.ofExcept (Plugin.relation? .outcome [
    .semantic (.text s!"timer scheduling inquiry {index}"),
    .semantic (.text s!"original timer observation {index}: カーネル 時刻 커널 시간 планировщик café Driver.cpp:7101")])

private def operations (source : Snapshot) : IO PageMap.ReadTrace := do
  let some trace ← source.trace.get | throw (IO.userError "missing original trace")
  check trace.complete "original trace exceeded normal allowance"
  return trace

private def fixture (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve fixture"
  FileSystem.privateDirectory output
  let first ← PageMap.create (output / "source.egg") "advice-fixture"
  let source ← publish first (← (List.range 70).mapM value)
  let _ ← RetrievalResearch.Index.warm source .user
  let questions := ["timer", "timer scheduling", "カーネル 時刻", "커널 시간", "планировщик", "café", "Driver.cpp:7101", "absent-advice-query", ""]
  for question in questions do
    let expected ← reference (← PageMap.pin source.directory) question
    let actual ← LexicalAdvice.query (← PageMap.pin source.directory) question
    check ((actual.ranked,actual.anchors) == expected) s!"complete ranking changed: {question}"
  source.trace.set (some {})
  let advice ← LexicalAdvice.query source "timer scheduling"
  let before ← operations source
  check (before.operations.all fun | .point name _ => name == "roots" || name == "candidates" | _ => false)
    "advice restored original owners or scanned the source"
  let wanted := advice.ranked.take 2
  let documents ← LexicalAdvice.originals advice wanted
  let after ← operations source
  check (documents.length == 2 && after.operations.length > before.operations.length)
    "selected owners bypassed their original checks"
  let some owner := wanted.head? | throw (IO.userError "no fixture owner")
  let some ordinal := advice.ordinals[owner]? | throw (IO.userError "no fixture ordinal")
  let forged := {advice with ordinals := advice.ordinals.insert owner (ordinal+1)}
  check (← rejected (LexicalAdvice.originals forged [owner])) "forged ordinal reached original admission"
  check (← rejected (LexicalAdvice.originals advice [owner,owner])) "duplicate consumed owner accepted"
  check (← rejected (LexicalAdvice.originals advice [1000000])) "unnominated consumed owner accepted"
  -- Change only the derived index. The old pinned result still retains its
  -- own original bytes; a new result must reject this selected bad hint.
  let _ ← PageMap.withWriter advice.reader.index fun writer =>
    putNat writer (key "owner" owner) (ordinal+1)
  let changed ← LexicalAdvice.query source "timer scheduling"
  check (← rejected (LexicalAdvice.originals changed [owner])) "corrupt indexed owner bypassed the original witness"
  let retained ← LexicalAdvice.originals advice [owner]
  check (retained.length == 1) "a later index publication moved the pinned original result"
  let appended ← publish source [← value 80]
  check (← rejected (LexicalAdvice.query appended "timer")) "changed nonempty source became a completed empty advice query"
  let cold ← publish (← PageMap.create (output / "cold.egg") "cold-advice") [← value 90]
  check (← rejected (LexicalAdvice.query cold "timer")) "missing index became a completed empty query"
  let result := Json.mkObj [("questions",toJson questions.length),("completeRankingsEqual",toJson true),
    ("sourceAdviceOperations",toJson before.operations.length),
    ("sourceConsumedOperations",toJson after.operations.length),
    ("originalChecksDeferredNotRemoved",toJson true),("forgedAndCorruptConsumedOwnersRejected",toJson true),
    ("pinnedIndexRetained",toJson true),("coldAndChangedAreUnavailable",toJson true)]
  IO.FS.writeFile (output / "result.json") result.pretty
  IO.println result.compress

private def measured (action : IO (List Nat × List Nat)) : IO ((List Nat × List Nat) × Nat) := do
  let started ← IO.monoMsNow
  let result ← action
  let force ← IO.mkRef (result.1.length+result.2.length)
  let _ ← force.get
  return (result,(← IO.monoMsNow)-started)

private def benchmark (database output plan : System.FilePath) (repetition : Nat) : IO Unit := do
  check (!(← output.pathExists)) "preserve benchmark"
  FileSystem.privateDirectory output
  let json ← IO.ofExcept (Json.parse (← IO.FS.readFile plan))
  let questions ← IO.ofExcept (json.getObjValAs? (List String) "queries")
  let pinned ← PageMap.pin database
  let mut results := #[]
  for (question,index) in questions.zipIdx do
    let baseline := do reference (← PageMap.pin database) question
    let candidate := do
      let result ← LexicalAdvice.query (← PageMap.pin database) question
      pure (result.ranked,result.anchors)
    let ((expected,referenceMs),(actual,candidateMs)) ← if repetition%2 == 0 then do
      let expected ← measured baseline
      let actual ← measured candidate
      pure (expected,actual)
    else do
      let actual ← measured candidate
      let expected ← measured baseline
      pure (expected,actual)
    check (expected == actual) s!"full ranked and anchor owner sequences changed: {question}"
    let bytes := (toJson expected).compress
    IO.FS.writeFile (output / s!"rank-{index}.json") bytes
    let record := Json.mkObj [("question",toJson question),("referenceMs",toJson referenceMs),
      ("candidateMs",toJson candidateMs),("ranked",toJson expected.1.length),
      ("anchors",toJson expected.2.length),("rankSha256",toJson (Sha256.hex bytes.toUTF8)),
      ("completeSequencesEqual",toJson true)]
    results := results.push record
    IO.FS.writeFile (output / "results.json") (toJson results).pretty
    IO.eprintln s!"rep {repetition}, q{index}: {referenceMs}/{candidateMs} ms, owners={expected.1.length}"
  check ((← PageMap.pin database).head == pinned.head) "benchmark changed the source head"
  IO.FS.writeFile (output / "summary.json") (Json.mkObj [("repetition",toJson repetition),
    ("order",toJson (if repetition%2==0 then "reference,candidate" else "candidate,reference")),
    ("source",toJson pinned.head),("cases",toJson results),
    ("scope",toJson "complete lexical nominations only, without answering model, embeddings or native delivery")]).pretty

def main (args : List String) : IO Unit := do
  match args with
  | ["fixture",output] => fixture (.mk output)
  | ["benchmark",source,output,plan,repetition] =>
    let some repetition := repetition.toNat? | throw (IO.userError "invalid repetition")
    benchmark (.mk source) (.mk output) (.mk plan) repetition
  | _ => throw (IO.userError "LexicalAdviceAudit fixture OUT | benchmark SOURCE OUT PLAN REPETITION")
