import tools.research.StudyLocal
open Lean StudyLocal
namespace ProductEntryStudy

def practical := base/"practical-runtime"
def parent := practical/"independent-maintenance"
def root := practical/"product-entry"
def records := project/"docs/candidates/product-entry"
def fixedParent := "bd9096c4378e207b22e1ad48de5906f6967cf7dbbcb1c12722bfc6ce6bb25707"

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← (records/"plan.json").pathExists)) "fresh product entry required"
  check ((← hash (parent/"build/StudyMain")) == fixedParent) "sealed parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,(root/"prefix").toString]
  let entry ← IO.FS.readFile (records/"ProductMain.lean")
  IO.FS.writeFile (root/"source/ProductMain.lean") entry
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "ProductMain")
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"build-settings.json") settings
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson fixedParent),
    ("changedProductModules",toJson (#[] : Array String)),("newEntry",toJson "ProductMain"),
    ("startupOrder",toJson #["parent","candidate","candidate","parent"]),("startupWaves",toJson (4 : Nat)),
    ("rankingChanged",toJson false),("workerLimitsChanged",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "product-entry-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def configure : IO Unit := do
  idle
  discard <| finished "product-entry-build"
  let executable := root/"prefix/libexec/eggshell"
  check ((← executable.symlinkMetadata).type == .symlink &&
    (← IO.FS.realPath executable) == (← IO.FS.realPath (parent/"build/StudyMain"))) "unexpected copied product alias"
  IO.FS.removeFile executable
  discard <| command "/bin/ln" #["-s",(root/"build/StudyMain").toString,executable.toString]
  let before ← read (parent/"installation.json")
  let mut files := #[]
  for file in ← IO.ofExcept (before.getObjValAs? (Array Json) "pluginFiles") do
    let old ← IO.ofExcept (file.getObjValAs? String "path")
    let sourcePrefix := (parent/"prefix").toString++"/"
    check (old.startsWith sourcePrefix) "plugin artifact escaped its parent prefix"
    let path := root/"prefix"/(old.drop sourcePrefix.length |>.toString)
    check (toJson (← hash path) == file.getObjValD "sha256") "copied hook registration changed"
    files := files.push (file.setObjVal! "path" (toJson path.toString))
  let env : Array (String × Option String) ← IO.ofExcept (fromJson? (before.getObjValD "environment"))
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),
    ("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"run/data").toString),("TMPDIR",some (root/"tmp").toString)]
  let env := env.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
  IO.FS.createDirAll (root/"tmp")
  let installation := before
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson executable.toString),("sha256",toJson (← hash executable))])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson env)
  check (!(← (root/"installation.json").pathExists)) "preserve sealed product entry"
  write (root/"installation.json") installation
  write (records/"identity.json") (Json.mkObj [("parentSha256",toJson fixedParent),
    ("runtime",installation.getObjValD "runtime"),("globalInstallChanged",toJson false)])
  guard "product-entry-startup" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/ProductEntryStudy.lean").toString,"__startup"]

def startup : IO Unit := do
  let installation ← read (root/"installation.json")
  check ((← hash (parent/"build/StudyMain")) == fixedParent) "startup parent changed"
  let runtime := root/"build/StudyMain"
  check (toJson (← hash runtime) == (installation.getObjValD "runtime").getObjValD "sha256") "startup candidate changed"
  let mut observations := #[]
  let mut reference : Option String := none
  for wave in [:4] do
    for label in ["parent","candidate","candidate","parent"] do
      let path := if label == "parent" then parent/"build/StudyMain" else runtime
      let started ← IO.monoMsNow
      let output ← IO.Process.output {cmd := "/usr/bin/time",args := #["-l",path.toString,"--help"]}
      let elapsed := (← IO.monoMsNow)-started
      check (output.exitCode == 0 && !output.stdout.isEmpty) "native help startup failed"
      if let some expected := reference then check (output.stdout == expected) "product help changed"
      else reference := some output.stdout
      observations := observations.push (Json.mkObj [("wave",toJson (wave+1)),("runtime",toJson label),
        ("elapsedMs",toJson elapsed),("time",toJson output.stderr),("exitCode",toJson output.exitCode.toNat)])
  let identity := Json.mkObj [("parentSha256",toJson fixedParent),("candidateSha256",toJson (← hash runtime)),
    ("parentBytes",toJson (← (parent/"build/StudyMain").metadata).byteSize),
    ("candidateBytes",toJson (← runtime.metadata).byteSize),
    ("observations",toJson observations),("stdout",toJson reference),
    ("testsHelpOnly",toJson true),("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)]
  write (records/"startup.json") identity
  IO.println identity.compress

def audit : IO Unit := do
  idle
  discard <| finished "product-entry-build"
  let auditing := project/"tools/research/StudyBuildClosureAudit.lean"
  let runAudit := fun args => command (compiler/"bin/lean").toString
    (#["-j1","-M768","--run",auditing.toString] ++ args)
  IO.println (← runAudit #["inspect",(root/"build").toString,(records/"native.json").toString])
  IO.println (← runAudit #["subset-sources",(parent/"build").toString,(root/"build").toString,
    (records/"sources.json").toString,"Main","Eggshell.HookFrontend","Eggshell.PublicationService",
    "Eggshell.Handoff","Eggshell.GraphStore","Eggshell.SynapseJournal","Eggshell.SearchProvider"])
  let law := root/"entry-law.lean"
  IO.FS.writeFile law "import ProductMain\n#print axioms product_entry_dispatch\n"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M2048",law.toString],
    env := #[("LEAN_PATH",some ((root/"build/lib").toString++":"++(compiler/"lib/lean").toString))]}
  IO.FS.writeFile (records/"laws.txt") (result.stdout++result.stderr)
  check (result.exitCode == 0 && result.stderr.isEmpty) "entry dispatch proof failed"

def main : List String → IO Unit
  | ["prepare"] => prepare
  | ["configure"] => configure
  | ["__startup"] => startup
  | ["audit"] => audit
  | _ => throw (IO.userError "ProductEntryStudy prepare|configure")
end ProductEntryStudy
def main := ProductEntryStudy.main
