import tools.research.StudySeedChecks
import Eggshell.Install
open Lean Eggshell Eggshell.Research

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- One real hook, a fresh session and the already prepared immutable DB.
No model, full warm, source copy, gold-dependent input or old memo replay. -/
def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "output directory required")
  let destination := System.FilePath.mk output
  unless !(← destination.pathExists) do throw (IO.userError "keep previous replay")
  IO.FS.createDirAll destination
  let candidate := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/prepared-record-delivery-20261027"
  let trial := candidate / "fixed-source-hooks"
  let database := trial / "work.egg"
  let original ← DB.PageMap.pin database
  let files ← StudyRuntime.files database
  unless (← Synapses.Index.openShared? original).isSome &&
      (← Synapses.CanonicalSource.Cache.ready original) do throw (IO.userError "prepared DB is unavailable; replay never warms")
  let installRoot := destination / "prefix"
  let binary := installRoot / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",(candidate / "product-build/StudyMain").toString,binary.toString]}
  unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
  let plugin := installRoot / "share/eggshell/codex-plugin"
  let launcher := plugin / "bin/eggshelld"
  IO.FS.createDirAll launcher.parent.get!
  IO.FS.writeFile launcher (Install.pluginLauncher installRoot)
  IO.setAccessRights launcher {
    user := {read := true,write := true,execution := true}
    group := {read := true,execution := true}
    other := {read := true,execution := true}}
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",
    "/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/share/eggshell/minilm",
    (installRoot / "share/eggshell/minilm").toString]}
  unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  let config := destination / "config.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
    (toJson #[binary.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson database.toString).compress ++ "\n[profiles.work]\nread = [\"work\"]\nhandoff_chars = 120000\n")
  let data := trial / "data"
  let environment := #[
    ("EGGSHELL_PREFIX",some installRoot.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),
    ("EGGSHELL_HANDOFF_TRACE",some (destination / "handoff-trace.txt").toString),
    ("PLUGIN_ROOT",some plugin.toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
  let publisher ← StudyRuntime.startPublisher binary data environment true
  let session := "prepared-record-replay-2"
  try
    let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") environment
    try
      let request ← read (trial / "topic-2/hook/stdin")
      let request := request.setObjVal! "session_id" (toJson session)
        |>.setObjVal! "turn_id" (toJson "prepared-replay")
        |>.setObjVal! "_eggshell_config" (toJson config.toString)
      let cwd ← IO.ofExcept (request.getObjValAs? String "cwd")
      let result ← StudyCommand.run binary.toString #["codex-hook"] environment cwd (request.compress ++ "\n")
        (destination / "hook") 35000
      let reply ← IO.ofExcept (Json.parse result.stdout)
      let body := ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
      IO.FS.writeFile (destination / "body.txt") body
      let old ← read (trial / "topic-2/audit-input.json")
      let input := old.setObjVal! "request" (toJson (destination / "hook/stdin").toString)
        |>.setObjVal! "stdout" (toJson (destination / "hook/stdout").toString)
        |>.setObjVal! "timing" (toJson (destination / "hook/record.json").toString)
        |>.setObjVal! "body" (toJson (destination / "body.txt").toString)
      IO.FS.writeFile (destination / "audit-input.json") input.pretty
      let audit ← NativeTrialAudit.inspect (destination / "audit-input.json").toString
      unless audit.getObjValD "frozenEvidence" == (← read (trial / "topic-2/audit.json")).getObjValD "frozenEvidence" do
        throw (IO.userError "frozen source evidence changed")
      IO.FS.writeFile (destination / "audit.json") audit.pretty
      let summary := Json.mkObj [("elapsedMs",toJson result.elapsedMs),("actualHook",toJson true),
        ("warmCalls",toJson (0 : Nat)),("modelCalls",toJson (0 : Nat)),("newSeedStudy",toJson false),
        ("adopted",toJson false),("bodyBytes",toJson body.utf8ByteSize),
        ("runtimeSha256",toJson (← ArtifactHash.hex binary)),
        ("requiredDelivery",audit.getObjValD "requiredDelivery")]
      IO.FS.writeFile (destination / "result.json") summary.pretty
      IO.println summary.compress
    finally StudyRuntime.stopManaged managed (destination / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (destination / "publisher-shutdown.json")
  unless (← DB.PageMap.pin database).head == original.head && (← StudyRuntime.files database) == files do
    throw (IO.userError "replay changed its immutable source")
