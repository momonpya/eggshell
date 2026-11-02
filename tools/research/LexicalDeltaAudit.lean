import tools.RetrievalIndex
import Lean

open Lean Eggshell DB Persistence.Store

run_meta do
  let environment ← getEnv
  let mut pending := [``RetrievalResearch.Index.deltaPlan]
  let mut seen : Std.HashSet Name := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    if let some info := environment.find? name then
      if let some body := info.value? then
        for used in body.getUsedConstants do
          if used.toString.startsWith "Eggshell." then pending := used :: pending
  for forbidden in [``searchDocuments,``directory,``PageMap.Snapshot.foldRange] do
    if seen.contains forbidden then throwError "lexical delta reaches a full catalogue scan: {forbidden}"
  unless seen.contains ``SourceDelta.read? && seen.contains ``SourceDelta.documents do
    throwError "lexical delta bypasses checked original publication/membership reads"
  logInfo "Lexical delta uses verified source changes and point reads, without catalogue range scans"

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def outcome (i : Nat) : Value := .apply .outcome (.semantic
  (.text s!"inspect kernelsignal{i}") (.semantic (.text s!"shared evidence 커널 café kernelsignal{i}") .nil))

private def publish (source : Snapshot) (values : List Value) (removed : List Nat := [])
    (affected : List Nat := []) : IO Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    for id in removed do removeRoot writer id
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let added ← values.mapM intern.root
    writeChange writer {added,removed,affected,unionsChanged := false}
  PageMap.pin source.directory

private def terms (source : Snapshot) : IO (List (Nat × List String)) := do
  let reader ← NodeReader.new source
  (← searchDocuments source).mapM fun document => do
    return (document.owner,RetrievalResearch.tokens (searchText (← reader.outcome (← reader.locateOutcome document.owner))))

private def exact (source : Snapshot) : IO Unit := do
  let some reader ← RetrievalResearch.Index.open? source | throw (IO.userError "prepared lexical reader missing")
  let original ← terms source
  let units := hashDistinct ((original.flatMap Prod.snd) ++ RetrievalResearch.tokens "kernelsignal0 kernelsignal999 absent")
  for unit in units do
    let expected := (original.filter (fun row => row.2.contains unit)).map Prod.fst
    let (actual,count) ← reader.posting unit
    check (actual.mergeSort (· ≤ ·) == expected.mergeSort (· ≤ ·) && count == expected.length)
      s!"lexical delta differs from full original oracle: {unit}"

private def delta (source : Snapshot) : IO Json := do
  source.trace.set (some {})
  let started ← IO.monoMsNow
  let result ← RetrievalResearch.Index.warm source .user
  let elapsed := (← IO.monoMsNow)-started
  let trace ← source.trace.get
  check (result.mode == "publication-delta" && result.catalogueOwners == 0 &&
    trace.any (fun row => row.complete && row.operations.all (fun item => match item with
      | .range .. => false | _ => true))) "delta update scanned the original catalogue"
  source.trace.set none
  exact source
  return (toJson result).setObjVal! "elapsedMs" (toJson elapsed)

private def scenario (root : System.FilePath) : IO Json := do
  let base ← PageMap.create (root / "source.egg") "lexical-delta-fixture"
  let first ← publish base (List.range 40 |>.map outcome)
  let initial ← RetrievalResearch.Index.warm first .user
  check (initial.mode == "full-reconcile" && initial.added == 40 && initial.hydrated == 40)
    "bootstrap did not index every original"
  exact first
  let some old ← RetrievalResearch.Index.open? first | throw (IO.userError "old reader absent")
  let added ← publish first [outcome 40]
  let addedResult ← delta added
  let oldOwner := (← rootIds first).head!
  let removed ← publish added [] [oldOwner]
  let removedResult ← delta removed
  let restored ← publish removed [outcome 0]
  let restoredResult ← delta restored
  check (restoredResult.getObjValD "hydrated" == toJson (0 : Nat)) "reinsert re-tokenized an immutable original"
  let sameOwner := (← rootIds restored).head!
  let changed ← publish restored [] [] [sameOwner]
  let affectedResult ← delta changed
  let empty ← publish changed [] (← rootIds changed)
  let emptyResult ← delta empty
  let revived ← publish empty [outcome 90]
  let revivedResult ← delta revived
  let later ← publish revived [outcome 91]
  let some pendingOwner ← findNode? later (outcome 91) | throw (IO.userError "pending original missing")
  let [pending] ← SourceDelta.documents later [pendingOwner] | throw (IO.userError "pending original is not live")
  let (_,_,_) ← PageMap.withWriter (← PageMap.pin (← RetrievalResearch.Index.path later .user)) fun writer =>
    do
    writer.put "ready" none
    writer.put "preparing" (some (toJson later.head).compress.toUTF8)
    let _ ← RetrievalResearch.Index.add writer later pending (← getNat later.get (key "member" pendingOwner))
    putNat writer "documents" 2
  let recovery ← RetrievalResearch.Index.warm later .user
  check (recovery.mode == "full-reconcile" && recovery.hydrated == 0 && recovery.added == 0)
    "incomplete workspace lost its committed prefix or was treated as a complete delta basis"
  exact later
  let latest ← publish later [outcome 92]
  let mutating ← RetrievalResearch.Index.warm revived .user
  check (mutating.mode == "warm") "retained old view was not reusable"
  let latestResult ← delta latest
  let workspace ← PageMap.pin (← RetrievalResearch.Index.path latest .user)
  IO.FS.removeDirAll (PreparedRoot.path workspace)
  let recoveredView ← delta latest
  check (recoveredView.getObjValD "hydrated" == toJson (0 : Nat) &&
    recoveredView.getObjValD "batches" == toJson (0 : Nat)) "completion registration re-enumerated data"
  let unit := (RetrievalResearch.tokens "kernelsignal0").head!
  check ((← old.posting unit).2 == 1) "old active reader changed after retraction/reinsertion"
  let bad ← PageMap.pin (← RetrievalResearch.Index.path latest .user)
  let _ ← PageMap.withWriter bad fun writer => putNat writer "documents" 9999
  let final ← publish latest [outcome 93]
  let refused ← try let _ ← RetrievalResearch.Index.warm final .user; pure false catch _ => pure true
  check refused "inconsistent complete workspace population was trusted"
  let gapBase ← PageMap.create (root / "gap.egg") "gap-fixture"
  let gapFirst ← publish gapBase [outcome 800]
  let _ ← RetrievalResearch.Index.warm gapFirst .user
  let _ ← PageMap.withWriter gapFirst fun writer => writer.put "memo:missing-feed" (some "derived".toUTF8)
  let gap ← PageMap.pin gapFirst.directory
  let gapResult ← RetrievalResearch.Index.warm gap .user
  check (gapResult.mode == "full-reconcile") "missing ancestry was treated as an empty delta"
  exact gap
  let forkBase ← PageMap.create (root / "fork-a.egg") "fork-fixture"
  let common ← publish forkBase [outcome 700]
  let _ ← RetrievalResearch.Index.warm common .user
  let copy ← IO.Process.output {cmd := "/bin/cp",args := #["-c","-R",common.directory.toString,(root / "fork-b.egg").toString]}
  check (copy.exitCode == 0) "cannot make independent source-only copy"
  let branchA ← publish common [outcome 701]
  let _ ← delta branchA
  let branchB ← publish (← PageMap.pin (root / "fork-b.egg")) [outcome 702]
  let branchResult ← RetrievalResearch.Index.warm branchB .user
  check (branchResult.mode == "full-reconcile" && branchResult.reset && branchResult.hydrated == 2)
    "divergent copy reused owner-number token aliases"
  exact branchB
  exact branchA
  return Json.mkObj [("bootstrap",toJson initial),("addition",addedResult),("removal",removedResult),
    ("reinsertion",restoredResult),("affected",affectedResult),("empty",emptyResult),
    ("revival",revivedResult),("incompleteRecovery",toJson recovery),("later",latestResult),
    ("completionRegistrationRecovery",recoveredView),("missingAncestry",toJson gapResult),
    ("divergentCopy",toJson branchResult),("divergentCopyOriginalsMatched",toJson true),
    ("oldReaderRetained",toJson true),("inconsistentPopulationRejected",toJson true),
    ("fullOracleMatched",toJson true),("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]

private def json (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal comparison executable"
  return (result.stdout.splitOn " ").headD ""

private def probe (binary privateRoot source output : System.FilePath) (query : Option String := none) : IO Json := do
  let args := match query with
    | none => #[source.toString,output.toString]
    | some unit => #["query",source.toString,unit,output.toString]
  let process ← IO.Process.output {
    cmd := binary.toString
    args
    env := #[("EGGSHELL_DATA_ROOT",some privateRoot.toString),("LEAN_NUM_THREADS",some "1")] }
  unless process.exitCode == 0 do
    IO.FS.writeFile (output.withExtension "failure.json") (Json.mkObj [
      ("exitCode",toJson process.exitCode.toNat),("stdout",toJson process.stdout),("stderr",toJson process.stderr)]).pretty
    throw (IO.userError "comparison probe failed; retain its failure receipt")
  json output

private def benchmark (control candidate root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve comparison"
  FileSystem.privateDirectory root
  let sizes := [64,1024,10000]
  let repetitions := 3
  IO.FS.writeFile (root / "plan.json") (Json.mkObj [
    ("sizes",toJson sizes),("repetitions",toJson repetitions),
    ("control",toJson control.toString),("controlSha256",toJson (← digest control)),
    ("candidate",toJson candidate.toString),("candidateSha256",toJson (← digest candidate)),
    ("order",toJson "alternate control/candidate on consecutive source additions"),
    ("sharedSnapshot",toJson true),("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let mut observations : Array Json := #[]
  for count in sizes do
    let directory := root / s!"size-{count}"
    FileSystem.privateDirectory directory
    let mut source ← PageMap.create (directory / "source.egg") s!"lexical-scale-{count}"
    for batch in [:((count+31)/32)] do
      let first := batch*32
      source ← publish source ((List.range (min 32 (count-first))).map (fun index => outcome (first+index)))
      if batch % 32 == 31 then IO.println (Json.mkObj [("building",toJson count),("owners",toJson (first+32))]).compress
    let controlRoot := directory / "control-private"
    let candidateRoot := directory / "candidate-private"
    let first ← probe control controlRoot source.directory (directory / "control-bootstrap.json")
    let second ← probe candidate candidateRoot source.directory (directory / "candidate-bootstrap.json")
    check (first.getObjValD "source" == second.getObjValD "source") "bootstrap sources differ"
    for repetition in [:repetitions] do
      let id := count+repetition
      source ← publish source [outcome id]
      let a := directory / s!"control-{repetition}.json"
      let b := directory / s!"candidate-{repetition}.json"
      let (before,after) ← if repetition % 2 == 0 then do
          let before ← probe control controlRoot source.directory a
          let after ← probe candidate candidateRoot source.directory b
          pure (before,after)
        else do
          let after ← probe candidate candidateRoot source.directory b
          let before ← probe control controlRoot source.directory a
          pure (before,after)
      check (before.getObjValD "source" == toJson source.head && after.getObjValD "source" == toJson source.head)
        "comparison used different source snapshots"
      check ((after.getObjValD "result").getObjValD "mode" == toJson "publication-delta" &&
        (after.getObjValD "result").getObjValD "catalogueOwners" == toJson (0 : Nat) &&
        after.getObjValD "sourceTraceComplete" == toJson true &&
        after.getObjValD "sourceRangeReads" == toJson (some (0 : Nat))) "candidate used full enumeration"
      let all := (← rootIds source).mergeSort (· ≤ ·)
      let some newOwner ← findNode? source (outcome id) | throw (IO.userError "new source owner absent")
      for (word,expected) in [("shared",all),(s!"kernelsignal{id}",[newOwner]),("absentkeyword",[])] do
        let unit := (RetrievalResearch.tokens word).head!
        let left ← probe control controlRoot source.directory (directory / s!"control-{repetition}-{word}.json") (some unit)
        let right ← probe candidate candidateRoot source.directory (directory / s!"candidate-{repetition}-{word}.json") (some unit)
        for report in [left,right] do
          let owners ← IO.ofExcept (report.getObjValAs? (List Nat) "owners")
          check (owners.mergeSort (· ≤ ·) == expected && report.getObjValD "count" == toJson expected.length)
            "comparison postings differ from the independently generated source membership"
      let observation := Json.mkObj [("initialOwners",toJson count),("repetition",toJson repetition),
        ("source",toJson source.head),("control",before),("candidate",after),
        ("postingsMatchOriginalMembership",toJson true)]
      observations := observations.push observation
      IO.FS.writeFile (root / "observations.json") (toJson observations).pretty
      IO.println (Json.mkObj [("initialOwners",toJson count),("repetition",toJson repetition),
        ("controlMs",before.getObjValD "elapsedMs"),("candidateMs",after.getObjValD "elapsedMs")]).compress
  IO.FS.writeFile (root / "complete.json") (Json.mkObj [
    ("comparisons",toJson observations.size),("postingsMatchOriginalMembership",toJson true),
    ("modelCalls",toJson (0 : Nat)),("hookBenchmark",toJson false),("adopted",toJson false)]).pretty

def main (args : List String) : IO Unit := do
  if let ["benchmark",control,candidate,root] := args then
    benchmark (.mk control) (.mk candidate) (.mk root)
    return
  let [directory] := args | throw (IO.userError "LexicalDeltaAudit NEW_ROOT")
  let root := System.FilePath.mk directory
  check (!(← root.pathExists)) "preserve previous audit"
  FileSystem.privateDirectory root
  let result ← scenario root
  IO.FS.writeFile (root / "result.json") result.pretty
  IO.println result.compress
