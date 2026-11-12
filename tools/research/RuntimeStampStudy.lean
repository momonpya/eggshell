import tools.research.StudyLocal
open Lean StudyLocal
namespace RuntimeStampStudy
def parent := base/"practical-runtime/hook-command"
def root := base/"practical-runtime/runtime-stamp"
def records := project/"docs/candidates/runtime-stamp"
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh runtime-stamp candidate required"
  check ((← hash (parent/"build/StudyMain")) == "ea5b3861dfba62fe0e600552a13facb59595304c67b28fa9f2d3f395d66e0e35")
    "fixed runtime-stamp parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  let path := root/"source/Eggshell/PublicationWire.lean"
  let before ← IO.FS.readFile path
  let marker := "def implementation : String := "
  let [first,rest] := before.splitOn marker | throw (IO.userError "unique publication identity required")
  let [expression,last] := rest.splitOn "\ninitialize runtimeGeneration" |
    throw (IO.userError "unique publication initialization required")
  let expression := "\n".intercalate (expression.trimAscii.toString.splitOn "\n" |>.map ("    "++·))
  let after := first.replace "module\n" "module\nmeta import Lean\n" ++
    "run_cmd do\n  let value : String :=\n"++expression++
    "\n  let name := Lean.mkIdent `implementation\n"++
    "  Lean.Elab.Command.elabCommand (← `(def $name : String := $(Lean.quote value)))\n"++
    "\ninitialize runtimeGeneration"++last
  IO.FS.writeFile path after
  let delta ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/PublicationWire.lean",
    "-L","b/Eggshell/PublicationWire.lean",(parent/"source/Eggshell/PublicationWire.lean").toString,path.toString]}
  check (delta.exitCode == 1) "publication identity patch absent"
  IO.FS.writeFile (records/"candidate.patch") delta.stdout
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("sourceSha256",toJson (← hash path)),("identityAlgorithmChanged",toJson false),
    ("literalRuntimeBodyRequired",toJson true),("nativeReferenceComparisonRequired",toJson true),
    ("minimumPerPairSavingKiBForGrowth",toJson (8192 : Nat)),
    ("rankingOrBudgetChanged",toJson false),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  copyLocalArtifacts (parent/"build") (root/"build")
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.StudyMain")
  write (root/"settings.json") settings
  guard "runtime-stamp-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def repairMeta : IO Unit := do
  idle
  let rejected ← read (base/"runtime-stamp-build.guard.json")
  check (rejected.getObjValD "state" == toJson "finished" &&
    rejected.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    rejected.getObjValD "exitCode" != toJson (0 : Nat)) "only repair the stopped meta elaboration"
  let path := root/"source/Eggshell/PublicationWire.lean"
  write (records/"meta-rejection.json") (Json.mkObj [("guard",rejected),
    ("sourceSha256",toJson (← hash path)),
    ("compilerOutput",toJson (← IO.FS.readFile (root/"build/Eggshell_PublicationWire-lean.stdout"))),
    ("compilerError",toJson (← IO.FS.readFile (root/"build/Eggshell_PublicationWire-lean.stderr")))])
  let before ← IO.FS.readFile path
  let after := before.replace "meta import Lean\n" "meta import Lean\npublic meta import Eggshell.CanonicalSourceCache\npublic meta import Eggshell.SynapseIndex\n"
    |>.replace "/-- Installation paths" "/- Installation paths"
  check (before != after) "meta phase correction absent"
  IO.FS.writeFile path after
  guard "runtime-stamp-meta-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def audit : IO Unit := do
  idle
  if ← (records/"literal-audit.json").pathExists then
    let previous ← read (records/"literal-audit.json")
    check (previous.getObjValD "exitCode" != toJson (0 : Nat)) "preserve the completed declaration audit"
    if ← (records/"literal-audit-rejection.json").pathExists then
      check ((← read (records/"literal-audit-rejection.json")) == previous) "retain the first declaration failure"
    else write (records/"literal-audit-rejection.json") previous
  write (records/"build.guard.json") (← finished "runtime-stamp-meta-build")
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  unless ← (records/"native.json").pathExists do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditing.toString,
      "inspect",(root/"build").toString,(records/"native.json").toString]
  let path := root/"source/Eggshell/PublicationWire.lean"
  unless ← (records/"sources.json").pathExists do
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditing.toString,
      "compare-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString,
      "Eggshell.PublicationWire","@"++(← hash path)++":"++path.toString]
  check ((← read (records/"native.json")).getObjValD "consistent" == toJson true &&
    (← read (records/"sources.json")).getObjValD "candidateRuntimeSha256" == toJson (← hash (root/"build/StudyMain")))
    "native source audit changed before the declaration-only correction"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true",(project/"tools/research/RuntimeStampAudit.lean").toString]
    env := #[("LEAN_PATH",some (root/"build/lib").toString)]}
  write (records/"literal-audit.json") (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
    ("stdout",toJson result.stdout),("stderr",toJson result.stderr),
    ("sourceSha256",toJson (← hash (project/"tools/research/RuntimeStampAudit.lean")))])
  check (result.exitCode == 0 && result.stderr.isEmpty) "compiled stamp declaration audit failed"
  let delta ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/PublicationWire.lean",
    "-L","b/Eggshell/PublicationWire.lean",(parent/"source/Eggshell/PublicationWire.lean").toString,path.toString]}
  check (delta.exitCode == 1) "publication stamp source change absent"
  IO.FS.writeFile (records/"candidate.patch") delta.stdout
def prepareChecks : IO Unit := do
  idle
  check ((← read (records/"native.json")).getObjValD "consistent" == toJson true &&
    (← read (records/"sources.json")).getObjValD "exactExpectedChangeSet" == toJson true &&
    (← read (records/"literal-audit.json")).getObjValD "exitCode" == toJson (0 : Nat))
    "audit the compiled literal and unchanged product before observing it"
  let original ← IO.FS.readFile (parent/"source/Eggshell/PublicationWire.lean")
  let [_,rest] := original.splitOn "def implementation : String := " | throw (IO.userError "missing reference expression")
  let [expression,_] := rest.splitOn "\ninitialize runtimeGeneration" | throw (IO.userError "missing reference end")
  let code := "module\npublic import Eggshell.PublicationWire\n@[expose] public section\n"++
    "namespace Eggshell.Plugin.Publication\nopen Lean DB Synapses\n"++
    "def reference : String := "++expression++"\n"++
    "def main (args : List String) : IO Unit := do\n"++
    "  let [output] := args | throw (IO.userError \"reference output path required\")\n"++
    "  let actual ← generation\n"++
    "  unless actual == reference do throw (IO.userError \"compiled source stamp differs from native reference\")\n"++
    "  IO.FS.writeFile (.mk output) (Json.mkObj [(\"sameAlgorithmAndCurrentSource\",toJson true),\n"++
    "    (\"actual\",toJson actual),(\"nativeReference\",toJson reference),\n"++
    "    (\"answeringModelCalls\",toJson (0 : Nat))]).compress\n"++
    "end Eggshell.Plugin.Publication\n"++
    "def main := Eggshell.Plugin.Publication.main\n"
  IO.FS.writeFile (root/"source/Eggshell/RuntimeStampChecks.lean") code
  IO.FS.writeFile (records/"RuntimeStampChecks.lean") code
  for name in ["StudyLocal","HookCommandChecks"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  for (name,mainModule) in [("reference-build","Eggshell.RuntimeStampChecks"),("probe-build","tools.research.HookCommandChecks")] do
    copyLocalArtifacts (root/"build") (root/name)
    let settings := (← read (root/"build/build.json")).getObjValD "settings"
      |>.setObjVal! "output" (toJson (root/name).toString)
      |>.setObjVal! "parents" (toJson #[(root/"build").toString])
      |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
      |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
      |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
      |>.setObjVal! "mainModule" (toJson mainModule)
    write (root/(name++".json")) settings
  guard "runtime-stamp-reference-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"reference-build.json").toString]
def prepareProbe : IO Unit := do
  idle
  write (records/"reference-build.guard.json") (← finished "runtime-stamp-reference-visible-build")
  guard "runtime-stamp-probe-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"probe-build.json").toString]
def reference : IO Unit := do
  idle
  discard <| finished "runtime-stamp-reference-visible-build"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"reference-build").toString,
    (records/"reference-native.json").toString]
  guard "runtime-stamp-reference" #["/usr/bin/env","-u","LEAN_NUM_THREADS",(root/"reference-build/StudyMain").toString,
    (records/"reference.json").toString]
def repairReference : IO Unit := do
  idle
  let stopped ← read (base/"runtime-stamp-reference-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" != toJson (0 : Nat)) "only repair a stopped reference visibility error"
  let path := root/"source/Eggshell/RuntimeStampChecks.lean"
  write (records/"reference-rejection.json") (Json.mkObj [("guard",stopped),
    ("sourceSha256",toJson (← hash path)),
    ("stdout",toJson (← IO.FS.readFile (root/"reference-build/Eggshell_RuntimeStampChecks-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"reference-build/Eggshell_RuntimeStampChecks-lean.stderr"))),
    ("productChanged",toJson false)])
  let before ← IO.FS.readFile path
  let after := before.replace "\nimport Eggshell.PublicationWire\n" "\npublic import Eggshell.PublicationWire\n"
  check (before != after) "reference visibility correction absent"
  IO.FS.writeFile path after
  IO.FS.writeFile (records/"RuntimeStampChecks.lean") after
  guard "runtime-stamp-reference-visible-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"reference-build.json").toString]
def probe : IO Unit := do
  idle
  write (records/"probe-build.guard.json") (← finished "runtime-stamp-probe-owned-build")
  write (records/"reference.guard.json") (← finished "runtime-stamp-reference")
  check ((← read (records/"reference.json")).getObjValD "sameAlgorithmAndCurrentSource" == toJson true)
    "the literal must agree with independent native computation"
  IO.FS.createDirAll (root/"command-build")
  discard <| command "/bin/ln" #["-s",(parent/"command-build/StudyMain").toString,(root/"command-build/StudyMain").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"probe-build").toString,
    (records/"probe-native.json").toString]
  write (records/"probe-plan.json") (Json.mkObj [("order",toJson #["parent","candidate","candidate","parent"]),
    ("sameSupervisorSha256",toJson (← hash (parent/"command-build/StudyMain"))),
    ("parentBackendSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("candidateBackendSha256",toJson (← hash (root/"build/StudyMain"))),
    ("controllerSha256",toJson (← hash (root/"probe-build/StudyMain"))),
    ("componentMeasurementOnly",toJson true),("minimumSavingKiB",toJson (8192 : Nat))])
  guard "runtime-stamp-probe" #[(root/"probe-build/StudyMain").toString,root.toString,"component-probe","footprint",
    (root/"build/StudyMain").toString,(parent/"command-build/StudyMain").toString,(parent/"build/StudyMain").toString]
def repairProbe : IO Unit := do
  idle
  let stopped ← read (base/"runtime-stamp-probe-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    stopped.getObjValD "exitCode" != toJson (0 : Nat)) "repair only the stopped observer compiler error"
  let path := root/"source/tools/research/HookCommandChecks.lean"
  write (records/"probe-rejection.json") (Json.mkObj [("guard",stopped),("sourceSha256",toJson (← hash path)),
    ("stdout",toJson (← IO.FS.readFile (root/"probe-build/tools_research_HookCommandChecks-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"probe-build/tools_research_HookCommandChecks-lean.stderr"))),
    ("productChanged",toJson false)])
  IO.FS.writeFile path (← IO.FS.readFile (project/"tools/research/HookCommandChecks.lean"))
  guard "runtime-stamp-probe-owned-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"probe-build.json").toString]
def prepareReady : IO Unit := do
  idle
  write (records/"unphased-probe.guard.json") (← finished "runtime-stamp-probe")
  let receipts := root/"component-probe/footprint-1/data/receipts"
  let entries ← receipts.readDir
  check (entries.size == 1) "one original candidate ingress witness required"
  let some entry := entries[0]? | throw (IO.userError "missing candidate ingress directory")
  let ingress ← read (entry.path/"ingress.json")
  let published ← read (entry.path/"published.json")
  let start : Nat ← IO.ofExcept ((published.getObjValD "data").getObjValAs? _ "startedMs")
  let observed : Nat ← IO.ofExcept (ingress.getObjValAs? _ "observedMs")
  let old ← IO.ofExcept ((← read (records/"footprint.json")).getObjValAs? (Array Json) "probes")
  let samples : Array (Nat × Array (Nat × Nat × Nat)) ← IO.ofExcept (old[1]!.getObjValAs? _ "samples")
  check (observed ≥ start && observed-start > samples.back!.1) "cold first observation was not entirely before ingress"
  write (records/"unphased-rejection.json") (Json.mkObj [("ingress",ingress),("publication",published),
    ("ingressAfterSupervisorStartMs",toJson (observed-start)),
    ("lastSampleAfterObserverSpawnMs",toJson samples.back!.1),
    ("reason",toJson "all first-candidate samples preceded initialized backend ingress"),
    ("performanceSuccess",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/HookCommandChecks.lean")
    (← IO.FS.readFile (project/"tools/research/HookCommandChecks.lean"))
  write (records/"ready-plan.json") (Json.mkObj [("minimumSavingKiB",toJson (8192 : Nat)),
    ("sameSupervisorSha256",toJson (← hash (parent/"command-build/StudyMain"))),
    ("parentBackendSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("candidateBackendSha256",toJson (← hash (root/"build/StudyMain"))),
    ("measurement",toJson "100-700 ms after backend ingress; minimum 200 ms of samples"),
    ("productOrGuardChanged",toJson false),("actualProjectQueries",toJson (0 : Nat))])
  guard "runtime-stamp-ready-probe-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"probe-build.json").toString]
def readyProbe : IO Unit := do
  idle
  write (records/"ready-probe-build.guard.json") (← finished "runtime-stamp-ready-probe-build")
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"probe-build").toString,
    (records/"ready-probe-native.json").toString]
  guard "runtime-stamp-ready-probe" #[(root/"probe-build/StudyMain").toString,root.toString,"ready-component-probe","ready-footprint",
    (root/"build/StudyMain").toString,(parent/"command-build/StudyMain").toString,(parent/"build/StudyMain").toString]
def conclude : IO Unit := do
  idle
  check (!(← (records/"result.json").pathExists)) "retain the first runtime-stamp result"
  let plan ← read (records/"ready-plan.json")
  check (plan.getObjValD "sameSupervisorSha256" == toJson (← hash (parent/"command-build/StudyMain")) &&
    plan.getObjValD "parentBackendSha256" == toJson (← hash (parent/"build/StudyMain")) &&
    plan.getObjValD "candidateBackendSha256" == toJson (← hash (root/"build/StudyMain")))
    "ready observation inputs changed"
  let rows ← IO.ofExcept ((← read (records/"ready-footprint.json")).getObjValAs? (Array Json) "probes")
  check (rows.size == 4) "four initialized observations required"
  let mut peaks : Array Nat := #[]
  for index in [:rows.size] do
    let row := rows[index]!
    check (row.getObjValD "candidateClient" == toJson (index == 1 || index == 2) &&
      row.getObjValD "stderr" == toJson "" && row.getObjValD "ingress" != Json.null)
      "initialized comparison order, readiness or stderr changed"
    peaks := peaks.push (← IO.ofExcept (row.getObjValAs? Nat "pairPeakRssKiB"))
  let saving := #[Int.ofNat peaks[0]!-Int.ofNat peaks[1]!,Int.ofNat peaks[3]!-Int.ofNat peaks[2]!]
  let minimum : Nat ← IO.ofExcept (plan.getObjValAs? _ "minimumSavingKiB")
  check (!(saving.all (· ≥ Int.ofNat minimum))) "retain the observed failed growth-admission gate"
  let mut guards := #[]
  for tag in ["build","meta-build","reference-build","reference-visible-build","probe-build","probe-owned-build",
      "reference","probe","ready-probe-build","ready-probe"] do
    let record ← read (base/("runtime-stamp-"++tag++".guard.json"))
    check (record.getObjValD "state" == toJson "finished" && record.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "a runtime-stamp stage is not terminal and drained"
    guards := guards.push (tag,record)
  write (records/"guard-records.json") (toJson guards)
  write (records/"result.json") (Json.mkObj [("pairedSavingKiB",toJson saving),("minimumSavingKiB",toJson minimum),
    ("growthAdmissionPassed",toJson false),("mixedGrowthRetried",toJson false),
    ("unphasedComparisonRetainedAsInvalid",toJson true),
    ("literalBodyAudited",toJson true),("independentNativeReference",← read (records/"reference.json")),
    ("candidateBackendSha256",plan.getObjValD "candidateBackendSha256"),
    ("parentBackendSha256",plan.getObjValD "parentBackendSha256"),
    ("supervisorSha256",plan.getObjValD "sameSupervisorSha256"),
    ("actualProjectQueries",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  write (records/"cleanup-plan.json") (toJson #[root.toString])
end RuntimeStampStudy
def main : List String → IO Unit
  | ["prepare"] => RuntimeStampStudy.prepare
  | ["repair-meta"] => RuntimeStampStudy.repairMeta
  | ["audit"] => RuntimeStampStudy.audit
  | ["prepare-checks"] => RuntimeStampStudy.prepareChecks
  | ["prepare-probe"] => RuntimeStampStudy.prepareProbe
  | ["repair-reference"] => RuntimeStampStudy.repairReference
  | ["reference"] => RuntimeStampStudy.reference
  | ["probe"] => RuntimeStampStudy.probe
  | ["repair-probe"] => RuntimeStampStudy.repairProbe
  | ["prepare-ready"] => RuntimeStampStudy.prepareReady
  | ["ready-probe"] => RuntimeStampStudy.readyProbe
  | ["conclude"] => RuntimeStampStudy.conclude
  | _ => throw (IO.userError "RuntimeStampStudy prepare|repair-meta|audit|prepare-checks|repair-reference|prepare-probe|repair-probe|reference|probe|prepare-ready|ready-probe|conclude")
