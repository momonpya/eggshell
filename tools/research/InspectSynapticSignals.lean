import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def read (path : System.FilePath) : IO Json := do
  unless (← path.metadata).byteSize ≤ 32*1024*1024 do throw (IO.userError "signal input exceeds bound")
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

def main (args : List String) : IO Unit := do
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/synaptic-signal-audit-20261027"
  let project := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  if args == ["plan"] then
    unless !(← root.pathExists) do throw (IO.userError "preserve previous signal audit")
    IO.FS.createDir root
    IO.FS.writeFile (root / "settings.json") (Json.mkObj [
      ("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-j1","-M2048","--run",
        project ++ "/tools/research/InspectSynapticSignals.lean","inspect"]),
      ("cwd",toJson project),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
      ("ownedPrefixes",toJson #[root.toString]),("record",toJson (root / "guard.json").toString)]).pretty
    return
  unless args == ["inspect"] do throw (IO.userError "plan | inspect")
  let path := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/feedback-context-20261026/walk.json"
  let document ← read path
  let trials ← IO.ofExcept (document.getObjValAs? (Array Json) "trials")
  let mut rows := #[]
  for trial in trials do
    let result := trial.getObjValD "result"
    let offers := (result.getObjValAs? (Array Json) "offers").toOption.getD #[]
    let mut kinds : Std.HashMap String Nat := {}
    let mut withGroup := 0
    for offer in offers do
      let kind := (offer.getObjValAs? String "kind").toOption.getD "untyped"
      kinds := kinds.insert kind (kinds[kind]?.getD 0 + 1)
      if (offer.getObjVal? "group").isOk then withGroup := withGroup+1
    let keys := match trial with | .obj fields => fields.toArray.map Prod.fst | _ => #[]
    let resultKeys := match result with | .obj fields => fields.toArray.map Prod.fst | _ => #[]
    rows := rows.push (Json.mkObj [("keys",toJson keys),("resultKeys",toJson resultKeys),
      ("label",trial.getObjValD "label"),("topic",trial.getObjValD "topic"),
      ("offers",toJson offers.size),("groupFieldPresent",toJson withGroup),
      ("kinds",toJson kinds.toArray),("firstOffers",toJson (offers.extract 0 (min 2 offers.size)))])
  IO.FS.writeFile (root / "legacy-walk-summary.json") (Json.mkObj [("legacyOracle",toJson true),
    ("input",toJson path.toString),("trials",toJson rows),("warmCalls",toJson (0 : Nat)),
    ("modelCalls",toJson (0 : Nat)),("currentRuntimeMeasurement",toJson false)]).pretty
  IO.println (toJson rows).pretty
