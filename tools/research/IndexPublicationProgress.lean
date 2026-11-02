import Eggshell.Warm

open Lean Eggshell DB Persistence.Store

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def outcome (i : Nat) : Value := .apply .outcome (.semantic
  (.text s!"inspect device progresssignal{i}") (.semantic
    (.text s!"The original device observation has progresssignal{i}; retain this evidence.") .nil))

private def publish (source : PageMap.Snapshot) (i : Nat) : IO PageMap.Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let owner ← intern.root (outcome i)
    writeChange writer {added := [owner],removed := [],unionsChanged := false}
  PageMap.pin source.directory

private def writeJson (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path value.pretty

private def send (input : IO.Ref (Option IO.FS.Handle)) (value : Json) : IO Unit := do
  let some handle ← input.get | throw (IO.userError "worker input is closed")
  handle.putStrLn value.compress
  handle.flush

private def checkpoint (target : Plugin.IndexTarget) (source : PageMap.Snapshot) : IO Warm.Checkpoint := do
  Plugin.readBoundedJson (← Warm.checkpointPath target source) 65536

private def exactLexical (source : PageMap.Snapshot) : IO Unit := do
  let some index ← RetrievalResearch.Index.open? source |
    throw (IO.userError "latest lexical publication missing")
  let documents ← searchDocuments source
  let reader ← NodeReader.new source
  let terms ← documents.mapM fun document => do
    return (document.owner,RetrievalResearch.tokens
      (searchText (← reader.outcome (← reader.locateOutcome document.owner))))
  for token in hashDistinct (terms.flatMap Prod.snd) do
    let expected := (terms.filter (fun row => row.2.contains token)).map Prod.fst
    let (actual,count) ← index.posting token
    check (count == expected.length && actual.mergeSort (· ≤ ·) == expected.mergeSort (· ≤ ·))
      "worker catch-up differs from independent full-source tokenization"

/-- A real worker protocol process overlaps durable original publications.
No answering model, mocked encoder or direct insertion of derived roots. -/
def main (args : List String) : IO Unit := do
  let [root,runtime] := args | throw (IO.userError "IndexPublicationProgress ROOT RUNTIME")
  let root : System.FilePath := .mk root
  IO.FS.createDirAll root
  let database := root / "work.egg"
  let base ← PageMap.create database "index-publication-progress-fixture"
  let mut source := base
  for i in [:16] do source ← publish source i
  let initial := source
  let target : Plugin.IndexTarget := {
    owner := Sidecar.Owner.ofSnapshot source
    command := [runtime,"search-provider"]
    storage := .database }
  let initialWarm ← Warm.runTarget source target
  check (initialWarm.after.missing == 0 && initialWarm.after.invalid == 0 &&
    !(← Warm.required target source)) "initial snapshot failed ordinary preparation"
  let some old ← RetrievalResearch.Index.open? initial |
    throw (IO.userError "initial completed lexical reader absent")
  let retainedBefore ← old.posting "w:device"
  let (input,child) ← do
    let (pipe,child) ← (← IO.Process.spawn {
      cmd := runtime
      args := #["codex-worker","index"]
      stdin := .piped
      stdout := .piped
      stderr := .piped }).takeStdin
    pure (← IO.mkRef (some pipe),child)
  let errors ← IO.asTask child.stderr.readToEnd .dedicated
  let mut exchanges := #[]
  try
    for round in [:3] do
      source ← publish source (16+round*100)
      let before := source.head
      let started ← IO.monoMsNow
      send input (Json.mkObj [("target",toJson target),("paths",toJson ([] : List String)),
        ("warm",toJson true)])
      let finished ← IO.mkRef false
      let response ← IO.asTask (do
        try child.stdout.getLine finally finished.set true) .dedicated
      let mut publications := #[]
      for i in [:24] do
        if ← finished.get then break
        source ← publish source (17+round*100+i)
        publications := publications.push (toJson source.head)
        IO.sleep 25
      let raw ← IO.ofExcept response.get
      let reply ← IO.ofExcept (Json.parse raw)
      check ((fromJson? reply : Except String Nat).toOption == some 0)
        s!"ordinary index worker failed across publication: {raw}"
      let completed ← checkpoint target source
      check (!publications.isEmpty && completed.source.revision < source.head.revision &&
        before.revision ≤ completed.source.revision)
        "no newer publication actually overlapped worker preparation"
      let some history ← PageMap.HistoryReader.make? source completed.source |
        throw (IO.userError "worker completed source is no longer readable")
      check ((← RetrievalResearch.Index.ready history.snapshot) &&
        (← WindowOwners.openShared? history.snapshot).isSome)
        "worker acknowledged an incomplete pinned source"
      check (← Warm.required target source) "old completion falsely marked newer publications ready"
      check ((← old.posting "w:device") == retainedBefore)
        "background updates invalidated an active completed reader"
      let exchange := Json.mkObj [("round",toJson round),("before",toJson before),
        ("publications",toJson publications),("completed",toJson completed.source),
        ("latest",toJson source.head),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
        ("reply",reply),("newerDebtRetained",toJson true),("oldReaderUnchanged",toJson true)]
      exchanges := exchanges.push exchange
      writeJson (root / "progress.json") (toJson exchanges)
    send input (Json.mkObj [("target",toJson target),("paths",toJson ([] : List String)),
      ("warm",toJson true)])
    let reply ← child.stdout.getLine
    check ((Json.parse reply >>= fromJson? (α := Nat)).toOption == some 0)
      s!"final ordinary worker catch-up failed: {reply}"
    check (!(← Warm.required target source)) "ordinary worker did not catch up to newest source"
    exactLexical source
    let settings ← Warm.options source target.command target.storage
    let inspected ← Warm.inspect source settings
    check (inspected.coverage.missing == 0 && inspected.coverage.invalid == 0 && inspected.needed.isEmpty)
      "final original/focus windows are not numerically prepared"
    let some windows ← WindowOwners.openShared? source | throw (IO.userError "final window-owner reader absent")
    let mut expected := []
    for document in ← searchDocuments source do
      expected := expected ++ WindowOwners.entries document (← getNat source.get (key "member" document.owner))
    let found ← WindowOwners.lookup windows (hashDistinct (expected.map Prod.fst)) 8192
    check (found.val.partialKeys.isEmpty && found.val.occurrences.length == expected.length &&
      found.val.occurrences.all expected.contains) "final window owners differ from full original census"
    input.set none
    let exit ← child.wait
    let stderr ← IO.ofExcept errors.get
    IO.FS.writeFile (root / "worker.stderr.txt") stderr
    check (exit == 0 && (stderr.splitOn "source changed").length == 1 &&
      (stderr.splitOn "matrix changed").length == 1)
      "worker exited badly or retained an invalidation error"
    writeJson (root / "result.json") (Json.mkObj [("actualWorkerProtocol",toJson true),
      ("rounds",toJson exchanges),("initialWarm",toJson initialWarm),
      ("finalSource",toJson source.head),("finalCoverage",toJson inspected.coverage),
      ("exactLexicalPostings",toJson true),("exactWindowOwners",toJson true),
      ("latestReady",toJson true),("workerExit",toJson exit.toNat),
      ("answeringModelCalls",toJson (0 : Nat)),("loadBenchmark",toJson false),
      ("publicationDriver",toJson "direct durable PageMap original writes; not service/client load")])
  catch error =>
    input.set none
    try child.kill catch _ => pure ()
    let _ ← child.wait
    throw error
