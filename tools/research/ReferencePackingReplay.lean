import tools.research.ReferencePacking
import tools.SharedCoverageInput
import tools.research.FrozenCanonicalBasis
import tools.research.OriginalPayloadBasis
import tools.research.AvailableDelivery
import tools.VerifiedWinnerCoverage
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research

private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

private def roundtrip (references : List ReferencePacking.Reference) : IO Unit := do
  let encoded := (toJson (ReferencePacking.pack references)).compress
  let decoded : List ReferencePacking.Group ← IO.ofExcept (Json.parse encoded >>= fromJson?)
  check (ReferencePacking.expand decoded == references) "serialized provenance changed a reference or scope"

private def fixtures : IO Unit := do
  let first : ReferencePacking.Reference := ⟨⟨"db-a","session-a","turn-a"⟩,⟨"owner-a","work-a","call-a"⟩⟩
  let other : ReferencePacking.Reference := ⟨⟨"db-b","session-a","turn-a"⟩,⟨"owner-a","work-a","call-a"⟩⟩
  let changed := {first with read := {first.read with useId := "日本語\n\"\\event"}}
  for input in [[],[first],[first,first],[first,other,first],[first,changed,other]] do roundtrip input

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh reference-packing result required")
  let output : System.FilePath := .mk destination
  check (!(← output.pathExists)) "preserve previous reference-packing result"
  fixtures
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let receipt := project / "docs/candidates/prepared-bindings/resumed/cue-capture/receipts/43ba2a13af5aae5fc34557e5b8747cafce13fa0063d0da7356b09f43de8cd9ca"
  let data := (← read (receipt / "selection-plan.json")).getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (data.getObjValAs? _ "selectorInput")
  let old ← IO.ofExcept raw.decode
  let families : Nat ← IO.ofExcept (data.getObjValAs? _ "families")
  let (source,rows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let some basis := OriginalPayloadBasis.prepare families rows old |
    throw (IO.userError "selector does not bind the original cost basis")
  let mut costs := raw.costs
  let mut files : Std.HashSet File := {}
  let mut frames := #[]
  for (row,atom) in basis.sourceRows do
    if files.contains row.key.file then continue
    files := files.insert row.key.file
    check (atom.val > 0) "file frame precedes the original payload"
    let index := atom.val-1
    let originalRows := rows.filter (·.key.file == row.key.file)
    let previous := Packet.fileFrame row.key.file originalRows
    let next := ReferencePacking.fileFrame row.key.file originalRows
    let beforeText := previous.leading ++ previous.trailing
    let afterText := next.leading ++ next.trailing
    check (costs[index]? == some (beforeText.length,beforeText.utf8ByteSize)) "captured file frame cost changed"
    roundtrip (ReferencePacking.references originalRows)
    costs := costs.set! index (afterText.length,afterText.utf8ByteSize)
    frames := frames.push (Json.mkObj [("frameAtom",toJson index),("file",toJson row.key.file),
      ("beforeCost",toJson (beforeText.length,beforeText.utf8ByteSize)),
      ("afterCost",toJson (afterText.length,afterText.utf8ByteSize)),
      ("references",toJson (ReferencePacking.references originalRows).length)])
  let changed := {raw with costs}
  check (changed.weights == raw.weights && changed.offers == raw.offers &&
    changed.fixed == raw.fixed && changed.limit == raw.limit) "packing changed values, candidates, fixed metadata or budgets"
  let next ← IO.ofExcept changed.decode
  let started ← IO.monoMsNow
  let some baseline := SharedCoverage.choose? old | throw (IO.userError "baseline empty packet infeasible")
  let baselineMs := (← IO.monoMsNow)-started
  let started ← IO.monoMsNow
  let some candidate := SharedCoverage.choose? next | throw (IO.userError "candidate empty packet infeasible")
  let candidateMs := (← IO.monoMsNow)-started
  let prior : List Nat ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/selector-decisions.json")).getObjValAs? _ "selected")
  check (baseline.selected.map Fin.val == prior) "independent baseline differs from the actual selector sequence"
  let beforeNodes := Std.HashSet.ofList ((SharedCoverage.nodes old baseline.selected).map Fin.val)
  let afterNodes := Std.HashSet.ofList ((SharedCoverage.nodes next candidate.selected).map Fin.val)
  -- Human labels are opened only after both selections have finished.
  let frozenTopics ← IO.ofExcept ((← read (project / "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let some entry := frozenTopics[0]? | throw (IO.userError "frozen topic missing")
  let frozen : AvailableDelivery.Frozen ← IO.ofExcept (fromJson? (entry.getObjValD "available"))
  let shown := fun (nodes : Std.HashSet Nat) => basis.sourceRows.filterMap fun (row,atom) =>
    if nodes.contains atom.val then some (⟨row.key.file,row.key.line,row.key.line⟩ : Range) else none
  let before := AvailableDelivery.assess frozen (shown beforeNodes)
  let after := AvailableDelivery.assess frozen (shown afterNodes)
  check (before.eligible == 3 && before.delivered == 2) "baseline original coverage differs from actual body"
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only experiment changed the original source"
  IO.FS.writeFile output (Json.mkObj [("baseline",toJson before),("candidate",toJson after),
    ("baselineSolveMs",toJson baselineMs),("candidateSolveMs",toJson candidateMs),
    ("baselineCost",toJson (SharedCoverage.cost old baseline.selected)),
    ("candidateCost",toJson (SharedCoverage.cost next candidate.selected)),("frames",toJson frames),
    ("sourceUnchanged",toJson true),("frozenDenominatorUnchanged",toJson true),
    ("weightsOffersAndBudgetsUnchanged",toJson true),("serializedReferencesRoundtrip",toJson true),
    ("plannedOriginalNodesOnly",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Reference packing preview: {before.delivered}/{before.eligible} -> {after.delivered}/{after.eligible}"
