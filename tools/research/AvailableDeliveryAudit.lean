import tools.research.AvailableDelivery
import tools.research.NativeTrialAudit
import tools.research.StudyPrepare
import tools.research.StudySeedChecks
open Lean Eggshell Eggshell.Synapses Eggshell.Research

#print axioms AvailableDelivery.fragment_is_observed
#print axioms AvailableDelivery.target_has_evidence
#print axioms AvailableDelivery.one_miss_requires_fifty

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def fixtures : IO Json := do
  let file : File := ⟨"any/data.txt",String.ofList (List.replicate 64 'a'),100⟩
  let range := fun first last => (⟨file,first,last⟩ : Range)
  let required : Array RequiredDelivery.Requirement := #[⟨"partial",#[range 5 10]⟩]
  let frozen ← IO.ofExcept (AvailableDelivery.freeze required #[range 7 7])
  check (frozen.units.size == 1 && frozen.absent.isEmpty &&
      (frozen.units[0]?).any (fun unit => unit.partialNames == #["partial"]))
    "partial required evidence disappeared from denominator"
  let missing := AvailableDelivery.assess frozen #[]
  check (missing.eligible == 1 && missing.delivered == 0 && !missing.targetMet)
    "unseen partial evidence passed the gate"
  let found := AvailableDelivery.assess frozen #[range 7 7]
  check (found.delivered == 1 && found.partialNames == #["partial"] && found.targetMet)
    "observed partial delivery was called a complete semantic result"
  let absent ← IO.ofExcept (AvailableDelivery.freeze required #[])
  check (absent.units.isEmpty && absent.absent == #["partial"] &&
      !(AvailableDelivery.assess absent #[]).targetMet) "empty memory passed 98%"
  let repeated ← IO.ofExcept (AvailableDelivery.freeze #[⟨"one",#[range 7 7]⟩,⟨"alias",#[range 5 10]⟩]
    #[range 7 7,range 7 7])
  check (repeated.units.size == 1 && (repeated.units[0]?).any (fun unit =>
      unit.names.size == 2 && unit.partialNames == #["alias"])) "duplicate physical evidence inflated the denominator"
  let other : File := {file with fingerprint := String.ofList (List.replicate 64 'b')}
  let foreign ← IO.ofExcept (AvailableDelivery.freeze required #[⟨other,7,7⟩])
  check (foreign.units.isEmpty) "another content fingerprint supplied evidence"
  let overlapping := AvailableDelivery.freeze #[⟨"left",#[range 4 6]⟩,⟨"right",#[range 5 8]⟩]
    #[range 4 8]
  check (!overlapping.isOk) "overlapping units were counted twice"
  check (!(AvailableDelivery.reachesTarget 49 48) && AvailableDelivery.reachesTarget 50 49)
    "98 percent arithmetic is incorrect"
  return Json.mkObj [("partialRetained",toJson true),("partialMissingRejected",toJson true),
    ("emptyRejected",toJson true),("physicalDuplicateMerged",toJson true),("fingerprintIsolated",toJson true),
    ("overlapRequiresPartition",toJson true),("targetPercent",toJson (98 : Nat))]

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "AvailableDeliveryAudit NEW-DIRECTORY")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "keep previous audit"
  IO.FS.createDir output
  let tests ← fixtures
  IO.FS.writeFile (output / "fixtures.json") tests.pretty
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/anchored-capture"
  let sourceSpec := ((← read (study / "r0/stage1/preparation/audit-input.json")).getObjValD "source")
  let before ← NativeTrialAudit.freezeAvailable sourceSpec
  IO.FS.writeFile (output / "before-body.json") (toJson before).pretty
  -- Reanalyse the retained actual body; no new hook, DB, warm or model.
  -- Request/timing fields were checked by the prior native audit.
  let original ← read (records / "benchmark-audit.json")
  let expectedHash ← IO.ofExcept (original.getObjValAs? String "bodySha256")
  let report ← NativeTrialAudit.replayAvailable sourceSpec (records / "hook/body.txt").toString expectedHash
  check (report.getObjValD "availableEvidence" == toJson before) "body changed available source denominator"
  check (report.getObjValD "frozenEvidence" == original.getObjValD "frozenEvidence" &&
      report.getObjValD "requiredDelivery" == original.getObjValD "requiredDelivery")
    "historical metric changed"
  IO.FS.writeFile (output / "report.json") report.pretty
  IO.println (Json.mkObj [("legacy",report.getObjValD "requiredDelivery"),
    ("allDbBacked",report.getObjValD "availableDelivery"),("newHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat))]).compress
