module
public import Lean
public import tools.research.SharedEncoder
public import tools.research.EncoderPool
public import Eggshell.Sha256

@[expose] public section
namespace Eggshell.Research.SharedEncoderControls
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def kernel : String := include_str "../../runtime/shared_embedding.py"
def normalized (reply : String) : IO String := do
  let value ← IO.ofExcept (Json.parse reply)
  return (Json.mkObj [("vectors",value.getObjValD "vectors"),("coverage",value.getObjValD "coverage")]).compress
def verify (rows : Array Json) (index : Nat) (reply : String) : IO Unit := do
  let normalized ← normalized reply
  check (rows[index]!.getObjValD "normalizedReplySha256" == toJson (Sha256.hex normalized.toUTF8))
    "Lean shared encoder changed the fixed numerical response"

run_elab do
  let environment ← Lean.getEnv
  for target in [``SharedEncoder.Server.request,``SharedEncoder.waitReply,``SharedEncoder.waitStartup] do
    let some body := (environment.find? target).bind (·.value?) | throwError "Missing shared request/wait body"
    for forbidden in [``Std.Mutex.atomically,``Std.Mutex.tryAtomically] do
      if body.getUsedConstants.contains forbidden then throwError "Shared request waits in a management transaction"

#check SharedEncoder.Reply.foreign_rejected
#check SharedEncoder.Reply.bound
#check SharedEncoder.State.reserve_advances
#check SharedEncoder.State.reserve_fresh
#check SharedEncoder.State.reserve_older
#check SharedEncoder.State.extract_preserves_generation
#check SharedEncoder.State.extract_older
#check SharedEncoder.State.retire_once
#check SharedEncoder.State.retire_preserves_generation
#check SharedEncoder.State.retire_older

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous Lean transport evidence"
  IO.FS.createDirAll root
  let input ← read (workspace/"docs/candidates/shared-model/inputs.json")
  let inputs ← IO.ofExcept input.getArr?
  let previous := (← read (workspace/"docs/candidates/shared-model/controls.json")).getObjValD "experiment"
  let expected ← IO.ofExcept ((previous.getObjValD "reference").getObjValAs? (Array Json) "observations")
  check (inputs.size == 17 && expected.size == inputs.size) "fixed complete numerical domain required"
  let assets := base/"prefix/share/eggshell/minilm"
  let server ← SharedEncoder.Server.start (IO.Process.spawn {
    cmd := (assets/"fastembed-0.8.0/bin/python").toString,
    args := #["-c",kernel,"sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
      (assets/"models").toString,"4",(root/"model.guard").toString,"shared"],
    stdin := .piped,stdout := .piped,stderr := .inherit})
  let pool ← EncoderPool.Pool.make 2
  let encode := fun index live => pool.withResource live (fun _ => pure ()) (fun _ => pure ()) fun _ _ _ => do
    let reply ← server.request inputs[index]!.compress ((← IO.monoMsNow)+30000) live
    verify expected index reply
    return reply
  try
    let mut waves := #[]
    for wave in [:2] do
      let began ← IO.monoMsNow
      let tasks ← (Array.range inputs.size).mapM fun index => IO.asTask (do
        let started ← IO.monoMsNow
        let reply ← encode index (pure true)
        let value ← IO.ofExcept (Json.parse reply)
        check (value.getObjValD "pid" == toJson server.core.child.pid.toNat) "shared encoder changed its process"
        return Json.mkObj [("request",toJson index),("identity",value.getObjValD "id"),
          ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("exact",toJson true)]) .dedicated
      let rows ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
      check ((rows.map (·.getObjValD "identity")).toList.eraseDups.length == inputs.size &&
        (← server.pending) == 0) "shared wave repeated an identity or retained a response"
      let value := Json.mkObj [("wave",toJson wave),("requests",toJson rows.size),("rows",toJson rows),
        ("wallMs",toJson ((← IO.monoMsNow)-began))]
      write (root/s!"wave-{wave}.json") value
      waves := waves.push value
    let live ← IO.mkRef true
    let cancelled ← IO.asTask (encode (inputs.size-1) live.get) .dedicated
    let survivor ← IO.asTask (encode 0 (pure true)) .dedicated
    let activationDeadline := (← IO.monoMsNow)+5000
    while (← server.pending) < 2 do
      check ((← IO.monoMsNow) < activationDeadline) "two shared requests never became active"
      IO.sleep 1
    live.set false
    let cancelledResult ← IO.wait cancelled
    let .error cancelledError := cancelledResult | throw (IO.userError "expired shared request unexpectedly completed")
    check (cancelledError.toString.contains "expired or disconnected") "shared request failed for an unrelated reason"
    let survivorResult ← IO.ofExcept (← IO.wait survivor)
    verify expected 0 survivorResult
    discard <| encode 0 (pure true)
    check ((← server.pending) == 0 && !(← server.closed)) "individual cancellation retired the shared model"
    write (root/"report.json") (Json.mkObj [("allPassed",toJson true),("waves",toJson waves),
      ("parallelRepliesExact",toJson (2*inputs.size)),("cancelledRequestRejected",toJson true),
      ("survivorAndFollowingResponseExact",toJson true),("modelProcesses",toJson (1 : Nat)),
      ("pid",toJson server.core.child.pid.toNat),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  finally
    pool.close (fun _ => pure ())
    server.close
  check (← server.closed) "shared encoder did not close"
  let taskEnded ← IO.hasFinished server.reader
  check taskEnded "shared encoder reader outlived shutdown"
  write (root/"shutdown.json") (Json.mkObj [("readerJoined",toJson true),("closed",toJson true),
    ("pending",toJson (← server.pending)),("pid",toJson server.core.child.pid.toNat)])
  let startupLive ← IO.mkRef true
  let startupPid ← IO.mkRef (none : Option Nat)
  let starting ← IO.asTask (SharedEncoder.Server.start (do
      let child ← IO.Process.spawn {
        cmd := "/bin/sleep"
        args := #["10"]
        stdin := .piped
        stdout := .piped
        stderr := .inherit }
      startupPid.set (some child.pid.toNat)
      return child) startupLive.get) .dedicated
  let activationDeadline := (← IO.monoMsNow)+1000
  while (← startupPid.get).isNone do
    check ((← IO.monoMsNow) < activationDeadline) "startup fixture did not start"
    IO.sleep 1
  let began ← IO.monoMsNow
  startupLive.set false
  let stopped ← IO.wait starting
  let .error error := stopped | throw (IO.userError "service stop did not cancel unready model startup")
  check (error.toString.contains "startup expired or service stopped" && (← IO.monoMsNow)-began < 1000)
    "startup ignored its service lifetime"
  let pid := (← startupPid.get).get!
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","stat="]}
  check (process.exitCode != 0 || process.stdout.trimAscii.toString.startsWith "Z") "startup child survived cancellation"
  write (root/"startup-stop.json") (Json.mkObj [("cancelled",toJson true),("processExited",toJson true),
    ("elapsedMs",toJson ((← IO.monoMsNow)-began)),("pid",toJson pid)])

end Eggshell.Research.SharedEncoderControls
