import tools.research.RecordIncidence
import tools.research.FrozenCanonicalBasis
import Eggshell.CanonicalSourceRecipe
import Eggshell.CanonicalSourcePrepared
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource Eggshell.Research

#print axioms RecordIncidence.close_exact
#print axioms RecordIncidence.checkWire
#print axioms Recipe.Checked.close_exact

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

structure Input where
  stored : Recipe.Stored
  checked : Recipe.Checked stored.rows
  requests : List (List (Fin stored.rows.size))

private def requests (n : Nat) : List (List (Fin n)) :=
  if positive : 0 < n then
    (List.range 64).map fun group =>
      let width := #[1,4,16,64][group%4]!
      let start := ((group/8)*37)%n
      (List.range width).map fun offset =>
        let value := (start+offset*(if group/4%2 == 0 then 1 else 7))%n
        (⟨value,Nat.mod_lt _ positive⟩ : Fin n)
  else [[]]

private def cycle (inputs : Array Input) (candidate : Bool) : IO (Nat × Nat) := do
  let sink ← IO.mkRef (0 : Nat)
  let begin ← IO.monoNanosNow
  let mut checksum := 0
  for input in inputs do
    for wanted in input.requests do
      let selected := if candidate then input.checked.close wanted else
        Records.close input.stored.rows input.checked.records wanted
      for row in selected do checksum := checksum+row.key.line+row.code.utf8ByteSize+row.origins.size
  sink.set checksum
  let elapsed := (← IO.monoNanosNow)-begin
  return (elapsed,← sink.get)

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh record incidence result required")
  let path : System.FilePath := .mk destination
  check (!(← path.pathExists)) "preserve record incidence benchmark"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let (source,originals) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let registry ← IO.ofExcept (CanonicalSource.load source.head.identity originals)
  let grouped := Delivery.byOwner registry (Shared.allOwners registry)
  let mut inputs := #[]
  let mut checks := 0
  let mut memberships := 0
  let mut wireBytes := 0
  let mut validationNs := 0
  let mut rejected := 0
  for (_,rows) in grouped do
    let stored ← IO.ofExcept (Recipe.compile rows)
    let encoded := (toJson stored).compress
    let decoded ← IO.ofExcept (Json.parse encoded >>= fromJson? (α := Recipe.Stored))
    check (stored == decoded) "published rows/layout changed during serialization"
    let begin ← IO.monoNanosNow
    let checked ← IO.ofExcept (Recipe.check decoded.rows decoded.layout)
    validationNs := validationNs+(← IO.monoNanosNow)-begin
    wireBytes := wireBytes+(toJson stored.layout.incidence).compress.utf8ByteSize
    memberships := memberships+(stored.layout.incidence.foldl (fun count bucket => count+bucket.length) 0)
    let wanted := requests decoded.rows.size
    for request in wanted do
      let actual := checked.close request
      let expected := Records.close decoded.rows checked.records request
      check (actual == expected) "record index changed original bytes, origins, order or duplicates"
      checks := checks+1
    for incidence in [#[],stored.layout.incidence.push []] do
      if incidence.size != decoded.rows.size then
        check ((Recipe.check decoded.rows {decoded.layout with incidence}).toOption.isNone) "wrong row domain accepted"
        rejected := rejected+1
    if !decoded.rows.isEmpty then
      let bad := {decoded.layout with incidence := decoded.layout.incidence.set! 0 [decoded.layout.entries.length+1]}
      check ((Recipe.check decoded.rows bad).toOption.isNone) "foreign record ordinal accepted"
      rejected := rejected+1
    inputs := inputs.push ⟨decoded,checked,wanted⟩
  let mut samples := #[]
  let mut baseline := #[]
  let mut candidate := #[]
  let mut expectedChecksum : Option Nat := none
  for repetition in [0:3] do
    for reverse in [false,true] do
      for arm in (if reverse then [true,false] else [false,true]) do
        let (elapsed,checksum) ← cycle inputs arm
        check (expectedChecksum.all (· == checksum)) "timed record closure changed payload checksum"
        expectedChecksum := some checksum
        if arm then candidate := candidate.push elapsed else baseline := baseline.push elapsed
        samples := samples.push (Json.mkObj [("repetition",toJson repetition),("reverse",toJson reverse),
          ("candidate",toJson arm),("elapsedNs",toJson elapsed),("checksum",toJson checksum)])
  let report := Json.mkObj [("source",toJson source.head),("originalRows",toJson originals.size),
    ("owners",toJson inputs.size),("queryGroupsPerCycle",toJson checks),("memberships",toJson memberships),
    ("incidenceJsonBytes",toJson wireBytes),("validationNs",toJson validationNs),
    ("baselineUpperMedianNs",toJson (baseline.qsort (· < ·))[3]!),
    ("candidateUpperMedianNs",toJson (candidate.qsort (· < ·))[3]!),
    ("samples",toJson samples),("exactOriginalClosures",toJson true),("malformedRejected",toJson rejected),
    ("actualHookMeasured",toJson false),("answeringModels",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile path report.pretty
  IO.println "Exact original record closures and stored inverse-index validation completed"
