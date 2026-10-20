import Eggshell.Install

open Lean Eggshell Plugin Persistence Store

namespace RetrievalScale

def work (index : Nat) : String :=
  s!"Inspect kernel realtime clock source {index}: monotonic scheduling and elapsed timer observations"

def body (index requested : Nat) : String :=
  if index == 0 && requested ≥ 32 then
    let text := String.join ((List.range 256).map fun chunk =>
      s!"ORIGINAL_CLOCK_BODY_0 chunk {chunk}: observed kernel timer and monotonic clock scheduling.\n")
    String.ofList (text.toList.take (32 * 384 - (work 0).length - 1))
  else s!"ORIGINAL_CLOCK_BODY_{index}: observed kernel timer and monotonic clock scheduling source {index}."

def owner (index requested : Nat) : OutcomeEdge :=
  OutcomeEdge.make (.text (work index)) (.text (body index requested)) [] (by simp) (by simp)

def graphFiles (database : System.FilePath) : IO Json := do
  let mut fields := []
  for entry in ← database.readDir do
    if (← entry.path.symlinkMetadata).type == .file then
      let some (fingerprint, _) ← SourceEvidence.fingerprint entry.path ((← IO.monoMsNow) + 600000) |
        throw (IO.userError "scale graph fingerprint did not finish on a stable file")
      fields := fields ++ [(entry.fileName, toJson fingerprint)]
  pure (Json.mkObj fields)

/-- This producer must be compiled against the original save-time policy.
The same saved graph, not newly generated arms, is the study input. -/
def prepare (directory : System.FilePath) (requested : Nat) : IO Json := do
  unless requested > 0 && requested ≤ 50000 do throw (IO.userError "window count must be in 1..50000")
  FileSystem.privateDirectory directory
  let directory ← IO.FS.realPath directory
  let database := directory / "source.egg"
  let documents := if requested ≥ 32 then requested - 31 else requested
  let initial ← match ← DB.PageMap.open? database with
    | some snapshot => pure snapshot
    | none => DB.PageMap.create database (Persistence.valueToJson (.text s!"scale fixture {requested}")).compress
  let existing ← searchDocuments initial
  unless existing.length ≤ documents do throw (IO.userError "saved scale fixture exceeds its fixed prefix")
  let reader ← NodeReader.new initial
  for (document, index) in existing.zipIdx do
    let restored ← reader.outcome (← reader.locateOutcome document.owner)
    unless restored.relation == (owner index requested).relation do
      throw (IO.userError "saved scale fixture differs from its expected prefix")
  let started ← IO.monoMsNow
  let mut saved := existing.length
  let mut snapshot := initial
  while saved < documents do
    let stop := min documents (saved + 32)
    let _ ← DB.PageMap.withWriter snapshot fun writer => do
      let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
      let mut roots := []
      for index in [saved:stop] do
        roots := (← intern.root (owner index requested).relation) :: roots
      writeChange writer {added := roots.reverse, removed := [], unionsChanged := false}
    saved := stop
    snapshot ← DB.PageMap.pin database
    if saved % 1024 == 0 || saved == documents then
      IO.eprintln s!"saved {saved}/{documents} owners for {requested} windows"
  let observed ← searchDocuments snapshot
  let references := (observed.map (·.windows.length)).sum
  let unique := (Std.HashSet.ofList (observed.flatMap (·.windows))).size
  unless observed.length == documents && references == requested && unique == requested do
    throw (IO.userError s!"scale fixture counts disagree: {observed.length} owners, {references} references, {unique} keys")
  let result := Json.mkObj [
    ("requestedWindows", toJson requested), ("documents", toJson documents),
    ("windowReferences", toJson references), ("uniqueWindows", toJson unique),
    ("multiOwnerWindows", toJson (if requested ≥ 32 then 32 else 1)),
    ("database", toJson database.toString), ("head", toJson snapshot.head),
    ("graphFiles", ← graphFiles database), ("saveMs", toJson ((← IO.monoMsNow) - started)),
    ("producerContract", toJson (Sha256.hex (include_str "RetrievalScale.lean").toUTF8)),
    ("generationModelCalls", toJson (0 : Nat))]
  writeJson (directory / "fixture.json") result
  pure result

def command : IO (List String) := do
  pure [(← IO.appPath).withFileName "eggshell" |>.toString, "search-provider"]

def warm (database : System.FilePath) (writable : Bool) : IO Json := do
  let before ← graphFiles database
  let result ← Warm.run (← DB.PageMap.pin database) (← command) writable
  unless (← graphFiles database) == before do throw (IO.userError "warming changed the saved source graph")
  pure (toJson result)

def query (database : System.FilePath) (question : String) : IO Json := do
  let snapshot ← DB.PageMap.pin database
  let settings ← SearchProvider.queryOptions (← Warm.options snapshot (← command))
  let windows := SearchRank.windows question
  let mut found := 0
  for part in windows do
    if (← SearchProvider.readVector settings part).isSome then found := found + 1
  pure (Json.mkObj [("ready", toJson (found == windows.length)),
    ("windows", toJson windows.length), ("valid", toJson found)])

end RetrievalScale

def main (arguments : List String) : IO UInt32 := do
  let result ← match arguments with
    | ["prepare", directory, requested] => do
      let some count := requested.toNat? | throw (IO.userError "invalid requested windows")
      RetrievalScale.prepare (.mk directory) count
    | ["warm", database] => RetrievalScale.warm (.mk database) true
    | ["warm-private", database] => RetrievalScale.warm (.mk database) false
    | ["query", database, question] => RetrievalScale.query (.mk database) question
    | _ => throw (IO.userError "retrieval_scale: prepare DIR WINDOWS | warm DB | warm-private DB | query DB QUESTION")
  IO.println result.compress
  pure 0
