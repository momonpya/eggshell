import tools.research.StudyLocal
open Lean StudyLocal
namespace InitializationStudy
def practical := base/"practical-runtime"
def root := practical/"initialization"
def records := project/"docs/practical-runtime/initialization"
def runtime := practical/"bound-product/prefix/libexec/eggshell"
def runtimeSha := "bd9096c4378e207b22e1ad48de5906f6967cf7dbbcb1c12722bfc6ce6bb25707"

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← (records/"plan.json").pathExists)) "fresh initialization diagnostic required"
  check ((← hash runtime) == runtimeSha) "diagnostic runtime changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  write (records/"plan.json") (Json.mkObj [("runtime",toJson runtime.toString),("sha256",toJson runtimeSha),
    ("captures",toJson (2 : Nat)),("arguments",toJson #["--help"]),("sampleIntervalMs",toJson (1 : Nat)),
    ("diagnosticOnly",toJson true),("actualHookCalls",toJson (0 : Nat)),("modelCalls",toJson (0 : Nat)),
    ("productChanged",toJson false),("adopted",toJson false)])
  guard "initialization-sampling" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/InitializationStudy.lean").toString,"__profile"]

def profile : IO Unit := do
  check ((← hash runtime) == runtimeSha) "diagnostic runtime changed"
  let mut observations := #[]
  let mut reference : Option String := none
  for index in [:2] do
    let child ← IO.Process.spawn {
      cmd := runtime.toString,args := #["--help"]
      stdin := .null,stdout := .piped,stderr := .piped,setsid := true}
    let output ← IO.asTask child.stdout.readToEnd .dedicated
    let errors ← IO.asTask child.stderr.readToEnd .dedicated
    let exit ← IO.mkRef (none : Option UInt32)
    let stack := records/s!"startup-{index+1}.sample"
    try
      let sampled ← IO.Process.output {
        cmd := "/usr/bin/sample"
        args := #[toString child.pid.toNat,"1","1","-mayDie","-file",stack.toString]}
      let deadline := (← IO.monoMsNow)+10000
      repeat
        if let some code ← child.tryWait then exit.set (some code); break
        check ((← IO.monoMsNow) < deadline) "diagnostic native help did not exit"
        IO.sleep 5
      let stdout ← IO.ofExcept (output.get.mapError IO.Error.toString)
      let stderr ← IO.ofExcept (errors.get.mapError IO.Error.toString)
      check ((← exit.get) == some 0 && stderr.isEmpty) "profiled native command failed"
      if let some previous := reference then check (stdout == previous) "diagnostic changed native help output"
      else reference := some stdout
      observations := observations.push (Json.mkObj [("capture",toJson (index+1)),("pid",toJson child.pid.toNat),
        ("sampleExitCode",toJson sampled.exitCode.toNat),("sampleStdout",toJson sampled.stdout),
        ("sampleStderr",toJson sampled.stderr),("nativeExitCode",toJson (0 : Nat)),
        ("stackExists",toJson (← stack.pathExists)),("nativeSha256",toJson runtimeSha)])
    finally
      if (← exit.get).isNone then
        try child.kill catch _ => pure ()
        discard <| child.wait
  check ((← hash runtime) == runtimeSha) "sampling modified the product"
  write (records/"result.json") (Json.mkObj [("observations",toJson observations),
    ("stdout",toJson reference),("diagnosticOnly",toJson true),("actualHookCalls",toJson (0 : Nat))])

def main : List String → IO Unit
  | ["prepare"] => prepare
  | ["__profile"] => profile
  | _ => throw (IO.userError "InitializationStudy prepare")
end InitializationStudy
def main := InitializationStudy.main
