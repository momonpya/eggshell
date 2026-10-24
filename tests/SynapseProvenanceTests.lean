import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def clockDomain : String := String.ofList (List.replicate 64 'a')
private def occurrence (name : String) : Occurrence := ⟨"portable", "turn", name⟩
private def tool (name command output : String) : Plugin.ToolEvent := {
  name := "shell", useId := name
  input := (Json.mkObj [("command", toJson command)]).compress
  response := (Json.mkObj [("output", toJson output)]).compress }

private def publish (snapshot : DB.PageMap.Snapshot) (event : Plugin.ToolEvent) :
    IO (DB.PageMap.Snapshot × Nat) := do
  let relation := (Plugin.compileOperationOutcomes (.text "portable") (.text "turn") event).2
  let certificate := SourceEvidence.receipt (.text "portable") (.text "turn") (.text event.useId) relation {
    workspace := "/fixture", complete := true
    files := [⟨"src/source.cpp", some ⟨1000, String.ofList (List.replicate 64 'c')⟩⟩] }
  let (id, _, _) ← DB.PageMap.withWriter snapshot fun writer => do
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root relation
    let receipt ← intern.root certificate
    writeChange writer ⟨[id, receipt], [], false⟩
    return id
  return (← DB.PageMap.pin snapshot.directory, id)

private def authoritative (source : DB.PageMap.Snapshot) : IO (Array DB.PageMap.Row) := do
  let some root := source.head.root | return #[]
  source.foldRange ⟨root.first, root.last ++ "\x00"⟩ (fun rows row =>
    pure (if DB.PageMap.derivedKey row.1 || row.1.startsWith "change:" then rows else rows.push row)) #[]

private def facts (source : DB.PageMap.Snapshot) (storage : DB.Sidecar.Storage) : IO (Array Fact) := do
  let some reader ← Index.open? source storage .shared | throw (IO.userError "missing ready index")
  Index.allFacts reader.index

private def reject (action : IO α) (message : String) : IO Unit := do
  let rejected ← try let _ ← action; pure false catch _ => pure true
  check rejected message

private def copySource (source : DB.PageMap.Snapshot) (destination : System.FilePath) : IO Unit := do
  IO.FS.createDirAll destination
  for entry in ← source.directory.readDir do
    if entry.fileName == "head" || entry.fileName.endsWith ".pages" then
      IO.FS.writeBinFile (destination / entry.fileName) (← IO.FS.readBinFile entry.path)

private def fixture (root : System.FilePath) : IO Unit := do
  let source ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "authority")).compress
  let producer := tool "read" "nl -ba src/source.cpp | sed -n '10,12p'"
    "  10\talpha\n  11\tNEEDED_SYMBOL\n  12\tomega\n"
  let consumer := tool "consumer" "printf NEEDED_SYMBOL" "done"
  let (source, producerId) ← publish source producer
  let (source, consumerId) ← publish source consumer
  let before ← authoritative source
  check (!before.isEmpty) "authority scan is empty"
  let _ ← Build.refresh source .database
  check ((← facts source .database).all fun fact => match fact with | .consumed _ => false | _ => true)
    "DB allocation order invented a consumption edge"
  let readOrigin : Provenance.Origin := ⟨producerId, occurrence "read", clockDomain, 10, 20, none⟩
  let useOrigin : Provenance.Origin := ⟨consumerId, occurrence "consumer", clockDomain, 30, 40, none⟩
  for name in ["equal-time.egg", "reverse.egg", "other-clock.egg"] do
    copySource source (root / name)
    IO.FS.writeBinFile (root / name / "writer") ByteArray.empty
  let updated ← Provenance.publish source #[useOrigin, readOrigin]
  check (updated.head != source.head && (← authoritative updated) == before &&
    (← Index.sameSources updated source.head)) "portable metadata changed an authoritative row"
  check ((← Index.open? updated .database .shared).isNone) "provenance change left a stale index ready"
  let _ ← Build.refresh updated .database
  let all ← facts updated .database
  let consumed := all.filterMap fun fact => match fact with | .consumed edge => some edge | _ => none
  check (consumed.any (fun edge => edge.consumer == occurrence "consumer" &&
    edge.producer == occurrence "read" && edge.rows.any (·.first == 11)))
    "DB-native provenance did not restore the original row witness"
  let repeated ← Provenance.publish updated #[readOrigin, useOrigin]
  check (repeated.head == updated.head) "identical provenance appended another publication"
  reject (Provenance.publish updated #[{readOrigin with finished := 21}]) "immutable origin was relabelled"
  reject (Provenance.publish updated #[{readOrigin with owner := consumerId}]) "foreign owner accepted an occurrence"
  reject (Provenance.publish updated #[{readOrigin with finished := 10}]) "nonpositive interval was accepted"
  check ((← DB.PageMap.pin updated.directory).head == updated.head) "rejected origin changed the DB head"
  -- Two calls on the same tick are independent. An output completed on that
  -- tick cannot become input evidence, regardless of stable insertion order.
  let equal := root / "equal-time.egg"
  let equal ← DB.PageMap.pin equal
  let equal ← Provenance.publish equal #[readOrigin, {useOrigin with started := 20}]
  check ((← Provenance.derive equal).graph.snapshot.isEmpty) "equal clock ticks invented causality"
  let reverseDir := root / "reverse.egg"
  let reverse ← DB.PageMap.pin reverseDir
  let reverse ← Provenance.publish reverse #[readOrigin, useOrigin]
  check ((← Provenance.derive reverse).graph.snapshot == (← Provenance.derive updated).graph.snapshot)
    "metadata insertion order became event chronology"
  let otherDir := root / "other-clock.egg"
  let other ← DB.PageMap.pin otherDir
  let other ← Provenance.publish other #[readOrigin,
    {useOrigin with domain := String.ofList (List.replicate 64 'd')}]
  check ((← Provenance.derive other).graph.snapshot.isEmpty) "independent manager clocks were joined"
  -- An independent reader will receive only native DB head/pages and a fresh
  -- private data root; the expected facts are outside the source database.
  copySource updated (root / "copied.egg")
  IO.FS.writeFile (root / "expected.json") (toJson all).compress
  let damagedDir := root / "damaged.egg"
  copySource updated damagedDir
  IO.FS.writeBinFile (damagedDir / "writer") ByteArray.empty
  let damaged ← DB.PageMap.pin damagedDir
  let _ ← DB.PageMap.withWriter damaged fun writer => do
    writer.put (Provenance.name readOrigin.occurrence) none
    writeChange writer ⟨[], [], false⟩
  reject (Provenance.derive (← DB.PageMap.pin damagedDir)) "a missing origin was accepted under an intact chain root"
  let retiredDir := root / "retired.egg"
  copySource updated retiredDir
  IO.FS.writeBinFile (retiredDir / "writer") ByteArray.empty
  let retired ← DB.PageMap.pin retiredDir
  let _ ← DB.PageMap.withWriter retired fun writer => do
    removeRoot writer producerId
    writeChange writer ⟨[], [producerId], false⟩
  let retired ← Provenance.derive (← DB.PageMap.pin retiredDir)
  check (retired.ignored == 1 && retired.graph.snapshot.isEmpty) "retired original remained a consumption producer"
  IO.println s!"portable writer checks passed: {consumed.size} consumption witnesses; immutable, neutral, clock and insertion-order boundaries"

private def copied (root : System.FilePath) : IO Unit := do
  let directory := root / "copied.egg"
  let source ← DB.PageMap.pin directory
  let headBytes ← IO.FS.readBinFile (directory / "head")
  let pages := directory / (source.head.identity ++ ".pages")
  let pageBytes ← IO.FS.readBinFile pages
  check (!(← (directory / "derived").pathExists)) "copy contains a derived cache"
  check ((← Journal.open? source).isNone) "reader inherited a private event journal"
  let (storage, _) ← DB.Sidecar.destination (DB.Sidecar.Owner.ofSnapshot source) false
  check (storage == .user) "read-only profile selected a DB-owned writer"
  let result ← Build.refresh source storage
  let expected ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "expected.json")))
  let expected ← IO.ofExcept (fromJson? (α := Array Fact) expected)
  check ((← facts source storage) == expected) "DB-only copy did not restore identical recommendations"
  check ((← Provenance.records source).size == 2) "copy lost the native provenance chain"
  let ready ← Build.refresh source storage
  check (ready.mode == "warm" && ready.hydrated == 0) "second native warm reread original bodies"
  check ((← IO.FS.readBinFile (directory / "head")) == headBytes &&
    (← IO.FS.readBinFile pages) == pageBytes && !(← (directory / "derived").pathExists))
    "read-only reconstruction wrote to the source database"
  IO.println s!"independent DB-only readonly reader passed: facts={result.facts} rebuild={result.elapsedMs}ms warm={ready.elapsedMs}ms"

def main (args : List String) : IO Unit := do
  match args with
  | ["create", path] =>
    let root := System.FilePath.mk path
    unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute fixture directory required")
    IO.FS.createDirAll root
    fixture root
  | ["copy", path] => copied (.mk path)
  | _ => throw (IO.userError "SynapseProvenanceTests create|copy ROOT")
