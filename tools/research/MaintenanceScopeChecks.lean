import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.MaintenanceScopeChecks
#print axioms MaintenanceScope.current_grant
#print axioms MaintenanceScope.standalone_recovery
def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)
def run (source root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier maintenance audit"
  IO.FS.createDirAll root
  let project ← ProjectStore.openProject (source/"work.project")
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let heads := view.sources.map (·.head)
  let some firstHead := heads[0]? | throw (IO.userError "empty maintenance source inventory")
  let mut rows := #[]
  for writable in [true,false] do
    let session := if writable then "maintenance-writer" else "maintenance-reader"
    let pending : PendingTurn := {
      sessionId := session,turnId := "turn",cwd := root.toString,prompt := "fixed question",profile := "work",
      write := if writable then some project.directory.toString else none,
      read := [project.directory.toString],semanticMatcher := none,handoffChars := 120000,projection := .none,
      projectInputs := some #[ProjectInputs.ofView view] }
    let files ← sessionFiles session
    FileSystem.privateDirectory files.directory
    writeJson files.pending pending
    let capturedScope ← MaintenanceScope.capture session ((← IO.monoMsNow)+30000)
    let some context := capturedScope.context | throw (IO.userError "maintenance lost project context")
    check (capturedScope.sources == some (heads.map (·.identity))) "maintenance changed complete source inventory"
    check (context.images == #[ProjectInputs.ofView view]) "maintenance changed the pinned cut"
    let allowed := view.sources.map fun original => capturedScope.canPrepare (DB.Sidecar.Owner.ofSnapshot original)
    check (allowed.all (· == writable)) "maintenance widened or dropped project writer scope"
    for original in view.sources do
      let owner := DB.Sidecar.Owner.ofSnapshot original
      let reference := capturedScope.context.any (·.canPrepare owner) || pending.write.any (fun path =>
        (System.FilePath.mk path).normalize == (System.FilePath.mk owner.directory).normalize)
      check (capturedScope.canPrepare owner == reference) "captured maintenance differs from original grant predicate"
    let foreignOwner : DB.Sidecar.Owner := {directory := (root/"foreign.egg").toString,database := firstHead.identity}
    check (!(capturedScope.canPrepare foreignOwner)) "same identity at a foreign path gained a writer grant"
    let standalone : MaintenanceScope := ⟨none,none,none⟩
    check (standalone.canPrepare foreignOwner) "standalone recovery contract changed"
    let denied : MaintenanceScope := ⟨some {pending with write := none},none,none⟩
    check (!(denied.canPrepare foreignOwner)) "reader gained standalone recovery authority"
    rows := rows.push (Json.mkObj [("writer",toJson writable),("sources",toJson heads.size),
      ("allowed",toJson allowed),("exactGrantPredicate",toJson true),
      ("capturedHeadsExact",toJson true),("foreignPathRejected",toJson true)])
  for original in view.sources do
    check ((← DB.PageMap.pin original.directory).head == original.head) "maintenance audit changed an original head"
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("rows",toJson rows),
    ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
end Eggshell.Research.MaintenanceScopeChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["maintenance-scope-checks",source,root] =>
      Eggshell.Research.MaintenanceScopeChecks.run (.mk source) (.mk root)
      return 0
  | ["front-traffic-audit",source] =>
      -- Keep the independent original-data auditor fixed. It is outside the
      -- timed hook and does not start this candidate's frontend.
      let result ← IO.Process.output {
        cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain",
        args := #["front-traffic-audit",source]}
      IO.print result.stdout
      IO.eprint result.stderr
      return result.exitCode
  | other => sourceRouteEngine other
