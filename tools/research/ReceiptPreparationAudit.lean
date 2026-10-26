import tools.research.ReceiptPlanBefore
open Lean Eggshell Eggshell.Synapses

#print axioms Eggshell.KeyPostings.directory_exact
#print axioms Eggshell.KeyPostings.Index.lookup_exact

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

private def scenario (population : Nat) : IO Json := do
  let raw := String.ofList (List.replicate population 'x')
  let work := Value.text "arbitrary_tool\n{}"
  let outcome := Value.text raw
  let occurrence : Occurrence := ⟨"receipt-plan-fixture","turn","read"⟩
  let event := Value.applyList .occurrence [Ref.semantic outcome,Ref.semantic work,
    Ref.exact (.text occurrence.session),Ref.exact (.text occurrence.turn),Ref.exact (.text occurrence.useId)]
  let original := OutcomeEdge.make work outcome [event] (by simp) (by simp [maxOutcomeObservations])
  let owner : Transport.Owner := ⟨"database",original,[]⟩
  let doc ← IO.ofExcept owner.document
  let subject := Subject.original ⟨doc.work,Sha256.hex raw.toUTF8,raw.length⟩
  let mut located : Array Routed.Located := #[]
  let mut rows : Array Read := #[]
  let mut hints : Array Routing.Store.Hint := #[]
  for number in Array.range population do
    let source : Range := ⟨subject,number+1,number+1⟩
    let row : Read := ⟨occurrence,source,⟨"database",doc.owner,doc.work,number,number+1⟩,#[]⟩
    let hint : Routing.Store.Hint := ⟨.range source,0,s!"evidence-{number}",0,none⟩
    located := located.push ⟨hint,source,rfl,row,Range.contains_self source⟩
    rows := rows.push row
    hints := hints.push hint
  let duplicated := located ++ located.extract 0 (min 8 located.size)
  let plan : Transport.Plan := {
    results := #[{hints := hints ++ hints.extract 0 (min 8 hints.size)}]
    owners := #[⟨original,doc,duplicated,#[]⟩,⟨original,doc,located,#[]⟩]
    documents := #[doc],rows := rows}
  let frame := "\nWORK GRAPH " ++ doc.owner ++ "\n  GROUNDED OUTCOME\n" ++ raw ++ "\n  TRACE\n"
  let mut times := #[]
  for body in #["",frame,frame.replace "xxx" "xyx"] do
    let before ← IO.monoMsNow
    let reference := Research.ReceiptPlanBefore.bundles plan #[] body
    let referenceText := reference.compress
    check (!referenceText.isEmpty) "empty reference JSON"
    let referenceMs := (← IO.monoMsNow)-before
    let started ← IO.monoMsNow
    let indexed := Bundles.receipt plan #[] body
    check (indexed.compress == referenceText) "prepared receipt changed the original complete JSON"
    let indexedMs := (← IO.monoMsNow)-started
    times := times.push (Json.mkObj [("referenceMs",toJson referenceMs),("indexedMs",toJson indexedMs),
      ("bodyPresent",toJson (!body.isEmpty)),("exactReceiptBytes",toJson true)])
  return Json.mkObj [("sources",toJson population),("ownerRows",toJson (duplicated.size+located.size)),
    ("offers",toJson (hints.size+min 8 hints.size)),("trials",toJson times)]

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "ReceiptPreparationAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "new differential receipt directory required"
    IO.FS.createDir root
    let mut records := #[]
    for population in [32,256,1024] do
      let record ← scenario population
      records := records.push record
      IO.println record.compress
    IO.FS.writeFile (root / "results.json") (Json.mkObj [("synthetic",toJson true),
      ("scenarios",toJson records),("productionAdoption",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
    return 0
  catch error => IO.eprintln error.toString; return 1
