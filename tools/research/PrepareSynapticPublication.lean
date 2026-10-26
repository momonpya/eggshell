import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def block (source first last : String) : IO String := do
  let [_,tail] := source.splitOn first | throw (IO.userError s!"unique start required: {first}")
  let [middle,_] := tail.splitOn last | throw (IO.userError s!"unique end required: {last}")
  return first ++ middle

private def replace (source before after : String) : IO String := do
  let [first,last] := source.splitOn before | throw (IO.userError s!"unique replacement required: {before.take 80}")
  return first ++ after ++ last

def main (args : List String) : IO Unit := do
  let receipt := args.head? == some "receipt"
  let args := if receipt then args.tail else args
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / (if receipt then "receipt-row-postings-20261027" else "synaptic-publication-delta-20261027")
  let parent := base / (if receipt then "synaptic-publication-delta-20261027" else "captured-correspondence-20261026")
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  if receipt && args == ["reference"] then
    let source ← IO.FS.readFile (parent / "checkout/Eggshell/SynapseUsage.lean")
    let body ← block source "def sharedPresented" "/-- Verify actual packet bytes"
    let reference := "import Eggshell.SynapseUsage\nopen Lean Eggshell.Synapses Eggshell.Synapses.Extraction\nnamespace Eggshell.Research.ReceiptBefore\n" ++
      body ++ "end Eggshell.Research.ReceiptBefore\n"
    IO.FS.writeFile (System.FilePath.mk project / "tools/research/ReceiptBefore.lean") reference
    return
  if args == ["fork"] then
    unless !(← root.pathExists) do throw (IO.userError "keep prior isolated topology trial")
    IO.FS.createDir root
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(parent / "checkout").toString,(root / "checkout").toString]}
    unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
    if receipt then return
    let core := root / "checkout/Eggshell"
    let index ← IO.FS.readFile (core / "SynapseIndex.lean")
    let recommend ← IO.FS.readFile (core / "SynapseRecommend.lean")
    let routing ← IO.FS.readFile (core / "SynapticRouting.lean")
    let store ← IO.FS.readFile (core / "SynapticRoutingStore.lean")
    let scope ← block index "inductive Scope where" "/-- The implementation key"
    let keys ← block index "inductive Key where" "def factName"
    let codec ← block index "def payloadLimit" "def manifest?"
    let bytes ← block index "def checkedBytes" "def putImmutable"
    let target ← block recommend "/-- Output identity is native occurrence identity." "structure Offer where"
    let step ← block routing "/-- One step in the existing advisory relation." "/-- The serialized digest"
    let topology := "module\npublic import Eggshell.GraphStore\npublic import Eggshell.SynapseSource\n@[expose] public section\nnamespace Eggshell.Synapses\nopen Lean DB\nnamespace Index\n" ++
      scope ++ keys ++ codec ++ bytes ++ "end Index\nnamespace Recommend\n" ++ target ++
      "deriving instance FromJson for Target\nend Recommend\nnamespace Routing\nopen Recommend\n" ++ step ++
      "end Routing\nend Eggshell.Synapses\n"
    IO.FS.writeFile (core / "SynapticTopology.lean") topology
    let index ← replace index scope ""
    let index ← replace index keys ""
    let index ← replace index codec ""
    let index ← replace index bytes ""
    IO.FS.writeFile (core / "SynapseIndex.lean") index
    IO.FS.writeFile (core / "SynapseRecommend.lean") (← replace recommend target "")
    IO.FS.writeFile (core / "SynapticRouting.lean") (← replace routing step "")
    let declarations ← block store "/-- This is an advisory projection" "structure Reader where"
    let declarations ← replace declarations (← block declarations "structure Manifest where" "def arcPrefix") ""
    let implementation := "def implementation : String := Blake3.hex (Blake3.digest \"eggshell.synaptic-topology\".toUTF8 [\n  (include_str \"SynapticTopology.lean\").toUTF8,(include_str \"SynapticTopologyStore.lean\").toUTF8])\n\n"
    IO.FS.writeFile (core / "SynapticTopologyStore.lean") ("module\npublic import Eggshell.SynapticTopology\n@[expose] public section\nnamespace Eggshell.Synapses.Routing.Store\nopen Lean DB Recommend\n" ++ implementation ++ declarations ++ "end Eggshell.Synapses.Routing.Store\n")
    let manifest ← block store "structure Manifest where" "def arcPrefix"
    let reader ← block store "structure Reader where" "def open?"
    let scan ← block store "structure Scan where" "end Eggshell.Synapses.Routing.Store"
    IO.FS.writeFile (core / "SynapticRoutingStore.lean") ("module\npublic import Eggshell.SynapticRouting\npublic import Eggshell.SynapticTopologyStore\n@[expose] public section\nnamespace Eggshell.Synapses.Routing.Store\nopen Lean DB Recommend\n" ++ manifest ++ reader ++ "\n" ++ scan ++ "end Eggshell.Synapses.Routing.Store\n")
    return
  let [mode,label] := args | throw (IO.userError "PrepareSynapticPublication fork | product|audit|hooks|run-audit|run-hooks LABEL")
  unless ["product","audit","hooks","contract","checkpoint","source","profile","receipt-audit","run-audit","run-hooks","run-checkpoint","run-source","run-profile","run-receipt-audit"].contains mode && !label.isEmpty &&
      label.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "known mode and simple label required")
  if mode.startsWith "run-" then
    let output := if mode == "run-profile" then root / "fixed-source-hooks" else root / label
    let hooks := mode == "run-hooks"
    let source := mode == "run-source"
    let command := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++
      (if hooks then output / "native/data" else output / "data").toString,
      (root / (if hooks then "hooks-build/StudyMain"
        else if mode == "run-receipt-audit" then "receipt-audit-build/StudyMain"
        else if mode == "run-profile" then "profile-build/StudyMain"
        else if source then "source-build/StudyMain"
        else if mode == "run-checkpoint" then "checkpoint-build/StudyMain" else "audit-build/StudyMain")).toString] ++
      (if hooks then #[root.toString,output.toString,"routing"]
        else if source then #[root.toString,output.toString] else #[output.toString])
    IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
      ("command",toJson command),("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString]),
      ("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
    return
  let parent := if mode == "product" then parent else root
  let baseline ← read (parent / "product-build/build.json")
  let mut objects ← IO.ofExcept ((← read (parent / "objects.json")).getObj?)
  for row in ← IO.ofExcept ((baseline.getObjValD "modules").getArr?) do
    objects := objects.insert (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  IO.FS.writeFile (root / "objects.json") (Json.obj objects).pretty
  let plan := baseline.getObjValD "settings"
    |>.setObjVal! "core" (toJson (root / "checkout").toString)
    |>.setObjVal! "output" (toJson (root / (mode ++ "-build")).toString)
    |>.setObjVal! "mainModule" (toJson (if mode == "product" then "Main"
      else if mode == "hooks" then "tools.research.CapturedHookAudit"
      else if mode == "contract" then "tools.research.SynapticPublicationContractMain"
      else if mode == "checkpoint" then "tools.research.SynapticCheckpointAudit"
      else if mode == "source" then "tools.research.SynapticSourceHookAudit"
      else if mode == "profile" then "tools.research.ProfileSynapticSource"
      else if mode == "receipt-audit" then "tools.research.ReceiptPostingsAudit"
      else "tools.research.SynapticPublicationAudit"))
    |>.setObjVal! "force" (toJson (if mode == "contract" then #["Eggshell.ContractAudit"] else (#[] : Array String)))
    |>.setObjVal! "objectModules" (toJson (root / "objects.json").toString)
    |>.setObjVal! "baselineResponse" (toJson (parent / "product-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "product-build/Main.o").toString)
    |>.setObjVal! "baselineCore" (toJson (parent / "checkout").toString)
  IO.FS.writeFile (root / (mode ++ "-plan.json")) plan.pretty
  let library := root / "checkout/.lake/build/lib/lean"
  IO.FS.removeFile library
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "product-build/lib").toString,library.toString]}
  unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
    ("command",toJson #["/usr/bin/env","LEAN_PATH=" ++ toolchain ++ "/lib/lean","LEAN_NUM_THREADS=1",
      toolchain ++ "/bin/lean","-j1","-M1536","--run",project ++ "/tools/research/StudyBuildMain.lean",
      (root / (mode ++ "-plan.json")).toString]),
    ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
