import tools.research.ViewAdmissionProof
import Init.System.Promise
open Lean Eggshell Eggshell.Synapses.SharedReadViews

namespace Eggshell.Research.ViewAdmissionProbe
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def key (i : Nat) : Key := ⟨s!"probe-scope-{i}",s!"probe-content-{i}"⟩

/-- Sixteen distinct preparations remain live together until every caller
settles. These are admission handles, not fabricated readable sources. -/
def concurrent (pool : Pool) : IO Json := do
  let launch ← IO.Promise.new (α := Nat)
  let release ← IO.Promise.new (α := Unit)
  let settled ← (Array.range 16).mapM fun _ => IO.Promise.new (α := Json)
  let tasks ← settled.mapIdxM fun i status => IO.asTask (do
    let deadline ← IO.wait launch.result!
    let began ← IO.monoMsNow
    try
      let admitted ← pool.reserve (key i) 0 deadline
      try
        status.resolve (Json.mkObj [("client",toJson i),("admitted",toJson true),
          ("elapsedMs",toJson ((← IO.monoMsNow)-began)),("resident",toJson admitted.resident)])
        discard <| IO.wait release.result!
      finally pool.release admitted.token (key i).scope
    catch error => status.resolve (Json.mkObj [("client",toJson i),("admitted",toJson false),
      ("elapsedMs",toJson ((← IO.monoMsNow)-began)),("error",toJson error.toString)])) .dedicated
  let began ← IO.monoMsNow
  try
    launch.resolve (began+1000)
    while !(← settled.allM (·.isResolved)) do
      check ((← IO.monoMsNow) < began+3000) "admission callers did not settle"
      IO.sleep 1
    let elapsed := (← IO.monoMsNow)-began
    let rows ← settled.mapM fun promise => IO.wait promise.result!
    let admitted := rows.countP (fun row => row.getObjValD "admitted" == toJson true)
    let barrier ← pool.stats
    check (barrier.getObjValD "active" == toJson admitted &&
      barrier.getObjValD "building" == toJson admitted &&
      barrier.getObjValD "queued" == toJson (0 : Nat)) "barrier lost live admission accounting"
    release.resolve ()
    for task in tasks do discard <| IO.ofExcept (← IO.wait task)
    let drained ← pool.stats
    check (drained.getObjValD "active" == toJson (0 : Nat) &&
      drained.getObjValD "chargedBytes" == toJson (0 : Nat)) "released preparations retained a reservation"
    return Json.mkObj [("clients",toJson (16 : Nat)),("admittedTogether",toJson admitted),
      ("wallMs",toJson elapsed),("deadlineMs",toJson (1000 : Nat)),("rows",toJson rows),
      ("barrier",barrier),("drained",drained)]
  finally
    launch.resolve (began+1000)
    release.resolve ()
    for task in tasks do IO.cancel task
    for task in tasks do discard <| IO.wait task

def boundaries (pool : Pool) : IO Json := do
  let admitted ← pool.reserve (key 99) 0 ((← IO.monoMsNow)+1000)
  let wrongScope ← try pool.release admitted.token "foreign-scope"; pure false catch _ => pure true
  let unreadable ← try discard <| pool.validateView admitted.token (key 99).scope; pure false catch _ => pure true
  check (wrongScope && unreadable && (← pool.stats).getObjValD "active" == toJson (1 : Nat))
    "an unprepared or foreign scope acquired authority"
  pool.release admitted.token (key 99).scope
  let overBudget ← try
    discard <| pool.reserve (key 100) capacity ((← IO.monoMsNow)+1000)
    pure false
    catch _ => pure true
  check (overBudget && (← pool.stats).getObjValD "active" == toJson (0 : Nat)) "byte budget was bypassed"
  return Json.mkObj [("foreignScopeRejected",toJson wrongScope),("unpreparedReadRejected",toJson unreadable),
    ("overBudgetRejected",toJson overBudget)]

def run (output : System.FilePath) : IO Unit := do
  check (output.isAbsolute && !(← output.pathExists)) "fresh native admission report required"
  IO.FS.createDirAll output
  let pool ← Pool.new
  try
    let batch ← concurrent pool
    let limits ← boundaries pool
    IO.FS.writeFile (output/"report.json") (Json.mkObj [("batch",batch),("boundaries",limits),
      ("syntheticAdmissionOnly",toJson true),("actualHookCalls",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally pool.close
end Eggshell.Research.ViewAdmissionProbe
