import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main (args : List String) : IO Unit := do
  let (mode,label,topic) ← match args with
    | [mode,label] => pure (mode,label,none)
    | [mode,label,"topic",number] => pure (mode,label,some number)
    | _ => throw (IO.userError "MODE LABEL [topic NUMBER]")
  unless topic.isNone || (mode == "run-hook" && topic.any (["1","2","3"].contains ·)) do
    throw (IO.userError "explicit study topic applies only to a native hook")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / "verified-winner-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  unless ["product","audit","controller","study","signal","batch","transport","usage","close","storage","run-audit","run-hook","profile"].contains mode && !label.isEmpty &&
      label.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "known mode/simple label required")
  let command ← if mode == "run-audit" then
    pure #[(root / "audit-build/StudyMain").toString,(root / "selector-input.json").toString,(root / label).toString]
  else if mode == "profile" then
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-j1","-M1024","--run",
      project ++ "/tools/research/ProfileCueHook.lean",root.toString,(root / label).toString,
      (base / "packet-delivery-ledger-20261027/one-prepared-hook").toString,"0"]
  else if mode == "run-hook" then
    pure (#["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++ (root / label / "data").toString,
      (root / "controller-build/StudyMain").toString,root.toString,(root / label).toString,
      (base / "packet-delivery-ledger-20261027/one-prepared-hook").toString] ++
        (topic.toArray.flatMap fun number => #["topic",number]))
  else do
    let origin := root
    let baseline := origin / "product-build"
    let library := root / "checkout/.lake/build/lib/lean"
    unless (← library.symlinkMetadata).type == .symlink do throw (IO.userError "expected current native library link")
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
      |>.setObjVal! "mainModule" (toJson (if mode == "product" then "Main" else
        if mode == "study" then "tools.research.StudyMain" else
        if mode == "transport" then "tools.research.StudyTransportFixture" else
        if mode == "usage" then "tools.research.StudyUsageEvidence" else
        if mode == "close" then "tools.research.StudyClosePrepared" else
        if mode == "storage" then "tools.research.StorageReplay" else
        if mode == "audit" then "tools.research.VerifiedWinnerAudit" else
        if mode == "batch" then "tools.research.BatchedBindingsAudit" else
        if mode == "signal" then "tools.research.EvidenceSignalJoin" else "tools.research.OnePreparedHook"))
      |>.setObjVal! "baselineCore" (toJson (origin / "checkout").toString)
      |>.setObjVal! "baselineResponse" (toJson (baseline / "runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (baseline / "Main.o").toString)
      |>.setObjVal! "objectModules" (toJson (root / "objects.json").toString)
      |>.setObjVal! "force" (toJson (#[] : Array String))
    IO.FS.writeFile (root / (mode ++ "-plan.json")) plan.pretty
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-j1","-M1536","--run",
      project ++ "/tools/research/StudyBuildMain.lean",(root / (mode ++ "-plan.json")).toString]
  IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
    ("command",toJson command),("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString]),
    ("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
