import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/query-residency"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "source identity hashing failed")
  return (result.stdout.splitOn " ").head!
def hashText (text : String) : IO String := do
  let scratch := base/"query-residency-record-text"
  IO.FS.writeFile scratch text
  try hash scratch finally IO.FS.removeFile scratch
def body (value : Json) : String :=
  ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
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
    if entry.fileName.startsWith "query-residency-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "query-residency-records" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      let path := base/(entry.fileName.replace ".guard.json" ".log")
      let lines := (← IO.FS.readFile path).splitOn "\n"
      guards := guards.push (Json.mkObj [("tag",toJson entry.fileName),("guard",guard),
        ("logSha256",toJson (← hash path)),("tail",toJson (String.intercalate "\n" (lines.drop (lines.length-18))))])
  let mut patch := ""
  let mut sourceHashes := #[]
  for name in ["PublicationWire.lean","PublicationClient.lean","PublicationService.lean","SynapseRecommend.lean","Handoff.lean"] do
    let prior := base/"query-residency-baseline-core/Eggshell"/name
    let current := base/"interest-traffic-core/Eggshell"/name
    let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--unified=0","--",prior.toString,current.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "isolated source diff missing")
    patch := patch++(diff.stdout.replace ("a"++(base/"query-residency-baseline-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
    sourceHashes := sourceHashes.push (name,← hash prior,← hash current)
  let normalized := String.intercalate "\n" ((patch.splitOn "\n").map fun line =>
    if line.startsWith "@@" then (line.splitOn " @@").head!++" @@" else line)
  IO.FS.writeFile (output/"candidate.patch") normalized
  let mut unchanged := #[]
  for name in ["MiniLM.lean","Numerical.lean","SearchProvider.lean","BlockScore.lean","GraphStore.lean","DB/PageMap.lean",
      "NativePublication.lean","ProjectSources.lean","SearchRank.lean","SourceOwners.lean","SourceBitmap.lean",
      "SynapseTransport.lean","OwnerViews.lean","HookFrontend.lean","Matcher.lean","Extract.lean","Worker.lean","OperationPool.lean","Daemon.lean"] do
    let before ← hash (base/"query-residency-baseline-core/Eggshell"/name)
    let actual ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless before == actual do throw (IO.userError ("unrelated source changed: "++name))
    unchanged := unchanged.push (name,actual)
  let mut audits := #[]
  for tag in ["query-residency-audit3"] do
    let root := base/("query-residency-fixture-"++tag)
    audits := audits.push (tag,← IO.FS.readFile (root/"runtime.sha256"),← read (root/"report.json"))
  let mut profiles := #[]
  let mut comparisons := #[]
  let mut actualBodies : Array (String × String) := #[]
  for pair in ["1","2","3","-lexical1"] do
    for arm in ["parent","candidate"] do
      let tag := s!"query-residency-{arm}{pair}"
      let root := base/("query-residency-fixture-"++tag)
      let files ← ["runtime.sha256","report.json","warm-result.json","stages.json",
          "cold-frontend-trace.txt","running-frontend-trace.txt"].toArray.mapM fun (name : String) => do
        return (name,← IO.FS.readFile (root/name))
      profiles := profiles.push (tag,files)
    for name in ["cold-frontend","running-frontend"] do
      let before ← read (base/s!"query-residency-fixture-query-residency-parent{pair}"/(name++"-stdout.json"))
      let after ← read (base/s!"query-residency-fixture-query-residency-candidate{pair}"/(name++"-stdout.json"))
      unless !(body before).isEmpty && body before == body after do throw (IO.userError "actual paired body differs")
      let digest ← hashText (body before)
      if !actualBodies.any (·.1 == digest) then actualBodies := actualBodies.push (digest,body before)
      comparisons := comparisons.push (pair,name,(body before).utf8ByteSize,digest)
  let mut loads := #[]
  for tag in ["query-residency-parent-readback1","query-residency-readback1"] do
    let root := base/("query-residency-fixture-"++tag)
    let mut hooks := #[]
    let mut stages := #[]
    let mut delivered := 0
    let mut admitted := 0
    let mut captures := 0
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
      if log.any (fun (name,value) => name == "prepared-inputs-turn.json" &&
          (value.getObjValD "data").getObjValD "status" == toJson "complete") then captures := captures+1
      stages := stages.push (entry.fileName,log)
      let digest ← hashText text
      if !actualBodies.any (·.1 == digest) then actualBodies := actualBodies.push (digest,text)
      hooks := hooks.push (entry.fileName,row.setObjVal! "body" Json.null |>.setObjVal! "bodySha256" (toJson digest)
        |>.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
      times := ((row.getObjValAs? Nat "elapsedMs").toOption.getD 0)::times
      let framed ← IO.FS.readFile (root/(entry.fileName.replace "-measurement.json" ".json"))
      unless framed.endsWith "\n" do throw (IO.userError "actual output framing differs")
      unless (← hashText (framed.dropEnd 1).toString) ==
          (row.getObjValAs? String "outputSha256").toOption.getD "" do
        throw (IO.userError "actual output differs from receipt")
    unless hooks.size == 80 && captures == 80 do throw (IO.userError "incomplete eighty-reader measurements or capture")
    let reports ← ["before-originals.json","warm-result.json","readers-results.json"].toArray.mapM fun (name : String) => do return (name,← read (root/name))
    let original ← read (root/"before-originals.json")
    unless original.getObjValD "allExactInputOutput" == toJson true do throw (IO.userError "saved original differs")
    let ordered := times.mergeSort (· ≤ ·)
    loads := loads.push (Json.mkObj [("tag",toJson tag),("runtime",toJson (← IO.FS.readFile (root/"runtime.sha256"))),
      ("delivered",toJson delivered),("admitted",toJson admitted),("completeCaptures",toJson captures),
      ("minMs",toJson (ordered.headD 0)),("maxMs",toJson (ordered.getLast?.getD 0)),
      ("reports",toJson reports),("hooks",toJson hooks),("stages",toJson stages)])
  let source := base/"frontend-quiescence-fixture-small1"
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == (← read (source/"frozen-readback.json")).getObjValD "sourceHeads" do throw (IO.userError "original heads changed")
  for (tag,name) in [("query-residency-proofs1","laws.txt"),("query-residency-contract1","contract-audit.txt")] do
    let path := base/(tag++".log")
    let lines := (← IO.FS.readFile path).splitOn "\n"
    IO.FS.writeFile (output/name) ("Full output SHA-256: "++(← hash path)++"\n"++String.intercalate "\n" (lines.drop (lines.length-16)))
  let mut initialProfiles := #[]
  for tag in ["query-residency-lexical1","query-residency-sample1"] do
    let root := base/("query-residency-fixture-"++tag)
    let files ← ["runtime.sha256","report.json","warm-result.json","stages.json",
        "cold-frontend-trace.txt","running-frontend-trace.txt"].toArray.mapM fun (name : String) => do
      return (name,← IO.FS.readFile (root/name))
    initialProfiles := initialProfiles.push (tag,files)
  let sampled := base/"query-residency-fixture-query-residency-sample1/worker.sample.txt"
  let stack := (← IO.FS.readFile sampled).splitOn "\n"
  let selected := stack.filter fun line =>
    ["Worker_searchRestored","Synapses_Recommend_prepare","Client_prepareSourceUsing","Client_retainSourceAt",
      "Client_resolve","Client_ready","Daemon_exchange"].any (fun part => line.contains part)
  IO.FS.writeFile (output/"parent-stack.txt") ("One-second native sample SHA-256: "++(← hash sampled)++
    "\nRecursive stack observations are not CPU percentages.\n"++String.intercalate "\n" (selected.take 32)++"\n")
  let evidence := Json.mkObj [("parent",toJson "4cc95e159d39c8cac75fdb24de294b0b08722b5c"),
    ("sourceHashes",toJson sourceHashes),("unchanged",toJson unchanged),("guards",toJson guards),
    ("audits",toJson audits),("initialProfiles",toJson initialProfiles),("profiles",toJson profiles),("bodyChecks",toJson comparisons),("loads",toJson loads),
    ("actualBodiesBySha256",toJson actualBodies),("originalHeads",toJson heads),
    ("runtimeSha256",toJson (← hash (base/"query-residency-build/StudyMain"))),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedComparisons",toJson "0/18"),("adopted",toJson false)]
  IO.FS.writeFile (output/"evidence.json") (evidence.compress++"\n")
  IO.println (toJson (loads.map fun load => (load.getObjValD "tag",load.getObjValD "delivered"))).compress
