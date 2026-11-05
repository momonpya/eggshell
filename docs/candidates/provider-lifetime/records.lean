import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/provider-lifetime"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal file identity")
  return (result.stdout.splitOn " ").head!
def hashText (text : String) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some text)
  unless result.exitCode == 0 do throw (IO.userError "cannot seal received bytes")
  return (result.stdout.splitOn " ").head!
def events (root : System.FilePath) (receipt : String) : IO (Array (String × Json)) := do
  let directory := root/"private/receipts"/receipt
  let mut rows := #[]
  if ← directory.pathExists then
    for entry in ← directory.readDir do
      if entry.fileName.endsWith ".json" &&
          (entry.fileName.endsWith "-profile.json" ||
           ["operation-","search-phase-","worker-restoration-","numerical-"].any (entry.fileName.startsWith ·) ||
           ["prepared-inputs-turn.json","prepared-reader-images.json","search.json","failure.json"].contains entry.fileName) then
        rows := rows.push (entry.fileName,← read entry.path)
  return rows
def main : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed evidence")
  let mut guards := #[]
  let mut trials := #[]
  let mut bodies : Array (String × String) := #[]
  let mut loads := #[]
  for entry in ← base.readDir do
    if !entry.fileName.startsWith "provider-lifetime-" then continue
    if entry.fileName.endsWith ".guard.json" && !entry.fileName.contains "records" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "guard still owns work")
      let log := base/(entry.fileName.replace ".guard.json" ".log")
      let text ← if ← log.pathExists then IO.FS.readFile log else pure ""
      let lines := text.splitOn "\n"
      guards := guards.push (entry.fileName,guard,String.intercalate "\n" (lines.drop (lines.length-16)))
    if entry.fileName.endsWith "-result" && (← entry.path.isDir) then
      let mut files : Array (String × Json) := #[]
      for name in ["report.json","rows.json","stages.json","runtime.sha256","paired-bodies.json",
          "frozen-request.json","pair-0-process.json","seed-originals.json","writers-originals.json",
          "seed-ready.json","writers-ready.json","frozen-readback.json"] do
        let path := entry.path/name
        if ← path.pathExists then
          let value ← if name.endsWith ".json" then read path else toJson <$> IO.FS.readFile path
          files := files.push (name,value)
      for name in ["cold-frontend-stdout.json","running-frontend-stdout.json"] do
        let path := entry.path/name
        if ← path.pathExists then
          let value ← read path
          let body ← IO.ofExcept ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
          let digest ← hash path
          let bodyHash ← hashText body
          if !bodies.any (·.1 == bodyHash) then bodies := bodies.push (bodyHash,body)
          files := files.push (name,Json.mkObj [("fileSha256",toJson digest),
            ("bodySha256",toJson bodyHash),("bodyBytes",toJson body.utf8ByteSize)])
      trials := trials.push (entry.fileName,files)
      if ← (entry.path/"writers-drain.json").pathExists then
        let samples ← IO.ofExcept (fromJson? (← read (entry.path/"writers-drain.json")) : Except String (Array Json))
        let summary := samples.map fun row => row.setObjVal! "sourceHeads" Json.null
        trials := trials.push (entry.fileName++"-drain",#[("samples",toJson summary)])
      if ← (entry.path/"writers-results.json").pathExists then
        let writers ← read (entry.path/"writers-results.json")
        let writerRows ← IO.ofExcept (writers.getObjValAs? (Array Json) "rows")
        let mut measurements := #[]
        for file in ← entry.path.readDir do
          if !file.fileName.endsWith "-measurement.json" || !file.fileName.startsWith "writer-" then continue
          let row ← read file.path
          let text := (row.getObjValAs? String "body").toOption.getD ""
          measurements := measurements.push (file.fileName,row.setObjVal! "body" Json.null
            |>.setObjVal! "bodySha256" (toJson (← hashText text)) |>.setObjVal! "bodyBytes" (toJson text.utf8ByteSize))
        trials := trials.push (entry.fileName++"-writer-summary",#[("writers",Json.mkObj [
          ("completeLoops",toJson writerRows.size),("errors",writers.getObjValD "errors"),("hooks",toJson measurements)])])
      if ← (entry.path/"readers-results.json").pathExists then
        let results ← read (entry.path/"readers-results.json")
        let mut hooks := #[]
        let mut stages := #[]
        let mut delivered := 0
        let mut admitted := 0
        let mut captures := 0
        for file in ← entry.path.readDir do
          if !file.fileName.endsWith "-measurement.json" || !file.fileName.contains "-readback-UserPromptSubmit" then continue
          let row ← read file.path
          let text := (row.getObjValAs? String "body").toOption.getD ""
          let head := text.contains "\"observed-head-case-79-7b319c\""
          let tail := text.contains "\"observed-tail-case-79-d82a04\""
          if head && tail && row.getObjValD "complete" == toJson true then delivered := delivered+1
          let digest ← hashText text
          if !bodies.any (·.1 == digest) then bodies := bodies.push (digest,text)
          hooks := hooks.push (file.fileName,row.setObjVal! "body" Json.null
            |>.setObjVal! "bodySha256" (toJson digest) |>.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
          let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
          let logs ← events entry.path receipt
          if logs.any (fun (name,_) => name.endsWith "-admitted.json") then admitted := admitted+1
          if logs.any (fun (name,value) => name == "prepared-inputs-turn.json" &&
              (value.getObjValD "data").getObjValD "status" == toJson "complete") then captures := captures+1
          stages := stages.push (file.fileName,logs)
          let output ← IO.FS.readFile (entry.path/(file.fileName.replace "-measurement.json" ".json"))
          unless output.endsWith "\n" && (← hashText (output.dropEnd 1).toString) ==
              (row.getObjValAs? String "outputSha256").toOption.getD "" do
            throw (IO.userError "native received bytes changed")
        let originalPath := if ← (entry.path/"before-originals.json").pathExists then
            entry.path/"before-originals.json" else entry.path/"writers-originals.json"
        let original ← read originalPath
        unless original.getObjValD "allExactInputOutput" == toJson true do
          throw (IO.userError "saved original input/output differed")
        loads := loads.push (Json.mkObj [("tag",toJson entry.fileName),("delivered",toJson delivered),
          ("admitted",toJson admitted),("completeCaptures",toJson captures),("originals",original),
          ("hooks",toJson hooks),("stages",toJson stages),("clientErrors",results.getObjValD "errors")])
  let mut patch := ""
  let mut sources := #[]
  for name in ["BuiltinSearch.lean","SemanticMatcher.lean","KeyedSearchClient.lean","Numerical.lean",
      "Handoff.lean","PublicationWire.lean","ContractAudit.lean"] do
    let before := base/"provider-lifetime-baseline-core/Eggshell"/name
    let after := base/"interest-traffic-core/Eggshell"/name
    let present ← before.pathExists
    let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--unified=0","--",
      (if present then before.toString else "/dev/null"),after.toString]}
    unless diff.exitCode ≤ 1 do throw (IO.userError "cannot seal candidate patch")
    patch := patch ++ (diff.stdout.replace ("a"++before.toString) ("a/Eggshell/"++name)
      |>.replace ("a"++after.toString) ("a/Eggshell/"++name)
      |>.replace ("b"++after.toString) ("b/Eggshell/"++name))
    let beforeHash ← if present then some <$> hash before else pure none
    sources := sources.push (name,beforeHash,← hash after)
  IO.FS.writeFile (output/"candidate.patch") patch
  let runtime ← hash (base/"provider-native-build/StudyMain")
  let parent ← hash (base/"prepared-reader-images-build/StudyMain")
  let source := base/"frontend-quiescence-fixture-small1"
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == (← read (source/"frozen-readback.json")).getObjValD "sourceHeads" do
    throw (IO.userError "original cut changed")
  IO.FS.writeFile (output/"evidence.json") (Json.mkObj [("runtimeSha256",toJson runtime),
    ("probeRuntimeSha256",toJson (← hash (base/"provider-lifetime-build/StudyMain"))),
    ("parentRuntimeSha256",toJson parent),("sourceHashes",toJson sources),("guards",toJson guards),
    ("trials",toJson trials),("loads",toJson loads),("originalHeads",toJson heads),
    ("actualBodies",toJson bodies),("answeringModelCalls",toJson (0 : Nat)),
    ("matchedPaidComparisons",toJson "0/18"),("adopted",toJson false)]).compress
