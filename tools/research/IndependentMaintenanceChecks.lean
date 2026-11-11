import Eggshell.HookFrontend
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.IndependentMaintenanceChecks

/-- Keeping the source epoch permits an older preparation completion to mark
the session quiet. The actual frontend proves this cannot happen after save. -/
theorem unchanged_epoch_can_accept_old_preparation (entry : HookFrontend.Session) :
    (({entry with sourceQuiet := true} : HookFrontend.Session).finishPreparation entry.revision true).quiet = true := by
  simp [HookFrontend.Session.finishPreparation,HookFrontend.Session.quiet]

def run : IO Unit := do
  let entry ← HookFrontend.Session.create "independent-maintenance-control" (← IO.monoMsNow)
  let release ← IO.mkRef false
  let blocked := do
    while !(← release.get) do IO.sleep 1
    pure false
  let first ← IO.asTask blocked .dedicated
  let second ← IO.asTask blocked .dedicated
  let owned := ({} : HookFrontend.OwnedTasks)
    |>.addMaintenance ⟨"blocked-first",0,first⟩
    |>.addMaintenance ⟨"blocked-second",0,second⟩
  try
    unless owned.maintenance.size == HookBudget.maintenance && owned.canSave entry.name do
      throw (IO.userError "blocked preparation consumed source admission")
    let admitted ← owned.startSave entry
    unless admitted.saves.size == 1 && !admitted.canSave entry.name do
      throw (IO.userError "source ownership was absent or duplicated")
    let some work := admitted.saves[0]? | throw (IO.userError "source task was not retained")
    let .ok true ← IO.wait work.task | throw (IO.userError "actual empty source refresh did not finish")
    unless !(← IO.hasFinished first) && !(← IO.hasFinished second) do
      throw (IO.userError "preparation was not held during the source check")
    IO.println (Json.mkObj [("blockedPreparation",toJson (2 : Nat)),("completedSourceRefresh",toJson true),
      ("nativeSourcePublication",toJson false),("newNativeWorkers",toJson (0 : Nat))]).compress
  finally
    release.set true
    discard <| IO.wait first
    discard <| IO.wait second
end Eggshell.Research.IndependentMaintenanceChecks
