import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "io | proofs")
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let command ← match mode with
    | "io" => pure #[(base / "metadata-build/StudyMain").toString,(base / "metadata-payload-checks").toString]
    | "proofs" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "LEAN_PATH=" ++ (base / "storage-build/lib").toString ++ ":" ++ (base / "product-build/lib").toString,
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-j1","-M2048",
        project ++ "/tools/research/MetadataPayloadProofs.lean"]
    | _ => throw (IO.userError "known metadata check mode required")
  let label := "metadata-" ++ mode
  let path := base / (label ++ ".settings.json")
  unless !(← path.pathExists) do throw (IO.userError "preserve earlier verification settings")
  IO.FS.writeFile path (Json.mkObj [("command",toJson command),("cwd",toJson project),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (base / (label ++ ".guard.json")).toString)]).pretty
