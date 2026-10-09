module

public import Eggshell.SourceEvidence
public import Eggshell.DB.Wire

@[expose] public section
namespace Eggshell.SourceObservation
open Lean SourceEvidence

/-- An explicit patch path registers a local file; it is not a write or
freshness assertion. Arbitrary programs need no command-name classification. -/
def patchPaths? (patch : String) : Option (List String) := do
  let lines := patch.trimAscii.toString.splitOn "\n"
  if lines.head? != some "*** Begin Patch" || lines.getLast? != some "*** End Patch" then return ← none
  let mut paths := []
  for line in lines.tail.dropLast do
    for header in ["*** Add File: ", "*** Delete File: ", "*** Update File: ", "*** Move to: "] do
      if line.startsWith header then
        let path := (line.drop header.length).copy
        if path.isEmpty then return ← none
        paths := path :: paths
  if paths.isEmpty then none else some paths.reverse.eraseDups

def targets (workspace : System.FilePath) (name : String) (input : Json) : List String := Id.run do
  let paths := if ["apply_patch", "functions.apply_patch"].contains name then
      ((input.getStr?.toOption.orElse fun _ => (input.getObjValAs? String "patch").toOption
        |>.orElse fun _ => (input.getObjValAs? String "input").toOption).bind patchPaths?).getD []
    else if ["Write", "Edit", "Read", "read_file"].contains name then pathsFromInput input
    else if ["Bash", "bash", "shell", "exec_command", "functions.exec_command"].contains name then
      (((input.getObjValAs? String "cmd").toOption.orElse fun _ =>
        (input.getObjValAs? String "command").toOption).bind commandFiles?).getD []
    else []
  let some directory := inputDirectory? workspace input | return []
  return paths.filterMap fun path =>
    if isURI path then none else (relative? workspace directory path).map (·.text)

structure Span where
  offset : Nat
  bytes : Nat
  deriving Repr, ToJson, FromJson

def size (spans : List Span) : Nat := (spans.map (·.bytes)).sum

def add (limit : Nat) (spans : List Span) (span : Span) : List Span :=
  if spans.any (·.offset == span.offset) then spans
  else if size spans + span.bytes ≤ limit then spans ++ [span]
  else spans

theorem add_bounded (limit : Nat) (spans : List Span) (span : Span)
    (bounded : size spans ≤ limit) : size (add limit spans span) ≤ limit := by
  unfold add
  split
  · exact bounded
  · split
    · rename_i fits
      simpa [size, List.map_append, List.sum_append] using fits
    · exact bounded

structure Chunk where
  offset : Nat
  bytes : ByteArray

structure Window (limit : Nat) where
  chunks : List Chunk
  bounded : (chunks.map (·.bytes.size)).sum ≤ limit

structure Observation (limit : Nat) where
  before : Option File
  capture : SourceEvidence.Capture
  verified : capture.record.valid = true
  files_match : capture.record.files = capture.probes.map (·.file)
  window : Window limit
  changedPages : Nat

theorem observation_bytes_bounded (observation : Observation limit) :
    (observation.window.chunks.map (·.bytes.size)).sum ≤ limit := observation.window.bounded

theorem observation_certificate_bound (observation : Observation limit) :
    observation.capture.record.valid = true ∧
      observation.capture.record.files = observation.capture.probes.map (·.file) :=
  ⟨observation.verified, observation.files_match⟩

/-- This is a disposable observation index, not a saved tool/result or source
certificate. Page hashes occupy 64 bytes per 4096 source bytes. -/
structure Snapshot where
  file : File
  stamp : Option String
  bank : String
  deriving ToJson, FromJson, BEq

/-- A small resumable scan cursor. It stores references to source ranges,
never copies their bodies or the growing page-hash bank on each checkpoint. -/
structure Cursor where
  version : FileSystem.ReadVersion
  offset : Nat := 0
  root : String
  changes : List Span := []
  context : List Span := []
  changedPages : Nat := 0
  includeNext : Bool := false
  bank : String
  deriving ToJson, FromJson

structure Entry where
  relative : String
  expected : Option File := none
  snapshot : Option Snapshot := none
  cursor : Option Cursor := none
  deriving ToJson, FromJson

def pageHash (page : ByteArray) : String :=
  Blake3.hex (Blake3.digest "eggshell.observation.page".toUTF8 [page])

def key (workspace : System.FilePath) (relative : String) : String :=
  Blake3.hex (Blake3.digest "eggshell.observation.index".toUTF8
    [workspace.normalize.toString.toUTF8, relative.toUTF8])

def directory (root workspace : System.FilePath) : System.FilePath :=
  root / "observed-files" / key workspace ""

def entryPath (root workspace : System.FilePath) (relative : String) : System.FilePath :=
  directory root workspace / (key workspace relative ++ ".json")

def readJson [FromJson α] (path : System.FilePath) : IO (Option α) := do
  if !(← path.pathExists) then return none
  let value ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson? (α := α))
  pure (some value)

def writeJson [ToJson α] (path : System.FilePath) (value : α) : IO Unit := do
  if let some parent := path.parent then FileSystem.durableDirectory parent
  FileSystem.atomicBytes path (toJson value |>.compress |>.toUTF8)

def register (root workspace : System.FilePath) (file : File) : IO Unit := do
  let some relative := Relative.check? file.relative | return
  let path := entryPath root workspace relative.text
  -- Register once. An old handoff cannot roll the observation index back.
  if ← path.pathExists then return
  let admissible ← try
    let _ ← FileSystem.regularMetadata? (workspace / relative.text)
    pure true
    catch _ => pure false
  unless admissible do return
  if let some parent := path.parent then FileSystem.durableDirectory parent
  let entry : Entry := ⟨relative.text, some file, none, none⟩
  FileSystem.immutableBytes path (toJson entry |>.compress |>.toUTF8)

def entries (root workspace : System.FilePath) : IO (List System.FilePath) := do
  let folder := directory root workspace
  if !(← folder.pathExists) then return []
  return (← folder.readDir).toList.filterMap fun item =>
    if item.fileName.endsWith ".json" then some item.path else none

def bankDirectory (path : System.FilePath) : System.FilePath :=
  path.parent.getD "." / (path.fileName.getD "observation" ++ ".pages")

def bankPath? (folder : System.FilePath) (name : String) : Option System.FilePath :=
  if name == "a" || name == "b" then
    some (folder / (name ++ ".pages")) else none

def validCursor (limit : Nat) (cursor : Cursor) : Bool :=
  cursor.offset ≤ cursor.version.bytes &&
  (cursor.offset % 4096 == 0 || cursor.offset == cursor.version.bytes) &&
  size cursor.changes ≤ limit && size cursor.context ≤ limit &&
  (cursor.changes ++ cursor.context).all (fun span =>
    span.bytes ≤ 4096 && span.offset + span.bytes ≤ cursor.version.bytes)

def nextBank (current : Option String) : String := if current == some "a" then "b" else "a"

theorem bank_storage_bounded (current : Option String) :
    nextBank current = "a" ∨ nextBank current = "b" := by
  unfold nextBank
  split <;> simp_all

/-- Two disposable hash banks per related file: the last completed scan and
the pending scan. Restarting a changed version resets only the pending bank. -/
def initial (folder : System.FilePath) (version : FileSystem.ReadVersion)
    (current : Option String) : IO Cursor := do
  FileSystem.durableDirectory folder
  let bank := nextBank current
  let path := folder / (bank ++ ".pages")
  FileSystem.atomicBytes path ByteArray.empty
  let root := Blake3.hex (Blake3.digest "eggshell.source.file".toUTF8 [Blake3.u64le version.bytes])
  pure {version := version, root := root, bank := bank}

inductive Step (limit : Nat) where
  | pending
  | unverified
  | complete (snapshot : Snapshot) (observation : Option (Observation limit))

def Step.finished : Step limit → Bool
  | .pending => false
  | .unverified => true
  | .complete .. => true

theorem pending_is_not_complete : (Step.pending : Step limit).finished = false := rfl

def Step.observation? : Step limit → Option (Observation limit)
  | .complete _ observation => observation
  | _ => none

theorem unverified_emits_no_evidence : (Step.unverified : Step limit).observation? = none := rfl

def chunks (handle : FileSystem.ReadHandle) (spans : List Span) (limit : Nat) :
    IO (Window limit) := do
  let mut chunks : List Chunk := []
  for span in spans do
    if bound : span.bytes ≤ 4096 then
      let bytes ← FileSystem.readPage handle span.offset.toUInt64 ⟨span.bytes, bound⟩
      unless bytes.size == span.bytes do throw (IO.userError "short observation window")
      chunks := chunks ++ [⟨span.offset, bytes⟩]
    else throw (IO.userError "invalid observation range")
  if bounded : (chunks.map (·.bytes.size)).sum ≤ limit then return ⟨chunks, bounded⟩
  else throw (IO.userError "observation window exceeds budget")

def finish (workspace : System.FilePath) (before : Option File) (snapshot : Snapshot)
    (window : Window limit) (changed : Nat) (deadline : Nat) : IO (Step limit) := do
  let probe : Probe := ⟨snapshot.file, snapshot.stamp⟩
  if (← checkedProbeFile workspace (some probe) deadline).isNone then return .pending
  if before == some snapshot.file then return .complete snapshot none
  let record : Record := ⟨workspace.fileName.getD workspace.toString, [snapshot.file], [], true⟩
  let capture : SourceEvidence.Capture := ⟨record, [probe]⟩
  if verified : record.valid = true then
    return .complete snapshot (some ⟨before, capture, verified, rfl, window, changed⟩)
  return .pending

/-- A bounded amount of work per visit. Append page hashes, sync them, then
publish the cursor. After interruption the uncommitted hash tail is truncated.
An incomplete visit never emits evidence or advances the completed index. -/
def step (path workspace : System.FilePath) (limit maxPages deadline : Nat) : IO (Step limit) := do
  let some entry ← (readJson path : IO (Option Entry)) | return .pending
  let some relative := Relative.check? entry.relative | return .pending
  let before := entry.snapshot.map (·.file) |>.orElse fun _ => entry.expected
  let actual := workspace / relative.text
  if (← IO.monoMsNow) ≥ deadline then return .pending
  let folder := bankDirectory path
  let metadata ← try
    pure (.ok (← FileSystem.regularMetadata? actual) : Except IO.Error (Option IO.FS.Metadata))
    catch error => pure (.error error)
  -- A directory, symlink or inaccessible path is not a file observation.
  -- It cannot authorize absence and cannot hold a committed native result's
  -- queue entry forever. The registered path is retried on the next request.
  let .ok metadata := metadata | return .unverified
  if metadata.isNone then
    return ← finish workspace before ⟨⟨relative.text, none⟩, none, ""⟩ ⟨[], Nat.zero_le _⟩ 0 deadline
  let handle ← FileSystem.openRead actual.toString
  let version ← FileSystem.readVersion handle
  -- A matching stamp is only a background scheduling optimization. Reuse
  -- authority continues to require SourceEvidence's actual content check.
  if let some old := entry.snapshot then
    if old.stamp == some version.stamp && old.file.content.isSome then return .complete old none
  let cursor ← match entry.cursor with
    | some cursor =>
        if cursor.version == version && validCursor limit cursor then pure cursor
        else initial folder version (entry.snapshot.map (·.bank))
    | none => initial folder version (entry.snapshot.map (·.bank))
  let some bank := bankPath? folder cursor.bank | return .pending
  let writer ← FileSystem.openAppend bank.toString
  let size ← FileSystem.readVersion (← FileSystem.openRead bank.toString)
  let committed := (cursor.offset + 4095) / 4096 * 64
  if size.bytes < committed then throw (IO.userError "observation cursor lost committed page hashes")
  if size.bytes > committed then
    FileSystem.truncateAppend writer size.bytes.toUInt64 committed.toUInt64
  let oldBank ← entry.snapshot.filter (fun old => !old.bank.isEmpty) |>.mapM fun old => do
    let some oldPath := bankPath? folder old.bank | throw (IO.userError "invalid observation index")
    FileSystem.openRead oldPath.toString
  let mut cursor := cursor
  let rootBytes := ByteArray.mk (← IO.ofExcept (DB.Wire.fromHex cursor.root)).toArray
  let checkedRoot ← if valid : rootBytes.size = 32 then pure (⟨rootBytes, valid⟩ : Root)
    else throw (IO.userError "invalid observation digest")
  let mut root := checkedRoot
  let mut visited := 0
  let mut written := committed
  while cursor.offset < version.bytes && visited < maxPages && (← IO.monoMsNow) < deadline do
    let offset := cursor.offset
    let count := min 4096 (version.bytes - offset)
    let page ← FileSystem.readPage handle offset.toUInt64 ⟨count, Nat.min_le_left _ _⟩
    if page.size != count then return .pending
    root := stepRoot root page
    let hash := pageHash page
    let oldHash ← match oldBank with
      | none => pure none
      | some old =>
          let bytes ← FileSystem.readPage old (offset / 4096 * 64).toUInt64 ⟨64, by decide⟩
          pure (String.fromUTF8? bytes)
    let shortened := offset + count == version.bytes && before.any
      (fun old => old.content.any (fun content => content.bytes > version.bytes))
    let changed := oldHash != some hash || shortened
    let span : Span := ⟨offset, count⟩
    if changed then
      cursor := {cursor with changes := add limit cursor.changes span, changedPages := cursor.changedPages + 1}
      if offset ≥ 4096 then
        cursor := {cursor with context := add limit cursor.context ⟨offset - 4096, 4096⟩}
    else if cursor.includeNext then cursor := {cursor with context := add limit cursor.context span}
    FileSystem.appendAt writer written.toUInt64 hash.toUTF8
    written := written + 64
    cursor := {cursor with offset := offset + count, root := Blake3.hex root.val, includeNext := changed}
    visited := visited + 1
  FileSystem.syncAppend writer
  FileSystem.closeAppend writer
  let after ← FileSystem.readVersion handle
  let current ← FileSystem.readVersion (← FileSystem.openRead actual.toString)
  if after != version || current != version then
    writeJson path {entry with cursor := none}
    return .pending
  writeJson path {entry with cursor := some cursor}
  if cursor.offset != version.bytes then return .pending
  let selected := cursor.context.foldl (add limit) cursor.changes
  let window ← chunks handle selected limit
  let snapshot : Snapshot := ⟨⟨relative.text, some ⟨version.bytes, cursor.root⟩⟩,
    some version.stamp, cursor.bank⟩
  finish workspace before snapshot window cursor.changedPages deadline

/-- Only after the immutable observation is queued may this disposable index
advance. Updating this pointer does not mutate any previous evidence. -/
def acknowledge (path : System.FilePath) (snapshot : Snapshot) : IO Unit := do
  let some entry ← (readJson path : IO (Option Entry)) | throw (IO.userError "observation index disappeared")
  if entry.snapshot == some snapshot && entry.cursor.isNone then return
  writeJson path {entry with snapshot := some snapshot, cursor := none}

def observationJson (observation : Observation limit) : Json := Json.mkObj [
  ("kind", toJson "observed filesystem state; not attributed to a tool or a successful write"),
  ("previous", toJson observation.before), ("current", toJson observation.capture.record.files),
  ("retained_bytes", toJson (observation.window.chunks.map (·.bytes.size)).sum),
  ("different_or_unconfirmed_pages", toJson observation.changedPages),
  ("coverage", toJson "retained changed ranges and adjacent context; omitted ranges are not evidence"),
  ("chunks", toJson (observation.window.chunks.map fun chunk => Json.mkObj [
    ("byte_offset", toJson chunk.offset), ("byte_length", toJson chunk.bytes.size),
    ("encoding", toJson (if (String.fromUTF8? chunk.bytes).isSome then "utf8" else "hex")),
    ("content", toJson ((String.fromUTF8? chunk.bytes).getD (Blake3.hex chunk.bytes)))]))]

theorem changed_dependencies_are_historical (old : Record) (current : List File)
    (changed : current ≠ old.files) : check? old current = none :=
  changed_dependency_rejected old current changed

/-- The source reader and resumable observer use the same typed digest
transition. Splitting the ordered pages into visits preserves that result. -/
theorem resumed_digest_exact (root : Root) (first rest : List ByteArray) :
    (first ++ rest).foldl stepRoot root = rest.foldl stepRoot (first.foldl stepRoot root) :=
  List.foldl_append

theorem dependent_result_requires_old_content (records : List Record) (ledger : Ledger)
    (old : Record) (present : old ∈ records) (current : List File)
    (observed : currentFiles? ledger old.files = some current)
    (changed : current ≠ old.files) : authorize? records ledger = none := by
  unfold authorize?
  split
  · rename_i accepted
    have agreement := List.all_eq_true.mp (Bool.and_eq_true_iff.mp accepted).2 old present
    simp [recordAgrees, observed, agrees, changed] at agreement
  · rfl

end Eggshell.SourceObservation
