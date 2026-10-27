import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let parent := base / "quotation-context-20261027"
  let root := base / "packet-delivery-ledger-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  if args == ["capture-contract"] then
    let result ← IO.Process.output {
      cmd := toolchain ++ "/bin/lean"
      args := #["-j1","-M1536","-DwarningAsError=true",project ++ "/tools/research/PacketLedgerContract.lean"]
      env := #[("LEAN_PATH",some ((root / "audit-build/lib").toString ++ ":" ++ toolchain ++ "/lib/lean")),
        ("LEAN_NUM_THREADS",some "1")]}
    IO.FS.writeFile (root / "contract.stdout") result.stdout
    IO.FS.writeFile (root / "contract.stderr") result.stderr
    unless result.exitCode == 0 do throw (IO.userError (result.stdout ++ result.stderr))
    return
  if args == ["fork"] then
    unless !(← root.pathExists) do throw (IO.userError "preserve existing packet candidate")
    IO.FS.createDir root
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(parent / "checkout").toString,(root / "checkout").toString]}
    unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
    return
  let [mode,label] := args | throw (IO.userError "fork | MODE LABEL")
  unless ["audit","payload","product","hook","run-audit","run-payload","run-hook","run-ready-hook","contract"].contains mode && !label.isEmpty &&
      label.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "known mode/simple label required")
  let command ← if mode == "contract" then
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-j1","-M1536","--run",
      project ++ "/tools/research/PreparePacketLedger.lean","capture-contract"]
  else if mode == "run-hook" || mode == "run-ready-hook" then
    pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (root / label / "data").toString,
      (root / "hook-build/StudyMain").toString,root.toString,(root / label).toString] ++
      if mode == "run-ready-hook" then #[(root / "one-prepared-hook").toString] else #[])
  else if mode == "run-audit" || mode == "run-payload" then
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (root / label / "data").toString,
      (root / (if mode == "run-payload" then "payload-build/StudyMain" else "audit-build/StudyMain")).toString,(root / label).toString]
  else do
    let reuseAudit := mode != "audit" && (← (root / "audit-build/build.json").pathExists)
    let origin := if reuseAudit then root else parent
    let baseline := if reuseAudit then root / "audit-build" else parent / "bindings-build"
    let library := root / "checkout/.lake/build/lib/lean"
    unless (← library.symlinkMetadata).type == .symlink do throw (IO.userError "candidate library must be a link")
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
      |>.setObjVal! "mainModule" (toJson (if mode == "product" then "Main" else if mode == "hook" then "tools.research.OnePreparedHook" else if mode == "payload" then "tools.research.NativePacketPayloadAudit" else "tools.research.PacketLedgerAudit"))
      |>.setObjVal! "baselineCore" (toJson (origin / "checkout").toString)
      |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (baseline / (if reuseAudit then "tools_research_PacketLedgerAudit.o" else "tools_research_SynapticBindingAudit.o")).toString)
      |>.setObjVal! "objectModules" (toJson (root / "objects.json").toString)
      |>.setObjVal! "force" (toJson (if mode == "product" then #["Main"] else (#[] : Array String)))
    IO.FS.writeFile (root / (mode ++ "-plan.json")) plan.pretty
    pure #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean",
      "-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",(root / (mode ++ "-plan.json")).toString]
  IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [("command",toJson command),
    ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
