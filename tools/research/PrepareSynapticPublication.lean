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
  let prepared := args.head? == some "prepared"
  let payload := args.head? == some "payload"
  let fold := args.head? == some "fold"
  let leaf := args.head? == some "leaf"
  let sparse := args.head? == some "sparse"
  let dispatch := args.head? == some "dispatch"
  let streaming := args.head? == some "streaming"
  let observing := args.head? == some "observing"
  let tournament := args.head? == some "tournament"
  let span := args.head? == some "span"
  let receipt := args.head? == some "receipt"
  let args := if receipt || prepared || payload || fold || leaf || sparse || dispatch || streaming || observing || tournament || span then args.tail else args
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let root := base / (if span then "bound-span-preparation-20261027" else if tournament then "tournament-selection-20261027" else if observing then "selector-observation-20261027" else if streaming then "streamed-incidence-20261027" else if dispatch then "incremental-dispatch-20261027" else if sparse then "incremental-selection-20261027" else if leaf then "bounded-leaf-encoding-20261027" else if fold then "selector-weight-fold-20261027" else if payload then "nonempty-source-payload-20261027" else if prepared then "receipt-preparation-20261027" else if receipt then "receipt-row-postings-20261027" else "synaptic-publication-delta-20261027")
  let parent := base / (if span || tournament || observing then "streamed-incidence-20261027" else if streaming then "incremental-dispatch-20261027" else if dispatch then "incremental-selection-20261027" else if sparse then "bounded-leaf-encoding-20261027" else if leaf then "selector-weight-fold-20261027" else if fold then "nonempty-source-payload-20261027" else if payload then "receipt-preparation-20261027" else if prepared then "receipt-row-postings-20261027" else if receipt then "synaptic-publication-delta-20261027" else "captured-correspondence-20261026")
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  if prepared && args == ["reference"] then
    let source ← IO.FS.readFile (parent / "checkout/Eggshell/SynapseTransport.lean")
    let body ← block source "def Plan.receipt" "end Eggshell.Synapses.Transport"
    let body ← replace body "def Plan.receipt" "def receipt"
    let bundleSource ← IO.FS.readFile (parent / "checkout/Eggshell/SynapseBundles.lean")
    let bundle ← block bundleSource "def receipt" "end Eggshell.Synapses.Bundles"
    let bundle ← replace bundle "def receipt" "def bundles"
    let bundle ← replace bundle "plan.receipt text" "receipt plan text"
    IO.FS.writeFile (System.FilePath.mk project / "tools/research/ReceiptPlanBefore.lean")
      ("import Eggshell.SynapseBundles\nopen Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Transport Eggshell.Synapses.Bundles\nnamespace Eggshell.Research.ReceiptPlanBefore\n" ++ body ++ bundle ++ "end Eggshell.Research.ReceiptPlanBefore\n")
    return
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
    if receipt || prepared || payload || fold || leaf || sparse || dispatch || streaming || observing || tournament || span then return
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
  let (mode,label,runLabel) ← match args with
    | [mode,label] => pure (mode,label,label)
    | [mode,label,runLabel] =>
      unless ["run-audit","run-source","run-resume-source","run-hooks","run-checkpoint",
          "run-profile","run-receipt-audit"].contains mode && !runLabel.isEmpty &&
          runLabel.toList.all (fun c => c.isAlphanum || c == '-') do
        throw (IO.userError "a distinct run-record label requires a run mode")
      pure (mode,label,runLabel)
    | _ => throw (IO.userError "PrepareSynapticPublication MODE OUTPUT-LABEL [RUN-RECORD-LABEL]")
  if mode == "run-worker-audit" || mode == "run-worker-replay" then
    IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
      ("command",toJson (#["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT=" ++ (root / "worker-probe/data").toString,
        (root / "worker-audit-build/StudyMain").toString] ++
        (if mode == "run-worker-replay" then #["replay"] else #[]) ++
        #[(root / "worker-probe").toString,(root / label).toString])),
      ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
    return
  if mode == "run-canonical" then
    IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
      ("command",toJson #[(root / "canonical-build/StudyMain").toString]),("cwd",toJson project),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
    return
  if mode == "run-missing" || mode == "run-worker-missing" then
    let inputs := if mode == "run-worker-missing" then
      #["worker",(root / "worker-probe").toString,(root / "receipt-probe").toString]
      else #[(root / "fixed-source-hooks").toString]
    IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
      ("command",toJson (#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-j1","-M1536","--run",
        project ++ "/tools/research/ExplainMissingNative.lean"] ++ inputs ++
        #[(root / "explain-build/StudyMain").toString,(root / label).toString])),
      ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
    return
  if mode == "warm-profile" then
    let trial := root / "fixed-source-hooks"
    IO.FS.writeFile (root / (label ++ "-settings.json")) (Json.mkObj [
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_PREFIX=" ++ (trial / "prefix").toString,
        "EGGSHELL_DATA_ROOT=" ++ (trial / "data").toString,
        "EGGSHELL_CONFIG=" ++ (trial / "config.toml").toString,
        "EGGSHELL_PROFILE=work","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1",
        "HF_HUB_OFFLINE=1","TOKENIZERS_PARALLELISM=false",
        (trial / "prefix/libexec/eggshell").toString,"egg","warm","work"]),
      ("cwd",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / (label ++ ".guard.json")).toString)]).pretty
    return
  unless ["product","audit","hooks","contract","canonical","checkpoint","source","profile","explain","receipt-audit","worker-audit","run-audit","run-hooks","run-checkpoint","run-source","run-resume-source","run-profile","run-receipt-audit"].contains mode && !label.isEmpty &&
      label.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "known mode and simple label required")
  if mode.startsWith "run-" then
    let resume := mode == "run-resume-source"
    let output := if mode == "run-profile" || resume then root / "fixed-source-hooks" else root / label
    let hooks := mode == "run-hooks"
    let source := mode == "run-source" || resume
    if (dispatch || streaming || observing || tournament || span) && source then
      let checked ← IO.Process.output {cmd := toolchain ++ "/bin/lean",args := #["--run",
        project ++ "/tools/research/NativeSelectorDispatch.lean",root.toString] ++
          (if tournament then #["tournament"] else #[])}
      unless checked.exitCode == 0 do throw (IO.userError (checked.stdout ++ checked.stderr))
    let command := #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_DATA_ROOT=" ++
      (if hooks then output / "native/data" else output / "data").toString,
      (root / (if hooks then "hooks-build/StudyMain"
        else if mode == "run-receipt-audit" then "receipt-audit-build/StudyMain"
        else if mode == "run-profile" then "profile-build/StudyMain"
        else if source then "source-build/StudyMain"
        else if mode == "run-checkpoint" then "checkpoint-build/StudyMain" else "audit-build/StudyMain")).toString] ++
      (if hooks then #[root.toString,output.toString,"routing"]
        else if source then #[root.toString,output.toString] ++ (if observing then #["worker"] else if resume then #["resume"] else if span then #["topic","2"] else #[]) else #[output.toString])
    IO.FS.writeFile (root / (runLabel ++ "-settings.json")) (Json.mkObj [
      ("command",toJson command),("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString]),
      ("record",toJson (root / (runLabel ++ ".guard.json")).toString)]).pretty
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
      else if mode == "contract" then if prepared then "tools.research.ReceiptPreparationContractMain" else "tools.research.SynapticPublicationContractMain"
      else if mode == "canonical" then "tests.CanonicalHookTests"
      else if mode == "checkpoint" then "tools.research.SynapticCheckpointAudit"
      else if mode == "source" then "tools.research.SynapticSourceHookAudit"
      else if mode == "profile" then "tools.research.ProfileSynapticSource"
      else if mode == "explain" then "tools.research.DeliveryExplain"
      else if mode == "worker-audit" then "tools.research.WorkerEvidenceAudit"
      else if mode == "receipt-audit" then if prepared then "tools.research.ReceiptPreparationAudit" else "tools.research.ReceiptPostingsAudit"
      else if span then "tools.research.BoundSpanAudit"
      else if tournament then "tools.research.TournamentSelectionAudit"
      else if sparse || dispatch || streaming then "tools.research.IncrementalSelectionAudit" else if leaf then "tools.research.PageEncodingAudit" else if fold then "tools.research.SelectorFoldAudit" else if payload then "tools.research.NonemptySourcePayloadAudit" else "tools.research.SynapticPublicationAudit"))
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
