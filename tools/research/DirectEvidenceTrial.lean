import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
import tools.research.NativeTrialAudit
import Eggshell.Install
open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)

private def frameChecks : IO Unit := do
  let file : File := ⟨"src.cc",String.ofList (List.replicate 64 'a'),6⟩
  let occurrence : Occurrence := ⟨"fixture-session","fixture-turn","fixture-read"⟩
  let binding : Binding := ⟨String.ofList (List.replicate 64 'b'),"fixture-owner","fixture-work",2,7⟩
  let saved : Read := {occurrence,source := ⟨file,1,1⟩,binding}
  let row : CanonicalSource.StoredRow := ⟨⟨file,1⟩,"alpha",#[⟨occurrence,binding⟩]⟩
  let document : Extraction.Document := {
    owner := binding.owner,work := binding.work,workText := some "Bash\n{}",source := some "1\talpha\n"
    native := true,occurrences := #[occurrence],files := #[file]}
  let frame := CanonicalSource.Packet.fileFrame file #[row]
  let body := CanonicalSource.Packet.wrapper ++ frame.leading ++ CanonicalSource.Packet.rowText row ++
    frame.trailing ++ CanonicalSource.Packet.footer
  unless (Extraction.sharedPresented body #[document] #[saved]).size == 1 do
    throw (IO.userError "compact origin framing lost genuine original bytes")
  for (before,after) in #[("alpha","omega"),(binding.work,"another-work"),
      (binding.database,String.ofList (List.replicate 64 'c')),(occurrence.useId,"another-read")] do
    unless (Extraction.sharedPresented (body.replace before after) #[document] #[saved]).isEmpty do
      throw (IO.userError "forged code or original identity was credited")

def main (args : List String) : IO Unit := do
  frameChecks
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "direct-evidence"
  let name := args.headD "trial"
  unless name.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "safe new trial name required")
  let target := root / name
  unless !(← target.pathExists) do throw (IO.userError "preserve previous trial")
  let manifest := study / "r0/stage1/history/history.json"
  let _ ← StudyHistory.fork ⟨manifest.toString,← ArtifactHash.hex manifest⟩ target
  let database := target / "work.egg"
  let original ← StudyRuntime.files database
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",
    (study / "study/seed-2/work.egg/derived").toString,(database / "derived").toString]}
  unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
  let installation := root / "prefix"
  let binary := installation / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  IO.FS.writeBinFile binary (← IO.FS.readBinFile (root / "product-build/StudyMain"))
  IO.setAccessRights binary {
    user := {read := true,write := true,execution := true}
    group := {read := true,execution := true}
    other := {read := true,execution := true}}
  let plugin := installation / "share/eggshell/plugin"
  IO.FS.createDirAll (plugin / "bin")
  IO.FS.writeFile (plugin / "bin/eggshelld") (Install.pluginLauncher installation)
  let model := installation / "share/eggshell/minilm"
  if !(← model.pathExists) then
    let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",(study / "prefix/share/eggshell/minilm").toString,model.toString]}
    unless linked.exitCode == 0 do throw (IO.userError linked.stderr)
  let config := target / "config.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
    (toJson #[binary.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson database.toString).compress ++
    "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let data := target / "data"
  let environment := #[("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_PROFILE",some "work"),("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),
    ("EGGSHELL_HANDOFF_TRACE",some (target / "handoff.trace").toString),
    ("EGGSHELL_TRACE_SELECTION_RANGES",some "1"),("EGGSHELL_TRACE_SELECTOR_INPUT",some "1"),
    ("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),
    ("TOKENIZERS_PARALLELISM",some "false")]
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let publisher ← StudyRuntime.startPublisher binary data environment
  try
    let warm ← StudyCommand.run binary.toString #["egg","warm","work"] environment workspace "" (target / "warm") 240000
    unless warm.exitCode == 0 do throw (IO.userError "candidate preparation did not complete")
    let session := "direct-evidence-" ++ name
    let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") environment
    try
      let prompt ← IO.FS.readFile (study / "prompts/topic-1.txt")
      for event in #["SessionStart","UserPromptSubmit"] do
        let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
          ("turn_id",toJson "first"),("cwd",toJson workspace),("_eggshell_config",toJson config.toString)] ++
          if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
        let result ← StudyCommand.run binary.toString #["codex-hook"] environment workspace
          (request.compress ++ "\n") (target / event) 35000
        if event == "UserPromptSubmit" then
          let reply ← IO.ofExcept (Json.parse result.stdout)
          let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
          IO.FS.writeFile (target / "body.txt") body
          let previous ← read (study / "all-citations-audit-input.json")
          let input := Json.mkObj [("source",previous.getObjValD "source"),("database",toJson database.toString),
            ("request",toJson (target / event / "stdin").toString),("stdout",toJson (target / event / "stdout").toString),
            ("timing",toJson (target / event / "record.json").toString),("body",toJson (target / "body.txt").toString)]
          IO.FS.writeFile (target / "audit-input.json") input.pretty
          let audit ← NativeTrialAudit.inspect (target / "audit-input.json").toString
          IO.FS.writeFile (target / "audit.json") audit.pretty
          IO.println (Json.mkObj [("delivery",audit.getObjValD "requiredDelivery"),
            ("elapsedMs",toJson result.elapsedMs),("modelCalls",toJson (0 : Nat))]).compress
    finally StudyRuntime.stopManaged managed (target / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (target / "publisher-shutdown.json")
  unless (← StudyRuntime.files database) == original do throw (IO.userError "original source publication changed")
