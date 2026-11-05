import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def destination := workspace/"docs/candidates/provider-stages"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def array (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def number (value : Json) (key : String) : Nat := (value.getObjValAs? Nat key).toOption.getD 0
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def run (path : System.FilePath) (args : Array String) : IO Unit := do
  let result ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
    args := #["-j1","-M1536","--run",path.toString]++args,cwd := some workspace}
  IO.print result.stdout
  IO.eprint result.stderr
  check (result.exitCode == 0) "provider-stage helper failed"
def analyze (output : System.FilePath := destination) : IO Unit := do
  let mut evidence := array (← read (output/"evidence.json")) "runs"
  if ← (output/"partial-evidence.json").pathExists then
    evidence := evidence.push (← read (output/"partial-evidence.json"))
  let mut analyses := #[]
  for item in evidence do
    let tag ← IO.ofExcept (item.getObjValAs? String "tag")
    let enabled := tag.startsWith "provider-stages-on" || tag.startsWith "numerical-ready-on"
    let mut spans : Array (String × Nat) := #[]
    let mut missing := #[]
    let mut statuses := #[]
    let mut traceCount := 0
    for wave in array item "waves" do
      if wave.getObjValD "name" == toJson "prime" then continue
      for receipt in array wave "receipts" do
        let pages := receipt.getObjValD "request-pages"
        check (pages.getObjValD "capacityBytes" != Json.null) "original request-page statistics omitted"
        let encoded := pages.getObjValD "queryStages"
        if !enabled then
          check (encoded == Json.null) "disabled trace emitted timestamps"
          continue
        let events ← IO.ofExcept (fromJson? encoded : Except String (Array (String × Nat)))
        check (!events.isEmpty && events[0]!.1 == "restore-request:start" &&
          events.back?.any (·.1 == "actor-finalized")) "request trace not finalized"
        for i in [1:events.size] do check (events[i-1]!.2 ≤ events[i]!.2) "timestamps regressed"
        traceCount := traceCount+1
        for ((label,start),i) in events.zipIdx do
          if label.endsWith ":start" then
            let name := label.dropEnd 6 |>.toString
            match (events.extract (i+1) events.size).find? (fun event => event.1 == name++":end") with
            | some (_,finish) => spans := spans.push (name,finish-start)
            | none => missing := missing.push (Json.mkObj [("receipt",receipt.getObjValD "receipt"),
                ("stage",toJson name),("durationMeasured",toJson false)])
        statuses := statuses.push (Json.mkObj [("receipt",receipt.getObjValD "receipt"),
          ("events",toJson (events.filter fun (name,_) => name.endsWith ":available" || name.endsWith ":unavailable" ||
            name.endsWith ":failed" || name.endsWith ":success" || name.endsWith ":hit" ||
            name.endsWith ":miss" || name.endsWith ":joined"))])
    let names := spans.toList.map (·.1) |>.eraseDups |>.toArray
    let rows := (array item "rowsIncludingPrime").filter fun row =>
      !((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-prime-"
    analyses := analyses.push (Json.mkObj [("tag",toJson tag),("traces",toJson traceCount),
      ("clientRowsUnavailable",item.getObjValD "clientRowsUnavailable"),
      ("actualRows",toJson rows.size),("bothOriginalFields",toJson (rows.filter (fun row => row.getObjValD "bothFields" == toJson true)).size),
      ("latencyMs",distribution (rows.map (fun row => number row "elapsedMs"))),
      ("completedSpans",toJson (names.map fun name => Json.mkObj [("stage",toJson name),
        ("wallMs",distribution (spans.filterMap fun (stage,ms) => if stage == name then some ms else none))])),
      ("missingEnds",toJson missing),("statuses",toJson statuses)])
  IO.FS.writeFile (output/"stages.json") (Json.mkObj [("runs",toJson analyses),
    ("wallTimeIsNotCpuTime",toJson true),("missingEndsAreUnmeasured",toJson true),
    ("nestedSpansNotAdditive",toJson true),("adopted",toJson false)]).pretty
def stopped (output : System.FilePath) : IO Unit := do
  let tag := "numerical-ready-on80-1"
  let root := base/(tag++"-result")
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "guardTriggered" == toJson true &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "stopped wave is not drained"
  check (!(← (root/"report.json").pathExists)) "do not replace a completed client report"
  let prime ← read (root/"prime.json")
  let primeIds := (array prime "receipts").map (fun row => row.getObjValD "receipt")
  let mut bodies : Array Json := #[]
  let mut rows := #[]
  for session in ((List.range 3).map (fun index => s!"cpu-prime-{index}")) ++
      ((List.range 80).map (fun index => s!"cpu-wave-a-{index}")) do
    let raw ← IO.FS.readFile (root/(session++".stdout"))
    let parsed ← IO.ofExcept (Json.parse raw)
    let body ← IO.ofExcept ((parsed.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
    let isPrime := session.startsWith "cpu-prime-"
    let suffix := (session.splitOn "-").getLast!
    let some index := suffix.toNat? | throw (IO.userError "missing output case")
    let both := body.contains s!"\"observed-head-case-{index}-7b319c\"" && body.contains s!"\"observed-tail-case-{index}-d82a04\""
    if !isPrime then check (!both && body.startsWith "EGGSHELL SEARCH INCOMPLETE") "unexpected stopped output"
    let reference := (bodies.findIdx? (fun entry => entry.getObjValD "body" == toJson body)).getD bodies.size
    let hash ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some body)
    let rawHash ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some raw)
    check (hash.exitCode == 0 && rawHash.exitCode == 0) "cannot retain stopped bytes"
    if reference == bodies.size then bodies := bodies.push (Json.mkObj [("body",toJson body),
      ("sha256",toJson ((hash.stdout.splitOn " ").headD "")),("utf8Bytes",toJson body.utf8ByteSize)])
    rows := rows.push (Json.mkObj [("session",toJson session),("case",toJson index),("prime",toJson isPrime),
      ("bodyRef",toJson reference),("bodyBytes",toJson body.utf8ByteSize),("bothFields",toJson both),
      ("stdoutSha256",toJson ((rawHash.stdout.splitOn " ").headD "")),
      ("clientElapsedMs",Json.null),("clientAcknowledgment",Json.null)])
  let mut receipts := #[]
  for directory in ← (root/"private/receipts").readDir do
    if !(← (directory.path/"request-pages.json").pathExists) then continue
    if primeIds.contains (toJson directory.fileName) then continue
    let mut fields := [("receipt",toJson directory.fileName),("session",Json.null),
      ("caseAssociationUnavailable",toJson true)]
    for stage in ["request-pages","search-phase-semantic","search-phase-lexical","operation-service",
        "keyed-nominations","transport","dispatch","source-acquisition-unavailable"] do
      let path := directory.path/(stage++".json")
      if ← path.pathExists then fields := fields++[(stage,(← read path).getObjValD "data")]
    receipts := receipts.push (Json.mkObj fields)
  check (rows.size == 83 && receipts.size == 80) "stopped output/receipt domain incomplete"
  IO.FS.writeFile (output/"partial-bodies.json") (toJson bodies).pretty
  IO.FS.writeFile (output/"partial-evidence.json") (Json.mkObj [("tag",toJson tag),("guard",guard),
    ("actualOutputs",toJson rows),("primeClientReport",prime),("clientRowsUnavailable",toJson true),
    ("clientLatencyAndReceiptAssociationNotReconstructed",toJson true),("actualOutputsRetained",toJson rows.size),
    ("waves",toJson #[Json.mkObj [("name",toJson "wave-a"),("receipts",toJson receipts)]]),
    ("originalAudit",← read (root/"original-audit.json")),("frozenHeads",← read (root/"heads.json")),
    ("requiredOriginalFieldsDelivered",toJson (0 : Nat)),("adopted",toJson false)]).pretty
def verifyStopped (output : System.FilePath) : IO Unit := do
  let evidence ← read (output/"partial-evidence.json")
  let bodies ← IO.ofExcept (← read (output/"partial-bodies.json")).getArr?
  let rows := array evidence "actualOutputs"
  let mut hits := 0
  let mut locks := 0
  let mut encoded := 0
  let mut scored := 0
  check (rows.size == 83 && evidence.getObjValD "actualOutputsRetained" == toJson rows.size) "stopped body domain changed"
  for body in bodies do
    let text ← IO.ofExcept (body.getObjValAs? String "body")
    let hash ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some text)
    check (hash.exitCode == 0 && body.getObjValD "sha256" == toJson ((hash.stdout.splitOn " ").headD "") &&
      body.getObjValD "utf8Bytes" == toJson text.utf8ByteSize) "retained stopped body changed"
  for row in rows do
    let some entry := bodies[number row "bodyRef"]? | throw (IO.userError "stopped body reference missing")
    let text ← IO.ofExcept (entry.getObjValAs? String "body")
    let index := number row "case"
    let both := text.contains s!"\"observed-head-case-{index}-7b319c\"" && text.contains s!"\"observed-tail-case-{index}-d82a04\""
    check (row.getObjValD "bothFields" == toJson both && row.getObjValD "bodyBytes" == entry.getObjValD "utf8Bytes")
      "stopped byte evidence differs"
  let receipts := (array evidence "waves").flatMap (array · "receipts")
  check (receipts.size == 80) "stopped trace domain changed"
  for receipt in receipts do
    let events ← IO.ofExcept (fromJson? ((receipt.getObjValD "request-pages").getObjValD "queryStages") :
      Except String (Array (String × Nat)))
    for (name,_) in events do
      if name == "configured:numerical-ready:hit" then hits := hits+1
      if name == "configured:numerical-start-lock:start" then locks := locks+1
      if name == "configured:provider-query-encode:end" then encoded := encoded+1
      if name == "configured:provider-score:end" then scored := scored+1
  IO.FS.writeFile (output/"partial-verification.json") (Json.mkObj [("actualOutputs",toJson rows.size),
    ("measuredReceipts",toJson receipts.size),("readyHits",toJson hits),("startupLockEntries",toJson locks),
    ("queryEncodingFinished",toJson encoded),("scoreFinished",toJson scored),
    ("measuredOriginalsDelivered",toJson (rows.filter (fun row => row.getObjValD "prime" == toJson false &&
      row.getObjValD "bothFields" == toJson true)).size),
    ("clientLatencyAndReceiptAssociationUnavailable",toJson true),("adopted",toJson false)]).pretty
def complete : IO Unit := do
  let output := workspace/"docs/candidates/numerical-ready"
  check (!(← (output/"completion.json").pathExists)) "completion already recorded"
  run (workspace/"docs/candidates/shared-leases/records.lean") #["--provider-stages","verify","236"]
  run (workspace/"docs/candidates/shared-leases/records.lean") #["--numerical-ready","verify","70"]
  verifyStopped output
  let changed ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--name-only","HEAD","--","Eggshell","Main.lean"],cwd := some workspace}
  check (changed.exitCode == 0 && changed.stdout.trimAscii.isEmpty) "product core changed"
  for (root,patch) in [(base/"interest-traffic-core",workspace/"docs/candidates/shared-leases/combined.patch"),
      (base/"provider-stages-parent-core",workspace/"docs/candidates/provider-stages/candidate.patch"),
      (base/"numerical-ready-parent-core",output/"candidate.patch"),
      (base/"numerical-ready-parent-core",output/"initial-readiness.patch")] do
    let status ← IO.Process.output {cmd := "/usr/bin/git",args := #["apply","--check","--unidiff-zero",patch.toString],cwd := some root}
    check (status.exitCode == 0) "isolated overlay does not replay"
  check (!(← (base/"interest-traffic-core/tools/research/NumericalReadyChecks.lean").pathExists)) "temporary checker copy remains"
  let originalStatus ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (originalStatus.exitCode == 0) "protected artifacts changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × String × String)))
  for (path,text,_) in heads do check ((← IO.FS.readFile (.mk path)) == text) "frozen original changed"
  for path in [workspace/"docs/candidates/provider-stages/cleanup.json",output/"cleanup.json",output/"compiled-cleanup.json"] do
    let cleanup ← read path
    check (cleanup.getObjValD "archive" == toJson false && cleanup.getObjValD "protectedOriginalsUnchanged" == toJson true)
      "cleanup contract failed"
    for removed in array cleanup "removed" do
      let path ← IO.ofExcept (removed.getObjValAs? String "path")
      check (!(← (System.FilePath.mk path).pathExists)) "ended artifact remains"
  let metrics ← read (output/"numerical-metrics.json")
  check (number metrics "scoringQueries" == 57) "scoring profile domain changed"
  let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(base/"numerical-ready-build/StudyMain").toString]}
  check (hashed.exitCode == 0) "current diagnostic executable missing"
  let runtime := (hashed.stdout.splitOn " ").headD ""
  let evidence := array (← read (output/"evidence.json")) "runs"
  for tag in ["numerical-ready-off16-1","numerical-ready-on16-1"] do
    let some trial := evidence.find? (fun trial => trial.getObjValD "tag" == toJson tag) | throw (IO.userError "control missing")
    check (trial.getObjValD "runtimeSha256" == toJson runtime) "current runtime differs from actual control"
  let mut guards := #[]
  for entry in ← base.readDir do
    let name := entry.fileName
    if !name.endsWith ".guard.json" || name.contains "-complete" ||
        !(name.startsWith "provider-stages-" || name.startsWith "numerical-ready-") then continue
    let guard ← read entry.path
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "study guard still owns a process"
    let pid ← IO.ofExcept (guard.getObjValAs? Nat "guardPid")
    let live ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
    let tag := name.dropEnd 11 |>.toString
    check (!live.stdout.contains (base/(tag++".guard-settings.json")).toString) "study guard still live"
    guards := guards.push (Json.mkObj [("tag",toJson tag),("guard",guard)])
  IO.FS.writeFile (output/"completion.json") (Json.mkObj [("guards",toJson guards),("actualOutputsVerified",toJson (389 : Nat)),
    ("stoppedWaveClientTimingsNotReconstructed",toJson true),("originalHeadsUnchanged",toJson true),
    ("productCoreUnchanged",toJson true),("isolatedSourceRestored",toJson true),
    ("currentDiagnosticRuntimeSha256",toJson runtime),("adopted",toJson false),("goalAchieved",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18")]).pretty
def main (args : List String) : IO Unit := do
  let numerical := args.head? == some "--numerical-ready"
  let args := if numerical then args.drop 1 else args
  let study := if numerical then "numerical-ready" else "provider-stages"
  let selector := "--"++study
  let output := workspace/"docs/candidates"/study
  let expected := if numerical then "70" else "236"
  if args == ["complete"] then
    check numerical "completion requires numerical study"
    return ← complete
  if args == ["analyze"] then return ← analyze output
  if args == ["verify"] then
    run (workspace/"docs/candidates/shared-leases/records.lean") #[selector,"verify",expected]
    if numerical then verifyStopped output
    return
  check (args == ["collect"]) "provider records mode required"
  let tags := #[selector,study++"-build1"] ++ (if numerical then #[study++"-build2",study++"-build3",
    study++"-laws-build1",study++"-laws-build2",study++"-laws1"] else #[]) ++
    #[study++"-off16-1",study++"-on16-1",study++"-on80-1"] ++ (if numerical then #[] else #[study++"-off80-1"])
  if numerical then stopped output
  run (workspace/"docs/candidates/shared-leases/records.lean") tags
  run (workspace/"docs/candidates/shared-leases/records.lean") #[selector,"verify",expected]
  analyze output
  if numerical then
    verifyStopped output
    IO.FS.writeFile (output/"laws.json") (← IO.FS.readFile (base/"numerical-ready-laws1-result/report.json"))
    let parent := array (← read (destination/"evidence.json")) "runs"
    let candidate := array (← read (output/"evidence.json")) "runs"
    let parentBodies ← IO.ofExcept (← read (destination/"bodies.json")).getArr?
    let candidateBodies ← IO.ofExcept (← read (output/"bodies.json")).getArr?
    let rows := fun run => (array run "rowsIncludingPrime").filter (fun row =>
      !((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-prime-") |>.qsort
        (fun left right => number left "case" < number right "case")
    let some baseline := parent.find? (fun run => run.getObjValD "tag" == toJson "provider-stages-off16-1") |
      throw (IO.userError "parent control not retained")
    let mut pairs := #[]
    for tag in ["numerical-ready-off16-1","numerical-ready-on16-1"] do
      let some trial := candidate.find? (fun run => run.getObjValD "tag" == toJson tag) |
        throw (IO.userError "candidate observer control missing")
      check ((rows baseline).size == 32 && (rows trial).size == 32) "comparison omitted a case"
      for (before,after) in (rows baseline).zip (rows trial) do
        check (before.getObjValD "case" == after.getObjValD "case") "comparison changed case order"
        let some old := parentBodies[number before "bodyRef"]? | throw (IO.userError "missing parent body")
        let some new := candidateBodies[number after "bodyRef"]? | throw (IO.userError "missing candidate body")
        pairs := pairs.push (Json.mkObj [("candidate",toJson tag),("case",before.getObjValD "case"),
          ("actualBodyByteIdentical",toJson (old.getObjValD "body" == new.getObjValD "body")),
          ("wholeStdoutDigestIdentical",toJson (before.getObjValD "stdoutSha256" == after.getObjValD "stdoutSha256")),
          ("parentMs",before.getObjValD "elapsedMs"),("candidateMs",after.getObjValD "elapsedMs")])
    IO.FS.writeFile (output/"control-pairs.json") (Json.mkObj [("pairs",toJson pairs),
      ("notAnAnsweringModelOrTokenComparison",toJson true),("adopted",toJson false)]).pretty
  run (workspace/"tools/research/CaptureConcurrentPatches.lean") #[study]
