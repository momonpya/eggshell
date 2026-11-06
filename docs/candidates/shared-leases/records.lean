import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def destination : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/shared-leases"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def digest (value : String) : IO String := do
  let output ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some value)
  check (output.exitCode == 0) "cannot hash actual bytes"
  return (output.stdout.splitOn " ").headD ""
def compactReceipt (value : Json) : Json := Json.mkObj (
  ["session","receipt","operation-service","search-phase-semantic","search-phase-lexical","transport","ack","published","actorFailures","request-pages","canonical-source-input","delivery-domain","keyed-nominations","source-acquisition-unavailable"].filterMap fun key =>
    let field := value.getObjValD key
    if field == Json.null then none else some (key,field))
def number (value : Json) (key : String) := (value.getObjValAs? Nat key).toOption.getD 0
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def verify (destination : System.FilePath) (evidence bodies : Array Json) (expected : Nat) : IO Unit := do
  for entry in bodies do
    let body ← IO.ofExcept (entry.getObjValAs? String "body")
    check (entry.getObjValD "sha256" == toJson (← digest body) &&
      entry.getObjValD "utf8Bytes" == toJson body.utf8ByteSize) "retained body bytes changed"
  let mut outputs := 0
  let mut results := #[]
  for run in evidence do
    for row in arr run "rowsIncludingPrime" do
      let some entry := bodies[number row "bodyRef"]? | throw (IO.userError "missing retained actual body")
      let body ← IO.ofExcept (entry.getObjValAs? String "body")
      let index := number row "case"
      let both := body.contains s!"\"observed-head-case-{index}-7b319c\"" &&
        body.contains s!"\"observed-tail-case-{index}-d82a04\""
      check (toJson both == row.getObjValD "bothFields" && entry.getObjValD "utf8Bytes" == row.getObjValD "bodyBytes") "retained evidence fields disagree"
      outputs := outputs+1
    let measured := (arr run "rowsIncludingPrime").filter fun row =>
      !((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-prime-"
    if measured.isEmpty then continue
    let observations := ((arr run "waves").filter (fun wave => wave.getObjValD "name" != toJson "prime")).flatMap (arr · "receipts")
    let complete := observations.filter fun receipt =>
      let phase := receipt.getObjValD "search-phase-semantic"
      phase.getObjValD "status" == toJson "completed" && phase.getObjValD "hasHandoff" == toJson true
    let passed := measured.filter fun row => row.getObjValD "bothFields" == toJson true &&
      row.getObjValD "acknowledged" == toJson true && number row "elapsedMs" < 30000
    results := results.push (Json.mkObj [("tag",run.getObjValD "tag"),("queries",toJson measured.size),
      ("requiredOriginalAndAck",toJson passed.size),("semanticCompletedWithHandoff",toJson complete.size),
      ("latencyMs",distribution (measured.map (number · "elapsedMs"))),
      ("queueMs",distribution (observations.filterMap fun receipt =>
        ((receipt.getObjValD "operation-service").getObjValAs? Nat "queueMs").toOption)),
      ("emptySemanticCompletions",toJson (observations.filter fun receipt =>
        let phase := receipt.getObjValD "search-phase-semantic"
        phase.getObjValD "status" == toJson "completed" && phase.getObjValD "hasHandoff" == toJson false).size)])
  check (outputs == expected) "fixed pair output domain changed"
  IO.FS.writeFile (destination/"verification.json") (Json.mkObj [("actualOutputs",toJson outputs),
    ("distinctBodyDigests",toJson bodies.size),("runs",toJson results),("adopted",toJson false)]).pretty
def enrichedReceipt (root : System.FilePath) (value : Json) : IO Json := do
  let id ← IO.ofExcept (value.getObjValAs? String "receipt")
  let path := root/"private/receipts"/id/"request-pages.json"
  let mut value := value
  if ← path.pathExists then value := value.setObjVal! "request-pages" ((← read path).getObjValD "data")
  for stage in ["canonical-source-input","delivery-domain","keyed-nominations","source-acquisition-unavailable"] do
    let path := root/"private/receipts"/id/(stage++".json")
    if ← path.pathExists then
      let detail := (← read path).getObjValD "data"
      let summary := if stage == "canonical-source-input" || stage == "source-acquisition-unavailable" then detail else
        Json.mkObj (["synapticComplete","status","error","related","ranked"].filterMap fun key =>
          let field := detail.getObjValD key
          if field == Json.null then none else some (key,field))
      value := value.setObjVal! stage summary
  return compactReceipt value

def main (arguments : List String) : IO Unit := do
  let (destination,tags) := match arguments with
    | "--source-protocol" :: tags => (destination.parent.getD destination / "source-protocol",tags)
    | "--query-stages" :: tags => (destination.parent.getD destination / "query-stages",tags)
    | "--provider-stages" :: tags => (destination.parent.getD destination / "provider-stages",tags)
    | "--numerical-ready" :: tags => (destination.parent.getD destination / "numerical-ready",tags)
    | "--numerical-stages" :: tags => (destination.parent.getD destination / "numerical-stages",tags)
    | "--numerical-waits" :: tags => (destination.parent.getD destination / "numerical-waits",tags)
    | "--owned-receive" :: tags => (destination.parent.getD destination / "owned-receive",tags)
    | "--readonly-pages" :: tags => (destination.parent.getD destination / "readonly-pages",tags)
    | "--working-set" :: tags => (destination.parent.getD destination / "working-set",tags)
    | "--immutable-deadline" :: tags => (destination.parent.getD destination / "immutable-deadline",tags)
    | "--owner-metadata-image" :: tags => (destination.parent.getD destination / "owner-metadata-image",tags)
    | tags => (destination,tags)
  let evidencePath := destination/"evidence.json"
  let bodiesPath := destination/"bodies.json"
  let mut evidence : Array Json := #[]
  if ← evidencePath.pathExists then evidence := arr (← read evidencePath) "runs"
  let mut bodies : Array Json := #[]
  if ← bodiesPath.pathExists then bodies ← IO.ofExcept (← read bodiesPath).getArr?
  if let ["verify",count] := tags then
    let some count := count.toNat? | throw (IO.userError "explicit output count required")
    return ← verify destination evidence bodies count
  if tags == ["verify"] then return ← verify destination evidence bodies 35
  if tags == ["enrich"] then
    evidence ← evidence.mapM fun run => do
      let tag ← IO.ofExcept (run.getObjValAs? String "tag")
      let root := base/(tag++"-result")
      let waves ← (arr run "waves").mapM fun wave => do
        let receipts ← (arr wave "receipts").mapM (enrichedReceipt root)
        return wave.setObjVal! "receipts" (toJson receipts)
      return run.setObjVal! "waves" (toJson waves)
    let previous ← read evidencePath
    IO.FS.writeFile evidencePath (previous.setObjVal! "runs" (toJson evidence)).pretty
    return ← verify destination evidence bodies (evidence.foldl (fun count run => count+(arr run "rowsIncludingPrime").size) 0)
  let mut indices : Std.HashMap String Nat := {}
  for entry in bodies.zipIdx do
    let body ← IO.ofExcept (entry.1.getObjValAs? String "body")
    indices := indices.insert body entry.2
  for tag in tags do
    check ((tag.startsWith "shared-leases-" || tag.startsWith "hosted-endpoint-" ||
      tag.startsWith "source-protocol-overlap" || tag.startsWith "task-observer-" ||
      tag.startsWith "task-waiter-" || tag.startsWith "query-stages-" || tag.startsWith "provider-stages-" ||
      tag.startsWith "numerical-ready-" || tag.startsWith "numerical-stages-" || tag.startsWith "numerical-waits-" ||
      tag.startsWith "owned-receive-" || tag.startsWith "readonly-pages-" || tag.startsWith "working-set-" ||
      tag.startsWith "immutable-deadline-" || tag.startsWith "owner-metadata-image-") &&
      !evidence.any (fun run => run.getObjValD "tag" == toJson tag)) "fresh dispatch record required"
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "guard is not drained"
    let pid ← IO.ofExcept (guard.getObjValAs? Nat "guardPid")
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
    check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "guard process still live"
    let root := base/(tag++"-result")
    let incompleteReport := !(← (root/"report.json").pathExists) && (← (root/"prime-checkpoint.json").pathExists)
    let report ← if ← (root/"report.json").pathExists then read (root/"report.json") else if ← (root/"direct-events.json").pathExists then read (root/"direct-events.json") else if incompleteReport then do
        pure (Json.mkObj [("prime",← read (root/"prime-checkpoint.json"))])
      else pure Json.null
    let waves := (#[report.getObjValD "prime",report.getObjValD "first",report.getObjValD "second"]++arr report "remaining").filter (· != Json.null)
    let mut captured := #[]
    let mut observations := #[]
    for wave in waves do
      for row in arr wave "rows" do
        let session ← IO.ofExcept (row.getObjValAs? String "session")
        let raw ← IO.FS.readFile (root/(session++".stdout"))
        check (toJson (← digest raw) == row.getObjValD "stdoutSha256") "actual stdout changed"
        let output ← IO.ofExcept (Json.parse raw)
        let body := ((output.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
        let index ← match indices[body]? with
          | some index => pure index
          | none => do
            let index := bodies.size
            bodies := bodies.push (Json.mkObj [("body",toJson body),("sha256",toJson (← digest body)),("utf8Bytes",toJson body.utf8ByteSize)])
            indices := indices.insert body index
            pure index
        let indexCase ← IO.ofExcept (row.getObjValAs? Nat "case")
        let both := body.contains s!"\"observed-head-case-{indexCase}-7b319c\"" &&
          body.contains s!"\"observed-tail-case-{indexCase}-d82a04\""
        check (toJson both == row.getObjValD "bothFields" && toJson body.utf8ByteSize == row.getObjValD "bodyBytes") "independent original-field/body audit differs"
        captured := captured.push (row.setObjVal! "bodyRef" (toJson index))
      let receipts ← (arr wave "receipts").mapM (enrichedReceipt root)
      observations := observations.push (Json.mkObj [("name",wave.getObjValD "name"),("serviceStats",wave.getObjValD "serviceStats"),
        ("persistentCpu",wave.getObjValD "persistentCpu"),("receipts",toJson receipts)])
    for entry in ← if ← root.pathExists then root.readDir else pure #[] do
      if entry.fileName.endsWith ".stdout" then
        check (captured.any fun row => row.getObjValD "session" == toJson (entry.fileName.dropEnd 7 |>.toString)) "actual stdout omitted from retained evidence"
    let mut fields := [("tag",toJson tag),("guard",guard),("rowsIncludingPrime",toJson captured),("waves",toJson observations),
      ("stoppedBeforeClientReport",toJson incompleteReport),("missingClientLatenciesUnmeasured",toJson incompleteReport)]
    for key in ["runtimeSha256","caseCount","concurrentClients","requestOwnedActors","originalHeadsUnchanged","independentSearchActors",
      "separateMutableFronts","oneSharedHitPerBorrower","fullDescriptorAndScopeChecked","pressureInsertions","maxEncodedReferencedBytes","maxEntries","left","right","shared","earlyCompletions","parallelNativeTimers","exactPayloadsAndOrder","exceptionsPreserved","validEmptyPreserved","expiredCompletionRefused","elapsedMs","sameChatSequential","metadataAndCountBounds","saveLanesRemainIndependent","staleTokensRejected",
      "cancelledTaskJoinedPeerCompleted","expiredTaskJoined","actualHookCapacityTested","concurrentCuts","sourcesPerCut","retainedTokens","acquisitionElapsedMs","full","drained","final","oneCachePinPerDescriptor","foreignScopeRootManifestRejected","activeReleaseExpiryCloseAccounted",
      "parallelTasks","monotoneChecksPerTask","completedBeforeRegistration","originalErrorPreserved",
      "unresolvedReplyNotComplete","emptyReplyAndDroppedOwnerDistinct","cancelledTaskFinalizerJoined","peerUnaffected"] do
      if report.getObjValD key != Json.null then fields := fields++[(key,report.getObjValD key)]
    if ← (base/(tag++".log")).pathExists then
      let log ← IO.FS.readFile (base/(tag++".log"))
      fields := fields++[("logSha256",toJson (← digest log))]
      if guard.getObjValD "exitCode" != toJson (0 : Nat) then fields := fields++[("failureLog",toJson (String.intercalate "\n" ((log.splitOn "\n").filter (fun line => line.contains "error:" || line.contains "failed:" || line.contains "missing module:") |>.take 20)))]
    evidence := evidence.push (Json.mkObj fields)
  IO.FS.writeFile bodiesPath (toJson bodies).pretty
  IO.FS.writeFile evidencePath (Json.mkObj [("runs",toJson evidence),("actualBodies",toJson bodies.size),
    ("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisons",toJson "0/18"),("adopted",toJson false)]).pretty
