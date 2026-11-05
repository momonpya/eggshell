import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/prepared-reader-images"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "prepared reader evidence identity unavailable")
  return (result.stdout.splitOn " ").head!
def hashText (value : String) : IO String := do
  let scratch := base/"prepared-reader-images-record-text"
  IO.FS.writeFile scratch value
  try hash scratch finally IO.FS.removeFile scratch
def body (value : Json) : String :=
  ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
def events (root : System.FilePath) (receipt : String) : IO (Array (String × Json)) := do
  let folder := root/"private/receipts"/receipt
  let mut result := #[]
  if !(← folder.pathExists) then return result
  for entry in ← folder.readDir do
    if entry.fileName.endsWith ".json" &&
        (["operation-","search-phase-","numerical-","discovery-counters-"].any (fun stem => entry.fileName.startsWith stem) ||
         ["search.json","transport.json","failure.json","prepared-inputs-turn.json","prepared-owner-bindings.json",
          "prepared-reader-images.json","prepared-reader-unavailable.json"].contains entry.fileName) then
      result := result.push (entry.fileName,← read entry.path)
  return result
def compactTrace (row : Json) : IO Json := do
  return row.setObjVal! "tracesSha256" (toJson (← hashText (row.getObjValD "traces").compress))
    |>.setObjVal! "traces" Json.null
def main : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed evidence")
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "prepared-reader-images-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "prepared-reader-images-records" && !entry.fileName.startsWith "prepared-reader-images-cleanup" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      let path := base/(entry.fileName.replace ".guard.json" ".log")
      let lines := (← IO.FS.readFile path).splitOn "\n"
      guards := guards.push (entry.fileName,guard,← hash path,String.intercalate "\n" (lines.drop (lines.length-12)))
  let mut sourceHashes : Array (String × Option String × String) := #[]
  let mut patch := ""
  for name in ["PreparedReaders.lean","SynapseRecommend.lean","Handoff.lean","Worker.lean"] do
    let before := base/"prepared-reader-images-baseline-core/Eggshell"/name
    let after := base/"interest-traffic-core/Eggshell"/name
    let present ← before.pathExists
    let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--unified=0","--",
      (if present then before.toString else "/dev/null"),after.toString]}
    unless diff.exitCode == 1 do throw (IO.userError "isolated prepared reader patch missing")
    patch := patch++(diff.stdout.replace ("a"++(base/"prepared-reader-images-baseline-core").toString++"/") "a/"
      |>.replace ("a"++(base/"interest-traffic-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
    sourceHashes := sourceHashes.push (name,← (if present then some <$> hash before else pure none),← hash after)
  IO.FS.writeFile (output/"candidate.patch") (String.intercalate "\n" ((patch.splitOn "\n").map fun line =>
    if line.startsWith "@@" then (line.splitOn " @@").head!++" @@" else line))
  let mut unchanged := #[]
  for name in ["PreparedInputs.lean","OwnerViews.lean","SourceOwners.lean","SourceBitmap.lean","DB/PageMap.lean",
      "ProjectSources.lean","ProjectAccess.lean","PluginProjectContext.lean","PluginModel.lean","GraphStore.lean",
      "SynapseIndex.lean","SynapseTransport.lean","MiniLM.lean","Numerical.lean","SearchProvider.lean","BlockScore.lean",
      "PublicationService.lean","PublicationClient.lean","PublicationWire.lean","OperationPool.lean","Matcher.lean","Extract.lean"] do
    let prior ← hash (base/"prepared-reader-images-baseline-core/Eggshell"/name)
    let current ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless prior == current do throw (IO.userError ("unrelated source changed: "++name))
    unchanged := unchanged.push (name,current)
  let auditPath := base/"prepared-reader-images-audit3-result/report.json"
  let audit ← read auditPath
  unless audit.getObjValD "allPassed" == toJson true do throw (IO.userError "native prepared-reader audit failed")
  let rows ← IO.ofExcept (audit.getObjValAs? (Array Json) "rows")
  let reordered ← IO.ofExcept (fromJson? (audit.getObjValD "reordered") : Except String (Json × Json))
  let audit := audit.setObjVal! "rows" (toJson (← rows.mapM compactTrace))
    |>.setObjVal! "reordered" (toJson (← compactTrace reordered.1,← compactTrace reordered.2))
  let synthetic := base/"prepared-reader-images-synthetic"
  let syntheticRows ← IO.ofExcept (fromJson? (← read (synthetic/"prepared-readers.json")) : Except String (Array Json))
  let syntheticReport ← read (synthetic/"report.json")
  let mut profiles := #[]
  let mut checks := #[]
  let mut actualBodies : Array (String × String) := #[]
  for pair in ["1","2","3","-lexical1"] do
    for arm in ["parent","candidate"] do
      let root := base/s!"prepared-reader-images-{arm}{pair}-result"
      let files ← ["report.json","warm-result.json","stages.json"].toArray.mapM fun (name : String) => do
        return (name,← read (root/name))
      let traces ← ["cold-frontend-trace.txt","running-frontend-trace.txt"].toArray.mapM fun (name : String) => do
        return (name,← IO.FS.readFile (root/name))
      profiles := profiles.push (arm++pair,← IO.FS.readFile (root/"runtime.sha256"),files,traces)
    let before := base/s!"prepared-reader-images-parent{pair}-result"
    let after := base/s!"prepared-reader-images-candidate{pair}-result"
    let _ ← read (after/"paired-bodies.json")
    for name in ["cold-frontend","running-frontend"] do
      let left := body (← read (before/(name++"-stdout.json")))
      let right := body (← read (after/(name++"-stdout.json")))
      unless !left.isEmpty && left == right do throw (IO.userError "actual paired body changed")
      let digest ← hashText left
      if !actualBodies.any (·.1 == digest) then actualBodies := actualBodies.push (digest,left)
      checks := checks.push (pair,name,left.utf8ByteSize,digest)
  let mut loads := #[]
  for tag in ["prepared-reader-images-parent-readback1","prepared-reader-images-readback1"] do
    let root := base/(tag++"-result")
    let mut hooks := #[]
    let mut stages := #[]
    let mut delivered := 0
    let mut admitted := 0
    let mut captures := 0
    for entry in ← root.readDir do
      if !entry.fileName.endsWith "-measurement.json" then continue
      let row ← read entry.path
      let text := (row.getObjValAs? String "body").toOption.getD ""
      let head := text.contains "\"observed-head-case-79-7b319c\""
      let tail := text.contains "\"observed-tail-case-79-d82a04\""
      if head && tail && row.getObjValD "complete" == toJson true then delivered := delivered+1
      let logs ← events root (← IO.ofExcept (row.getObjValAs? String "receipt"))
      if logs.any (fun (name,_) => name.endsWith "-admitted.json") then admitted := admitted+1
      if logs.any (fun (name,value) => name == "prepared-inputs-turn.json" &&
          (value.getObjValD "data").getObjValD "status" == toJson "complete") then captures := captures+1
      stages := stages.push (entry.fileName,logs)
      let digest ← hashText text
      if !actualBodies.any (·.1 == digest) then actualBodies := actualBodies.push (digest,text)
      hooks := hooks.push (entry.fileName,row.setObjVal! "body" Json.null |>.setObjVal! "bodySha256" (toJson digest)
        |>.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
      let framed ← IO.FS.readFile (root/(entry.fileName.replace "-measurement.json" ".json"))
      unless framed.endsWith "\n" && (← hashText (framed.dropEnd 1).toString) ==
          (row.getObjValAs? String "outputSha256").toOption.getD "" do throw (IO.userError "native receiver output differs from receipt")
    unless hooks.size == 80 && captures == 80 do throw (IO.userError "incomplete eighty-reader boundary measurements")
    let original ← read (root/"before-originals.json")
    unless original.getObjValD "allExactInputOutput" == toJson true do throw (IO.userError "saved native input/output differed")
    let results ← read (root/"readers-results.json")
    loads := loads.push (Json.mkObj [("tag",toJson tag),("runtime",toJson (← IO.FS.readFile (root/"runtime.sha256"))),
      ("delivered",toJson delivered),("admitted",toJson admitted),("completeCaptures",toJson captures),
      ("originals",original),("hooks",toJson hooks),("stages",toJson stages),
      ("clientErrors",results.getObjValD "errors")])
  let source := base/"frontend-quiescence-fixture-small1"
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == (← read (source/"frozen-readback.json")).getObjValD "sourceHeads" do throw (IO.userError "original cut changed")
  for (tag,name) in [("prepared-reader-images-proofs2","laws.txt"),("prepared-reader-images-contract1","contract-audit.txt")] do
    let path := base/(tag++".log")
    let lines := (← IO.FS.readFile path).splitOn "\n"
    IO.FS.writeFile (output/name) ("Full output SHA-256: "++(← hash path)++"\n"++String.intercalate "\n" (lines.drop (lines.length-16)))
  let identities ← ["prepared-reader-images-audit3","prepared-reader-images-captured1","prepared-reader-images-fixture1"].toArray.mapM fun (tag : String) => do
    return (tag,← IO.FS.readFile (base/(tag++".runtime.sha256")))
  let evidence := Json.mkObj [("parent",toJson "4526171e83f163f62d60347f0c57a96e7c829b50"),
    ("sourceHashes",toJson sourceHashes),("unchanged",toJson unchanged),("guards",toJson guards),
    ("nativeAudit",audit),("auditReportSha256",toJson (← hash auditPath)),
    ("synthetic",syntheticReport),("syntheticPreparedReaders",toJson (← syntheticRows.mapM compactTrace)),
    ("runtimeIdentities",toJson identities),("profiles",toJson profiles),("bodyChecks",toJson checks),
    ("loads",toJson loads),("actualBodiesBySha256",toJson actualBodies),("originalHeads",toJson heads),
    ("runtimeSha256",toJson (← hash (base/"prepared-reader-images-build/StudyMain"))),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedComparisons",toJson "0/18"),("adopted",toJson false)]
  IO.FS.writeFile (output/"evidence.json") (evidence.compress++"\n")
  IO.println (toJson (loads.map fun load => (load.getObjValD "tag",load.getObjValD "delivered"))).compress
