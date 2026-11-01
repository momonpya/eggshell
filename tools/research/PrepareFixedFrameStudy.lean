import Lean
import Eggshell.Install
open Lean Eggshell
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def json (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
private def copy (source target : System.FilePath) : IO Unit := do
  let result ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",source.toString,target.toString]}
  check (result.exitCode == 0) "cannot clone reviewed study inputs"
private def privateDir (path : System.FilePath) : IO Unit := do
  IO.FS.createDirAll path
  IO.setAccessRights path {user := {read := true,write := true,execution := true}}

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let shared := study / "shared-snapshot"
  let root := study / "fixed-frame-study"
  let records := project / "docs/candidates/fixed-frame-study"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  check (!(← root.pathExists)) "preserve existing fixed-frame study"
  privateDir root
  IO.FS.createDirAll records
  let core := root / "core"
  copy (shared / "fixed-frame-price-core") core
  IO.FS.createDirAll (core / "docs/benchmarks")
  for name in ["reseed-delivery-contract.json","llvm-three-topics.json","readme-memory-facts.json"] do
    IO.FS.writeFile (core / "docs/benchmarks" / name) (← IO.FS.readFile (project / "docs/benchmarks" / name))
  let modules := #["StudyProfile","StudyProfileChecks","StudyPreparationChecks","StudyAdmission","StudyAcquire","StudyPrepare",
    "StudySeedChecks","StudyBootstrap","StudyStages","StudyMain"]
  for name in modules do
    let target := core / s!"tools/research/{name}.lean"
    if ← target.pathExists then IO.FS.removeFile target
    IO.FS.writeFile target (← IO.FS.readFile (project / s!"tools/research/{name}.lean"))
  let controller := root / "controller"
  copy (shared / "fixed-frame-price-hook-candidate-build") controller
  let settings := root / "controller.settings.json"
  json settings (Json.mkObj [("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (shared / "query-cache-baseline-core").toString),
    ("output",toJson controller.toString),("toolchain",toJson toolchain),
    ("objectModules",toJson (shared / "fixed-frame-price-runtime-build/object-mapping.json").toString),
    ("baselineResponse",toJson (shared / "fixed-frame-price-runtime-build/runtime.rsp").toString),
    ("baselineMain",toJson (shared / "fixed-frame-price-runtime-build/Main.o").toString),
    ("parents",toJson #[(shared / "fixed-frame-price-runtime-build").toString,(study / "controller-build").toString]),
    ("force",toJson (#[] : Array String)),("mainModule",toJson "tools.research.StudyMain")])
  let guard := fun (name : String) (command : Array String) => json (root / (name ++ ".settings.json"))
    (Json.mkObj [("cwd",toJson root.toString),("record",toJson (records / (name ++ ".guard.json")).toString),
      ("command",toJson command),("ownedPrefixes",toJson #[root.toString]),
      ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
  guard "controller-build" #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
    (project / "tools/research/StudyBuildMain.lean").toString,settings.toString]
  guard "profile-checks" #[controller.toString ++ "/StudyMain","profile-checks",(root / "profile-checks").toString,
    (study / "seed-2.plan.json").toString]
  let prefixRoot := root / "prefix"
  IO.FS.createDirAll (prefixRoot / "libexec")
  IO.FS.createDirAll (prefixRoot / "share/eggshell")
  copy (shared / "fixed-frame-price-runtime-build/StudyMain") (prefixRoot / "libexec/eggshell")
  copy (study / "prefix/share/eggshell/minilm") (prefixRoot / "share/eggshell/minilm")
  let plugin := prefixRoot / "plugins/eggshell"
  IO.FS.createDirAll (plugin / ".codex-plugin")
  IO.FS.createDirAll (plugin / "hooks")
  IO.FS.createDirAll (plugin / "bin")
  IO.FS.writeFile (plugin / ".codex-plugin/plugin.json") Install.pluginManifest
  IO.FS.writeFile (plugin / Install.ownerMarkerName) Install.ownerMarkerContents
  let mut manifest ← IO.ofExcept (Json.parse Install.hooksManifest)
  let mut hooks ← IO.ofExcept (manifest.getObjVal? "hooks")
  for event in ["UserPromptSubmit","PreToolUse","PostToolUse"] do
    let groups ← IO.ofExcept (hooks.getObjValAs? (Array Json) event)
    let groups ← groups.mapM fun group => do
      let handlers ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks")
      return group.setObjVal! "hooks" (toJson (handlers.map (·.setObjVal! "additionalContextLimit" (toJson (0 : Nat)))))
    hooks := hooks.setObjVal! event (toJson groups)
  manifest := manifest.setObjVal! "hooks" hooks
  json (plugin / "hooks/hooks.json") manifest
  for name in ["egg","eggshelld"] do Install.writeExecutable (plugin / "bin" / name) (Install.pluginLauncher prefixRoot)
  let _ ← Install.updateMarketplace (prefixRoot / ".agents/plugins/marketplace.json") true
  let account := root / "account"
  privateDir account
  -- Credentials are private runtime inputs, never hashed into experiment artifacts or printed.
  let auth := account / "auth.json"
  IO.FS.writeBinFile auth (← IO.FS.readBinFile (study / "account/auth.json"))
  IO.setAccessRights auth {user := {read := true,write := true}}
  let oldConfig ← IO.FS.readFile (study / "account/config.toml")
  let base := (oldConfig.splitOn "[hooks.state.").headD ""
  IO.FS.writeFile (account / "config.toml") (base.replace (study / "prefix").toString prefixRoot.toString)
  privateDir (root / "tmp")
  IO.FS.createDirAll (root / "prompts")
  for topic in [0,1,2,3] do
    IO.FS.writeFile (root / s!"prompts/topic-{topic}.txt") (← IO.FS.readFile (study / s!"prompts/topic-{topic}.txt"))
  let environment : Array (String × Option String) := #[
    ("CODEX_HOME",some account.toString),("TMPDIR",some (root / "tmp").toString),
    ("EGGSHELL_PREFIX",some prefixRoot.toString),("PLUGIN_ROOT",some plugin.toString),
    ("HF_HUB_OFFLINE",some "1"),("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),
    ("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  json (root / "discovery.input.json") (Json.mkObj [
    ("command",toJson #["/Users/ovm/.nodebrew/current/bin/codex","--strict-config","-c","features.remote_plugin=false","app-server","--listen","stdio://"]),
    ("cwd",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
    ("environment",toJson environment),("output",toJson (root / "discovery").toString),
    ("timeoutMs",toJson (60000 : Nat)),("responseBytes",toJson (33554432 : Nat)),("transcriptBytes",toJson (268435456 : Nat))])
  guard "discovery" #[controller.toString ++ "/StudyMain","probe",(root / "discovery.input.json").toString]
  json (records / "plan.json") (Json.mkObj [
    ("candidateRuntimeSha256",toJson "a109b39d9911fbfcc03ba8ea3133b81958595373998857b593dac713d147dadc"),
    ("candidateHandoffChars",toJson (500000 : Nat)),("candidateNativeByteCap",toJson (512000 : Nat)),
    ("controlRuntimeSha256",toJson "27708291ad028369de099c0faef4f1ef839841262d6bd03e789ccef1ced6a0fe"),
    ("controlHandoffChars",toJson (120000 : Nat)),("controlNativeByteCap",toJson (128000 : Nat)),
    ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
    ("modelInput",toJson "Both arms use additionalContextLimit=0 with a sealed, bounded native packet. Do not equate hook stdout with verified model input. Inspect actual hook notifications and the full model-visible packet receipt."),
    ("steps",toJson "Typed arm budget transfer checks; metadata-only real App Server model/hooks inspection; trust only the isolated exact bundle; empty-DB native Pre/Post/Stop and source-only recovery; then freeze three independent candidate-runtime seed plans. Six paired stages per block; both arms receive the same common checkpoint, chosen candidate trajectory, and bounded harness. No silent model substitution or retry."),
    ("accounting",toJson "Input+output inclusive tokens, including cached input and failed attempts; seed separately. Report initial/history x topics1/2/3 and every block, preserve quality and <30s; no adoption from delivery alone."),
    ("answeringModelCallsSoFar",toJson (0 : Nat)),("adopted",toJson false)])
  IO.println "Prepared isolated bounded study harness, unchanged candidate runtime and private account."
