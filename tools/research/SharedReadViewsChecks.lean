import tools.research.SharedReadViews
open Lean Eggshell.Synapses.SharedReadViews
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def rejects (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

def main : IO Unit := do
  -- Expired/released borrowers must stay charged until their finalizer.
  let held : View := {scope := "project-set",sources := #[],deadline := 1,charge := 1024,borrowers := 1}
  let state : State := {active := ({} : Std.HashMap String View).insert "held" held}
  check ((state.reap 2).used == 1024 && (state.reap 2).active.size == 1)
    "expired borrower escaped its memory reservation"
  let released := {state with active := state.active.insert "held" {held with released := true}}
  check ((released.reap 2).used == 1024) "released borrower escaped its reservation"
  let finished := {released with active := released.active.insert "held" {held with released := true,borrowers := 0}}
  check ((finished.reap 2).used == 0) "finished borrower retained its reservation"
  let pool ← Pool.new
  let deadline := (← IO.monoMsNow)+10000
  let rejectedOversize ← rejects (pool.reserve "project-set" capacity deadline)
  check rejectedOversize "oversize request was admitted"
  let token ← pool.reserve "project-set" 1024 deadline
  check (← rejects (pool.release token "other-project")) "release crossed its project scope"
  check ((← pool.stats).getObjValD "active" == toJson (1 : Nat)) "invalid release removed another project's reservation"
  check (← rejects (pool.validateView token "project-set")) "unbound view was readable"
  pool.release token "project-set"
  let jobs ← (List.range 80).mapM fun _ => IO.asTask (do
    let token ← pool.reserve "project-set" 16384 deadline
    try IO.sleep 2 finally pool.release token "project-set") .dedicated
  for job in jobs do let _ ← IO.ofExcept job.get
  let stats ← pool.stats
  check (stats.getObjValD "active" == toJson (0 : Nat) && stats.getObjValD "queued" == toJson (0 : Nat) &&
    stats.getObjValD "chargedBytes" == toJson (0 : Nat) && stats.getObjValD "admitted" == toJson (81 : Nat) &&
    stats.getObjValD "released" == toJson (81 : Nat)) "concurrent reservations leaked"
  pool.close
  check (← rejects (pool.reserve "project-set" 1 deadline)) "closed pool restarted work"
  IO.println (Json.mkObj [("borrowedExpiryStillCharged",toJson true),("wrongScopeRejected",toJson true),
    ("unboundViewRejected",toJson true),("concurrentReservations",toJson (80 : Nat)),("beforeClose",stats),
    ("closedRejectedNewWork",toJson true)]).compress
