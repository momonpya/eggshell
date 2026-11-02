import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def sha (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash frozen-post evidence"
  return (result.stdout.splitOn " ").headD ""
private partial def removeTree (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do removeTree entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path
private def without (object : Json) (field : String) : IO Json := do
  return Json.obj ((← IO.ofExcept object.getObj?).erase field)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let core := root / "frozen-post-core"
  let target := project / "docs/candidates/frozen-post"
  IO.FS.createDirAll target
  let write := fun (name : String) (value : Json) => do
    let path := target / name
    if ← path.pathExists then check ((← read path) == value) "retained frozen-post evidence differs"
    else IO.FS.writeFile path value.pretty
  let native ← read (root / "frozen-post-native/result.json")
  for name in ["postCatalogUnchangedByLaterSupplement","allReplayFactsAndStatusUnchanged",
      "foreignSourceGainsNoPublicAuthority"] do
    check (native.getObjValD name == toJson true) "native frozen-post control failed"
  check (native.getObjValD "nativeConsumed" == toJson (1 : Nat) &&
    native.getObjValD "foreignPublicationPendingBefore" == toJson (1 : Nat) &&
    native.getObjValD "foreignPublicationPendingAfter" == toJson (0 : Nat)) "native test did not exercise actual debt"
  write "checks.json" native
  let parent ← read (root / "frozen-replay-parent.json")
  let actual ← read (root / "frozen-replay-candidate.json")
  check (actual.getObjValD "input" == parent.getObjValD "input" &&
    actual.getObjValD "replay" == parent.getObjValD "replay" &&
    actual.getObjValD "exactParentInputFactsAndStatus" == toJson true &&
    actual.getObjValD "inputUnchanged" == toJson true &&
    parent.getObjValD "inputUnchanged" == toJson true) "full native replay changed input or result"
  write "actual.json" actual
  write "parent-summary.json" (← without parent "replay")
  let legacy ← read (root / "seed-2-replay-readonly.json")
  let oldUsage : Array Json ← IO.ofExcept (legacy.getObjValAs? _ "usage")
  let citations := oldUsage.filter fun fact =>
    ((fact.getObjValD "used").getObjValD "usage").getObjValD "kind" == toJson "deliveredThenCited"
  let rereads := oldUsage.filter fun fact =>
    ((fact.getObjValD "used").getObjValD "usage").getObjValD "kind" == toJson "reread"
  let replay := actual.getObjValD "replay"
  check (legacy.getObjValD "consumed" == replay.getObjValD "consumed" &&
    toJson citations == replay.getObjValD "usage" && rereads.size == 197) "legacy replay gap was not preserved exactly"
  write "legacy-gap.json" (Json.mkObj [("sameConsumedFacts",toJson true),
    ("sameCitationLabels",toJson true),("oldUsage",toJson oldUsage.size),
    ("remainingUsage",toJson citations.size),("missingRereadLabels",toJson rereads.size),
    ("oldUnknown",legacy.getObjValD "unknown"),("newUnknown",replay.getObjValD "unknown"),
    ("oldReferenceFullyEquivalent",toJson false),("historicalReadViewsBackfilled",toJson false),
    ("replayTimeIsNotDeliveryOrTokenImprovement",toJson true)])
  let jobs := #["frozen-post-compile","frozen-post-compile-repair","frozen-post-checks",
    "frozen-replay-parent-compile","frozen-replay-parent","frozen-replay-candidate-compile","frozen-replay-candidate"]
  let mut resources := #[]
  for job in jobs do
    let guard ← read (root / (job ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "audit job has no terminal record"
    if job != "frozen-post-compile" then
      check (guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "guardTriggered" == toJson false) "final audit job failed"
    resources := resources.push (Json.mkObj [("name",toJson job),("guard",guard)])
  write "resources.json" (toJson resources)
  write "negative-builds.json" (Json.mkObj [
    ("initialHelperError",toJson "Lean reserved identifier partial; renamed capturedPartial before the successful native build"),
    ("guardReuseRejectedBeforeSpawn",toJson "Existing guard record cannot be reused; a new record was selected"),
    ("collectorCleanupElaboration",toJson "An implicit String pattern argument required an explicit lambda; the final collector passed Lean elaboration"),
    ("objectMapElaborationMemoryLimit",toJson "Metadata helper failed at -M512; succeeded at the established -M1024; no product input was mutated")])
  let auditPath := root / "frozen-post-build/Eggshell_ContractAudit-lean.stdout"
  let audit ← IO.FS.readFile auditPath
  check ((audit.splitOn "Audited all source dependency boundaries").length == 2 &&
    (audit.splitOn "Audited generated authority and non-retrieved local origins").length == 2 &&
    !(audit.splitOn "\n").any (fun row => (row.splitOn "error:").length > 1)) "full ContractAudit did not pass"
  write "audit.json" (Json.mkObj [("sha256",toJson (← sha auditPath)),
    ("messages",toJson (audit.splitOn "\n" |>.filter (·.startsWith "Audited ") |>.length)),
    ("historicalPostCannotReachSupplementOrIndexLoader",toJson true),
    ("ioRefinementOrDeliveryGuaranteeProved",toJson false)])
  let mut inputs := #[]
  for name in ["ContentMetadata","SourceReadView","SynapseJournal","ReplayPreparation","ContractAudit"] do
    let path := core / "Eggshell" / (name ++ ".lean")
    let stampPath := root / "frozen-post-build" / ("Eggshell_" ++ name ++ ".source")
    check ((← read stampPath).getArr?.toOption.bind (·[0]?) == some (toJson (← IO.FS.readFile path)))
      "candidate differs from actual native compilation input"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label","a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",(root / "source-journal-core/Eggshell" / (name ++ ".lean")).toString,path.toString]}
    check (patch.exitCode == 1 && patch.stderr.isEmpty && !patch.stdout.isEmpty) "missing frozen-post patch"
    IO.FS.writeFile (target / (name ++ ".patch")) patch.stdout
    inputs := inputs.push (name,← sha path,← sha stampPath)
  for (name,build) in [("FrozenPostChecks","frozen-post-build"),("FrozenReplayAudit","frozen-replay-parent-build"),
      ("FrozenReplayAudit","frozen-replay-candidate-build")] do
    let path := project / "tools/research" / (name ++ ".lean")
    let stamp := root / build / ("tools_research_" ++ name ++ ".source")
    check ((← read stamp).getArr?.toOption.bind (·[0]?) == some (toJson (← IO.FS.readFile path)))
      "helper differs from actual native input"
    inputs := inputs.push (name ++ ":" ++ build,← sha path,← sha stamp)
  let inherited ← read (project / "docs/candidates/source-journal/manifest.json")
  let originals : Array (String × String) ← IO.ofExcept (inherited.getObjValAs? _ "protectedOriginals")
  let sealedInputs : Array Json ← IO.ofExcept (inherited.getObjValAs? _ "sealedInputs")
  let verify := do
    for (path,digest) in originals do check ((← sha (.mk path)) == digest) "protected original changed"
    for artifact in sealedInputs do
      let path ← IO.ofExcept (artifact.getObjValAs? String "path")
      check (toJson (← sha (.mk path)) == artifact.getObjValD "sha256") "sealed model input changed"
  verify
  let mut programs := #[]
  let mut builds := #[]
  for name in ["frozen-post-build","frozen-replay-parent-build","frozen-replay-candidate-build"] do
    let path := root / name / "StudyMain"
    programs := programs.push (path.toString,← sha path,(← path.metadata).byteSize)
    builds := builds.push (← read (root / name / "build.json"))
  write "builds.json" (toJson builds)
  write "manifest.json" (Json.mkObj [("sourcesAndInputStamps",toJson inputs),("runtimes",toJson programs),
    ("protectedOriginals",toJson originals),("sealedInputs",toJson sealedInputs),
    ("closedTurnCheckpointChanged",toJson false),("ackProjectionPublishedWithDelivery",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),("adopted",toJson false)])
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot check audit processes"
  for (path,_,_) in programs do
    check (!(processes.stdout.splitOn "\n").any (·.startsWith path)) "native helper remains live"
  removeTree (root / "frozen-post-native")
  for (path,digest,_) in programs do
    check ((← sha (.mk path)) == digest) "ended executable changed"
    IO.FS.removeFile (.mk path)
  -- Cached native reuse needs objects, interfaces and input/dependency stamps,
  -- not generated C or compiler stdout/stderr. A rebuild regenerates them.
  for name in ["frozen-post-build","frozen-replay-parent-build","frozen-replay-candidate-build"] do
    for entry in ← (root / name).readDir do
      if [".c",".stdout",".stderr"].any (fun suffix => entry.fileName.endsWith suffix) then
        check ((← entry.path.symlinkMetadata).type == .file) "compiler output is not a regular file"
        IO.FS.removeFile entry.path
  for path in ["frozen-replay-parent.json","frozen-replay-candidate.json",
      "frozen-replay-parent.json.progress.json","frozen-replay-candidate.json.progress.json"] do
    IO.FS.removeFile (root / path)
  for job in jobs do
    for suffix in ["stdout","stderr"] do
      let path := root / (job ++ "." ++ suffix)
      if ← path.pathExists then IO.FS.removeFile path
  verify
  write "cleanup.json" (Json.mkObj [("endedAuditDbCacheAndFullLogsRemoved",toJson true),
    ("endedExecutablesRemoved",toJson (3 : Nat)),("protectedInputsUnchanged",toJson true),
    ("generatedCAndCompilerLogsRemoved",toJson true),
    ("objectAndInterfaceParentsRetained",toJson true),("archiveCreated",toJson false)])
  IO.println "Frozen native post, foreign pending retry and full parent replay equality retained; legacy reread gap remains unadopted."
