import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashSet
import Std.Data.HashMap
open Lean
namespace Eggshell.Research.RealSourceStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def runtime := base/"search-read-build"
def source := base/"real-source-search-read-auditor-source"
def target := base/"real-source-search-read-auditor-build"
def installation := base/"real-source-search-read-prefix"
def root := base/"real-source-search-read-trial-result"
def study := workspace/"docs/candidates/real-source-search-read"
def inputFile := base/"real-source-search-read-input.json"
def installFile := base/"real-source-search-read-install.json"
def buildFile := base/"real-source-search-read-auditor-settings.json"
def diagnosticSource := base/"real-source-reply-footprint-source"
def diagnosticTarget := base/"real-source-reply-footprint-build"
def diagnosticSettings := base/"real-source-reply-footprint-settings.json"
def diagnosticAuditorSource := base/"real-source-reply-footprint-auditor-source"
def diagnosticAuditor := base/"real-source-reply-footprint-auditor-build"
def diagnosticAuditorSettings := base/"real-source-reply-footprint-auditor-settings.json"
def diagnosticInstallation := base/"real-source-reply-footprint-prefix"
def diagnosticInstall := base/"real-source-reply-footprint-install.json"
def diagnosticProbe := base/"real-source-reply-footprint-probe.json"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let all ← command "/bin/ps" #["-axo","command="]
  check (!(all.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native resource guard active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "real-source-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "real-source guard not drained"
partial def ensureResearch (folder : System.FilePath) (name : String) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if !name.startsWith "tools.research." || (← seen.get).contains name then return
  seen.modify (·.insert name)
  let relative := name.replace "." "/"++".lean"
  let destination := folder/relative
  if !(← destination.pathExists) then
    let original := workspace/relative
    check (← original.pathExists) ("missing research source: "++name)
    IO.FS.createDirAll destination.parent.get!
    IO.FS.writeFile destination (← IO.FS.readFile original)
  for row in (← IO.FS.readFile destination).splitOn "\n" do
    let row := row.trimAscii.toString
    let marker := if row.startsWith "public import " then "public import " else "import "
    if !row.startsWith marker then continue
    let names := (row.drop marker.length).toString.splitOn " " |>.filter (!·.isEmpty)
    if let some dependency := (if names.head? == some "all" then names.drop 1 else names).head? then
      ensureResearch folder dependency seen
def prepare : IO Unit := do
  drained
  let runtimeRecord ← read (workspace/"docs/candidates/search-read/runtime.json")
  check ((← hash (runtime/"StudyMain")) == (← IO.ofExcept (runtimeRecord.getObjValAs? String "sha256")) &&
    (← read (workspace/"docs/candidates/search-read/native-closure.json")).getObjValD "consistent" == toJson true &&
    (← read (workspace/"docs/candidates/search-read/native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true &&
    (← read (workspace/"docs/candidates/search-read/controls.json")).getObjValD "nativeExchanges" == toJson (240 : Nat))
    "frozen coherent runtime and completed native protocol controls required"
  check (!(← source.pathExists) && !(← root.pathExists) && !(← installation.pathExists))
    "fresh isolated real-source paths required"
  IO.FS.createDirAll study
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",runtime.toString,
    source.toString,target.toString,"tools.research.RealDeliveryProbe",buildFile.toString]
  ensureResearch source "tools.research.RealDeliveryProbe" (← IO.mkRef {})
  let old ← read (base/"record-boundary-hook-input.json")
  check (old.getObjValD "handoffChars" == toJson (500000 : Nat) && old.getObjValD "repetitions" == toJson (2 : Nat))
    "do not change the existing real-source envelope"
  let runtimeHash ← hash (runtime/"StudyMain")
  write installFile (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (runtime/"StudyMain").toString),("sha256",toJson runtimeHash)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let previous ← IO.ofExcept (old.getObjValAs? (Array (String × Option String)) "environment")
  let updated := previous.filter (fun row => !["CODEX_HOME","TMPDIR","EGGSHELL_PREFIX","PLUGIN_ROOT","EGGSHELL_DATA_ROOT"].contains row.1) ++
    #[("CODEX_HOME",some (base/"real-source-search-read-empty-account").toString),("EGGSHELL_PREFIX",some installation.toString),
      ("PLUGIN_ROOT",some (installation/"share/eggshell/codex-plugin").toString)]
  let input := Json.mkObj [
    ("runtime",Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson runtimeHash)]),
    ("source",old.getObjValD "source"),("workspace",old.getObjValD "workspace"),("output",toJson root.toString),
    ("pluginRoot",toJson (installation/"share/eggshell/codex-plugin").toString),("environment",toJson updated),
    ("handoffChars",old.getObjValD "handoffChars"),("repetitions",old.getObjValD "repetitions"),("topics",old.getObjValD "topics")]
  write inputFile input
  write (study/"plan.json") (Json.mkObj [("runtimeSha256",toJson runtimeHash),
    ("protectedSource",old.getObjValD "source"),("topics",toJson #[1,2,3]),
    ("sameQuestionsReferencesSnapshotAnd500000CharacterEnvelope",toJson true),
    ("independentNewChatsPerTopic",toJson (2 : Nat)),("notTwoModelHistoryCycles",toJson true),
    ("expectedAvailableCounts",toJson #[4,7,5]),("freezeBeforeHookBytes",toJson true),
    ("failFastOnFirstDeliveryMiss",toJson true),("sourceOnlyCopies",toJson true),
    ("noAnsweringModelCalls",toJson true),("adopted",toJson false),("paidComparisons",toJson "0/18")])
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh guard required"
  let args ← match action with
    | "footprint-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,diagnosticSettings.toString]
    | "footprint-helper-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,diagnosticAuditorSettings.toString]
    | "footprint-install" => pure #[(diagnosticAuditor/"StudyMain").toString,"install-prefix",diagnosticInstall.toString]
    | "footprint-probe" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(diagnosticAuditor/"StudyMain").toString,
      "probe",diagnosticProbe.toString]
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,buildFile.toString]
    | "install" => pure #[(target/"StudyMain").toString,"install-prefix",installFile.toString]
    | "freeze" | "run" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
      action,inputFile.toString]
    | _ => throw (IO.userError "unknown real-source action")
  if action == "run" then
    check ((← read (study/"frozen.json")).getObjValD "sameCompleteDenominators" == toJson true)
      "verify all frozen obligations before a candidate hook"
    check ((← read (study/"auditor-sources.json")).getObjValD "commonSourcesUnchanged" == toJson true &&
      (← read (study/"auditor-closure.json")).getObjValD "consistent" == toJson true)
      "auditor must decode using the current native product types"
  if action == "footprint-probe" then
    let types ← read (study/"footprint-auditor-sources.json")
    check (types.getObjValD "commonSourcesUnchanged" == toJson true &&
      types.getObjValD "productSha256" == toJson (← hash (diagnosticTarget/"StudyMain")) &&
      types.getObjValD "auditorSha256" == toJson (← hash (diagnosticAuditor/"StudyMain")))
      "diagnostic product and auditor must share their complete native source inputs"
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def sealSource : IO Unit := do
  drained
  let previous ← read (workspace/"docs/candidates/record-boundary/frozen.json")
  let expected ← IO.ofExcept (previous.getObjValAs? (Array Json) "topics")
  let sealed ← read (root/"sealed.json")
  check (sealed.getObjValD "sourceFiles" == (previous.getObjValD "sealed").getObjValD "sourceFiles")
    "do not compare another seed or source publication"
  let mut topics := #[]
  for topic in expected do
    let id ← IO.ofExcept (topic.getObjValAs? Nat "topic")
    let actual ← read (root/s!"topic-{id}-frozen.json")
    check (actual == topic.getObjValD "frozen") "frozen DB-backed obligations changed"
    topics := topics.push (Json.mkObj [("topic",toJson id),("frozen",actual)])
  write (study/"frozen.json") (Json.mkObj [("sealed",sealed),("topics",toJson topics),
    ("sameCompleteDenominators",toJson true),("bodyReads",toJson (0 : Nat))])
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"auditor-closure.json").toString]
def witnesses (directory : System.FilePath) : IO (Std.HashMap String Json) := do
  let config ← read (directory/"build.json")
  let mut mapping ← read (directory/"object-mapping.json")
  for row in ← IO.ofExcept (config.getObjValAs? (Array Json) "modules") do
    mapping := mapping.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  let mut result : Std.HashMap String Json := {}
  for line in (← IO.FS.readFile (directory/"runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let object ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let witness := (System.FilePath.mk object).withExtension "source"
    if !(← witness.pathExists) then continue
    let name ← IO.ofExcept (mapping.getObjValAs? String object)
    let value ← read witness
    if let some old := result[name]? then check (old == value) "duplicate native source producer"
    result := result.insert name value
  return result
def sealAuditor : IO Unit := do
  drained
  let before ← witnesses runtime
  let after ← witnesses target
  let mut shared := #[]
  let mut added := #[]
  for (name,value) in after do
    if let some previous := before[name]? then
      check (value == previous) ("auditor changed an existing native source: "++name)
      shared := shared.push name
    else
      check (name.startsWith "tools.research.") ("auditor introduced unverified product source: "++name)
      added := added.push name
  check (shared.size > 150 && ["Eggshell.GraphStore","Eggshell.ContentMetadata","Eggshell.PublicationWire"].all shared.contains)
    "current DB and publication type comparison is vacuous"
  write (study/"auditor-sources.json") (Json.mkObj [("commonSourcesUnchanged",toJson true),
    ("sharedNativeModules",toJson (shared.qsort (· < ·))),("addedResearchModules",toJson (added.qsort (· < ·))),
    ("helperDoesNotNeedEveryRuntimeEntryOrContractControl",toJson true),
    ("runtimeSha256",toJson (← hash (runtime/"StudyMain"))),("auditorSha256",toJson (← hash (target/"StudyMain")))])
def refreshHelper : IO Unit := do
  drained
  for name in ["RealDeliveryProbe","StudyWarm"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (source/relative) (← IO.FS.readFile (workspace/relative))
def prepareFootprint : IO Unit := do
  drained
  check (!(← diagnosticSource.pathExists)) "fresh diagnostic source required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",runtime.toString,
    diagnosticSource.toString,diagnosticTarget.toString,"tools.research.ReplayReadinessChecks",diagnosticSettings.toString]
  let helper := "tools/research/ReplyFootprint.lean"
  IO.FS.writeFile (diagnosticSource/helper) (← IO.FS.readFile (workspace/helper))
  let path := diagnosticSource/"Eggshell/OperationPool.lean"
  let before ← IO.FS.readFile path
  let needle := "    let value := toJson reply\n    let amount := value.compress.utf8ByteSize+1024\n"
  check ((before.splitOn needle).length == 2) "one actual actor reply admission required"
  let replacement := "    let value := toJson reply\n    let serialized := value.compress\n    let amount := serialized.utf8ByteSize+1024\n    observeJob job \"reply-sizing\" [(\"payloadBytes\",toJson serialized.utf8ByteSize),\n      (\"reservationBytes\",toJson amount),(\"frameLimit\",toJson (replyBytes job.request.role)),\n      (\"fitsFrame\",toJson (decide (amount ≤ replyBytes job.request.role))),\n      (\"payloadSha256\",toJson (Sha256.hex serialized.toUTF8))]\n    Research.ReplyFootprint.capture job.request.id serialized\n"
  IO.FS.writeFile path ((before.replace needle replacement).replace "public import Eggshell.SearchReaders"
    "public import Eggshell.SearchReaders\npublic import tools.research.ReplyFootprint")
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/OperationPool.lean",
    "--label","b/Eggshell/OperationPool.lean",(base/"search-read-source/Eggshell/OperationPool.lean").toString,path.toString]}
  check (patch.exitCode == 1) "diagnostic patch missing"
  IO.FS.writeFile (study/"reply-footprint.patch") patch.stdout
def prepareFootprintHelper : IO Unit := do
  drained
  check (!(← diagnosticAuditorSource.pathExists)) "fresh diagnostic auditor source required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",diagnosticTarget.toString,
    diagnosticAuditorSource.toString,diagnosticAuditor.toString,"tools.research.RealDeliveryProbe",diagnosticAuditorSettings.toString]
  IO.FS.writeFile (diagnosticAuditorSource/"tools/research/RealDeliveryProbe.lean")
    (← IO.FS.readFile (workspace/"tools/research/RealDeliveryProbe.lean"))
  ensureResearch diagnosticAuditorSource "tools.research.RealDeliveryProbe" (← IO.mkRef {})
  let runtimeHash ← hash (diagnosticTarget/"StudyMain")
  write diagnosticInstall (Json.mkObj [("root",toJson diagnosticInstallation.toString),
    ("runtime",Json.mkObj [("path",toJson (diagnosticTarget/"StudyMain").toString),("sha256",toJson runtimeHash)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  write diagnosticProbe (Json.mkObj [
    ("originalInput",Json.mkObj [("path",toJson inputFile.toString),("sha256",toJson (← hash inputFile))]),
    ("runtime",Json.mkObj [("path",toJson (diagnosticInstallation/"libexec/eggshell").toString),("sha256",toJson runtimeHash)]),
    ("pluginRoot",toJson (diagnosticInstallation/"share/eggshell/codex-plugin").toString),
    ("topic",toJson (1 : Nat)),("destination",toJson (base/"real-source-reply-footprint-result").toString)])
def sealFootprint : IO Unit := do
  drained
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  for (selected,name) in [(diagnosticTarget,"footprint-runtime"),(diagnosticAuditor,"footprint-auditor")] do
    let path := study/(name++"-closure.json")
    if !(← path.pathExists) then
      discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
        "inspect",selected.toString,path.toString]
    check ((← read path).getObjValD "consistent" == toJson true) "diagnostic native closure is inconsistent"
  if !(← (study/"footprint-runtime-sources.json").pathExists) then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
      "compare-sources",runtime.toString,diagnosticTarget.toString,(study/"footprint-runtime-sources.json").toString,
      "Eggshell.OperationPool","+tools.research.ReplyFootprint"]
  check ((← read (study/"footprint-runtime-sources.json")).getObjValD "candidateRuntimeSha256" ==
    toJson (← hash (diagnosticTarget/"StudyMain"))) "diagnostic runtime changed after source audit"
  let product ← witnesses diagnosticTarget
  let helper ← witnesses diagnosticAuditor
  let mut shared := 0
  for (name,value) in helper do
    if let some existing := product[name]? then
      check (existing == value) ("diagnostic auditor changed product source: "++name)
      shared := shared+1
    else check (name.startsWith "tools.research.") "unexpected diagnostic product module"
  check (shared > 150) "diagnostic native type comparison was vacuous"
  write (study/"footprint-auditor-sources.json") (Json.mkObj [("commonSourcesUnchanged",toJson true),
    ("sharedModules",toJson shared),("productSha256",toJson (← hash (diagnosticTarget/"StudyMain"))),
    ("auditorSha256",toJson (← hash (diagnosticAuditor/"StudyMain")))])
def rebaseFootprintHelper : IO Unit := do
  drained
  let settings ← read diagnosticAuditorSettings
  check (settings.getObjValD "baselineResponse" == toJson (target/"runtime.rsp").toString)
    "only the rejected parent-auditor materialization may be retired"
  write (study/"footprint-helper-rejection.json") (Json.mkObj [
    ("reason",toJson "PublicationWire embedded OperationPool; the diagnostic auditor must inherit the diagnostic product"),
    ("productSha256",toJson (← hash (diagnosticTarget/"StudyMain"))),
    ("rejectedAuditorSha256",toJson (← hash (diagnosticAuditor/"StudyMain"))),
    ("rejectedSettings",settings),("rejectedClosure",← read (study/"footprint-auditor-closure.json")),
    ("hooksStarted",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  IO.FS.removeFile (study/"footprint-auditor-closure.json")
  for path in [diagnosticAuditorSource,diagnosticAuditor] do
    check (path.toString.startsWith (base.toString++"/real-source-reply-footprint-auditor-"))
      "refuse to remove another native source"
    discard <| command "/bin/rm" #["-rf","--",path.toString]
  IO.FS.removeFile diagnosticAuditorSettings
  prepareFootprintHelper
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["seal-source"] => sealSource
  | ["seal-auditor"] => sealAuditor
  | ["refresh-helper"] => refreshHelper
  | ["prepare-footprint"] => prepareFootprint
  | ["prepare-footprint-helper"] => prepareFootprintHelper
  | ["seal-footprint"] => sealFootprint
  | ["rebase-footprint-helper"] => rebaseFootprintHelper
  | ["refresh-footprint-helper"] => do
    drained
    ensureResearch diagnosticAuditorSource "tools.research.RealDeliveryProbe" (← IO.mkRef {})
  | _ => throw (IO.userError "prepare | setup ACTION TAG | seal-source | seal-auditor")
end Eggshell.Research.RealSourceStudy
def main := Eggshell.Research.RealSourceStudy.main
