import Eggshell.SynapseBundles
open Lean Eggshell Eggshell.Synapses

#print axioms Bundles.Bound.spans_exact

@[noinline] private def reference (bound : Bundles.Bound source) (query : Nat) : Nat :=
  ((bound.rows.toList.map fun row => (row.binding.first,row.binding.limit)).eraseDups).foldl
    (fun total span => total+(span.1+query)%(span.2+1)) 0

@[noinline] private def prepared (bound : Bundles.Bound source) (query : Nat) : Nat :=
  bound.spans.foldl (fun total span => total+(span.1+query)%(span.2+1)) 0

private theorem exact (bound : Bundles.Bound source) (query : Nat) :
    prepared bound query = reference bound query := by
  simp only [prepared,reference,bound.spans_exact]

private def scenario (population repetitions : Nat) : IO Json := do
  let raw := String.ofList (List.replicate population 'x')
  let work := Value.text "arbitrary_tool\n{}"
  let outcome := Value.text raw
  let occurrence : Occurrence := ⟨"bound-span-fixture","turn","read"⟩
  let event := Value.applyList .occurrence [Ref.semantic outcome,Ref.semantic work,
    Ref.exact (.text occurrence.session),Ref.exact (.text occurrence.turn),Ref.exact (.text occurrence.useId)]
  let original := OutcomeEdge.make work outcome [event] (by simp) (by simp [maxOutcomeObservations])
  let doc ← IO.ofExcept (Transport.Owner.document ⟨"database",original,[]⟩)
  let owner := Persistence.selectionKey original.relation
  let subject := Subject.original ⟨doc.work,Sha256.hex raw.toUTF8,raw.length⟩
  let source : Range := ⟨subject,1,population⟩
  let rows : Array Read := (Array.range population).map fun index =>
    ⟨occurrence,⟨subject,index+1,index+1⟩,⟨"database",owner,doc.work,index,index+1⟩,#[]⟩
  let rows := rows ++ rows.extract 0 (min 8 rows.size)
  if valid : rows.all Read.valid = true then
    if inside : rows.all (fun row => source.contains row.source) = true then
      if owned : rows.all (fun row => row.binding.owner == owner) = true then
        if complete : covered source (rows.map (·.source)) = true then
          let started ← IO.monoMsNow
          let spans := hashDistinct (rows.toList.map fun row => (row.binding.first,row.binding.limit))
          let bound : Bundles.Bound source := ⟨original,owner,rfl,rows,valid,inside,owned,complete,
            spans,HashDistinct.reference _⟩
          unless bound.spans.length == population do throw (IO.userError "prepared spans were not materialized")
          let preparationMs := (← IO.monoMsNow)-started
          let started ← IO.monoMsNow
          let mut expected := #[]
          for query in Array.range repetitions do expected := expected.push (reference bound query)
          let referenceMs := (← IO.monoMsNow)-started
          let started ← IO.monoMsNow
          let mut actual := #[]
          for query in Array.range repetitions do actual := actual.push (prepared bound query)
          unless actual == expected do throw (IO.userError "prepared spans changed lookup answers")
          return Json.mkObj [("rows",toJson rows.size),("spans",toJson population),
            ("queries",toJson repetitions),("preparationMs",toJson preparationMs),
            ("referenceMs",toJson referenceMs),("candidateMs",toJson ((← IO.monoMsNow)-started)),
            ("exactAnswers",toJson true),("duplicateRows",toJson true)]
        else throw (IO.userError "incomplete bound")
      else throw (IO.userError "foreign owner")
    else throw (IO.userError "outside source")
  else throw (IO.userError "invalid original rows")

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "BoundSpanAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute directory required")
    IO.FS.createDir root
    let mut results := #[]
    for population in [64,256,1024] do
      let result ← scenario population 128
      IO.println result.compress
      results := results.push result
    IO.FS.writeFile (root / "results.json") (Json.mkObj [("synthetic",toJson true),
      ("results",toJson results),("answeringModelCalls",toJson (0 : Nat)),
      ("productionAdoption",toJson false)]).pretty
    return 0
  catch error => IO.eprintln error.toString; return 1
