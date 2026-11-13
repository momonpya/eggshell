import tools.research.StudyLocal
open Lean StudyLocal
namespace ProjectQueryReceiptStudy
def parent := base/"practical-runtime/source-snapshot"
def cohort := base/"practical-runtime/complete-delivery-cohort/cohort"
def root := base/"practical-runtime/project-query-receipt"
def records := project/"docs/candidates/project-query-receipt"
def binary := root/"build/StudyMain"
def observer := root/"observer/StudyMain"
def plan := root/"plan.json"
def audit (args : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]++args)
def checked : IO Unit := do
  check ((← hash (parent/"build/StudyMain")) == "720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534")
    "fixed product changed"
def environment (host : Bool := false) : IO (Array String) := do
  let installation := (← read plan).getObjValD "installation"
  let fields : Array (String × Option String) ← IO.ofExcept (installation.getObjValAs? _ "environment")
  let fields := fields.filter (·.1 != "EGGSHELL_DATA_ROOT")++#[
    ("EGGSHELL_DATA_ROOT",some (root/"case"/(if host then "host" else "client")).toString)]
  return #["/usr/bin/env"]++(fields.filterMap fun (key,value) => if value.isNone then some key else none).flatMap
    (fun key => #["-u",key])++(fields.filterMap fun (key,value) => value.map fun value => key++"="++value)
def prepare : IO Unit := do
  idle
  checked
  check (!(← root.pathExists) && !(← records.pathExists)) "preserve earlier query-receipt study"
  IO.FS.createDirAll records
  IO.FS.createDirAll root
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  let settings := (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
  write (root/"settings.json") settings
def build : IO Unit := do
  idle
  checked
  let before ← IO.FS.readFile (parent/"source/Eggshell/ProjectRead.lean")
  let after ← IO.FS.readFile (root/"source/Eggshell/ProjectRead.lean")
  check (before != after) "receipt observation patch must be explicit"
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",
    (parent/"source/Eggshell/ProjectRead.lean").toString,(root/"source/Eggshell/ProjectRead.lean").toString]}
  check (diff.exitCode == 1) "expected one source observation difference"
  IO.FS.writeFile (records/"ProjectRead.patch") diff.stdout
  guard "project-query-receipt-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"settings.json").toString]
def prepareObserver : IO Unit := do
  idle
  checked
  write (records/"build.guard.json") (← finished "project-query-receipt-build")
  audit #["inspect",(root/"build").toString,(records/"native.json").toString]
  audit #["compare-sources",(parent/"build").toString,(root/"build").toString,
    (records/"product-sources.json").toString,"Eggshell.ProjectRead"]
  copyLocalArtifacts (root/"build") (root/"observer")
  let checks ← IO.FS.readFile (project/"tools/research/LLVMProjectChecks.lean")
  let pieces := checks.splitOn "\ndef main :"
  check (pieces.length == 2) "native observer entry boundary changed"
  let source := pieces[0]!.replace "import tools.research.NativeSourceIntegrity\n" ""
  IO.FS.writeFile (root/"source/tools/research/LLVMProjectChecks.lean") (source++
    "\ndef main : List String → IO UInt32\n"++
    "  | [\"prepare\",input] => do LLVMProjectChecks.prepare input; return 0\n"++
    "  | [\"run\",input] => do LLVMProjectChecks.run input; return 0\n"++
    "  | [\"capture\",input,number] => do\n"++
    "    let some number := number.toNat? | throw (IO.userError \"natural topic required\")\n"++
    "    LLVMProjectChecks.diagnose input number\n    return 0\n"++
    "  | _ => throw (IO.userError \"project receipt prepare|run|capture\")\n")
  let settings := (← read (root/"settings.json"))
    |>.setObjVal! "output" (toJson (root/"observer").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.LLVMProjectChecks")
  write (root/"observer-settings.json") settings
  guard "project-query-receipt-observer-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"observer-settings.json").toString]
def setup : IO Unit := do
  idle
  checked
  write (records/"observer-build.guard.json") (← finished "project-query-receipt-observer-build")
  if !(← (records/"observer-native.json").pathExists) then
    audit #["inspect",(root/"observer").toString,(records/"observer-native.json").toString]
    audit #["common-sources",(root/"build").toString,(root/"observer").toString,(records/"observer-sources.json").toString]
  else
    let inspected ← read (records/"observer-native.json")
    let compared ← read (records/"observer-sources.json")
    check (inspected.getObjValD "consistent" == toJson true &&
      compared.getObjValD "commonSourcesUnchanged" == toJson true &&
      compared.getObjValD "auditorSha256" == toJson (← hash observer)) "previously inspected observer changed"
  if !(← (root/"prefix").pathExists) then
    discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,(root/"prefix").toString]
    IO.FS.removeFile (root/"prefix/libexec/eggshell")
    discard <| command "/bin/ln" #["-s",binary.toString,(root/"prefix/libexec/eggshell").toString]
  else
    check ((← IO.FS.realPath (root/"prefix/libexec/eggshell")) == binary) "partial prefix points outside its candidate"
    write (records/"setup-refusal.json") (Json.mkObj [("error",toJson "metadata setup requested nonexistent optional bin/eggshelld; native product has bin/egg and plugin-owned eggshelld"),
      ("databaseOrHookStarted",toJson false),("observerUnchanged",toJson true)])
  for name in ["bin/egg","plugins/eggshell/bin/egg","plugins/eggshell/bin/eggshelld"] do
    let path := root/"prefix"/name
    let text ← IO.FS.readFile path
    check ((← path.symlinkMetadata).type == .file) "copied launcher must be an owned regular file"
    IO.FS.writeFile path (text.replace (parent/"prefix").toString (root/"prefix").toString)
  let template ← read (parent/"installation.json")
  let files : Array Json ← IO.ofExcept (template.getObjValAs? _ "pluginFiles")
  let mut artifacts := #[]
  for file in files do
    let path ← IO.ofExcept (file.getObjValAs? String "path")
    let path := System.FilePath.mk (path.replace (parent/"prefix").toString (root/"prefix").toString)
    artifacts := artifacts.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path))])
  let fields : Array (String × Option String) ← IO.ofExcept (template.getObjValAs? _ "environment")
  let updates := #[("EGGSHELL_PREFIX",some (root/"prefix").toString),
    ("PLUGIN_ROOT",some (root/"prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"case/client").toString),("CODEX_HOME",some (root/"codex").toString),
    ("TMPDIR",some (root/"scratch").toString),("EGGSHELL_TRACE_SELECTOR_INPUT",none),
    ("EGGSHELL_TRACE_SELECTION_RANGES",none),("LEAN_NUM_THREADS",none)]
  let fields := fields.filter (fun row => !updates.any (·.1 == row.1))++updates
  let installation := template.setObjVal! "runtime" (Json.mkObj [
    ("path",toJson (root/"prefix/libexec/eggshell").toString),("sha256",toJson (← hash binary))])
    |>.setObjVal! "pluginRoot" (toJson (root/"prefix/plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson artifacts)
    |>.setObjVal! "handoffChars" (toJson (120000 : Nat))|>.setObjVal! "environment" (toJson fields)
  let seed ← read (project/"docs/practical-runtime/complete-delivery-cohort/seed-source-audit.json")
  check (seed.getObjValD "seedAccepted" == toJson true) "accepted fixed seed required"
  write plan (Json.mkObj [("installation",installation),("original",seed.getObjValD "publication"),
    ("originalFiles",seed.getObjValD "sourceFiles"),
    ("definitions",toJson (project/"docs/practical-runtime/complete-delivery-cohort/task-definitions.json").toString),
    ("workspace",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
    ("root",toJson (root/"case").toString),("records",toJson records.toString)])
  write (records/"plan.json") (← read plan)
  guard "project-query-receipt-freeze" ((← environment)++#[observer.toString,"prepare",plan.toString])
def run : IO Unit := do
  idle
  checked
  write (records/"freeze.guard.json") (← finished "project-query-receipt-freeze")
  let before ← read (records/"before-delivery.json")
  let control ← read (project/"docs/practical-runtime/complete-delivery-cohort/selector-input/before-delivery.json")
  let topics : Array Json ← IO.ofExcept (before.getObjValAs? _ "topics")
  let original : Array Json ← IO.ofExcept (control.getObjValAs? _ "topics")
  check (before.getObjValD "capturedHead" == control.getObjValD "capturedHead" &&
    topics.map (·.getObjValD "frozen") == original.map (·.getObjValD "frozen"))
    "source head or independently frozen evidence differs from the current-product control"
  guard "project-query-receipt-hooks" ((← environment)++#[observer.toString,"run",plan.toString])
def capture (number : Nat) : IO Unit := do
  idle
  checked
  write (records/"hooks.guard.json") (← finished "project-query-receipt-hooks")
  let current : Array Json ← IO.ofExcept ((← read (records/"result.json")).getObjValAs? _ "queries")
  let control : Array Json ← IO.ofExcept ((← read (project/"docs/practical-runtime/complete-delivery-cohort/selector-input/result.json")).getObjValAs? _ "queries")
  check (current.size == 6 && control.size == 6 && (current.zip control).all (fun (a,b) =>
    a.getObjValD "pass" == b.getObjValD "pass" && a.getObjValD "topic" == b.getObjValD "topic" &&
    a.getObjValD "bodySha256" == b.getObjValD "bodySha256" && a.getObjValD "semantic" == toJson "completed"))
    "observation-only runtime changed actual ordinary delivery"
  guard s!"project-query-receipt-capture-{number}" ((← environment true)++
    #[observer.toString,"capture",plan.toString,toString number])
def buildMembership : IO Unit := do
  idle
  checked
  for number in [1:4] do
    write (records/s!"capture-{number}.guard.json") (← finished s!"project-query-receipt-capture-{number}")
    let directory := records/(if number == 1 then "diagnostic" else s!"diagnostic-topic-{number}")
    check ((← read (directory/"validation.json")).getObjValD "sameOrdinaryBody" == toJson true)
      "selection input differs from actual ordinary delivery"
  IO.FS.writeFile (root/"source/tools/research/SelectionMembershipAudit.lean")
    (← IO.FS.readFile (project/"tools/research/SelectionMembershipAudit.lean"))
  let settings := (← read (root/"settings.json"))
    |>.setObjVal! "output" (toJson (root/"membership").toString)
    |>.setObjVal! "parents" (toJson #[(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (root/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (root/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (root/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.SelectionMembershipAudit")
  write (root/"membership-settings.json") settings
  guard "project-query-receipt-membership-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"membership-settings.json").toString]
def repairMembership : IO Unit := do
  idle
  let stopped ← read (base/"project-query-receipt-membership-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only repair the stopped metadata parser import"
  write (records/"membership-build-refusal.json") (Json.mkObj [("guard",stopped),
    ("compiler",toJson (← IO.FS.readFile (root/"membership/tools_research_SelectionMembershipAudit-lean.stdout"))),
    ("correction",toJson "explicitly import Lean.Data.Json.Parser; no source, query, product or scoring changed")])
  IO.FS.writeFile (root/"source/tools/research/SelectionMembershipAudit.lean")
    (← IO.FS.readFile (project/"tools/research/SelectionMembershipAudit.lean"))
  guard "project-query-receipt-membership-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"membership-settings.json").toString]
def runMembership (tag : String := "project-query-receipt-membership-build") : IO Unit := do
  idle
  discard <| finished tag
  audit #["inspect",(root/"membership").toString,(records/"membership-native.json").toString]
  audit #["component-sources",(root/"build").toString,(root/"membership").toString,
    (records/"membership-sources.json").toString,"Eggshell.Sha256","tools.SharedCoverageInput"]
  guard "project-query-receipt-membership" #[(root/"membership/StudyMain").toString,records.toString,
    (base/"practical-runtime/selector-input/originals.json").toString,(records/"membership.json").toString]
def packRecords : IO Unit := do
  idle
  checked
  write (records/"membership.guard.json") (← finished "project-query-receipt-membership")
  write (project/"docs/candidates/local-judgment/native-probe/download.guard.json")
    (← finished "local-judgment-native-assets")
  let retained := root/"captured-inputs"
  check (!(← retained.pathExists) && !(← (records/"bodies.json").pathExists))
    "preserve already packaged captured inputs"
  IO.FS.createDirAll retained
  let queries : Array Json ← IO.ofExcept ((← read (records/"result.json")).getObjValAs? _ "queries")
  let mut bodies : Array (String × String) := #[]
  let mut references := #[]
  let mut redundant := #[]
  for query in queries do
    let pass ← IO.ofExcept (query.getObjValAs? Nat "pass")
    let topic ← IO.ofExcept (query.getObjValAs? Nat "topic")
    let path := records/s!"pass-{pass}-topic-{topic}.txt"
    let digest ← hash path
    check (toJson digest == query.getObjValD "bodySha256") "ordinary body differs from actual receipt"
    let bytes ← IO.FS.readBinFile path
    let some body := String.fromUTF8? bytes | throw (IO.userError "body is not UTF-8")
    let restored ← IO.ofExcept ((← IO.ofExcept (Json.parse (toJson body).compress)).getStr?)
    check (restored.toUTF8 == bytes) "JSON preservation changed literal body bytes"
    unless bodies.any (·.1 == digest) do bodies := bodies.push (digest,body)
    references := references.push (path.toString,digest)
    redundant := redundant.push path
  let mut inputs := #[]
  for number in [1:4] do
    let name := if number == 1 then "diagnostic" else s!"diagnostic-topic-{number}"
    let directory := records/name
    let validation ← read (directory/"validation.json")
    check (validation.getObjValD "actualRegisteredHook" == toJson true &&
      validation.getObjValD "sameOrdinaryBody" == toJson true) "trace is not an ordinary actual hook"
    let bodyPath := directory/"body.txt"
    let digest ← hash bodyPath
    let some prior := bodies.find? (·.1 == digest) | throw (IO.userError "trace body absent from ordinary bodies")
    check ((← IO.FS.readBinFile bodyPath) == prior.2.toUTF8) "trace body is not byte equal"
    references := references.push (bodyPath.toString,digest)
    redundant := redundant.push bodyPath
    IO.FS.createDirAll (retained/name)
    let original := directory/"selection.json"
    let target := retained/name/"selection.json"
    let digest ← hash original
    let bytes := (← original.metadata).byteSize.toNat
    IO.FS.rename original target
    check ((← hash target) == digest && (← target.metadata).byteSize.toNat == bytes)
      "moving active captured input changed bytes"
    IO.FS.writeBinFile (retained/name/"validation.json") (← IO.FS.readBinFile (directory/"validation.json"))
    inputs := inputs.push (Json.mkObj [("original",toJson original.toString),
      ("active",toJson target.toString),("sha256",toJson digest),("bytes",toJson bytes)])
  for name in ["before-delivery.json","result.json"] do
    IO.FS.writeBinFile (retained/name) (← IO.FS.readBinFile (records/name))
  write (records/"captured-inputs.json") (Json.mkObj [("activeDirectory",toJson retained.toString),
    ("inputs",toJson inputs),("archived",toJson false),("neededForNextJudgmentStudy",toJson true)])
  write (records/"bodies.json") (Json.mkObj [("references",toJson references),
    ("utf8BodiesBySha256",toJson bodies),("literalBytesPreserved",toJson true)])
  for path in redundant do IO.FS.removeFile path
  guard "project-query-receipt-relocated-membership" #[(root/"membership/StudyMain").toString,
    retained.toString,(base/"practical-runtime/selector-input/originals.json").toString,
    (records/"membership-relocated.json").toString]
partial def removeOwned (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (1,0)
  for entry in ← path.readDir do
    let next ← removeOwned entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total
def retire : IO Unit := do
  idle
  checked
  write (records/"relocated-membership.guard.json") (← finished "project-query-receipt-relocated-membership")
  check ((← read (records/"membership.json")) == (← read (records/"membership-relocated.json")))
    "retained active inputs do not reproduce the independent audit"
  for entry in ← IO.ofExcept ((← read (records/"captured-inputs.json")).getObjValAs? (Array Json) "inputs") do
    let path ← IO.ofExcept (entry.getObjValAs? String "active")
    check (toJson (← hash (.mk path)) == entry.getObjValD "sha256") "active selector input changed"
  let originalFiles : Array (String × String) ← IO.ofExcept ((← read plan).getObjValAs? _ "originalFiles")
  let original ← IO.ofExcept ((← read plan).getObjValAs? String "original")
  for (name,digest) in originalFiles do
    check ((← hash (System.FilePath.mk original/name)) == digest) "accepted seed changed"
  audit #["inspect",(parent/"build").toString,(records/"retained-product-native.json").toString]
  let mut removed := #[]
  for name in ["case","source","build","observer","membership","prefix","scratch","codex"] do
    let path := root/name
    if ← path.pathExists then
      let counts ← removeOwned path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),
        ("entries",toJson counts.1),("logicalBytes",toJson counts.2)])
  write (records/"retired.json") (Json.mkObj [("removed",toJson removed),("archived",toJson false),
    ("activeCapturedInputsRetained",toJson true),("acceptedSeedUnchanged",toJson true),
    ("productSha256",toJson (← hash (parent/"build/StudyMain")))])
end ProjectQueryReceiptStudy
def main : List String → IO Unit
  | ["prepare"] => ProjectQueryReceiptStudy.prepare
  | ["build"] => ProjectQueryReceiptStudy.build
  | ["prepare-observer"] => ProjectQueryReceiptStudy.prepareObserver
  | ["setup"] => ProjectQueryReceiptStudy.setup
  | ["run"] => ProjectQueryReceiptStudy.run
  | ["capture",number] => do
    let some number := number.toNat? | throw (IO.userError "natural topic required")
    ProjectQueryReceiptStudy.capture number
  | ["build-membership"] => ProjectQueryReceiptStudy.buildMembership
  | ["run-membership"] => ProjectQueryReceiptStudy.runMembership
  | ["repair-membership"] => ProjectQueryReceiptStudy.repairMembership
  | ["run-membership-checked"] => ProjectQueryReceiptStudy.runMembership "project-query-receipt-membership-checked-build"
  | ["pack-records"] => ProjectQueryReceiptStudy.packRecords
  | ["retire"] => ProjectQueryReceiptStudy.retire
  | _ => throw (IO.userError "ProjectQueryReceiptStudy prepare|build|prepare-observer|setup")
