import Eggshell.Handoff

open Lean Eggshell Eggshell.Plugin

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def handoff (record : SourceEvidence.Record) : Handoff := Id.run do
  let use : SourceUse := {owner := "owner",references := [0],completed := true}
  let checkpoint : SourceCheckpoint := {
    use,key := "d:owner",fragment := none
    connection := "GRAPH owner\n  COVERED WORK\n    MATCH CURRENT owner"}
  let delta := renderDeltaFrames [checkpoint.connection]
  return {
    text := "ORIGINAL HISTORICAL EVIDENCE\n\n" ++ delta,reason := "freshness-fixture"
    completed := 1,advisory := 0,localUnions := 1,blocksCurrent := true
    coveredFragments := ["owner"],deliveredGraphs := ["g:owner",checkpoint.key]
    sourceRecords := [record],sourceUses := [use],sourceCheckpoints := [checkpoint]
    controlDeltaChars := delta.length+2}

private def scenario (root : System.FilePath) : IO Unit := do
  IO.FS.createDirAll root
  let file := root / "evidence.txt"
  IO.FS.writeFile file "original evidence\n"
  let capture ← SourceEvidence.capture root
    (Json.mkObj [("command",toJson "cat evidence.txt")]) ((← IO.monoMsNow)+5000)
  check capture.record.valid "fixture could not capture a file dependency"
  let prior := handoff capture.record
  check prior.controlSuffixValid "fixture control suffix is not exact"
  let table := [capture.record,capture.record,SourceEvidence.unverified,
    {capture.record with uris := ["mcp://fixture/current-state"]}]
  let observation ← SourceEvidence.observeRecords root table ((← IO.monoMsNow)+5000)
  check (observation.files.size == 1 && observation.files.all (·.status == .checked) &&
      observation.records.map (·.status) == #[.matched,.matched,.unverified,.external])
    "shared file checks or external/unknown classifications changed"
  check ((SourceEvidence.authorize? [capture.record] observation.ledger).isSome &&
      (SourceEvidence.authorize? table observation.ledger).isNone)
    "diagnostic states acquired source authority"
  let id := String.ofList (List.replicate 64 'f')
  let expired ← prior.checkSources {workspace := root,deadline := 0,receipt := some id}
  check (expired.text.contains "ORIGINAL HISTORICAL EVIDENCE" && expired.completed == 0 &&
      !expired.blocksCurrent && expired.localUnions == 0 && expired.coveredFragments.isEmpty &&
      !expired.deliveredGraphs.contains "d:owner")
    "freshness expiry discarded historical body or retained completion authority"
  let expiredObservation ← SourceEvidence.observeRecords root [capture.record] 0
  check (expiredObservation.records.map (·.status) == #[.timedOut] &&
      expiredObservation.files.all (·.status == .timedOut) &&
      (SourceEvidence.authorize? [capture.record] expiredObservation.ledger).isNone)
    "timeout was mistaken for a definite source change or a successful check"
  let verified ← prior.checkSources {
    workspace := root,deadline := (← IO.monoMsNow)+5000,receipt := some id}
  check (verified.completed == 1 && verified.blocksCurrent && verified.text.contains "ORIGINAL HISTORICAL EVIDENCE")
    "bounded verification lost a matched source or original evidence"
  IO.FS.writeFile file "changed evidence\n"
  let changed ← SourceEvidence.observeRecords root [capture.record] ((← IO.monoMsNow)+5000)
  check (changed.records.map (·.status) == #[.changed] && changed.files.all (·.status == .checked))
    "a changed file was conflated with timeout or I/O uncertainty"
  let checked ← prior.checkSources {workspace := root,deadline := (← IO.monoMsNow)+5000,receipt := some id}
  check (checked.completed == 0 && !checked.blocksCurrent && checked.text.contains "ORIGINAL HISTORICAL EVIDENCE")
    "changed source retained authority or lost history"
  let receipts := (← Paths.dataRoot) / "receipts" / id
  let mut count := 0
  for entry in ← receipts.readDir do
    if !entry.fileName.startsWith "freshness-" then continue
    let record ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
    let data := record.getObjValD "data"
    let hook ← IO.ofExcept (data.getObjValAs? Nat "hookDeadlineMs")
    let verification ← IO.ofExcept (data.getObjValAs? Nat "verificationDeadlineMs")
    check (verification ≤ hook && data.getObjValD "observation" != Json.null &&
        data.getObjValD "sourceUses" != Json.null && data.getObjValD "completedAfter" != Json.null)
      "freshness receipt extended the parent deadline or lost its source states"
    count := count+1
  check (count == 3) "successive freshness checks overwrote the same receipt stage"
  IO.FS.writeFile (root / "observation.json") (Json.mkObj [
    ("matched",observation.receipt),("expired",expiredObservation.receipt),("changed",changed.receipt),
    ("historicalBody",toJson expired.text),("receiptStages",toJson count)]).pretty
  IO.println "freshness deadline passed: remaining-time reserve, original historical body after expiry/change, per-record states, shared probes, no authority from unknown/external, distinct receipt stages"

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "FreshnessDeadlineTests NEW-DIRECTORY")
  let root := System.FilePath.mk path
  check (root.isAbsolute && !(← root.pathExists)) "new absolute fixture required"
  for now in [0,1,2,100,29000,30000,1000000000] do
    for deadline in [0,1,2,3,100,29000,30000,1000000000] do
      let stop := Deadline.verification now deadline
      check (stop ≤ deadline && (now > deadline ||
        ((deadline-now)/2 ≤ deadline-stop && min Deadline.minimumDeliveryMs (deadline-now) ≤ deadline-stop)))
        "deadline arithmetic did not preserve the existing budget and delivery reserve"
  scenario root
