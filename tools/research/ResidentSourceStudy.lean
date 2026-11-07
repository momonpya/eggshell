import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace ResidentSourceStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := workspace/"docs/candidates/resident-source"
def source := base/"resident-source-source"
def build := base/"resident-source-build"
def parent := base/"typed-plan-build"
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
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.contains base.toString && !row.contains "ResidentSourceStudy.lean"))
    "an experiment owner is live"
def guard (tag : String) (args : Array String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve existing guard"
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def replace (path : System.FilePath) (before after : String) : IO Unit := do
  let text ← IO.FS.readFile path
  check ((text.splitOn before).length == 2) ("unique source block missing: "++path.toString)
  IO.FS.writeFile path (text.replace before after)
def prepare : IO Unit := do
  drained
  check ((← hash (parent/"StudyMain")) == "bb0d5972b756ba984e97e6277df8c174521292073d022972b5e06191bb7a2bf7")
    "parent runtime changed"
  check (!(← source.pathExists) && !(← build.pathExists)) "fresh isolated source required"
  IO.FS.createDirAll folder
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,build.toString,"tools.research.ReplayReadinessChecks",(base/"resident-source-settings.json").toString]
  let path := source/"tools/research/PreparedOwnerArena.lean"
  replace path ("  palette : OwnerPalette.Ready stored layout\n"++
    "  units : PreparedFileUnits.Ready owner stored.rows layout\n"++
    "  published : PublishedPlanMetadata.Ready owner stored layout\n") ""
  replace path "⟨database,owner,stored,layout,checked,⟨registry,loaded⟩,inScope,OwnerPalette.prepare stored layout,PreparedFileUnits.prepare owner stored.rows layout,PublishedPlanMetadata.prepare owner stored layout⟩"
    "⟨database,owner,stored,layout,checked,⟨registry,loaded⟩,inScope⟩"
  replace path ("  let published ← PublishedPlanMetadata.check ready.owner ready.stored ready.layout metadata\n"++
    "  return {ready with published}")
    ("  let _ ← PublishedPlanMetadata.check ready.owner ready.stored ready.layout metadata\n"++"  return ready")
  IO.FS.writeFile (source/"tools/research/ResidentSourceChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/ResidentSourceChecks.lean"))
  let entry := source/"tools/research/ReplayReadinessChecks.lean"
  replace entry "import tools.research.TypedPlanChecks" "import tools.research.TypedPlanChecks\nimport tools.research.ResidentSourceChecks"
  replace entry "  | [\"typed-plan-check\",fixture,sha,output] =>"
    ("  | [\"resident-source-check\",fixture,sha,output] =>\n"++
      "    Eggshell.Research.ResidentSourceChecks.run (.mk fixture) sha (.mk output); return 0\n"++
      "  | [\"typed-plan-check\",fixture,sha,output] =>")
  write (folder/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"StudyMain"))),
    ("change",toJson "remove unread duplicate palette/layout metadata from resident canonical owner; retain original and publication validation"),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
def setup (action tag : String) : IO Unit := do
  drained
  if action == "build" then guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"resident-source-settings.json").toString]
  else if action == "component" then
    let fixture := base/"real-source-search-read-trial-result/data/reply-witnesses/affacad8c38e209788a0eafb78d716bda6237f42a0b995594a4af87c9089a6f2.json"
    guard tag #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,"resident-source-check",
      fixture.toString,(← hash fixture),(base/(tag++"-result.json")).toString]
  else throw (IO.userError "unknown resident source action")
def collect (tag : String) : IO Unit := do
  drained
  let g ← read (base/(tag++".guard.json"))
  check (g.getObjValD "state" == toJson "finished" && g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "owner not drained"
  write (folder/(tag++".json")) (Json.mkObj [("guard",g),
    ("stdout",toJson (← IO.FS.readFile (base/(tag++".stdout")))),
    ("stderr",toJson (← IO.FS.readFile (base/(tag++".stderr"))))])
def auditNative : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",audit,"inspect",build.toString,
    (folder/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",audit,"compare-sources",parent.toString,build.toString,
    (folder/"native-sources.json").toString,"tools.research.PreparedOwnerArena","+tools.research.ResidentSourceChecks"]
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected source changes"
  let relative := "tools/research/PreparedOwnerArena.lean"
  let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
    (base/"typed-plan-source"/relative).toString,(source/relative).toString]}
  check (difference.exitCode == 1) "resident source change missing"
  IO.FS.writeFile (folder/"PreparedOwnerArena.patch") difference.stdout
def auditEntry : IO Unit := do
  drained
  let native ← IO.ofExcept ((← read (build/"tools_research_ReplayReadinessChecks.source")).getArr?)
  let entry ← IO.ofExcept native[0]!.getStr?
  let before ← IO.FS.readFile (base/"typed-plan-source/tools/research/ReplayReadinessChecks.lean")
  let stripped := entry.replace "\nimport tools.research.ResidentSourceChecks" "" |>.replace
    ("  | [\"resident-source-check\",fixture,sha,output] =>\n"++
      "    Eggshell.Research.ResidentSourceChecks.run (.mk fixture) sha (.mk output); return 0\n") ""
  check (stripped == before && entry == (← IO.FS.readFile (source/"tools/research/ReplayReadinessChecks.lean")))
    "compiled entry differs beyond the research check"
  write (folder/"entry-source.json") (Json.mkObj [("onlyResearchCommandAndImportAdded",toJson true)])
partial def ensureTools (name : String) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if ["Init","Std","Lean"].any (fun rootName => name == rootName || name.startsWith (rootName++".")) then return
  if (← seen.get).contains name then return
  seen.modify (·.insert name)
  let relative := name.replace "." "/"++".lean"
  let path := source/relative
  if !(← path.pathExists) then
    check (name.startsWith "tools.research." || name.startsWith "tests.") ("missing frozen product module: "++name)
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeFile path (← IO.FS.readFile (workspace/relative))
  for line in (← IO.FS.readFile path).splitOn "\n" do
    let line := line.trimAscii.toString
    let introducer := if line.startsWith "public import " then "public import " else "import "
    if !line.startsWith introducer then continue
    let words := ((line.drop introducer.length).toString.splitOn " ").filter (!·.isEmpty)
    let words := if words.head? == some "all" then words.drop 1 else words
    if let some imported := words.head? then ensureTools imported seen
def prepareAuditor : IO Unit := do
  drained
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "seal the product first"
  ensureTools "tools.research.RealDeliveryProbe" (← IO.mkRef {})
  let settings ← read (base/"resident-source-settings.json")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  write (base/"resident-source-auditor-settings.json") (settings
    |>.setObjVal! "output" (toJson (base/"resident-source-auditor-build").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.RealDeliveryProbe")
    |>.setObjVal! "parents" (toJson (#[build.toString]++parents))
    |>.setObjVal! "baselineResponse" (toJson (build/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (build/"tools_research_ReplayReadinessChecks.o").toString))
  guard "resident-source-auditor-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"resident-source-auditor-settings.json").toString]
def prepareCells : IO Unit := do
  drained
  let auditor := base/"resident-source-auditor-build"
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",audit,"inspect",auditor.toString,
    (folder/"auditor-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",audit,"common-sources",build.toString,auditor.toString,
    (folder/"auditor-sources.json").toString]
  let proof ← read (folder/"auditor-sources.json")
  check (proof.getObjValD "allProductCorePresent" == toJson true && proof.getObjValD "commonSourcesUnchanged" == toJson true)
    "delivery auditor changed product core"
  let installation := base/"resident-source-prefix"
  let manifest := base/"resident-source-install.json"
  write manifest (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (build/"StudyMain").toString),("sha256",toJson (← hash (build/"StudyMain")))]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  guard "resident-source-install1" #[(auditor/"StudyMain").toString,"install-prefix",manifest.toString]
  let input ← read (base/"typed-plan-cells.json")
  let root := base/"resident-source-cells-result"
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let cell := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (root/cell).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),
        ("sha256",toJson (← hash (build/"StudyMain")))])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"resident-source-cells.json") (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
  guard "resident-source-cells1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(auditor/"StudyMain").toString,"cells",
    (base/"resident-source-cells.json").toString]
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["refresh-checks"] =>
    drained
    IO.FS.writeFile (source/"tools/research/ResidentSourceChecks.lean")
      (← IO.FS.readFile (workspace/"tools/research/ResidentSourceChecks.lean"))
  | ["setup",action,tag] => setup action tag
  | ["collect",tag] => collect tag
  | ["collect-all"] =>
    for entry in ← base.readDir do
      if entry.fileName.startsWith "resident-source-" && entry.fileName.endsWith ".guard.json" then
        collect (entry.fileName.dropEnd 11).toString
  | ["retire-ended-helpers"] =>
    drained
    let mut removed := #[]
    let entries := [
      (base/"typed-fetch-build/StudyMain",workspace/"docs/candidates/typed-fetch/native-sources.json","candidateRuntimeSha256"),
      (base/"typed-fetch-prefix/libexec/eggshell",workspace/"docs/candidates/typed-fetch/native-sources.json","candidateRuntimeSha256"),
      (base/"typed-plan-auditor-build/StudyMain",workspace/"docs/candidates/typed-plan/auditor-sources.json","auditorSha256"),
      (base/"typed-plan-capacity-build/StudyMain",workspace/"docs/candidates/typed-plan/capacity-sources.json","auditorSha256")]
    for (path,evidence,key) in entries do
      if !(← path.pathExists) then continue
      let digest ← hash path
      check ((← read evidence).getObjValD key == toJson digest) "ended helper identity changed"
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson digest)])
      IO.FS.removeFile path
    let failed := base/"resident-source-cells-result"
    if ← failed.pathExists then
      check (!(← (failed/"topic-1-chat-0/hook/stdout").pathExists)) "actual failed delivery must be retained first"
      IO.FS.removeDirAll failed
    write (folder/"ended-helpers-cleanup.json") (Json.mkObj [("removed",toJson removed),
      ("failedUnstartedTrialRemoved",toJson true),("archived",toJson false),
      ("parentProductCurrentProductSourceDbProjectCacheModelsNativeInputsRetained",toJson true)])
  | ["audit"] => auditNative; auditEntry
  | ["audit-entry"] => auditEntry
  | ["prepare-auditor"] => prepareAuditor
  | ["prepare-cells"] => prepareCells
  | ["resume-unstarted-cells"] =>
    drained
    let g ← read (base/"resident-source-cells1.guard.json")
    check (g.getObjValD "state" == toJson "finished" && g.getObjValD "exitCode" == toJson (1 : Nat) &&
      g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous attempt has not ended"
    check (!(← (base/"resident-source-cells-result/topic-1-chat-0/hook/stdout").pathExists)) "previous actual hook exists"
    let input ← read (base/"resident-source-cells.json")
    let root := base/"resident-source-cells2-result"
    check (!(← root.pathExists)) "preserve delivery retry evidence"
    let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
    let probes ← probes.mapM fun probe => do
      let cell := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
      return probe.setObjVal! "destination" (toJson (root/cell).toString)
    let path := base/"resident-source-cells2.json"
    write path (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
    guard "resident-source-cells2" #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"resident-source-auditor-build/StudyMain").toString,
      "cells",path.toString]
  | ["seal-installed"] =>
    drained
    let path := base/"resident-source-prefix/libexec/eggshell"
    let digest ← hash (build/"StudyMain")
    check (digest == (← hash path)) "installed product differs"
    let link := path.withExtension "shared"
    check (!(← link.pathExists)) "sharing temporary exists"
    discard <| command "/bin/ln" #[(build/"StudyMain").toString,link.toString]
    IO.FS.rename link path
    write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sharesImmutableProductInode",toJson true)])
    let component ← read (base/"resident-source-component1-result.json")
    check (component.getObjValD "allPassed" == toJson true) "component check failed"
    write (folder/"component.json") component
  | _ => throw (IO.userError "unknown resident source operation")
end ResidentSourceStudy
def main := ResidentSourceStudy.main
