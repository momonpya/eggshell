import Eggshell.ReplayWork
import Eggshell.Persistence

open Lean Eggshell Eggshell.Synapses

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def publishAtom (source : DB.PageMap.Snapshot) (value : Value) : IO DB.PageMap.Snapshot := do
  let (_,head,_) ← DB.PageMap.withWriter source fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.value value
    Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := false,affected := [id]}
  return {source with head}

def main (args : List String) : IO Unit := do
  let [mode,path] := args | throw (IO.userError "observe|verify FRESH_ROOT")
  check (["observe","verify"].contains mode) "unknown registration check mode"
  let root := System.FilePath.mk path
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute root required"
  IO.FS.createDirAll root
  let source ← Persistence.ensureSnapshot (root/"source.egg")
  let journal ← Persistence.ensureSnapshot (root/"private.egg")
  let value := Value.text "registered input remains absent under unrelated publications"
  let changed := Value.text "a separately registered dependency changed before registration"
  let inputs ← TurnReplay.Inputs.observe {} source value
  let laterInputs ← TurnReplay.Inputs.observe {} source changed
  check (!(inputs.sources.flatMap (·.buckets.map (·.key))).any
    (laterInputs.sources.flatMap (·.buckets.map (·.key))).contains) "fixture bucket collision"
  let base := "registration-check"
  let name := Index.contentKey "original dependency"
  let late := Index.contentKey "late dependency"
  let (_,head,_) ← DB.PageMap.withWriter journal fun writer => ReplayWork.register writer base name inputs
  let journal := {journal with head}
  -- Model the source advancing after validation but before this job's private
  -- registration transaction. Publication and journal ownership are independent.
  check (← laterInputs.agree source ((← IO.monoMsNow)+30000)) "late dependency was not initially validated"
  let published ← publishAtom source changed
  check (← inputs.agree published ((← IO.monoMsNow)+30000)) "old unchanged dependency is no longer valid"
  let (first,head,_) ← DB.PageMap.withWriter journal fun writer => do
    ReplayWork.sync journal writer base published ((← IO.monoMsNow)+30000)
  let journal := {journal with head}
  check (first.complete && !(← ReplayWork.pending journal base)) "unrelated initial delta did not drain"
  let cursorKey := ReplayWork.sourceKey base source.directory.normalize.toString
  let before ← journal.get cursorKey
  let (_,head,_) ← DB.PageMap.withWriter journal fun writer => ReplayWork.register writer base name inputs
  let journal := {journal with head}
  let preserved := (← journal.get cursorKey) == before
  let (again,head,_) ← DB.PageMap.withWriter journal fun writer => do
    ReplayWork.sync journal writer base published ((← IO.monoMsNow)+30000)
  let journal := {journal with head}
  let noRepeat := again.complete && again.blocks == 0 && again.rows == 0
  let settled ← journal.get cursorKey
  let (_,head,_) ← DB.PageMap.withWriter journal fun writer => ReplayWork.register writer base late laterInputs
  let journal := {journal with head}
  let newPreserved := (← journal.get cursorKey) == settled
  let queuedLate := (← journal.get (ReplayWork.jobKey base late)).isSome
  let originalNotQueued := (← journal.get (ReplayWork.jobKey base name)).isNone
  let beforeAbort := journal.head
  let aborted ← try
    let _ ← DB.PageMap.withWriter (α := Unit) journal fun writer => do
      ReplayWork.register writer base (Index.contentKey "aborted dependency") laterInputs
      writer.flush
      throw (IO.userError "intentional aborted registration")
    pure false
    catch _ => pure true
  let reopened ← DB.PageMap.pin journal.directory
  let abortAtomic := aborted && reopened.head == beforeAbort &&
    (← reopened.get (ReplayWork.jobKey base (Index.contentKey "aborted dependency"))).isNone
  let report := Json.mkObj [
    ("unchangedRegistrationPreservesCursor",toJson preserved),
    ("unchangedRegistrationRepeatsNoFeedWork",toJson noRepeat),
    ("repeatBlocks",toJson again.blocks),("repeatRows",toJson again.rows),
    ("lateDependencyPreservesSharedCursor",toJson newPreserved),
    ("lateDependencyRequeuesOnlyItself",toJson (queuedLate && originalNotQueued)),
    ("abortedRegistrationAtomic",toJson abortAtomic),("answeringModelCalls",toJson (0 : Nat)),
    ("sustained80PersonCapacityValidated",toJson false)]
  IO.FS.writeFile (root/"result.json") report.pretty
  IO.println report.compress
  if mode == "verify" then
    check (preserved && noRepeat && newPreserved && queuedLate && originalNotQueued && abortAtomic)
      "registration rewinds source progress or loses a late dependency"
