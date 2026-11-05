import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def output := workspace/"docs/candidates/local-selection"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless reply.exitCode == 0 do throw (IO.userError "file identity unavailable")
  return (reply.stdout.splitOn " ").head!
def hashText (value : String) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some value)
  unless reply.exitCode == 0 do throw (IO.userError "body identity unavailable")
  return (reply.stdout.splitOn " ").head!
def distribution (values : Array Nat) : Json := Id.run do
  let rows := values.qsort (· < ·)
  return Json.mkObj [("count",toJson rows.size),("min",toJson rows[0]?),
    ("median",toJson rows[rows.size/2]?),("max",toJson rows.back?)]
def phases (root : System.FilePath) : IO (Array (String × Json)) := do
  let mut values := #[]
  let directory := root/"private/receipts"
  if !(← directory.pathExists) then return values
  for receipt in ← directory.readDir do
    if (← receipt.path.symlinkMetadata).type != .dir then continue
    for entry in ← receipt.path.readDir do
      let name := entry.fileName
      let keep := ["operation-","search-phase-","numerical-","provider-","discovery-counters-"].any (fun start => name.startsWith start) ||
        ["render-selector-path.json","render-automatic-profile.json","render-client-profile.json", "source-plan-profile.json",
          "client-profile.json","server-envelope-profile.json","stream-exchange-profile.json","stream-receive-profile.json",
          "prepared-inputs-turn.json","prepared-reader-images.json","prepared-owner-bindings.json"].contains name
      if keep && name.endsWith ".json" then values := values.push (receipt.fileName++"/"++name,← read entry.path)
  return values
partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← erase entry.path)
    IO.FS.removeDir path
    return bytes
  unless metadata.type == .file || metadata.type == .symlink do throw (IO.userError "special cleanup input")
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def cleanup : IO Unit := do
  unless (← (output/"evidence.json").pathExists) && !(← (output/"cleanup.json").pathExists) do
    throw (IO.userError "seal evidence first and preserve prior cleanup receipt")
  let originals ← IO.ofExcept (fromJson? (← read (base/"semantic-phase-native1-result/original-heads.json")) :
    Except String (Array (String × String × String)))
  let verify := do
    for (path,expected,digest) in originals do
      unless (← IO.FS.readFile (.mk path)) == expected && (← hash (.mk path)) == digest do
        throw (IO.userError "active fixed original changed")
  verify
  for entry in ← base.readDir do
    if !(["local-selection-","semantic-phase-"].any (fun start => entry.fileName.startsWith start)) ||
        !entry.fileName.endsWith ".guard.json" then continue
    let guard ← read entry.path
    unless guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "live work at cleanup")
  let mut removed := #[]
  for name in ["semantic-phase-native1-result","semantic-phase-oracle1-result","local-selection-pairs1-result",
      "local-selection-mixed1-result"] do
    let path := base/name
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if ["local-selection-","semantic-phase-"].any (fun start => entry.fileName.startsWith start) &&
        [".guard.json",".guard-settings.json",".log"].any (fun suffix => entry.fileName.endsWith suffix) then
      removed := removed.push (entry.path.toString,← erase entry.path)
  verify
  let receipt := Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun total item => total+item.2) (0 : Nat))),
    ("activeFixedOriginalHeadsUnchanged",toJson true),("activeSourceAndBuildInputsRetained",toJson true),
    ("archiveCreated",toJson false)]
  IO.FS.writeFile (output/"cleanup.json") receipt.pretty
  IO.println (receipt.setObjVal! "removed" Json.null).compress
def retireChecks (candidateSha groupedSha : String) : IO Unit := do
  unless (← (output/"evidence.json").pathExists) && !(← (output/"retirement.json").pathExists) do
    throw (IO.userError "seal checks before retiring their ended executables")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axww","-o","command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot check live executable users")
  let mut retired := #[]
  for (name,expected) in [("local-selection-build",candidateSha),("grouped-ingress-build",groupedSha)] do
    let path := base/name/"StudyMain"
    unless expected.length == 64 && (← path.symlinkMetadata).type == .file && (← hash path) == expected do
      throw (IO.userError "ended executable identity changed")
    if processes.stdout.splitOn "\n" |>.any (fun line =>
        let text := line.trimAscii.toString
        text == path.toString || text.startsWith (path.toString++" ")) then
      throw (IO.userError "ended executable is still running")
    for entry in ["runtime.rsp","object-mapping.json","lib"] do
      unless ← (base/name/entry).pathExists do throw (IO.userError "retain live link inputs before executable retirement")
    let bytes := (← path.metadata).byteSize.toNat
    IO.FS.removeFile path
    retired := retired.push (path.toString,expected,bytes)
  let receipt := Json.mkObj [("removed",toJson retired),
    ("apparentBytes",toJson (retired.foldl (fun n item => n+item.2.2) (0 : Nat))),
    ("serviceExecutablesAndLinkInputsRetained",toJson true),("archiveCreated",toJson false)]
  IO.FS.writeFile (output/"retirement.json") receipt.pretty
  IO.println receipt.compress
def main (args : List String) : IO Unit := do
  if let ["retire-checks",candidateSha,groupedSha] := args then return ← retireChecks candidateSha groupedSha
  if args == ["cleanup"] then return ← cleanup
  let previous ← if args == ["repair-reader-scope"] then do
      -- The unscoped evidence is large. Bind its streaming file hash and the
      -- small sidecar summary; do not parse that entire old tree to repair it.
      let old ← read (output/"mixed-summary.json")
      let observations ← IO.ofExcept (old.getObjValAs? Nat "observedServiceOperations")
      let readers ← IO.ofExcept (old.getObjValAs? Nat "readerMeasurements")
      unless observations > readers && (← hash (base/"local-selection-traffic-build/StudyMain")) ==
          "b275aae992d10c66dc3b10d9d6dddaf76a27976849b81de435ec657b24388fcf" do
        throw (IO.userError "prior unscoped evidence/runtime changed")
      pure (some (← hash (output/"evidence.json"),old))
    else do
      unless args.isEmpty && !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed evidence")
      pure none
  let mut guards := #[]
  for entry in ← base.readDir do
    if !(["local-selection-","semantic-phase-"].any (fun start => entry.fileName.startsWith start)) ||
        !entry.fileName.endsWith ".guard.json" then continue
    let guard ← read entry.path
    unless guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "guard still owns work")
    let log := base/(entry.fileName.replace ".guard.json" ".log")
    guards := guards.push (entry.fileName,guard,← IO.FS.readFile log)
  let mut patch := ""
  let mut sources := #[]
  for name in ["Handoff","PublicationService"] do
    let relative := "Eggshell/"++name++".lean"
    let parent := base/"local-selection-baseline-core"
    let core := base/"interest-traffic-core"
    let diff ← IO.Process.output {
      cmd := "/usr/bin/git"
      args := #["diff","--no-index","--no-prefix","--unified=0","--",(parent/relative).toString,(core/relative).toString]}
    unless diff.exitCode ≤ 1 && diff.stderr.isEmpty do throw (IO.userError "cannot capture isolated candidate")
    patch := patch++(diff.stdout.replace ((parent.toString.drop 1).toString++"/") "a/"
      |>.replace ((core.toString.drop 1).toString++"/") "b/")
    sources := sources.push (relative,← hash (parent/relative),← hash (core/relative))
  IO.FS.writeFile (output/"candidate.patch") patch
  let pairsRoot := base/"local-selection-pairs1-result"
  let paired ← read (pairsRoot/"report.json")
  unless paired.getObjValD "actualBodiesByteEqual" == toJson true do throw (IO.userError "paired actual bodies differ")
  let mut profiles := #[]
  let mut body : Option String := none
  let trials ← IO.ofExcept (paired.getObjValAs? (Array Json) "trials")
  let mut roots := #[base/"semantic-phase-native1-result",base/"semantic-phase-oracle1-result"]
  for trial in trials do roots := roots.push (.mk (← IO.ofExcept (trial.getObjValAs? String "directory")))
  for root in roots do
    let report ← read (root/"report.json")
    let rows ← IO.ofExcept (report.getObjValAs? (Array Json) "rows")
    for row in rows do
      let text ← IO.ofExcept (row.getObjValAs? String "body")
      if let some expected := body then
        unless text == expected do throw (IO.userError "profile evidence body changed")
      else body := some text
    profiles := profiles.push (root.toString,Json.mkObj [
      ("report",report.setObjVal! "rows" (toJson (rows.map (·.setObjVal! "body" Json.null)))),
      ("warm",← read (root/"warm.json")),("trace",toJson (← IO.FS.readFile (root/"handoff.trace"))),
      ("originalHeads",← read (root/"original-heads.json")),("phases",toJson (← phases root))])
  let mixedRoot := base/"local-selection-mixed1-result"
  let frozen ← IO.ofExcept ((← read (mixedRoot/"frozen-readback.json")).getObjValAs? (Array Json) "sourceHeads")
  for owner in [:frozen.size] do
    let current ← read (mixedRoot/"work.project/owners"/toString owner/"source.egg/head")
    unless some current == frozen[owner]? do throw (IO.userError "readback changed a frozen original source head")
  let mut received := #[]
  let mut readerReceipts : Array String := #[]
  let mut durations := #[]
  let mut delivered := 0
  for entry in ← mixedRoot.readDir do
    if !entry.fileName.startsWith "reader-" || !entry.fileName.endsWith "-measurement.json" then continue
    let row ← read entry.path
    readerReceipts := readerReceipts.push (← IO.ofExcept (row.getObjValAs? String "receipt"))
    let text ← IO.ofExcept (row.getObjValAs? String "body")
    let actual ← IO.FS.readFile (mixedRoot/(entry.fileName.replace "-measurement.json" ".json"))
    unless actual.endsWith "\n" && toJson (← hashText (actual.dropEnd 1).toString) == row.getObjValD "outputSha256" do
      throw (IO.userError "mixed receiver differs from recorded output")
    let complete := text.contains "\"observed-head-case-79-7b319c\"" && text.contains "\"observed-tail-case-79-d82a04\""
    let elapsed ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
    durations := durations.push elapsed
    if complete && row.getObjValD "complete" == toJson true && elapsed < 30000 then delivered := delivered+1
    received := received.push (entry.fileName,row.setObjVal! "bothOriginalFields" (toJson complete))
  let mut mixedFiles := #[]
  for name in ["writers-results.json","readers-results.json","writers-drain.json","seed-drain.json",
      "writers-originals.json","retained-original-audit.json","frozen-readback.json","report.json"] do
    if ← (mixedRoot/name).pathExists then mixedFiles := mixedFiles.push (name,← read (mixedRoot/name))
  let mixedPhases := (← phases mixedRoot).filter fun (name,_) => readerReceipts.contains (name.splitOn "/").head!
  let services := mixedPhases.filterMap fun (name,value) =>
    if name.endsWith "operation-service.json" then some (value.getObjValD "data") else none
  let values := fun key => services.filterMap fun value => (value.getObjValAs? Nat key).toOption
  let summary := Json.mkObj [("readerMeasurements",toJson received.size),("deliveredWithin30s",toJson delivered),
    ("semanticCompleted",toJson (mixedPhases.filter fun (name,value) =>
      name.endsWith "search-phase-semantic.json" && (value.getObjValD "data").getObjValD "status" == toJson "completed").size),
    ("lexicalCompleted",toJson (mixedPhases.filter fun (name,value) =>
      name.endsWith "search-phase-lexical.json" && (value.getObjValD "data").getObjValD "status" == toJson "finished").size),
    ("failureInclusiveHookMs",distribution durations),("observedServiceOperations",toJson services.size),
    ("observedQueueMs",distribution (values "queueMs")),("observedWorkMs",distribution (values "workMs"))]
  IO.FS.writeFile (output/"mixed-summary.json") summary.pretty
  let originalBody := body.getD ""
  let evidence := Json.mkObj [("adopted",toJson false),("sources",toJson sources),("guards",toJson guards),
    ("componentRuntimeSha256",toJson (← hash (base/"local-selection-build/StudyMain"))),
    ("trafficRuntimeSha256",toJson (← hash (base/"local-selection-traffic-build/StudyMain"))),
    ("candidatePatchSha256",toJson (← hash (output/"candidate.patch"))),("paired",paired),("profiles",toJson profiles),
    ("actualProfileBody",toJson originalBody),("profileBodySha256",toJson (← hashText originalBody)),
    ("mixed",Json.mkObj [("summary",summary),("files",toJson mixedFiles),("received",toJson received),
      ("frozenOriginalHeadsUnchanged",toJson true),("frozenOriginalHeadCount",toJson frozen.size),("phases",toJson mixedPhases)]),
    ("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisonsCompleted",toJson (0 : Nat)),
    ("real98PercentDeliveryValidated",toJson false),("sustained80PersonCapacityValidated",toJson false)]
  let evidence := if let some (before,summary) := previous then
      evidence.setObjVal! "readerScopeRepair" (Json.mkObj [("beforeEvidenceSha256",toJson before),
        ("previousUnscopedSummary",summary),
        ("reason",toJson "restrict operation/semantic counts to the actual eighty reader receipt IDs; writer phases are not reader timings; native trials unchanged"),
        ("recordingMemoryRepair",toJson "old full-tree parsing exceeded the unchanged 512 MiB interpreter limit; use its streaming digest and regenerate scoped evidence from ended raw files")])
    else evidence
  IO.FS.writeFile (output/"evidence.json") (evidence.compress++"\n")
  IO.println summary.compress
