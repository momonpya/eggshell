import Eggshell.ProjectViews
import Eggshell.PublicationWire
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.Publication Eggshell.ProjectStore DB

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def append (project : ProjectStore.Project) (slot step : Nat) (context : View) : IO Unit :=
  withOwner project slot fun owner => do
    let capsule : Capsule := {
      session := "native-view-check",turn := toString step,cwd := "/controlled-source",work := "check original images"
      tools := #[{name := "mcp__fixture__inspect",useId := toString step,input := "{}",response := s!"original-{step}"}]
      finalMessage := some s!"recorded original-{step}",checkpoint := false
      timing := #[.interval ⟨Sha256.hex "native-view-check".toUTF8,step*10+1,step*10+2,none⟩] }
    let request ← IO.ofExcept (capsule.prepare project.directory owner.source.identity)
    let request := {request with target := project.sourceDirectory slot}
    let results ← owner.publish context #[request]
    check (results.size == 1 && results.all (·.source.complete)) "native view fixture did not publish"

def main (args : List String) : IO Unit := do
  let [pathText] := args | throw (IO.userError "ProjectViewChecks NEW_ROOT")
  let root := System.FilePath.mk pathText
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute image check root required"
  FileSystem.privateDirectory root
  let project ← create (root / "work.project") 2
  let other ← create (root / "other.project") 2
  let boot ← pin project ((← IO.monoMsNow)+28000)
  let pool ← ProjectViews.Pool.new
  let start ← Std.Mutex.new false
  let tasks ← (List.range 80).toArray.mapM fun _ => IO.asTask (do
    while !(← start.atomically get) do IO.sleep 1
    pool.acquire project boot.cut ((← IO.monoMsNow)+28000)) .dedicated
  start.atomically (set true)
  let borrows ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
  let initial ← pool.stats
  check (initial.getObjValD "builds" == toJson (1 : Nat) && initial.getObjValD "reused" == toJson (79 : Nat) &&
    initial.getObjValD "borrowers" == toJson (80 : Nat) && initial.getObjValD "handles" == toJson (2 : Nat))
    "identical image requests repeated validation or lost borrowers"
  let some first := borrows[0]? | throw (IO.userError "first image borrow missing")
  let some second := borrows[1]? | throw (IO.userError "second image borrow missing")
  first.withReader fun a => second.withReader fun b => do
    let some aSource := a.sources[0]? | throw (IO.userError "borrow omitted source")
    let some bSource := b.sources[0]? | throw (IO.userError "borrow omitted source")
    aSource.reads.set 37
    check ((← bSource.reads.get) == 0 && a.cut == b.cut && a.cut == boot.cut)
      "borrowers share mutable counters or changed their source heads"
  let mut cuts := #[]
  for step in [:33] do
    append project 0 step boot
    let view ← pin project ((← IO.monoMsNow)+28000)
    cuts := cuts.push view.cut
    let borrowed ← pool.acquire project view.cut ((← IO.monoMsNow)+28000)
    borrowed.release
  first.withReader fun old => check (old.cut == boot.cut && old.sources.all (·.head.revision == 0))
    "later publication changed a retained old image"
  let afterEviction ← pool.stats
  check (afterEviction.getObjValD "images" == toJson ProjectViews.maxImages &&
    ((afterEviction.getObjValAs? Nat "evicted").toOption.getD 0) > 0)
    "image catalogue never enforced its resident bound"
  for borrowed in borrows.extract 1 borrows.size do borrowed.release
  let mut held := #[]
  for cut in cuts.extract 0 31 do
    held := held.push (← pool.acquire project cut ((← IO.monoMsNow)+28000))
  let some last := cuts[32]? | throw (IO.userError "last immutable cut missing")
  check (← rejected (pool.acquire project last ((← IO.monoMsNow)+10)))
    "image admission evicted an active borrower"
  first.withReader fun old => do
    first.release
    first.release
    check (old.cut == boot.cut) "operation lost its pinned image after outer release"
    check (← rejected (pool.acquire project last ((← IO.monoMsNow)+10)))
      "image was evicted while an operation still used its reader"
  let newest ← pool.acquire project last ((← IO.monoMsNow)+28000)
  check (← rejected (first.withReader fun _ => pure ())) "released image borrow was reusable"
  let some middle := held[0]? | throw (IO.userError "retained image missing")
  ProjectViews.withReaders [middle,newest] fun views => do
    let some a := views[0]? | throw (IO.userError "join lost first image")
    let joined ← a.joinMany (views.extract 1 views.size)
    check (joined.cut == last && joined.sources.size == project.manifest.owners.size)
      "joining retained images changed the complete maximum cut"
  check (← rejected (pool.acquire project {last with heads := last.heads.pop} ((← IO.monoMsNow)+100)))
    "image cache accepted a missing source owner"
  check (← rejected (pool.acquire other last ((← IO.monoMsNow)+100))) "image cache crossed project scopes"
  newest.release
  let forked := {last with heads := last.heads.modify 0 fun h => {h with bytes := h.bytes+1}}
  check (← rejected (pool.acquire project forked ((← IO.monoMsNow)+1000))) "image cache accepted a forked original"
  -- Free admission before constructing the separate dependency rejection.
  for borrowed in held do borrowed.release
  let context ← pin project ((← IO.monoMsNow)+28000)
  append project 1 100 context
  let latest ← pin project ((← IO.monoMsNow)+28000)
  let oldHead ← headAt boot.cut.heads 0
  let missing := {latest.cut with heads := latest.cut.heads.modify 0 fun _ => oldHead}
  check (← rejected (pool.acquire project missing ((← IO.monoMsNow)+1000)))
    "image cache accepted an omitted cross-owner dependency"
  let retained ← pool.acquire project latest.cut ((← IO.monoMsNow)+28000)
  pool.stop
  check (← rejected (pool.acquire project latest.cut ((← IO.monoMsNow)+100))) "closed image pool admitted new work"
  check (← rejected pool.drain) "image pool drained an active borrower"
  retained.withReader fun view => check (view.cut == latest.cut) "close invalidated an admitted operation"
  retained.release
  let beforeDrain ← pool.stats
  pool.drain
  let drained ← pool.stats
  check (drained.getObjValD "images" == toJson (0 : Nat) && drained.getObjValD "handles" == toJson (0 : Nat) &&
    drained.getObjValD "borrowers" == toJson (0 : Nat)) "image drain leaked source handles"
  let wide ← create (root / "wide.project") 33
  let wideBoot ← pin wide ((← IO.monoMsNow)+28000)
  let widePool ← ProjectViews.Pool.new
  let mut wideBorrows := #[]
  for step in [:15] do
    append wide 0 (200+step) wideBoot
    let view ← pin wide ((← IO.monoMsNow)+28000)
    wideBorrows := wideBorrows.push (← widePool.acquire wide view.cut ((← IO.monoMsNow)+28000))
  append wide 0 300 wideBoot
  let wideLatest ← pin wide ((← IO.monoMsNow)+28000)
  check (← rejected (widePool.acquire wide wideLatest.cut ((← IO.monoMsNow)+10)))
    "source-handle admission evicted an active image"
  let handleBudget ← widePool.stats
  check (handleBudget.getObjValD "images" == toJson (15 : Nat) &&
    handleBudget.getObjValD "handles" == toJson (495 : Nat)) "source-handle budget was not exercised"
  let some releaseOne := wideBorrows[0]? | throw (IO.userError "wide image missing")
  releaseOne.release
  let replacement ← widePool.acquire wide wideLatest.cut ((← IO.monoMsNow)+28000)
  widePool.stop
  replacement.release
  for borrowed in wideBorrows do borrowed.release
  widePool.drain
  let result := Json.mkObj [("identicalRequests",toJson (80 : Nat)),("initial",initial),
    ("afterEviction",afterEviction),("beforeDrain",beforeDrain),("drained",drained),
    ("sourceHandleBudget",handleBudget),
    ("allPassed",toJson true),("answeringModelCalls",toJson (0 : Nat)),("tokenAdoptionEvidence",toJson false)]
  IO.FS.writeFile (root / "report.json") (result.pretty ++ "\n")
  IO.println result.compress
