import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def main (args : List String) : IO Unit := do
  let [tag,kind] := args | throw (IO.userError "unique tag and proofs/audit required")
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "front-traffic-" && entry.fileName.endsWith ".guard.json" then
      let prior ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
      unless prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "previous work is still owned")
  unless tag.startsWith "front-traffic-" && !(← (base/(tag++".guard.json")).pathExists) do
    throw (IO.userError "retain previous proof receipt")
  let settings ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"front-traffic-build-settings.json")))
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  let paths := #[(base/"front-traffic-build/lib").toString] ++ parents.map (fun path => path++"/lib") ++
    #[(base/"interest-traffic-core/.lake/build/lib/lean").toString,toolchain++"/lib/lean"]
  let source ← match kind with
    | "proofs" => pure (workspace/"tools/research/TaskDeadlineProofs.lean")
    | "audit" => pure (base/"interest-traffic-core/Eggshell/ContractAudit.lean")
    | _ => throw (IO.userError "proofs/audit required")
  let config := Json.mkObj [
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++String.intercalate ":" paths.toList,
      toolchain++"/bin/lean","-M1024",source.toString]),
    ("cwd",toJson (base/"interest-traffic-core").toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) config.pretty
