import Lean.Data.Json.Parser
open Lean

/-- Reuse the previously proved ordering algebra and point-update tree only.
The failed all-leaf refresh algorithm is deliberately not restored. -/
def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let core := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/selector-input-20261027/checkout/tools"
  let patch ← IO.FS.readFile (project / "docs/candidates/tournament-selection/core.patch")
  for (name,destination) in [("StableTournament","StableWinnerIndex"),("SelectionRating","SelectionRating")] do
    let path := core / (destination ++ ".lean")
    unless !(← path.pathExists) do throw (IO.userError "preserve existing winner component")
    let marker := "+++ b/tools/" ++ name ++ ".lean\n"
    let some part := (patch.splitOn marker)[1]? | throw (IO.userError "recorded proof component is missing")
    let body := ((part.splitOn "\n--- a/").head!.splitOn "\n").filterMap fun line =>
      if line.startsWith "+" then some (line.drop 1 |>.copy) else none
    let text := String.intercalate "\n" body ++ "\n"
    let text := if name == "StableTournament" then
      (text.splitOn "def Tree.relabel").head! ++ "end StableTournament\n" else text
    IO.FS.writeFile path (text.replace "StableTournament" "StableWinnerIndex")
