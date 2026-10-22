import Eggshell.SynapseImport
import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def reject (action : IO α) (message : String) : IO Unit := do
  let rejected ← try let _ ← action; pure false catch _ => pure true
  check rejected message

private def occurrence (name : String) : Occurrence := ⟨"recorded", "turn", name⟩
private def command := "nl -ba src/source.cpp | sed -n '10,12p'"
private def output := "  10\talpha\n  11\tNEEDED_SYMBOL\n  12\tomega\n"

private def event (name invocation result : String) : Plugin.ToolEvent := {
  name := "shell", useId := name
  input := (Json.mkObj [("command", toJson invocation)]).compress
  response := (Json.mkObj [("output", toJson result)]).compress }

private def publish (source : DB.PageMap.Snapshot) (tool : Plugin.ToolEvent) :
    IO (DB.PageMap.Snapshot × Nat) := do
  let relation := (Plugin.compileOperationOutcomes (.text "recorded") (.text "turn") tool).2
  let receipt := SourceEvidence.receipt (.text "recorded") (.text "turn") (.text tool.useId) relation {
    workspace := "/fixture", complete := true
    files := [⟨"src/source.cpp", some ⟨1000, String.ofList (List.replicate 64 'c')⟩⟩] }
  let (id, _, _) ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root relation
    let certificate ← intern.root receipt
    writeChange writer ⟨[id, certificate], [], false⟩
    return id
  return (← DB.PageMap.pin source.directory, id)

private def row (name : String) (started : Bool) (time : Option Nat)
    (invocation := command) (result := output) : Json :=
  let item := Json.mkObj [("id", toJson name), ("type", toJson "commandExecution"),
    ("command", toJson invocation), ("aggregatedOutput", toJson result)]
  let message := Json.mkObj [("method", toJson (if started then "item/started" else "item/completed")),
    ("params", Json.mkObj [("threadId", toJson "recorded"), ("turnId", toJson "turn"), ("item", item)])]
  let base := Json.mkObj [("direction", toJson "server"), ("message", message)]
  match time with | none => base | some value => base.setObjVal! "monotonic_ns" (toJson value)

private def recording (root : System.FilePath) (name : String) (rows : Array Json) : IO System.FilePath := do
  let path := root / name
  IO.FS.writeFile path ("\n".intercalate (rows.toList.map Json.compress) ++ "\n")
  return path

private def authoritative (source : DB.PageMap.Snapshot) : IO (Array DB.PageMap.Row) := do
  let some root := source.head.root | return #[]
  source.foldRange ⟨root.first, root.last ++ "\x00"⟩ (fun rows row =>
    pure (if DB.PageMap.derivedKey row.1 || row.1.startsWith "change:" then rows else rows.push row)) #[]

private def run (root : System.FilePath) : IO Unit := do
  let source ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "authority")).compress
  let (source, producer) ← publish source (event "read" command output)
  let (source, consumer) ← publish source (event "use" "printf NEEDED_SYMBOL" "done")
  let original ← authoritative source
  let bytes ← IO.FS.readBinFile (source.directory / "head")
  let capture ← recording root "exact.jsonl" #[row "read" true (some 10), row "read" false (some 20),
    row "use" true (some 30) "printf NEEDED_SYMBOL" "done",
    row "use" false (some 40) "printf NEEDED_SYMBOL" "done"]
  let parsed ← Import.recording capture
  check (parsed.calls.size == 2 && parsed.incomplete == 0) "actual intervals were not read"
  let plan ← Import.plan source #[capture]
  check (plan.matched == 2 && plan.origins.any (fun value => value.owner == producer &&
    value.started == 10 && value.finished == 20 && value.domain == parsed.domain) &&
    plan.origins.any (·.owner == consumer)) "exact original binding changed the recorded clock"
  check ((← IO.FS.readBinFile (source.directory / "head")) == bytes &&
    (← Provenance.records source).isEmpty) "planning wrote to the source"
  let reader ← NodeReader.new source
  let doc ← Provenance.document reader producer
  let some call := parsed.calls[0]? | throw (IO.userError "missing first observed call")
  check ((Import.bind? doc call).isSome &&
    (Import.bind? {doc with native := false} call).isNone &&
    (Import.bind? {doc with occurrences := #[]} call).isNone &&
    (Import.bind? doc {call with output := "NEEDED_SYMBOL"}).isNone &&
    (Import.bind? doc {call with command := "printf NEEDED_SYMBOL"}).isNone &&
    (Import.bind? doc {call with finished := call.started}).isNone)
    "binding accepted non-native, foreign, partial-output, wrong-invocation or unordered evidence"
  let changed ← recording root "changed.jsonl" #[row "read" true (some 10),
    row "read" false (some 20) command "NEEDED_SYMBOL"]
  let changedPlan ← Import.plan source #[changed]
  check (changedPlan.matched == 0 && changedPlan.outputMismatch == 1)
    "substring output was accepted as an entire original output"
  let wrong ← recording root "wrong.jsonl" #[row "read" true (some 10) "printf NEEDED_SYMBOL",
    row "read" false (some 20) "printf NEEDED_SYMBOL"]
  check ((← Import.plan source #[wrong]).invocationMismatch == 1) "wrong invocation bound by occurrence alone"
  let foreign ← recording root "foreign.jsonl" #[row "absent" true (some 10), row "absent" false (some 20)]
  check ((← Import.plan source #[foreign]).absentOccurrence == 1) "absent source occurrence was invented"
  let incomplete ← recording root "incomplete.jsonl" #[row "read" true none, row "read" false (some 20)]
  let missing ← Import.recording incomplete
  check (missing.calls.isEmpty && missing.incomplete > 0) "missing observed time was fabricated"
  let backwards ← recording root "backwards.jsonl" #[row "read" true (some 20), row "read" false (some 10)]
  reject (Import.recording backwards) "backwards observed clock was accepted"
  let equal ← recording root "equal.jsonl" #[row "read" true (some 10), row "read" false (some 10)]
  reject (Import.recording equal) "nonpositive observed interval was accepted"
  let conflict ← recording root "conflict.jsonl" #[row "read" true (some 10),
    row "read" false (some 20) "printf NEEDED_SYMBOL"]
  reject (Import.recording conflict) "completion changed the started invocation"
  let duplicate ← recording root "duplicate.jsonl" #[row "read" true (some 10),
    row "read" true (some 11), row "read" false (some 20), row "read" false (some 21)]
  let deduplicated ← Import.recording duplicate
  let some first := deduplicated.calls[0]? | throw (IO.userError "missing deduplicated call")
  check (deduplicated.calls.size == 1 && first.started == 10 && first.finished == 20)
    "duplicate notifications changed the first observed interval"
  let updated ← Provenance.publish source plan.origins
  check ((← authoritative updated) == original && (← Index.sameSources updated source.head))
    "import changed graph or authority rows"
  let derived ← Provenance.derive updated
  check (derived.graph.snapshot.any fun fact => match fact with
    | .consumed value => value.consumer == occurrence "use" && value.producer == occurrence "read" &&
      value.rows.any (·.first == 11)
    | _ => false) "observed chronology did not produce an original-row consumption witness"
  let retry ← Import.plan updated #[capture]
  check (retry.origins.isEmpty && retry.alreadyPresent == 2 &&
    (← Provenance.publish updated retry.origins).head == updated.head) "import retry appended new provenance"
  -- Copy only authoritative DB pages plus query-free provenance: no RPC or
  -- private event logs are needed to reconstruct the same consumption graph.
  let copied := root / "copied.egg"
  IO.FS.createDirAll copied
  for entry in ← updated.directory.readDir do
    if entry.fileName == "head" || entry.fileName.endsWith ".pages" then
      IO.FS.writeBinFile (copied / entry.fileName) (← IO.FS.readBinFile entry.path)
  check ((← Provenance.derive (← DB.PageMap.pin copied)).graph.snapshot == derived.graph.snapshot)
    "DB-only copy lost the imported relation"
  -- The same observed occurrence bound to two different original outputs is
  -- not resolved by choosing an allocation id or the first listed owner.
  let another := {(event "read" command output) with
    input := (Json.mkObj [("command", toJson command), ("tag", toJson "another-original")]).compress}
  let (ambiguous, _) ← publish updated another
  let ambiguity ← Import.plan ambiguous #[capture]
  check (ambiguity.ambiguous == 1) "ambiguous owner silently selected"
  IO.println "Lean import tests passed: exact identities/invocation/full output, observed clocks, neutral/idempotent metadata and DB-only reconstruction"

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "SynapseImportTests NEW-DIRECTORY")
  let root := System.FilePath.mk path
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute fixture required")
  IO.FS.createDirAll root
  run root
