import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  pure ((result.stdout.splitOn " ").head!).trimAscii.toString

/-- Preserve measured worker results without retaining diagnostic databases.
No diagnostic deadline is promoted to a hook deadline. -/
def main (args : List String) : IO Unit := do
  let (sourceName,destinationName,metadata) ← match args with
    | [source,destination] => pure (source,destination,false)
    | [source,destination,"metadata"] => pure (source,destination,true)
    | _ => throw (IO.userError "CollectSelectorObservation CANDIDATE DIRECTORY [metadata]")
  let source := System.FilePath.mk sourceName
  let destination := System.FilePath.mk destinationName
  unless source.isAbsolute && destination.isAbsolute && ((← destination.pathExists) == metadata) do
    throw (IO.userError "absolute source and new collection directory required")
  if metadata then
    let build ← read (source / "product-build/build.json")
    let parent ← IO.ofExcept ((build.getObjValD "settings").getObjValAs? String "baselineCore")
    let file := "tools/DeferredCoverage.lean"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/" ++ file,"-L","b/" ++ file,
      (System.FilePath.mk parent / file).toString,(source / "checkout" / file).toString]}
    unless patch.exitCode == 1 do throw (IO.userError "diagnostic-only patch expected")
    IO.FS.writeFile (destination.parent.get! / "core.patch") patch.stdout
    let mut guards := #[]
    for entry in ← source.readDir do
      if entry.fileName.endsWith ".guard.json" then
        let guard ← read entry.path
        guards := guards.push (Json.mkObj (("file",toJson entry.fileName) ::
          (["state","exitCode","reason","guardTriggered","sampledPeakRssKiB","ownedPids"].map
            fun key => (key,guard.getObjValD key))))
    IO.FS.writeFile (destination / "frozen-before-delivery.json")
      (← IO.FS.readFile (source / "worker-probe/frozen-before-delivery.json"))
    IO.FS.writeFile (destination / "collection.json") (Json.mkObj [
      ("warm",← read (source / "worker-probe/warm-complete.json")),
      ("guards",toJson guards),("newPythonOrRuby",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
    return
  IO.FS.createDirAll destination
  let mut results := #[]
  for (name,worker,audit,guard) in [
      ("first",source / "worker-probe/topic-2/worker",source / "diagnostic-evidence/result.json",source / "worker-probe.guard.json"),
      ("receipts",source / "receipt-probe/worker",source / "receipt-probe/result.json",source / "receipt-probe.guard.json")] do
    let timing ← read (worker / "record.json")
    let coverage ← read audit
    let protection ← read guard
    unless (protection.getObjValAs? String "state").toOption == some "finished" &&
        (protection.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
      throw (IO.userError "diagnostic still owns processes")
    let stdout ← IO.FS.readFile (worker / "stdout")
    let some line := (stdout.splitOn "\n").filter (fun line => !line.isEmpty) |>.getLast? |
      throw (IO.userError "worker reply missing")
    let reply ← IO.ofExcept (Json.parse line)
    let body ← IO.ofExcept (((reply.getObjValD "reply").getObjValD "handoff").getObjValAs? String "text")
    IO.FS.writeFile (destination / (name ++ "-body.txt")) body
    IO.FS.writeFile (destination / (name ++ "-evidence.json")) coverage.pretty
    let stderr ← IO.FS.readFile (worker / "stderr")
    let events := stderr.splitOn "\n" |>.filter (·.startsWith "EGGSHELL_SELECTOR_")
    IO.FS.writeFile (destination / (name ++ "-selector.txt")) ("\n".intercalate events ++ "\n")
    results := results.push (Json.mkObj [
      ("name",toJson name),("elapsedMs",timing.getObjValD "elapsedMs"),
      ("stdoutSha256",timing.getObjValD "stdoutSha256"),("bodySha256",toJson (← digest (destination / (name ++ "-body.txt")))),
      ("actualHook",toJson false),("latencyAcceptance",toJson false),
      ("coverageWithoutDeadline",coverage.getObjValD "coverageWithoutDeadline"),
      ("peakAggregateRssKiB",protection.getObjValD "sampledPeakRssKiB"),
      ("guardTriggered",protection.getObjValD "guardTriggered"),("remainingProcesses",protection.getObjValD "ownedPids")])
  let missing ← read (source / "worker-missing/summary.json")
  IO.FS.writeFile (destination / "missing.json") missing.pretty
  for report in ← (source / "worker-missing").readDir do
    if report.fileName.startsWith "range-" && report.fileName.endsWith ".json" then
      IO.FS.writeFile (destination / report.fileName) (← IO.FS.readFile report.path)
  IO.FS.writeFile (destination / "results.json") (Json.mkObj [
    ("diagnosticOnly",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false),("trials",toJson results)]).pretty
  IO.println (toJson results).compress
