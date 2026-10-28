import Eggshell.SynapseTransport

open Lean Eggshell Eggshell.Synapses

private def check (test : Bool) (message : String) : IO Unit :=
  unless test do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "NEW-OUTPUT")
  check (!(← System.FilePath.pathExists output)) "preserve previous checks"
  let fingerprint := String.ofList (List.replicate 64 'a')
  let original : Original := ⟨"work",fingerprint,7⟩
  let file : File := ⟨"src/input",fingerprint,7⟩
  let occurrence : Occurrence := ⟨"s","t","c"⟩
  let edge := OutcomeEdge.make (.atom "work".toUTF8) (.atom "payload".toUTF8) [] (by simp) (by decide)
  let doc : Extraction.Document := {
    owner := "owner",work := "work",workText := none,source := some "payload"
    native := true,occurrences := #[occurrence],files := #[file]}
  let plan := fun (range : Range) (kinds : Array Nat) =>
    let row : Read := ⟨occurrence,range,⟨"db","owner","work",2,4⟩,#[]⟩
    let hints := kinds.map fun kind => ({
      target := .range range,priority := kind,evidence := fingerprint,kind,group := none} : Routing.Store.Hint)
    ({owners := #[{
      owner := edge,document := doc,located := Routed.locate hints #[row],outputs := #[]}]} : Transport.Plan)
  let fileRange : Range := ⟨file,1,1⟩
  check (((plan fileRange #[6]).ranges.flatMap (·.2)).isEmpty) "spelling inherited file rank"
  for kind in [0,1,2,3,4,5] do
    check (((plan fileRange #[kind]).ranges.flatMap (·.2)) == [(kind,2,4)]) "strong file reason lost its rank"
  let rawRange := Range.original original 2 4
  let [weak] := (plan rawRange #[6]).outputRanges.flatMap (·.2) |
    throw (IO.userError "spelling original range was lost or duplicated")
  check (weak.priority.isNone && weak.first == 2 && weak.limit == 4)
    "candidate-only original payload was dropped or changed"
  for kinds in [#[6,0],#[0,6]] do
    let [both] := (plan rawRange kinds).outputRanges.flatMap (·.2) |
      throw (IO.userError "strong original range was lost or duplicated")
    check (both.priority == some 0 && both.first == 2 && both.limit == 4)
      "a weak duplicate displaced the cited original"
  IO.FS.writeFile output (Json.mkObj [("allPassed",toJson true),
    ("fileReasonsPreserved",toJson (6 : Nat)),("spellingPayloadPreserved",toJson true),
    ("strongDuplicateWinsBothOrders",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false)]).pretty
  IO.println "Passed spelling rank, original payload, file reasons, and duplicate precedence"
