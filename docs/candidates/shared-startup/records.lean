import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/shared-startup"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "hashing failed")
  return (result.stdout.splitOn " ").head!
def events (root : System.FilePath) (receipt : String) : IO (Array (String × Json)) := do
  let folder := root/"private/receipts"/receipt
  if !(← folder.pathExists) then return #[]
  let mut rows := #[]
  for entry in ← folder.readDir do
    if entry.fileName.endsWith ".json" &&
        (["operation-","search-phase-","discovery-counters-"].any (fun stem => entry.fileName.startsWith stem) ||
         ["failure.json","search.json","prepared-inputs-turn.json","prepared-inputs-operation.json","transport.json",
          "canonical-source-reuse.json","original-read.json","projection.json","published.json"].contains entry.fileName) then
      rows := rows.push (entry.fileName,(← read entry.path).getObjValD "data")
  return rows
def collectEvidence : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed evidence")
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "shared-startup-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "shared-startup-records" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      let log := base/(entry.fileName.replace ".guard.json" ".log")
      let text ← IO.FS.readFile log
      let lines := text.splitOn "\n"
      guards := guards.push (Json.mkObj [("tag",toJson entry.fileName),("guard",guard),
        ("logSha256",toJson (← hash log)),("logTail",toJson (String.intercalate "\n" (lines.drop (lines.length-16))))])
  let mut patch := ""
  let mut changed := #[]
  for name in ["Daemon.lean","DaemonWire.lean"] do
    let prior := base/"shared-startup-baseline-core/Eggshell"/name
    let current := base/"interest-traffic-core/Eggshell"/name
    let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--",prior.toString,current.toString]}
    unless diff.exitCode ≤ 1 do throw (IO.userError "source diff failed")
    patch := patch++(diff.stdout.replace ("a"++(base/"shared-startup-baseline-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
    changed := changed.push (name,← hash prior,← hash current)
  IO.FS.writeFile (output/"candidate.patch") patch
  let mut unchanged := #[]
  for name in ["MiniLM.lean","Numerical.lean","SearchProvider.lean","BlockScore.lean","GraphStore.lean","DB/PageMap.lean",
      "NativePublication.lean","ProjectSources.lean","PublicationService.lean","Handoff.lean","SearchRank.lean",
      "HookFrontend.lean","Matcher.lean","Extract.lean","Worker.lean","PluginHooks.lean","OperationPool.lean","HookBudget.lean"] do
    let old ← hash (base/"shared-startup-baseline-core/Eggshell"/name)
    let actual ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless old == actual do throw (IO.userError ("unrelated source changed: "++name))
    unchanged := unchanged.push (name,actual)
  let component := base/"shared-startup-fixture-shared-startup-startup1"
  let trial := base/"shared-startup-fixture-shared-startup-readback1"
  let mut startup := #[]
  for name in ["negative.json","cold.json","running.json","processes.json","report.json"] do
    if ← (component/name).pathExists then startup := startup.push (name,← read (component/name))
  let mut hooks := #[]
  let mut stages := #[]
  let mut actual : Array (String × String) := #[]
  let mut delivered := 0
  let mut times : List Nat := []
  let mut admitted := 0
  for entry in ← trial.readDir do
    if !entry.fileName.endsWith "-measurement.json" then continue
    let row ← read entry.path
    let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
    let body := (row.getObjValAs? String "body").toOption.getD ""
    let head := body.contains "\"observed-head-case-79-7b319c\""
    let tail := body.contains "\"observed-tail-case-79-d82a04\""
    if head && tail && row.getObjValD "complete" == toJson true then delivered := delivered+1
    let log ← events trial receipt
    if log.any (fun (file,_) => file.endsWith "-admitted.json") then admitted := admitted+1
    stages := stages.push (entry.fileName,log)
    times := ((row.getObjValAs? Nat "elapsedMs").toOption.getD 0)::times
    hooks := hooks.push (entry.fileName,row.setObjVal! "body" Json.null |>.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
    let digest ← IO.ofExcept (row.getObjValAs? String "outputSha256")
    if !actual.any (·.1 == digest) then
      let framed ← IO.FS.readFile (trial/(entry.fileName.replace "-measurement.json" ".json"))
      unless framed.endsWith "\n" do throw (IO.userError "receiver framing changed")
      let text := (framed.dropEnd 1).toString
      let scratch := base/"shared-startup-output-hash"
      IO.FS.writeFile scratch text
      let checked ← try hash scratch finally IO.FS.removeFile scratch
      unless checked == digest do throw (IO.userError "actual output differs from receipt")
      actual := actual.push (digest,text)
  let source := base/"frontend-quiescence-fixture-small1"
  let frozen ← read (source/"frozen-readback.json")
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == frozen.getObjValD "sourceHeads" do throw (IO.userError "original heads changed")
  let mut reports := #[]
  for name in ["before-originals.json","warm-result.json","warm-stdout.json","readers-results.json","report.json"] do
    if ← (trial/name).pathExists then reports := reports.push (name,← read (trial/name))
  for (tag,name) in [("shared-startup-proofs1","laws.txt"),("shared-startup-contract1","contract-audit.txt")] do
    let path := base/(tag++".log")
    let lines := (← IO.FS.readFile path).splitOn "\n"
    IO.FS.writeFile (output/name) ("Full output SHA-256: "++(← hash path)++"\n"++String.intercalate "\n" (lines.drop (lines.length-16)))
  let ordered := times.mergeSort (· ≤ ·)
  let summary := Json.mkObj [("deliveredBothOriginalFields",toJson delivered),("readers",toJson (80 : Nat)),
    ("admitted",toJson admitted),("measurements",toJson hooks.size),("minMs",toJson (ordered.headD 0)),
    ("maxMs",toJson (ordered.getLast?.getD 0)),("originalHeadsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedComparisons",toJson "0/18"),("adopted",toJson false)]
  let evidence := Json.mkObj [("parent",toJson "9a512e8c512cc9572cbadeebeb869c9980731b83"),
    ("changed",toJson changed),("unchanged",toJson unchanged),("guards",toJson guards),
    ("runtimeSha256",toJson (← hash (base/"shared-startup-build/StudyMain"))),
    ("startupRuntime",toJson (← IO.FS.readFile (component/"runtime.sha256"))),
    ("readbackRuntime",toJson (← IO.FS.readFile (trial/"runtime.sha256"))),
    ("startup",toJson startup),("reports",toJson reports),("hooks",toJson hooks),("stages",toJson stages),
    ("actualOutputsBySha256",toJson actual),("originalHeads",toJson heads),("summary",summary)]
  IO.FS.writeFile (output/"evidence.json") (evidence.compress++"\n")
  IO.FS.writeFile (output/"summary.json") (summary.pretty++"\n")
  IO.println summary.compress

/-- Preserve existing low-level timings before retiring the ended private root.
No request, endpoint secret or authorization token is copied. -/
def details : IO Unit := do
  unless !(← (output/"stage-details.json").pathExists) do throw (IO.userError "preserve detailed evidence")
  let trial := base/"shared-startup-fixture-shared-startup-readback1"
  let mut rows := #[]
  for receipt in ← (trial/"private/receipts").readDir do
    if !(← receipt.path.isDir) then continue
    let mut stages := #[]
    for entry in ← receipt.path.readDir do
      if entry.fileName.endsWith ".json" &&
          (["numerical-","keyed-partition-","freshness-","lexical-advice-","lexical-reads-","lexical-consumed-"].any
            (fun stem => entry.fileName.startsWith stem) ||
           ["canonical-source-input.json","delivery-domain.json","keyed-coverage.json","keyed-nominations.json",
            "selection-plan.json","synaptic-delivery.json"].contains entry.fileName) then
        stages := stages.push (entry.fileName,(← read entry.path).getObjValD "data")
    rows := rows.push (receipt.fileName,stages)
  IO.FS.writeFile (output/"stage-details.json") ((toJson rows).compress++"\n")

def main (args : List String) : IO Unit := do
  if args == [] then collectEvidence
  else if args == ["details"] then details
  else throw (IO.userError "unknown evidence action")
