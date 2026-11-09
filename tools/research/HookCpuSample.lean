import tools.research.StudyLocal
open Lean StudyLocal

namespace HookCpuSample
def folder := project/"docs/candidates/hook-cpu"
def result := base/"hook-cpu-result"
def fixture := base/"prepared-literals-fixture"
def auditor := base/"byte-pages-auditor-build/StudyMain"

def setup : IO Unit := do
  idle
  check (!(← result.pathExists)) "fresh diagnostic result required"
  IO.FS.createDirAll folder
  IO.FS.createDirAll result
  let original := base/"prepared-literals-fixture-input.json"
  let runtime := base/"byte-pages-prefix/libexec/eggshell"
  write (result/"probe.json") (Json.mkObj [
    ("originalInput",Json.mkObj [("path",toJson original.toString),("sha256",toJson (← hash original))]),
    ("runtime",Json.mkObj [("path",toJson runtime.toString),("sha256",toJson (← hash runtime))]),
    ("pluginRoot",toJson (base/"byte-pages-prefix/share/eggshell/codex-plugin").toString),
    ("topic",toJson (2 : Nat)),("destination",toJson (result/"hook").toString),
    ("captureReply",toJson false),("requireSharedKeyedImage",toJson true)])
  write (folder/"plan.json") (Json.mkObj [("purpose",toJson "Sample current unchanged publisher CPU after numerical focus, once, without rerunning eighty clients or changing selector weights."),
    ("runtimeSha256",toJson (← hash runtime)),("auditorSha256",toJson (← hash auditor)),
    ("sampleSeconds",toJson (3 : Nat)),("sampleIntervalMs",toJson (5 : Nat)),
    ("observerMayAffectLatency",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "hook-cpu" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M512","--run",
    (project/"tools/research/HookCpuSample.lean").toString,"run"]

def run : IO Unit := do
  let child ← IO.Process.spawn {
    cmd := auditor.toString
    args := #["probe", (result / "probe.json").toString]
    cwd := some project
    stdout := .piped
    stderr := .piped
    stdin := .null
    setsid := true }
  let stdout ← IO.asTask child.stdout.readToEnd .dedicated
  let stderr ← IO.asTask child.stderr.readToEnd .dedicated
  let status ← IO.mkRef (none : Option UInt32)
  let waiting ← IO.asTask (do let code ← child.wait; status.set (some code); return code) .dedicated
  let observationDeadline := (← IO.monoMsNow)+90000
  let mut sampled := false
  let mut sampledPid : Option Nat := none
  while (← IO.monoMsNow) < observationDeadline && (← status.get).isNone do
    let endpoint := fixture/"data/publisher/endpoint.json"
    if ← endpoint.pathExists then
      let value ← read endpoint
      let pid ← IO.ofExcept (value.getObjValAs? Nat "pid")
      let parent ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","ppid="]}
      check (parent.exitCode == 0 && parent.stdout.trimAscii.toString.toNat? == some child.pid.toNat)
        "sampling target is not this diagnostic's child"
      let receipts := fixture/"data/receipts"
      let mut focus := false
      if ← receipts.pathExists then
        for entry in ← receipts.readDir do
          let path := entry.path/"prepared-window-focus.json"
          if ← path.pathExists then
            let row ← read path
            if row.getObjValD "pid" == toJson pid then focus := true
      if focus then
        let sample ← IO.Process.output {
          cmd := "/usr/bin/sample"
          args := #[toString pid,"3","5","-file",(result/"sample.txt").toString] }
        write (result/"sample-command.json") (Json.mkObj [("exitCode",toJson sample.exitCode.toNat),
          ("stdout",toJson sample.stdout),("stderr",toJson sample.stderr),("ownedPublisherPid",toJson pid)])
        sampled := sample.exitCode == 0
        sampledPid := some pid
        break
    IO.sleep 10
  let exitCode ← IO.ofExcept (← IO.wait waiting)
  IO.FS.writeFile (result/"stdout") (← IO.ofExcept (← IO.wait stdout))
  IO.FS.writeFile (result/"stderr") (← IO.ofExcept (← IO.wait stderr))
  write (result/"controller.json") (Json.mkObj [("exitCode",toJson exitCode.toNat),
    ("sampled",toJson sampled),("pid",toJson sampledPid),("answeringModelCalls",toJson (0 : Nat)),
    ("observerMayAffectLatency",toJson true)])
  check (exitCode == 0 && sampled) "CPU diagnostic did not complete"
end HookCpuSample

def main (args : List String) : IO Unit := do
  match args with
  | ["setup"] => HookCpuSample.setup
  | ["retry-setup"] =>
    idle
    let prior ← read (base/"hook-cpu.guard.json")
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "prior observer still live"
    write (HookCpuSample.folder/"setup-refusal.json") (Json.mkObj [("guard",prior),
      ("error",toJson (← IO.FS.readFile (base/"hook-cpu.stdout"))),
      ("nativeRuntimeStarted",toJson false)])
    guard "hook-cpu2" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M512","--run",
      (project/"tools/research/HookCpuSample.lean").toString,"run"]
  | ["run"] => HookCpuSample.run
  | _ => throw (IO.userError "setup | run")
