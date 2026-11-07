import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.ModelAllocationStudy

def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def assets := base/"prefix/share/eggshell/minilm"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot identify allocation input"
  return (result.stdout.splitOn " ").headD ""
def drained : IO Unit := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (!result.stdout.contains "controller/StudyMain guard ") "resource guard is still active"

/-- Same request boundaries in both arms: no batching across clients, text
rewriting, tokenizer changes, model changes or altered normalization. -/
def payload (index : Nat) : Json := Json.mkObj [("texts",toJson (#[
  s!"Independent request {index}: a cached observation retains its source identity.",
  s!"要求{index}: " ++ String.join (List.replicate 8 "非同期の要求ごとに独立した入出力を持ち原文の末尾まで確認する。"),
  s!"요청{index}: " ++ String.join (List.replicate 6 "모든 입력과 원문을 확인하고 독립적으로 처리합니다. "),
  "case_" ++ toString index ++ "() { if (ready && owner) return source[offset]; else return pending; }" ] : Array String))]
def inputs : Array Json := (Array.range 16).map payload |>.push (Json.mkObj [("texts",toJson
  ((Array.range 32).map fun index => s!"window_{index}: " ++ String.join (List.replicate 24
    "if (source[offset] && snapshot == captured) { return original_evidence; }\n")))])
def normalized (reply : Json) : Json :=
  Json.mkObj [("vectors",reply.getObjValD "vectors"),("coverage",reply.getObjValD "coverage")]

abbrev Kernel := IO.Process.Child {stdin := .piped,stdout := .piped,stderr := .inherit}
def exchange (child : Kernel) (input : Json) : IO Json := do
  child.stdin.putStrLn input.compress
  child.stdin.flush
  let reading ← IO.asTask child.stdout.getLine .dedicated
  try
    let deadline := (← IO.monoMsNow)+30000
    repeat
      if ← IO.hasFinished reading then
        let line ← IO.ofExcept (← IO.wait reading)
        check (!line.isEmpty) "encoder ended without a reply"
        let reply ← IO.ofExcept (Json.parse line)
        if let .ok error := reply.getObjValAs? String "error" then throw (IO.userError error)
        return reply
      check ((← IO.monoMsNow) < deadline) "allocation probe request timed out"
      IO.sleep 5
    throw (IO.userError "unreachable allocation probe")
  finally
    unless ← IO.hasFinished reading do child.kill
    discard <| IO.wait reading
def rss (pid : Nat) : IO Nat := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","rss="]}
  check (result.exitCode == 0) "encoder disappeared before memory measurement"
  let some bytes := result.stdout.trimAscii.toString.toNat? | throw (IO.userError "invalid RSS observation")
  return bytes

def one (root : System.FilePath) (kernel mode : String) (pair : Nat) : IO (Array Json × Json) := do
  let folder := root/s!"pair-{pair}-{mode}"
  IO.FS.createDirAll folder
  let source := folder/"kernel.txt"
  IO.FS.writeFile source kernel
  let child ← IO.Process.spawn {
    cmd := (assets/"fastembed-0.8.0/bin/python").toString
    args := #["-c",kernel,"sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
      (assets/"models").toString,"4",(folder/"model.guard").toString,"shared"],
    stdin := .piped,stdout := .piped,stderr := .inherit}
  try
    let mut replies := #[]
    let mut observations := #[]
    for index in [:inputs.size] do
      let started ← IO.monoMsNow
      let reply ← exchange child inputs[index]!
      let elapsed := (← IO.monoMsNow)-started
      let value := normalized reply
      let request := inputs[index]!
      let texts ← IO.ofExcept (request.getObjValAs? (Array String) "texts")
      let coverage ← IO.ofExcept ((reply.getObjValD "coverage").getArr?)
      let vectors ← IO.ofExcept ((reply.getObjValD "vectors").getArr?)
      check (coverage.size == texts.size && vectors.size == texts.size) "allocation response lost an input"
      for group in vectors do
        let group ← IO.ofExcept group.getArr?
        check (!group.isEmpty) "allocation response has an empty vector group"
        for row in group do check ((← IO.ofExcept row.getArr?).size == 384) "embedding width changed"
      let result := folder/s!"reply-{index}.json"
      write result value
      replies := replies.push value
      observations := observations.push (Json.mkObj [("request",toJson index),("elapsedMs",toJson elapsed),
        ("rssAfterReplyKiB",toJson (← rss child.pid.toNat)),("timing",reply.getObjValD "timing"),
        ("normalizedReplySha256",toJson (← hash result))])
    IO.sleep 100
    let summary := Json.mkObj [("mode",toJson mode),("pair",toJson pair),("pid",toJson child.pid.toNat),
      ("kernelSha256",toJson (← hash source)),("rssAfterIdleKiB",toJson (← rss child.pid.toNat)),
      ("observations",toJson observations),("allOriginalRequestBoundariesPreserved",toJson true)]
    write (folder/"report.json") summary
    return (replies,summary)
  finally
    if (← child.tryWait).isNone then
      child.kill
      discard <| child.wait

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier allocation experiment"
  IO.FS.createDirAll root
  let original := base/"elastic-encoder-source/runtime/embedding.py"
  let kernel ← IO.FS.readFile original
  let before := "threads=int(sys.argv[3]), local_files_only=True)"
  let after := "threads=int(sys.argv[3]), local_files_only=True, enable_cpu_mem_arena=False)"
  check ((kernel.splitOn before).length == 2) "allocation option must change exactly one initializer"
  let candidate := kernel.replace before after
  write (root/"inputs.json") (toJson inputs)
  let mut pairs := #[]
  for pair in [:3] do
    let arms := if pair % 2 == 0 then [("default",kernel),("released",candidate)]
      else [("released",candidate),("default",kernel)]
    let mut reference : Array Json := #[]
    let mut observations := #[]
    for (mode,source) in arms do
      let (replies,report) ← one root source mode pair
      if reference.isEmpty then reference := replies
      else check (replies == reference) "allocation policy changed vectors or coverage"
      observations := observations.push report
    pairs := pairs.push (Json.mkObj [("pair",toJson pair),("bothArmsExact",toJson true),("arms",toJson observations)])
    write (root/"progress.json") (toJson pairs)
  write (root/"report.json") (Json.mkObj [("allPassed",toJson true),("pairs",toJson pairs),
    ("originalKernelSha256",toJson (← hash original)),("onlyInitializerArgumentChanged",toJson true),
    ("normalizedRepliesCompared",toJson (3*2*inputs.size)),("fullHookOrEightyUsers",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def setup (tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh allocation guard required"
  write settings (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M512","--run",
    (workspace/"tools/research/ModelAllocationStudy.lean").toString,"run",(base/(tag++"-result")).toString]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def collect (tag : String) : IO Unit := do
  drained
  check (tag == "model-allocation1") "unknown fixed allocation experiment"
  let root := base/(tag++"-result")
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "allocation experiment has not terminated successfully"
  let report ← read (root/"report.json")
  check (report.getObjValD "allPassed" == toJson true &&
    report.getObjValD "normalizedRepliesCompared" == toJson (102 : Nat)) "retain all fixed pairs"
  check (report.getObjValD "originalKernelSha256" == toJson (← hash (base/"elastic-encoder-source/runtime/embedding.py")))
    "original numerical input changed"
  check ((← read (root/"inputs.json")) == toJson inputs) "allocation request boundary changed"
  let pairs ← IO.ofExcept ((report.getObjValD "pairs").getArr?)
  let mut retainedMemoryImproved := true
  for pair in pairs do
    let arms ← IO.ofExcept ((pair.getObjValD "arms").getArr?)
    let some standard := arms.find? (fun arm => arm.getObjValD "mode" == toJson "default") |
      throw (IO.userError "missing allocation reference")
    let some released := arms.find? (fun arm => arm.getObjValD "mode" == toJson "released") |
      throw (IO.userError "missing allocation treatment")
    let before ← IO.ofExcept (standard.getObjValAs? Nat "rssAfterIdleKiB")
    let after ← IO.ofExcept (released.getObjValAs? Nat "rssAfterIdleKiB")
    retainedMemoryImproved := retainedMemoryImproved && after < before
  let destination := workspace/"docs/candidates/model-allocation"
  IO.FS.createDirAll destination
  let stderr := base/(tag++".stderr")
  let captured ← stderr.pathExists
  write (destination/"controls.json") (Json.mkObj [("guard",guard),("experiment",report),
    ("retainedMemoryImprovedAllPairs",toJson retainedMemoryImproved),("adopted",toJson false),
    ("fullHookOrEightyUsers",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("stderrCapturedToFile",toJson captured),
    ("controllerSha256AtCollection",toJson (← hash (workspace/"tools/research/ModelAllocationStudy.lean")))])
  write (destination/"inputs.json") (toJson inputs)
  if captured then IO.FS.writeFile (destination/"stderr.txt") (← IO.FS.readFile stderr)
def cleanup : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/model-allocation"
  let evidence ← read (destination/"controls.json")
  let guard := evidence.getObjValD "guard"
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    evidence.getObjValD "retainedMemoryImprovedAllPairs" == toJson false) "preserve completed negative result first"
  let root := base/"model-allocation1-result"
  let mut removed := #[]
  for pair in [:3] do
    for mode in ["default","released"] do
      let folder := root/s!"pair-{pair}-{mode}"
      let report ← read (folder/"report.json")
      let source := folder/"kernel.txt"
      check (toJson (← hash source) == report.getObjValD "kernelSha256") "probe kernel changed"
      for row in (report.getObjValD "observations").getArr?.toOption.getD #[] do
        let index ← IO.ofExcept (row.getObjValAs? Nat "request")
        check (index < inputs.size) "allocation cleanup escaped fixed inputs"
        let reply := folder/s!"reply-{index}.json"
        check (toJson (← hash reply) == row.getObjValD "normalizedReplySha256") "probe reply changed"
        removed := removed.push reply
      removed := removed.push source
  write (destination/"cleanup.json") (Json.mkObj [("files",toJson (removed.map (·.toString))),
    ("completed",toJson false),("archived",toJson false)])
  for file in removed do IO.FS.removeFile file
  write (destination/"cleanup.json") (Json.mkObj [("files",toJson (removed.map (·.toString))),
    ("completed",toJson true),("archived",toJson false)])
def main (args : List String) : IO Unit := match args with
  | ["setup",tag] => setup tag
  | ["run",root] => run (.mk root)
  | ["collect",tag] => collect tag
  | ["cleanup"] => cleanup
  | _ => throw (IO.userError "setup TAG | run OUTPUT")
end Eggshell.Research.ModelAllocationStudy
def main := Eggshell.Research.ModelAllocationStudy.main
