import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let parent := base / "prepared-record-delivery-20261027"
  let root := base / "quotation-context-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  if args == ["fork"] then
    unless !(← root.pathExists) do throw (IO.userError "preserve previous quotation candidate")
    IO.FS.createDir root
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(parent / "checkout").toString,(root / "checkout").toString]}
    unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
    -- The failed fine-grained frontier is not the implementation parent of
    -- this change. Keep the prior renderer while changing the stored edges.
    let renderer := base / "bound-span-preparation-20261027/checkout/Eggshell/Handoff.lean"
    IO.FS.writeFile (root / "checkout/Eggshell/Handoff.lean") (← IO.FS.readFile renderer)
    IO.FS.removeFile (root / "checkout/.lake/build/lib/lean")
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "product-build/lib").toString,(root / "checkout/.lake/build/lib/lean").toString]}
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
    return
  let [mode,label] := args | throw (IO.userError "fork | MODE LABEL")
  unless ["audit","source","bindings","run-audit","run-source","run-bindings"].contains mode && !label.isEmpty &&
      label.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "known mode/simple label required")
  let command ← if mode.startsWith "run-" then
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (root / label / "data").toString,
      (root / (if mode == "run-source" then "source-current-build/StudyMain" else if mode == "run-bindings" then "bindings-build/StudyMain" else "audit-current-build/StudyMain")).toString,
      (root / label).toString]
  else do
    let reuseBindings := mode != "bindings" && (← (root / "bindings-build/build.json").pathExists)
    let baseline := if reuseBindings then root / "bindings-build" else parent / "product-build"
    let built ← IO.ofExcept (Json.parse (← IO.FS.readFile (baseline / "build.json")))
    let mut objects ← IO.ofExcept (Json.parse (← IO.FS.readFile (parent / "objects.json")) >>= Json.getObj?)
    for entry in ← IO.ofExcept ((built.getObjValD "modules").getArr?) do
      objects := objects.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
    IO.FS.writeFile (root / "objects.json") (Json.obj objects).pretty
    do
      let library := root / "checkout/.lake/build/lib/lean"
      unless (← library.symlinkMetadata).type == .symlink do throw (IO.userError "expected candidate library link")
      IO.FS.removeFile library
      let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(baseline / "lib").toString,library.toString]}
      unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
    let plan := (built.getObjValD "settings").setObjVal! "core" (toJson (root / "checkout").toString)
      |>.setObjVal! "output" (toJson (root / (mode ++ (if reuseBindings then "-current-build" else "-build"))).toString)
      |>.setObjVal! "mainModule" (toJson (if mode == "source" then "tools.research.QuotationSourceAudit" else if mode == "bindings" then "tools.research.SynapticBindingAudit" else "tools.research.QuotationContextAudit"))
      |>.setObjVal! "baselineCore" (toJson ((if reuseBindings then root else parent) / "checkout").toString)
      |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (if reuseBindings then
          (baseline / (("tools.research.SynapticBindingAudit".replace "." "_") ++ ".o")).toString
        else (parent / "product-build/Main.o").toString))
      |>.setObjVal! "objectModules" (toJson (root / "objects.json").toString)
      |>.setObjVal! "force" (toJson (#[] : Array String))
    IO.FS.writeFile (root / (mode ++ "-plan.json")) plan.pretty
    pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean",
      "-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",(root / (mode ++ "-plan.json")).toString]
  IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
