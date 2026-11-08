import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace SearchCpuStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := workspace/"docs/candidates/search-cpu"
def output := base/"search-cpu-result"
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.contains base.toString && !row.contains "SearchCpuStudy.lean")) "an experiment is live"
partial def removeOwnedTree (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do removeOwnedTree entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
def collectThin : IO Unit := do
  drained
  check (!(← (folder/"observation.json").pathExists)) "preserve CPU observation"
  let status ← read (base/"search-cpu-thin1.guard.json")
  check (status.getObjValD "state" == toJson "finished" && status.getObjValD "exitCode" == toJson (0 : Nat) &&
    status.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "CPU observation did not finish and drain"
  let report ← read (output/"report.json")
  check (report.getObjValD "allFourFrozenBodiesByteEqual" == toJson true &&
    report.getObjValD "originalSourceFilesUnchanged" == toJson true &&
    report.getObjValD "runtimeSha256" == toJson (← hash (base/"deferred-audit-build/StudyMain"))) "CPU target or frozen bodies changed"
  let mut samples := #[]
  for index in [:3] do
    let path := output/s!"cpu-{index}.txt"
    let metadata ← read (output/s!"cpu-{index}.json")
    check (metadata.getObjValD "exitCode" == toJson (0 : Nat)) "native CPU sample failed"
    let text ← IO.FS.readFile path
    let lines := text.splitOn "\n" |>.toArray
    let marker := "Sort by top of stack, same collapsed (when >= 5):"
    let parts := text.splitOn marker
    check (parts.length == 2 && text.contains "l_Eggshell_Research_RegisterMix_instDecidableValid")
      "CPU sample does not contain the concrete mix-guard observation"
    let leaves := marker++(parts[1]!.splitOn "\nBinary Images:").headD ""
    let mut contexts := #[]
    for offset in [:lines.size] do
      if !lines[offset]!.contains "l_Eggshell_Research_RegisterMix_instDecidableValid" then continue
      contexts := contexts.push (Json.mkObj [("line",toJson (offset+1)),
        ("text",toJson ("\n".intercalate (lines.extract (offset-16) (min lines.size (offset+5))).toList))])
    samples := samples.push (Json.mkObj [("index",toJson index),("sha256",toJson (← hash path)),
      ("bytes",toJson text.utf8ByteSize),("metadata",metadata),
      ("header",toJson ("\n".intercalate (lines.extract 0 23).toList)),
      ("leafCountsAreSamplesNotCpuTime",toJson true),("topOfStack",toJson leaves),("mixCallPaths",toJson contexts)])
  let mut hooks := #[]
  for entry in ← output.readDir do
    if !(entry.fileName.startsWith "prime-" || entry.fileName.startsWith "query-") ||
      !entry.fileName.endsWith ".json" then continue
    hooks := hooks.push (← read entry.path)
  let mut sources := #[]
  for name in ["Eggshell_Blake3","tools_research_RegisterMix"] do
    let mut found := false
    for line in (← IO.FS.readFile (base/"deferred-audit-build/runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let object : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if object.fileName != some (name++".o") then continue
      let witness ← IO.ofExcept (fromJson? (← read (object.withExtension "source")) : Except String (String × Array (String × String)))
      let relative := if name == "Eggshell_Blake3" then "Eggshell/Blake3.lean" else "tools/research/RegisterMix.lean"
      check (witness.1 == (← IO.FS.readFile (base/"deferred-audit-source"/relative))) "observed hot code differs from its linked source"
      sources := sources.push (Json.mkObj [("module",toJson relative),("object",toJson object.toString),
        ("sourceSha256",toJson (← hash (base/"deferred-audit-source"/relative))),("sourceEqualsLinkedWitness",toJson true)])
      found := true
    check found "observed native module is absent"
  write (folder/"observation.json") (Json.mkObj [("report",report),("guard",status),("samples",toJson samples),
    ("hooks",toJson hooks),("linkedHotModules",toJson sources),
    ("frontendShutdown",← read (output/"frontend-shutdown.json")),
    ("publisherShutdown",← read (output/"publisher-shutdown.json")),
    ("stderr",toJson (← IO.FS.readFile (base/"search-cpu-thin1.stderr"))),
    ("answeringModelCalls",toJson (0 : Nat)),("newCapacityGate",toJson false),("adopted",toJson false)])
def cleanupThin : IO Unit := do
  drained
  let observation ← read (folder/"observation.json")
  check (!(← (folder/"cleanup.json").pathExists)) "preserve CPU cleanup"
  let input ← read (base/"search-cpu-input.json")
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  check (data == base/"real-source-search-read-trial-result/data") "cleanup changed its diagnostic data scope"
  let mut removed := #[]
  for row in ← IO.ofExcept (observation.getObjValAs? (Array Json) "hooks") do
    let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
    let session ← IO.ofExcept (row.getObjValAs? String "session")
    check (receipt.length == 64 && receipt.toList.all Char.isAlphanum &&
      (session.startsWith "cpu-query-" || session.startsWith "cpu-prime-")) "cleanup escaped generated CPU observations"
    for path in [data/"receipts"/receipt,data/"sessions"/session] do
      if ← path.pathExists then
        removeOwnedTree path
        removed := removed.push path.toString
  removeOwnedTree output
  for extension in ["stdout","stderr"] do
    let path := base/("search-cpu-thin1."++extension)
    if ← path.pathExists then IO.FS.removeFile path
  write (folder/"cleanup.json") (Json.mkObj [("generatedSessionsAndReceipts",toJson removed),
    ("rawSamplesAndDuplicateStdoutRemoved",toJson true),("originalDbProjectCacheModelAndComparisonBodiesRetained",toJson true),
    ("archived",toJson false)])

/-- Configure the small CLI observer. The abandoned whole-product driver and
one-time retirement commands are deliberately not retained as runnable paths. -/
def prepare : IO Unit := do
  drained
  check (!(← output.pathExists)) "fresh CPU observation required"
  check (!(← (base/"search-cpu-input.json").pathExists)) "preserve the frozen observation input"
  IO.FS.createDirAll folder
  let input := (← read (workspace/"docs/candidates/deferred-audit/capacity-small.json")).getObjValD "input"
  let environment ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let environment := environment.map fun (name,value) => (name,match name with
    | "EGGSHELL_CONFIG" => some (output/"config.toml").toString
    | "EGGSHELL_TRACE_SERVICE_PROFILE" => some "1"
    | _ => value)
  let environment := if environment.any (·.1 == "EGGSHELL_TRACE_SERVICE_PROFILE") then environment
    else environment.push ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1")
  write (base/"search-cpu-input.json") (input.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "config" (toJson (output/"config.toml").toString)
    |>.setObjVal! "counts" (toJson (#[(4 : Nat)]))
    |>.setObjVal! "diagnostic" (toJson true)
    |>.setObjVal! "gate" Json.null
    |>.setObjVal! "environment" (toJson environment))

def setup (tag : String) : IO Unit := do
  drained
  check (tag.startsWith "search-cpu-thin") "known observer owner required"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve the previous CPU observation"
  let input ← read (base/"search-cpu-input.json")
  let environment ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let unset := environment.toList.flatMap fun (name,value) => if value.isNone then ["-u",name] else []
  let args := #["/usr/bin/env"]++unset.toArray++#["LEAN_NUM_THREADS=1"]++
    environment.filterMap (fun (name,value) => value.map (fun value => name++"="++value))++
    #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (workspace/"tools/research/SearchCpuThin.lean").toString,(base/"search-cpu-input.json").toString]
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["setup",tag] => setup tag
  | ["collect"] => collectThin
  | ["cleanup"] => cleanupThin
  | _ => throw (IO.userError "search CPU: prepare|setup TAG|collect|cleanup")
end SearchCpuStudy
def main := SearchCpuStudy.main
