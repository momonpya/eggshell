import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def base := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell"
private def allowed := #["advisory-prefix-20261026","selection-plan-20261026",
  "canonical-plan-20261026","record-catalog-20261026","shared-activation-20261026"]
private def buildDependencies := #["complete-focus-20261026","record-focus-20261026"]

private def targets (name : String) : Array String :=
  if buildDependencies.contains name then
    #["topic-1/work.egg","topic-1/data","prefix","contract/lib"]
  else #["topic-1/work.egg","topic-1/data","checks","check-build","inspection","build","prefix","checkout","contract/lib",
    "probe-tools_research_SharedActivationChecks","probe-tools_research_SynapticWalkAudit"]

private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "retirement digest failed")
  let value := ((result.stdout.take 64).toString)
  unless value.length == 64 do throw (IO.userError "invalid retirement digest")
  return value

private partial def bytes (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut count := 0
    for entry in ← path.readDir do count := count+(← bytes entry.path)
    return count
  return if metadata.type == .file then metadata.byteSize.toNat else 0

/-- Never follow checkout/library/model links while retiring a prototype. -/
private partial def unlinkTree (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do unlinkTree entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

private partial def guardsClosed (path : System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then
      if !#["checkout","build","check-build","inspection","prefix","lib","work.egg","data"].contains entry.fileName then
        guardsClosed entry.path
    else if metadata.type == .file && entry.fileName.endsWith ".guard.json" then
      let value ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless (value.getObjValAs? String "state").toOption == some "finished" &&
          (value.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
        throw (IO.userError "prototype guard is not terminal and empty")

private partial def rejectActiveLinks (retired : Array String) (path : System.FilePath) : IO Unit := do
  for entry in ← path.readDir do
    let metadata ← entry.path.symlinkMetadata
    if metadata.type == .dir then rejectActiveLinks retired entry.path
    else if metadata.type == .symlink then
      let target ← IO.FS.realPath entry.path
      unless !retired.any (fun name => target.toString.startsWith ((base / name).toString ++ "/")) do
        throw (IO.userError "active checkout depends on retired prototype")

def main (args : List String) : IO Unit := do
  let activeName :: destination :: names := args |
    throw (IO.userError "RetireDeliveryPrototypes ACTIVE-NAME NEW-REPORT OLD-NAME...")
  let retired := names.toArray
  unless !retired.isEmpty && retired.all (fun name => allowed.contains name || buildDependencies.contains name) &&
      retired.toList.eraseDups.length == retired.size && !retired.contains activeName &&
      !activeName.isEmpty && activeName.toList.all (fun char => char.isAlphanum || char == '-') do
    throw (IO.userError "only explicit ended prototype names may be removed")
  let report := System.FilePath.mk destination
  unless report.isAbsolute && !(← report.pathExists) do throw (IO.userError "keep previous retirement evidence")
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot verify live prototype processes")
  for name in retired do
    unless (processes.stdout.splitOn (base / name).toString).length == 1 do
      throw (IO.userError "prototype still appears in a live process")
    guardsClosed (base / name)
  let active := base / activeName
  let forbidden := retired.flatMap fun name => (targets name).map (fun relative => name ++ "/" ++ relative)
  rejectActiveLinks forbidden (active / "checkout")
  rejectActiveLinks forbidden (active / "prefix")
  let response ← IO.FS.readFile (active / "build/runtime.rsp")
  unless !forbidden.any (fun name => (response.splitOn (base / name).toString).length > 1) do
    throw (IO.userError "active link plan depends on retired object files")
  let mut removed := #[]
  let mut removals : Array System.FilePath := #[]
  let mut count := 0
  for name in retired do
    let root := base / name
    let receipts := root / "topic-1/data/receipts"
    if ← receipts.pathExists then
      for entry in ← receipts.readDir do
        if (← entry.path.symlinkMetadata).type != .dir then continue
        for record in ← entry.path.readDir do
          unless record.fileName.endsWith ".json" &&
              (#["request.json","ack.json","search.json","transport.json","synaptic-delivery.json",
                "canonical-source-input.json","delivery-domain.json","selection-plan.json"].contains record.fileName ||
                #["numerical-","lexical-","keyed-"].any (fun prefixText => record.fileName.startsWith prefixText)) do continue
          let target := root / "recorded-receipts" / entry.fileName / record.fileName
          unless !(← target.pathExists) && (← record.path.symlinkMetadata).type == .file do
            throw (IO.userError "unexpected receipt or existing extracted record")
          let data ← IO.FS.readBinFile record.path
          unless data.size ≤ 8*1024*1024 do throw (IO.userError "receipt exceeds extraction bound")
          IO.FS.createDirAll target.parent.get!
          IO.FS.writeBinFile target data
    let product := root / "prefix/libexec/eggshell"
    let productHash ← digest product
    for relative in targets name do
      let path := root / relative
      if !(← path.pathExists) then continue
      let size ← bytes path
      count := count+size
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson size),
        ("prototypeProductSha256",toJson productHash)])
      removals := removals.push path
  IO.FS.writeFile report (Json.mkObj [("removed",toJson removed),("logicalBytes",toJson count),
    ("archives",toJson false),("activeCandidateRetained",toJson active.toString),
    ("state",toJson "inspected"),
    ("currentSeedAndSupportRetained",toJson true)]).pretty
  let mut completed : Array String := #[]
  for path in removals do
    unlinkTree path
    completed := completed.push path.toString
    IO.FS.writeFile (report.withExtension "result.json") (Json.mkObj [
      ("state",toJson (if completed.size == removals.size then "finished" else "removing")),
      ("completed",toJson completed),("archives",toJson false)]).pretty
  IO.println (Json.mkObj [("removedTargets",toJson removed.size),("logicalBytes",toJson count),
    ("archives",toJson false)]).compress
