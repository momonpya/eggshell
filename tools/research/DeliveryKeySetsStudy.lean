import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace DeliveryKeySetsStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := workspace/"docs/candidates/delivery-key-sets"
def source := base/"delivery-key-sets-source"
def build := base/"delivery-key-sets-build"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (cmd++": "++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains "controller/StudyMain guard ") "resource guard remains live"
def guard (tag : String) (args : Array String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve previous guard"
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def replaceOne (path : System.FilePath) (before after : String) : IO Unit := do
  let text ← IO.FS.readFile path
  check ((text.splitOn before).length == 2) ("unique source boundary missing: "++path.toString)
  IO.FS.writeFile path (text.replace before after)
partial def missingSources (origin target : System.FilePath) : IO Unit := do
  IO.FS.createDirAll target
  for entry in ← origin.readDir do
    if entry.fileName.startsWith "." then continue
    if ← entry.path.isDir then missingSources entry.path (target/entry.fileName)
    else if entry.fileName.endsWith ".lean" && !(← (target/entry.fileName).pathExists) then
      IO.FS.writeFile (target/entry.fileName) (← IO.FS.readFile entry.path)
def prepare : IO Unit := do
  drained
  check (!(← source.pathExists) && !(← build.pathExists) && !(← folder.pathExists)) "preserve previous candidate"
  let runtime := base/"selection-membership-build/StudyMain"
  check ((← hash runtime) == "ba74ebfcfcb3c19ef3ae15fcf135f468ad6d6c986863c59787854581d2ee976b") "current candidate changed"
  IO.FS.createDirAll folder
  discard <| command "/bin/cp" #["-cR",(base/"selection-membership-auditor-source").toString,source.toString]
  missingSources (base/"selection-membership-source") source
  replaceOne (source/"tools/research/DeliveryKeys.lean") "end Eggshell.Research.DeliveryKeys"
    ("/-- Preserve first occurrence and exact equality; hashes only select buckets. -/\n"++
    "def distinct (keys : List String) : List String := keys.eraseDups\n"++
    "@[noinline] def distinctCompiled (keys : List String) : List String := hashDistinct keys\n"++
    "@[csimp] theorem distinct_compiled : distinct = distinctCompiled := by\n"++
    "  funext keys\n  exact (HashDistinct.reference keys).symm\n\nend Eggshell.Research.DeliveryKeys")
  replaceOne (source/"Eggshell/Handoff.lean")
    "public import Eggshell.PluginModel" "public import Eggshell.PluginModel\npublic import tools.research.DeliveryKeys"
  replaceOne (source/"Eggshell/Handoff.lean")
    "let fittedKeys := fittedSlices.flatMap (·.keys) |>.eraseDups"
    "let fittedKeys := Research.DeliveryKeys.distinct (fittedSlices.flatMap (·.keys))"
  replaceOne (source/"Eggshell/Handoff.lean")
    "(fittedKeys ++ newlyCovered.map deliveryKey).eraseDups"
    "Research.DeliveryKeys.distinct (fittedKeys ++ newlyCovered.map deliveryKey)"
  IO.FS.writeFile (source/"tools/research/DeliveryKeySetsChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/DeliveryKeySetsChecks.lean"))
  replaceOne (source/"tools/research/ReplayReadinessChecks.lean")
    "import Eggshell.ContractAudit" "import Eggshell.ContractAudit\nimport tools.research.DeliveryKeySetsChecks"
  replaceOne (source/"tools/research/ReplayReadinessChecks.lean")
    "  | [\"parallel-encoder-check\",root] =>"
    ("  | [\"delivery-key-sets-check\",fixture,sha,output] =>\n"++
      "    Eggshell.Research.DeliveryKeySetsChecks.run (.mk fixture) sha (.mk output); return 0\n"++
      "  | [\"parallel-encoder-check\",root] =>")
  let parent ← read (base/"selection-membership-settings.json")
  let parents ← IO.ofExcept (parent.getObjValAs? (Array String) "parents")
  let settings := parent.setObjVal! "project" (toJson source.toString)
    |>.setObjVal! "core" (toJson source.toString)
    |>.setObjVal! "output" (toJson build.toString)
    |>.setObjVal! "baselineResponse" (toJson (base/"selection-membership-build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (base/"selection-membership-build/tools_research_ReplayReadinessChecks.o").toString)
    |>.setObjVal! "objectModules" (toJson (source/"object-mapping.json").toString)
    |>.setObjVal! "parents" (toJson (#[ (base/"selection-membership-build").toString,
      (base/"selection-membership-auditor-build").toString]++parents))
  write (base/"delivery-key-sets-settings.json") settings
  write (folder/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash runtime)),
    ("change",toJson "two quadratic ordered delivery-key distinct passes use proven hash membership"),
    ("preserved",toJson "all keys/order, body, candidates, model, inference slots, deadlines, budgets, certification, resource limits"),
    ("comparison",toJson "actual6554keys and doubled independent keys; AB,BA,AB; whole hooks before capacity"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "delivery-key-sets-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"delivery-key-sets-settings.json").toString]
  let fixture := base/"reply-ownership-ledger-fixture.json"
  guard "delivery-key-sets-comparison1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,
    "delivery-key-sets-check",fixture.toString,← hash fixture,(base/"delivery-key-sets-comparison.json").toString]
def collect (tag : String) : IO Unit := do
  drained
  let g ← read (base/(tag++".guard.json"))
  check (g.getObjValD "state" == toJson "finished" && g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "guard is not terminal"
  let log := fun suffix => do
    let path := base/(tag++suffix)
    if ← path.pathExists then return toJson (← IO.FS.readFile path)
    return Json.null
  write (folder/(tag++".json")) (Json.mkObj [("guard",g),("stdout",← log ".stdout"),("stderr",← log ".stderr")])
def sealBuild : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let run := fun args => do discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  if !(← (folder/"native-closure.json").pathExists) then
    run #["inspect",build.toString,(folder/"native-closure.json").toString]
  check ((← read (folder/"native-closure.json")).getObjValD "consistent" == toJson true) "native closure is inconsistent"
  run #["compare-sources",(base/"selection-membership-build").toString,build.toString,
    (folder/"native-sources.json").toString,"Eggshell.Handoff","tools.research.DeliveryKeys",
    "+tools.research.DeliveryKeySetsChecks"]
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected native source change"
  let nativeEntry ← IO.ofExcept ((← read (build/"tools_research_ReplayReadinessChecks.source")).getArr?)
  let entry ← IO.ofExcept (nativeEntry[0]!.getStr?)
  let before ← IO.FS.readFile (base/"selection-membership-source/tools/research/ReplayReadinessChecks.lean")
  let removed := entry.replace "\nimport tools.research.DeliveryKeySetsChecks" ""
    |>.replace ("  | [\"delivery-key-sets-check\",fixture,sha,output] =>\n"++
      "    Eggshell.Research.DeliveryKeySetsChecks.run (.mk fixture) sha (.mk output); return 0\n") ""
  check (removed == before && entry == (← IO.FS.readFile (source/"tools/research/ReplayReadinessChecks.lean")))
    "compiled entry changed beyond the explicit research-only command"
  write (folder/"entry-source.json") (Json.mkObj [("onlyResearchCommandAndImportAdded",toJson true),
    ("nativeSourceMatchesActualFile",toJson true),("parentSourceSha256",toJson (← hash (base/"selection-membership-source/tools/research/ReplayReadinessChecks.lean")))])
  for relative in ["Eggshell/Handoff.lean","tools/research/DeliveryKeys.lean","tools/research/ReplayReadinessChecks.lean"] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,
      "--label","b/"++relative,(base/"selection-membership-source"/relative).toString,(source/relative).toString]}
    check (patch.exitCode ≤ 1) "cannot record isolated patch"
    IO.FS.writeFile (folder/(relative.replace "/" "_"++".patch")) patch.stdout
  write (folder/"comparison.json") (← read (base/"delivery-key-sets-comparison.json"))
def prepareCells : IO Unit := do
  drained
  let comparison ← read (folder/"comparison.json")
  check (comparison.getObjValD "componentOnly" == toJson true) "component comparison required"
  let target := base/"delivery-key-sets-auditor-build"
  let settings := (← read (base/"delivery-key-sets-settings.json"))
    |>.setObjVal! "output" (toJson target.toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.RealDeliveryProbe")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  let settings := settings.setObjVal! "parents" (toJson (#[build.toString]++parents))
    |>.setObjVal! "baselineResponse" (toJson (build/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (build/"tools_research_ReplayReadinessChecks.o").toString)
  write (base/"delivery-key-sets-auditor-settings.json") settings
  guard "delivery-key-sets-auditor-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"delivery-key-sets-auditor-settings.json").toString]
def actualCells : IO Unit := do
  drained
  let target := base/"delivery-key-sets-auditor-build"
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let run := fun args => do discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  run #["inspect",target.toString,(folder/"auditor-closure.json").toString]
  run #["common-sources",build.toString,target.toString,(folder/"auditor-sources.json").toString]
  let proof ← read (folder/"auditor-sources.json")
  check (proof.getObjValD "allProductCorePresent" == toJson true &&
    proof.getObjValD "commonSourcesUnchanged" == toJson true) "auditor changed the product core"
  let runtime := build/"StudyMain"
  let digest ← hash runtime
  let installation := base/"delivery-key-sets-prefix"
  let manifest := base/"delivery-key-sets-install.json"
  write manifest (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson runtime.toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  guard "delivery-key-sets-install1" #[(target/"StudyMain").toString,"install-prefix",manifest.toString]
  let original ← read (base/"selection-membership-cells.json")
  let probes ← IO.ofExcept (original.getObjValAs? (Array Json) "probes")
  let output := base/"delivery-key-sets-cells-result"
  let probes ← probes.mapM fun probe => do
    let old ← IO.ofExcept (probe.getObjValAs? String "destination")
    let cell := (System.FilePath.mk old).fileName.get!
    return probe.setObjVal! "destination" (toJson (output/cell).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  let input := base/"delivery-key-sets-cells.json"
  write input (Json.mkObj [("output",toJson output.toString),("probes",toJson probes)])
  guard "delivery-key-sets-cells1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,"cells",input.toString]
def retireSuperseded : IO Unit := do
  drained
  let record := folder/"retired-superseded.json"
  check (!(← record.pathExists)) "preserve retirement evidence"
  let processes ← command "/bin/ps" #["-axo","command="]
  let planned := [("local-completion-build/StudyMain","ba2d1d30ec3ec83945c1dcb9c072534f6e29d101106aa137f971dd05a84442d6"),
    ("local-completion-prefix/libexec/eggshell","ba2d1d30ec3ec83945c1dcb9c072534f6e29d101106aa137f971dd05a84442d6"),
    ("shared-model-build/StudyMain","ffb25590c28bc01b4f0baf46122ab26635763a125fa59dc0e1a8ace712ff9778")]
  let mut removed : Array Json := #[]
  for (name,expected) in planned do
    let path := base/name
    check (!processes.contains path.toString && (← hash path) == expected) "retired executable changed or remains live"
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson expected),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  for item in removed do IO.FS.removeFile (.mk (← IO.ofExcept (item.getObjValAs? String "path")))
  write record (Json.mkObj [("removed",toJson removed),("originalDbProjectCacheModelsAndAdoptionBaselineRetained",toJson true),
    ("currentParentAndCandidateRetained",toJson true),("sourceObjectInterfaceDependencyWitnessesRetained",toJson true),
    ("archived",toJson false)])
def retireEnded : IO Unit := do
  drained
  let result ← read (folder/"delivery-cells.json")
  check (result.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    result.getObjValD "allParentBodiesByteEqual" == toJson true &&
    (← (folder/"delivery-cleanup.json").pathExists)) "retain actual delivery and clean sessions first"
  let record := folder/"retired-ended-experiments.json"
  check (!(← record.pathExists)) "preserve ended experiment cleanup"
  let path := base/"delivery-key-sets-auditor-build/StudyMain"
  let expected := (← read (folder/"auditor-sources.json")).getObjValD "auditorSha256"
  let processes ← command "/bin/ps" #["-axo","command="]
  let digest ← hash path
  check (!processes.contains path.toString && expected == toJson digest) "auditor still live or changed"
  let bytes := (← path.metadata).byteSize.toNat
  let mut removed := #[path.toString]
  for tag in ["delivery-key-sets-build1","delivery-key-sets-build2","delivery-key-sets-comparison1",
      "delivery-key-sets-auditor-build1","delivery-key-sets-install1","delivery-key-sets-cells1"] do
    let saved ← read (folder/(tag++".json"))
    check ((saved.getObjValD "guard").getObjValD "state" == toJson "finished" &&
      (saved.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat)) "ended guard not retained"
    for suffix in [".stdout",".stderr"] do
      let raw := base/(tag++suffix)
      if ← raw.pathExists then removed := removed.push raw.toString
  for file in removed do IO.FS.removeFile (.mk file)
  write record (Json.mkObj [("removed",toJson removed),("retiredAuditorSha256",toJson digest),
    ("retiredAuditorBytes",toJson bytes),("sourceObjectInterfaceDependencyWitnessesRetained",toJson true),
    ("currentCandidateParentDbProjectCacheModelsAndActualBodiesRetained",toJson true),("archived",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["retry-build",tag] =>
    drained
    check (tag.startsWith "delivery-key-sets-build") "build guard escaped candidate"
    guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"delivery-key-sets-settings.json").toString]
  | ["collect",tag] => collect tag
  | ["seal"] => sealBuild
  | ["prepare-cells"] => prepareCells
  | ["actual-cells"] => actualCells
  | ["retire-superseded"] => retireSuperseded
  | ["retire-ended"] => retireEnded
  | _ => throw (IO.userError "prepare | collect TAG | seal")
end DeliveryKeySetsStudy
def main := DeliveryKeySetsStudy.main
