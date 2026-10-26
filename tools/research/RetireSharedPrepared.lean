import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then return if metadata.type == .file then metadata.byteSize.toNat else 0
  let mut total := 0
  for entry in ← path.readDir do total := total+(← bytes entry.path)
  return total

private partial def remove (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do remove entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

/-- Fixed allowlist, completed guards, retained evidence and live-process/link
checks precede deletion. Symlinks are removed without following their targets. -/
def main (args : List String) : IO Unit := do
  let [mode,destination] := args | throw (IO.userError "RetireSharedPrepared rejected|finished NEW-REPORT")
  let output := System.FilePath.mk destination
  unless output.isAbsolute && !(← output.pathExists) do throw (IO.userError "new absolute deletion report required")
  let base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
  let a := base / "shared-prepared-service-20261026"
  let b := base / "shared-bundle-projection-20261026"
  let evidence := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates"
  let (guards,proofs,targets) ← match mode with
    | "rejected" => pure (#[b / "required-replay/topic-1/prepare.guard.json"],
        #[evidence / "shared-bundle-projection/records/rejected-unmodified-binary/rejection.json",
          evidence / "shared-bundle-projection/records/rejected-unmodified-binary/stdout"],
        #[b / "required-replay"])
    | "finished" => pure (#[a / "run-native.guard.json",a / "run-matrix.guard.json",
        a / "run-numbered-source.guard.json",a / "run-lifecycle.guard.json",
        a / "required-replay/topic-1/prepare.guard.json",a / "required-replay/topic-1/render-profile.guard.json",
        b / "required-replay/topic-1/prepare.guard.json",b / "required-replay/topic-1/source-bound.guard.json"],
        #[evidence / "shared-prepared-service/records/collection.json",
          evidence / "shared-bundle-projection/records/collection.json"],
        #[a / "run-native",a / "run-matrix",a / "run-numbered-source",a / "run-lifecycle",
          a / "required-replay/prefix",b / "required-replay/prefix"])
    | _ => throw (IO.userError "known completed experimental targets required")
  for path in guards do
    let record ← read path
    unless (record.getObjValAs? String "state").toOption == some "finished" &&
        (record.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "experimental target still owns processes")
  for path in proofs do
    unless ← path.pathExists do throw (IO.userError "small evidence must be preserved before deletion")
  let prefixes := if mode == "rejected" then #[b / "required-replay/prefix"]
    else #[a / "required-replay/prefix",b / "required-replay/prefix"]
  let mut targets := targets
  let data := base / "literal-support-20261026/required-replay/topic-1/data/index-targets"
  for entry in ← data.readDir do
    if !entry.fileName.endsWith ".json" then continue
    let command ← IO.ofExcept ((← read entry.path).getObjValAs? (Array String) "command")
    if prefixes.any (fun prefixPath => command[0]? == some (prefixPath / "libexec/eggshell").toString) then
      targets := targets.push entry.path
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot inspect live target ownership")
  let response := (← IO.FS.readFile (a / "product-build/runtime.rsp")) ++
    (← IO.FS.readFile (b / "product-build/runtime.rsp"))
  let mut removed := #[]
  let mut total := 0
  for path in targets do
    unless (processes.stdout.splitOn path.toString).length == 1 &&
        (response.splitOn path.toString).length == 1 do
      throw (IO.userError "target has a live process or product link dependency")
    let size ← bytes path
    total := total+size
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson size)])
  let record := Json.mkObj [("targets",toJson removed),("logicalBytes",toJson total),
    ("archiveCreated",toJson false),("followsSymlinks",toJson false),
    ("originalSeedAndActiveSourceRetained",toJson true),("activeLinkInputsRetained",toJson true)]
  IO.FS.writeFile output record.pretty
  for path in targets do remove path
  for path in targets do
    if ← path.pathExists then throw (IO.userError "retired target survived")
  IO.FS.writeFile (.mk (destination ++ ".result.json"))
    (Json.mkObj [("removed",toJson targets.size),("logicalBytes",toJson total),("archiveCreated",toJson false)]).pretty
  IO.println record.compress
