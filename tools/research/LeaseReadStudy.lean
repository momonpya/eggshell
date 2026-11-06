import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.LeaseReadStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"replay-readiness-build"
def source := base/"lease-read-source"
def target := base/"lease-read-build"
def study := workspace/"docs/candidates/lease-read"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native guard still active"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "lease-read-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "lease read guard not terminal"

def laws := "
/-- A checked request-local borrow of the immutable descriptor fields.
Validation and this state transition are pure; IO remains at the pool boundary. -/
structure ReadCut (state : State) (token scope : String) (source : PageMap.Head)
    (metadata : Cache.Manifest) (now deadline : Nat) where
  held : Held
  descriptor : Descriptor
  registered : state.entries[token]? = some held
  bound : state.descriptors[held.descriptor]? = some descriptor
  accepted : (!state.closed && !held.released && now < held.deadline && now < deadline &&
    descriptor.accepts scope source metadata) = true

def ReadCut.next (cut : ReadCut state token scope source metadata now deadline) : State :=
  {state with entries := state.entries.insert token {cut.held with readers := cut.held.readers+1}}

theorem ReadCut.live (cut : ReadCut state token scope source metadata now deadline) :
    state.closed = false ∧ cut.held.released = false ∧ now < cut.held.deadline ∧ now < deadline := by
  have h := cut.accepted
  simp only [Bool.and_eq_true,Bool.not_eq_true',decide_eq_true_eq] at h
  exact ⟨h.1.1.1.1,h.1.1.1.2,h.1.1.2,h.1.2⟩

theorem ReadCut.same_source (cut : ReadCut state token scope source metadata now deadline) :
    cut.descriptor.source = source := by
  have h := cut.accepted
  simp only [Bool.and_eq_true] at h
  exact Descriptor.same_source _ _ _ _ h.2

theorem ReadCut.reader_owned (cut : ReadCut state token scope source metadata now deadline) :
    cut.next.entries[token]? = some {cut.held with readers := cut.held.readers+1} := by
  simp [ReadCut.next]

theorem ReadCut.budget_unchanged (cut : ReadCut state token scope source metadata now deadline) :
    cut.next.budget = state.budget := rfl

theorem ReadCut.descriptors_unchanged (cut : ReadCut state token scope source metadata now deadline) :
    cut.next.descriptors = state.descriptors := rfl

def State.readCut (state : State) (token scope : String) (source : PageMap.Head)
    (metadata : Cache.Manifest) (now deadline : Nat) :
    Except String (ReadCut state token scope source metadata now deadline) := do
  match registered : state.entries[token]? with
  | none => throw \"retained source expired or released\"
  | some held =>
    match bound : state.descriptors[held.descriptor]? with
    | none => throw \"retained source descriptor missing\"
    | some descriptor =>
      if accepted : (!state.closed && !held.released && now < held.deadline && now < deadline &&
          descriptor.accepts scope source metadata) = true then
        return ⟨held,descriptor,registered,bound,accepted⟩
      else throw \"retained source changed its scope, root or lifetime\"

"

def prepare : IO Unit := do
  drained
  IO.FS.createDirAll study
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.LeaseReadChecks",(base/"lease-read-settings.json").toString]
  let path := source/"Eggshell/CanonicalSourceLease.lean"
  let before ← IO.FS.readFile path
  let start := "structure Pool where"
  check ((before.splitOn start).length == 2) "unique lease state boundary required"
  -- Keep the original eager sweep in retain (admission), explicit reap and close.
  let old := "  pool.reap\n  let now ← IO.monoMsNow\n  let descriptor ← pool.state.atomically do\n    let state ← get\n    let some held := state.entries[token]? | throw (IO.userError \"retained source expired or released\")\n    let some descriptor := state.descriptors[held.descriptor]? | throw (IO.userError \"retained source descriptor missing\")\n    unless !state.closed && !held.released && now < held.deadline && now < deadline &&\n        descriptor.accepts scope source metadata do\n      throw (IO.userError \"retained source changed its scope, root or lifetime\")\n    set {state with entries := state.entries.insert token {held with readers := held.readers+1}}\n    return descriptor"
  let replacement := "  let now ← IO.monoMsNow\n  let descriptor ← pool.state.atomically do\n    let state ← get\n    let cut ← IO.ofExcept (state.readCut token scope source metadata now deadline)\n    set cut.next\n    return cut.descriptor"
  check ((before.splitOn old).length == 2) "exact old repeated read sweep required"
  let changed := (before.replace old replacement).replace start (laws++start)
  IO.FS.writeFile path changed
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U3",
    (base/"replay-readiness-source/Eggshell/CanonicalSourceLease.lean").toString,path.toString]}
  check (diff.exitCode == 1) "lease patch missing"
  IO.FS.writeFile (study/"CanonicalSourceLease.patch") diff.stdout
  write (study/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("purpose",toJson "remove unrelated expiration sweep from reads; prove complete live descriptor borrow"),
    ("reclaimBeforeEveryNewRetention",toJson true),("releaseCloseAndFinalizerPreserved",toJson true),
    ("noNewMutexCasWorkerOrResourceIncrease",toJson true),("noRankingOrQueryChange",toJson true),
    ("adopted",toJson false),("paidComparisons",toJson "0/18")])
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"lease-read-settings.json").toString]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
      "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      (target/"StudyMain").toString,(base/(tag++"-result")).toString]
    | _ => throw (IO.userError "unknown lease study action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def repair : IO Unit := do
  drained
  IO.FS.writeFile (study/"build1-failure.txt") (← IO.FS.readFile (target/"Eggshell_CanonicalSourceLease-lean.stdout"))
  let path := source/"Eggshell/CanonicalSourceLease.lean"
  let before ← IO.FS.readFile path
  check ((before.splitOn "Bool.not_eq_true,").length == 2) "one corrected Bool equality lemma expected"
  IO.FS.writeFile path (before.replace "Bool.not_eq_true," "Bool.not_eq_true',")
def refreshChecks : IO Unit := do
  drained
  let path := source/"Eggshell/CanonicalSourceLease.lean"
  let before ← IO.FS.readFile path
  let old := "/-- A request owns the immutable descriptor after this one checked transition.\nNo cache sweep, IO, mutex, CAS or background work is available in this value. -/"
  let corrected := "/-- A checked request-local borrow of the immutable descriptor fields.\nValidation and this state transition are pure; IO remains at the pool boundary. -/"
  check ((before.splitOn old).length == 2) "precise pure boundary comment required"
  IO.FS.writeFile path (before.replace old corrected)
  IO.FS.writeFile (source/"tools/research/LeaseReadChecks.lean") (← IO.FS.readFile (workspace/"tools/research/LeaseReadChecks.lean"))
def sealCandidate (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "native read controls failed"
  let report ← read (base/(tag++"-result/report.json"))
  check (report.getObjValD "unrelatedSweepAbsent" == toJson true &&
    report.getObjValD "closeAndCancellationReleaseCharges" == toJson true) "native lifetime evidence incomplete"
  write (study/"report.json") report
  write (study/"checks.guard.json") guard
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.CanonicalSourceLease"]
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/CanonicalSourceLease.lean",
    "--label","b/Eggshell/CanonicalSourceLease.lean",
    (base/"replay-readiness-source/Eggshell/CanonicalSourceLease.lean").toString,(source/"Eggshell/CanonicalSourceLease.lean").toString]}
  check (patch.exitCode == 1) "source patch missing"
  IO.FS.writeFile (study/"CanonicalSourceLease.patch") patch.stdout
  let kernel ← IO.FS.readFile (target/"tools_research_LeaseReadChecks-lean.stdout")
  check (kernel.contains "checked descriptor dependencies have no shared synchronization" && !kernel.contains "sorryAx")
    "actual pure read path audit missing"
  IO.FS.writeFile (study/"kernel-audit.txt") kernel
  write (study/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (target/"StudyMain"))),
    ("parent",toJson (← hash (parent/"StudyMain"))),("controlOnly",toJson true),("adopted",toJson false)])
def finish (tag : String) : IO Unit := do
  drained
  check ((← read (study/"native-closure.json")).getObjValD "consistent" == toJson true &&
    (← read (study/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "native closure and exact source audit required before cleanup"
  let originalCheck ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (originalCheck.exitCode == 0) "protected original changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × (String × String))))
  for (path,(bytes,digest)) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "frozen original head changed"
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "lease-read-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (entry.fileName,← read entry.path)
  write (study/"guards.json") (toJson guards)
  IO.FS.removeDirAll (base/(tag++"-result"))
  let mut logs := 0
  for entry in ← target.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      let text ← IO.FS.readFile entry.path
      check (!text.contains "error:" && !text.contains "error(") "retain native compiler error before cleanup"
      IO.FS.removeFile entry.path
      logs := logs+1
  let bytes := (← (target/"StudyMain").metadata).byteSize
  IO.FS.removeFile (target/"StudyMain")
  write (study/"cleanup.json") (Json.mkObj [("endedPrivateDbAndCacheRemoved",toJson true),
    ("compilerLogsRemoved",toJson logs),("unusedControlExecutableBytesRemoved",toJson bytes),
    ("nativeSourceObjectInterfacesRetained",toJson true),("originalHeadsAndProtectedFilesUnchanged",toJson true),
    ("archiveCreated",toJson false)])
  IO.println (Json.mkObj [("componentControlsPassed",toJson true),("wholeSearchLockFree",toJson false),
    ("adopted",toJson false)]).compress
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["repair"] => repair
  | ["refresh-checks"] => refreshChecks
  | ["seal",tag] => sealCandidate tag
  | ["finish",tag] => finish tag
  | ["patch"] => do
    drained
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/CanonicalSourceLease.lean",
      "--label","b/Eggshell/CanonicalSourceLease.lean",
      (base/"replay-readiness-source/Eggshell/CanonicalSourceLease.lean").toString,(source/"Eggshell/CanonicalSourceLease.lean").toString]}
    check (patch.exitCode == 1) "lease source patch missing"
    IO.FS.writeFile (study/"CanonicalSourceLease.patch") patch.stdout
  | _ => throw (IO.userError "prepare | setup ACTION TAG")
end Eggshell.Research.LeaseReadStudy
def main := Eggshell.Research.LeaseReadStudy.main
