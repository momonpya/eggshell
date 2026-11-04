import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/subset-rank"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "source identity hashing failed")
  return (result.stdout.splitOn " ").head!
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.compress++"\n")
def body (value : Json) : String := ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
def events (root : System.FilePath) (receipt : String) : IO (Array (String × Json)) := do
  let folder := root/"private/receipts"/receipt
  if !(← folder.pathExists) then return #[]
  let mut records := #[]
  for entry in ← folder.readDir do
    if entry.fileName.endsWith ".json" &&
        (["operation-","search-phase-","numerical-","discovery-counters-"].any (fun stem => entry.fileName.startsWith stem) ||
         ["search.json","transport.json","failure.json","prepared-inputs-turn.json"].contains entry.fileName) then
      records := records.push (entry.fileName,← read entry.path)
  return records
def main : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed evidence")
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "subset-rank-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "subset-rank-records" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      let path := base/(entry.fileName.replace ".guard.json" ".log")
      let lines := (← IO.FS.readFile path).splitOn "\n"
      guards := guards.push (Json.mkObj [("tag",toJson entry.fileName),("guard",guard),
        ("logSha256",toJson (← hash path)),("tail",toJson (String.intercalate "\n" (lines.drop (lines.length-18))))])
  let prior := base/"subset-rank-baseline-core/Eggshell/Handoff.lean"
  let current := base/"interest-traffic-core/Eggshell/Handoff.lean"
  let added := base/"interest-traffic-core/Eggshell/SubsetLexical.lean"
  let mut patch := ""
  for (left,right) in [(prior,current),(System.FilePath.mk "/dev/null",added)] do
    let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--unified=0","--",left.toString,right.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "isolated source diff missing")
    patch := patch++(diff.stdout.replace ("a"++(base/"subset-rank-baseline-core").toString++"/") "a/"
      |>.replace ("a"++(base/"interest-traffic-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
  IO.FS.writeFile (output/"candidate.patch") patch
  let mut unchanged := #[]
  for name in ["MiniLM.lean","Numerical.lean","SearchProvider.lean","BlockScore.lean","GraphStore.lean","DB/PageMap.lean",
      "NativePublication.lean","ProjectSources.lean","PublicationService.lean","SearchRank.lean","SourceOwners.lean","SourceBitmap.lean",
      "SynapseTransport.lean","OwnerViews.lean","HookFrontend.lean","Matcher.lean","Extract.lean","Worker.lean","OperationPool.lean","Daemon.lean"] do
    let before ← hash (base/"subset-rank-baseline-core/Eggshell"/name)
    let actual ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless before == actual do throw (IO.userError ("unrelated source changed: "++name))
    unchanged := unchanged.push (name,actual)
  let mut audits := #[]
  for tag in ["subset-rank-audit1","subset-rank-audit2"] do
    let root := base/("subset-rank-fixture-"++tag)
    let files ← ["report.json","checks.json","timings.json"].toArray.mapM fun (name : String) => do return (name,← read (root/name))
    audits := audits.push (tag,← IO.FS.readFile (root/"runtime.sha256"),files)
  let mut profiles := #[]
  let mut comparisons := #[]
  for pair in [1,2,3] do
    for arm in ["parent","candidate"] do
      let tag := s!"subset-rank-{arm}{pair}"
      let root := base/("subset-rank-fixture-"++tag)
      let files ← ["runtime.sha256","report.json","rows.json","warm-result.json","stages.json",
          "cold-frontend-stdout.json","running-frontend-stdout.json","cold-frontend-trace.txt","running-frontend-trace.txt"].toArray.mapM fun (name : String) => do
        return (name,← IO.FS.readFile (root/name))
      profiles := profiles.push (tag,files)
    for name in ["cold-frontend","running-frontend"] do
      let before ← read (base/s!"subset-rank-fixture-subset-rank-parent{pair}"/(name++"-stdout.json"))
      let after ← read (base/s!"subset-rank-fixture-subset-rank-candidate{pair}"/(name++"-stdout.json"))
      unless !(body before).isEmpty && body before == body after do throw (IO.userError "actual paired body differs")
      comparisons := comparisons.push (pair,name,(body before).utf8ByteSize)
  let mut loads := #[]
  for tag in ["subset-rank-parent-readback1","subset-rank-readback1"] do
    let root := base/("subset-rank-fixture-"++tag)
    let mut hooks := #[]
    let mut stages := #[]
    let mut actual : Array (String × String) := #[]
    let mut delivered := 0
    let mut admitted := 0
    let mut times : List Nat := []
    for entry in ← root.readDir do
      if !entry.fileName.endsWith "-measurement.json" then continue
      let row ← read entry.path
      let text := (row.getObjValAs? String "body").toOption.getD ""
      let head := text.contains "\"observed-head-case-79-7b319c\""
      let tail := text.contains "\"observed-tail-case-79-d82a04\""
      if head && tail && row.getObjValD "complete" == toJson true then delivered := delivered+1
      let log ← events root (← IO.ofExcept (row.getObjValAs? String "receipt"))
      if log.any (fun (name,_) => name.endsWith "-admitted.json") then admitted := admitted+1
      stages := stages.push (entry.fileName,log)
      hooks := hooks.push (entry.fileName,row.setObjVal! "body" Json.null |>.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
      times := ((row.getObjValAs? Nat "elapsedMs").toOption.getD 0)::times
      let digest ← IO.ofExcept (row.getObjValAs? String "outputSha256")
      if !actual.any (·.1 == digest) then
        let framed ← IO.FS.readFile (root/(entry.fileName.replace "-measurement.json" ".json"))
        unless framed.endsWith "\n" do throw (IO.userError "actual output framing differs")
        let payload := (framed.dropEnd 1).toString
        let scratch := base/"subset-rank-output-hash"
        IO.FS.writeFile scratch payload
        let checked ← try hash scratch finally IO.FS.removeFile scratch
        unless checked == digest do throw (IO.userError "actual output differs from receipt")
        actual := actual.push (digest,payload)
    unless hooks.size == 80 do throw (IO.userError "incomplete eighty-reader measurements")
    let reports ← ["before-originals.json","warm-result.json","readers-results.json"].toArray.mapM fun (name : String) => do return (name,← read (root/name))
    let ordered := times.mergeSort (· ≤ ·)
    loads := loads.push (Json.mkObj [("tag",toJson tag),("runtime",toJson (← IO.FS.readFile (root/"runtime.sha256"))),
      ("delivered",toJson delivered),("admitted",toJson admitted),("minMs",toJson (ordered.headD 0)),
      ("maxMs",toJson (ordered.getLast?.getD 0)),("reports",toJson reports),("hooks",toJson hooks),
      ("stages",toJson stages),("actualOutputsBySha256",toJson actual)])
  let source := base/"frontend-quiescence-fixture-small1"
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == (← read (source/"frozen-readback.json")).getObjValD "sourceHeads" do throw (IO.userError "original heads changed")
  for (tag,name) in [("subset-rank-proofs3","laws.txt"),("subset-rank-contract2","contract-audit.txt")] do
    let path := base/(tag++".log")
    let lines := (← IO.FS.readFile path).splitOn "\n"
    IO.FS.writeFile (output/name) ("Full output SHA-256: "++(← hash path)++"\n"++String.intercalate "\n" (lines.drop (lines.length-16)))
  save "evidence.json" (Json.mkObj [("parent",toJson "b9eac443a9be1d00518167dd04059c6482b472ac"),
    ("sourceHashes",toJson (← hash prior,← hash current)),("newModuleSha256",toJson (← hash added)),
    ("unchanged",toJson unchanged),("guards",toJson guards),("audits",toJson audits),("profiles",toJson profiles),
    ("bodyChecks",toJson comparisons),("loads",toJson loads),("originalHeads",toJson heads),
    ("runtimeSha256",toJson (← hash (base/"subset-rank-build/StudyMain"))),
    ("launchError",toJson (← IO.FS.readFile (base/"subset-rank-build1.launch-error.txt"))),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedComparisons",toJson "0/18"),("adopted",toJson false)])
  IO.println (toJson (loads.map fun load => (load.getObjValD "tag",load.getObjValD "delivered"))).compress
