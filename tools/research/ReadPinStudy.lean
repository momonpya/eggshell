import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.ReadPinStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"search-read-build"
def source := base/"pinned-reads-source"
def target := base/"pinned-reads-build"
def study := workspace/"docs/candidates/pinned-reads"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def drained : IO Unit := do
  let all ← command "/bin/ps" #["-axo","command="]
  check (!(all.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native guard active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "pinned-reads-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "previous native process not drained"
def refresh : IO Unit := do
  drained
  for name in ["PinnedReads","PinnedReadsChecks"] do
    let relative := "tools/research/"++name++".lean"
    IO.FS.writeFile (source/relative) (← IO.FS.readFile (workspace/relative))
def connectControls : IO Unit := do
  drained
  let path := source/"tools/research/RuntimeReadControls.lean"
  let before ← IO.FS.readFile path
  check (!before.contains "readPinnedSourceViews") "pin connection audit already updated"
  let after := before.replace
    "(← body ``readSourceViews).getUsedConstants.contains ``withBatchSource"
    "(← body ``readSourceViews).getUsedConstants.contains ``readPinnedSourceViews &&\n      (← body ``readPinnedSourceViews).getUsedConstants.contains ``withPinnedSource"
  let after := after.replace "let mut pending := [``withBatchSource]" "let mut pending := [``withPinnedSource]"
  let after := after.replace "(``readSourceViews,``SharedReadViews.View.project)" "(``readPinnedSourceViews,``SharedReadViews.View.project)"
  let after := after.replace "(``readSourceViews,``SharedReadViews.Pool.borrow?)" "(``readPinnedSourceViews,``SharedReadViews.Pool.borrow?)"
  let after := after.replace "(``readSourceViews,``withBatchSource)"
    "(``readPinnedSourceViews,``withPinnedSource),\n      (``readSourceViews,``CanonicalSource.Leases.PinnedReads.withBatch),\n      (``readSourceViews,``readPinnedSourceViews),\n      (``withPinnedSource,``CanonicalSource.Leases.PinnedReads.resolve)"
  check (after != before) "missing old direct-call audit"
  IO.FS.writeFile path after
def prepare : IO Unit := do
  drained
  let sha := ((← command "/usr/bin/shasum" #["-a","256",(parent/"StudyMain").toString]).splitOn " ").headD ""
  check (sha == "54f6020654cfe694a7d0a642b02436d37759c269851b7322e4c4a45d55119556") "frozen parent changed"
  check (!(← source.pathExists)) "new isolated source required"
  IO.FS.createDirAll study
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.ReplayReadinessChecks",(base/"pinned-reads-settings.json").toString]
  refresh
  let service := source/"Eggshell/PublicationService.lean"
  let before ← IO.FS.readFile service
  check (!before.contains "PinnedReads.withBatch") "do not reimplement an existing pin boundary"
  let helper := "def batchPinRequests (entries : Array (ReadBoundary.Entry sources)) : List CanonicalSource.Leases.PinnedReads.Request :=\n"++
    "  entries.toList.filterMap fun entry => entry.request.retained.map fun token =>\n"++
    "    ⟨token,entry.request.access.scope,entry.request.access.source,entry.request.access.metadata⟩\n\n"++
    "def withPinnedSource (server : Server) (pins : List CanonicalSource.Leases.PinnedReads.Pin)\n"++
    "    (entry : ReadBoundary.Entry sources) (deadline : Nat)\n"++
    "    (use : CanonicalSource.Shared.Loaded → CanonicalSource.Shared.Reuse → IO α) : IO α := do\n"++
    "  if let some token := entry.request.retained then\n"++
    "    let request : CanonicalSource.Leases.PinnedReads.Request :=\n"++
    "      ⟨token,entry.request.access.scope,entry.request.access.source,entry.request.access.metadata⟩\n"++
    "    let checked ← IO.ofExcept (CanonicalSource.Leases.PinnedReads.resolve pins request (← IO.monoMsNow))\n"++
    "    return ← use checked.loaded .hit\n"++
    "  withBatchSource server entry deadline use\n\n"
  let start := "/-- First count cached metadata under short borrows."
  let [front,tail] := before.splitOn start | throw (IO.userError "unique batch implementation required")
  let [body,after] := tail.splitOn "def sourcePalettes " | throw (IO.userError "unique batch end required")
  let body := body.replace "  let authorized ← authorizeBatch server secret requests\n" ""
  let body := body.replace "    (deadline : Nat) : IO SourceViewBatch.Palette := do"
    "    (deadline : Nat) (authorized : ReadBoundary.Batch secret requests)\n    (pins : List CanonicalSource.Leases.PinnedReads.Pin) : IO SourceViewBatch.Palette := do"
  let body := body.replace "def readSourceViews " "def readPinnedSourceViews "
  let body := body.replace "withBatchSource server entry deadline" "withPinnedSource server pins entry deadline"
  let wrapper := "def readSourceViews (server : Server) (secret : String) (requests : Array SourceViewBatch.Request)\n"++
    "    (deadline : Nat) : IO SourceViewBatch.Palette := do\n"++
    "  let authorized ← authorizeBatch server secret requests\n"++
    "  CanonicalSource.Leases.PinnedReads.withBatch server.retained (batchPinRequests authorized.entries) deadline fun batch =>\n"++
    "    readPinnedSourceViews server secret requests deadline authorized batch.pins\n\n"
  let comment := "/-- Pin retained descriptors once at the operation boundary. These arenas are\n"++
    "already resident and charged; the batch never loads or waits for another\n"++
    "arena. Geometry still enters only after the existing reply reservation. -/\n"
  -- Keep the body after its declaration, without the obsolete short-borrow comment.
  let [_,decl] := body.splitOn "def readPinnedSourceViews " | throw (IO.userError "pinned declaration missing")
  let result := front++helper++comment++"def readPinnedSourceViews "++decl++wrapper++"def sourcePalettes "++after
  IO.FS.writeFile service (result.replace "public import tools.research.ReadBoundary"
    "public import tools.research.ReadBoundary\npublic import tools.research.PinnedReads")
  let main := source/"tools/research/ReplayReadinessChecks.lean"
  let before ← IO.FS.readFile main
  IO.FS.writeFile main ((before.replace "import tools.research.SearchReadChecks"
    "import tools.research.SearchReadChecks\nimport tools.research.PinnedReadsChecks").replace
    "  match args with\n" "  match args with\n  | [\"pinned-reads-check\",root] => Eggshell.Research.PinnedReadsChecks.run (.mk root); return 0\n")
  connectControls
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"pinned-reads-settings.json").toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
        "pinned-reads-check",(base/(tag++"-result")).toString]
    | "typed-checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
        "combined-read-check",(base/(tag++"-result")).toString]
    | _ => throw (IO.userError "unknown action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def record (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "native read controls must complete before recording success"
  write (study/"controls.json") (← read (base/(tag++"-result/report.json")))
  for name in ["pinned-reads-build1","pinned-reads-build2","pinned-reads-build3",tag] do
    write (study/(name++".guard.json")) (← read (base/(name++".guard.json")))
  for relative in ["Eggshell/PublicationService.lean","tools/research/RuntimeReadControls.lean",
      "tools/research/ReplayReadinessChecks.lean"] do
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"search-read-source"/relative).toString,(source/relative).toString]}
    check (patch.exitCode == 1) "declared source patch missing"
    IO.FS.writeFile (study/(relative.replace "/" "_"++".patch")) patch.stdout
  let kernel ← IO.FS.readFile (target/"tools_research_PinnedReadsChecks-lean.stdout")
  check (!kernel.contains "sorryAx" && !kernel.contains "error:" && kernel.contains "558 pure source-resolution dependencies")
    "retain the exact pure dependency and axiom audit"
  IO.FS.writeFile (study/"kernel-audit.txt") kernel
  IO.FS.writeFile (study/"runtime-kernel-audit.txt") (← IO.FS.readFile (target/"tools_research_RuntimeReadControls-lean.stdout"))
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.PublicationService","tools.research.RuntimeReadControls",
    "+tools.research.PinnedReads","+tools.research.PinnedReadsChecks"]
  write (study/"runtime.json") (Json.mkObj [("parentSha256",(← read (study/"native-sources.json")).getObjValD "parentRuntimeSha256"),
    ("sha256",(← read (study/"native-sources.json")).getObjValD "candidateRuntimeSha256"),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18"),
    ("fullHookRepetitions",toJson (0 : Nat)),("replyFrameBlockerResolved",toJson false)])
def recordTyped (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "ordinary typed and wire controls did not complete"
  write (study/(tag++".guard.json")) guard
  for (file,name) in [("report.json","typed-controls.json"),("shared-eighty.json","shared-eighty.json"),
      ("held-lock-reads.json","held-lock-reads.json"),("read-boundary.json","read-boundary.json"),
      ("borrow-checks/report.json","scalar-borrow-controls.json"),("probe-checks.json","probe-controls.json")] do
    write (study/name) (← read (base/(tag++"-result")/file))
def cleanControls : IO Unit := do
  drained
  let controls ← read (study/"controls.json")
  let typed ← read (study/"typed-controls.json")
  check (controls.getObjValD "originalHeadUnchanged" == toJson true &&
    typed.getObjValD "originalHeadsUnchanged" == toJson true &&
    typed.getObjValD "allReservationsReleased" == toJson true) "preserve source integrity and cleanup receipts first"
  let mut removed := #[]
  for name in ["pinned-reads-checks1-result","pinned-reads-typed1-result"] do
    let path := base/name
    if ← path.pathExists then
      IO.FS.removeDirAll path
      removed := removed.push path.toString
  write (study/"cleanup.json") (Json.mkObj [("removedEndedControlRoots",toJson removed),
    ("archivesCreated",toJson false),("currentReproducerAndNativeDependenciesRetained",toJson true)])
def recordRealSource : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/real-source-search-read"
  let original := base/"real-source-search-read-trial-result"
  let diagnostic := base/"real-source-reply-footprint-result"
  let receipt ← read (diagnostic/"receipt.json")
  let stages ← IO.ofExcept (receipt.getObjValAs? (Array Json) "stages")
  let some sizing := stages.find? (fun stage =>
    (stage.getObjValAs? String "name").toOption.any (·.contains "reply-sizing")) |
    throw (IO.userError "measured reply-sizing receipt missing")
  let sizing := (sizing.getObjValD "record").getObjValD "data"
  check (sizing.getObjValD "payloadBytes" == toJson (13420015 : Nat) &&
    sizing.getObjValD "fitsFrame" == toJson false) "actual reply-size witness changed"
  write (destination/"failure.json") (Json.mkObj [("actualTrialProgress",← read (original/"progress.json")),
    ("diagnostic",← read (diagnostic/"result.json")),("replySizing",sizing),
    ("internalNecessaryEvidenceCoverageAudited",toJson false),("adopted",toJson false),
    ("paidComparisons",toJson "0/18")])
  for name in ["real-source-search-read-build1","real-source-search-read-build2","real-source-search-read-freeze1",
      "real-source-search-read-install1","real-source-search-read-run1","real-source-reply-footprint-build1",
      "real-source-reply-footprint-helper1","real-source-reply-footprint-helper2","real-source-reply-footprint-helper3",
      "real-source-reply-footprint-install1","real-source-reply-footprint-probe1"] do
    let guard ← read (base/(name++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "do not record a still-running real-source actor as stopped"
    write (destination/(name++".guard.json")) guard
  let relative := "Eggshell/OperationPool.lean"
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
    (base/"search-read-source"/relative).toString,(base/"real-source-reply-footprint-source"/relative).toString]}
  check (patch.exitCode == 1) "diagnostic-only actual product patch missing"
  IO.FS.writeFile (destination/"reply-footprint.patch") patch.stdout
def retireOldPreflight : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/real-source-read-runtime"
  for name in ["real-source-auditor-build1","real-source-auditor-build2","real-source-auditor-build3",
      "real-source-freeze1","real-source-install1"] do
    let guard ← read (base/(name++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "old preflight still owns processes"
    write (destination/(name++".guard.json")) guard
  let process ← command "/bin/ps" #["-axo","command="]
  let directories := ["real-source-trial1-result","real-source-prefix","real-source-empty-account"]
  for name in directories ++ ["real-source-auditor-build/StudyMain"] do
    check (!(process.splitOn "\n").any (·.contains (base/name).toString)) "obsolete preflight is still running"
  let mut removed := #[]
  for name in directories do
    let path := base/name
    if ← path.pathExists then
      -- rm does not follow the old prefix's model symlink.
      discard <| command "/bin/rm" #["-rf","--",path.toString]
      removed := removed.push path.toString
  let executable := base/"real-source-auditor-build/StudyMain"
  let sha ← if ← executable.pathExists then do
      let sha := ((← command "/usr/bin/shasum" #["-a","256",executable.toString]).splitOn " ").headD ""
      IO.FS.removeFile executable
      removed := removed.push executable.toString
      pure (toJson sha)
    else pure Json.null
  write (destination/"cleanup.json") (Json.mkObj [("removed",toJson removed),("removedExecutableSha256",sha),
    ("hookRuns",toJson (0 : Nat)),("archivesCreated",toJson false),("nativeObjectAndInterfaceDependenciesRetained",toJson true)])
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["refresh"] => refresh
  | ["connect-controls"] => connectControls
  | ["setup",action,tag] => setup action tag
  | ["record",tag] => record tag
  | ["record-typed",tag] => recordTyped tag
  | ["clean-controls"] => cleanControls
  | ["record-real-source"] => recordRealSource
  | ["retire-old-preflight"] => retireOldPreflight
  | _ => throw (IO.userError "prepare|refresh|setup action tag")
end Eggshell.Research.ReadPinStudy
def main := Eggshell.Research.ReadPinStudy.main
