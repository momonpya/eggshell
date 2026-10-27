import tools.research.StudySeedChecks
import tools.research.StudyWorkerProbe
import Eggshell.Install
import Eggshell.WindowOwners
open Lean Eggshell Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def checkReadScope : IO Unit := do
  let seen ← IO.mkRef (#[] : Array DB.Sidecar.Storage)
  let primary ← Synapses.Recommend.readablePrepared? (α := Nat) fun storage => do
    seen.modify (·.push storage)
    pure (some (if storage == .database then 7 else 99))
  check (primary == some 7 && (← seen.get) == #[.database]) "a ready shared view was not reused directly"
  seen.set #[]
  let fallback ← Synapses.Recommend.readablePrepared? (α := Nat) fun storage => do
    seen.modify (·.push storage)
    if storage == .database then throw (.permissionDenied none 13 "fixture")
    pure (some 11)
  check (fallback == some 11 && (← seen.get) == #[.database,.user]) "unreadable shared view prevented private reuse"
  seen.set #[]
  let corruptAccepted ← try
    let _ ← Synapses.Recommend.readablePrepared? (α := Nat) fun storage => do
      seen.modify (·.push storage)
      if storage == .database then throw (IO.userError "fixture corruption")
      pure (some 11)
    pure true
    catch _ => pure false
  check (!corruptAccepted && (← seen.get) == #[.database]) "corrupt shared data was silently treated as a miss"

/-- Exactly one old-snapshot diagnostic. Reuse numerical/lexical preparation;
rebuild only the changed synaptic and original-source views, before the hook.
No answering model, all-topic retry, or foreground repair. -/
def main (args : List String) : IO Unit := do
  checkReadScope
  let (candidate,output,prepared,captureRanges,diagnostic,captureInput) ← match args with
    | [candidate,output,prepared] => pure (candidate,output,System.FilePath.mk prepared,false,false,false)
    | [candidate,output,prepared,"ranges"] => pure (candidate,output,System.FilePath.mk prepared,true,false,false)
    | [candidate,output,prepared,"worker"] => pure (candidate,output,System.FilePath.mk prepared,false,true,false)
    | [candidate,output,prepared,"selector-input"] => pure (candidate,output,System.FilePath.mk prepared,false,true,true)
    | _ => throw (IO.userError "candidate, new output directory and explicit prepared checkpoint required")
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "keep previous actual hook"
  IO.FS.createDirAll root
  let study := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
  let database := prepared / "work.egg"
  let original ← DB.PageMap.pin database
  check (original.head.identity == "76352b67a9c35002bff67dc3d3c3a01b7bd194e43e09f5f54714dde75df5a8de" &&
    original.head.revision == 31 && original.head.bytes == 45216846) "wrong fixed source"
  let sourceFiles ← StudyRuntime.files database
  let data := root / "data"
  IO.FS.createDir data
  let shared ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(prepared / "read-cache").toString,(data / "read-cache").toString]}
  check (shared.exitCode == 0) "could not reuse private read preparation"
  let frozen ← read (study / "seed-1-complete-audit.json")
  let availability ← IO.ofExcept (frozen.getObjValAs? (Array Json) "availability")
  let some required := availability.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some 2) |
    throw (IO.userError "missing frozen topic")
  IO.FS.writeFile (root / "frozen-before-delivery.json") required.pretty
  let started ← IO.monoMsNow
  let synapses ← Synapses.Build.refresh original .database
  let canonical ← Synapses.CanonicalSource.Cache.refresh original .database
  let owners ← WindowOwners.refresh original .database
  IO.FS.writeFile (root / "changed-views.json") (Json.mkObj [("synaptic",toJson synapses),
    ("canonical",toJson canonical),("windowOwners",toJson owners),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
    ("fullWarmCalls",toJson (0 : Nat)),("numericalLexicalPreparationReused",toJson true)]).pretty
  check ((← Synapses.Index.openShared? original).isSome && (← Synapses.CanonicalSource.Cache.ready original))
    "changed views did not become ready"
  check ((← WindowOwners.openShared? original).isSome) "numerical window-owner view is not ready"
  let installRoot := root / "prefix"
  let binary := installRoot / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",candidate ++ "/product-build/StudyMain",binary.toString]}
  check (copied.exitCode == 0) "could not select fixed product"
  let runtimeSha ← ArtifactHash.hex binary
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
  check (linked.exitCode == 0) "could not select existing MiniLM boundary"
  let config := root / "config.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
    (toJson #[binary.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson database.toString).compress ++ "\n[profiles.work]\nread = [\"work\"]\nhandoff_chars = 120000\n")
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let environment := #[
    ("EGGSHELL_PREFIX",some installRoot.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),
    ("EGGSHELL_HANDOFF_TRACE",some (root / "handoff-trace.txt").toString),
    ("EGGSHELL_TRACE_SELECTION_RANGES",if captureRanges then some "1" else none),
    ("EGGSHELL_TRACE_SELECTOR_INPUT",if captureInput then some "1" else none),
    ("PLUGIN_ROOT",some plugin.toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
  let definitions ← IO.ofExcept (Json.parse (← IO.FS.readFile (study / "task-definitions.json")) >>= Json.getArr?)
  let some definition := definitions.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some 2) |
    throw (IO.userError "missing fixed question")
  let prompt ← IO.FS.readFile (.mk (← IO.ofExcept ((definition.getObjValD "prompt").getObjValAs? String "path")))
  check (Sha256.hex prompt.toUTF8 == (← IO.ofExcept ((definition.getObjValD "prompt").getObjValAs? String "sha256")))
    "fixed question changed"
  let publisher ← StudyRuntime.startPublisher binary data environment
  try
    let session := "packet-ledger-one-native-hook"
    let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") environment
    try
      let request := Json.mkObj [("hook_event_name",toJson "UserPromptSubmit"),("session_id",toJson session),
        ("turn_id",toJson "source-turn"),("cwd",toJson workspace),("prompt",toJson prompt),
        ("_eggshell_config",toJson config.toString)]
      let commandRoot := root / (if diagnostic then "worker" else "hook")
      let output ← if diagnostic then StudyWorkerProbe.run binary database data session workspace prompt environment commandRoot
        else StudyCommand.run binary.toString #["codex-hook"] environment workspace (request.compress ++ "\n") commandRoot 35000
      let body ← if diagnostic then do
          let some last := (output.stdout.splitOn "\n" |>.filter (!·.isEmpty)).getLast? |
            throw (IO.userError "worker did not return a frame")
          let frame ← IO.ofExcept (Json.parse last >>= fromJson? (α := Plugin.Worker.SearchFrame))
          let .reply _ handoff := frame | throw (IO.userError "worker did not complete")
          pure (handoff.map (·.text) |>.getD "")
        else do
          let reply ← IO.ofExcept (Json.parse output.stdout)
          pure (((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD "")
      IO.FS.writeFile (root / "body.txt") body
      let specification := Json.mkObj [("source",toJson database.toString),("workspace",toJson workspace),
        ("prompt",toJson prompt),("files",toJson sourceFiles),("required",definition.getObjValD "referenceRanges")]
      let auditInput := Json.mkObj [("source",specification),("database",toJson database.toString),
        ("request",toJson (commandRoot / "stdin").toString),("stdout",toJson (commandRoot / "stdout").toString),
        ("timing",toJson (commandRoot / "record.json").toString),("body",toJson (root / "body.txt").toString)]
      IO.FS.writeFile (root / "audit-input.json") auditInput.pretty
      let audit ← if diagnostic then NativeTrialAudit.inspectWorker (root / "audit-input.json").toString
        else NativeTrialAudit.inspect (root / "audit-input.json").toString
      check (audit.getObjValD "frozenEvidence" == required.getObjValD "frozenEvidence") "frozen denominator changed"
      IO.FS.writeFile (root / "audit.json") audit.pretty
      IO.FS.writeFile (root / "result.json") (Json.mkObj [("actualHook",toJson (!diagnostic)),
        ("diagnosticOnly",toJson diagnostic),("latencyAcceptance",toJson (!diagnostic)),
        ("deadlineMs",toJson (if diagnostic then (120000 : Nat) else 30000)),
        ("elapsedMs",toJson output.elapsedMs),("exitCode",toJson output.exitCode),
        ("runtimeSha256",toJson runtimeSha),("bodyBytes",toJson body.utf8ByteSize),
        ("requiredDelivery",audit.getObjValD (if diagnostic then "coverageWithoutDeadline" else "requiredDelivery")),("modelCalls",toJson (0 : Nat)),
        ("newSeedStudy",toJson false),("adopted",toJson false)]).pretty
    finally StudyRuntime.stopManaged managed (root / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (root / "publisher-shutdown.json")
  check ((← DB.PageMap.pin database).head == original.head) "read-only hook changed the source"
