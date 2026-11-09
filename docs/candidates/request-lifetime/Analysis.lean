import tools.research.StudyLocal
open Lean StudyLocal

def evidence := project/"docs/candidates/request-lifetime"
def arrayAt (value : Json) (key : String) : Array Json :=
  (value.getObjValAs? (Array Json) key).toOption.getD #[]
def numberAt (value : Json) (key : String) : Nat :=
  (value.getObjValAs? Nat key).toOption.getD 0

/-- Keep scalar counters and small structures, never full ranking/payload arrays. -/
partial def compact (value : Json) : Json :=
  match value with
  | .arr values =>
    if values.size > 24 then Json.mkObj [("omittedArrayEntries",toJson values.size)]
    else toJson (values.map compact)
  | .obj fields => Json.mkObj (fields.toArray.toList.map fun (key,value) => (key,compact value))
  | .str value =>
    if value.utf8ByteSize > 1024 then Json.mkObj [("omittedStringBytes",toJson value.utf8ByteSize)]
    else toJson value
  | _ => value

def total (sample : Json) : Nat :=
  (arrayAt sample "rows").foldl (fun n row => n+numberAt row "rssKiB") 0

def earliest (values : Array Nat) : Nat := values.foldl min (values[0]?.getD 0)

def main : IO Unit := do
  idle
  let path := evidence/"observation.json"
  let originalDigest ← hash path
  let observation ← read path
  check (!(← (evidence/"summary.json").pathExists)) "preserve original summary"
  let stages := arrayAt observation "stages"
  let samples := arrayAt observation "samples"
  let some firstPage := stages.find? (·.getObjValD "name" == toJson "request-pages.json")
    | throw (IO.userError "request page record missing")
  let publisher := numberAt (firstPage.getObjValD "record") "pid"
  let began := earliest (samples.map (numberAt · "atMs"))
  let ended := (samples.map (numberAt · "atMs")).foldl max 0
  let mut profiles := #[]
  let profileNames := #["local-source-bindings","source-bindings-profile","client-profile",
    "render-client-profile","render-automatic-profile","source-plan-profile","local-source-plan",
    "local-source-views","local-source-fetch","server-envelope-profile"]
  for entry in ← (base/"prepared-literals-fixture/data/receipts").readDir do
    if !(← entry.path.isDir) then continue
    for name in profileNames do
      let profilePath := entry.path/(name++".json")
      if !(← profilePath.pathExists) then continue
      let row ← read profilePath
      let stamp := numberAt row "observedMs"
      if numberAt row "pid" != publisher || stamp < began || ended < stamp then continue
      profiles := profiles.push (row.setObjVal! "receiptDirectory" (toJson entry.fileName))
  let mut phaseRows := #[]
  for name in ["prime","phase-4","phase-16"] do
    let phaseStages := stages.filter (·.getObjValD "phase" == toJson name)
    let pages := phaseStages.filter (·.getObjValD "name" == toJson "request-pages.json")
    let starts := pages.filterMap fun page =>
      let data := page.getObjValD "record" |>.getObjValD "data"
      let marks := (data.getObjValAs? (Array (String × Nat)) "queryStages").toOption.getD #[]
      (marks.find? (·.1 == "restore-request:start")).map Prod.snd
    let phaseStart := earliest starts
    let phaseEnd := phaseStages.foldl (fun n row => max n (numberAt (row.getObjValD "record") "observedMs")) 0
    let within := samples.filter fun row => phaseStart ≤ numberAt row "atMs" && numberAt row "atMs" ≤ phaseEnd
    let peak := within.foldl (fun best row => if total best < total row then row else best) Json.null
    let peakStamp := numberAt peak "atMs"
    let marks := #["prepared-window-focus.json","canonical-source-input.json","delivery-domain.json",
      "selection-plan.json","synaptic-delivery.json","request-pages.json","search.json","ack.json"]
    let counts := marks.map fun mark => (mark,(phaseStages.filter fun row =>
      row.getObjValD "name" == toJson mark && numberAt (row.getObjValD "record") "observedMs" ≤ peakStamp).size)
    phaseRows := phaseRows.push (Json.mkObj [("phase",toJson name),("startMs",toJson phaseStart),
      ("endMs",toJson phaseEnd),("peakSample",peak),("sampledPeakRssKiB",toJson (total peak)),
      ("stagesCompletedAtPeak",toJson counts)])
  let peak := samples.foldl (fun best row => if total best < total row then row else best) Json.null
  let report := Json.mkObj [("uncompactedObservationSha256",toJson originalDigest),
    ("publisherPid",toJson publisher),("serviceProfileRecords",toJson profiles.size),
    ("phasePeaks",toJson phaseRows),("aggregatePeakSample",peak),
    ("aggregatePeakRssKiBExcludingGuard",toJson (total peak)),
    ("observerIsReadOnly",toJson true),("rssDoesNotMeasureCompressedOrSwappedBytes",toJson true),
    ("normalLifecycleGatePassed",toJson false),("adopted",toJson false)]
  write (evidence/"summary.json") report
  write (evidence/"service-profiles.json") (toJson (profiles.map compact))
  let reduced := observation.setObjVal! "phases" (toJson ((arrayAt observation "phases").map fun row =>
      row.setObjVal! "rows" Json.null))
    |>.setObjVal! "stages" (toJson (stages.map fun row => row.setObjVal! "record" (compact (row.getObjValD "record"))))
    |>.setObjVal! "uncompactedObservationSha256" (toJson originalDigest)
    |>.setObjVal! "largeArraysReplacedByEntryCounts" (toJson true)
  write path reduced
  IO.FS.writeFile (evidence/"Analysis.lean") (← IO.FS.readFile (base/"request-timeline-summarize.lean"))
  IO.println (Json.mkObj [("serviceProfiles",toJson profiles.size),("compactBytes",toJson reduced.compress.utf8ByteSize),
    ("peakKiB",toJson (total peak))]).compress
