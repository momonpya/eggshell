module

public import Eggshell.Handoff
public import Eggshell.PluginHooks

@[expose] public section
namespace Eggshell.SourceEvidenceTests
open Lean Plugin Persistence DB

def require (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

def deadline : IO Nat := return (← IO.monoMsNow) + 5000

def testReadBatches : IO Unit := do
  require (SourceEvidence.observedCommandFiles
      "nl -ba src/product.cc | sed -n '1,20p'; rg --files src | rg 'product|other'" == ["src/product.cc"])
    "a directory inventory erased an independently recognized file read"
  require (SourceEvidence.commandFiles? "cat src/product.cc; cat src/second.cc" ==
      some ["src/product.cc", "src/second.cc"]) "compound read omitted a dependency"
  require (SourceEvidence.commandFiles?
      "nl -ba src/product.cc | sed -n '1,20p;30,40p'; rg -n -- '-x|mode' src/second.cc | head -80" ==
      some ["src/product.cc", "src/second.cc"]) "quoted separators or explicit rg pattern lost a batched source"
  require (SourceEvidence.commandFiles?
      "cat src/product.cc && nl -ba src/second.cc | tail -n 5; cat src/product.cc;" ==
      some ["src/product.cc", "src/second.cc"]) "conditional literal read or source deduplication failed"
  require (SourceEvidence.commandFiles? "cat src/product.cc\ncat src/second.cc" ==
      some ["src/product.cc", "src/second.cc"]) "newline read batch lost a dependency"
  require (SourceEvidence.commandFiles?
      "rg -n \"getToolChain\\(|a\\\";b\" src/product.cc && cat src/second.cc" ==
      some ["src/product.cc", "src/second.cc"]) "double-quoted regex or escaped quote changed source operands"

def testBatchCapture (first moved : System.FilePath) (body : String) : IO Unit := do
  IO.FS.writeFile (moved / "src/product.cc") body
  IO.FS.writeFile (moved / "src/second.cc") "independent source B"
  let input := Json.mkObj [("command", toJson
    "nl -ba src/product.cc | sed -n '1,20p;30,40p'; rg -n -- 'source|product' src/second.cc | head -80")]
  let capture ← SourceEvidence.capture first input (← deadline)
  require (capture.record.valid && capture.record.files.map (·.relative) ==
      ["src/product.cc", "src/second.cc"]) "real batched source capture omitted a source"
  require (← SourceEvidence.verify moved capture.record (← deadline))
    "relocated batched sources lost freshness"
  IO.FS.writeFile (moved / "src/second.cc") "changed second dependency"
  require (!(← SourceEvidence.verify moved capture.record (← deadline)))
    "editing the second subcommand source retained freshness"
  IO.FS.removeFile (moved / "src/second.cc")
  require (!(← SourceEvidence.verify moved capture.record (← deadline)))
    "deleting the second subcommand source retained freshness"
  IO.FS.writeFile (first / "src/second.cc") "changed during batch execution"
  require (!(← SourceEvidence.sealCapture first capture (← deadline)).complete)
    "batch source changed during the command retained freshness"
  IO.FS.writeFile (first / "src/second.cc") "independent source B"

def testNativeBatchCapture (workspace : System.FilePath) (session turn : String)
    (files : SessionFiles) (result : Json) : IO Unit := do
  IO.FS.writeFile (workspace / "src/batch-second.cc") "second native dependency"
  let input := Json.mkObj [("command", toJson
    "nl -ba src/product.cc | sed -n '1,20p;30,40p'; rg -n -- 'second' src/batch-second.cc | head -80")]
  let event := fun name => Json.mkObj [
    ("hook_event_name", toJson name), ("session_id", toJson session),
    ("turn_id", toJson turn), ("tool_name", toJson "Bash"),
    ("tool_use_id", toJson "native-batch"), ("tool_input", input), ("tool_response", result)]
  let _ ← preToolUse (event "PreToolUse")
  captureTerminal (event "PostToolUse")
  let tool : ToolEvent := {
    name := "Bash", useId := "native-batch", input := input.compress, response := result.compress }
  let some recorded ← recordedTool? files turn tool |
    throw (IO.userError "native batch result was not durable")
  let some capture := recorded.source |
    throw (IO.userError "native batch omitted its source certificate")
  require (capture.record.valid && capture.record.files.map (·.relative) ==
      ["src/product.cc", "src/batch-second.cc"])
    "actual native batch did not seal every subcommand's dependency"
  require (← SourceEvidence.verify workspace capture.record (← deadline))
    "actual native batch was not reusable"
  IO.FS.writeFile (workspace / "src/batch-second.cc") "changed native dependency"
  require (!(← SourceEvidence.verify workspace capture.record (← deadline)))
    "actual native batch ignored a changed later subcommand"

def testScopedRefresh (workspace : System.FilePath) (record : SourceEvidence.Record) : IO Unit := do
  let statusKeys := fun (handoff : Handoff) => handoff.deliveredGraphs.filter (·.startsWith "s:")
  -- Unsupported glob/search results have no named file observations. A
  -- background index update must not turn their refresh into a global warning.
  for records in [[], [SourceEvidence.unverified]] do
    let unknownRefresh ← (sourceRefresh records).checkSources {
      workspace, deadline := ← deadline}
    require (unknownRefresh.text.isEmpty && statusKeys unknownRefresh == [] &&
        !unknownRefresh.blocksCurrent && unknownRefresh.completed == 0)
      "unknown-only refresh emitted an unscoped stale-source warning or authority"
  let mixedRefresh ← (sourceRefresh [record, SourceEvidence.unverified]).checkSources {
    workspace, deadline := ← deadline}
  require (mixedRefresh.text.contains "src/product.cc: unchanged" &&
      !mixedRefresh.text.contains "HISTORICAL/UNVERIFIED" &&
      !mixedRefresh.blocksCurrent && mixedRefresh.completed == 0)
    "unknown provenance globally mislabeled separately unchanged source files"
  let unnamedRefresh ← (sourceRefresh [record, SourceEvidence.unverified]).checkSources {
    workspace, deadline := ← deadline, handoffChars := sourceStatusReserve}
  require (unnamedRefresh.text.isEmpty && statusKeys unnamedRefresh == [])
    "a small refresh budget emitted a verdict without its named source"

def testMixedReadCapture (workspace : System.FilePath) (body : String) (tool : ToolEvent) : IO Unit := do
  let mixedInput := Json.mkObj [("command", toJson
    "nl -ba src/product.cc | sed -n '1,20p'; rg -n 'product' src | head -80")]
  let mixedCapture ← SourceEvidence.capture workspace mixedInput (← deadline)
  require (mixedCapture.record.valid && !mixedCapture.record.closed &&
      mixedCapture.record.files.map (·.relative) == ["src/product.cc"] &&
      (← SourceEvidence.sealCapture workspace mixedCapture (← deadline)).valid)
    "a mixed read/search lost the sealed file state or certified the open search domain"
  let mixedWork : ToolEvent := {tool with input := mixedInput.compress}
  require ((nativeSourceInput? mixedWork).isSome &&
      !sourceApplicable {
        workspace := workspace, deadline := 0, native := true, targets := some ["src/product.cc"]} [mixedCapture.record])
    "a mixed file observation was discarded or acquired native completion authority"
  IO.FS.writeFile (workspace / "src/product.cc") (body ++ " changed")
  require (!(← SourceEvidence.sealCapture workspace mixedCapture (← deadline)).valid)
    "a changed mixed-batch file acquired a sealed observation"
  IO.FS.writeFile (workspace / "src/product.cc") body

def testIndependentObservations (workspace : System.FilePath) (body : String) : IO Unit := do
  let input := Json.mkObj [("command", toJson "cat src/product.cc")]
  let earlier ← SourceEvidence.capture workspace input (← deadline)
  IO.FS.writeFile (workspace / "src/product.cc") (body ++ " new observation")
  let current ← SourceEvidence.capture workspace input (← deadline)
  require ((← SourceEvidence.sealCapture workspace current (← deadline)).valid)
    "new independent observation did not seal"
  IO.FS.writeFile (workspace / "src/independent.cc") "independent dependency"
  let independent ← SourceEvidence.capture workspace
    (Json.mkObj [("command", toJson "cat src/independent.cc")]) (← deadline)
  let table := [SourceEvidence.unverified, earlier.record,
    {current.record with closed := false}, current.record, independent.record]
  let use : SourceUse := {owner := "immutable-result", references := [0, 1, 2, 3], completed := true}
  let ledger ← SourceEvidence.observeRecords workspace table (← deadline)
  let some checked := checkSourceUse? table use ledger |
    throw (IO.userError "older receipts revoked the same result's current observation")
  require (checked.records == [{current.record with closed := false}] &&
      (checkedOwnerSources? table [use] ledger).isSome)
    "a current observation was not independently reusable as evidence"
  let some native := checkApplicableSourceUse? table use {
      workspace, deadline := 0, native := true, targets := some ["src/product.cc"]} ledger |
    throw (IO.userError "a fresh open-domain receipt hid a later applicable receipt")
  require (native.checked.records == [current.record])
    "native completion did not choose its own closed applicable observation"
  require ((checkSourceUse? table {use with references := [0, 1]} ledger).isNone &&
      (checkSourceUse? table {use with references := [0, 999, 3]} ledger).isNone)
    "an expired receipt or an invalid owner reference acquired freshness"
  let wider := {use with references := [3, 4]}
  require ((checkApplicableSourceUse? table wider {
      workspace, deadline := 0, native := true,
      targets := some ["src/product.cc", "src/independent.cc"]} ledger).isNone)
    "separate observations were combined to invent complete operation coverage"
  IO.FS.removeFile (workspace / "src/product.cc")
  let deleted ← SourceEvidence.observeRecords workspace table (← deadline)
  require ((checkSourceUse? table use deleted).isNone)
    "an independent observation ignored deletion of its dependency"
  IO.FS.writeFile (workspace / "src/product.cc") body

def run : IO Unit := do
  let root ← PageMap.absolute ".lake/portable-source-tests"
  if ← root.pathExists then IO.FS.removeDirAll root
  let first := root / "first-product"
  let moved := root / "relocated-product"
  for workspace in [first, moved] do IO.FS.createDirAll (workspace / "src")
  let body := "product version A\n" ++ String.intercalate "" (List.replicate 512 "related dependency bytes\n")
  for workspace in [first, moved] do IO.FS.writeFile (workspace / "src/product.cc") body
  let input := Json.mkObj [("command", toJson "cat src/product.cc")]
  let capture ← SourceEvidence.capture first input (← deadline)
  require (capture.record.valid && capture.record.files.length == 1) "explicit related file was not captured"
  require (SourceEvidence.decode? (SourceEvidence.encode capture.record) == some capture.record)
    "source codec changed dependencies"
  let fileOnly := Json.mkObj [("workspace", toJson capture.record.workspace),
    ("files", toJson capture.record.files), ("uris", toJson capture.record.uris),
    ("complete", toJson capture.record.complete)]
  require ((fromJson? fileOnly : Except String SourceEvidence.Record).toOption ==
      some {capture.record with closed := false})
    "a file observation without operation coverage was discarded or granted closed-domain authority"
  require (← SourceEvidence.verify moved capture.record (← deadline)) "relocated same relative source failed"
  IO.FS.writeFile (moved / "src/unrelated.cc") "unrelated update"
  require (← SourceEvidence.verify moved capture.record (← deadline)) "unrelated file invalidated the certificate"
  IO.FS.writeFile (moved / "src/product.cc") (body ++ " version B")
  require (!(← SourceEvidence.verify moved capture.record (← deadline))) "same name, changed bytes was authorized"
  IO.FS.removeFile (moved / "src/product.cc")
  require (!(← SourceEvidence.verify moved capture.record (← deadline))) "deleted source was authorized"
  let absent ← SourceEvidence.capture moved input (← deadline)
  require (absent.record.valid && absent.record.files.all (·.content.isNone)) "absence was not observed"
  IO.FS.writeFile (moved / "src/product.cc") body
  require (!(← SourceEvidence.verify moved absent.record (← deadline))) "new source reused an absence conclusion"
  let some related := SourceEvidence.Relative.check? "src/product.cc" |
    throw (IO.userError "source locator fixture failed")
  let some earlierProbe ← SourceEvidence.probe first related (← deadline) |
    throw (IO.userError "source probe fixture failed")
  IO.FS.writeFile (first / "src/product.cc") (body ++ "changed after hashing")
  require ((← SourceEvidence.checkedProbeFile first (some earlierProbe) (← deadline)).isNone)
    "source changed after hashing retained freshness authority"
  IO.FS.writeFile (first / "src/product.cc") body
  IO.FS.writeFile (first / "src/product.cc") (body ++ "during tool execution")
  require (!(← SourceEvidence.sealCapture first capture (← deadline)).complete) "changed during tool was authorized"
  IO.FS.writeFile (first / "src/product.cc") body
  require ((SourceEvidence.relative? first first "../other/src/product.cc").isNone) "source escaped its workspace"
  testReadBatches
  require (SourceEvidence.commandFiles? "nl -ba src/product.cc | sed -n '1,20p;30,40p'" ==
      some ["src/product.cc"]) "literal line-number/read pipeline lost its actual source"
  require (SourceEvidence.commandFiles? "rg -n 'a|b' src/product.cc | head -80" ==
      some ["src/product.cc"]) "quoted regex pipe or bounded stream filter changed dependencies"
  for command in ["nl -ba src/product.cc | sed -n '1p;r /tmp/foreign'",
      "cat src/product.cc | sed -n '1p' src/unrelated.cc",
      "cat src/product.cc | head -80 src/unrelated.cc",
      "cat src/product.cc | sh", "cat $(whoami)", "cat src/product.cc > /tmp/other",
      "cat src/product.cc || cat src/unrelated.cc", "cat src/product.cc; touch src/product.cc",
      "cat src/product.cc &&", "cat src/product.cc &", "cat src/product.cc &&& cat src/unrelated.cc",
      "cat src/product.cc;; cat src/unrelated.cc", "cat src/product.cc; rg -n pattern src/*"] do
    require ((SourceEvidence.commandFiles? command).isNone)
      "unsupported filter/foreign read/substitution acquired complete dependencies"
  require (SourceEvidence.workTargets? first ("shell\n" ++ input.compress) == some ["src/product.cc"])
    "native source was not resolved relative to the workspace"
  require (!(← SourceEvidence.capture first
    (Json.mkObj [("url", toJson "https://example.com/product")]) (← deadline)).record.complete)
    "unavailable URI was asserted current"
  let tool : ToolEvent := {
    name := "Bash", useId := "related-one", input := input.compress
    response := (Json.mkObj [("output", toJson "product version A evidence")]).compress }
  let current ← SourceEvidence.capture first input (← deadline)
  testMixedReadCapture first body tool
  testIndependentObservations first body
  -- Each result owns its dependencies. Unknown or superseded results must
  -- not poison an unrelated, verified completion in the same handoff.
  IO.FS.writeFile (first / "src/second.cc") "independent source B"
  testBatchCapture first moved body
  let secondSource ← SourceEvidence.capture first
    (Json.mkObj [("command", toJson "cat src/second.cc")]) (← deadline)
  let uses : List SourceUse := [
    {owner := "result-A", references := [0], completed := true},
    {owner := "result-B", references := [1], completed := true},
    {owner := "unknown", references := [2], completed := true},
    {owner := "invalid-index", references := [999], completed := true}]
  let checkpoints := uses.map fun use => ({
    use, key := "d:" ++ use.owner, fragment := some use.owner,
    connection := "GRAPH " ++ use.owner ++ "\n  COVERED WORK\n    MATCH CURRENT " ++ use.owner } : SourceCheckpoint)
  let originalBody := "Original evidence A and B, plus an unverified historical result."
  let delta := renderDeltaFrames (checkpoints.map (·.connection))
  let mixedHandoff : Handoff := {
    text := originalBody ++ "\n\n" ++ delta, reason := "mixed-fixture"
    deliveredGraphs := ["h:history", "g:evidence"] ++ checkpoints.map (·.key)
    completed := 4, advisory := 0, localUnions := 4
    coveredFragments := uses.map (·.owner), blocksCurrent := true
    sourceRecords := [current.record, secondSource.record, SourceEvidence.unverified]
    sourceUses := uses, sourceCheckpoints := checkpoints, controlDeltaChars := delta.length + 2 }
  require mixedHandoff.controlSuffixValid "source control fixture has no valid framed suffix"
  let checkedMixed ← mixedHandoff.checkSources {workspace := first, deadline := ← deadline}
  require (checkedMixed.controlSuffixValid && checkedMixed.reason.endsWith "sources=mixed" && checkedMixed.completed == 2 &&
    checkedMixed.advisory == 2 && checkedMixed.blocksCurrent &&
    checkedMixed.coveredFragments == ["result-A", "result-B"] &&
    checkedMixed.deliveredGraphs.contains "d:result-A" && checkedMixed.deliveredGraphs.contains "d:result-B" &&
    !checkedMixed.deliveredGraphs.contains "d:unknown" && !checkedMixed.deliveredGraphs.contains "d:invalid-index")
    "unverified results poisoned verified controls or acquired a checkpoint"
  require (checkedMixed.text.contains originalBody && !checkedMixed.text.contains "GRAPH unknown\n" &&
    !checkedMixed.text.contains "GRAPH invalid-index\n" && checkedMixed.text.length ≤ 24000)
    "source filtering erased original evidence or left unverified control instructions"
  require (checkedMixed.text.contains "GRAPH result-A: recorded file dependencies unchanged" &&
      checkedMixed.text.contains "GRAPH result-B: recorded file dependencies unchanged" &&
      !checkedMixed.text.contains "GRAPH unknown:" &&
      !checkedMixed.text.contains "GRAPH invalid-index:")
    "mixed source display lost confirmed observations or invented an unchecked-source verdict"
  let ledger ← SourceEvidence.observeRecords first mixedHandoff.sourceRecords (← deadline)
  let conflicting := {mixedHandoff with sourceUses := uses ++
    [{owner := "result-A", references := [2], completed := false}]}
  require ((checkedOwnerSources? conflicting.sourceRecords (ownerSourceUses conflicting "result-A")
      ledger).isNone &&
      (checkedOwnerSources? mixedHandoff.sourceRecords [] ledger).isNone)
    "a verified sibling or empty owner acquired an unconditional current-source label"
  for budget in [0, 16, 160, 512, 24000] do
    let table := renderOwnerSourceStatus mixedHandoff ledger budget
    require (table.text.length ≤ budget) "owner status exceeded the remaining handoff budget"
  let frameOnly ← ({mixedHandoff with text := delta, controlDeltaChars := delta.length}).checkSources
    {workspace := first, deadline := ← deadline}
  require (frameOnly.controlSuffixValid && frameOnly.completed == 2 && frameOnly.blocksCurrent)
    "source notice broke a filtered delta without an original body"
  IO.FS.writeFile (first / "src/product.cc") (body ++ " superseded A")
  let checkedEdit ← mixedHandoff.checkSources {workspace := first, deadline := ← deadline}
  require (checkedEdit.controlSuffixValid && checkedEdit.completed == 1 && checkedEdit.blocksCurrent &&
    checkedEdit.coveredFragments == ["result-B"] && !checkedEdit.deliveredGraphs.contains "d:result-A" &&
    checkedEdit.deliveredGraphs.contains "d:result-B" && checkedEdit.text.contains originalBody &&
    !checkedEdit.text.contains "GRAPH result-A\n" && checkedEdit.text.contains "GRAPH result-B\n")
    "editing one result's source revoked a different result or retained stale control"
  require (checkedEdit.text.contains "GRAPH result-A: recorded file dependencies changed" &&
      checkedEdit.text.contains "GRAPH result-B: recorded file dependencies unchanged")
    "one changed source mislabeled an unchanged result"
  IO.FS.writeFile (first / "src/product.cc") body
  let namedA ← mixedHandoff.checkSources {
    workspace := first, deadline := ← deadline, native := true, targets := some ["src/product.cc"]}
  require (namedA.coveredFragments == ["result-A"] && !namedA.deliveredGraphs.contains "d:result-B")
    "a different relative path supplied authority for the named source"
  require (namedA.text.contains "GRAPH result-A: recorded file dependencies unchanged" &&
      namedA.text.contains "GRAPH result-B: recorded file dependencies unchanged")
    "native target coverage was incorrectly presented as source freshness"
  let wider ← mixedHandoff.checkSources {
    workspace := first, deadline := ← deadline, native := true,
    targets := some ["src/product.cc", "src/second.cc"]}
  require (!wider.blocksCurrent && wider.coveredFragments.isEmpty && wider.completed == 0 &&
      wider.text.contains "GRAPH result-A: recorded file dependencies unchanged" &&
      wider.text.contains "GRAPH result-B: recorded file dependencies unchanged")
    "broader operation lost fresh evidence or was erased by only partially applicable results"
  let unknownTargets ← mixedHandoff.checkSources {
    workspace := first, deadline := ← deadline, native := true}
  require (!unknownTargets.blocksCurrent && unknownTargets.coveredFragments.isEmpty &&
      unknownTargets.completed == 0 &&
      unknownTargets.text.contains "GRAPH result-A: recorded file dependencies unchanged" &&
      unknownTargets.text.contains "GRAPH result-B: recorded file dependencies unchanged")
    "unknown native operation scope lost fresh evidence or acquired completion authority"
  let statusKeys := fun (handoff : Handoff) => handoff.deliveredGraphs.filter (·.startsWith "s:")
  require (statusKeys namedA == statusKeys wider && statusKeys wider == statusKeys unknownTargets)
    "different operation targets repeatedly recreated the same source status"
  testScopedRefresh first current.record
  let malformed ← ({mixedHandoff with text := mixedHandoff.text ++ "corrupt suffix"}).checkSources
    {workspace := first, deadline := ← deadline}
  require (malformed.reason == "search-incomplete" && !malformed.blocksCurrent && malformed.completed == 0)
    "invalid restored control framing remained usable"
  require (sourceStatusReserve == 267) "source notices increased the evidence budget reserve"
  let certified := {tool with source := some current}
  let owner := (compileOperationOutcomes (.text "source-chat") (.text "source-turn") tool).2
  require (owner == (compileOperationOutcomes (.text "source-chat") (.text "source-turn") certified).2)
    "late source metadata changed the observed owner"
  let receipt := SourceEvidence.receipt (.text "source-chat") (.text "source-turn")
    (.text tool.useId) owner current.record
  require (SourceEvidence.receiptRecord? owner receipt == some current.record &&
    (SourceEvidence.receiptRecord? (.text "foreign owner") receipt).isNone) "certificate accepted another owner"
  let files ← sessionFiles "portable-source-receipt"
  recordTool files "source-turn" tool
  let path := toolReceiptPath files "source-turn" tool.useId
  let before ← FileSystem.readVersion (← FileSystem.openRead path.toString)
  recordTool files "source-turn" certified
  recordTool files "source-turn" certified
  require (before == (← FileSystem.readVersion (← FileSystem.openRead path.toString)))
    "certificate or replay rewrote the native body"
  require ((← recordedTool? files "source-turn" tool).any (·.source.isSome)) "source companion not restored"
  let conflict ← try
    recordTool files "source-turn" {tool with response := "different result"}
    pure false
    catch _ => pure true
  require conflict "conflicting receipt ID replaced a result"
  IO.FS.writeFile (sourceCertificatePath files "source-turn" tool.useId) "broken metadata"
  require ((← recordedTool? files "source-turn" tool).any
    (fun t => t.response == tool.response && t.source.isNone)) "invalid provenance discarded native work"
  let authority ← PageMap.create (root / "authority") (Persistence.valueToJson (.text "source-fixture")).compress
  let (ownerId, _, _) ← PageMap.withWriter authority fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root owner
    Store.writeChange writer ⟨[id], [], false⟩
    pure id
  let initial ← PageMap.pin (root / "authority")
  let population ← Store.getNat initial.get "candidates"
  let semanticPopulation ← Store.getNat initial.get "semanticPopulation"
  let selection : Config.Selection := {
    label := "source", semanticMatcher := none
    read := [{name := "source", path := root / "authority"}]
    write := some {name := "source", path := root / "authority"}
    handoffChars := 24000 }
  let context : SourceContext := {workspace := first, deadline := ← deadline}
  let ask := fun ctx => automaticHandoff selection (canonicalToolWork tool) [] false
    none [] true true (some ctx)
  let some historical ← ask context | throw (IO.userError "source fixture did not match native work")
  require (historical.reason.endsWith "sources=historical" && historical.completed == 0)
    "missing certificate authorized completion"
  let some unknownReplay ← automaticHandoff selection (canonicalToolWork tool)
      historical.deliveredGraphs false none [] true true
      (some {context with deadline := ← deadline}) |
    throw (IO.userError "already delivered unknown work lost source refresh metadata")
  require (unknownReplay.text.isEmpty && statusKeys unknownReplay == [] &&
      !unknownReplay.blocksCurrent && unknownReplay.completed == 0)
    "already delivered unknown work repeated an unscoped source warning"
  let (receiptId, _, _) ← PageMap.withWriter (← PageMap.pin (root / "authority")) fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root receipt
    require (id == (← intern.root receipt)) "replay allocated another source root"
    Store.writeChange writer ⟨[id], [], false⟩
    pure id
  let published ← PageMap.pin (root / "authority")
  require ((← Store.getNat published.get "candidates") == population &&
    (← Store.getNat published.get "semanticPopulation") == semanticPopulation + 1 &&
    (← Store.getNat published.get "liveOutcomes") == 1)
    "Exact metadata changed Outcome counts or exposed Exact descendants as semantic nodes"
  let reader ← Store.NodeReader.new published
  require ((← reader.sources ownerId) == [current.record]) "owner source index lost its certificate"
  let some (some nativeFast) ← indexedTerminalRoot selection [some published]
      (canonicalToolWork tool) [] true none true true |
    throw (IO.userError "native source fixture did not use the terminal fast path")
  let nativeFast ← nativeFast.checkSources {context with
    deadline := ← deadline
    native := true
    targets := some ["src/product.cc"]}
  require (nativeFast.reason.endsWith "sources=matched" && nativeFast.sourceRecords.contains current.record)
    ("native terminal fast path lost source authority: " ++ nativeFast.reason)
  let some matching ← ask {context with deadline := ← deadline} | throw (IO.userError "late certificate lost handoff")
  require (matching.reason.endsWith "sources=matched" && matching.text.length ≤ selection.handoffChars)
    "late certificate did not invalidate missing source dependency or exceeded budget"
  let cachedSnapshot ← PageMap.pin (root / "authority")
  let engine ← FileSystem.readVersion (← FileSystem.openRead (← IO.appPath).toString)
  let request := demandRequest engine selection
    (canonicalToolWork tool) [] false none [] true true true
  let some memo ← DemandMemo.read cachedSnapshot request | throw (IO.userError "freshness fixture has no durable demand memo")
  require (← DemandMemo.dependenciesAgree memo [root / "authority"] [some cachedSnapshot])
    "freshness fixture does not exercise a reusable memo"
  let some unchanged ← automaticHandoff selection (canonicalToolWork tool) matching.deliveredGraphs false
      none [] true true (some {context with deadline := ← deadline}) |
    throw (IO.userError "delivered source did not retain refresh metadata")
  require unchanged.text.isEmpty "unchanged delivered source repeated a notice or body"
  IO.FS.writeFile (first / "src/product.cc") (body ++ " changed again")
  let some changed ← ask {context with deadline := ← deadline} | throw (IO.userError "source change lost history")
  require (changed.reason.endsWith "sources=historical" && changed.completed == 0 &&
    !changed.blocksCurrent && changed.coveredFragments.isEmpty) "memo hit reused stale authority"
  let some refreshed ← automaticHandoff selection (canonicalToolWork tool) matching.deliveredGraphs false
      none [] true true (some {context with deadline := ← deadline}) |
    throw (IO.userError "already delivered source change was lost")
  require ((refreshed.text.splitOn "src/product.cc: changed").length == 2)
    "already delivered source did not identify the changed file"
  require (!refreshed.blocksCurrent && refreshed.completed == 0 &&
    (refreshed.text.splitOn "GROUNDED OUTCOME").length == 1)
    "source refresh replayed a body or controlled native Work"
  let some repeated ← automaticHandoff selection (canonicalToolWork tool)
      (matching.deliveredGraphs ++ refreshed.deliveredGraphs) false none [] true true
      (some {context with deadline := ← deadline}) |
    throw (IO.userError "repeated refresh metadata disappeared")
  require repeated.text.isEmpty "same source change repeatedly notified"
  let deliveryState : ThreadState := {
    profile := "source"
    deliveredGraphs := ["g:root", "d:checkpoint", "h:owner"]}
  let deliveryState := (List.range 100).foldl (fun state n =>
    addDeliveredGraphs state ["s:one-scope:" ++ toString n]) deliveryState
  require (deliveryState.deliveredGraphs.length == 4 &&
    ["g:root", "d:checkpoint", "h:owner", "s:one-scope:99"].all deliveryState.deliveredGraphs.contains)
    "freshness status retained obsolete observations or erased graph/checkpoint delivery"
  let tooSmall ← matching.checkSources {context with
    deadline := ← deadline
    handoffChars := 1}
  require (tooSmall.text.isEmpty && tooSmall.deliveredGraphs.isEmpty &&
    tooSmall.completed == 0 && !tooSmall.blocksCurrent)
    "small notice budget overflowed or authorized an undelivered checkpoint"
  let _ ← PageMap.withWriter (← PageMap.pin (root / "authority")) fun writer => do
    Store.removeRoot writer receiptId
    Store.writeChange writer ⟨[], [receiptId], false⟩
  let retracted ← PageMap.pin (root / "authority")
  require ((← (← Store.NodeReader.new retracted).sources ownerId).isEmpty) "withdrawn source remained indexed"
  require ((← Store.getNat retracted.get "candidates") == population) "source withdrawal removed its result"
  -- The same observed owner may be present in two sources with its certificate
  -- only in the second. Canonicalization must retain both provenance origins.
  let shared ← PageMap.create (root / "shared") (Persistence.valueToJson (.text "shared-fixture")).compress
  let _ ← PageMap.withWriter shared fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let firstId ← intern.root owner
    let sourceId ← intern.root receipt
    Store.writeChange writer ⟨[firstId, sourceId], [], false⟩
  let federated := {selection with read := selection.read ++ [{name := "shared", path := root / "shared"}]}
  let some relocated ← automaticHandoff federated (canonicalToolWork tool) [] false
      none [] true true (some {context with workspace := moved, deadline := ← deadline}) |
    throw (IO.userError "federation lost a duplicated owner")
  require (relocated.reason.endsWith "sources=matched") "federation discarded the second source certificate"
  -- Certificate-only reads must not hydrate their referenced giant Outcome.
  let large := (observedWorkOutcome (.text "load giant result")
    (.atom (.mk (Array.replicate (1024 * 1024) (254 : UInt8)))) (.text "large observation")).2
  let giantReceipt := SourceEvidence.receipt (.text "source-chat") (.text "source-turn")
    (.text "giant") large current.record
  let (largeId, _, _) ← PageMap.withWriter (← PageMap.pin (root / "shared")) fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let largeId ← intern.root large
    let sourceId ← intern.root giantReceipt
    Store.writeChange writer ⟨[largeId, sourceId], [], false⟩
    pure largeId
  let largeSnapshot ← PageMap.pin (root / "shared")
  let beforeBytes ← largeSnapshot.readBytes.get
  require ((← (← Store.NodeReader.new largeSnapshot).sources largeId) == [current.record])
    "giant owner's source certificate was lost"
  let sourceBytes := (← largeSnapshot.readBytes.get) - beforeBytes
  require (sourceBytes < 128 * 1024) "source metadata hydrated a giant result body"
  -- Real terminal capture retains the native result before sealing provenance.
  let hookSession := "portable-source-hook"
  let hookFiles ← sessionFiles hookSession
  let pending : PendingTurn := {
    sessionId := hookSession, turnId := "hook-turn", cwd := moved.toString
    prompt := "inspect product", profile := "work", semanticMatcher := none
    read := [], write := none, handoffChars := 24000, projection := .automatic }
  writeJson hookFiles.state ({profile := "work"} : ThreadState)
  writeJson hookFiles.pending pending
  let event := fun name useId response => Json.mkObj [
    ("hook_event_name", toJson name), ("session_id", toJson hookSession),
    ("turn_id", toJson pending.turnId), ("tool_name", toJson tool.name),
    ("tool_use_id", toJson useId), ("tool_input", input), ("tool_response", response)]
  let _ ← preToolUse (event "PreToolUse" "native-good" Json.null)
  let result := Json.mkObj [("output", toJson "native result stays durable")]
  captureTerminal (event "PostToolUse" "native-good" result)
  let good : ToolEvent := {tool with useId := "native-good", response := result.compress}
  require ((← recordedTool? hookFiles pending.turnId good).any
    (fun t => t.source.any (·.record.complete))) "real terminal capture did not seal source provenance"
  let pipelineInput := Json.mkObj [("command", toJson
    "nl -ba src/product.cc | sed -n '1,20p;30,40p'")]
  let pipelineEvent := fun name => Json.mkObj [
    ("hook_event_name", toJson name), ("session_id", toJson hookSession),
    ("turn_id", toJson pending.turnId), ("tool_name", toJson "Bash"),
    ("tool_use_id", toJson "native-pipeline"), ("tool_input", pipelineInput),
    ("tool_response", result)]
  let _ ← preToolUse (pipelineEvent "PreToolUse")
  captureTerminal (pipelineEvent "PostToolUse")
  let pipelineTool : ToolEvent := {tool with
    useId := "native-pipeline", input := pipelineInput.compress,
    response := result.compress}
  require ((← recordedTool? hookFiles pending.turnId pipelineTool).any fun t =>
      t.source.any fun s => s.record.complete && s.record.files.map (·.relative) == ["src/product.cc"])
    "actual Bash read pipeline did not preserve its owner-bound native source certificate"
  testNativeBatchCapture moved hookSession pending.turnId hookFiles result
  IO.FS.writeFile (moved / "src/driver.cc") (String.ofList (List.replicate (340 * 1024) 'a'))
  let driverInput := Json.mkObj [("command", toJson "nl -ba src/driver.cc | sed -n '1,20p'")]
  let driverEvent := fun name => Json.mkObj [
    ("hook_event_name", toJson name), ("session_id", toJson hookSession),
    ("turn_id", toJson pending.turnId), ("tool_name", toJson "Bash"),
    ("tool_use_id", toJson "native-driver"), ("tool_input", driverInput),
    ("tool_response", result)]
  let driverStart ← IO.monoNanosNow
  let _ ← preToolUse (driverEvent "PreToolUse")
  captureTerminal (driverEvent "PostToolUse")
  let driverNs := (← IO.monoNanosNow) - driverStart
  let driverTool : ToolEvent := {tool with
    useId := "native-driver", input := driverInput.compress,
    response := result.compress}
  require ((← recordedTool? hookFiles pending.turnId driverTool).any fun t =>
      t.source.any (·.record.complete))
    "ordinary Driver-sized Bash source did not fit the actual capture window"
  IO.println ((Json.mkObj [("kind", toJson "native_bash_source_capture"),
    ("file_bytes", toJson (340 * 1024 : Nat)), ("pre_post_ns", toJson driverNs)]).compress)
  let remoteInput := Json.mkObj [("path", toJson "src/product.cc")]
  let remote : ToolEvent := {
    name := "mcp__remote__read_file", useId := "remote-local-spelling", input := remoteInput.compress,
    response := result.compress }
  let remoteEvent := fun name => Json.mkObj [
    ("hook_event_name", toJson name), ("session_id", toJson hookSession),
    ("turn_id", toJson pending.turnId), ("tool_name", toJson remote.name),
    ("tool_use_id", toJson remote.useId), ("tool_input", remoteInput), ("tool_response", result)]
  let _ ← preToolUse (remoteEvent "PreToolUse")
  captureTerminal (remoteEvent "PostToolUse")
  require ((← recordedTool? hookFiles pending.turnId remote).any
    (fun t => t.response == remote.response && t.source.isNone))
    "unknown MCP path acquired a local freshness certificate or lost its result"
  let directOverride : ToolEvent := {tool with
    input := (Json.mkObj [("command", toJson "cat src/product.cc"),
      ("path", toJson "src/unrelated.cc")]).compress }
  let some localInput := nativeSourceInput? directOverride |
    throw (IO.userError "literal local source command was rejected")
  require (SourceEvidence.inputPaths localInput == ["src/product.cc"])
    "an unrelated argument replaced the local command's true dependencies"
  let _ ← preToolUse (event "PreToolUse" "native-stale" Json.null)
  IO.FS.writeFile (moved / "src/product.cc") (body ++ " changed during native execution")
  captureTerminal (event "PostToolUse" "native-stale" result)
  let stale : ToolEvent := {good with useId := "native-stale"}
  require ((← recordedTool? hookFiles pending.turnId stale).any
    (fun t => t.response == stale.response && t.source.any (fun s => !s.record.complete)))
    "real terminal capture lost work or authorized a changed source"
  IO.println ((Json.mkObj [("source_certificate_read_bytes", toJson sourceBytes),
    ("referenced_result_bytes", toJson (1024 * 1024 : Nat))]).compress)
  IO.println "PASS portable sources: streamed fingerprints, relocation, edit/delete/absence, unknown URI, exact owner, immutable native receipt, late indexed certificate, demand-memo freshness and retraction, query-independent freshness with scoped native controls"

end Eggshell.SourceEvidenceTests
