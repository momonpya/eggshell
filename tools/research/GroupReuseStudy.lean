import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace GroupReuseStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"group-reuse-source"
def build := base/"group-reuse-build"
def folder := workspace/"docs/candidates/group-reuse"
def check (yes : Bool) (message : String) : IO Unit := unless yes do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.contains base.toString && !row.contains "GroupReuseStudy.lean")) "an experiment is live"
def between (text first last : String) : IO String := do
  let parts := text.splitOn first
  check (parts.length == 2) "ambiguous group producer start"
  let suffix := parts[1]!.splitOn last
  check (suffix.length == 2) "ambiguous group producer end"
  return first++suffix[0]!

def grouped : String := r#"
def groupUnit? (owner : String) (ready : OwnerReady)
    (spans : List (Nat × Nat)) : Except String (Option UnitRef) := do
  let requested := (Array.range ready.rows.size).toList.filter fun index =>
    (ready.rows[index]?).any fun row => row.origins.any fun origin =>
      origin.binding.owner == owner && spans.any fun (first,limit) =>
        first < origin.binding.limit && origin.binding.first < limit
  let selected := hashDistinct (requested ++ (ready.stored.records.filter fun record =>
    record.any requested.contains).flatten)
  if selected.isEmpty then return none
  let rows ← selected.toArray.mapM fun index => requireSome (ready.rows[index]?) "source group escaped its row domain"
  return some {keys := rows.map (·.key),ranges := bindings owner rows}

def groupedUnits (owner : String) (ready : OwnerReady)
    (groups : List (List (Nat × Nat))) : Except String (Array UnitRef) := do
  let result ← Eggshell.Research.MemoGroupFold.run (groupUnit? owner ready) (·.ranges)
    ⟨ready.units,Std.HashSet.ofArray (ready.units.map (·.ranges))⟩ groups
  return result.values

theorem grouped_units_memo_exact (owner : String) (ready : OwnerReady)
    (groups : List (List (Nat × Nat))) :
    groupedUnits owner ready groups = (do
      let result ← Eggshell.Research.MemoGroupFold.reference (groupUnit? owner ready) (·.ranges)
        ⟨ready.units,Std.HashSet.ofArray (ready.units.map (·.ranges))⟩ groups
      return result.values) := by
  unfold groupedUnits
  rw [Eggshell.Research.MemoGroupFold.run_exact]

"#

def federated : String := r#"
def federatedUnit? (owner : String) (rows : Array RowRef)
    (indices : List Nat) : Except String (Option UnitRef) := do
  if indices.isEmpty then return none
  let selected ← indices.toArray.mapM fun index => requireSome (rows[index]?) "federated unit escaped its rows"
  return some {keys := selected.map (·.key),ranges := bindings owner selected}

def federatedUnits (owner : String) (parts : Array OwnerReady) (rows : Array RowRef)
    (groups : List (List (Nat × Nat))) : Except String (Array UnitRef) := do
  if parts.size == 1 then
    let some ready := parts[0]? | throw "federated owner disappeared"
    return ← groupedUnits owner ready groups
  let positions := Std.HashMap.ofArray (rows.mapIdx fun index row => (row.key,index))
  let mut records := []
  for part in parts do
    for record in part.stored.records do
      let remapped ← record.mapM fun index => do
        let row ← requireSome (part.rows[index]?) "federated record escaped its owner"
        requireSome positions[row.key]? "federation lost an original record row"
      records := records ++ [remapped]
  records := hashDistinct records
  let covered := Std.HashSet.ofList records.flatten
  let catalogue := records ++ (Array.range rows.size).toList.filterMap fun index =>
    if covered.contains index then none else some [index]
  let initialOut ← Eggshell.Research.MemoGroupFold.reference (federatedUnit? owner rows) (·.ranges)
    ⟨#[],{}⟩ catalogue
  let make := fun (spans : List (Nat × Nat)) =>
    let indices := (Array.range rows.size).toList.filter fun index => (rows[index]?).any fun row =>
      row.origins.any fun origin => origin.binding.owner == owner && spans.any fun (first,limit) =>
        first < origin.binding.limit && origin.binding.first < limit
    federatedUnit? owner rows (hashDistinct (indices ++
      (records.filter (fun record => record.any indices.contains)).flatten))
  let result ← Eggshell.Research.MemoGroupFold.run make (·.ranges) initialOut groups
  return result.values

"#

def prepare : IO Unit := do
  drained
  check (!(← source.pathExists) && !(← build.pathExists)) "fresh group reuse candidate required"
  IO.FS.createDirAll folder
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"deferred-audit-build").toString,source.toString,build.toString,
    "tools.research.GroupReuseChecks",(base/"group-reuse-settings.json").toString]
  let target := source/"tools/research/PreparedSourceView.lean"
  let original ← IO.FS.readFile target
  let oldGrouped ← between original "def groupedUnits (owner : String)" "/-- A genuinely federated view"
  let oldFederated ← between original "def federatedUnits (owner : String)" "structure FileStored where"
  let importLine := "public import tools.research.PreparedFocusFacts\n"
  check ((original.splitOn importLine).length == 2) "group imports changed"
  IO.FS.writeFile target (original.replace importLine (importLine++"public import tools.research.MemoGroupFold\n")
    |>.replace oldGrouped grouped |>.replace oldFederated federated)
  for name in ["MemoGroupFold","GroupReuseChecks"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))
  let checker ← IO.FS.readFile (source/"tools/research/GroupReuseChecks.lean")
  check ((checker.splitOn "-- ORIGINAL PRODUCERS\n").length == 2) "reference producer insertion changed"
  let reference := oldGrouped.replace "def groupedUnits" "def referenceGroupedUnits" ++
    (oldFederated.replace "def federatedUnits" "def referenceFederatedUnits" |>.replace
      "return ← groupedUnits" "return ← referenceGroupedUnits")
  IO.FS.writeFile (source/"tools/research/GroupReuseChecks.lean")
    (checker.replace "-- ORIGINAL PRODUCERS\n" reference)
  write (folder/"plan.json") (Json.mkObj [("parentRuntime",toJson "a2ed21ff02eeab7951f4b16e69fcaed7225dbf56045fbb1952177bfacc6e5a6b"),
    ("change",toJson "skip repeated exact group inputs before deterministic row/record expansion"),
    ("inputKeyContainsNoOutputPayload",toJson true),("recordInverseNotReintroduced",toJson true),
    ("sourceDomainRanksBudgetsModelAndResourceLimitsUnchanged",toJson true),
    ("componentTrials",toJson "three complete saved-query replays per arm, AB/BA/AB, including input-key preparation"),
    ("originalProducerDefinitions",toJson (oldGrouped,oldFederated)),
    ("preliminaryProofCompileFailures",toJson #["implicit make/key type inference","Except simplification","Except instance reduction"]),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def setup (mode tag : String) : IO Unit := do
  drained
  check (tag.startsWith "group-reuse-") "known group reuse owner required"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve group attempt"
  let args ← if ["build","runtime-build","auditor-build"].contains mode then
    pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,
      (base/(if mode == "build" then "group-reuse-settings.json" else s!"group-reuse-{mode.dropEnd 6}.json")).toString]
    else do
      if mode == "check" then
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
          "EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
          (build/"StudyMain").toString,(base/"real-source-search-read-trial-result/work.egg").toString,
          (base/"selection-profile-inputs/selector-fixture.json").toString,(base/"group-reuse-result.json").toString]
      else
        check (["install","cells"].contains mode) "unknown group reuse stage"
        pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"group-reuse-auditor-build/StudyMain").toString,
          (if mode == "install" then "install-prefix" else "cells"),
          (base/(if mode == "install" then "group-reuse-install.json" else "group-reuse-cells.json")).toString]
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def collectComponent : IO Unit := do
  drained
  check (!(← (folder/"component.json").pathExists)) "preserve group component comparison"
  let result ← read (base/"group-reuse-result.json")
  check (result.getObjValD "allCompleteOutputsEqual" == toJson true &&
    result.getObjValD "originalSourceUnchanged" == toJson true) "component did not preserve originals"
  let mut attempts := #[]
  for tag in ["group-reuse-build1","group-reuse-build2","group-reuse-build3","group-reuse-check1"] do
    let status ← read (base/(tag++".guard.json"))
    check (status.getObjValD "state" == toJson "finished" &&
      status.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a group attempt is live"
    let mut logs := #[]
    for extension in ["stdout","stderr"] do
      let text ← IO.FS.readFile (base/(tag++"."++extension))
      check (text.utf8ByteSize ≤ 65536) "component log needs explicit bounded collection"
      logs := logs.push (extension,text)
    attempts := attempts.push (Json.mkObj [("tag",toJson tag),("guard",status),("logs",toJson logs)])
  write (folder/"component.json") (Json.mkObj [("result",result),("attempts",toJson attempts),
    ("runtimeSha256",toJson (← hash (build/"StudyMain"))),
    ("genericProofAxioms",toJson #["propext","Classical.choice","Quot.sound"]),
    ("normalRuntimeOrCapacityVerified",toJson false),("adopted",toJson false)])

def prepareRuntime : IO Unit := do
  drained
  let component ← read (folder/"component.json")
  check ((component.getObjValD "result").getObjValD "allCompleteOutputsEqual" == toJson true)
    "verify complete group outputs first"
  let settings ← read (base/"group-reuse-settings.json")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  -- Component materialization replaces the parent's entry. Restore exactly
  -- its linked source when building the ordinary runtime, never a newer entry.
  IO.FS.writeFile (source/"tools/research/ReplayReadinessChecks.lean")
    (← IO.FS.readFile (base/"deferred-audit-source/tools/research/ReplayReadinessChecks.lean"))
  write (base/"group-reuse-runtime.json") (settings
    |>.setObjVal! "mainModule" (toJson "tools.research.ReplayReadinessChecks")
    |>.setObjVal! "output" (toJson (base/"group-reuse-runtime-build").toString)
    |>.setObjVal! "parents" (toJson (#[build.toString]++parents)))

def auditRuntime : IO Unit := do
  drained
  let runtime := base/"group-reuse-runtime-build"
  let tool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"inspect",
    runtime.toString,(folder/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"compare-sources",
    (base/"deferred-audit-build").toString,runtime.toString,(folder/"native-sources.json").toString,
    "tools.research.PreparedSourceView","+tools.research.MemoGroupFold"]

partial def supplyHelper (name : String) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if (← seen.get).contains name then return
  seen.modify (·.insert name)
  let relative := name.replace "." "/"++".lean"
  let target := source/relative
  if !(← target.pathExists) then
    check (name.startsWith "tools.research.") ("missing product dependency: "++name)
    IO.FS.createDirAll target.parent.get!
    IO.FS.writeFile target (← IO.FS.readFile (workspace/relative))
  for row in (← IO.FS.readFile target).splitOn "\n" do
    let row := row.trimAscii.toString
    let imported := if row.startsWith "public import " then (row.drop 14).toString
      else if row.startsWith "import " then (row.drop 7).toString else ""
    if imported.startsWith "Eggshell." || imported.startsWith "tools." || imported.startsWith "tests." || imported == "Main" then
      supplyHelper imported seen

def prepareAuditor : IO Unit := do
  drained
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "verify the normal product first"
  supplyHelper "tools.research.RealDeliveryProbe" (← IO.mkRef {})
  let settings ← read (base/"group-reuse-runtime.json")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  let runtime := base/"group-reuse-runtime-build"
  let modules ← IO.ofExcept ((← read (runtime/"build.json")).getObjValAs? (Array Json) "modules")
  let some entry := modules.find? (fun row => row.getObjValD "module" == toJson "tools.research.ReplayReadinessChecks") |
    throw (IO.userError "normal runtime entry is absent")
  write (base/"group-reuse-auditor.json") (settings
    |>.setObjVal! "mainModule" (toJson "tools.research.RealDeliveryProbe")
    |>.setObjVal! "output" (toJson (base/"group-reuse-auditor-build").toString)
    |>.setObjVal! "parents" (toJson (#[runtime.toString]++parents))
    |>.setObjVal! "baselineResponse" (toJson (runtime/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (entry.getObjValD "object"))

def prepareCells : IO Unit := do
  drained
  let runtime := base/"group-reuse-runtime-build"
  let auditor := base/"group-reuse-auditor-build"
  let tool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"inspect",
    auditor.toString,(folder/"auditor-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"common-sources",
    runtime.toString,auditor.toString,(folder/"auditor-sources.json").toString]
  let proof ← read (folder/"auditor-sources.json")
  check (proof.getObjValD "allProductCorePresent" == toJson true &&
    proof.getObjValD "commonSourcesUnchanged" == toJson true) "actual hook driver changed product core"
  let installation := base/"group-reuse-prefix"
  let sha ← hash (runtime/"StudyMain")
  write (base/"group-reuse-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (runtime/"StudyMain").toString),("sha256",toJson sha)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let input ← read (base/"deferred-audit-cells2.json")
  let root := base/"group-reuse-cells-result"
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let cell := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (root/cell).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson sha)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"group-reuse-cells.json") (input.setObjVal! "output" (toJson root.toString)
    |>.setObjVal! "probes" (toJson probes))

def sealInstalled : IO Unit := do
  drained
  let binary := base/"group-reuse-prefix/libexec/eggshell"
  let product := base/"group-reuse-runtime-build/StudyMain"
  let sha ← hash product
  check ((← hash binary) == sha) "new installation differs from its normal runtime"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "installation temporary already exists"
  discard <| command "/bin/ln" #[product.toString,temporary.toString]
  IO.FS.rename temporary binary
  write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson sha),("sharesImmutableProductInode",toJson true)])

partial def removeTree (path : System.FilePath) : IO Nat := do
  if (← path.symlinkMetadata).type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← removeTree entry.path)
    IO.FS.removeDir path
    return bytes
  else
    let bytes := (← path.symlinkMetadata).byteSize.toNat
    IO.FS.removeFile path
    return bytes

def retireEndedOutputs : IO Unit := do
  drained
  check (!(← (folder/"retired-ended-outputs.json").pathExists)) "preserve output retirement"
  let product := base/"group-reuse-runtime-build/StudyMain"
  let productHash ← hash product
  let parentHash ← hash (base/"deferred-audit-build/StudyMain")
  let original := base/"real-source-search-read-trial-result/work.egg"
  let expected ← IO.ofExcept (((← read (folder/"component.json")).getObjValD "result").getObjValAs?
    (Array (String × String)) "sourceFiles")
  for (name,sha) in expected do check ((← hash (original/name)) == sha) "source already changed"
  let actualBase ← IO.FS.realPath base
  let mut removed := #[]
  for entry in ← base.readDir do
    if ["deferred-audit-cells2-result","group-reuse-cells-result"].contains entry.fileName then continue
    let cells := entry.fileName.endsWith "-cells-result" || entry.fileName.endsWith "-cells2-result"
    let capacity := entry.fileName.endsWith "-capacity-small-result"
    if !cells && !capacity then continue
    let reportPath := entry.path/(if cells then "result.json" else "report.json")
    if !(← reportPath.pathExists) then continue
    let report ← read reportPath
    if cells && report.getObjValD "allSixPassed" != toJson true then continue
    if capacity && report.getObjValD "allPhasesPassed" != toJson true then continue
    check ((← entry.path.symlinkMetadata).type == .dir &&
      (← IO.FS.realPath entry.path) == actualBase/entry.fileName) "ended output escaped its exact child path"
    let sha ← hash reportPath
    let bytes ← removeTree entry.path
    removed := removed.push (Json.mkObj [("path",toJson entry.path.toString),("reportSha256",toJson sha),
      ("allDeclaredPhasesPassed",toJson true),("logicalBytes",toJson bytes)])
  let component := (← read (folder/"component.json")).getObjValD "runtimeSha256"
  check (component == toJson (← hash (build/"StudyMain"))) "ended component executable changed"
  let bytes := (← (build/"StudyMain").metadata).byteSize.toNat
  IO.FS.removeFile (build/"StudyMain")
  for (name,sha) in expected do check ((← hash (original/name)) == sha) "retirement changed original source"
  check ((← hash product) == productHash && (← hash (base/"deferred-audit-build/StudyMain")) == parentHash)
    "retirement changed an active product"
  write (folder/"retired-ended-outputs.json") (Json.mkObj [("removed",toJson removed),
    ("componentExecutableSha256",component),("componentExecutableLogicalBytes",toJson bytes),
    ("currentSixFrozenBodiesRetained",toJson true),("projectCachesModelsOriginalDbAndNativeInputsRetained",toJson true),
    ("archived",toJson false)])

def collectRuntime : IO Unit := do
  drained
  check (!(← (folder/"runtime.json").pathExists)) "preserve normal-runtime evidence"
  let runtime := base/"group-reuse-runtime-build"
  let audit ← read (folder/"native-sources.json")
  let sha ← hash (runtime/"StudyMain")
  check (audit.getObjValD "exactExpectedChangeSet" == toJson true &&
    audit.getObjValD "candidateRuntimeSha256" == toJson sha) "runtime source audit changed"
  let mut attempts := #[]
  for tag in ["group-reuse-runtime1","group-reuse-runtime2"] do
    let status ← read (base/(tag++".guard.json"))
    check (status.getObjValD "state" == toJson "finished" &&
      status.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "normal runtime build did not drain"
    let stdout ← IO.FS.readFile (base/(tag++".stdout"))
    let stderr ← IO.FS.readFile (base/(tag++".stderr"))
    check (stdout.utf8ByteSize+stderr.utf8ByteSize ≤ 65536) "runtime build log is not bounded"
    attempts := attempts.push (Json.mkObj [("tag",toJson tag),("guard",status),
      ("stdout",toJson stdout),("stderr",toJson stderr)])
  let blocked := "group-reuse-auditor1"
  check (!(← (base/(blocked++".guard.json")).pathExists)) "do not label a started auditor as a preflight rejection"
  let stderr ← IO.FS.readFile (base/(blocked++".stderr"))
  check (stderr.contains "not enough disk space to start") "auditor stopped for a different reason"
  let disk ← command "/bin/df" #["-k",workspace.toString]
  let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/tools/research/PreparedSourceView.lean",
    "--label","b/tools/research/PreparedSourceView.lean",
    (base/"deferred-audit-source/tools/research/PreparedSourceView.lean").toString,
    (source/"tools/research/PreparedSourceView.lean").toString]}
  check (difference.exitCode == 1) "the declared group producer change is absent"
  IO.FS.writeFile (folder/"PreparedSourceView.patch") difference.stdout
  write (folder/"runtime.json") (Json.mkObj [("runtimeSha256",toJson sha),("attempts",toJson attempts),
    ("auditorPreflight",Json.mkObj [("childStarted",toJson false),("stderr",toJson stderr),
      ("settings",← read (base/(blocked++".guard-settings.json"))),("observedDisk",toJson disk)]),
    ("actualSixHookRuns",toJson (0 : Nat)),("newCapacityRuns",toJson (0 : Nat)),
    ("next",toJson "restore at least the unchanged disk floor, build the matching auditor, then topic1-first all six actual hooks and the unchanged 4/16 to 80 gates"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  for tag in ["group-reuse-build1","group-reuse-build2","group-reuse-build3","group-reuse-check1",
      "group-reuse-runtime1","group-reuse-runtime2",blocked] do
    for extension in ["stdout","stderr"] do
      let path := base/(tag++"."++extension)
      if ← path.pathExists then IO.FS.removeFile path

def refresh : IO Unit := do
  drained
  for name in ["MemoGroupFold","GroupReuseChecks"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))
  let original ← IO.FS.readFile (base/"deferred-audit-source/tools/research/PreparedSourceView.lean")
  let oldGrouped ← between original "def groupedUnits (owner : String)" "/-- A genuinely federated view"
  let oldFederated ← between original "def federatedUnits (owner : String)" "structure FileStored where"
  let importLine := "public import tools.research.PreparedFocusFacts\n"
  IO.FS.writeFile (source/"tools/research/PreparedSourceView.lean")
    (original.replace importLine (importLine++"public import tools.research.MemoGroupFold\n")
      |>.replace oldGrouped grouped |>.replace oldFederated federated)
  let checker ← IO.FS.readFile (source/"tools/research/GroupReuseChecks.lean")
  let reference := oldGrouped.replace "def groupedUnits" "def referenceGroupedUnits" ++
    (oldFederated.replace "def federatedUnits" "def referenceFederatedUnits" |>.replace
      "return ← groupedUnits" "return ← referenceGroupedUnits")
  IO.FS.writeFile (source/"tools/research/GroupReuseChecks.lean")
    (checker.replace "-- ORIGINAL PRODUCERS\n" reference)

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["setup",mode,tag] => setup mode tag
  | ["refresh"] => refresh
  | ["collect-component"] => collectComponent
  | ["prepare-runtime"] => prepareRuntime
  | ["audit-runtime"] => auditRuntime
  | ["prepare-auditor"] => prepareAuditor
  | ["prepare-cells"] => prepareCells
  | ["seal-installed"] => sealInstalled
  | ["retire-ended-outputs"] => retireEndedOutputs
  | ["collect-runtime"] => collectRuntime
  | _ => throw (IO.userError "group reuse: prepare|setup MODE TAG|refresh")
end GroupReuseStudy
def main := GroupReuseStudy.main
