import Lean.Data.Json.FromToJson
open Lean
def main (args : List String) : IO Unit := do
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let library := (base/"interest-lifetime-build/lib").toString++":"++
    (base/"interest-lifetime-core/.lake/build/lib/lean").toString++":"++toolchain++"/lib/lean"
  let tag := args.head?.getD "interest-lifetime-laws"
  unless tag.startsWith "interest-lifetime-laws" do throw (IO.userError "controlled proof tag required")
  unless !(← (base/(tag++".guard.json")).pathExists) do throw (IO.userError "retain previous proof run")
  let value := Json.mkObj [
    ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1","LEAN_PATH="++library,
      toolchain++"/bin/lean","-M1024",(project/"tools/research/InterestLifetimeLaws.lean").toString]),
    ("cwd",toJson (base/"interest-lifetime-core").toString),
    ("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat))]
  IO.FS.writeFile (base/(tag++".guard-settings.json")) value.pretty
