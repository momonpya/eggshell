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

private def runCase (root binary : System.FilePath) (row : CaseRow) : IO Json := do
  assertSource row
  let revision ← IO.Process.output {cmd := "git", args := #["rev-parse", "HEAD"], cwd := some row.workspace}
  check (revision.exitCode == 0 && revision.stdout.trimAscii.toString == row.sourceCommit) "benchmark source revision changed"
  let directory := root / s!"stage{row.stage}"
  IO.FS.createDirAll directory
  let database := directory / "work.egg"
  let copied ← IO.Process.output {cmd := "/bin/cp", args := #["-cR", row.source, database.toString]}
  check (copied.exitCode == 0) copied.stderr
  let original ← DB.PageMap.pin database
  let originalPages ← IO.FS.readBinFile (DB.PageMap.dataPath database original.head)
  let originalPages := originalPages.extract 0 original.head.bytes
  let (documents, rows) ← originalRows original row.required
  let config := directory / "config.toml"
  let command := [binary.toString, "search-provider"]
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++ (toJson command).compress ++
    "\n[eggs]\nwork = " ++ (toJson database.toString).compress ++
    "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let dataRoot := directory / "data"
  IO.FS.createDirAll dataRoot
  let environment := #[("EGGSHELL_CONFIG", some config.toString), ("EGGSHELL_DATA_ROOT", some dataRoot.toString),
    ("HF_HUB_OFFLINE", some "1"), ("OMP_NUM_THREADS", some "1"), ("TOKENIZERS_PARALLELISM", some "false")]
  let cwd := System.FilePath.mk row.workspace
  let (warm, _) ← execute (directory / "warm") cwd binary.toString #["egg", "warm", "work"] environment
  let _ ← IO.ofExcept (Json.parse warm)
  let mut outputs : Array String := #[]
  let mut results := #[]
  for index in [:2] do
    let session := s!"synaptic-six-{row.stage}-{index}"
    let base := Json.mkObj [("session_id", toJson session), ("turn_id", toJson "first"),
      ("cwd", toJson row.workspace), ("_eggshell_config", toJson config.toString)]
    let trial := directory / s!"native-{index}"
    try
      let _ ← hook (trial / "start") cwd binary environment (base.setObjVal! "hook_event_name" (toJson "SessionStart"))
      let input := (base.setObjVal! "hook_event_name" (toJson "UserPromptSubmit")) |>.setObjVal! "prompt" (toJson row.prompt)
      let (stdout, elapsed) ← hook (trial / "prompt") cwd binary environment input
      let reply ← IO.ofExcept (Json.parse stdout)
      let body := (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext")).toOption.getD ""
      IO.FS.writeFile (trial / "body.txt") body
      let incomplete := decide ((body.splitOn "EGGSHELL SEARCH INCOMPLETE").length > 1)
      outputs := outputs.push body
      results := results.push (Json.mkObj [("elapsedMs", toJson elapsed), ("incomplete", toJson incomplete),
        ("bodySha256", toJson (Sha256.hex body.toUTF8)), ("requirements", audit body row.required documents rows)])
    finally
      let _ ← execute (trial / "shutdown") cwd binary.toString #["codex-daemon", "shutdown"] environment
      pure ()
  let after ← DB.PageMap.pin database
  check (← Synapses.Index.sameSources after original.head (after.head.revision-original.head.revision+1))
    "native preparation changed source graph facts"
  let pages ← IO.FS.readBinFile (DB.PageMap.dataPath database after.head)
  check (pages.extract 0 originalPages.size == originalPages) "native preparation mutated original page bytes"
  assertSource row
  let same := outputs[0]? == outputs[1]?
  let result := Json.mkObj [("stage", toJson row.stage), ("topic", toJson row.topic),
    ("sameIndependentBodies", toJson same), ("sessions", toJson results), ("answeringModelCalls", toJson (0 : Nat))]
  IO.FS.writeFile (directory / "result.json") result.compress
  IO.println result.compress
  return result

def main (args : List String) : IO Unit := do
  if let ["audit", specification, bodies, destination] := args then
    let json ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)))
    let cases ← IO.ofExcept (fromJson? (α := Array CaseRow) json)
    let mut results := #[]
    for row in cases do
      assertSource row
      let source ← DB.PageMap.pin (.mk row.source)
      let (documents, rows) ← originalRows source row.required
      let mut sessions := #[]
      for index in [:2] do
        let body ← IO.FS.readFile (System.FilePath.mk bodies / "prepared" /
          s!"stage{row.stage}-native" / s!"native-{index}" / "body.txt")
        sessions := sessions.push (audit body row.required documents rows)
      results := results.push (Json.mkObj [("stage", toJson row.stage), ("sessions", toJson sessions)])
    IO.FS.writeFile (.mk destination) (toJson results).compress
    return
  let [path, executable, specification] := args | throw (IO.userError "SynapseSixGate NEW-ROOT CANDIDATE FROZEN-SPEC")
  let root := System.FilePath.mk path
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "new absolute gate root required")
  let json ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)))
  let cases ← IO.ofExcept (fromJson? (α := Array CaseRow) json)
  check (cases.map (·.stage) == #[1,2,3,4,5,6]) "freeze all six stages in order"
  IO.FS.createDirAll root
  let mut results := #[]
  for row in cases do
    results := results.push (← runCase root (.mk executable) row)
    IO.FS.writeFile (root / "progress.json") (toJson results).compress
