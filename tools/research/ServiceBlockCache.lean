import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def replace (text old updated : String) : IO String := do
  check ((text.splitOn old).length == 2) "exactly one cache boundary required"
  return text.replace old updated

private def cache : String := r#"/-- One service-wide byte budget. Keys keep read scope, absolute directory,
file incarnation and authority. Complete references are still checked on hits. -/
abbrev SharedPageKey := String × String × String × String × Nat

def sharedPageCapacity : Nat := 2*1024*65536

/-- The charge includes decoded row/child cells and descriptor overhead as
well as bytes. It is an allocation estimate, not a theorem about native RSS. -/
def CachedPage.charge (page : CachedPage) : Nat :=
  512+2*page.ref.bytes+256*(match page.loaded.page with
    | .leaf rows => rows.length
    | .branch children => children.length)

abbrev SharedPageCache := ByteBudgetCache.Cache SharedPageKey CachedPage (sharedPageCapacity/2)

def SharedPageCache.capacity : Nat := sharedPageCapacity

def SharedPageCache.lookup (cache : SharedPageCache) (key : SharedPageKey) : Option CachedPage :=
  cache.find? key

def SharedPageCache.find (cache : SharedPageCache) (key : SharedPageKey) (ref : Ref) : Option (Loaded ref) := do
  let cached ← cache.lookup key
  if same : cached.ref = ref then some (same ▸ cached.loaded) else none

def SharedPageCache.touch (cache : SharedPageCache) (key : SharedPageKey) (page : CachedPage) : SharedPageCache :=
  ByteBudgetCache.Cache.touch cache ⟨key,page,page.charge⟩

theorem SharedPageCache.touch_bounded (cache : SharedPageCache) (key : SharedPageKey) (page : CachedPage) :
    ByteBudgetCache.allocated (cache.touch key page).recent.slots +
      ByteBudgetCache.allocated (cache.touch key page).previous.slots ≤ capacity := by
  simpa [capacity,sharedPageCapacity] using (cache.touch key page).allocated_bounded

theorem SharedPageCache.touch_recent (cache : SharedPageCache) (key : SharedPageKey) (page : CachedPage)
    (fits : page.charge ≤ sharedPageCapacity/2) :
    (cache.touch key page).lookup key = some page := by
  have found := ByteBudgetCache.Cache.touch_recent cache ⟨key,page,page.charge⟩ fits
  simp [lookup,touch,ByteBudgetCache.Cache.find?,found]

theorem SharedPageCache.find_rejects (cache : SharedPageCache) (key : SharedPageKey)
    (ref : Ref) (cached : CachedPage) (located : cache.lookup key = some cached) (different : cached.ref ≠ ref) :
    cache.find key ref = none := by
  simp [find,located,different]

structure SharedPages where
  cache : SharedPageCache := {}
  hits : Nat := 0
  misses : Nat := 0

structure PagePool where
  state : Std.Mutex SharedPages

def PagePool.new : IO PagePool := return ⟨← Std.Mutex.new {}⟩

def PagePool.find (pool : PagePool) (key : SharedPageKey) (ref : Ref) : IO (Option (Loaded ref)) :=
  pool.state.atomically do
    let state ← get
    if let some loaded := state.cache.find key ref then
      -- A recent hit is read-only. Do not copy a bucket table or allocate
      -- another ownership slot for every B-tree level of every lookup.
      let cache := if (state.cache.recent.find? key).isSome then state.cache
        else state.cache.touch key ⟨ref,loaded⟩
      set {state with cache,hits := state.hits+1}
      return some loaded
    set {state with misses := state.misses+1}
    return none

def PagePool.insert (pool : PagePool) (key : SharedPageKey) (page : CachedPage) : IO Unit :=
  if page.ref.bytes ≤ 65536 then
    pool.state.atomically (modify fun state => {state with cache := state.cache.touch key page})
  else throw (IO.userError "shared page exceeds its verified block bound")

def PagePool.stats (pool : PagePool) : IO Json := pool.state.atomically do
  let state ← get
  let cache := state.cache
  return Json.mkObj [("pages",toJson (cache.recent.index.size+cache.previous.index.size)),
    ("retainedSlots",toJson (cache.recent.slots.size+cache.previous.slots.size)),
    ("chargedBytes",toJson (cache.recent.bytes+cache.previous.bytes)),
    ("retainedPageBytes",toJson ((cache.recent.slots ++ cache.previous.slots).foldl
      (fun total slot => total+slot.value.ref.bytes) 0)),
    ("capacityBytes",toJson SharedPageCache.capacity),("hits",toJson state.hits),("misses",toJson state.misses)]

"#

private def prepareBuild (core parent : System.FilePath) (label mainModule record : String) : IO Unit := do
  let evidence := project / "docs/candidates/service-block-cache"
  let prior ← read (parent / "build.json")
  let settings := prior.getObjValD "settings"
  let mut objects ← IO.ofExcept ((← read (.mk (← IO.ofExcept (settings.getObjValAs? String "objectModules")))).getObj?)
  for entry in ← IO.ofExcept (prior.getObjValAs? (Array Json) "modules") do
    objects := objects.insert (← IO.ofExcept (entry.getObjValAs? String "object")) (entry.getObjValD "module")
  let map := root / (label ++ "-objects.json")
  IO.FS.writeFile map (Json.obj objects).pretty
  let plan := settings.setObjVal! "core" (toJson core.toString)
    |>.setObjVal! "project" (toJson project.toString)
    |>.setObjVal! "baselineCore" (toJson (root / "query-cache-baseline-core").toString)
    |>.setObjVal! "baselineResponse" (toJson (parent / "runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent / "Main.o").toString)
    |>.setObjVal! "objectModules" (toJson map.toString)
    |>.setObjVal! "mainModule" (toJson mainModule)
    |>.setObjVal! "output" (toJson (root / (label ++ "-build")).toString)
  IO.FS.writeFile (root / (label ++ "-build.settings.json")) plan.pretty
  IO.FS.writeFile (root / (label ++ "-build.guard-settings.json")) (Json.mkObj [
    ("record",toJson (evidence / record).toString),("cwd",toJson project.toString),
    ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,(root / (label ++ "-build.settings.json")).toString])]).pretty

def main (args : List String) : IO Unit := do
  let core := root / "service-block-cache-core"
  let evidence := project / "docs/candidates/service-block-cache"
  if args == ["retire-protocol-rejection"] then
    let guard ← read (evidence / "trial.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (1 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) && guard.getObjValD "guardTriggered" == toJson false)
      "only the terminal protocol-rejected setup may be retired"
    let records := evidence / "trial"
    check (!(← (records / "progress.json").pathExists) && !(← (records / "baseline/warm").pathExists) &&
      !(← (evidence / "protocol-setup-rejected").pathExists)) "preserve any actual hook result separately"
    let definitions ← IO.ofExcept ((← read (records / "frozen-before-delivery.json")).getArr?)
    let some first := definitions[0]? | throw (IO.userError "frozen common source missing")
    let specification := first.getObjValD "specification"
    let common ← IO.ofExcept (specification.getObjValAs? String "source")
    let files ← IO.ofExcept (specification.getObjValAs? (Array (String × String)) "files")
    for (name,digest) in files do
      check (!name.contains '/' && name != "." && name != "..") "invalid frozen file name"
      let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(System.FilePath.mk common / name).toString]}
      check (hashed.exitCode == 0 && (hashed.stdout.splitOn " ").headD "" == digest) "the common original source changed"
    let fixture := root / "service-block-cache-trial"
    let binary := root / "service-block-cache-trial-build/StudyMain"
    for path in [fixture,binary] do
      let arguments := if (← path.symlinkMetadata).type == .dir then #["-t","+D",path.toString] else #["-t",path.toString]
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := arguments}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "rejected setup still open"
    for name in ["tools_research_StudyRuntime.source","tools_research_PreparedOriginalKeysTrial.source"] do
      IO.FS.writeFile (records / name) (← IO.FS.readFile (root / "service-block-cache-trial-build" / name))
    IO.FS.rename records (evidence / "protocol-setup-rejected")
    for (before,after) in [("trial.guard.json","protocol-setup-rejected.guard.json"),
        ("trial-build.guard.json","protocol-setup-build.guard.json"),
        ("trial-native-closure.json","protocol-setup-native-closure.json")] do
      IO.FS.rename (evidence / before) (evidence / after)
    IO.FS.removeDirAll fixture
    IO.FS.removeFile binary
    IO.FS.writeFile (evidence / "retired-protocol-rejection.json") (Json.mkObj [
      ("failure",toJson "publisher implementation differs from the frozen protocol"),
      ("targets",toJson #[fixture,binary]),("completed",toJson true),("archiveCreated",toJson false),
      ("originalSourceUnchanged",toJson true),("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
      ("protocolCheckBypassed",toJson false)]).pretty
    return
  if let [mode,arm] := args then
    check (["prepare-runtime","prepare-runtime-run","seal-runtime"].contains mode && ["baseline","candidate"].contains arm)
      "known descriptor phase and explicit comparison arm required"
    let parent := root / (if arm == "baseline" then "query-cache-baseline-build" else "service-block-cache-build")
    let selectedCore := if arm == "baseline" then root / "query-cache-baseline-core" else core
    let label := "publisher-runtime-" ++ arm
    let saved := evidence / (label ++ ".json")
    if mode == "prepare-runtime" then
      prepareBuild selectedCore parent label "tools.research.PublisherRuntime" (label ++ "-build.guard.json")
      return
    let native := root / (label ++ "-build/StudyMain")
    if mode == "prepare-runtime-run" then
      let guard ← read (evidence / (label ++ "-build.guard.json"))
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat))
        "finish the independently compiled protocol descriptor"
      let audited ← IO.Process.output {
        cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
        args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
          (root / "cached-usage-runtime-build").toString,(root / (label ++ "-build")).toString,
          (evidence / (label ++ "-native-closure.json")).toString]}
      check (audited.exitCode == 0) "protocol descriptor module closure differs"
      IO.FS.writeFile (root / (label ++ ".guard-settings.json")) (Json.mkObj [
        ("record",toJson (evidence / (label ++ ".guard.json")).toString),("cwd",toJson project.toString),
        ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
        ("command",toJson #[native.toString,(parent / "StudyMain").toString,saved.toString])]).pretty
      return
    let guard ← read (evidence / (label ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "finish the protocol descriptor before sealing it"
    let descriptor ← read saved
    let hashed ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(parent / "StudyMain").toString]}
    check (hashed.exitCode == 0 && descriptor.getObjValD "binary" == toJson (parent / "StudyMain").toString &&
      descriptor.getObjValD "sha256" == toJson ((hashed.stdout.splitOn " ").headD ""))
      "independent runtime SHA differs from its descriptor"
    let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args := #["-t",native.toString]}
    check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "protocol helper is still open"
    IO.FS.removeFile native
    IO.FS.writeFile (evidence / (label ++ "-retired.json")) (Json.mkObj [
      ("target",toJson native.toString),("completed",toJson true),("archiveCreated",toJson false)]).pretty
    if (← (evidence / "publisher-runtime-baseline.json").pathExists) &&
        (← (evidence / "publisher-runtime-candidate.json").pathExists) then
      check (!(← (evidence / "runtime-descriptors.json").pathExists)) "preserve the frozen comparison descriptors"
      let mut rows := #[]
      for name in ["baseline","candidate"] do
        rows := rows.push (Json.mkObj [("arm",toJson name),
          ("runtime",← read (evidence / ("publisher-runtime-" ++ name ++ ".json")))])
      IO.FS.writeFile (evidence / "runtime-descriptors.json") (Json.arr rows).pretty
    return
  if args == ["seal-checks"] then
    let guard ← read (evidence / "checks.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "complete the measured cache checks before retirement"
    let fixture := root / "service-block-cache-checks"
    let binary := root / "service-block-cache-checks-build/StudyMain"
    IO.FS.writeFile (evidence / "checks.json") (← IO.FS.readFile (fixture / "result.json"))
    for path in [fixture,binary] do
      let args := if (← path.symlinkMetadata).type == .dir then #["-t","+D",path.toString] else #["-t",path.toString]
      let opened ← IO.Process.output {cmd := "/usr/sbin/lsof",args}
      check (opened.exitCode == 1 && opened.stdout.trimAscii.isEmpty) "cache check input or executable still open"
    let retired := Json.mkObj [("targets",toJson #[fixture,binary]),("archiveCreated",toJson false)]
    IO.FS.writeFile (evidence / "retired-checks.json") (retired.setObjVal! "completed" (toJson false)).pretty
    IO.FS.removeDirAll fixture
    IO.FS.removeFile binary
    IO.FS.writeFile (evidence / "retired-checks.json") (retired.setObjVal! "completed" (toJson true)).pretty
    return
  if args == ["prepare-checks-run"] then
    let guard ← read (evidence / "checks-build.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat))
      "finish the native checks before running them"
    let audited ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        (root / "cached-usage-runtime-build").toString,(root / "service-block-cache-checks-build").toString,
        (evidence / "checks-native-closure.json").toString]}
    check (audited.exitCode == 0) "native check dependencies differ"
    IO.FS.writeFile (root / "service-block-cache-checks.guard-settings.json") (Json.mkObj [
      ("record",toJson (evidence / "checks.guard.json").toString),("cwd",toJson project.toString),
      ("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("command",toJson #[(root / "service-block-cache-checks-build/StudyMain").toString,
        (root / "service-block-cache-checks").toString])]).pretty
    return
  if args == ["prepare-checks"] then
    let guard ← read (evidence / "build.guard.json")
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat))
      "complete the candidate runtime before linking its checks"
    let parent := root / "service-block-cache-build"
    let library := core / ".lake/build/lib/lean"
    check ((← library.symlinkMetadata).type == .symlink) "candidate interface link missing"
    IO.FS.removeFile library
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(parent / "lib").toString,library.toString]}
    check (linked.exitCode == 0) "cannot bind consistent candidate interfaces"
    prepareBuild core parent "service-block-cache-checks" "tools.research.SharedPagePoolChecks" "checks-build.guard.json"
    return
  check args.isEmpty "explicit prepare-checks or a fresh candidate only"
  check (!(← core.pathExists)) "preserve the existing isolated cache candidate"
  IO.FS.createDirAll evidence
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "query-cache-baseline-core").toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate the actual control sources"
  IO.FS.writeFile (core / "tools/ByteBudgetCache.lean") (← IO.FS.readFile (project / "tools/ByteBudgetCache.lean"))
  let path := core / "Eggshell/DB/PageMap.lean"
  let before ← IO.FS.readFile path
  let imported ← replace before "public import Std.Data.HashMap.Lemmas\n"
    "public import Std.Data.HashMap.Lemmas\npublic import tools.ByteBudgetCache\n"
  let start := "/-- One service-wide page budget."
  let stop := "structure SharedReader where\n"
  let pieces := imported.splitOn start
  check (pieces.length == 2) "shared cache start changed"
  let rest := pieces[1]!.splitOn stop
  check (rest.length == 2) "shared cache end changed"
  IO.FS.writeFile path (pieces[0]! ++ cache ++ stop ++ rest[1]!)
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-u",(root / "query-cache-baseline-core/Eggshell/DB/PageMap.lean").toString,path.toString]}
  check (patch.exitCode == 1) "isolated cache difference missing"
  IO.FS.writeFile (evidence / "core.patch") patch.stdout
  prepareBuild core (root / "query-cache-baseline-build") "service-block-cache" "Main" "build.guard.json"
  IO.println "Isolated byte-accounted page retention; no source format, hash or authority change"
