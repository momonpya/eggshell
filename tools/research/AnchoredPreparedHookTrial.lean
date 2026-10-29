import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.StudyHistory
import tools.research.NativeTrialAudit
import Eggshell.Install
import Eggshell.SynapseJournal
open Lean Eggshell Eggshell.Research Eggshell.Synapses

private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)

private def cacheLifecycle (root : System.FilePath) (doc : Extraction.Document)
    (parent : ContentCapture.Captured) (extra : ContentCapture.Supplement) : IO Json := do
  let source ← DB.PageMap.create root "supplement-cache fixture"
  let _ ← Synapses.Index.replace source .database .shared #[]
  let before ← CanonicalSource.Cache.refresh source .database
  let some index ← Synapses.Index.open? source .database .shared |
    throw (IO.userError "fixture index missing")
  let _ ← DB.PageMap.withWriter index.index fun writer =>
    ContentMetadata.stageSupplement writer source.head.identity 7 doc parent extra
  unless (← CanonicalSource.Cache.open? source .database).isNone &&
      !(← CanonicalSource.Cache.ready source) do
    throw (IO.userError "changed supplement retained stale ready cache")
  let path ← CanonicalSource.Cache.directory source .database
  unless (← CanonicalSource.Cache.preparedAt? source path before.metadata).isSome do
    throw (IO.userError "supplement publication invalidated a pinned old reader")
  let after ← CanonicalSource.Cache.refresh source .database
  unless after.metadata.supplements.isSome && after.metadata.supplements != before.metadata.supplements &&
      (← CanonicalSource.Cache.open? source .database).isSome &&
      (← CanonicalSource.Cache.preparedAt? source path before.metadata).isSome &&
      (← DB.PageMap.pin root).head == source.head do
    throw (IO.userError "supplement preparation did not preserve source and pinned readers")
  return Json.mkObj [("staleReadyRejected",toJson true),("pinnedReaderRetained",toJson true),
    ("newReadyPublished",toJson true),("originalUnchanged",toJson true)]

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
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let name := args.headD "trial"
  let runtime := (args[1]?).getD ((root / "product-build/StudyMain").toString)
  let prepared := System.FilePath.mk ((args[2]?).getD ((study / "study/seed-2/work.egg").toString))
  let supplements := System.FilePath.mk ((args[3]?).getD ((root / "anchored-capture/seed-refinement.json").toString))
  let prepareUsage := args[4]? == some "usage"
  unless name.toList.all (fun c => c.isAlphanum || c == '-') do throw (IO.userError "safe new trial name required")
  let target := root / name
  unless !(← target.pathExists) do throw (IO.userError "preserve previous trial")
  let manifest := study / "r0/stage1/history/history.json"
  let _ ← StudyHistory.fork ⟨manifest.toString,← ArtifactHash.hex manifest⟩ target
  let database := target / "work.egg"
  let original ← StudyRuntime.files database
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",
    (prepared / "derived").toString,(database / "derived").toString]}
  unless copied.exitCode == 0 do throw (IO.userError copied.stderr)
  let source ← DB.PageMap.pin database
  let mandatorySpec := (← read (study / "r0/stage1/preparation/audit-input.json")).getObjValD "source"
  let mandatoryBefore ← NativeTrialAudit.freezeAvailable mandatorySpec
  IO.FS.writeFile (target / "available-before-delivery.json") (toJson mandatoryBefore).pretty
  let derivation ← read supplements
  unless derivation.getObjValD "source" == toJson source.head do
    throw (IO.userError "supplement preparation differs from the frozen source")
  let entries : Array (Nat × String × ContentCapture.Supplement) ←
    IO.ofExcept (derivation.getObjValAs? _ "supplements")
  let reader ← Persistence.Store.NodeReader.new source
  let mut additions := #[]
  let mut lifecycle := Json.null
  for (id,owner,value) in entries do
    let document ← Synapses.Build.document reader id
    unless document.owner == owner do throw (IO.userError "supplement crossed its original owner")
    if value.sealed then
      additions := additions.push (id,value)
      if lifecycle == Json.null && !value.aliases.isEmpty then
        let some parent ← ContentMetadata.load? source id document |
          throw (IO.userError "supplement lost its stored parent")
        lifecycle ← cacheLifecycle (target / "cache-lifecycle") document parent value
  IO.FS.writeFile (target / "cache-lifecycle.json") lifecycle.pretty
  let previousStamp ← (← Synapses.Index.open? source .database .shared).bindM fun index =>
    ContentMetadata.supplementStamp index.index
  let started ← IO.monoMsNow
  let publication ← Synapses.Build.refresh source .database additions
  let canonical ← Synapses.CanonicalSource.Cache.refresh source .database
  let again ← Synapses.Build.refresh source .database
  unless again.mode == "warm" && (← Synapses.CanonicalSource.Cache.open? source .database).isSome &&
      (← DB.PageMap.pin database).head == source.head do
    throw (IO.userError "prepared supplement was not reusable without source mutation")
  IO.FS.writeFile (target / "supplement-publication.json") (Json.mkObj [
    ("previousStamp",toJson previousStamp),("owners",toJson additions.size),
    ("publication",toJson publication),("canonical",toJson canonical),
    ("reuse",toJson again),("sourceUnchanged",toJson true),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started))]).pretty
  let installation := root / "prefix"
  let binary := installation / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  IO.FS.writeBinFile binary (← IO.FS.readBinFile (.mk runtime))
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
    if prepareUsage then
      unless (← Paths.dataRoot) == data do throw (IO.userError "usage preparation requires the isolated trial data root")
      let some journal ← Journal.open? source | throw (IO.userError "common input lost its native journal")
      let originalJournal := journal.head
      let began ← IO.monoMsNow
      let replayed ← Journal.refresh source .database (began+120000) 64
      unless replayed.complete && replayed.pending == 0 && !(← Journal.required source) do
        throw (IO.userError "private usage preparation did not complete")
      let some usage ← UsageCache.open? source | throw (IO.userError "prepared usage index is missing")
      let facts ← Index.allFacts usage.index
      let mut queries := #[]
      for number in [1,2,3] do
        let prompt ← IO.FS.readFile (study / "prompts" / s!"topic-{number}.txt")
        let query := Sha256.hex prompt.toUTF8
        let found ← usage.lookup (.query query) 100000 ((← IO.monoMsNow)+5000)
        unless found.complete do throw (IO.userError "incomplete fixed-query usage audit")
        queries := queries.push (Json.mkObj [("topic",toJson number),("query",toJson query),
          ("directUsageFacts",toJson found.facts.size)])
      let some after ← Journal.open? source | throw (IO.userError "usage preparation lost the raw journal")
      let count ← Persistence.Store.getNat journal.get "count"
      for ordinal in [:count] do
        unless (← Journal.entry journal ordinal) == (← Journal.entry after ordinal) do
          throw (IO.userError "usage preparation changed an original native observation")
      IO.FS.writeFile (target / "usage-preparation.json") (Json.mkObj [
        ("result",toJson replayed),("elapsedMs",toJson ((← IO.monoMsNow)-began)),
        ("usageHead",toJson usage.index.head),("facts",toJson facts.size),("queries",Json.arr queries),
        ("rawJournalBefore",toJson originalJournal),("rawJournalAfter",toJson after.head),
        ("originalEntriesExact",toJson true)]).pretty
    let session := "published-recipes-" ++ name
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
          let mandatoryInput := input.setObjVal! "source" mandatorySpec
          IO.FS.writeFile (target / "mandatory-audit-input.json") mandatoryInput.pretty
          let mandatory ← NativeTrialAudit.inspect (target / "mandatory-audit-input.json").toString
          unless mandatory.getObjValD "availableEvidence" == toJson mandatoryBefore do
            throw (IO.userError "DB-backed delivery obligations changed after opening the body")
          IO.FS.writeFile (target / "mandatory-audit.json") mandatory.pretty
          IO.println (Json.mkObj [("delivery",audit.getObjValD "requiredDelivery"),
            ("availableDelivery",mandatory.getObjValD "availableDelivery"),
            ("elapsedMs",toJson result.elapsedMs),("modelCalls",toJson (0 : Nat))]).compress
    finally StudyRuntime.stopManaged managed (target / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (target / "publisher-shutdown.json")
  unless (← StudyRuntime.files database) == original do throw (IO.userError "original source publication changed")
