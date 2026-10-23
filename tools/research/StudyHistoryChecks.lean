import tools.research.StudyHistory

open Lean Eggshell Eggshell.Research

namespace Eggshell.Research.StudyHistoryChecks

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def rejected (action : IO Unit) : IO Bool := do
  try action; return false
  catch _ => return true

private def mark (path : System.FilePath) (text : String) : IO Unit := do
  let snapshot ← DB.PageMap.pin path
  let _ ← DB.PageMap.withWriter snapshot fun writer =>
    writer.put "fixture" (some text.toUTF8)
  pure ()

def cliMain (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "StudyHistoryChecks NEW-DIRECTORY")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "new absolute fixture root required"
  FileSystem.privateDirectory root
  let source := root / "source.egg"
  let data := root / "data"
  let initial ← DB.PageMap.create source "history-source"
  let id := initial.head.identity
  let synapses := data / "read-cache" / id / "synapses"
  FileSystem.privateDirectory synapses
  for name in #["events", "usage"] do
    let authority := if name == "events" then "private-synaptic-events:" ++ id else "advisory:" ++ id ++ ":usage"
    let _ ← DB.PageMap.create (synapses / name) authority
    mark (synapses / name) (name ++ "-retained")
  FileSystem.privateDirectory (data / "queries")
  IO.FS.writeFile (data / "queries/query.txt") "must not be carried"
  FileSystem.privateDirectory (data / "synaptic-targets")
  IO.FS.writeFile (data / "synaptic-targets/stale.json") "old absolute route"
  let before ← StudyAdmission.tree data
  let sourceFiles ← StudyRuntime.files source
  let _ ← StudyHistory.freeze source data (root / "common")
  let manifest : StudyAdmission.Artifact :=
    ⟨(root / "common/history.json").toString, ← ArtifactHash.hex (root / "common/history.json")⟩
  let first ← StudyHistory.fork manifest (root / "current")
  let second ← StudyHistory.fork manifest (root / "candidate")
  check (toJson first == toJson second && first.privateFamilies.size == 2)
    "the two arms did not receive identical durable history"
  for name in #["current", "candidate"] do
    check ((← StudyRuntime.files (root / name / "work.egg")) == sourceFiles) "source fork differs"
    for family in first.privateFamilies do
      check ((← StudyRuntime.files (root / name / "data/read-cache" / id / "synapses" / family.name)) == family.files)
        "private learning fork differs"
    for forbidden in #["queries", "sessions", "synaptic-targets", "index-targets", "numerical"] do
      check (!(← (root / name / "data" / forbidden).pathExists)) "transient state entered the history fork"
  let candidateUsage := root / "candidate/data/read-cache" / id / "synapses/usage"
  let candidateBefore ← StudyRuntime.files candidateUsage
  mark (root / "current/data/read-cache" / id / "synapses/usage") "current-only-update"
  check ((← StudyRuntime.files candidateUsage) == candidateBefore &&
    (← StudyAdmission.tree data) == before && (← StudyRuntime.files source) == sourceFiles)
    "one arm changed its peer or protected input"
  check (← rejected (do let _ ← StudyHistory.fork manifest (root / "current"); pure ())) "existing arm was overwritten"
  check (← rejected (do let _ ← StudyHistory.fork {manifest with sha256 := "bad"} (root / "bad-digest"); pure ()))
    "changed manifest was accepted"
  check (← rejected (do let _ ← StudyHistory.freeze source data (data / "inside"); pure ()))
    "history was written inside protected data"
  let queued := data / "sessions/pending/deferred"
  FileSystem.privateDirectory queued
  IO.FS.writeFile (queued / "save.json") "{}"
  check (← rejected (do let _ ← StudyHistory.freeze source data (root / "queued"); pure ())) "undrained save was accepted"
  IO.FS.removeFile (queued / "save.json")
  IO.FS.writeFile (data / "sessions/pending/daemon.json") "{}"
  check (← rejected (do let _ ← StudyHistory.freeze source data (root / "live"); pure ())) "live daemon was accepted"
  IO.FS.removeFile (data / "sessions/pending/daemon.json")
  check (!StudyHistory.keeps "queries" && !StudyHistory.keeps "../events" && !StudyHistory.keeps "shared")
    "private family scope widened"
  mark (root / "common/private/usage") "changed-frozen-feedback"
  check (← rejected (do let _ ← StudyHistory.verify manifest; pure ())) "mutated common learning was accepted"
  IO.FS.writeFile (root / "result.json") ((Json.mkObj [
    ("identicalSourceAndPrivateInputs",toJson true),("independentWritableArms",toJson true),
    ("protectedSourceUnchanged",toJson true),("transientStateExcluded",toJson true),
    ("changedAndLiveInputsRejected",toJson true),("answeringModelCalls",toJson (0 : Nat))]).compress ++ "\n")

end Eggshell.Research.StudyHistoryChecks
