import Main
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.FrontSessionChecks
def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path (value.compress++"\n")
def turn (root : System.FilePath) (session : String) (closed : Bool) : PendingTurn := {
  sessionId := session,turnId := "turn",cwd := root.toString,prompt := "retain private state"
  profile := "private",semanticMatcher := none,read := [],write := none,handoffChars := 120000
  projection := .none,closed := closed }
def privateTurn (root : System.FilePath) (session : String) (closed : Bool) : IO SessionFiles := do
  let files ← sessionFiles session
  writeJson files.state ({profile := "private"} : ThreadState)
  writeJson files.pending (turn root session closed)
  return files
def stats (endpoint : Daemon.Endpoint) : IO Json := do
  IO.ofExcept (Json.parse (← Daemon.exchange endpoint "stats"))
def settle (endpoint : Daemon.Endpoint) : IO Json := do
  let deadline := (← IO.monoMsNow)+10000
  repeat
    let current ← stats endpoint
    let n ← IO.ofExcept (current.getObjValAs? Nat "registeredSessions")
    check (n ≤ HookBudget.sessions) "frontend enlarged its registry bound"
    if current.getObjValD "quiescentSessions" == toJson n &&
        current.getObjValD "activeMaintenance" == toJson (0 : Nat) &&
        current.getObjValD "pendingMaintenance" == toJson (0 : Nat) then return current
    check ((← IO.monoMsNow) < deadline) "closed sessions did not become quiescent"
    IO.sleep 20
  throw (IO.userError "unreachable quiescence wait")
def policy (root : System.FilePath) : IO Unit := do
  IO.FS.createDirAll root
  let files ← privateTurn root "file-check" false
  check (!(← HookFrontend.Session.closedAndDrained files)) "open turn was marked quiescent"
  writeJson files.pending (turn root "file-check" true)
  check (← HookFrontend.Session.closedAndDrained files) "closed drained turn was pinned forever"
  for name in ["deferred","checkpoints"] do
    IO.FS.createDirAll (files.directory/name)
    let debt := files.directory/name/"retained.json"
    IO.FS.writeFile debt "{}"
    check (!(← HookFrontend.Session.closedAndDrained files)) "durable save debt was ignored"
    check ((← IO.FS.readFile debt) == "{}") "quiescence inspection consumed durable work"
    IO.FS.removeFile debt
  IO.FS.writeFile files.pending "malformed"
  check (!(← HookFrontend.Session.closedAndDrained files)) "malformed turn became absent"
  check ((← IO.FS.readFile files.pending) == "malformed") "quiescence inspection changed an unreadable turn"
  IO.FS.removeFile files.pending
  let corrupt := files.directory/"pending.json.corrupt-test"
  IO.FS.writeFile corrupt "malformed"
  check (!(← HookFrontend.Session.closedAndDrained files)) "quarantined turn became absent"
  IO.FS.removeFile corrupt
  check (← HookFrontend.Session.closedAndDrained files) "absent drained turn was pinned"
  let a ← HookFrontend.Session.create "pure-a" 1
  let b ← HookFrontend.Session.create "pure-b" 2
  let a := {a with quiet := true}
  let b := {b with quiet := true}
  check (HookFrontend.retirementIndex? #[a,b] [] [] [] == some 0) "oldest eligible cursor was not selected"
  check (HookFrontend.retirementIndex? #[a,b] [a.name] [] [] == some 1) "queued maintenance was evicted"
  check (HookFrontend.retirementIndex? #[a,b] [] [a.name] [] == some 1) "active maintenance was evicted"
  check (HookFrontend.retirementIndex? #[a,b] [] [] [a.name,b.name] == none) "active request was evicted"
  check (!((a.touch 3).finish a.revision true).quiet) "stale maintenance result restored quiescence"
  let old ← privateTurn root "closed-0" true
  let original := Sha256.hex (← IO.FS.readBinFile old.pending)
  let mut snapshots := #[]
  let mut manager := 0
  try
    let endpoint ← Daemon.ensure "closed-0"
    manager := endpoint.pid
    for wave in [:3] do
      for i in [:80] do
        let session := s!"closed-{wave*80+i}"
        let _ ← privateTurn root session true
        let current ← Daemon.readyEndpoint session
        check (current.pid == manager) "session churn created a separate frontend"
        let reply ← Daemon.exchange current "register" (Json.mkObj [("session_id",toJson session)])
        check reply.isEmpty "unexpected authenticated registration reply"
      let snapshot ← settle endpoint
      snapshots := snapshots.push snapshot
      save (root/"churn.json") (toJson snapshots)
    let settled ← settle endpoint
    let retired ← IO.ofExcept (settled.getObjValAs? Nat "retiredSessions")
    check (retired ≥ 112) "completed session history was not retired at the unchanged bound"
    IO.sleep 2200
    let idle ← stats endpoint
    check (idle.getObjValD "maintenanceRuns" == settled.getObjValD "maintenanceRuns") "quiet history was polled repeatedly"
    let reply ← Daemon.exchange endpoint "register" (Json.mkObj [("session_id",toJson "closed-0")])
    check reply.isEmpty "unexpected resumed-session registration reply"
    let resumed ← settle endpoint
    check (Sha256.hex (← IO.FS.readBinFile old.pending) == original) "retirement changed private authoritative state"
    let rejected ← try
      let _ ← Daemon.exchange {endpoint with secret := "invalid"} "register" (Json.mkObj [("session_id",toJson "unauthorized")])
      pure false
    catch _ => pure true
    check rejected "unauthenticated request changed admission"
    let after ← stats endpoint
    check (after.getObjValD "retiredSessions" == resumed.getObjValD "retiredSessions") "unauthorized input evicted a session"
    save (root/"report.json") (Json.mkObj [("allPassed",toJson true),("registeredHistory",toJson (240 : Nat)),
      ("snapshots",toJson snapshots),("idle",idle),("resumed",resumed),
      ("privateStateUnchanged",toJson true),("durableDebtPreserved",toJson true),
      ("staleCompletionRejected",toJson true),("activeAndPendingEntriesProtected",toJson true),
      ("unauthorizedRejected",toJson rejected),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  finally
    try Daemon.shutdown finally
      Worker.shutdown
      let _ ← Publication.Client.control "shutdown"
      pure ()
  check (!(← Numerical.alive manager)) "frontend did not exit"

end Eggshell.Research.FrontSessionChecks
