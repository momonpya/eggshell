import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Isolated dead-transfer experiment. It reuses the one prepared source
checkpoint; no answering model, new seed, or full warm is launched here. -/
def main (args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let parent := base / "joint-range-bindings-20261027"
  let root := base / "prepared-original-service-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  if args == ["fork"] then
    unless !(← root.pathExists) do throw (IO.userError "preserve existing original-service candidate")
    IO.FS.createDir root
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",
      (parent / "checkout").toString,(root / "checkout").toString]}
    unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
    let path := root / "checkout/Eggshell/SynapseTransport.lean"
    let text ← IO.FS.readFile path
    if (← path.symlinkMetadata).type == .symlink then IO.FS.removeFile path
    IO.FS.writeFile path text
    return
  let [mode,label] := args | throw (IO.userError "fork | MODE LABEL")
  unless ["product","hook","run-hook"].contains mode && !label.isEmpty &&
      label.toList.all (fun c => c.isAlphanum || c == '-') do
    throw (IO.userError "known mode/simple label required")
  let command ← if mode == "run-hook" then
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (root / label / "data").toString,
      (root / "hook-build/StudyMain").toString,root.toString,(root / label).toString,
      (base / "packet-delivery-ledger-20261027/one-prepared-hook").toString]
  else do
    let own := mode == "hook"
    let baseline := if own then root / "product-build" else parent / "product-build"
    let origin := if own then root else parent
    let library := root / "checkout/.lake/build/lib/lean"
    unless (← library.symlinkMetadata).type == .symlink do
      throw (IO.userError "candidate library must be a link")
    IO.FS.removeFile library
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(baseline / "lib").toString,library.toString]}
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
    let built ← IO.ofExcept (Json.parse (← IO.FS.readFile (baseline / "build.json")))
    let mut objects ← IO.ofExcept (Json.parse (← IO.FS.readFile (origin / "objects.json")) >>= Json.getObj?)
    for entry in ← IO.ofExcept ((built.getObjValD "modules").getArr?) do
      objects := objects.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
    IO.FS.writeFile (root / "objects.json") (Json.obj objects).pretty
    let plan := (built.getObjValD "settings")
      |>.setObjVal! "core" (toJson (root / "checkout").toString)
      |>.setObjVal! "output" (toJson (root / (mode ++ "-build")).toString)
      |>.setObjVal! "mainModule" (toJson (if own then "tools.research.OnePreparedHook" else "Main"))
      |>.setObjVal! "baselineCore" (toJson (origin / "checkout").toString)
      |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (baseline / "Main.o").toString)
      |>.setObjVal! "objectModules" (toJson (root / "objects.json").toString)
      |>.setObjVal! "force" (toJson (#[] : Array String))
    IO.FS.writeFile (root / (mode ++ "-plan.json")) plan.pretty
    pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",
      toolchain ++ "/bin/lean","-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",
      (root / (mode ++ "-plan.json")).toString]
  IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
    ("command",toJson command),("cwd",toJson project),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("ownedPrefixes",toJson #[root.toString]),
    ("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
