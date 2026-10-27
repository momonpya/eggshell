import tools.research.StudyAcquire
import tools.research.StudySeedChecks

open Lean Eggshell Eggshell.Research
namespace Eggshell.Research.StudyBootstrap

private def check (b : Bool) (message : String) : IO Unit :=
  unless b do throw (IO.userError message)

private def save (path : System.FilePath) (value : Json) : IO Unit := do
  check (!(← path.pathExists)) "keep the previous bootstrap evidence"
  IO.FS.writeFile path (value.pretty ++ "\n")

def trustHooks (root : String) : IO Unit := do
  let directory := System.FilePath.mk root
  let runtime ← StudyPrepare.artifact (directory / "prefix/libexec/eggshell")
  let hooks ← StudyAdmission.readJson (directory / "discovery/hooks.json").toString
  let expected ← IO.FS.readFile (directory / "prefix/plugins/eggshell/hooks/hooks.json")
  let mut additions := ""
  let mut pluginRoot := ""
  let mut count := 0
  for group in ← IO.ofExcept (hooks.getObjValAs? (Array Json) "data") do
    for field in #["warnings","errors"] do
      check ((group.getObjValAs? (Array Json) field).toOption.any (·.isEmpty)) "hook discovery failed"
    for hook in ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks") do
      let path ← IO.ofExcept (hook.getObjValAs? String "sourcePath")
      let parent := (System.FilePath.mk path).parent.get!.parent.get!
      check (StudyRuntime.inside directory parent && (← IO.FS.readFile path) == expected)
        "only the exact isolated Eggshell hooks may be trusted"
      StudyAdmission.verifyPluginRuntime runtime parent.toString
      check (pluginRoot.isEmpty || pluginRoot == parent.toString) "multiple plugin roots"
      pluginRoot := parent.toString
      let key ← IO.ofExcept (hook.getObjValAs? String "key")
      let digest ← IO.ofExcept (hook.getObjValAs? String "currentHash")
      additions := additions ++ "\n[hooks.state." ++ (toJson key).compress ++ "]\nenabled = true\ntrusted_hash = " ++
        (toJson digest).compress ++ "\n"
      count := count+1
  check (count == 8) "expected exactly eight reviewed native hooks"
  let configuration := directory / "account/config.toml"
  let handle ← IO.FS.Handle.mk configuration .append
  handle.putStr additions
  handle.flush
  save (directory / "hooks-trusted.json") (Json.mkObj [("runtime",toJson runtime),
    ("pluginRoot",toJson pluginRoot),("hooks",toJson count),("answeringModelCalls",toJson (0 : Nat))])

private def environment (root : System.FilePath) : Array (String × Option String) := #[
  ("CODEX_HOME",some (root / "account").toString),("TMPDIR",some (root / "tmp").toString),
  ("EGGSHELL_PREFIX",some (root / "prefix").toString),
  ("PLUGIN_ROOT",some (root / "prefix/plugins/eggshell").toString),
  ("EGGSHELL_DATA_ROOT",some (root / "native-gate/data").toString),
  ("HF_HUB_OFFLINE",some "1"),("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),
  ("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
  ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]

def seedInput (root : String) : IO Unit := do
  let directory := System.FilePath.mk root
  let trusted ← StudyAdmission.readJson (directory / "hooks-trusted.json").toString
  let runtime ← IO.ofExcept (trusted.getObjValAs? StudyAdmission.Artifact "runtime")
  let pluginRoot ← IO.ofExcept (trusted.getObjValAs? String "pluginRoot")
  StudyAdmission.verifyArtifact runtime
  let files ← StudyAdmission.tree (.mk pluginRoot)
  let pluginFiles := files.map fun (relative,digest) =>
    ({path := (System.FilePath.mk pluginRoot / relative).toString,sha256 := digest} : StudyAdmission.Artifact)
  let input : StudySeedChecks.Input := {runtime,pluginRoot,pluginFiles,environment := environment directory}
  save (directory / "native-gate-input.json") (toJson input)

def sealSeed (root : String) : IO Unit := do
  let directory := System.FilePath.mk root
  let input ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input)
    (← StudyAdmission.readJson (directory / "native-gate-input.json").toString))
  let build ← StudyAdmission.readJson (directory / "controller/build.json").toString
  let mut harness := #[]
  for row in ← IO.ofExcept (build.getObjValAs? (Array Json) "modules") do
    let path ← IO.ofExcept (row.getObjValAs? String "source")
    harness := harness.push (← StudyPrepare.artifact (.mk path))
  let project ← IO.ofExcept (build.getObjVal? "settings" >>= (·.getObjValAs? String "project"))
  for relative in #["tools/research/StudyBuildMain.lean","docs/benchmarks/reseed-delivery-contract.json",
      "docs/benchmarks/llvm-three-topics.json","docs/benchmarks/readme-memory-facts.json"] do
    harness := harness.push (← StudyPrepare.artifact (System.FilePath.mk project / relative))
  let gate := directory / "native-gate"
  let plan : StudyAcquire.Plan := {
    kind := "seed"
    label := "new-native-seed-1"
    model := "gpt-5.6-luna"
    effort := "xhigh"
    provider := "openai"
    workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
    sourceCommit := "6dfe1677ab8dffbc6ec13d53a1e0215d75147689"
    output := (directory / "study/seed-1").toString
    guardRecord := (directory / "seed-1.guard.json").toString
    runtime := input.runtime
    runner := ← StudyPrepare.artifact (← IO.appPath)
    cliWrapper := ← StudyPrepare.artifact "/Users/ovm/.nodebrew/current/bin/codex"
    nativeCli := ← StudyPrepare.artifact "/Users/ovm/.nodebrew/current/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
    accountConfiguration := ← StudyPrepare.artifact (directory / "account/config.toml")
    prompt := ← StudyPrepare.artifact (directory / "prompts/topic-0.txt")
    pluginRoot := input.pluginRoot
    pluginFiles := input.pluginFiles
    harness := harness
    gate := {
      report := ← StudyPrepare.artifact (gate / "result.json")
      guard := ← StudyPrepare.artifact (directory / "native-gate.guard.json")
      shutdown := ← StudyPrepare.artifact (gate / "shutdown.json")
      recovery := ← StudyPrepare.artifact (gate / "recovery.json")
      publisherShutdown := ← StudyPrepare.artifact (gate / "publisher-shutdown.json") }
    environment := input.environment }
  IO.FS.createDirAll (directory / "study")
  save (directory / "seed-1.plan.json") (toJson plan)
  let artifact ← StudyPrepare.artifact (directory / "seed-1.plan.json")
  let limits : StudyTrial.Limits := {inclusiveTokens := 5000000,answerMs := 900000}
  save (directory / "seed-1.limits.json") (toJson limits)
  let budget ← StudyPrepare.artifact (directory / "seed-1.limits.json")
  let settings := Json.mkObj [
    ("cwd",toJson root),("ownedPrefixes",toJson #[root]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (4194304 : Nat)),("record",toJson plan.guardRecord),
    ("command",toJson #[(← IO.appPath).toString,"acquire-bounded",artifact.path,artifact.sha256,budget.path,budget.sha256])]
  save (directory / "seed-1.settings.json") settings

def cliMain (args : List String) : IO UInt32 := do
  try
    match args with
    | ["trust-hooks",root] => trustHooks root
    | ["seed-input",root] => seedInput root
    | ["seal-seed",root] => sealSeed root
    | _ => throw (IO.userError "StudyBootstrap trust-hooks|seed-input|seal-seed ROOT")
    return 0
  catch error => IO.eprintln error.toString; return 1

end Eggshell.Research.StudyBootstrap
