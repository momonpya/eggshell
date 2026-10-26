import Lean.Data.Json.FromToJson
open Lean

/-- Seal a resource-bounded, read-only explanation of existing receipts. -/
def main (args : List String) : IO Unit := do
  let (rootPath,receipts,owner,label,range) ← match args with
    | [a,b,c,d] => pure (a,b,c,d,([] : List String))
    | [a,b,c,d,first,limit] => pure (a,b,c,d,[first,limit])
    | [a,b,c,d,first,limit,source] => pure (a,b,c,d,[first,limit,source])
    | _ => throw (IO.userError "PrepareDeliveryExplain ROOT RECEIPTS OWNER LABEL [FIRST LIMIT [SOURCE]]")
  let root := System.FilePath.mk rootPath
  unless root.isAbsolute && (← root.isDir) && !label.isEmpty &&
      label.toList.all (fun char => char.isAlphanum || char == '-') do
    throw (IO.userError "existing absolute root and simple label required")
  let path := root / (label ++ ".settings.json")
  let output := root / (label ++ ".json")
  unless !(← path.pathExists) && !(← output.pathExists) do throw (IO.userError "keep earlier explanation")
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let parent := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
  let leanRoot := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  IO.FS.writeFile path (Json.mkObj [
    ("record",toJson (root / (label ++ ".guard.json")).toString),
    ("cwd",toJson project),("ownedPrefixes",toJson #[root.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("command",toJson (#["/usr/bin/env","LEAN_PATH=" ++ parent ++ "/build/lib:" ++
      parent ++ "/checkout/.lake/build/lib/lean:" ++ leanRoot ++ "/lib/lean",
      leanRoot ++ "/bin/lean","--root=" ++ project,"-j1","-M1536","--run",
      project ++ "/tools/research/DeliveryExplain.lean",owner,receipts,output.toString] ++ range.toArray))]).pretty
  IO.println path.toString
