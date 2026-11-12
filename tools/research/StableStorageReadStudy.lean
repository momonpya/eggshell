import tools.research.StudyLocal
open Lean StudyLocal
namespace StableStorageReadStudy
def parent := base/"practical-runtime/terminal-closure"
def root := base/"practical-runtime/stable-storage-read"
def records := project/"docs/candidates/stable-storage-read"
def guard (tag : String) (args : Array String) : IO Unit := do
  StudyLocal.guard tag args
  let path := base/(tag++".guard-settings.json")
  write path ((← read path).setObjVal! "ownedPrefixes" (toJson #[root.toString]))
def settings (output : System.FilePath) (entry : String) (inherited : System.FilePath) : IO Json := do
  return (← read (inherited/"build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "parents" (toJson #[inherited.toString])
    |>.setObjVal! "baselineResponse" (toJson (inherited/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (inherited/"tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (inherited/"object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson entry)
    |>.setObjVal! "force" (toJson (#[] : Array String))
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh isolated storage candidate required"
  check ((← hash (parent/"build/StudyMain")) == "302ead2043af3ba3764668652f5543cdf330ca0dae16ac27784b7536ab116338")
    "fixed parent changed"
  discard <| finished "automatic-publication-postmortem"
  check ((← read (project/"docs/practical-runtime/automatic-publication/checked-summary.json")).getObjValD
    "allHookCallbacksClean" == toJson false) "preserve the failing hook before changing its reader"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("samePinnedDescriptor",toJson true),("attempts",toJson (3 : Nat)),
    ("retainFullVersionComparison",toJson true),("sourceFreshnessUnchanged",toJson true),
    ("readLocksAdded",toJson false),("sleepAdded",toJson false),("arbitraryIoErrorsCaught",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  write (root/"build-settings.json") (← settings (root/"build") "tools.research.StudyMain" (parent/"build"))
def build : IO Unit := do
  idle
  let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L","a/Eggshell/FileSystem.lean",
    "-L","b/Eggshell/FileSystem.lean",(parent/"source/Eggshell/FileSystem.lean").toString,
    (root/"source/Eggshell/FileSystem.lean").toString]}
  check (result.exitCode == 1) "declared storage fix absent"
  IO.FS.writeFile (records/"candidate.patch") result.stdout
  guard "stable-storage-read-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]
def audit : IO Unit := do
  idle
  discard <| finished "stable-storage-read-build"
  for args in [#["inspect",(root/"build").toString,(records/"native.json").toString],
      #["compare-sources",(parent/"build").toString,(root/"build").toString,
        (records/"sources.json").toString,"Eggshell.FileSystem"]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
def prepareChecks : IO Unit := do
  idle
  discard <| finished "stable-storage-read-build"
  IO.FS.writeFile (root/"source/tools/research/StableStorageReadChecks.lean")
    (← IO.FS.readFile (project/"tools/research/StableStorageReadChecks.lean"))
  IO.FS.writeFile (root/"source/tools/research/AutomaticPublicationChecks.lean")
    (← IO.FS.readFile (project/"tools/research/AutomaticPublicationChecks.lean"))
  copyLocalArtifacts (root/"build") (root/"checks-build")
  write (root/"checks-build-settings.json") (← settings (root/"checks-build") "tools.research.StableStorageReadChecks" (root/"build"))
  guard "stable-storage-read-checks-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"checks-build-settings.json").toString]
def runChecks : IO Unit := do
  idle
  discard <| finished "stable-storage-read-checks-build"
  unless ← (records/"checks-native.json").pathExists do
    IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/"checks-build").toString,
      (records/"checks-native.json").toString])
  check ((← read (records/"checks-native.json")).getObjValD "consistent" == toJson true) "native diagnostic closure must pass"
  if ← (records/"checks-sources.json").pathExists then
    check ((← read (records/"checks-sources.json")).getObjValD "failures" == toJson #["tools.research.AutomaticPublicationChecks"])
      "only the newly shared fixture library may extend the diagnostic closure"
    write (records/"audit-correction.json") (Json.mkObj [("reason",toJson "the strict subset audit rejects the new shared fixture library; check all product core plus its exact added source separately"),
      ("oldAuditRetained",toJson true),("nativeChecksExecuted",toJson (0 : Nat)),("productChanged",toJson false)])
  for args in [#["common-sources",(root/"build").toString,(root/"checks-build").toString,
        (records/"checked-common-sources.json").toString]] do
    IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
      (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args))
  let mut checked := #[]
  for name in ["AutomaticPublicationChecks","StableStorageReadChecks"] do
    let stamp ← read (root/"checks-build"/("tools_research_"++name++".source"))
    let (text,literals) : String × Array (String × String) ← IO.ofExcept (fromJson? stamp)
    check (text == (← IO.FS.readFile (project/"tools/research"/(name++".lean"))) && literals.isEmpty)
      "native diagnostic source differs from its exact retained fixture"
    checked := checked.push (Json.mkObj [("module",toJson ("tools.research."++name)),
      ("sourceSha256",toJson (← hash (project/"tools/research"/(name++".lean"))))])
  write (records/"checked-fixture-sources.json") (toJson checked)
  guard "stable-storage-read-checks" #[(root/"checks-build/StudyMain").toString,"checks",
    (root/"checks").toString,(records/"checks.json").toString]
def install : IO Unit := do
  idle
  discard <| finished "stable-storage-read-checks"
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/TerminalIntentStudy.lean").toString,"install-at",root.toString,parent.toString,records.toString])
def automatic : IO Unit := do
  idle
  discard <| finished "stable-storage-read-checks"
  let installation ← read (root/"installation.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (installation.getObjValD "environment"))
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := environment.filterMap fun (key,value) => value.map (fun value => key++"="++value)
  guard "stable-storage-read-automatic" (#["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "automatic",(records/"flow.stdout").toString,(records/"flow.stderr").toString,"/usr/bin/env"]++
    unset.flatMap (fun key => #["-u",key])++assigned++#[(root/"checks-build/StudyMain").toString,
      "automatic",(root/"installation.json").toString,(root/"run").toString])
def fingerprints : IO Unit := do
  idle
  discard <| finished "stable-storage-read-automatic"
  guard "stable-storage-read-fingerprints" #[(root/"checks-build/StudyMain").toString,"fingerprints",
    (root/"run").toString,(records/"source-fingerprints.json").toString]
def retain : IO Unit := do
  idle
  discard <| finished "stable-storage-read-fingerprints"
  IO.println (← command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retain-at",root.toString,records.toString,
    "stable-storage-read-automatic",(records/"source-fingerprints.json").toString,"1"])
def proofAudit : IO Unit := do
  idle
  discard <| finished "stable-storage-read-build"
  let names := ["storage_image_unchanged","storage_image_complete","storage_image_bounded",
    "mutated_storage_image_rejected","incomplete_storage_image_rejected","oversized_storage_image_rejected",
    "stable_read_identity","replaced_read_rejected","mutated_read_rejected","bounded_read_original"]
  IO.FS.writeFile (root/"laws.lean") ("import Eggshell.FileSystem\n"++String.join (names.map fun name =>
    "#print axioms Eggshell.FileSystem."++name++"\n"))
  guard "stable-storage-read-laws" #["/bin/sh","-c",
    "captured_stdout=$1; captured_stderr=$2; shift 2; exec \"$@\" >\"$captured_stdout\" 2>\"$captured_stderr\"",
    "kernel-axioms",(records/"laws.txt").toString,(records/"laws.stderr").toString,"/usr/bin/env",
    "LEAN_PATH="++(root/"build/lib").toString++":"++(compiler/"lib/lean").toString,
    (compiler/"bin/lean").toString,"-j1","-M2048",(root/"laws.lean").toString]
def retire : IO Unit := do
  idle
  let tags := #["build","checks-build","checks","automatic","fingerprints","laws"]
  IO.println (← command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
    (project/"tools/research/AutomaticPublicationStudy.lean").toString,"retire-product-at",root.toString,records.toString]++
    tags.map ("stable-storage-read-"++·)))
end StableStorageReadStudy
def main : List String → IO Unit
  | ["prepare"] => StableStorageReadStudy.prepare
  | ["build"] => StableStorageReadStudy.build
  | ["audit"] => StableStorageReadStudy.audit
  | ["prepare-checks"] => StableStorageReadStudy.prepareChecks
  | ["checks"] => StableStorageReadStudy.runChecks
  | ["install"] => StableStorageReadStudy.install
  | ["automatic"] => StableStorageReadStudy.automatic
  | ["fingerprints"] => StableStorageReadStudy.fingerprints
  | ["retain"] => StableStorageReadStudy.retain
  | ["proof-audit"] => StableStorageReadStudy.proofAudit
  | ["retire"] => StableStorageReadStudy.retire
  | _ => throw (IO.userError "StableStorageReadStudy prepare|build|audit|prepare-checks|checks")
