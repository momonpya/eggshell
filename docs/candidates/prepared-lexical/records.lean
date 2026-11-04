import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/prepared-lexical"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "identity hashing failed")
  return (result.stdout.splitOn " ").head!
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.compress++"\n")
def body (value : Json) : String :=
  ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
def main : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed evidence")
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "prepared-lexical-" && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.startsWith "prepared-lexical-records" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      let path := base/(entry.fileName.replace ".guard.json" ".log")
      let lines := (← IO.FS.readFile path).splitOn "\n"
      guards := guards.push (Json.mkObj [("tag",toJson entry.fileName),("guard",guard),
        ("logSha256",toJson (← hash path)),("tail",toJson (String.intercalate "\n" (lines.drop (lines.length-12))))])
  let prior := base/"prepared-lexical-baseline-core/Eggshell/SynapseTransport.lean"
  let current := base/"interest-traffic-core/Eggshell/SynapseTransport.lean"
  let diff ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--unified=0","--",prior.toString,current.toString]}
  unless diff.exitCode == 1 do throw (IO.userError "missing isolated candidate diff")
  IO.FS.writeFile (output/"candidate.patch") (diff.stdout.replace
    ("a"++(base/"prepared-lexical-baseline-core").toString++"/") "a/"
    |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
  let mut unchanged := #[]
  for name in ["MiniLM.lean","Numerical.lean","SearchProvider.lean","BlockScore.lean","GraphStore.lean","DB/PageMap.lean",
      "NativePublication.lean","ProjectSources.lean","PublicationService.lean","Handoff.lean","SearchRank.lean","SourceOwners.lean",
      "HookFrontend.lean","Matcher.lean","Extract.lean","Worker.lean","PluginHooks.lean","OperationPool.lean","Daemon.lean"] do
    let before ← hash (base/"prepared-lexical-baseline-core/Eggshell"/name)
    let actual ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless before == actual do throw (IO.userError ("unrelated source changed: "++name))
    unchanged := unchanged.push (name,actual)
  let audit := base/"prepared-lexical-fixture-prepared-lexical-audit1"
  let mut audited := #[]
  for name in ["report.json","postings.json","ranking.json","timings.json"] do audited := audited.push (name,← read (audit/name))
  let mut profiles := #[]
  for tag in ["prepared-lexical-profile1","prepared-lexical-profile2","prepared-lexical-meaning1"] do
    let root := base/("prepared-lexical-fixture-"++tag)
    let mut files := #[]
    for name in ["runtime.sha256","warm-result.json","report.json","rows.json","stages.json",
        "cold-frontend-stdout.json","running-frontend-stdout.json","cold-frontend-trace.txt","running-frontend-trace.txt"] do
      files := files.push (name,← IO.FS.readFile (root/name))
    profiles := profiles.push (tag,files)
  let oldEvidence ← read (output.parent.get!/"query-work/evidence.json")
  let oldProfiles ← IO.ofExcept (fromJson? (oldEvidence.getObjValD "profiles") : Except String (Array (String × Array (String × String))))
  let some (_,old) := oldProfiles.find? (·.1 == "query-work-profile3") | throw (IO.userError "missing sealed meaning control")
  let mut comparisons := #[]
  for name in ["cold-frontend","running-frontend"] do
    let file := name++"-stdout.json"
    let before ← read (base/"prepared-lexical-fixture-prepared-lexical-profile1"/file)
    let after ← read (base/"prepared-lexical-fixture-prepared-lexical-profile2"/file)
    let some (_,encoded) := old.find? (·.1 == file) | throw (IO.userError "missing original meaning body")
    let meaningBefore ← IO.ofExcept (Json.parse encoded)
    let meaningAfter ← read (base/"prepared-lexical-fixture-prepared-lexical-meaning1"/file)
    unless !(body before).isEmpty do throw (IO.userError "vacuous lexical body")
    unless body before == body after && body meaningBefore == body meaningAfter do throw (IO.userError "actual body changed")
    comparisons := comparisons.push (name,Json.mkObj [("lexicalByteIdentical",toJson true),
      ("meaningByteIdentical",toJson true),("lexicalBodyBytes",toJson (body before).utf8ByteSize),
      ("meaningBodyBytes",toJson (body meaningBefore).utf8ByteSize)])
  let trial := base/"prepared-lexical-fixture-prepared-lexical-readback1"
  let mut hooks := #[]
  let mut stages := #[]
  let mut actual : Array (String × String) := #[]
  let mut delivered := 0
  let mut admitted := 0
  let mut times : List Nat := []
  for entry in ← trial.readDir do
    if !entry.fileName.endsWith "-measurement.json" then continue
    let row ← read entry.path
    let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
    let text := (row.getObjValAs? String "body").toOption.getD ""
    let head := text.contains "\"observed-head-case-79-7b319c\""
    let tail := text.contains "\"observed-tail-case-79-d82a04\""
    if head && tail && row.getObjValD "complete" == toJson true then delivered := delivered+1
    let mut observed := #[]
    for event in ← (trial/"private/receipts"/receipt).readDir do
      if event.fileName.endsWith ".json" &&
          (["operation-","search-phase-","numerical-","discovery-counters-"].any (fun stem => event.fileName.startsWith stem) ||
            ["search.json","failure.json","transport.json","prepared-inputs-turn.json"].contains event.fileName) then
        observed := observed.push (event.fileName,← read event.path)
    if observed.any (fun (name,_) => name.endsWith "-admitted.json") then admitted := admitted+1
    stages := stages.push (entry.fileName,observed)
    hooks := hooks.push (entry.fileName,row.setObjVal! "body" Json.null |>.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
    times := ((row.getObjValAs? Nat "elapsedMs").toOption.getD 0)::times
    let digest ← IO.ofExcept (row.getObjValAs? String "outputSha256")
    if !actual.any (·.1 == digest) then
      let framed ← IO.FS.readFile (trial/(entry.fileName.replace "-measurement.json" ".json"))
      unless framed.endsWith "\n" do throw (IO.userError "receiver framing changed")
      let payload := (framed.dropEnd 1).toString
      let scratch := base/"prepared-lexical-output-hash"
      IO.FS.writeFile scratch payload
      let checked ← try hash scratch finally IO.FS.removeFile scratch
      unless checked == digest do throw (IO.userError "actual output differs from receipt")
      actual := actual.push (digest,payload)
  unless hooks.size == 80 do throw (IO.userError "incomplete native burst measurements")
  let source := base/"frontend-quiescence-fixture-small1"
  let heads ← (List.range 16).toArray.mapM fun owner => read (source/"work.project/owners"/toString owner/"source.egg/head")
  unless toJson heads == (← read (source/"frozen-readback.json")).getObjValD "sourceHeads" do throw (IO.userError "original heads changed")
  let mut reports := #[]
  for name in ["before-originals.json","warm-result.json","warm-stdout.json","readers-results.json","report.json"] do
    if ← (trial/name).pathExists then reports := reports.push (name,← read (trial/name))
  for (tag,name) in [("prepared-lexical-proofs1","laws.txt"),("prepared-lexical-contract1","contract-audit.txt")] do
    let path := base/(tag++".log")
    let lines := (← IO.FS.readFile path).splitOn "\n"
    IO.FS.writeFile (output/name) ("Full output SHA-256: "++(← hash path)++"\n"++String.intercalate "\n" (lines.drop (lines.length-16)))
  let ordered := times.mergeSort (· ≤ ·)
  let summary := Json.mkObj [("readers",toJson hooks.size),("deliveredBothOriginalFields",toJson delivered),
    ("admitted",toJson admitted),("minMs",toJson (ordered.headD 0)),("maxMs",toJson (ordered.getLast?.getD 0)),
    ("allProfileBodiesByteIdentical",toJson true),("originalHeadsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedComparisons",toJson "0/18"),("adopted",toJson false)]
  save "evidence.json" (Json.mkObj [("parent",toJson "7fd3c3cde100ad45a076ec4fad43bc58e0121449"),
    ("sourceHashes",toJson (← hash prior,← hash current)),("unchanged",toJson unchanged),("guards",toJson guards),
    ("auditRuntime",toJson (← IO.FS.readFile (audit/"runtime.sha256"))),("audit",toJson audited),
    ("profiles",toJson profiles),("bodyChecks",toJson comparisons),
    ("runtimeSha256",toJson (← hash (base/"prepared-lexical-build/StudyMain"))),
    ("readbackRuntime",toJson (← IO.FS.readFile (trial/"runtime.sha256"))),
    ("reports",toJson reports),("hooks",toJson hooks),("stages",toJson stages),
    ("actualOutputsBySha256",toJson actual),("originalHeads",toJson heads),("summary",summary)])
  save "summary.json" summary
  IO.println summary.compress
