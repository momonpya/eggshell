import tools.research.StudyAdmission

open Lean Eggshell

namespace Eggshell.Research.StudyHistory

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Carry durable synaptic observations and feedback, rather than session
delivery state, queries, cache ownership routes or daemon registrations. -/
def keeps (name : String) : Bool := name == "events" || name == "usage"

theorem keeps_events : keeps "events" = true := rfl
theorem keeps_usage : keeps "usage" = true := rfl
theorem kept_family (name : String) (h : keeps name = true) :
    name = "events" ∨ name = "usage" := by
  simpa [keeps, Bool.or_eq_true, beq_iff_eq] using h

structure Private where
  name : String
  files : Array (String × String)
  deriving FromJson, ToJson

structure Snapshot where
  database : String
  sourceFiles : Array (String × String)
  privateFamilies : Array Private
  deriving FromJson, ToJson

private def save (path : System.FilePath) (value : Json) : IO Unit := do
  check (!(← path.pathExists)) "keep the existing history evidence"
  IO.FS.writeFile path (value.compress ++ "\n")

private def requireQuiescent (data : System.FilePath) : IO Unit := do
  -- This also rejects symlinks and a live daemon endpoint anywhere in data.
  let _ ← StudyAdmission.tree data
  let sessions := data / "sessions"
  if !(← sessions.pathExists) then return
  for session in ← sessions.readDir do
    check ((← session.path.symlinkMetadata).type == .dir) "invalid session history"
    for lane in #["checkpoints", "deferred"] do
      let directory := session.path / lane
      if !(← directory.pathExists) then continue
      check (!(← directory.readDir).any (·.fileName.endsWith ".json"))
        "drain durable source saves before freezing history"

private def validatePrivate (database name : String) (path : System.FilePath) : IO Unit := do
  check (keeps name) "only durable events and usage belong to the common history"
  let snapshot ← DB.PageMap.pin path
  let authority := if name == "events" then "private-synaptic-events:" ++ database
    else "advisory:" ++ database ++ ":usage"
  check (snapshot.head.authority == authority) "private history belongs to another database or scope"

private def newRoot (source data target : System.FilePath) : IO Unit := do
  check (source.isAbsolute && data.isAbsolute && target.isAbsolute && !(← target.pathExists))
    "absolute inputs and a new history output required"
  FileSystem.rejectSymlinkAncestors target
  check (!(StudyRuntime.inside source target) && !(StudyRuntime.inside data target) &&
    !(StudyRuntime.inside target source) && !(StudyRuntime.inside target data))
    "history output overlaps its protected input"
  FileSystem.privateDirectory target

/-- A common input contains the same source publication and private learning
for both arms. Derived vectors and session state are prepared separately. -/
def freeze (source data target : System.FilePath) : IO Snapshot := do
  requireQuiescent data
  newRoot source data target
  let sourceHead ← DB.PageMap.pin source
  let sourceFiles ← StudyRuntime.checkpoint source (target / "source.egg")
  let privateRoot := data / "read-cache" / sourceHead.head.identity / "synapses"
  let mut privateFamilies := #[]
  for name in #["events", "usage"] do
    let path := privateRoot / name
    if !(← path.pathExists) then continue
    validatePrivate sourceHead.head.identity name path
    let files ← StudyRuntime.checkpoint path (target / "private" / name)
    privateFamilies := privateFamilies.push ⟨name,files⟩
  requireQuiescent data
  check ((← StudyRuntime.files source) == sourceFiles) "common source changed during history freeze"
  for family in privateFamilies do
    check ((← StudyRuntime.files (privateRoot / family.name)) == family.files)
      "private learning changed during history freeze"
  let snapshot : Snapshot := ⟨sourceHead.head.identity, sourceFiles, privateFamilies⟩
  save (target / "history.json") (toJson snapshot)
  return snapshot

def verify (manifest : StudyAdmission.Artifact) : IO (System.FilePath × Snapshot) := do
  StudyAdmission.verifyArtifact manifest
  let path := System.FilePath.mk manifest.path
  let some root := path.parent | throw (IO.userError "history manifest has no parent")
  let snapshot ← IO.ofExcept (fromJson? (α := Snapshot) (← StudyAdmission.readJson manifest.path))
  let source ← DB.PageMap.pin (root / "source.egg")
  check (source.head.identity == snapshot.database &&
    (← StudyRuntime.files source.directory) == snapshot.sourceFiles) "common source checkpoint changed"
  check ((snapshot.privateFamilies.map (·.name)).toList.eraseDups.length == snapshot.privateFamilies.size)
    "duplicate private history family"
  for family in snapshot.privateFamilies do
    validatePrivate snapshot.database family.name (root / "private" / family.name)
    check ((← StudyRuntime.files (root / "private" / family.name)) == family.files)
      "common private learning changed"
  return (root, snapshot)

/-- Fork only from the sealed common input. Each arm gets private writable
copies with identical bytes, never the other arm's measured output. -/
def fork (manifest : StudyAdmission.Artifact) (target : System.FilePath) : IO Snapshot := do
  let (root, snapshot) ← verify manifest
  newRoot root root target
  let _ ← StudyRuntime.checkpoint (root / "source.egg") (target / "work.egg")
  FileSystem.privateDirectory (target / "data")
  for family in snapshot.privateFamilies do
    let destination := target / "data/read-cache" / snapshot.database / "synapses" / family.name
    let _ ← StudyRuntime.checkpoint (root / "private" / family.name) destination
    pure ()
  let _ ← verify manifest
  save (target / "history-input.json") (Json.mkObj [
    ("manifest",toJson manifest),("snapshot",toJson snapshot),
    ("sessionStateCopied",toJson false),("derivedVectorsCopied",toJson false),
    ("answeringModelCalls",toJson (0 : Nat))])
  return snapshot

def cliMain (args : List String) : IO Unit := do
  match args with
  | ["freeze", source, data, target] =>
    let _ ← freeze (.mk source) (.mk data) (.mk target)
    pure ()
  | ["fork", manifest, digest, target] =>
    let _ ← fork ⟨manifest,digest⟩ (.mk target)
    pure ()
  | _ => throw (IO.userError "StudyHistory freeze SOURCE DATA NEW-ROOT | fork MANIFEST SHA256 NEW-ROOT")

end Eggshell.Research.StudyHistory
