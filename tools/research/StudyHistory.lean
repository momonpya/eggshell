import tools.research.StudyAdmission

open Lean Eggshell

namespace Eggshell.Research.StudyHistory

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Classifier names bind the complete implementation content address. -/
structure FeedbackFamily (name : String) where
  classifier : String
  bound : name = "usage-" ++ classifier
  valid : Synapses.digest classifier = true

def feedbackFamily? (name : String) : Option (FeedbackFamily name) :=
  let classifier := (name.drop 6).toString
  if checked : name = "usage-" ++ classifier ∧ Synapses.digest classifier = true then
    some ⟨classifier,checked.1,checked.2⟩
  else none

/-- Carry events and checked private feedback, not session delivery state,
question vectors, daemon routes or shared indexes. -/
def keeps (name : String) : Bool := name == "events" || (feedbackFamily? name).isSome

theorem keeps_events : keeps "events" = true := rfl
theorem kept_family (name : String) (h : keeps name = true) :
    name = "events" ∨ Nonempty (FeedbackFamily name) := by
  simp only [keeps, Bool.or_eq_true, beq_iff_eq] at h
  rcases h with events | feedback
  · exact Or.inl events
  · cases found : feedbackFamily? name with
    | none => simp [found] at feedback
    | some family => exact Or.inr ⟨family⟩

theorem feedback_family_is_content_addressed (family : FeedbackFamily name) :
    name = "usage-" ++ family.classifier ∧ Synapses.digest family.classifier = true :=
  ⟨family.bound,family.valid⟩

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

private def validatePrivate (source : DB.PageMap.Snapshot) (name : String) (path : System.FilePath) : IO Unit := do
  check (keeps name) "only durable events and usage belong to the common history"
  let snapshot ← DB.PageMap.pin path
  if name == "events" then
    check (snapshot.head.authority == "private-synaptic-events:" ++ source.head.identity)
      "private journal belongs to another database or scope"
  else
    let some family := feedbackFamily? name | throw (IO.userError "invalid private classifier family")
    check (snapshot.head.authority == "advisory-usage:" ++ source.head.identity ++ ":" ++ family.classifier &&
      (← snapshot.get "classifier") == some family.classifier.toUTF8)
      "private feedback classifier or authority differs from its family"
    let some manifest ← Synapses.Index.manifest? snapshot | throw (IO.userError "private feedback has no manifest")
    check (manifest.scope == .usage && manifest.source.identity == source.head.identity &&
      manifest.source.authority == source.head.authority && Synapses.digest manifest.implementation)
      "private feedback belongs to another database, authority or scope"

private def newRoot (source data target : System.FilePath) : IO Unit := do
  check (source.isAbsolute && data.isAbsolute && target.isAbsolute && !(← target.pathExists))
    "absolute inputs and a new history output required"
  FileSystem.rejectSymlinkAncestors target
  check (!(StudyRuntime.inside source target) && !(StudyRuntime.inside data target) &&
    !(StudyRuntime.inside target source) && !(StudyRuntime.inside target data))
    "history output overlaps its protected input"
  FileSystem.privateDirectory target

private def familyNames (root : System.FilePath) : IO (Array String) := do
  if !(← root.pathExists) then return #[]
  return ((← root.readDir).map (·.fileName)).filter keeps |>.qsort (· < ·)

/-- A common input contains the same source publication and private learning
for both arms. Derived vectors and session state are prepared separately. -/
def freeze (source data target : System.FilePath) : IO Snapshot := do
  requireQuiescent data
  newRoot source data target
  let sourceHead ← DB.PageMap.pin source
  let sourceFiles ← StudyRuntime.checkpoint source (target / "source.egg")
  let privateRoot := data / "read-cache" / sourceHead.head.identity / "synapses"
  let mut privateFamilies := #[]
  for name in ← familyNames privateRoot do
    let path := privateRoot / name
    validatePrivate sourceHead name path
    let files ← StudyRuntime.checkpoint path (target / "private" / name)
    privateFamilies := privateFamilies.push ⟨name,files⟩
  requireQuiescent data
  check ((← familyNames privateRoot) == privateFamilies.map (·.name))
    "private feedback family set changed during history freeze"
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
  check ((← familyNames (root / "private")) == snapshot.privateFamilies.map (·.name))
    "common history has unlisted or missing private feedback"
  for family in snapshot.privateFamilies do
    validatePrivate source family.name (root / "private" / family.name)
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
