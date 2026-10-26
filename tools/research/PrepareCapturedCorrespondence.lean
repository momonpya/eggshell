import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

def main (args : List String) : IO Unit := do
  let [mode,label] := args | throw (IO.userError "PrepareCapturedCorrespondence audit|product LABEL")
  unless ["audit","product","publication","hooks","contract","resume","run","run-publication","run-hooks"].contains mode && !label.isEmpty &&
      label.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "known build mode and simple label required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "captured-correspondence-20261026"
  let parent := if mode == "product" then base / "shared-bundle-projection-20261026" else root
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  if mode == "resume" then
    let settings := Json.mkObj [
      ("command",toJson #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",
        toolchain ++ "/bin/lean","-j1","-M1024","--run",project ++ "/tools/research/StudyBuildMain.lean",
        "resume-check",(root / "build-resume").toString]),
      ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]
    IO.FS.writeFile (root / (label ++ "-settings.json")) settings.pretty
    return
  if mode == "run" || mode == "run-publication" || mode == "run-hooks" then
    let output := root / label
    let executable := root / (if mode == "run" then "audit-build/StudyMain"
      else if mode == "run-hooks" then "hooks-build/StudyMain" else "publication-build/StudyMain")
    let arguments := if mode == "run-hooks" then #[root.toString,output.toString] else #[output.toString]
    let data := if mode == "run-hooks" then output / "native/data" else output / "data"
    let settings := Json.mkObj [
      ("command",toJson (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ data.toString,
        executable.toString] ++ arguments)),
      ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]
    IO.FS.writeFile (root / (label ++ "-settings.json")) settings.pretty
    return
  let baseline ← read (parent / "product-build/build.json")
  let mut objects ← IO.ofExcept ((← read (parent / "objects.json")).getObj?)
  for moduleInfo in ← IO.ofExcept ((baseline.getObjValD "modules").getArr?) do
    objects := objects.insert (← IO.ofExcept (moduleInfo.getObjValAs? String "object")) (moduleInfo.getObjValD "module")
  IO.FS.writeFile (root / "objects.json") (Json.obj objects).pretty
  let plan := baseline.getObjValD "settings"
    |>.setObjVal! "core" (toJson (root / "checkout").toString)
    |>.setObjVal! "output" (toJson (root / (mode ++ "-build")).toString)
    |>.setObjVal! "mainModule" (toJson (if mode == "audit" then "tools.research.ContentCaptureAudit"
      else if mode == "publication" then "tools.research.CapturedPublicationAudit"
      else if mode == "hooks" then "tools.research.CapturedHookAudit"
      else if mode == "contract" then "tools.research.CapturedContractMain" else "Main"))
    |>.setObjVal! "force" (toJson (if mode == "product" then #["Main"]
      else if mode == "contract" then #["Eggshell.ContractAudit"] else (#[] : Array String)))
    |>.setObjVal! "objectModules" (toJson (root / "objects.json").toString)
    |>.setObjVal! "baselineResponse" (toJson (parent / "product-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "product-build/Main.o").toString)
    |>.setObjVal! "baselineCore" (toJson (parent / "checkout").toString)
  IO.FS.writeFile (root / (mode ++ "-plan.json")) plan.pretty
  let library := root / "checkout/.lake/build/lib/lean"
  IO.FS.removeFile library
  let link ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "product-build/lib").toString,library.toString]}
  unless link.exitCode == 0 do throw (IO.userError link.stderr)
  let settings := Json.mkObj [
    ("command",toJson #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",
      toolchain ++ "/bin/lean","-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",
      (root / (mode ++ "-plan.json")).toString]),
    ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]
  IO.FS.writeFile (root / (label ++ "-settings.json")) settings.pretty
