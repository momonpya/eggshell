import Eggshell.SynapseBuild

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Build
open Eggshell.Persistence.Store

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def owner (work body : String) : OutcomeEdge :=
  OutcomeEdge.make (.text work) (.text body) [] (by simp) (by simp [maxOutcomeObservations])

private def readOwner (first last : Nat) (tag : String) : OutcomeEdge := Id.run do
  let command := s!"nl -ba src/source.cpp | sed -n '{first},{last}p'"
  let work := Value.text ("shell\n" ++ (Json.mkObj [("command", toJson command)]).compress)
  let body := Value.text ("\n".intercalate ((List.range (last+1-first)).map fun i => s!"  {first+i}\trow-{first+i}") ++ "\n")
  let occurrence := Value.applyList .occurrence [Ref.semantic body, Ref.semantic work,
    Ref.exact (.text "session"), Ref.exact (.text "turn"), Ref.exact (.text tag)]
  return OutcomeEdge.make work body [occurrence] (by simp) (by simp [maxOutcomeObservations])

private def certificate (edge : OutcomeEdge) (tag : String) : Value :=
  SourceEvidence.receipt (.text "session") (.text "turn") (.text tag) edge.relation {
    workspace := "/fixture"
    files := [⟨"src/source.cpp", some ⟨1000, String.ofList (List.replicate 64 'a')⟩⟩]
    complete := true }

private def family (answer read : OutcomeEdge) : IO Value := do
  if distinct : answer.work ≠ read.work then
    return (AllEdge.make answer.work [read.work] (by simp) (by simpa using distinct)).relation
  throw (IO.userError "fixture Work collision")

private def publish (snapshot : DB.PageMap.Snapshot) (values : List Value) (removed : List Nat := []) :
    IO (DB.PageMap.Snapshot × List Nat) := do
  let (ids, _, _) ← DB.PageMap.withWriter snapshot fun writer => do
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    for id in removed do removeRoot writer id
    let ids ← values.mapM intern.root
    writeChange writer ⟨ids, removed, false⟩
    return ids
  return (← DB.PageMap.pin snapshot.directory, ids)

private def facts (snapshot : DB.PageMap.Snapshot) : IO (Array Fact) := do
  let some reader ← Index.open? snapshot .database .shared | throw (IO.userError "missing built index")
  Index.allFacts reader.index

private def supported (snapshot : DB.PageMap.Snapshot) (answer : OutcomeEdge) (line : Nat) : IO Bool := do
  return (← facts snapshot).any fun fact => match fact with
    | .supports support => support.claim.answer == Persistence.selectionKey answer.relation &&
        support.source.first == line && support.source.last == line
    | _ => false

/-- Compare incremental extraction with a cold build of the exact same head.
Only immutable source files are copied; no derived index enters the oracle. -/
private def coldEqual (snapshot : DB.PageMap.Snapshot) (destination : System.FilePath) : IO Unit := do
  IO.FS.createDirAll destination
  for entry in ← snapshot.directory.readDir do
    if entry.fileName == "head" || entry.fileName.endsWith ".pages" then
      IO.FS.writeBinFile (destination / entry.fileName) (← IO.FS.readBinFile entry.path)
  let copied ← DB.PageMap.pin destination
  check (copied.head == snapshot.head) "cold comparison changed its input publication"
  let rebuilt ← refresh copied .database
  check (rebuilt.mode == "rebuild" && (← facts copied) == (← facts snapshot))
    "incremental extraction differs from a cold build of the identical publication"

private def scenario (root : System.FilePath) : IO Unit := do
  let snapshot ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "authority")).compress
  let read := readOwner 10 12 "read-a"
  let answer := owner "question-a" "A [source.cpp:11](src/source.cpp:11) supports this."
  let (snapshot, ids) ← publish snapshot [read.relation, answer.relation, ← family answer read, certificate read "a"]
  let before := snapshot.head
  let first ← refresh snapshot .database
  check (first.mode == "rebuild" && first.hydrated == 2 && first.facts == 4) "native rebuild differs from bound source fixture"
  check (← supported snapshot answer 11) "native source citation lost its exact row"
  check ((← DB.PageMap.pin snapshot.directory).head == before) "extractor changed the source graph"
  let warm ← refresh snapshot .database
  check (warm.mode == "warm" && warm.hydrated == 0 && warm.index == first.index) "warm extractor reread bodies or appended pages"
  let unrelated := owner "unrelated-question" "unrelated answer"
  let (snapshot, _) ← publish snapshot [unrelated.relation]
  let added ← refresh snapshot .database
  check (added.mode == "incremental" && added.hydrated == 1 && added.facts == 4) "unrelated addition rehydrated old source bodies"
  let next := owner "question-b" "B [source.cpp:12](src/source.cpp:12) also applies."
  let (snapshot, _) ← publish snapshot [next.relation, ← family next read]
  let cited ← refresh snapshot .database
  check (cited.mode == "incremental" && cited.hydrated == 2 && cited.facts == 7) "new answer did not hydrate just itself and its cited source"
  check (← supported snapshot next 12) "newly cited old row was not bound"
  let laterRead := readOwner 14 14 "read-b"
  let waiting := owner "question-c" "C [source.cpp:14](src/source.cpp:14) was not available yet."
  let (snapshot, waitingIds) ← publish snapshot [waiting.relation, ← family waiting laterRead]
  let _ ← refresh snapshot .database
  check (!(← supported snapshot waiting 14)) "nonexistent source acquired support"
  let (snapshot, _) ← publish snapshot [laterRead.relation, certificate laterRead "b"]
  let late ← refresh snapshot .database
  check (late.mode == "incremental" && late.hydrated == 2 && (← supported snapshot waiting 14))
    "new observation did not update its previously unsupported ancestor"
  coldEqual snapshot (root / "cold-added.egg")
  let (snapshot, _) ← publish snapshot [] [ids[3]!]
  let retired ← refresh snapshot .database
  check (retired.mode == "incremental" && !(← supported snapshot answer 11) && !(← supported snapshot next 12))
    "retired source certificate left support or coquotation live"
  check (← supported snapshot waiting 14) "unrelated source support was retired"
  let (snapshot, _) ← publish snapshot [] [waitingIds[1]!]
  let _ ← refresh snapshot .database
  check (!(← supported snapshot waiting 14)) "retired All relation left an unreachable support"
  coldEqual snapshot (root / "cold-retired.egg")
  let all ← facts snapshot
  check (all.all fun fact => match fact with | .consumed _ | .used _ => false | _ => true)
    "DB containment invented chronology or private usage"
  let mut derived := snapshot
  for i in [:17] do
    let _ ← DB.PageMap.withWriter derived fun writer => do
      writer.put s!"memo:fixture-{i}" (some "derived-only".toUTF8)
      writeChange writer ⟨[], [], false⟩
    derived ← DB.PageMap.pin snapshot.directory
  check (← Build.required derived .database) "bounded reader should defer a long memo chain to background work"
  let advanced ← refresh derived .database
  check (advanced.mode == "incremental" && advanced.hydrated == 0 && (← facts derived) == all)
    "derived-only catch-up rehydrated bodies or altered source facts"
  IO.println s!"native builder checks passed: rebuild={first.elapsedMs}ms warm={warm.elapsedMs}ms added={added.elapsedMs}ms cited={cited.elapsedMs}ms late={late.elapsedMs}ms retired={retired.elapsedMs}ms"

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "SynapseBuildTests NEW-DIRECTORY")
  let root := System.FilePath.mk directory
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "test directory must be new and absolute")
  IO.FS.createDirAll root
  scenario root
