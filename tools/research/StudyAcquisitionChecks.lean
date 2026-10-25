import tools.research.StudyAcquire

open Lean Eggshell.Research.StudyAccounting

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let counters := Json.mkObj [("totalTokens",toJson (110 : Nat)),("inputTokens",toJson (100 : Nat)),
    ("outputTokens",toJson (10 : Nat)),("cachedInputTokens",toJson (80 : Nat)),
    ("reasoningOutputTokens",toJson (5 : Nat))]
  let measured ← IO.ofExcept (usage counters)
  let finished : State := {
    lastUsage := some measured
    terminal := some "completed"
    answer := some "synthetic"
    hookCount := 1 }
  check (acquisitionAccepted .seed true finished) "empty seed with an actual prompt hook rejected"
  check (!(acquisitionAccepted .seed false finished)) "seed without a prompt hook accepted"
  let injected : State := {finished with packets := #[⟨"userPromptSubmit","untrusted",1,1,"completed"⟩]}
  check (!(acquisitionAccepted .seed true injected)) "old memory injected into empty seed accepted"
  let fresh := {finished with hookCount := 0}
  check (acquisitionAccepted .fresh false fresh) "fresh with no hooks rejected"
  check (!(acquisitionAccepted .fresh false finished)) "fresh with hooks accepted"
  check (!(acquisitionAccepted .fresh false {fresh with packets := injected.packets})) "fresh with context accepted"
  check (!(acquisitionAccepted .seed true {finished with terminal := some "failed"})) "failed seed accepted"
  check (!(acquisitionAccepted .seed true {finished with lastUsage := none})) "unknown seed cost accepted"
  let scope : Scope := ⟨"thread","turn","untrusted"⟩
  check (((report scope injected).getObjValAs? Bool "protocolPassed").toOption == some true)
    "normal memory-trial body admission changed"
  let mut gateChecks := 0
  if let [directory] := args then
    let root := System.FilePath.mk directory
    let read := fun path => do IO.ofExcept (Json.parse (← IO.FS.readFile path))
    let facts ← read (root / "native/result.json")
    let guard ← read (root / "native-run.guard.json")
    let stopped ← read (root / "native/shutdown.json")
    let recovery ← read (root / "native/recovery.json")
    let publisher ← read (root / "native/publisher-shutdown.json")
    let runtime ← IO.ofExcept (facts.getObjVal? "runtime")
    let accepted := Eggshell.Research.StudyAcquire.verifyNativeGate runtime facts guard stopped recovery publisher
    check accepted.isOk "actual qualified native gate was rejected"
    gateChecks := gateChecks+1
    let object ← IO.ofExcept facts.getObj?
    let missing := Json.mkObj (object.toArray.toList.filter (fun row =>
      !#["nativeToolCalls","portableOrigins"].contains row.1))
    for changed in #[missing,
        facts.setObjVal! "nativeToolCalls" (toJson (0 : Nat)),
        facts.setObjVal! "portableOrigins" (toJson (0 : Nat)),
        facts.setObjVal! "nativeJournalEvents" (toJson (1 : Nat)),
        facts.setObjVal! "runtime" Json.null,
        facts.setObjVal! "answeringModelCalls" (toJson (1 : Nat))] do
      check (!(Eggshell.Research.StudyAcquire.verifyNativeGate runtime changed guard stopped recovery publisher).isOk)
        "incomplete or unrelated native gate reached acquisition"
      gateChecks := gateChecks+1
    for changed in #[publisher.setObjVal! "processExited" (toJson false),
        publisher.setObjVal! "endpointRemoved" (toJson false)] do
      check (!(Eggshell.Research.StudyAcquire.verifyNativeGate runtime facts guard stopped recovery changed).isOk)
        "publication ACK without actual exit reached acquisition"
      gateChecks := gateChecks+1
  else check args.isEmpty "StudyAcquisitionChecks [SOURCE-AUTHORITY-EXPERIMENT]"
  IO.println (Json.mkObj [("checks",toJson (9 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("nativeGateChecks",toJson gateChecks),("syntheticUsage",toJson (110 : Nat)),
    ("productionAdoption",toJson false)]).compress
