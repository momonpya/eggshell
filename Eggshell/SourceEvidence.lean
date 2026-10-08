module

public import Eggshell.FileSystem
public import Eggshell.Blake3
public import Eggshell.Relation
public import Lean.Data.Json.FromToJson
public import Lean.Data.Json.Parser

@[expose] public section

namespace Eggshell.SourceEvidence
open Lean

/-- A portable locator is relative to the current workspace. The producing
workspace's absolute name is not an identity or permission to read elsewhere. -/
def safeRelative (path : String) : Bool :=
  !path.isEmpty && !path.startsWith "/" && !path.contains '\x00' &&
    (path.splitOn "/").all (fun part =>
      !part.isEmpty && part != "." && part != "..")

structure Relative where
  text : String
  safe : safeRelative text = true

def Relative.check? (path : String) : Option Relative :=
  if safe : safeRelative path = true then some ⟨path, safe⟩ else none

theorem relative_cannot_escape (path : Relative) :
    (path.text.splitOn "/").all (fun part => part != "..") = true := by
  have parts := path.safe
  simp only [safeRelative, Bool.and_eq_true] at parts
  apply List.all_eq_true.mpr
  intro part member
  have valid := List.all_eq_true.mp parts.2 part member
  simpa only [Bool.and_eq_true] using (Bool.and_eq_true_iff.mp valid).2

def withoutDots (path : String) : String :=
  (if path.startsWith "/" then "/" else "") ++
    "/".intercalate ((path.splitOn "/").filter (fun part => !part.isEmpty && part != "."))

def relative? (workspace directory : System.FilePath) (path : String) : Option Relative := do
  if path.isEmpty || path.contains '\x00' then none else do
    let workspace := withoutDots workspace.normalize.toString
    let actual := withoutDots (directory / System.FilePath.mk path).normalize.toString
    let basePrefix := if workspace.endsWith "/" then workspace else workspace ++ "/"
    if !actual.startsWith basePrefix then none else
      Relative.check? ((actual.drop basePrefix.length).copy)

structure Fingerprint where
  bytes : Nat
  root : String
  deriving Repr, DecidableEq, BEq, ToJson, FromJson

structure File where
  relative : String
  content : Option Fingerprint
  deriving Repr, DecidableEq, BEq, ToJson, FromJson

structure Record where
  workspace : String
  files : List File
  uris : List String := []
  complete : Bool
  deriving Repr, DecidableEq, ToJson, FromJson

instance : BEq Record := ⟨fun left right => decide (left = right)⟩
instance : LawfulBEq Record where
  rfl := by intro record; simp [BEq.beq]
  eq_of_beq := by intro left right equal; exact of_decide_eq_true equal

def Record.valid (record : Record) : Bool :=
  record.complete && record.uris.isEmpty && !record.files.isEmpty &&
    decide ((record.files.map (·.relative)).Nodup) &&
    record.files.all (fun file => safeRelative file.relative &&
      file.content.all (fun content => content.root.length == 64 &&
        content.root.toList.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f'))))

/-- Freshness authorizes only exact currently observed dependency descriptors.
It does not assert collision freedom or prove a provider's external behavior. -/
def agrees (record : Record) (current : List File) : Bool :=
  record.valid && decide (current = record.files)

structure Checked (record : Record) (current : List File) : Type where
  valid : record.valid = true
  exact : current = record.files

def check? (record : Record) (current : List File) : Option (Checked record current) :=
  if accepted : agrees record current = true then
    some ⟨(Bool.and_eq_true_iff.mp accepted).1,
      of_decide_eq_true (Bool.and_eq_true_iff.mp accepted).2⟩
  else none

theorem checked_dependencies_exact (checked : Checked record current) :
    current = record.files := checked.exact

theorem changed_dependency_rejected (record : Record) (current : List File)
    (changed : current ≠ record.files) : check? record current = none := by
  simp [check?, agrees, changed]

theorem incomplete_record_rejected (record : Record) (current : List File)
    (incomplete : record.complete = false) : check? record current = none := by
  simp [check?, agrees, Record.valid, incomplete]

/-- Workspace names are display provenance. Relocation changes neither the
relative dependency keys nor the contents which the receiving machine checks. -/
theorem relocated_record_agreement (record : Record) (current : List File) (name : String) :
    agrees {record with workspace := name} current = agrees record current := rfl

structure Probe where
  file : File
  stamp : Option String
  deriving Repr, ToJson, FromJson

structure Capture where
  record : Record
  probes : List Probe
  deriving Repr, ToJson, FromJson

def pageRoot (previous page : ByteArray) : ByteArray :=
  Blake3.digest "eggshell.source.page".toUTF8 [previous, page]

theorem page_root_size (previous page : ByteArray) : (pageRoot previous page).size = 32 := by
  exact Blake3.hashSegments_size _

abbrev Root := {bytes : ByteArray // bytes.size = 32}

def stepRoot (previous : Root) (page : ByteArray) : Root :=
  ⟨pageRoot previous.val page, page_root_size _ _⟩

/-- The scanner holds a single bounded native page, a digest and counters.
The chain commits page order and file length. It is a content fingerprint,
not an assertion that equal finite hashes imply equal arbitrary files. -/
def fingerprint (path : System.FilePath) (deadline : Nat) : IO (Option (Fingerprint × String)) := do
  if (← IO.monoMsNow) ≥ deadline then return none
  let handle ← FileSystem.openRead path.toString
  let before ← FileSystem.readVersion handle
  let mut offset := 0
  let mut root : Root := ⟨Blake3.digest "eggshell.source.file".toUTF8 [Blake3.u64le before.bytes],
    Blake3.hashSegments_size _⟩
  while offset < before.bytes do
    if (← IO.monoMsNow) ≥ deadline then return none
    let count := min 4096 (before.bytes - offset)
    let page ← FileSystem.readPage handle offset.toUInt64 ⟨count, Nat.min_le_left _ _⟩
    if page.size != count then return none
    root := stepRoot root page
    offset := offset + count
  let after ← FileSystem.readVersion handle
  let current ← FileSystem.readVersion (← FileSystem.openRead path.toString)
  if (← IO.monoMsNow) ≥ deadline then return none
  if !FileSystem.stableRead before after current offset then return none
  pure (some (⟨before.bytes, Blake3.hex root.val⟩, before.stamp))

def probe (workspace : System.FilePath) (relative : Relative) (deadline : Nat) : IO (Option Probe) := do
  if (← IO.monoMsNow) ≥ deadline then return none
  let path := workspace / relative.text
  try
    FileSystem.rejectSymlinkAncestors path
    match ← FileSystem.regularMetadata? path with
    | none => pure (some ⟨⟨relative.text, none⟩, none⟩)
    | some _ =>
        pure ((← fingerprint path deadline).map fun (content, stamp) =>
          ⟨⟨relative.text, some content⟩, some stamp⟩)
  catch _ => pure none -- inaccessible, symlink or interrupted is unverified, never absent

def stillCurrent (workspace : System.FilePath) (probe : Probe) : IO Bool := do
  let some relative := Relative.check? probe.file.relative | return false
  let path := workspace / relative.text
  try
    FileSystem.rejectSymlinkAncestors path
    match probe.stamp, ← FileSystem.regularMetadata? path with
    | none, none => pure true
    | some expected, some _ => pure ((← FileSystem.readVersion
        (← FileSystem.openRead path.toString)).stamp == expected)
    | _, _ => pure false
  catch _ => pure false

/-- Recheck the version after all related fingerprints have been collected.
The OS version checks are observations, not an atomic filesystem snapshot. -/
def checkedProbeFile (workspace : System.FilePath) (observed : Option Probe)
    (deadline : Nat) : IO (Option File) := do
  let some observed := observed | return none
  if (← IO.monoMsNow) ≥ deadline then return none
  unless ← stillCurrent workspace observed do return none
  if (← IO.monoMsNow) ≥ deadline then return none
  pure (some observed.file)

/-- Observe precisely the declared files. There is no workspace scan, Git
dependency, remote request, persistent negative cache or hard file-count cap. -/
def observe (workspace : System.FilePath) (files : List File) (deadline : Nat) :
    IO (Option (List File)) := do
  let mut observations := []
  for file in files do
    let some relative := Relative.check? file.relative | return none
    let some observed ← probe workspace relative deadline | return none
    observations := observed :: observations
  let mut files := []
  for observed in observations.reverse do
    let some file ← checkedProbeFile workspace (some observed) deadline | return none
    files := file :: files
  pure (some files.reverse)

def verify (workspace : System.FilePath) (record : Record) (deadline : Nat) : IO Bool := do
  if !record.valid then return false
  let some current ← observe workspace record.files deadline | return false
  pure ((check? record current).isSome)

def unknown (workspace : System.FilePath) (uris : List String := []) : Capture :=
  ⟨⟨workspace.fileName.getD workspace.toString, [], uris, false⟩, []⟩

/-- Only explicitly named local files are captured. Unrecognized shell syntax,
directory searches and remote providers remain historical evidence. -/
def pathsFromInput (input : Json) : List String :=
  ["path", "file_path", "filename", "file"].filterMap fun key =>
    (input.getObjValAs? String key).toOption

def urisFromInput (input : Json) : List String :=
  ["url", "uri"].filterMap fun key => (input.getObjValAs? String key).toOption

def isURI (path : String) : Bool := (path.splitOn "://").length > 1

/-- A deliberately literal single-command grammar. Expansion, redirection,
subcommands and pipelines cannot be guessed into a complete dependency list. -/
def literalWords? (text : String) : Option (List String) := do
  if text.contains '\x00' then return ← none
  let mut words := []
  let mut word := ""
  let mut quote := (0 : Nat)
  let mut started := false
  for c in text.toList do
    if quote == 1 then
      if c == '\'' then quote := 0 else word := word.push c
    else if quote == 2 then
      if c == '"' then quote := 0
      else if c == '$' || c == '`' || c == '\\' then return ← none
      else word := word.push c
    else if c == '\'' then
      quote := 1
      started := true
    else if c == '"' then
      quote := 2
      started := true
    else if c == '\n' || c == '\r' then return ← none
    else if c.isWhitespace then
      if started then words := word :: words
      word := ""
      started := false
    else if ['$', '`', '\\', ';', '|', '&', '<', '>', '*', '?', '[', ']', '(', ')', '{', '}'].contains c then
      return ← none
    else
      word := word.push c
      started := true
  if quote != 0 then return ← none
  if started then words := word :: words
  pure words.reverse

def printProgram (program : String) : Bool :=
  (program.splitOn ";").all fun range =>
    range.endsWith "p" && !(range.dropEnd 1).isEmpty &&
      ((range.dropEnd 1).copy.toList).all (fun c => c.isDigit || c == ',' || c == '$')

/-- A stream filter has no file operand. Programs which read/write another
file, execute a command or substitute shell expressions cannot inhabit this
plan. The external command/OS observation remains outside this pure contract. -/
inductive StreamFilter where
  | print (program : String) (literal : printProgram program = true)
  | prefix (lines : Nat)

def streamFilter? (words : List String) : Option StreamFilter := do
  match words with
  | ["sed", "-n", program] =>
      if literal : printProgram program = true then some (.print program literal) else none
  | ["head", "-n", count] => count.toNat? |>.map StreamFilter.prefix
  | ["head", count] =>
      if count.startsWith "-" then
        ((count.drop 1).copy.toNat?).map StreamFilter.prefix else none
  | _ => none

/-- Split only unquoted pipes. Each segment is subsequently accepted by the
same literal-word parser; substitutions, redirects, sequences and unknown
filters are rejected rather than guessed into complete dependencies. -/
def pipelineSegments? (command : String) : Option (List String) := do
  let mut parts := []
  let mut part := ""
  let mut quote := (0 : Nat)
  for c in command.toList do
    if quote == 0 && c == '|' then
      parts := part :: parts
      part := ""
    else
      part := part.push c
      if quote == 1 then
        if c == '\'' then quote := 0
      else if quote == 2 then
        if c == '"' then quote := 0
      else if c == '\'' then quote := 1
      else if c == '"' then quote := 2
  if quote != 0 then return ← none
  pure ((part :: parts).reverse)

def readerFiles? (words : List String) : Option (List String) := do
  let executable ← words.head?
  let arguments := words.tail
  let name := (System.FilePath.mk executable).fileName.getD executable
  match name with
  | "cat" =>
      let files := arguments.dropWhile (fun word => ["--", "-n", "-b", "-s", "-v", "-E", "-T"].contains word)
      if files.isEmpty || files.any (fun file => file.startsWith "-") then none else some files
  | "sed" =>
      match arguments with
      | "-n" :: program :: files =>
          if !files.isEmpty && printProgram program &&
              !files.any (fun file => file.startsWith "-") then some files else none
      | _ => none
  | "rg" =>
      let arguments := arguments.dropWhile (fun word =>
        ["-n", "-l", "-i", "-S", "-F", "-w", "-s", "--fixed-strings", "--line-number",
          "--ignore-case", "--word-regexp"].contains word)
      match arguments with
      | pattern :: files =>
          if !pattern.startsWith "-" && !files.isEmpty &&
              !files.any (fun file => file.startsWith "-") then some files else none
      | _ => none
  | "nl" =>
      match arguments with
      | [file] | ["-ba", file] => if file.startsWith "-" then none else some [file]
      | _ => none
  | _ => none

structure ReadPlan where
  sources : {files : List String // files ≠ []}
  filters : List StreamFilter

def readPlan? (command : String) : Option ReadPlan := do
  let segments ← pipelineSegments? command
  let words ← segments.mapM literalWords?
  let first ← words.head?
  let files ← readerFiles? first
  let filters ← words.tail.mapM streamFilter?
  if nonempty : files ≠ [] then some ⟨⟨files, nonempty⟩, filters⟩ else none

def commandFiles? (command : String) : Option (List String) :=
  (readPlan? command).map (·.sources.val)

theorem accepted_read_plan_dependencies (command : String) (plan : ReadPlan)
    (accepted : readPlan? command = some plan) :
    commandFiles? command = some plan.sources.val := by
  simp [commandFiles?, accepted]

theorem read_plan_dependencies_nonempty (plan : ReadPlan) : plan.sources.val ≠ [] :=
  plan.sources.property

theorem stream_filters_preserve_dependencies (plan : ReadPlan) (filters : List StreamFilter) :
    ({plan with filters} : ReadPlan).sources = plan.sources := rfl

def inputPaths (input : Json) : List String :=
  let direct := pathsFromInput input ++ ((input.getObjValAs? (List String) "paths").toOption.getD [])
  (if !direct.isEmpty then direct else
    (((input.getObjValAs? String "cmd").toOption.orElse
      (fun _ => (input.getObjValAs? String "command").toOption)).bind commandFiles?).getD []).eraseDups

def inputDirectory? (workspace : System.FilePath) (input : Json) : Option System.FilePath := do
  let mut directory := workspace
  let mut specified := false
  for key in ["workdir", "cwd"] do
    if (input.getObjVal? key).isOk then
      let raw ← (input.getObjValAs? String key).toOption
      let actual := (workspace / raw).normalize
      if specified && directory != actual then return ← none
      directory := actual
      specified := true
  pure directory

def capture (workspace : System.FilePath) (input : Json) (deadline : Nat) : IO Capture := do
  let paths := inputPaths input
  let uris := (urisFromInput input ++ paths.filter isURI).eraseDups
  if paths.isEmpty || !uris.isEmpty then return unknown workspace uris
  let some directory := inputDirectory? workspace input | return unknown workspace
  let mut probes := []
  for path in paths do
    let some relative := relative? workspace directory path | return unknown workspace
    let some observed ← probe workspace relative deadline | return unknown workspace
    probes := observed :: probes
  let completed := probes.reverse
  let record : Record := ⟨workspace.fileName.getD workspace.toString, completed.map (·.file), [], true⟩
  if !record.valid then return unknown workspace
  pure ⟨record, completed⟩

def sealCapture (workspace : System.FilePath) (capture : Capture) (deadline : Nat) : IO Record := do
  if capture.record.files != capture.probes.map (·.file) || !capture.record.valid then
    return {capture.record with complete := false}
  for probe in capture.probes do
    if (← IO.monoMsNow) ≥ deadline then return {capture.record with complete := false}
    unless ← stillCurrent workspace probe do return {capture.record with complete := false}
  pure capture.record

def sourceMarker : String := "EGGSHELL SOURCE\n"

def encode (record : Record) : String := sourceMarker ++ (toJson record).compress

def decode? (text : String) : Option Record := do
  if !text.startsWith sourceMarker then none else
    (Json.parse ((text.drop sourceMarker.length).copy) >>= fromJson?).toOption

/-- Source certificates are separate Exact-only roots. Adding one never
changes the identity of an observed Outcome or its semantic search terms. -/
def receiptMarker : String := "eggshell.source"
def receiptPurpose : String := "observed dependency certificate"

structure ReceiptFields (α : Type) where
  marker : α
  session : α
  turn : α
  tag : α
  owner : α
  data : α
  purpose : α

def receiptFields? {α : Type} (references : List (Authority × α)) : Option (ReceiptFields α) :=
  match Relation.exactValues references with
  | some [marker, session, turn, tag, owner, data, purpose] =>
      some ⟨marker, session, turn, tag, owner, data, purpose⟩
  | _ => none

def receiptArguments (session turn tag owner : Value) (record : Record) : List Ref :=
  [
    .exact (.text receiptMarker), .exact session, .exact turn, .exact tag,
    .exact owner, .exact (.text (encode record)), .exact (.text receiptPurpose)]

def receipt (session turn tag owner : Value) (record : Record) : Value :=
  .applyList .receipt (receiptArguments session turn tag owner record)

theorem receipt_owner_bound (session turn tag owner : Value) (record : Record) :
    (receiptFields? (receiptArguments session turn tag owner record)).map (·.owner) = some owner := by
  rfl

def receiptRecord? (owner value : Value) : Option Record := do
  match value with
  | .apply .receipt references =>
      let fields ← receiptFields? references.toList
      if fields.marker != .text receiptMarker || fields.purpose != .text receiptPurpose ||
          fields.owner != owner then none
      else match fields.data with
        | .atom bytes => String.fromUTF8? bytes >>= decode?
        | _ => none
  | _ => none

theorem receipt_other_owner_rejected (session turn tag owner other : Value) (record : Record)
    (different : owner ≠ other) :
    receiptRecord? other (receipt session turn tag owner record) = none := by
  simp [receiptRecord?, receipt, receiptArguments, receiptFields?, Relation.exactValues,
    Value.applyList, Refs.ofList, Refs.toList, Ref.exact, different]

/-- Unknown is a real provenance state, not a successful check with no files. -/
def unverified : Record := ⟨"", [], [], false⟩

abbrev Ledger := Std.HashMap String (Option File)

def currentFiles? (ledger : Ledger) (files : List File) : Option (List File) :=
  files.mapM fun file => (ledger[file.relative]?).join

def recordAgrees (ledger : Ledger) (record : Record) : Bool :=
  (currentFiles? ledger record.files).any (agrees record)

structure Authorization (records : List Record) where
  ledger : Ledger
  nonempty : records ≠ []
  checked : ∀ record ∈ records, recordAgrees ledger record = true

def authorize? (records : List Record) (ledger : Ledger) : Option (Authorization records) :=
  if checked : (!records.isEmpty && records.all (recordAgrees ledger)) = true then
    some ⟨ledger, by
      intro empty
      simp [empty] at checked,
      List.all_eq_true.mp (Bool.and_eq_true_iff.mp checked).2⟩ else none

theorem authorization_uses_observed_ledger (records : List Record) (ledger : Ledger)
    (authorization : Authorization records)
    (accepted : authorize? records ledger = some authorization) :
    authorization.ledger = ledger := by
  unfold authorize? at accepted
  split at accepted
  · cases accepted
    rfl
  · contradiction

/-- A currently named file/directory must occur in the selected sources under
the same relative locator, not merely with a matching basename or bytes. -/
def targetAgreement (targets : List String) (records : List Record) : Bool :=
  targets.all fun target => (records.flatMap (·.files)).any fun file =>
    file.relative == target || file.relative.startsWith (target ++ "/")

theorem target_agreement_has_each_locator (targets : List String) (records : List Record)
    (accepted : targetAgreement targets records = true) (target : String) (present : target ∈ targets) :
    ∃ file ∈ records.flatMap (·.files), file.relative == target ||
      file.relative.startsWith (target ++ "/") := by
  have covered := List.all_eq_true.mp accepted target present
  simpa only [List.any_eq_true] using covered

def workTargets? (workspace : System.FilePath) (work : String) : Option (List String) := do
  let lines := work.splitOn "\n"
  let input ← (Json.parse ("\n".intercalate lines.tail)).toOption
  let paths := inputPaths input
  if paths.isEmpty || !(urisFromInput input).isEmpty || paths.any isURI then none else do
    let directory ← inputDirectory? workspace input
    paths.mapM fun path => (relative? workspace directory path).map (·.text)

theorem authorization_has_current_dependencies (authorization : Authorization records)
    (record : Record) (present : record ∈ records) :
    ∃ current, currentFiles? authorization.ledger record.files = some current ∧
      record.valid = true ∧ current = record.files := by
  have accepted := authorization.checked record present
  cases observed : currentFiles? authorization.ledger record.files with
  | none => simp [recordAgrees, observed] at accepted
  | some current =>
      refine ⟨current, rfl, ?_⟩
      simpa [recordAgrees, observed, agrees] using accepted

/-- Request-local observation is shared by all selected owners. Even a failed
probe is done once; it cannot be converted to a permanent negative result. -/
def observeRecords (workspace : System.FilePath) (records : List Record) (deadline : Nat) :
    IO Ledger := do
  let mut observations : Std.HashMap String (Option Probe) := {}
  for record in records do
    if !record.valid then continue
    for file in record.files do
      if observations.contains file.relative then continue
      let some relative := Relative.check? file.relative | continue
      let observed ← probe workspace relative deadline
      observations := observations.insert file.relative observed
  let mut ledger : Ledger := {}
  for (relative, observed) in observations.toList do
    ledger := ledger.insert relative (← checkedProbeFile workspace observed deadline)
  pure ledger

/-- Delivery status replaces the previous observation for the same selected
source scope. Graph delivery and completion keys use separate namespaces. -/
def deliveryScope? (key : String) : Option String :=
  match key.splitOn ":" with
  | ["s", scope, status] => if scope.isEmpty || status.isEmpty then none else some scope
  | _ => none

end Eggshell.SourceEvidence
