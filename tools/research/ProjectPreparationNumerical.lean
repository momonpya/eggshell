import Eggshell.PreparationRegistry
import Eggshell.PublicationClient

open Lean Eggshell Eggshell.Plugin

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def stats : IO Json := do
  let value ← IO.ofExcept (Json.parse (← Publication.Client.control "stats"))
  IO.ofExcept (value.getObjVal? "preparation")

def numericalPreparationCommand (args : List String) : IO Unit := do
  let [binaryPath,rootPath] := args | throw (IO.userError "native helper and existing fixture required")
  let binary : System.FilePath := .mk binaryPath
  let root : System.FilePath := .mk rootPath
  let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "complete numerical fixture scope missing")
  let some (_ :: providerArgs) ← MiniLM.command (← Paths.installRoot) |
    throw (IO.userError "installed MiniLM runtime required")
  let provider := binary.toString :: providerArgs
  let targets ← context.reads.sources.mapM fun source =>
    registerIndexTarget source provider (context.canPrepare (DB.Sidecar.Owner.ofSnapshot source))
  let before ← targets.mapM fun target => do return (← target.owner.pin).head
  let child ← IO.Process.spawn {
    cmd := binary.toString,args := #["serve"],stdin := .null,stdout := .null,stderr := .inherit,setsid := true}
  try
    let startup := (← IO.monoMsNow)+10000
    repeat
      if (← Publication.Client.endpoint?).isSome then break
      if let some code ← child.tryWait then throw (IO.userError s!"native service exited: {code}")
      check ((← IO.monoMsNow) < startup) "native numerical service startup expired"
      IO.sleep 5
    let started ← IO.monoMsNow
    for target in targets do
      check (← Publication.Client.enqueuePreparation "index" target.key ((← IO.monoMsNow)+10000))
        "numerical target was not admitted"
    let deadline := (← IO.monoMsNow)+60000
    let mut prepared := Json.null
    repeat
      prepared ← stats
      if (prepared.getObjValAs? Nat "pending").toOption == some 0 &&
          (prepared.getObjValAs? Nat "active").toOption == some 0 then break
      check ((← IO.monoMsNow) < deadline) s!"numerical preparation debt did not drain: {prepared.compress}"
      IO.sleep 10
    let elapsedMs := (← IO.monoMsNow)-started
    let mut repeats := #[]
    let mut matrices : Array (String × Nat) := #[]
    for target in targets do
      let source ← target.owner.pin
      check (!(← Warm.required target source)) "actual MiniLM source remained cold"
      let sidecar ← DB.Sidecar.locate source target.storage
      let matrix ← VectorMatrix.open? sidecar.semantic MiniLM.model SearchProvider.encoderContract
      if let some matrix := matrix then
        if !(matrices.any (fun item => item.1 == sidecar.semantic.toString)) then
          matrices := matrices.push (sidecar.semantic.toString,matrix.metadata.rows)
      let repeated ← Warm.runTarget source target
      check (repeated.requested == 0 && repeated.projections.all (·.produced == 0))
        "unchanged service preparation requested numerical work again"
      repeats := repeats.push (toJson repeated)
    check (matrices.any (fun item => item.2 > 0)) "actual MiniLM service produced no projection rows"
    let after ← targets.mapM fun target => do return (← target.owner.pin).head
    check (before == after) "numerical preparation changed an acknowledged original"
    let report := Json.mkObj [("allPassed",toJson true),("actualMiniLM",toJson true),
      ("sourceCount",toJson targets.size),("servicePreparationMs",toJson elapsedMs),
      ("service",prepared),("matrices",toJson matrices),("unchangedRepeat",toJson repeats),
      ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
      ("eightyPersonCapacity",toJson false),("productionAdoption",toJson false)]
    IO.FS.writeFile (root/"numerical-service-report.json") (report.pretty++"\n")
    IO.println report.compress
  finally
    try let _ ← Publication.Client.control "shutdown" catch _ => pure ()
    let _ ← child.wait
    pure ()
