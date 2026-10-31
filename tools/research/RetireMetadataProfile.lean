import Lean
import Std.Data.HashSet
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun s => IO.ofExcept (Json.parse s)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  ensure (result.exitCode == 0) "cannot hash retained input"
  return (result.stdout.splitOn " ").headD ""
private def summarize (path : System.FilePath) : IO Json := do
  ensure ((← path.metadata).byteSize < 8*1024*1024) "sample exceeds its diagnostic bound"
  let text ← IO.FS.readFile path
  let mut counts : Std.HashMap String Nat := {}
  for line in text.splitOn "\n" do
    let words := ((line.splitOn " ").filter (!·.isEmpty)).dropWhile fun word => word.toNat?.isNone
    let some count := words[0]?.bind String.toNat? | continue
    let some symbol := words[1]? | continue
    unless symbol.startsWith "l_" || symbol.startsWith "lean_" do continue
    counts := counts.insert symbol (max count (counts[symbol]?.getD 0))
  let ordered := counts.toArray.qsort fun a b => if a.2 == b.2 then a.1 < b.1 else b.2 < a.2
  let tops := (text.splitOn "Sort by top of stack, same collapsed (when >= 5):\n")[1]?.getD ""
  return Json.mkObj [("sha256",toJson (← hash path)),("bytes",toJson text.utf8ByteSize),
    ("headers",toJson ((text.splitOn "\n").take 23)),("maximumInclusiveSamplesByCallPath",toJson (ordered.extract 0 240)),
    ("symbols",toJson counts.size),("retainedSymbols",toJson (min 240 counts.size)),
    ("topOfStack",toJson ((((tops.splitOn "\n\n").headD "").splitOn "\n"))),
    ("interpretation",toJson "Inclusive path counts overlap. They are not direct function wall times or whole-hook CPU percentages.")]
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  let mut total := (0,0)
  for child in ← path.readDir do
    let deleted ← remove child.path
    total := (total.1+deleted.1,total.2+deleted.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/metadata-profile"
  let candidate := project / "docs/candidates/carried-value"
  ensure (!(← (records / "retired.json").pathExists)) "preserve native profile cleanup evidence"
  let result ← read (records / "result.json")
  ensure (result.getObjValD "sameParentBody" == toJson true && result.getObjValD "hookReexecuted" == toJson false &&
    result.getObjValD "workerProfileCaptured" == toJson false) "profile recovery status differs"
  for label in ["prepare","recover"] do
    let stopped ← read (records / (label ++ ".guard.json"))
    ensure (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (0 : Nat) &&
      stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "native profile job not terminal"
  let profile ← read (records / "publisher-profile.json")
  ensure ((profile.getObjValD "sample").getObjValD "symbols" != toJson (0 : Nat)) "native profile was empty"
  let run ← read (records / "run.guard.json")
  ensure (run.getObjValD "state" == toJson "finished" && run.getObjValD "exitCode" == toJson (1 : Nat) &&
    run.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "preserve the failed observation controller"
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "protected input changed"
  let mut inputs : Std.HashSet String := {}
  let mut binaries := #[]
  for name in ["carried-value-runtime-build","project-metadata-runtime-build","prepared-view-runtime-build","published-plan-runtime-build",
      "service-plan-runtime-build","source-plan-runtime-build","owner-palette-runtime-build","owner-palette-build",
      "receipt-reconciliation-runtime-build","query-cache-baseline-build"] do
    let directory := root / name
    binaries := binaries.push (directory / "StudyMain",← hash (directory / "StudyMain"))
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      ensure (!["metadata-profile-","carried-value-audit-","carried-value-hook-"].any
        (fun name => path.contains name)) "active product borrows an ended helper"
      if path.endsWith ".o" then
        ensure (← System.FilePath.pathExists path) "active native input missing"
        inputs := inputs.insert path
  let mut timeline := #[]
  for entry in ← (root / "metadata-profile-trial/candidate/data/receipts").readDir do
    if !(← (entry.path / "request.json").pathExists) then continue
    let request ← read (entry.path / "request.json")
    if (request.getObjValD "data").getObjValD "event" != toJson "UserPromptSubmit" then continue
    let mut events := #[]
    for name in ["request","keyed-request","keyed-nominations","canonical-source-input","delivery-domain",
        "selection-plan","synaptic-delivery","search","dispatch","transport","published"] do
      let path := entry.path / (name ++ ".json")
      if !(← path.pathExists) then continue
      let value ← read path
      events := events.push (Json.mkObj [("stage",toJson name),("observedMs",value.getObjValD "observedMs")])
    timeline := timeline.push (Json.mkObj [("events",toJson events)])
  IO.FS.writeFile (records / "receipt-timeline.json") (toJson timeline).pretty
  let prepared ← read (records / "hooks/candidate/prepared-source.json")
  let warm ← read (records / "hooks/candidate/warm/record.json")
  IO.FS.writeFile (records / "preparation.json") (Json.mkObj [("sourceIndexMs",prepared.getObjValD "elapsedMs"),
    ("wholeWarm",warm),("freshDiagnosticFork",toJson true),("newSeed",toJson false)]).pretty
  for (name,output) in [("metadata-profile-hook-candidate-build","helper-closure.json"),
      ("metadata-profile-recovery-build","recovery-closure.json")] do
    let checked ← IO.Process.output {cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",args :=
      #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        "inspect",(root / name).toString,(records / output).toString]}
    ensure (checked.exitCode == 0) "native profile helper dependencies differ"
  for name in ["build-final","run","runtime-build","hook-build","describe","prepare","hook-run"] do
    let stopped ← read (candidate / (name ++ ".guard.json"))
    ensure (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (0 : Nat) &&
      stopped.getObjValD "guardTriggered" == toJson false && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "carried runtime job did not finish cleanly"
  let actualRoot := candidate / "hooks/candidate/rep-0/topic-1"
  let actual ← read (actualRoot / "result.json")
  let before ← read (actualRoot / "before-gold.json")
  let described ← read (candidate / "hooks/candidate-runtime.json")
  ensure (actual.getObjValD "profilingComplete" == toJson true && before.getObjValD "goldRead" == toJson false)
    "candidate observation was incomplete or read gold first"
  let reference := project / "docs/candidates/source-plan/bodies/topic-1.txt"
  ensure ((← IO.FS.readFile reference) == (← IO.FS.readFile (actualRoot / "body.txt")) &&
    actual.getObjValD "bodySha256" == toJson (← hash (actualRoot / "body.txt"))) "candidate changed parent delivery"
  let mut candidateShutdowns := #[]
  for path in [actualRoot / "shutdown.json",actualRoot / "publisher-shutdown.json",candidate / "hooks/candidate/prepare-shutdown.json"] do
    let stopped ← read path
    ensure (["acknowledged","processExited","endpointRemoved"].all (fun key => stopped.getObjValD key == toJson true))
      "candidate service did not stop"
    candidateShutdowns := candidateShutdowns.push stopped
  IO.FS.writeFile (candidate / "shutdowns.json") (toJson candidateShutdowns).pretty
  for name in ["publisher","worker"] do
    let sample := actualRoot / "native-profile" / (name ++ ".sample.txt")
    let receipt ← read (sample.withExtension "json")
    ensure (receipt.getObjValD "exitCode" == toJson (0 : Nat)) "candidate sample failed"
    IO.FS.writeFile (candidate / (name ++ "-profile.json")) (Json.mkObj [
      ("sample",← summarize sample),("receipt",receipt)]).pretty
  IO.FS.writeFile (candidate / "worker-owner.json") (← IO.FS.readFile (actualRoot / "native-profile/worker-owner.json"))
  IO.FS.writeFile (candidate / "runtime.json") described.pretty
  IO.FS.writeFile (candidate / "result.json") ((actual.setObjVal! "beforeGold" before)
    |>.setObjVal! "runtime" (described.getObjValD "runtime")
    |>.setObjVal! "bodyReference" (toJson reference.toString)
    |>.setObjVal! "sameParentBody" (toJson true)
    |>.setObjVal! "actualHookCount" (toJson (1 : Nat))
    |>.setObjVal! "latencyComparisonMeasured" (toJson false)
    |>.setObjVal! "historyRoundRun" (toJson false)
    |>.setObjVal! "tokenImprovementMeasured" (toJson false)
    |>.setObjVal! "sustained80PersonWorkloadVerified" (toJson false)).pretty
  IO.FS.writeFile (candidate / "preparation.json") (Json.mkObj [
    ("reuse",← read (candidate / "hooks/candidate/preparation-reuse.json")),
    ("warm",← read (candidate / "hooks/candidate/warm/stdout")),
    ("wholeWarm",← read (candidate / "hooks/candidate/warm/record.json"))]).pretty
  let mut receipts := #[]
  for entry in ← (root / "carried-value-trial/candidate/data/receipts").readDir do
    if !(← (entry.path / "request.json").pathExists) then continue
    let request ← read (entry.path / "request.json")
    if (request.getObjValD "data").getObjValD "event" != toJson "UserPromptSubmit" then continue
    for item in ← entry.path.readDir do
      let name := item.fileName
      unless name.endsWith ".json" do continue
      let value ← read item.path
      let keep := name.startsWith "numerical-" || name == "canonical-source-reuse.json"
      receipts := receipts.push (Json.mkObj [("stage",toJson name),("observedMs",value.getObjValD "observedMs"),
        ("data",if keep then value.getObjValD "data" else Json.null)])
  IO.FS.writeFile (candidate / "receipt-timeline.json") (toJson receipts).pretty
  IO.FS.writeFile (candidate / "proof-axioms.txt") (← IO.FS.readFile
    (root / "carried-value-audit-build/tools_research_CarriedSelectionAudit-lean.stdout"))
  let mut deleted := #[]
  for path in [root / "metadata-profile-trial",root / "metadata-profile-hook-candidate-build",
      root / "metadata-profile-recovery-build",records / "hooks",root / "carried-value-trial",candidate / "hooks",
      root / "carried-value-audit-build",root / "carried-value-audit-core",root / "carried-value-hook-candidate-build"] do
    if ← path.pathExists then
      let (files,bytes) ← remove path
      deleted := deleted.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
  for name in ["MetadataProfileHook","MetadataNativeProfile","RecoverMetadataProfile"] do
    let path := root / "project-metadata-core/tools/research" / (name ++ ".lean")
    if ← path.pathExists then IO.FS.removeFile path
  for name in ["MetadataProfileHook","MetadataNativeProfile","RecoverMetadataProfile","CarriedValueHook"] do
    let path := root / "carried-value-core/tools/research" / (name ++ ".lean")
    if ← path.pathExists then IO.FS.removeFile path
  for path in inputs do ensure (← System.FilePath.pathExists path) "cleanup removed active native input"
  for (path,expected) in binaries do ensure ((← hash path) == expected) "cleanup changed product"
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "cleanup changed protected original"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("deleted",toJson deleted),
    ("retainedNativeInputs",toJson inputs.size),("sourceAndRuntimesUnchanged",toJson true),("compressedOrArchived",toJson false)]).pretty
  IO.FS.writeFile (candidate / "retired.json") (Json.mkObj [("sharedCleanupRecord",toJson (records / "retired.json").toString),
    ("sourceAndRuntimesUnchanged",toJson true),("compressedOrArchived",toJson false)]).pretty
  IO.println "Retained the completed hook and partial native observation; deleted ended profile DBs, caches, helpers and full samples"
