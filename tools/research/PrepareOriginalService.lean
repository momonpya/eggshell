import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

/-- Isolated original-evidence experiments reuse the one prepared source
checkpoint; no answering model, new seed, or full warm is launched here. -/
def main (args : List String) : IO Unit := do
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let measured := args.head? == some "measured"
  let causal := args.head? == some "cause"
  let filtered := args.head? == some "filtered"
  let ranged := args.head? == some "ranged"
  let structural := args.head? == some "structure"
  let args := if structural || measured || causal || filtered || ranged then args.tail else args
  let parent := base / (if ranged then "filtered-postings-20261027" else
    if measured || causal || filtered then "shared-original-structure-20261027" else
    if structural then "prepared-original-service-20261027" else "joint-range-bindings-20261027")
  let root := base / (if ranged then "range-postings-20261027" else
    if filtered then "filtered-postings-20261027" else
    if causal then "evidence-cause-contract-20261027" else
    if measured then "rendered-marginal-cost-20261027" else
    if structural then "shared-original-structure-20261027" else "prepared-original-service-20261027")
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  if args == ["fork"] then
    unless !(← root.pathExists) do throw (IO.userError "preserve existing original-service candidate")
    IO.FS.createDir root
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",
      (parent / "checkout").toString,(root / "checkout").toString]}
    unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
    if ranged then
      let path := root / "checkout/Eggshell/Handoff.lean"
      let text ← IO.FS.readFile path
      if (← path.symlinkMetadata).type == .symlink then IO.FS.removeFile path
      IO.FS.writeFile path text
      return
    if filtered then
      let path := root / "checkout/tools/OwnerUnitPostings.lean"
      let text ← IO.FS.readFile path
      if (← path.symlinkMetadata).type == .symlink then IO.FS.removeFile path
      IO.FS.writeFile path text
      return
    for file in ["SynapseTransport.lean","Handoff.lean","ObservedRecordView.lean","SynapseBuild.lean",
        "SynapseIndex.lean","PublicationClient.lean","PublicationService.lean","CanonicalSourcePrepared.lean"] ++
        (if causal then ["SynapseBundles.lean","SynapseRecommend.lean"] else []) do
      let path := root / "checkout/Eggshell" / file
      let text ← IO.FS.readFile path
      if (← path.symlinkMetadata).type == .symlink then IO.FS.removeFile path
      IO.FS.writeFile path text
    return
  let [mode,label] := args | throw (IO.userError "fork | MODE LABEL")
  unless ["product","hook","audit","run-audit","run-hook","run-worker","contract","interfaces","run-interface-hook"].contains mode && !label.isEmpty &&
      label.toList.all (fun c => c.isAlphanum || c == '-') && (mode != "contract" || causal || filtered || ranged) &&
      (!["interfaces","run-interface-hook"].contains mode || ranged) do
    throw (IO.userError "known mode/simple label required")
  let command ← if mode == "interfaces" then
    pure (#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-j1","-M1024","--run",
      project ++ "/tools/research/StudyHookInterfaces.lean"] ++
        (if ← (root / "driver-interfaces").pathExists then #["resume"] else #[]))
  else if mode == "run-interface-hook" then
    pure #["/usr/bin/env","LEAN_PATH=" ++ (root / "driver-interfaces/lib").toString,"LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (root / label / "data").toString,
      toolchain ++ "/bin/lean","--root=" ++ project,"-j1","-M2048","--run",
      project ++ "/tools/research/OnePreparedHook.lean",root.toString,(root / label).toString,
      (base / "packet-delivery-ledger-20261027/one-prepared-hook").toString]
  else if mode == "contract" then
    let library := if ranged then root / "product-build/lib" else parent / "product-build/lib"
    pure #["/usr/bin/env","LEAN_PATH=" ++ library.toString,"LEAN_NUM_THREADS=1",
      toolchain ++ "/bin/lean","--root=" ++ (root / "checkout").toString,"-j1","-M1536",
      (root / "checkout" / (if ranged then "tools/PointBuckets.lean" else
        if filtered then "tools/OwnerUnitPostings.lean" else "Eggshell/SynapticCause.lean")).toString]
  else if mode == "run-audit" then
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(root / "audit-build/StudyMain").toString,(root / label).toString]
  else if mode == "run-hook" || mode == "run-worker" then
    pure (#["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (root / label / "data").toString,
      (root / "hook-build/StudyMain").toString,root.toString,(root / label).toString,
      (base / "packet-delivery-ledger-20261027/one-prepared-hook").toString] ++
        (if mode == "run-worker" then #["worker"] else #[]))
  else do
    let own := mode != "product" || (ranged && (← (root / "product-build/build.json").pathExists))
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
      |>.setObjVal! "mainModule" (toJson (if mode == "audit" then
        if ranged then "tools.research.RangePostingsChecks" else
          if filtered then "tools.research.FilteredPostingsChecks" else
          if causal then "tools.research.CauseContractChecks" else
          if measured then "tools.research.MeasuredCoverageChecks" else "tools.research.OriginalStructureAudit"
        else if own then "tools.research.OnePreparedHook" else "Main"))
      |>.setObjVal! "baselineCore" (toJson ((if ranged then parent else origin) / "checkout").toString)
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
