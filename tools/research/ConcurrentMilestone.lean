import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def destination := workspace/"docs/candidates/readonly-pages"
def lean := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
def studies := ["numerical-protocol","numerical-capacity","owned-receive","readonly-pages"]
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def run (cmd : String) (args : Array String) (cwd : System.FilePath := workspace) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some cwd}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def script (file : String) (args : Array String) : IO Unit := do
  discard <| run lean (#["-j1","-M1536","--run",(workspace/file).toString]++args)
def hash (path : System.FilePath) : IO String := do
  return ((← run "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def protectedInputs : IO Unit := do
  discard <| run "/usr/bin/shasum" #["-a","256","-c",(workspace/"docs/candidates/project-cache/protected-after.sha256").toString] base
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) : Except String (Array (String × String × String)))
  for (path,bytes,sha) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == sha) "original head changed"
def guards : IO (Array (String × Json)) := do
  let mut rows := #[]
  for entry in ← base.readDir do
    unless entry.fileName.endsWith ".guard.json" && studies.any (fun study => entry.fileName.startsWith (study++"-")) &&
      !entry.fileName.contains "-milestone" do continue
    let guard ← read entry.path
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "study still owns live work"
    let pid ← IO.ofExcept (guard.getObjValAs? Nat "guardPid")
    let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
    check (!process.stdout.contains (base/(entry.fileName.dropEnd 11 |>.toString)).toString) "study guard remains live"
    rows := rows.push (entry.fileName.dropEnd 11 |>.toString,guard)
  return rows.qsort (fun a b => a.1 < b.1)
def record : IO Unit := do
  let completed ← guards
  protectedInputs
  script "docs/candidates/numerical-protocol/records.lean" #[]
  for study in ["owned-receive","readonly-pages"] do
    let target := workspace/"docs/candidates"/study
    let prior ← if ← (target/"evidence.json").pathExists then read (target/"evidence.json") else pure Json.null
    let tags := completed.filterMap fun (tag,_) =>
      if tag.startsWith (study++"-") && !(arr prior "runs").any (fun run => run.getObjValD "tag" == toJson tag)
      then some tag else none
    if !tags.isEmpty then script "docs/candidates/shared-leases/records.lean" (#["--"++study]++tags)
    let evidence ← read (target/"evidence.json")
    let count := (arr evidence "runs").foldl (fun total row => total+(arr row "rowsIncludingPrime").size) 0
    check (count ≥ 35) "ordinary hook output evidence missing"
    script "docs/candidates/shared-leases/records.lean" #["--"++study,"verify",toString count]
  let trialRows (study tag : String) : IO (Array Json) := do
    let some trial := (arr (← read (workspace/"docs/candidates"/study/"evidence.json")) "runs").find? (fun row => row.getObjValD "tag" == toJson tag) |
      throw (IO.userError "ordinary hook control missing")
    return (arr trial "rowsIncludingPrime").filter (fun row => ((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-wave-")
  let mut comparisons := #[]
  for (leftStudy,leftTag,rightStudy,rightTag) in [
      ("numerical-waits","numerical-waits-on16-1","owned-receive","owned-receive-hook16-1"),
      ("owned-receive","owned-receive-hook16-1","readonly-pages","readonly-pages-hook16-1")] do
    let left ← trialRows leftStudy leftTag
    let right ← trialRows rightStudy rightTag
    check (left.size == 32 && right.size == 32) "ordinary hook control domain differs"
    for row in left do
      check (right.any fun next => next.getObjValD "session" == row.getObjValD "session" &&
        next.getObjValD "stdoutSha256" == row.getObjValD "stdoutSha256") "actual hook bytes changed"
    comparisons := comparisons.push (toJson (leftTag,rightTag,left.size))
  let some hookControl := (arr (← read (destination/"evidence.json")) "runs").find? (fun row => row.getObjValD "tag" == toJson "readonly-pages-hook16-1") |
    throw (IO.userError "readonly ordinary control missing")
  let observedPages := ((arr hookControl "waves").filter (fun wave => wave.getObjValD "name" != toJson "prime")).flatMap (arr · "receipts")
  check (observedPages.size == 32 && observedPages.all (fun receipt =>
    let pages := receipt.getObjValD "request-pages"
    pages.getObjValD "readOnly" == toJson true && pages.getObjValD "sharedCacheTouched" == toJson false))
    "ordinary hook retained shared page-cache access"
  let mut helperFailures := #[]
  for entry in ← base.readDir do
    unless entry.fileName.startsWith "readonly-pages-milestone-" && entry.fileName.endsWith ".guard.json" do continue
    let guard ← read entry.path
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" != toJson (0 : Nat) do continue
    let log := base/((entry.fileName.dropEnd 11 |>.toString)++".log")
    helperFailures := helperFailures.push (Json.mkObj [("guard",guard),("failure",toJson (← IO.FS.readFile log))])
  IO.FS.writeFile (destination/"controls.json") (Json.mkObj [("ordinaryHookBytesEqual",toJson comparisons),
    ("ordinaryHookReaderModeChecked",toJson observedPages.size),("helperFailures",toJson helperFailures),
    ("nativePageChecks",← read (base/"readonly-pages-checks1-result/report.json")),
    ("guards",toJson completed),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let stopped := base/"readonly-pages-hook80-1-result"
  if !(← (stopped/"report.json").pathExists) then
    let prime ← read (stopped/"prime-checkpoint.json")
    let primeIds := (arr prime "receipts").map (·.getObjValD "receipt")
    let mut observed := #[]
    for entry in ← (stopped/"private/receipts").readDir do
      if primeIds.contains (toJson entry.fileName) then continue
      let mut fields := [("receipt",toJson entry.fileName)]
      for stage in ["operation-service","request-pages","search-phase-semantic","search-phase-lexical",
          "canonical-source-input","source-acquisition-unavailable","transport","ack"] do
        let file := entry.path/(stage++".json")
        if ← file.pathExists then fields := fields++[(stage,(← read file).getObjValD "data")]
      if fields.length > 1 then observed := observed.push (Json.mkObj fields)
    IO.FS.writeFile (destination/"stopped-capacity.json") (Json.mkObj [("requestedQueries",toJson (80 : Nat)),
      ("guard",← read (base/"readonly-pages-hook80-1.guard.json")),("observedReceipts",toJson observed),
      ("clientLatencyAndReceiptAssociationUnavailable",toJson true),("adopted",toJson false)]).compress
  if !(← (destination/"candidate.patch").pathExists) then script "tools/research/CaptureConcurrentPatches.lean" #["readonly-pages"]
  protectedInputs
partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,metadata.byteSize.toNat)
  let mut count := 0
  let mut bytes := 0
  for entry in ← path.readDir do
    let (n,b) ← remove entry.path
    count := count+n
    bytes := bytes+b
  IO.FS.removeDir path
  return (count,bytes)
def cleanup : IO Unit := do
  check (!(← (destination/"cleanup.json").pathExists)) "cleanup already recorded"
  let completed ← guards
  protectedInputs
  for study in ["owned-receive","readonly-pages"] do
    check ((← read (workspace/"docs/candidates"/study/"verification.json")).getObjValD "actualOutputs" != Json.null) "actual output verification missing"
  let process ← run "/bin/ps" #["-axo","command="]
  let mut paths := #[]
  for (tag,_) in completed do
    for path in [base/(tag++"-result"),base/(tag++".log")] do
      if ← path.pathExists then paths := paths.push path
  for name in ["numerical-protocol-build","numerical-capacity-build","owned-receive-build",
      "owned-receive-checks-build","owned-receive-hook-build","readonly-pages-build"] do
    for entry in ← (base/name).readDir do
      if entry.fileName.endsWith ".c" || entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" ||
        (entry.fileName == "StudyMain" && !["owned-receive-hook-build","readonly-pages-build"].contains name) then paths := paths.push entry.path
  let mut removed := #[]
  let mut files := 0
  let mut bytes := 0
  for path in paths do
    check (!process.contains path.toString) "retired path still active"
    let (n,b) ← remove path
    files := files+n
    bytes := bytes+b
    removed := removed.push (path.toString,n,b)
  protectedInputs
  IO.FS.writeFile (destination/"cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("files",toJson files),("logicalBytes",toJson bytes),("archive",toJson false),
    ("originalsAndNativeLinkInputsRetained",toJson true)]).compress
def restore : IO Unit := do
  discard <| guards
  protectedInputs
  let core := base/"interest-traffic-core"
  for study in ["readonly-pages","owned-receive","numerical-capacity","numerical-waits","numerical-stages",
      "numerical-ready","provider-stages","query-stages","shared-leases"] do
    let patch := workspace/"docs/candidates"/study/(if study == "shared-leases" then "combined.patch" else "candidate.patch")
    discard <| run "/usr/bin/git" #["apply","--reverse","--unidiff-zero","--check",patch.toString] core
    discard <| run "/usr/bin/git" #["apply","--reverse","--unidiff-zero",patch.toString] core
  for file in ["NumericalProtocolProbe.lean","NumericalReadyChecks.lean","ReadonlyPageChecks.lean"] do
    let path := core/"tools/research"/file
    check ((← IO.FS.readFile path) == (← IO.FS.readFile (workspace/"tools/research"/file))) "native helper changed"
    IO.FS.removeFile path
  protectedInputs
  IO.FS.writeFile (destination/"restoration.json") (Json.mkObj [("allOverlaysReversed",toJson true),
    ("originalsUnchanged",toJson true),("adopted",toJson false)]).pretty
def complete : IO Unit := do
  let completed ← guards
  protectedInputs
  -- Keep machine records as plain JSON,without thousands of whitespace-only
  -- diff lines. This changes neither retained body strings nor parsed values.
  for study in studies do
    for name in ["evidence.json","protocol-evidence.json","bodies.json","controls.json","cleanup.json"] do
      let path := workspace/"docs/candidates"/study/name
      if ← path.pathExists then
        let value ← read path
        check ((← IO.ofExcept (Json.parse value.compress)) == value) "record formatting changed parsed evidence"
        IO.FS.writeFile path value.compress
  script "docs/candidates/shared-leases/records.lean" #["--owned-receive","verify","35"]
  script "docs/candidates/shared-leases/records.lean" #["--readonly-pages","verify","38"]
  let sealedRuntime ← read (destination/"seal.json")
  check (toJson (← hash (base/"readonly-pages-build/StudyMain")) == sealedRuntime.getObjValD "runtimeSha256" &&
    toJson (← hash (base/"owned-receive-hook-build/StudyMain")) == sealedRuntime.getObjValD "parentRuntimeSha256") "retained hook runtime changed"
  check ((← hash (base/"numerical-stages-client-build/StudyMain")) == "a80cad2a80fb084842d22e3ead44358762fbdea3e175601b1d407d82c67b308e") "sealed client changed"
  discard <| run "/usr/bin/git" #["diff","--quiet","--","Eggshell","Main.lean"]
  check ((← read (destination/"cleanup.json")).getObjValD "archive" == toJson false &&
    (← read (destination/"restoration.json")).getObjValD "allOverlaysReversed" == toJson true) "cleanup/restoration incomplete"
  IO.FS.writeFile (destination/"completion.json") (Json.mkObj [("runtimeGuardsDrained",toJson completed.size),
    ("actualBodiesVerifiedAfterDeletion",toJson (73 : Nat)),("retainedHookRuntimesAndClientSealed",toJson true),
    ("productCoreUnchanged",toJson true),("protectedOriginalsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18"),("adopted",toJson false)]).pretty
def main (args : List String) : IO Unit := do
  match args with
  | ["record"] => record
  | ["cleanup"] => cleanup
  | ["restore"] => restore
  | ["complete"] => complete
  | _ => throw (IO.userError "explicit record,cleanup,restore or complete required")
