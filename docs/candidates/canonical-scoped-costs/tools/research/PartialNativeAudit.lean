import Eggshell.SynapseBuild
import Eggshell.SynapseUsage

open Lean Eggshell Eggshell.Synapses

private structure Requirement where
  name : String
  path : String
  first : Nat
  last : Nat
  originalOwners : Array String
  deriving FromJson

private structure CaseRow where
  stage : Nat
  topic : Nat
  source : String
  workspace : String
  sourceCommit : String
  prompt : String
  files : Array (String × String)
  required : Array Requirement
  deriving FromJson

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def execute (root cwd : System.FilePath) (binary : String) (arguments : Array String)
    (environment : Array (String × Option String)) : IO (String × Nat) := do
  IO.FS.createDirAll root
  let started ← IO.monoMsNow
  let result ← IO.Process.output {cmd := binary, args := arguments, env := environment, cwd := some cwd.toString}
  let elapsed := (← IO.monoMsNow)-started
  IO.FS.writeFile (root / "stdout") result.stdout
  IO.FS.writeFile (root / "stderr") result.stderr
  IO.FS.writeFile (root / "record.json") (Json.mkObj [
    ("elapsedMs", toJson elapsed), ("exitCode", toJson result.exitCode.toNat),
    ("stdoutSha256", toJson (Sha256.hex result.stdout.toUTF8))]).compress
  check (result.exitCode == 0) s!"native gate command failed: {root}: {result.stderr}"
  return (result.stdout, elapsed)

private def hook (root cwd binary : System.FilePath) (environment : Array (String × Option String))
    (input : Json) : IO (String × Nat) := do
  IO.FS.createDirAll root
  let path := root / "stdin"
  IO.FS.writeFile path input.compress
  execute root cwd "/bin/sh" #["-c", "exec \"$1\" codex-hook < \"$2\"", "hook", binary.toString, path.toString] environment

private def assertSource (row : CaseRow) : IO Unit := do
  for (name, expected) in row.files do
    let actual := Sha256.hex (← IO.FS.readBinFile (System.FilePath.mk row.source / name))
    check (actual == expected) s!"canonical source changed: stage {row.stage} {name}"

private def originalRows (source : DB.PageMap.Snapshot) (requirements : Array Requirement) :
    IO (Array Synapses.Extraction.Document × Array Synapses.Read) := do
  let reader ← Persistence.Store.NodeReader.new source
  let mut seen : Std.HashSet String := {}
  let mut documents := #[]
  let mut rows := #[]
  for requirement in requirements do
    for owner in requirement.originalOwners do
      if seen.contains owner then continue
      seen := seen.insert owner
      let some id ← Synapses.Build.ownerId? source owner | throw (IO.userError "frozen required owner is missing")
      let doc ← Synapses.Build.document reader id
      documents := documents.push doc
      match Synapses.Extraction.recordedRows source.head.identity doc with
      | .ok found => rows := rows ++ found
      | .error _ => pure ()
  return (documents, rows)

private def audit (body : String) (requirements : Array Requirement)
    (documents : Array Synapses.Extraction.Document) (rows : Array Synapses.Read) : Json :=
  let shown := Synapses.Extraction.presented body documents rows
  toJson (requirements.map fun requirement =>
    let candidates := rows.filter fun row => requirement.originalOwners.contains row.binding.owner &&
      row.source.file.relative == requirement.path
    let files := candidates.foldl (fun files row => files.insert row.source.file) ({} : Std.HashSet File)
    let stored := files.toArray.any fun file =>
      covered ⟨file, requirement.first, requirement.last⟩ (candidates.map (·.source))
    let delivered := files.toArray.any fun file =>
      covered ⟨file, requirement.first, requirement.last⟩ shown.ranges
    Json.mkObj [("name", toJson requirement.name), ("stored", toJson stored),
      ("storedOwners", toJson requirement.originalOwners), ("bodyDelivered", toJson delivered),
      ("unlocated", toJson (!requirement.originalOwners.isEmpty && !stored))])

/-- Audit only actual completed stdout files in a partial native run. Missing
sessions remain missing; no duplicated body stands in for another chat. -/
def main (args : List String) : IO Unit := do
  let [specification,root,destination] := args | throw (IO.userError "PartialNativeAudit SPEC ROOT OUTPUT")
  let cases ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)) >>= fromJson? (α := Array CaseRow))
  let mut results := #[]
  for row in cases do
    let stage := System.FilePath.mk root / s!"stage{row.stage}"
    if !(← (stage / "work.egg").pathExists) then continue
    assertSource row
    let before ← DB.PageMap.pin (.mk row.source)
    let after ← DB.PageMap.pin (stage / "work.egg")
    let same ← Synapses.Index.sameSources after before.head (after.head.revision-before.head.revision+1)
    let original ← IO.FS.readBinFile (DB.PageMap.dataPath before.directory before.head)
    let now ← IO.FS.readBinFile (DB.PageMap.dataPath after.directory after.head)
    let prefixExact := original.extract 0 before.head.bytes == now.extract 0 before.head.bytes
    check (same && prefixExact) "partial run changed original source facts/pages"
    let (documents,rows) ← originalRows before row.required
    let mut sessions := #[]
    for index in [:2] do
      let trial := stage / s!"native-{index}"
      if !(← (trial / "prompt" / "record.json").pathExists) then continue
      let stdout ← IO.FS.readFile (trial / "prompt" / "stdout")
      let record ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "prompt" / "record.json")))
      let expected ← IO.ofExcept (record.getObjValAs? String "stdoutSha256")
      let reply ← IO.ofExcept (Json.parse stdout)
      let body ← IO.ofExcept (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext"))
      let saved ← IO.FS.readFile (trial / "body.txt")
      check (body == saved && Sha256.hex stdout.toUTF8 == expected) "actual stdout/body mismatch"
      sessions := sessions.push (Json.mkObj [("session",toJson index),
        ("actualStdoutBound",toJson true),("bodySha256",toJson (Sha256.hex body.toUTF8)),
        ("elapsedMs",record.getObjValD "elapsedMs"),("requirements",audit body row.required documents rows)])
    results := results.push (Json.mkObj [("stage",toJson row.stage),("sameSourceFacts",toJson same),
      ("samePublishedPagePrefix",toJson prefixExact),("sessions",toJson sessions)])
  IO.FS.writeFile (.mk destination) (toJson results).compress
  IO.println s!"audited {results.size} actual partial stages without aliasing missing sessions"
