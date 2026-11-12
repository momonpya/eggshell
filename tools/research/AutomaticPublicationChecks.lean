import Main
import Eggshell.ContractAudit
import tools.research.SharedTrafficChecks
open Lean Eggshell Eggshell.Plugin Eggshell.Research
open Eggshell.Research.SharedProjectLifecycle
namespace AutomaticPublicationChecks

def makeCase (group : String) (wave slot : Nat) : IO Case := do
  let symbol := s!"{group}_SUPPORT_{wave}_{slot}"
  SharedTrafficChecks.route {
    session := s!"automatic-{group}-{wave}-{slot}"
    path := s!"src/{group}_{wave}_{slot}.cpp"
    symbol := symbol++"_BASE"
    first := s!"int {symbol}_BASE = {101+wave*10+slot};"
    second := s!"int {symbol}_DETAIL = {809+wave*10+slot};" } slot

/-- Inspect only already published, source-bound references. No registry
registration, preparation request, repair, warm or model command is issued. -/
def prepared (runtime : String) (project : ProjectStore.Project) : IO Json := do
  let mut rows := #[]
  for slot in [:project.manifest.owners.size] do
    let source ← project.current slot
    let count ← Persistence.Store.getNat source.get "candidates"
    let target : IndexTarget := {
      owner := DB.Sidecar.Owner.ofSnapshot source
      command := [runtime,"search-provider"]
      storage := .database
      sourceHead := some source.head }
    let reference ← PreparedInputs.loadStored? source .database MiniLM.model SearchProvider.encoderContract
    let required ← if count == 0 then pure false else Warm.storedRequired target source
    rows := rows.push (Json.mkObj [("slot",toJson slot),("head",toJson source.head),
      ("candidates",toJson count),("required",toJson required),
      ("prepared",toJson reference.isSome),
      ("numeric",toJson (reference.any fun value => value.population == 0 || value.numeric.isSome))])
  return Json.mkObj [("ready",toJson (rows.all fun row => row.getObjValD "required" == toJson false &&
    row.getObjValD "prepared" == toJson true && row.getObjValD "numeric" == toJson true)),("sources",toJson rows)]

def waitPrepared (runtime : String) (project : ProjectStore.Project) : IO Json := do
  let started ← IO.monoMsNow
  let mut first : Option Json := none
  repeat
    let status ← prepared runtime project
    if first.isNone then first := some status
    if status.getObjValD "ready" == toJson true then
      return Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-started)),("before",toJson first),("after",status)]
    if (← IO.monoMsNow) ≥ started+30000 then
      throw (IO.userError ("automatic source preparation did not catch up: "++status.compress))
    IO.sleep 100
  throw (IO.userError "unreachable preparation wait")

def freeze (project : ProjectStore.Project) (group : String) (items : Array Case) : IO Json := do
  let required := items.flatMap fun item => #[item.first,item.second]
  let mut available : Array String := #[]
  let mut rows := #[]
  for slot in [:project.manifest.owners.size] do
    let source ← project.current slot
    let reader ← Persistence.Store.NodeReader.new source
    let records ← Synapses.Provenance.records source
    for record in records do
      check (record.origin.occurrence.session.startsWith ("automatic-"++group++"-")) "publication crossed its selected project"
      let doc ← Synapses.Provenance.checkedDocument reader record.origin
      if let some raw := doc.source then
        for line in required do if raw.contains line then available := available.push line
    rows := rows.push (Json.mkObj [("slot",toJson slot),("head",toJson source.head),
      ("observations",toJson records.size)])
  check (required.all available.contains) "required source text was absent before query admission"
  return Json.mkObj [("group",toJson group),("required",toJson required),
    ("sourceVerifiedBeforeDelivery",toJson true),("sources",toJson rows)]

def writeItems (plan : StudySeedChecks.Input) (root data configuration : System.FilePath)
    (project : ProjectStore.Project) (items : Array Case) (gate : IO.Ref Bool) :
    IO (Array (Task (Except IO.Error Json))) := do
  items.mapM fun item => IO.asTask (do
    while !(← gate.get) do IO.sleep 1
    let result ← writer plan root data configuration project.directory item false 2
      (fun session label event fields => RegisteredHook.invoke plan root root data configuration session label event fields) false
    return Json.mkObj [("kind",toJson "writer"),("output",result)]) .dedicated

def beginItems (plan : StudySeedChecks.Input) (root data config : System.FilePath) (items : Array Case) : IO Unit := do
  let tasks ← items.mapM fun item => IO.asTask (do
    IO.FS.writeFile (root/item.path) (item.first++"\n"++item.second++"\n")
    SharedTrafficChecks.beginWriter plan root data config item true) .dedicated
  for task in tasks do discard <| IO.ofExcept (task.get.mapError IO.Error.toString)

def readers (plan : StudySeedChecks.Input) (root data : System.FilePath)
    (alpha beta : Array Case) (label : String) (gate : IO.Ref Bool) : IO (Array (Task (Except IO.Error Json))) := do
  let sessions := (Array.range 10).map fun index => s!"automatic-reader-{label}-{index}"
  for index in [:10] do
    let config := root/(if index < 5 then "alpha-read.toml" else "beta-read.toml")
    discard <| RegisteredHook.invoke plan root root data config sessions[index]! "start" "SessionStart"
  (Array.range 10).mapM fun index => IO.asTask (do
    while !(← gate.get) do IO.sleep 1
    let group := if index < 5 then "ALPHA" else "BETA"
    let items := if index < 5 then alpha else beta
    let config := root/(if index < 5 then "alpha-read.toml" else "beta-read.toml")
    let required := items.flatMap fun item => #[item.first,item.second]
    let result ← SharedTrafficChecks.read plan root root data config sessions[index]!
      s!"Show the original {group}_SUPPORT BASE and DETAIL source definitions from the recorded investigations, with source locations." required true
    check (result.getObjValD "missing" == toJson (#[] : Array String)) "newly published source evidence was not delivered"
    check ((result.getObjValD "search").getObjValD "semantic" == toJson "completed") "automatic publication did not retain semantic delivery"
    let body : String ← IO.ofExcept (result.getObjValAs? _ "body")
    let text ← IO.FS.readFile (.mk body)
    check (!(text.contains (if index < 5 then "BETA_SUPPORT" else "ALPHA_SUPPORT"))) "read-only profile leaked another project"
    discard <| RegisteredHook.invoke plan root root data config sessions[index]! "end" "SessionEnd"
    return Json.mkObj [("kind",toJson "reader"),("group",toJson group),("required",toJson required.size),("delivery",result)]) .dedicated

def run (input directory : String) : IO Unit := do
  let initial ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson input))
  StudyAdmission.verifyArtifact initial.runtime
  for artifact in initial.pluginFiles do StudyAdmission.verifyArtifact artifact
  StudySeedChecks.requireNumericalSupport initial
  let root : System.FilePath := .mk directory
  check (root.isAbsolute && !(← root.pathExists) && (← Paths.dataRoot) == root/"data") "fresh automatic-publication trial required"
  IO.FS.createDirAll (root/"src")
  IO.FS.createDirAll (root/"tmp")
  let plan := {initial with environment := replaceEnv initial.environment #[
    ("EGGSHELL_DATA_ROOT",some (root/"data").toString),("TMPDIR",some (root/"tmp").toString)]}
  let data := root/"data"
  let alpha ← ProjectStore.create (root/"alpha.egg") 4
  let beta ← ProjectStore.create (root/"beta.egg") 4
  let alphaWrite := root/"alpha-write.toml"
  let betaWrite := root/"beta-write.toml"
  IO.FS.writeFile alphaWrite (renderConfig plan.runtime.path alpha.directory beta.directory (some "active"))
  IO.FS.writeFile betaWrite (renderConfig plan.runtime.path alpha.directory beta.directory (some "reference"))
  for (name,project) in [("alpha",alpha),("beta",beta)] do
    IO.FS.writeFile (root/(name++"-read.toml")) (SharedTrafficChecks.config plan.runtime.path project.directory false)
  let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data plan.environment
  let frontend ← try
      StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot) "automatic-publication"
        (data/"daemon.json") plan.environment
    catch error =>
      StudyRuntime.stopManaged publisher (root/"publisher-startup-stop.json")
      throw error
  let mut allAlpha := #[]
  let mut allBeta := #[]
  let mut waves := #[]
  try
    for wave in [0:4] do
      let itemsAlpha ← #[0,1].mapM fun n => makeCase "ALPHA" wave ((wave+n)%4)
      let itemsBeta ← #[0,1].mapM fun n => makeCase "BETA" wave ((wave+n)%4)
      beginItems plan root data alphaWrite itemsAlpha
      beginItems plan root data betaWrite itemsBeta
      let gate ← IO.mkRef false
      let mut tasks ← writeItems plan root data alphaWrite alpha itemsAlpha gate
      tasks := tasks++(← writeItems plan root data betaWrite beta itemsBeta gate)
      if wave > 0 then
        save (root/s!"frozen-{wave}-overlap.json") (toJson #[← freeze alpha "ALPHA" allAlpha,← freeze beta "BETA" allBeta])
        tasks := tasks++(← readers plan root data allAlpha allBeta s!"overlap-{wave}" gate)
      let started ← IO.monoMsNow
      gate.set true
      let (settled,ok) ← SharedTrafficChecks.settle tasks
      let elapsed := (← IO.monoMsNow)-started
      save (root/s!"wave-{wave}-outcomes.json") (Json.mkObj [("elapsedMs",toJson elapsed),("outcomes",toJson settled),("ok",toJson ok)])
      check ok "automatic publication or concurrent query failed"
      let committedAlpha ← SharedTrafficChecks.waitAnswers alpha itemsAlpha
      let committedBeta ← SharedTrafficChecks.waitAnswers beta itemsBeta
      allAlpha := allAlpha++itemsAlpha
      allBeta := allBeta++itemsBeta
      let preparedAlpha ← waitPrepared plan.runtime.path alpha
      let preparedBeta ← waitPrepared plan.runtime.path beta
      save (root/s!"wave-{wave}-preparation.json") (Json.mkObj [("alpha",preparedAlpha),("beta",preparedBeta)])
      discard <| census alpha ((wave+1)*6)
      discard <| census beta ((wave+1)*6)
      save (root/s!"frozen-{wave}-fresh.json") (toJson #[← freeze alpha "ALPHA" allAlpha,← freeze beta "BETA" allBeta])
      let readGate ← IO.mkRef false
      let newReaders ← readers plan root data allAlpha allBeta s!"fresh-{wave}" readGate
      let readStarted ← IO.monoMsNow
      readGate.set true
      let (delivered,ready) ← SharedTrafficChecks.settle newReaders
      let readMs := (← IO.monoMsNow)-readStarted
      save (root/s!"wave-{wave}-fresh.json") (Json.mkObj [("elapsedMs",toJson readMs),("outcomes",toJson delivered),("ok",toJson ready)])
      check ready "fresh chats could not consume automatically prepared records"
      waves := waves.push (Json.mkObj [("wave",toJson wave),("overlapMs",toJson elapsed),
        ("overlap",toJson settled),("freshMs",toJson readMs),("fresh",toJson delivered),
        ("alphaCommit",committedAlpha),("betaCommit",committedBeta),
        ("alphaPreparation",preparedAlpha),("betaPreparation",preparedBeta)])
      save (root/"waves.json") (toJson waves)
    save (root/"facts.json") (Json.mkObj [("alpha",← graphFacts alpha),("beta",← graphFacts beta)])
    save (root/"result.json") (Json.mkObj [("runtime",toJson plan.runtime),("waves",toJson waves),
      ("manualWarmCalls",toJson (0 : Nat)),("manualKeepCalls",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  catch error =>
    save (root/"failure.json") (Json.mkObj [("error",toJson error.toString),("completedWaves",toJson waves.size)])
    throw error
  finally
    try StudyRuntime.stopManaged frontend (root/"frontend-stop.json")
    finally StudyRuntime.stopManaged publisher (root/"publisher-stop.json")
end AutomaticPublicationChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["check",input,directory] => AutomaticPublicationChecks.run input directory; return 0
  | _ => sourceRouteEngine args
