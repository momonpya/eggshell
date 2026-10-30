import tools.research.PrincipalOffers
import tools.SharedCoverageInput
import Lean.Data.Json.Parser
open Lean Eggshell.Research

private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

private def fixtures : IO Unit := do
  let raw : SharedCoverage.Input.RawProblem := {
    costs := #[(5,5),(7,7),(9,9),(0,0)]
    weights := #[11,13,17]
    offers := #[{closure := [0,3],covers := [0]},
      {closure := [0,1],covers := [0]},
      {closure := [1],covers := [1]},
      {closure := [2],covers := [1]}]
    fixed := (0,0),limit := (20,20)}
  let p ← IO.ofExcept raw.decode
  let domain := PrincipalOffers.prepare p
  if enough : 2 < p.weights.size then
    let some principal := PrincipalOffers.find? domain ⟨0,by omega⟩ |
      throw (IO.userError "a real least witness was lost")
    check (principal.offer.val == 0) "zero-cost metadata changed the least paid witness"
    check ((PrincipalOffers.find? domain ⟨1,by omega⟩).isNone) "incomparable OR alternatives collapsed into AND"
    check ((PrincipalOffers.find? domain ⟨2,enough⟩).isNone) "an uncovered cue got an invented witness"
  else throw (IO.userError "fixture cue directory changed")

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh principal-offer audit required")
  let output : System.FilePath := .mk destination
  check (!(← output.pathExists)) "preserve the previous structural audit"
  fixtures
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let input := project / "docs/candidates/prepared-bindings/resumed/cue-capture/receipts/43ba2a13af5aae5fc34557e5b8747cafce13fa0063d0da7356b09f43de8cd9ca/selection-plan.json"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (((← read input).getObjValD "data").getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let started ← IO.monoMsNow
  let domain := PrincipalOffers.prepare p
  let mut principal := 0
  let mut ambiguous := 0
  let mut unavailable := 0
  let totalMass := p.weights.foldl (·+·) 0
  let mut principalMass := 0
  let mut ambiguousMass := 0
  let mut certificates := #[]
  let mut examples := #[]
  let mut complete := true
  let mut processed := 0
  for cue in List.finRange p.weights.size do
    if p.weights[cue] == 0 then continue
    if (← IO.monoMsNow)-started ≥ 15000 then complete := false; break
    processed := processed+1
    let choices := domain.alternatives cue
    if choices.isEmpty then unavailable := unavailable+1; continue
    match PrincipalOffers.find? domain cue with
    | some witness =>
        principal := principal+1
        principalMass := principalMass+p.weights[cue]
        certificates := certificates.push (cue.val,witness.offer.val)
    | none =>
        ambiguous := ambiguous+1
        ambiguousMass := ambiguousMass+p.weights[cue]
        if examples.size < 3 then
          examples := examples.push (Json.mkObj [("cue",toJson cue.val),
            ("alternatives",toJson (choices.map fun index => (index.val,(domain.paidAt index).map Fin.val)))])
  IO.FS.writeFile output (Json.mkObj [("complete",toJson complete),("processedPositiveCues",toJson processed),
    ("diagnosticBudgetMs",toJson (15000 : Nat)),("principalCues",toJson principal),("incomparableCues",toJson ambiguous),
    ("unavailablePositiveCues",toJson unavailable),("principalMass",toJson principalMass),
    ("otherReachableMass",toJson ambiguousMass),("totalMass",toJson totalMass),
    ("principalMassPartsPerMillion",toJson (principalMass*1000000/(max 1 totalMass))),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("offers",toJson p.offers.size),
    ("incidences",toJson domain.values.size),("certificates",toJson certificates),
    ("incomparableExamples",toJson examples),("originalWeightsCostsCandidatesUnchanged",toJson true),
    ("humanLabelsRead",toJson false),("newSolverImplemented",toJson false),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Principal witnesses: {principal}; alternative witnesses: {ambiguous}; mass ppm {principalMass*1000000/(max 1 totalMass)}"
