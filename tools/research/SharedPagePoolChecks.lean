import Eggshell.DB.PageMap
open Lean Eggshell.DB

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def publish (source : PageMap.Snapshot) (value : String) : IO PageMap.Snapshot := do
  let _ ← PageMap.withWriter source fun writer => writer.put "original" (some value.toUTF8)
  PageMap.pin source.directory

def main (args : List String) : IO Unit := do
  let [directory] := args | throw (IO.userError "new absolute fixture directory required")
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "preserve prior cache trial"
  IO.FS.createDirAll root
  let pool ← PageMap.PagePool.new
  let fixtures ← (Array.range 16).mapM fun index => do
    let source ← PageMap.create (root / s!"project-{index}") s!"customer-{index}"
    let source ← publish source s!"immutable original for project {index}"
    source.sharePages pool s!"customer-{index}"
  -- One retained service cache across all DBs, rather than 80 private caches.
  for index in List.finRange fixtures.size do
    check ((← fixtures[index].get "original") == some s!"immutable original for project {index.val}".toUTF8)
      "warm read differs from source"
  let before ← pool.stats
  let release ← IO.mkRef false
  let arrived ← Std.Mutex.new (0 : Nat)
  let jobs ← (Array.range 80).mapM fun client => IO.asTask (do
    arrived.atomically (modify (·+1))
    while !(← release.get) do IO.sleep 1
    let index := client%16
    let some source := fixtures[index]? | throw (IO.userError "missing project fixture")
    let start ← IO.monoMsNow
    for _ in [:8] do
      check ((← source.get "original") == some s!"immutable original for project {index}".toUTF8)
        "concurrent read crossed project or snapshot"
    return (← IO.monoMsNow)-start) .dedicated
  let deadline := (← IO.monoMsNow)+10000
  while (← arrived.atomically get) < 80 do
    check ((← IO.monoMsNow) < deadline) "clients did not reach barrier"
    IO.sleep 1
  release.set true
  let times ← jobs.mapM fun job => IO.ofExcept (job.get.mapError IO.Error.toString)
  let after ← pool.stats
  check (before.getObjValD "misses" == after.getObjValD "misses") "hot concurrency repeated physical page preparation"
  for source in fixtures do check ((← source.cache.get).recent.isEmpty &&
    (← source.cache.get).previous.isEmpty) "service reader retained a private page cache"
  let some first := fixtures[0]? | throw (IO.userError "missing first fixture")
  let changed ← publish first "new publication"
  let fresh ← changed.sharePages pool "customer-0"
  check ((← fresh.get "original") == some "new publication".toUTF8) "new head reused stale page"
  check ((← first.get "original") == some "immutable original for project 0".toUTF8) "publication invalidated an old pin"
  let otherScope ← first.sharePages pool "different-customer"
  let prior ← pool.stats
  let _ ← otherScope.get "original"
  let different ← pool.stats
  check ((prior.getObjValAs? Nat "misses").toOption.getD 0 <
    (different.getObjValAs? Nat "misses").toOption.getD 0) "another scope obtained a cache hit"
  let forked ← first.forkReader
  check forked.sharedPages.isNone "instrumented independent reader retained shared cache"
  let sorted := times.qsort (· < ·)
  let report := Json.mkObj [("databases",toJson (16 : Nat)),("clients",toJson (80 : Nat)),
    ("reads",toJson (640 : Nat)),("allOriginalsEqual",toJson true),
    ("hotPhysicalMisses",toJson (0 : Nat)),("privatePageCaches",toJson (0 : Nat)),
    ("scopeIsolated",toJson true),("oldPinExact",toJson true),("newPublicationExact",toJson true),
    ("p50Ms",toJson sorted[39]!),("p95Ms",toJson sorted[75]!),("maxMs",toJson sorted[79]!),
    ("pagesBefore",before),("pagesAfter",after),("actualHookMeasured",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
