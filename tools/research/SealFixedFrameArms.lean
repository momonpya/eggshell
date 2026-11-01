import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def save (path : System.FilePath) (value : Json) : IO Unit := do
  check (!(← path.pathExists)) "preserve sealed arm input"
  IO.FS.writeFile path (value.pretty ++ "\n")
private def artifact (path : System.FilePath) : IO Json := do
  check (path.fileName != some "auth.json") "credentials are not evidence"
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal matched arm input"
  return Json.mkObj [("path",toJson path.toString),
    ("sha256",toJson ((result.stdout.splitOn " ").headD ""))]

/-- Seal identical model/hook policy and the two predeclared memory
treatments before any topic delivery. Templates cannot dispatch a model. -/
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/fixed-frame-study"
  let controller ← read (root / "seed-2-isolated.plan.json")
  let candidateConfig ← IO.FS.readFile (root / "account/config.toml")
  let controlConfig ← IO.FS.readFile (root / "control-account/config.toml")
  check (candidateConfig.replace (root / "prefix").toString "<MEMORY_RUNTIME>" ==
    controlConfig.replace (root / "control-prefix").toString "<MEMORY_RUNTIME>")
    "account settings differ beyond memory runtime prefix"
  let mut hookHashes : Option (Array String) := none
  for directory in ["restored-isolation","control-discovery"] do
    let probe ← read (root / directory / "hooks.json")
    let groups ← IO.ofExcept (probe.getObjValAs? (Array Json) "data")
    check (groups.size == 1) "unexpected hook scopes"
    let hooks ← IO.ofExcept (groups[0]!.getObjValAs? (Array Json) "hooks")
    check (hooks.size == 8 && hooks.all (fun hook =>
      hook.getObjValD "enabled" == toJson true && hook.getObjValD "trustStatus" == toJson "trusted" &&
      hook.getObjValD "pluginId" == toJson "eggshell@eggshell")) "unsealed hook policy"
    let hashes ← hooks.mapM fun hook => IO.ofExcept (hook.getObjValAs? String "currentHash")
    if let some previous := hookHashes then check (previous == hashes) "hook policy differs between arms"
    hookHashes := some hashes
  let unused := Json.mkObj [("path",toJson "/unused-template-field"),("sha256",toJson "unused")]
  let preparation := Json.mkObj ((["input","stdout","timing","body","state","shutdown","search","auditInput","auditReport"].map
    fun key => (key,unused)) ++ [("numerical",toJson (#[] : Array Json)),("session",toJson "unused")])
  let common := Json.mkObj (["model","effort","workspace","sourceCommit","prompt","runner","cliWrapper","nativeCli","harness","environment"].map
    fun key => (key,controller.getObjValD key))
  let mut templates := #[]
  for (arm,prefixName,accountName,budget,expected) in [
      ("current","control-prefix","control-account",120000,"27708291ad028369de099c0faef4f1ef839841262d6bd03e789ccef1ced6a0fe"),
      ("candidate","prefix","account",500000,"a109b39d9911fbfcc03ba8ea3133b81958595373998857b593dac713d147dadc")] do
    let runtime ← artifact (root / prefixName / "libexec/eggshell")
    check (runtime.getObjValD "sha256" == toJson expected) "arm runtime changed"
    let plugin := root / accountName / "plugins/cache/eggshell/eggshell/0.1.0"
    let mut files := #[]
    for name in [".codex-plugin/plugin.json",".eggshell-owner","bin/egg","bin/eggshelld","hooks/hooks.json"] do
      files := files.push (← artifact (plugin / name))
    let extra := [("label",toJson ("matched-" ++ arm ++ "-template")),
      ("arm",toJson (if arm == "candidate" then "candidate" else "reference")),("purpose",toJson "comparison"),
      ("topic",toJson (1 : Nat)),("stage",toJson (1 : Nat)),("repetition",toJson (0 : Nat)),
      ("handoffChars",toJson (budget : Nat)),("runtime",runtime),
      ("accountConfiguration",← artifact (root / accountName / "config.toml")),("configuration",unused),
      ("pluginRoot",toJson plugin.toString),("pluginFiles",toJson files),
      ("sourceSnapshot",toJson "/unused-template-source"),("sourceFiles",toJson (#[] : Array Json)),
      ("database",toJson "/unused-template-database"),("databaseFiles",toJson (#[] : Array Json)),
      ("dataRoot",toJson "/unused-template-private"),("privateFiles",toJson (#[] : Array Json)),
      ("preparation",preparation),("output",toJson "/unused-template-output"),("guardRecord",toJson "/unused-template-guard")]
    let template := extra.foldl (fun value (key,item) => value.setObjVal! key item) common
    let path := root / (arm ++ "-template.json")
    save path template
    templates := templates.push (← artifact path)
  save (records / "arm-templates.json") (Json.mkObj [
    ("templates",toJson templates),("controllerSeedPlan",← artifact (root / "seed-2-isolated.plan.json")),
    ("hookHashes",toJson hookHashes),("normalizedAccountSettingsEqual",toJson true),
    ("topicDeliveriesBeforeSeal",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  IO.println "Sealed matched current/candidate templates, exact eight hooks and model policy."
