import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def sha (path : System.FilePath) : IO String := do
  let out ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (out.exitCode == 0) "cannot seal source-read-view evidence"
  return (out.stdout.splitOn " ").head!
private partial def removeTree (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do removeTree entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main (args : List String) : IO Unit := do
  if let ["inspect",path] := args then
    let rows ← IO.ofExcept ((← read (.mk path)).getArr?)
    let mut summary := #[]
    for row in rows do
      summary := summary.push (Json.mkObj [("subject",row.getObjValD "subject"),
        ("expected",row.getObjValD "expected"),("actual",row.getObjValD "actual"),
        ("complete",row.getObjValD "complete"),("orderedEqual",row.getObjValD "orderedEqual"),
        ("missing",toJson (← IO.ofExcept ((row.getObjValD "missing").getArr?)).size),
        ("extra",toJson (← IO.ofExcept ((row.getObjValD "extra").getArr?)).size)])
    IO.println (toJson summary).pretty
    return
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let target := project / "docs/candidates/source-read-view"
  if args == ["retire-runtimes"] then
    let inputManifest ← read (target / "manifest.json")
    let replay ← read (project / "docs/candidates/replay-cursor/manifest.json")
    let originals : Array (String × String) ← IO.ofExcept (inputManifest.getObjValAs? _ "protectedOriginals")
    let sealedInputs : Array Json ← IO.ofExcept (inputManifest.getObjValAs? _ "sealedInputs")
    let verify := do
      for (path,digest) in originals do check ((← sha (.mk path)) == digest) "protected original changed"
      for artifact in sealedInputs do
        let path ← IO.ofExcept (artifact.getObjValAs? String "path")
        check (toJson (← sha (.mk path)) == artifact.getObjValD "sha256") "sealed model input changed"
    verify
    let programs := #[("source-readview-build",inputManifest.getObjValD "nativeRuntimeSha256"),
      ("source-readview-actual-build",inputManifest.getObjValD "actualRuntimeSha256"),
      ("replay-cursor-build",replay.getObjValD "cursorRuntimeSha256"),
      ("replay-preparation-checks-build",replay.getObjValD "integrationRuntimeSha256")]
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    check (processes.exitCode == 0) "cannot check running native jobs"
    let mut retired := #[]
    for (name,digest) in programs do
      let path := root / name / "StudyMain"
      check (!(processes.stdout.splitOn "\n").any (·.startsWith path.toString)) "a retired native helper is still live"
      check ((← path.symlinkMetadata).type == .file && toJson (← sha path) == digest)
        "native helper differs from its retained execution evidence"
      let bytes := (← path.metadata).byteSize
      IO.FS.removeFile path
      retired := retired.push (Json.mkObj [("path",toJson path.toString),("sha256",digest),("bytes",toJson bytes)])
    verify
    IO.FS.writeFile (target / "retired-runtimes.json") (Json.mkObj [("executables",toJson retired),
      ("nativeObjectsAndInterfacesRetained",toJson true),("sealedModelInputsAndOriginalsUnchanged",toJson true),
      ("archiveCreated",toJson false)]).pretty
    IO.println "Four ended native diagnostic executables removed; link inputs and protected model inputs retained."
    return
  check args.isEmpty "expected no arguments, inspect PATH, or retire-runtimes"
  let core := root / "source-readview-core"
  IO.FS.createDirAll target
  let write := fun (name : String) (value : Json) => do
    let path := target / name
    if ← path.pathExists then check ((← read path) == value) "existing source-read-view evidence differs"
    else IO.FS.writeFile path value.pretty
  let native ← read (root / "source-readview-native3/result.json")
  check (native.getObjValD "completeOrderedCatalogEquality" == toJson true &&
    native.getObjValD "duplicatePublicationWrites" == toJson (0 : Nat) &&
    native.getObjValD "failedBatchPublishedRoots" == toJson (0 : Nat)) "native publication checks failed"
  let actual ← read (root / "source-readview-actual2/result.json")
  check (actual.getObjValD "completeOrderedCatalogEquality" == toJson true &&
    actual.getObjValD "originalFilesUnchanged" == toJson true &&
    actual.getObjValD "nativeOrigins" == toJson (89 : Nat)) "actual-source projection check failed"
  write "checks.json" native
  write "initial-checks.json" (← read (root / "source-readview-native2/result.json"))
  write "actual.json" actual
  write "negative-inspection.json" (← read (root / "source-readview-native/inspection.json"))
  write "negative-actual-summary.json" (← read (root / "source-readview-summary.stdout"))
  check ((← sha (target / "scattered-source.lean")) ==
    "ab772ec7e325bc87187f8fcbf05e35514747a9381319ded5aad0925fb745735c") "failed source witness differs"
  write "negative-actual.json" (Json.mkObj [
    ("runtimeSha256",toJson "634a45375dd216160d8e02a840fae8ca9561e38427a43b60ca1d37a8f5d650a1"),
    ("sourceSha256",toJson "ab772ec7e325bc87187f8fcbf05e35514747a9381319ded5aad0925fb745735c"),
    ("error",toJson "actual source-owned rows differ from the complete original catalog"),
    ("cause",toJson "30-second lookup of the large shared subject exhausted its deadline; bounded cache stopped admitting blocks and scattered owners revisited them"),
    ("diagnostic",toJson "Driver.cpp: expected 11521; returned 5803; complete=false; extra=0; every other subject matched"),
    ("oneSecondStackSample",Json.mkObj [("samples",toJson (542 : Nat)),
      ("rowBlockPayloadLoadSamples",toJson (342 : Nat)),
      ("stack",toJson "Reader.scan > Reader.row > MetadataBytes.get? > readPayloadUsing > readPinnedBlob > Blake3.hashSegments")]),
    ("fix",toJson "cluster postings by owner and row digest; rotate bounded decoded cache; restore canonical result order using precomputed keys")])
  write "negative.json" (Json.mkObj [("cause",toJson "compiler omitted aggregate located.read while retaining only originalRows"),
    ("diagnosticRuntimeSha256",toJson "08476e6ee2d381498a2f4f21e9bc44a7240d6fa2d308bb710c23f5958c6fb2c5"),
    ("initialFailureRuntimeSha256Retained",toJson false),
    ("failedSourceSha256",toJson "53f2d1427043a34dd0081f39dae6136b247170bddf3c84ae3e5a87ec637dfaa6"),
    ("failedSourceStampSha256",toJson "b1542fe030004356f7ea83f09396f5824d80891ef30c6779ff724c2a73ada334"),
    ("fix",toJson "compile both located.read and originalRows; deduplicate exact Read values")])
  let names := #["source-readview-compile","source-readview-compile2","source-readview-compile3",
    "source-readview-compile4","source-readview-compile5","source-readview-compile6",
    "source-readview-compile7","source-readview-compile8","source-readview-compile9","source-readview-compile10",
    "source-readview-compile11","source-readview-compile12","source-readview-compile13",
    "source-readview-compile14","source-readview-compile15","source-readview-compile16",
    "source-readview-checks","source-readview-inspect","source-readview-checks2",
    "source-readview-checks3","source-readview-actual-compile","source-readview-actual",
    "source-readview-actual-inspect","source-readview-summary",
    "source-readview-actual-compile2","source-readview-actual2"]
  let mut resources := #[]
  for name in names do
    let guard ← read (root / (name ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a source-read-view job is still live"
    if ["source-readview-compile16","source-readview-checks3","source-readview-actual-compile2","source-readview-actual2"].contains name then
      check (guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "guardTriggered" == toJson false) "the final native job failed"
    resources := resources.push (Json.mkObj [("name",toJson name),("guard",guard)])
  write "resources.json" (toJson resources)
  write "proof-axioms.json" (Json.mkObj [("output",toJson (← IO.FS.readFile
    (root / "source-readview-build/tools_research_SourceReadViewChecks-lean.stdout")))])
  let mut sources := #[]
  for name in ["Eggshell/SourceReadView","Eggshell/ObservedRecords","Eggshell/NativePublication",
      "tools/research/SourceReadViewChecks"] do
    let source := core / (name ++ ".lean")
    let objectName := name.replace "/" "_"
    let stamp ← IO.ofExcept ((← read (root / "source-readview-build" / (objectName ++ ".source"))).getArr?)
    check (stamp[0]? == some (toJson (← IO.FS.readFile source))) "source differs from its compiled input"
    sources := sources.push (name,← sha source,← sha (root / "source-readview-build" / (objectName ++ ".source")))
  let helper := project / "tools/research/SourceReadViewActual.lean"
  let actualStamp ← IO.ofExcept ((← read (root / "source-readview-actual-build/tools_research_SourceReadViewActual.source")).getArr?)
  check (actualStamp[0]? == some (toJson (← IO.FS.readFile helper)) &&
    (← sha helper) == (← sha (core / "tools/research/SourceReadViewActual.lean"))) "actual audit helper input differs"
  let sourceModule := core / "Eggshell/SourceReadView.lean"
  IO.FS.writeFile (target / "SourceReadView.lean") (← IO.FS.readFile sourceModule)
  for name in ["ObservedRecords","NativePublication"] do
    let before := root / "read-preparation-core/Eggshell" / (name ++ ".lean")
    let after := core / "Eggshell" / (name ++ ".lean")
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u","--label","a/Eggshell/" ++ name ++ ".lean",
      "--label","b/Eggshell/" ++ name ++ ".lean",before.toString,after.toString]}
    check (patch.exitCode == 1 && !patch.stdout.isEmpty && patch.stderr.isEmpty) "candidate patch is missing"
    IO.FS.writeFile (target / (name ++ ".patch")) patch.stdout
  let mut originalInputs : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let actualFiles : Array (String × String) ← IO.ofExcept (actual.getObjValAs? _ "originalFiles")
  for (name,digest) in actualFiles do
    originalInputs := originalInputs.push ((root / "study/seed-2-isolated/work.egg" / name).toString,digest)
  for (path,digest) in originalInputs do check ((← sha (.mk path)) == digest) "protected original changed"
  let plan ← read (root / "seed-1.plan.json")
  let mut sealedInputs ← IO.ofExcept (plan.getObjValAs? (Array Json) "harness")
  for field in ["runtime","runner"] do sealedInputs := sealedInputs.push (plan.getObjValD field)
  for artifact in sealedInputs do
    let path ← IO.ofExcept (artifact.getObjValAs? String "path")
    check (toJson (← sha (.mk path)) == artifact.getObjValD "sha256") "sealed runtime or harness input changed"
  write "manifest.json" (Json.mkObj [("nativeRuntimeSha256",toJson (← sha (root / "source-readview-build/StudyMain"))),
    ("actualRuntimeSha256",toJson (← sha (root / "source-readview-actual-build/StudyMain"))),
    ("sourcesAndInputStamps",toJson sources),("actualAuditSourceSha256",toJson (← sha helper)),
    ("protectedOriginals",toJson originalInputs),("sealedInputs",toJson sealedInputs),
    ("answeringModelCalls",toJson (0 : Nat)),("productionRuntimeChanged",toJson false),
    ("journalReadPathIntegrated",toJson false),("tokenImprovementMeasured",toJson false),("adopted",toJson false)])
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0 && !(processes.stdout.splitOn "\n").any (fun line =>
    line.startsWith (root / "source-readview-build/StudyMain").toString ||
    line.startsWith (root / "source-readview-actual-build/StudyMain").toString)) "audit is still live"
  for name in ["source-readview-native","source-readview-native2","source-readview-native3",
      "source-readview-actual","source-readview-actual2"] do
    removeTree (root / name)
  for suffix in ["stdout","stderr"] do
    for name in names do
      let path := root / (name ++ "." ++ suffix)
      if ← path.pathExists then IO.FS.removeFile path
  for name in ["source-readview-actual-inspect.sample.txt","source-readview-sample.stdout","source-readview-sample.stderr"] do
    let path := root / name
    if ← path.pathExists then IO.FS.removeFile path
  for (path,digest) in originalInputs do check ((← sha (.mk path)) == digest) "cleanup changed a protected original"
  for artifact in sealedInputs do
    let path ← IO.ofExcept (artifact.getObjValAs? String "path")
    check (toJson (← sha (.mk path)) == artifact.getObjValD "sha256") "cleanup changed a sealed input"
  write "cleanup.json" (Json.mkObj [("endedAuditDatabasesCachesAndFullLogsRemoved",toJson true),
    ("currentCandidateCoreAndBuildDependenciesRetained",toJson true),
    ("protectedInputsUnchanged",toJson true),("archiveCreated",toJson false)])
  IO.println "Source-owned read view: native and actual-input equality retained; ended audit data removed."
