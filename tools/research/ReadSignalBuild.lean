import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def evidence := project / "docs/candidates/read-signal-trace"
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "could not hash protected source")
  let value := (result.stdout.splitOn " ").headD ""
  unless value.length == 64 do throw (IO.userError "invalid source digest")
  return value

def main (args : List String) : IO Unit := do
  if args == ["seal"] then
    let report := evidence / "native-seal.json"
    unless !(← report.pathExists) do throw (IO.userError "preserve the completed source verification")
    for name in ["native.guard.json","binding-native.guard.json"] do
      let guard ← read (evidence / name)
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
          guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && guard.getObjValD "guardTriggered" == toJson false do
        throw (IO.userError "finish native inspections before sealing their inputs")
    let mut verified : Array (String × String) := #[]
    for stage in ["stage1","stage2"] do
      let history := root.parent.get! / "r0" / stage / "history"
      let files : Array (String × String) ← IO.ofExcept ((← read (history / "history.json")).getObjValAs? _ "sourceFiles")
      for (name,expected) in files do
        unless !name.contains '/' && name != "." && name != ".." do
          throw (IO.userError "invalid original source file")
        let path := history / "source.egg" / name
        let actual ← digest path
        unless actual == expected do throw (IO.userError "a protected original source file changed")
        verified := verified.push (path.toString,actual)
    let descriptors ← IO.ofExcept ((← read (project / "docs/candidates/prepared-bindings/runtime-descriptors.json")).getArr?)
    for entry in descriptors do
      let runtime := entry.getObjValD "runtime"
      let path : System.FilePath := .mk (← IO.ofExcept (runtime.getObjValAs? String "binary"))
      let actual ← digest path
      unless runtime.getObjValD "sha256" == toJson actual do throw (IO.userError "control or candidate runtime changed")
      verified := verified.push (path.toString,actual)
    let build := root / "read-binding-inventory-native-build"
    for (fromName,toName) in [("build.json","binding-native-build.json"),
        ("tools_research_ReadBindingInventory.dependencies","binding-native-entry.dependencies.json"),
        ("runtime.rsp","binding-native.rsp")] do
      IO.FS.writeFile (evidence / toName) (← IO.FS.readFile (build / fromName))
    IO.FS.writeFile report (Json.mkObj [("verifiedOriginalFilesAndRuntimes",toJson verified),
      ("bindingAuditBinarySha256",toJson (← digest (build / "StudyMain"))),
      ("allNativeJobsTerminal",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
    return
  let bindings := args == ["bindings-build"] || args == ["bindings-run"]
  let roots := args == ["roots-build"] || args == ["roots-run"]
  let label := if roots then "read-root-projection-native" else if bindings then "read-binding-inventory-native" else "read-signal-origins-native"
  let recordPrefix := if roots then "roots-native" else if bindings then "binding-native" else "native"
  let mainModule := if roots then "tools.research.ReadRootProjection" else if bindings then "tools.research.ReadBindingInventory" else "tools.research.ReadSignalOrigins"
  let parent := root / "query-cache-baseline-build"
  let output := root / (label ++ "-build")
  if args == ["prepare-run"] || args == ["bindings-run"] || args == ["roots-run"] then
    let guard ← read (evidence / (recordPrefix ++ "-build.guard.json"))
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && guard.getObjValD "guardTriggered" == toJson false do
      throw (IO.userError "finish the guarded native build before using its output")
    let audited ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        (root / "cached-usage-runtime-build").toString,output.toString,
        (evidence / (recordPrefix ++ "-closure.json")).toString]}
    unless audited.exitCode == 0 do throw (IO.userError "native provenance imports differ")
    IO.FS.writeFile (root / (label ++ ".guard-settings.json")) (Json.mkObj [
      ("record",toJson (evidence / (recordPrefix ++ ".guard.json")).toString),("cwd",toJson project.toString),
      ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("command",toJson (#["/usr/bin/env","LEAN_NUM_THREADS=1",(output / "StudyMain").toString,
        (root.parent.get! / "r0/stage1/history/source.egg").toString,
        (if bindings then project / "docs/candidates/query-cache-llvm/missing-support.json" else evidence / "result.json").toString] ++
        (if roots then #[(project / "docs/candidates/query-cache-llvm/missing-support.json").toString] else #[]) ++
        #[(evidence / (if roots then "root-projection.json" else if bindings then "binding-inventory.json" else "native-origins.json")).toString]))]).pretty
    return
  unless args.isEmpty || args == ["bindings-build"] || args == ["roots-build"] do throw (IO.userError "fresh native build or prepare-run required")
  unless !(← output.pathExists) && !(← (evidence / (recordPrefix ++ "-build.guard.json")).pathExists) do
    throw (IO.userError "preserve the previous native provenance audit")
  let build ← read (parent / "build.json")
  let settings := build.getObjValD "settings"
  let mut objects ← IO.ofExcept ((← read (.mk (← IO.ofExcept (settings.getObjValAs? String "objectModules")))).getObj?)
  for entry in ← IO.ofExcept (build.getObjValAs? (Array Json) "modules") do
    objects := objects.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
  let map := root / (label ++ "-objects.json")
  IO.FS.writeFile map (Json.obj objects).pretty
  let plan := settings.setObjVal! "project" (toJson project.toString)
    |>.setObjVal! "baselineResponse" (toJson (parent / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "Main.o").toString)
    |>.setObjVal! "objectModules" (toJson map.toString)
    |>.setObjVal! "mainModule" (toJson mainModule)
    |>.setObjVal! "output" (toJson output.toString)
  IO.FS.writeFile (root / (label ++ "-build.settings.json")) plan.pretty
  IO.FS.writeFile (root / (label ++ "-build.guard-settings.json")) (Json.mkObj [
    ("record",toJson (evidence / (recordPrefix ++ "-build.guard.json")).toString),("cwd",toJson project.toString),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,
      (root / (label ++ "-build.settings.json")).toString])]).pretty
