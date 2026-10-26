import Eggshell.Handoff
open Lean Eggshell

private def read (path : String) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))

/-- Reconstruct roots from the recorded nomination/hydration and immutable
original occurrences. Measure closure separately from presentation/selection.
This is a diagnostic, never an increased product-hook budget. -/
def main (args : List String) : IO Unit := do
  let [sourcePath,domainPath,promptPath,outputPath] := args |
    throw (IO.userError "SynapticWalkAudit SOURCE DOMAIN PROMPT NEW-REPORT")
  unless !(← (System.FilePath.mk outputPath).pathExists) do throw (IO.userError "keep earlier graph audit")
  let source ← DB.PageMap.pin (.mk sourcePath)
  let prepared ← Synapses.Recommend.prepare source true
  let some shared := prepared.shared | throw (IO.userError "recorded shared view unavailable")
  let domain := (← read domainPath).getObjValD "data"
  let ranking ← IO.ofExcept (domain.getObjValAs? (Array String) "nominated")
  let hydrated ← IO.ofExcept (domain.getObjValAs? (Array String) "hydrated")
  let answers := ranking.mapIdx fun priority owner => (owner,priority)
  let nodeReader ← Persistence.Store.NodeReader.new source
  let mut consumers := #[]
  for entry in ← Synapses.Build.entries source do
    let document ← Synapses.Build.document nodeReader entry.id
    if !hydrated.contains document.owner then continue
    if let some (_,priority) := answers.find? (·.1 == document.owner) then
      consumers := consumers ++ document.occurrences.map (·,priority)
  let query := Sha256.hex (← IO.FS.readFile (.mk promptPath)).toUTF8
  let rows := shared.index.head.root.map (·.rows) |>.getD 0
  let broad : Synapses.Recommend.Limits := {
    requests := rows+1,facts := rows+1,bytes := 64*1024*1024}
  let mut trials := #[]
  for (label,limits) in #[("original-work-cap",({} : Synapses.Recommend.Limits)),("full-diagnostic",broad)] do
    let started ← IO.monoMsNow
    let result ← Synapses.Recommend.collect shared prepared.usage answers #[] query
      (started+30000) limits consumers
    trials := trials.push (Json.mkObj [("label",toJson label),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("result",result.receipt),
      ("checkedOffersBeforeAdmission",toJson result.offers.size)])
  unless (← DB.PageMap.pin source.directory).head == source.head do
    throw (IO.userError "source changed during graph audit")
  let report := Json.mkObj [("trials",toJson trials),("answerRoots",toJson answers.size),
    ("consumerRoots",toJson consumers.size),("rootReconstruction",toJson true),
    ("sourceWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("productHookBudgetUnchanged",toJson true),("productionAdoption",toJson false)]
  IO.FS.writeFile (.mk outputPath) (report.pretty ++ "\n")
  for trial in trials do
    let result := trial.getObjValD "result"
    IO.println (Json.mkObj [("label",trial.getObjValD "label"),("elapsedMs",trial.getObjValD "elapsedMs"),
      ("complete",result.getObjValD "complete"),("requests",result.getObjValD "requests"),
      ("facts",result.getObjValD "facts"),("checkedOffers",trial.getObjValD "checkedOffersBeforeAdmission")]).compress
