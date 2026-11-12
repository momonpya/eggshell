import tools.research.StudyLocal
open Lean StudyLocal
namespace HookPrimitiveStudy
def parent := base/"practical-runtime/hook-command"
def root := base/"practical-runtime/hook-primitives"
def records := project/"docs/candidates/hook-primitives"
def changes := #["Blake3","Sha256","Receipt","HookCommand","ProcessGroup","PublicationWire"]
def additions := #["Hex","ReceiptId"]
def settings (output mainModule : String) (cache : System.FilePath) : IO Json := do
  return (← read (cache/"build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/output).toString)
    |>.setObjVal! "parents" (toJson #[cache.toString])
    |>.setObjVal! "baselineResponse" (toJson (cache/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (cache/"tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (cache/"object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson mainModule)
def build (tag config : String) : IO Unit :=
  guard ("hook-primitives-"++tag) #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/config).toString]
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh hook primitive experiment required"
  check ((← hash (parent/"build/StudyMain")) == "ea5b3861dfba62fe0e600552a13facb59595304c67b28fa9f2d3f395d66e0e35")
    "hook primitive parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("allBytesHashAndIdentifierRefinementRequired",toJson true),
    ("searchOrRankingChanged",toJson false),("growthWaves",toJson (4 : Nat)),("maxClients",toJson (14 : Nat)),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
def patch : IO Unit := do
  let mut text := ""
  for name in changes++additions do
    let path := "Eggshell/"++name++".lean"
    let original := if additions.contains name then "/dev/null" else (parent/"source"/path).toString
    let label := if additions.contains name then "/dev/null" else "a/"++path
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","-L",label,"-L","b/"++path,
      original,(root/"source"/path).toString]}
    check (result.exitCode ≤ 1) "cannot retain primitive source changes"
    text := text++result.stdout
  IO.FS.writeFile (records/"candidate.patch") text
def client : IO Unit := do
  idle
  patch
  IO.FS.writeFile (root/"source/tools/research/HookCommandMain.lean")
    (← IO.FS.readFile (project/"tools/research/HookCommandMain.lean"))
  write (root/"client-settings.json") (← settings "command-build" "tools.research.HookCommandMain" (parent/"build"))
  build "client-build" "client-settings.json"
def inspect (folder output : String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",(root/folder).toString,(records/output).toString]
def auditClient : IO Unit := do
  idle
  discard <| finished "hook-primitives-client-build"
  inspect "command-build" "command-native.json"
  let mapping ← read (root/"command-build/object-mapping.json")
  let compiled ← IO.ofExcept ((← read (root/"command-build/build.json")).getObjValAs? (Array Json) "modules")
  let mut modules : Array String := #[]
  for line in (← IO.FS.readFile (root/"command-build/runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let name := (mapping.getObjValAs? String path).toOption.orElse fun _ =>
      (compiled.find? (·.getObjValD "object" == toJson path)).bind (fun row => (row.getObjValAs? String "module").toOption)
    if let some name := name then modules := modules.push name
  let forbidden := #["Eggshell.Receipt","Eggshell.FileSystem","Eggshell.Paths","Eggshell.Blake3","Eggshell.Worker",
    "Eggshell.Handoff","Eggshell.Daemon","Eggshell.SearchProvider","Eggshell.Numerical","Eggshell.PublicationService"]
  check (!(modules.any forbidden.contains) && modules.contains "Eggshell.Hex" && modules.contains "Eggshell.ReceiptId")
    "small client still imports storage, the other hash algorithm or a backend"
  write (records/"command-modules.json") (Json.mkObj [("modules",toJson modules),
    ("commandSha256",toJson (← hash (root/"command-build/StudyMain"))),
    ("storageOrBackendImports",toJson false)])
def proof : IO Unit := do
  idle
  let source := project/"tools/research/HookPrimitiveAudit.lean"
  let result ← IO.Process.output {
    cmd := (compiler/"bin/lean").toString
    args := #["-j1","-M768","-DwarningAsError=true",source.toString]
    env := #[("LEAN_PATH",some (root/"command-build/lib").toString)]}
  let output := if result.exitCode == 0 then "proofs.json" else "proof-rejection.json"
  check (!(← (records/output).pathExists)) "preserve previous proof evidence"
  write (records/output) (Json.mkObj [("exitCode",toJson result.exitCode.toNat),("sourceSha256",toJson (← hash source)),
    ("stdout",toJson result.stdout),("stderr",toJson result.stderr)])
  check (result.exitCode == 0 && result.stderr.isEmpty && !result.stdout.contains "sorryAx" &&
    !result.stdout.contains "Lean.trustCompiler" && !result.stdout.contains "Lean.ofReduceBool") "primitive refinement audit failed"
def prepareRunner : IO Unit := do
  idle
  for name in ["StudyLocal","HookCommandChecks"] do
    IO.FS.writeFile (root/"source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  write (root/"probe-settings.json") (← settings "probe-build" "tools.research.HookCommandChecks" (parent/"build"))
  build "probe-build" "probe-settings.json"
def probe : IO Unit := do
  idle
  discard <| finished "hook-primitives-probe-build"
  inspect "probe-build" "probe-native.json"
  write (records/"probe-plan.json") (Json.mkObj [("order",toJson #["baseline","candidate","candidate","baseline"]),
    ("candidateSha256",toJson (← hash (root/"command-build/StudyMain"))),
    ("baselineSha256",toJson (← hash (parent/"command-build/StudyMain"))),
    ("sameBackendSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("controllerSha256",toJson (← hash (root/"probe-build/StudyMain"))),
    ("sourceSha256",toJson (← hash (project/"tools/research/HookCommandChecks.lean"))),
    ("minimumPerClientSavingKiBForGrowth",toJson (8192 : Nat)),("queryBenchmark",toJson false)])
  guard "hook-primitives-probe" #[(root/"probe-build/StudyMain").toString,root.toString,"component-probe","footprint",
    (parent/"build/StudyMain").toString,(parent/"command-build/StudyMain").toString]
def conclude : IO Unit := do
  idle
  check (!(← (records/"result.json").pathExists)) "retain the first primitive result"
  for tag in ["client-build","probe-build","probe"] do
    write (records/(tag++".guard.json")) (← finished ("hook-primitives-"++tag))
  let plan ← read (records/"probe-plan.json")
  check (plan.getObjValD "candidateSha256" == toJson (← hash (root/"command-build/StudyMain")) &&
    plan.getObjValD "baselineSha256" == toJson (← hash (parent/"command-build/StudyMain")) &&
    plan.getObjValD "sameBackendSha256" == toJson (← hash (parent/"build/StudyMain")) &&
    plan.getObjValD "controllerSha256" == toJson (← hash (root/"probe-build/StudyMain")) &&
    plan.getObjValD "sourceSha256" == toJson (← hash (project/"tools/research/HookCommandChecks.lean")))
    "primitive footprint inputs changed"
  let observations ← read (records/"footprint.json")
  let rows ← IO.ofExcept (observations.getObjValAs? (Array Json) "probes")
  check (rows.size == 4) "four ABBA observations required"
  let mut peaks : Array Nat := #[]
  for i in [:rows.size] do
    let row := rows[i]!
    check (row.getObjValD "candidateClient" == toJson (i == 1 || i == 2) &&
      row.getObjValD "stderr" == toJson "") "ABBA order or clean result changed"
    peaks := peaks.push (← IO.ofExcept (row.getObjValAs? Nat "pairPeakRssKiB"))
  let savings := #[Int.ofNat peaks[0]! - Int.ofNat peaks[1]!, Int.ofNat peaks[3]! - Int.ofNat peaks[2]!]
  let minimum : Nat ← IO.ofExcept (plan.getObjValAs? _ "minimumPerClientSavingKiBForGrowth")
  let proceed := savings.all (· ≥ Int.ofNat minimum)
  check (!proceed) "this finalizer is for the observed rejection, not an adoption gate"
  patch
  write (records/"result.json") (Json.mkObj [("pairedSavingKiB",toJson savings),
    ("minimumPerClientSavingKiBForGrowth",toJson minimum),("proceedToGrowth",toJson proceed),
    ("reason",toJson "No measured RSS reduction; kernel refinement and import removal are insufficient"),
    ("backendRebuilt",toJson false),("mixedGrowthRetried",toJson false),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("parentBackendSha256",plan.getObjValD "sameBackendSha256"),
    ("parentClientSha256",plan.getObjValD "baselineSha256"),
    ("candidateClientSha256",plan.getObjValD "candidateSha256")])
  write (records/"cleanup-plan.json") (toJson #[root.toString])
end HookPrimitiveStudy
def main : List String → IO Unit
  | ["prepare"] => HookPrimitiveStudy.prepare
  | ["client"] => HookPrimitiveStudy.client
  | ["audit-client"] => HookPrimitiveStudy.auditClient
  | ["proof"] => HookPrimitiveStudy.proof
  | ["prepare-runner"] => HookPrimitiveStudy.prepareRunner
  | ["probe"] => HookPrimitiveStudy.probe
  | ["conclude"] => HookPrimitiveStudy.conclude
  | _ => throw (IO.userError "HookPrimitiveStudy prepare|client|audit-client|proof|prepare-runner|probe|conclude")
