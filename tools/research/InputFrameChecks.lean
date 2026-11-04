import Main
open Lean Eggshell Eggshell.Plugin Eggshell.DB
namespace Eggshell.Research.InputFrameChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def size (value : Json) : Nat := value.compress.utf8ByteSize
def fields (value : Json) : Except String Json := do
  let object ← value.getObj?
  return toJson (object.toArray.map fun (name,value) => (name,size value))
def operation (query : Worker.Search) (id : String) : OperationWire.Request := {
  id,session := query.pending.sessionId,role := .search,payload := toJson query,
  cutoff := query.deadline,identity := some query.identity,finishReady := false }
def accepted (bytes : Nat) : Nat := Id.run do
  let mut plan := OperationPlan.initial
  let mut count := 0
  for n in [:80] do
    let (next,admitted) := OperationPlan.admit plan ⟨s!"frame-{n}",.search,bytes,30000⟩
    plan := next
    if admitted then count := count+1
  return count
def rejected (request : Worker.Search) : IO Bool := do
  try
    let _ ← Worker.capturePrepared request
    return false
  catch _ => return true
def run (source root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier input-frame audit"
  IO.FS.createDirAll root
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
  check (identity.exitCode == 0) "audit runtime identity missing"
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let projectPath := (source/"work.project").toString
  let command ← MiniLM.command (← Paths.installRoot)
  check command.isSome "installed MiniLM command unavailable"
  let initial : PendingTurn := {
    sessionId := "input-frame-audit",turnId := "turn",cwd := source.toString,
    prompt := "Return the recorded head and tail facts for support case-79.",
    profile := "work",semanticMatcher := command,read := [projectPath],write := some projectPath,
    handoffChars := 120000,projection := .automatic }
  let expected := (← read (source/"frozen-readback.json")).getObjValD "sourceHeads"
  let heads : IO (Array Json) := (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  check (toJson (← heads) == expected) "original source changed"
  let started ← IO.monoMsNow
  let pending ← ProjectContext.capture initial (started+30000)
  let frozen := (toJson pending).compress
  let request : Worker.Search := {
    pending,state := {profile := "work"},work := pending.prompt,enforce := false,
    deadline := started+OperationWire.searchBudgetMs,startedAt := started }
  let captured ← Worker.capturePrepared request
  check (captured.prepared.isSome && captured.originals.isSome && captured.owners.isSome &&
    captured.pending.preparedInputs.isSome) "normal capture did not retain both representations"
  let preview ← IO.ofExcept captured.compactPrepared
  check (preview.preparedInputProducer.isSome && preview.pending.preparedInputs.isNone) "actual compactor kept duplicate payload"
  let decoded ← IO.ofExcept (fromJson? (toJson preview) : Except String Worker.Search)
  let restored ← IO.ofExcept decoded.restorePrepared
  check ((toJson restored).compress == (toJson captured).compress) "wire round-trip changed serialized request or durable pending envelope"
  let full := operation captured (← Receipt.fresh)
  let compact := operation preview (← Receipt.fresh)
  OperationPool.validate full
  OperationPool.validate compact
  let some encoded := captured.pending.preparedInputs | throw (IO.userError "missing duplicate frame")
  let frame ← IO.ofExcept (fromJson? (α := PreparedInputs.Frame) encoded.payload)
  let wrongFrame := {frame with originals := frame.originals.reverse}
  let wrongDuplicate : Worker.Search := {captured with pending := {captured.pending with preparedInputs := some ⟨toJson wrongFrame⟩}}
  let some inputs := captured.prepared | throw (IO.userError "missing explicit inputs")
  let some first := inputs[0]? | throw (IO.userError "missing populated input")
  let changedUsage := inputs.set! 0 {first with usage := some first.source}
  let negatives ← [
    ("duplicate-original-inventory",wrongDuplicate),
    ("private-root",{captured with prepared := some changedUsage}),
    ("missing-boundary",{captured with pending := {captured.pending with inputBoundary := none}}),
    ("missing-owners",{captured with owners := none})].toArray.mapM fun (name,query) => do
      let refused ← rejected query
      check refused ("input mismatch was not rejected before erasure: "++name)
      return (name,refused)
  let wireNegatives ← [
    ("ambiguous-reference",{preview with pending := captured.pending}),
    ("reference-without-inputs",{preview with prepared := none}),
    ("reference-without-originals",{preview with originals := none})].toArray.mapM fun (name,query) => do
      let refused ← try
          OperationPool.validate (operation query (← Receipt.fresh))
          pure false
        catch _ => pure true
      check refused ("actual admission accepted invalid prepared reference: "++name)
      return (name,refused)
  check ((toJson pending).compress == frozen) "preview changed the original private pending value"
  check (toJson (← heads) == expected) "audit changed an original source"
  let fullBytes := size (toJson full)
  let compactBytes := size (toJson compact)
  check (compactBytes < fullBytes) "preview did not remove actual request bytes"
  let result := Json.mkObj [
    ("searchFields",← IO.ofExcept (fields (toJson captured))),
    ("pendingFields",← IO.ofExcept (fields (toJson captured.pending))),
    ("frameFields",← IO.ofExcept (fields (toJson frame))),
    ("fullRequestBytes",toJson fullBytes),("previewRequestBytes",toJson compactBytes),
    ("duplicateEnvelopeBytes",toJson (size (toJson captured.pending.preparedInputs))),
    ("full80Bytes",toJson (80*fullBytes)),("preview80Bytes",toJson (80*compactBytes)),
    ("queueByteBound",toJson OperationPlan.maxBytes),("modelFullAdmitted",toJson (accepted fullBytes)),
    ("modelPreviewAdmitted",toJson (accepted compactBytes)),("negatives",toJson negatives),("wireNegatives",toJson wireNegatives),
    ("normalCaptureMs",toJson ((← IO.monoMsNow)-started)),("sources",toJson inputs.size),
    ("originalHeadsUnchanged",toJson true),("privatePendingValueUnchanged",toJson true),
    ("actualValidatorAcceptsBoth",toJson true),("wireRoundTripRestoresWholeRequest",toJson true),
    ("projectionSentToService",toJson false),("productChanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") (result.pretty++"\n")
  IO.println result.compress
end Eggshell.Research.InputFrameChecks
