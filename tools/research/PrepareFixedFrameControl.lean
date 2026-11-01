import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def copy (source target : System.FilePath) : IO Unit := do
  let result ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",source.toString,target.toString]}
  check (result.exitCode == 0) "cannot clone isolated control input"

/-- Prepare only the reference installation. Candidate runtime, account and
seed files are read-only inputs; neither an answering turn nor a DB is made. -/
def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "fixed-frame-study"
  let prefixRoot := root / "control-prefix"
  let account := root / "control-account"
  check (!(← prefixRoot.pathExists) && !(← account.pathExists)) "preserve isolated control installation"
  copy (root / "prefix") prefixRoot
  IO.FS.removeFile (prefixRoot / "libexec/eggshell")
  copy (study / "shared-snapshot/transport-profile-runtime-build/StudyMain") (prefixRoot / "libexec/eggshell")
  for name in ["egg","eggshelld"] do
    let path := prefixRoot / "plugins/eggshell/bin" / name
    let original ← IO.FS.readFile path
    IO.FS.writeFile path (original.replace (root / "prefix").toString prefixRoot.toString)
    IO.setAccessRights path {user := {read := true,write := true,execution := true}}
  IO.FS.createDir account
  IO.setAccessRights account {user := {read := true,write := true,execution := true}}
  let auth := account / "auth.json"
  IO.FS.writeBinFile auth (← IO.FS.readBinFile (root / "account/auth.json"))
  IO.setAccessRights auth {user := {read := true,write := true}}
  let original ← IO.FS.readFile (root / "account/config.toml")
  let normalized := original.replace (root / "prefix").toString prefixRoot.toString
  IO.FS.writeFile (account / "config.toml") normalized
  check (normalized.replace prefixRoot.toString "<MEMORY_RUNTIME>" ==
    original.replace (root / "prefix").toString "<MEMORY_RUNTIME>") "control account differs beyond runtime prefix"
  let input ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "discovery.input.json")))
  let environment ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let environment : Array (String × Option String) := environment.map fun (name,value) => (name,
    if name == "CODEX_HOME" then some account.toString
    else value.map (fun (value : String) => value.replace (root / "prefix").toString prefixRoot.toString))
  let probe := input.setObjVal! "environment" (toJson environment)
    |>.setObjVal! "output" (toJson (root / "control-discovery").toString)
  IO.FS.writeFile (root / "control-discovery.input.json") probe.pretty
  IO.println "Prepared control prefix and matched isolated account; no model call."
