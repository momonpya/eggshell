import tools.research.StudyLocal
open Lean StudyLocal

def runRoot := base/"snapshot-scheduling"
def records := project/"docs/candidates/snapshot-scheduling"
def product := base/"current-six/fixed-sequence/cohort/prefix/libexec/eggshell"

def artifact (path : System.FilePath) : IO Json :=
  return Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path))]

/-- A child exit code alone is insufficient: the supervisor can have stopped
leftovers after that child returned successfully. -/
def cleanGuard (tag : String) : IO Json := do
  let record ← finished tag
  check (record.getObjValD "guardTriggered" == toJson false &&
    record.getObjValD "reason" == Json.null) (tag++" supervisor did not finish normally")
  return record

def collectOwned (label : String) : IO Unit := do
  let guard ← cleanGuard ("snapshot-scheduling-"++label)
  let input ← read (runRoot/(label++"-input.json"))
  let data : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "data"))
  let root := runRoot/label
  let report ← read (root/"report.json")
  let phases : Array Json ← IO.ofExcept (fromJson? (report.getObjValD "phases"))
  check (phases.all (fun phase => phase.getObjValD "passed" == toJson true)) "a measured phase failed"
  let mut windows := #[]
  let mut actors := #[]
  for phase in phases do
    let count ← IO.ofExcept (phase.getObjValAs? Nat "clients")
    let clients : Array Json ← IO.ofExcept (fromJson? (phase.getObjValD "rows"))
    let mut first : Option Nat := none
    let mut last := 0
    for client in clients do
      let id ← IO.ofExcept (client.getObjValAs? String "receipt")
      let publication ← read (data/"receipts"/id/"published.json")
      let started ← IO.ofExcept ((publication.getObjValD "data").getObjValAs? Nat "startedMs")
      let elapsed ← IO.ofExcept (client.getObjValAs? Nat "elapsedMs")
      first := some (first.map (min started) |>.getD started)
      last := max last (started+elapsed)
      let pages := data/"receipts"/id/"request-pages.json"
      let pageRecord ← if ← pages.pathExists then read pages else pure Json.null
      actors := actors.push (Json.mkObj [("clients",toJson count),("receipt",toJson id),
        ("client",client),("pages",pageRecord)])
    let some windowStart := first | throw (IO.userError "phase omitted actual client receipts")
    windows := windows.push (windowStart,last)
  let mut profiles := #[]
  for entry in ← (data/"receipts").readDir do
    for name in #["source-plan-profile","source-bindings-profile","source-views-profile","server-envelope-profile"] do
      let path := entry.path/(name++".json")
      if ← path.pathExists then
        let row ← read path
        let clock ← IO.ofExcept (row.getObjValAs? Nat "observedMs")
        if windows.any (fun (first,last) => first ≤ clock && clock ≤ last) then profiles := profiles.push row
  let source : System.FilePath := .mk (← IO.ofExcept (input.getObjValAs? String "project"))
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  for (name,digest) in files do check ((← hash (source/name)) == digest) "fixed source changed"
  write (records/(label++"-result.json")) (Json.mkObj [("guard",guard),("report",report),
    ("sourceFilesUnchanged",toJson true),("actorRecords",toJson actors),("serviceProfiles",toJson profiles),
    ("concurrentServiceRequestAttribution",toJson false),("normalExit",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("performanceImprovementEstablished",toJson false),("adopted",toJson false)])


/-- Metadata orchestration only. Completed capture/build/repair/retirement
commands were removed with the ended helper; their receipts remain records. -/
def main (args : List String) : IO Unit := do
  let [mode,label] := args | throw (IO.userError "collect|prepare-capacity <fresh-label>")
  check (!label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-')) "invalid bounded study label"
  if mode == "collect" then
    collectOwned label
  else if mode == "prepare-capacity" then
    discard <| cleanGuard "snapshot-scheduling-owned-sampled"
    let original ← read (runRoot/"owned-sampled-input.json")
    let root := runRoot/label
    let config := root/"config.toml"
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (original.getObjValD "environment"))
    let environment := environment.map fun (key,value) =>
      (key,if key == "EGGSHELL_CONFIG" then some config.toString
        else if key == "EGGSHELL_TRACE_QUERY_STAGES" || key == "EGGSHELL_TRACE_SERVICE_PROFILE" then none else value)
    let input := original.setObjVal! "output" (toJson root.toString)
      |>.setObjVal! "config" (toJson config.toString)
      |>.setObjVal! "environment" (toJson environment)
      |>.setObjVal! "counts" (toJson (#[(4 : Nat),16]))
      |>.setObjVal! "diagnostic" (toJson false)
    let inputPath := runRoot/(label++"-input.json")
    check (!(← inputPath.pathExists)) "preserve the fixed capacity trial"
    check ((← hash product) == "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e") "fixed runtime changed"
    write inputPath input
    write (records/(label++"-plan.json")) (Json.mkObj [("input",← artifact inputPath),
      ("counts",toJson (#[(4 : Nat),16])),("maximumClients",toJson (16 : Nat)),
      ("profilesAndSamplerDisabled",toJson true),("sameFinalSnapshot",toJson true),
      ("performanceComparison",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    guard ("snapshot-scheduling-"++label) (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
      #[product.toString,"owned-selection-capacity",inputPath.toString])

  else throw (IO.userError "collect|prepare-capacity <fresh-label>")
