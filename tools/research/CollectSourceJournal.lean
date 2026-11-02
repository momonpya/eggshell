import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def sha (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal source-journal evidence"
  return (result.stdout.splitOn " ").head!
private partial def removeTree (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do removeTree entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let core := root / "source-journal-core"
  let target := project / "docs/candidates/source-journal"
  IO.FS.createDirAll target
  let write := fun (name : String) (value : Json) => do
    let path := target / name
    if ← path.pathExists then check ((← read path) == value) "retained source-journal evidence differs"
    else IO.FS.writeFile path value.pretty
  let native ← read (root / "source-journal-native2/result.json")
  for field in ["acknowledgedReadNotLabelledMissing","unconfirmedKnowledgeNotLabelledMissing",
      "changedFingerprintNotLabelledMissing","preReadExcludesLaterOriginal"] do
    check (native.getObjValD field == toJson true) "native source-history control failed"
  check ((native.getObjValAs? Nat "omittedThenRead").toOption.getD 0 > 0) "native usage signal is empty"
  let actual ← read (root / "source-journal-actual/result.json")
  check (actual.getObjValD "completeOrderedCatalogEquality" == toJson true &&
    actual.getObjValD "readRows" == toJson (34534 : Nat) &&
    actual.getObjValD "journalStoredReadPathIntegrated" == toJson true &&
    actual.getObjValD "originalFilesUnchanged" == toJson true) "actual journal lookup audit failed"
  write "checks.json" native
  write "initial-checks.json" (← read (root / "source-journal-native/result.json"))
  write "actual.json" actual
  let names := #["source-journal-compile","source-journal-compile2","source-journal-compile3",
    "source-journal-compile4","source-journal-compile5","source-journal-compile6",
    "source-journal-compile7","source-journal-compile8","source-journal-compile9","source-journal-checks","source-journal-checks2",
    "source-journal-actual-compile","source-journal-actual"]
  let mut resources := #[]
  let mut failures := #[]
  for name in names do
    let guard ← read (root / (name ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "native source-history job is still live"
    if ["source-journal-compile9","source-journal-checks2","source-journal-actual-compile","source-journal-actual"].contains name then
      check (guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "guardTriggered" == toJson false) "final source-history native job failed"
    else if guard.getObjValD "exitCode" != toJson (0 : Nat) then
      let output ← IO.FS.readFile (root / (name ++ ".stderr"))
      failures := failures.push (Json.mkObj [("name",toJson name),("guard",guard),
        ("diagnostics",toJson (output.splitOn "\n" |>.filter (fun line =>
          (line.splitOn "error").length > 1 || line.startsWith "Source boundary" ||
          line.startsWith "  file:" || line.startsWith "no such file")))])
    resources := resources.push (Json.mkObj [("name",toJson name),("guard",guard)])
  write "resources.json" (toJson resources)
  write "negative-builds.json" (Json.mkObj [("attempts",toJson failures),
    ("initialObjectMapUtilityFailure",toJson "relative parent path did not match absolute manifest output; map absent, initial build failed before source compilation"),
    ("initialRuntimeSha256",toJson "2d48855c92f7af449549b81596b30b377f8d8c1b6118eeb97fda69ddf6faa62b"),
    ("initialMainInputStampSha256",toJson "53017d5e17a65c147e9a291d29881a8bb57d0b3bf62a9e85d1120c5248162be7")])
  let auditPath := root / "source-journal-build/Eggshell_ContractAudit-lean.stdout"
  let audit ← IO.FS.readFile auditPath
  check ((audit.splitOn "Audited all source dependency boundaries").length == 2 &&
    (audit.splitOn "Audited generated authority and non-retrieved local origins").length == 2 &&
    !(audit.splitOn "\n").any (fun line => (line.splitOn "error:").length > 1)) "full ContractAudit did not pass"
  write "proof-axioms.json" (Json.mkObj [("fullAuditOutputSha256",toJson (← sha auditPath)),
    ("fullAuditMessages",toJson (audit.splitOn "\n" |>.filter (·.startsWith "Audited ") |>.length)),
    ("sourceBoundaryAudit",toJson "all required and forbidden declaration dependencies checked, including Journal.storedReadsAt?"),
    ("mainOutput",toJson (← IO.FS.readFile (root / "source-journal-build/tools_research_SourceJournalChecks-lean.stdout")))])
  let mut sourceInputs := #[]
  for name in ["StoredReadLookup","SynapseJournal","UsageCache","ContractAudit"] do
    let source := core / "Eggshell" / (name ++ ".lean")
    let input := root / "source-journal-build" / ("Eggshell_" ++ name ++ ".source")
    let stamp ← IO.ofExcept ((← read input).getArr?)
    check (stamp[0]? == some (toJson (← IO.FS.readFile source))) "source-history module differs from compiled input"
    sourceInputs := sourceInputs.push (name,← sha source,← sha input)
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label","a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",(root / "source-readview-core/Eggshell" / (name ++ ".lean")).toString,source.toString]}
    check (patch.exitCode == 1 && patch.stderr.isEmpty && !patch.stdout.isEmpty) "candidate source-history patch missing"
    IO.FS.writeFile (target / (name ++ ".patch")) patch.stdout
  for (name,build) in [("SourceJournalChecks","source-journal-build"),("SourceJournalActual","source-journal-actual-build")] do
    let source := project / "tools/research" / (name ++ ".lean")
    let input := root / build / ("tools_research_" ++ name ++ ".source")
    let stamp ← IO.ofExcept ((← read input).getArr?)
    check (stamp[0]? == some (toJson (← IO.FS.readFile source)) &&
      (← sha source) == (← sha (core / "tools/research" / (name ++ ".lean")))) "audit helper differs from native executable input"
    sourceInputs := sourceInputs.push (name,← sha source,← sha input)
  let parent ← read (project / "docs/candidates/source-read-view/manifest.json")
  let originals : Array (String × String) ← IO.ofExcept (parent.getObjValAs? _ "protectedOriginals")
  let sealedInputs : Array Json ← IO.ofExcept (parent.getObjValAs? _ "sealedInputs")
  let verify := do
    for (path,digest) in originals do check ((← sha (.mk path)) == digest) "protected original changed"
    for artifact in sealedInputs do
      let path ← IO.ofExcept (artifact.getObjValAs? String "path")
      check (toJson (← sha (.mk path)) == artifact.getObjValD "sha256") "sealed model input changed"
  verify
  let mut unchanged := #[]
  for name in ["Handoff","LexicalAdvice","CanonicalSourceCache","NativePublication","SourceReadView"] do
    let source := core / "Eggshell" / (name ++ ".lean")
    check ((← sha source) == (← sha (root / "source-readview-core/Eggshell" / (name ++ ".lean")))) "unrelated product function changed"
    unchanged := unchanged.push (name,← sha source)
  let mut programs := #[]
  for name in ["source-journal-build","source-journal-actual-build"] do
    let path := root / name / "StudyMain"
    programs := programs.push (path.toString,← sha path,(← path.metadata).byteSize)
  write "manifest.json" (Json.mkObj [("sourcesAndInputStamps",toJson sourceInputs),("runtimes",toJson programs),
    ("unchangedRenderingLexicalPublicationAndProjectionSources",toJson unchanged),
    ("protectedOriginals",toJson originals),("sealedInputs",toJson sealedInputs),
    ("answeringModelCalls",toJson (0 : Nat)),("entire89OperationReplayValidated",toJson false),
    ("turnCheckpointChanged",toJson false),("tokenImprovementMeasured",toJson false),("adopted",toJson false)])
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0) "cannot check native audit processes"
  for (path,_,_) in programs do
    check (!(processes.stdout.splitOn "\n").any (·.startsWith path)) "native helper is still running"
  for name in ["source-journal-native","source-journal-native2","source-journal-actual"] do removeTree (root / name)
  for (path,digest,_) in programs do
    check ((← sha (.mk path)) == digest) "ended native executable changed before retirement"
    IO.FS.removeFile (.mk path)
  for suffix in ["stdout","stderr"] do
    for name in names do
      let path := root / (name ++ "." ++ suffix)
      if ← path.pathExists then IO.FS.removeFile path
  verify
  write "cleanup.json" (Json.mkObj [("endedAuditDatabasesCachesAndFullLogsRemoved",toJson true),
    ("endedNativeExecutablesRemoved",toJson (2 : Nat)),("objectsInterfacesAndCurrentCandidateCoreRetained",toJson true),
    ("protectedInputsUnchanged",toJson true),("archiveCreated",toJson false)])
  IO.println "Source-journal checks and actual catalog equality retained; ended audit data and native helpers removed."
