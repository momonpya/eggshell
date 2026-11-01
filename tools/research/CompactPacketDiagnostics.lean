import Lean
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum", args := #["-a", "256", path.toString]}
  check (result.exitCode == 0) "cannot verify protected original"
  return (result.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1, if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0, 0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1 + next.1, total.2 + next.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates"
  let output := records / "priced-fragments/finished-diagnostics.json"
  check (!(← output.pathExists)) "preserve previous cleanup record"
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (records / "read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path, expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed"
  let stages := #[("packet-envelope", "733c97d55943fa281146928d29bc75ac119f285939d79ec218d97e105db97308"),
    ("packet-failure", "c21bd12b1ada24d0c4ca5d09413c9146c1403fbcb3bc52282b0a7153cb0b074a"),
    ("packet-materialize", "b64d32eba06c39f6f2cdbc6d4caea02417ed6261cfc4a6983436a450e12e1ee1"),
    ("fragment-identity", "d6f77b324a9032cfce692b71e9284197086d78daab29711330c556008895acaa")]
  let mut rows := #[]
  let mut retired := #[]
  for (name, receipt) in stages do
    let stage := records / name
    let actual := stage / "hooks/candidate/rep-0/topic-1"
    let guard ← read (stage / "topic-1.guard.json")
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a diagnostic has not finished"
    let mut endings := #[]
    for label in ["shutdown", "publisher-shutdown"] do
      let ending ← read (actual / (label ++ ".json"))
      check (["acknowledged", "processExited", "endpointRemoved"].all
        (fun key => ending.getObjValD key == toJson true)) "a service has not stopped"
      endings := endings.push ending
    let failure ← read (root / "packet-envelope-trial/candidate/data/receipts" / receipt /
      "prepared-selection-failure.json")
    rows := rows.push (Json.mkObj [("name", toJson name), ("result", ← read (actual / "result.json")),
      ("beforeGold", ← read (actual / "before-gold.json")), ("serviceProfiles", ← read (actual / "service-profile.json")),
      ("failure", failure), ("shutdown", toJson endings), ("adopted", toJson false)])
    retired := retired.push actual |>.push (stage / "hooks/candidate/warm")
    for role in ["runtime", "hook-candidate"] do
      -- Linked executables have no borrowers. Keep the .o/.olean closure used by later builds.
      let binary := root / (name ++ "-" ++ role ++ "-build/StudyMain")
      check (!(originals.any (fun entry => entry.1 == binary.toString))) "protected executable selected"
      retired := retired.push binary
  IO.FS.writeFile output (Json.mkObj [("stages", toJson rows), ("archive", toJson false),
    ("modelCalls", toJson (0 : Nat)), ("adopted", toJson false)]).pretty
  let mut total := (0, 0)
  for path in retired do
    if !(← path.pathExists) then continue
    let next ← remove path
    total := (total.1 + next.1, total.2 + next.2)
  for (path, expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed after deletion"
  IO.FS.writeFile (records / "priced-fragments/finished-cleanup.json") (Json.mkObj [
    ("files", toJson total.1), ("logicalBytes", toJson total.2), ("deleted", toJson (retired.map (·.toString))),
    ("protectedFilesVerifiedBeforeAndAfter", toJson originals.size), ("archive", toJson false),
    ("nativeObjectClosureRetained", toJson true)]).pretty
  IO.println s!"Deleted {total.1} files / {total.2} logical bytes; protected {originals.size} originals unchanged."
