import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (text needle replacement : String) : IO String := do
  check ((text.splitOn needle).length == 2) "source reader anchor is absent or ambiguous"
  return text.replace needle replacement
private def region (text first last replacement : String) : IO String := do
  check ((text.splitOn first).length == 2) "source reader region start is ambiguous"
  let before := (text.splitOn first)[0]!
  let tail := (text.splitOn first)[1]!
  check ((tail.splitOn last).length == 2) "source reader region end is ambiguous"
  return before ++ replacement ++ last ++ (tail.splitOn last)[1]!

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let original := root / "query-cache-baseline-core"
  let core := root / "local-reader-core"
  check (!(← core.pathExists)) "preserve a previous source reader candidate"
  let declaration := "public import Eggshell.CanonicalSourcePrepared\n"
  let imported := declaration ++ "public import tools.research.PreparedSourceReader\n"
  let mut client ← IO.FS.readFile (original / "Eggshell/PublicationClient.lean")
  client ← once client declaration imported
  client ← region client "  unless result.identity == reference.identity && result.rows.map Prod.fst == owners &&"
    "def endpoint? : IO (Option Daemon.Endpoint) := do"
    "  Synapses.PreparedSource.checkedRows access owners result\n\n"
  client ← region client "  unless found.identity == reference.identity && some found.index == access.metadata.bindings do"
    "def sourceRecords (reference : SourceReference)"
    "  Synapses.PreparedSource.checkedBindings access wanted allowed found\n\n"
  client ← region client "  unless result.source == access.source && result.rows.map Prod.fst == owners do"
    "def ready (endpoint : Daemon.Endpoint) : IO Unit := do"
    ("  Synapses.PreparedSource.checkedRecords access owners result\n\n" ++
     "def SourceReference.reader (reference : SourceReference) : Synapses.PreparedSource.Reader :=\n" ++
     "  {access := reference.access,rows := sourceRows reference,bindings := sourceBindings reference,records := sourceRecords reference}\n\n" ++
     "theorem SourceReference.reader_identity (reference : SourceReference) : reference.reader.identity = reference.identity := rfl\n\n" ++
     "theorem SourceReference.reader_rows (reference : SourceReference) (owners : Array String) (deadline : Nat) :\n" ++
     "    reference.reader.rows owners deadline = sourceRows reference owners deadline := rfl\n\n" ++
     "theorem SourceReference.reader_bindings (reference : SourceReference) (wanted : Array Synapses.Range)\n" ++
     "    (allowed : Std.HashSet String) (deadline : Nat) :\n" ++
     "    reference.reader.bindings wanted allowed deadline = sourceBindings reference wanted allowed deadline := rfl\n\n" ++
     "theorem SourceReference.reader_records (reference : SourceReference) (owners : Array String) (deadline : Nat) :\n" ++
     "    reference.reader.records owners deadline = sourceRecords reference owners deadline := rfl\n\n")
  let mut recommend ← IO.FS.readFile (original / "Eggshell/SynapseRecommend.lean")
  recommend ← once recommend "  canonical : Option Plugin.Publication.Client.SourceReference := none"
    "  canonical : Option PreparedSource.Reader := none"
  recommend ← once recommend "      pure (prepared,if prepared.isNone then some \"canonical-not-ready\" else none)"
    "      pure (prepared.map Plugin.Publication.Client.SourceReference.reader,if prepared.isNone then some \"canonical-not-ready\" else none)"
  recommend ← once recommend "def Prepared.identity (prepared : Prepared) : Json :="
    ("def Prepared.withReader? (prepared : Prepared) (reader : PreparedSource.Reader) : Option Prepared :=\n" ++
     "  if reader.access.database == prepared.source.head.identity && reader.access.source == prepared.source.head then\n" ++
     "    some {prepared with canonical := some reader,canonicalFailure := none} else none\n\n" ++
     "theorem Prepared.reader_keeps_indexes (prepared result : Prepared) (reader : PreparedSource.Reader)\n" ++
     "    (found : prepared.withReader? reader = some result) :\n" ++
     "    result.source = prepared.source ∧ result.shared = prepared.shared ∧ result.usage = prepared.usage ∧ result.failure = prepared.failure := by\n" ++
     "  unfold Prepared.withReader? at found\n  split at found\n" ++
     "  · cases found; exact ⟨rfl,rfl,rfl,rfl⟩\n  · cases found\n\n" ++
     "def Prepared.identity (prepared : Prepared) : Json :=")
  let mut transport ← IO.FS.readFile (original / "Eggshell/SynapseTransport.lean")
  for (before,after) in [
      ("Plugin.Publication.Client.sourceBindings reference wanted allowed deadline","reference.bindings wanted allowed deadline"),
      ("Plugin.Publication.Client.sourceRows reference ids deadline","reference.rows ids deadline"),
      ("Plugin.Publication.Client.sourceRecords reference ids deadline","reference.records ids deadline")] do
    transport ← once transport before after
  let mut service ← IO.FS.readFile (original / "Eggshell/PublicationService.lean")
  service ← once service declaration imported
  service ← once service
    ("    let prepared ← loaded.rows owners deadline\n" ++
     "    let result : CanonicalSource.Shared.Projection := ⟨access.identity,\n" ++
     "      prepared.map (fun (owner,recipe) => (owner,recipe.rows)),reuse,\n" ++
     "      prepared.map (fun (owner,recipe) => (owner,recipe.records))⟩\n    return toJson result")
    "    return toJson (← PreparedSource.rowsAt access loaded owners deadline)"
  service ← region service
    "    let some original := loaded.originals | throw (IO.userError \"original record view is not prepared\")"
    "def lease (path : System.FilePath) : IO FileSystem.ReadHandle := do"
    ("    let access : CanonicalSource.Shared.Access := ⟨scope.database,scope.scope,\"\",head,metadata,.hit⟩\n" ++
     "    return toJson (← PreparedSource.recordsAt server.structures access loaded owners deadline Stream.maxBytes)\n\n")
  service ← region service
    "    let some original := loaded.originals | throw (IO.userError \"original bindings are not prepared\")"
    "/-- Registration is local administrator authority."
    ("    let access : CanonicalSource.Shared.Access := ⟨scope.database,scope.scope,\"\",head,metadata,.hit⟩\n" ++
     "    return toJson (← PreparedSource.bindingsAt access loaded wanted (Std.HashSet.ofArray allowed) deadline)\n\n" ++
     "/-- The caller must already own the query's admission. A scoped read\n" ++
     "capability is authenticated before borrowing a pinned prepared source.\n" ++
     "Use the handle only inside this continuation. No self-RPC is performed. -/\n" ++
     "def withSourceReader (server : Server) (secret : String) (payload : Json) (deadline : Nat)\n" ++
     "    (use : PreparedSource.Reader → IO α) : IO α := do\n" ++
     "  unless !(← server.stopping.get) && (← IO.monoMsNow) < deadline do\n" ++
     "    throw (IO.userError \"prepared local reader expired or stopped\")\n" ++
     "  let scope ← scopedSource server secret payload\n" ++
     "  let head ← IO.ofExcept (payload.getObjVal? \"source\" >>= fromJson? (α := PageMap.Head))\n" ++
     "  let metadata ← IO.ofExcept (payload.getObjVal? \"metadata\" >>= fromJson? (α := CanonicalSource.Cache.Manifest))\n" ++
     "  unless head.identity == scope.database && metadata.source.identity == scope.database &&\n" ++
     "      metadata.implementation == CanonicalSource.Cache.implementation && digest metadata.payload do\n" ++
     "    throw (IO.userError \"invalid prepared local reader request\")\n" ++
     "  let current ← PageMap.pin scope.directory\n" ++
     "  let some pinned ← PageMap.HistoryReader.make? current head |\n" ++
     "    throw (IO.userError \"prepared local source snapshot retired\")\n" ++
     "  let path ← CanonicalSource.Cache.directory pinned.snapshot scope.storage\n" ++
     "  server.prepared.withReady pinned.snapshot path metadata deadline fun loaded reuse => do\n" ++
     "    let access : CanonicalSource.Shared.Access := ⟨scope.database,scope.scope,scope.capability,head,metadata,reuse⟩\n" ++
     "    let slot ← IO.mkRef (some loaded)\n" ++
     "    try use (PreparedSource.borrowed access slot pinned.snapshot server.prepared.pages path.normalize.toString server.structures server.stopping deadline Stream.maxBytes)\n" ++
     "    finally slot.set none\n\n")
  let helper := "tools/research/PreparedSourceReader.lean"
  let wire ← IO.FS.readFile (original / "Eggshell/PublicationWire.lean")
  let wire ← once wire "  (include_str \"PublicationWire.lean\").toUTF8,"
    "  (include_str \"../tools/research/PreparedSourceReader.lean\").toUTF8,\n  (include_str \"PublicationWire.lean\").toUTF8,"
  -- Validate every transformation before creating an owned checkout.
  let changes := [("Eggshell/PublicationClient.lean",client),("Eggshell/SynapseRecommend.lean",recommend),
    ("Eggshell/SynapseTransport.lean",transport),("Eggshell/PublicationService.lean",service),("Eggshell/PublicationWire.lean",wire)]
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",original.toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate source reader candidate"
  for (name,source) in changes do IO.FS.writeFile (core / name) source
  IO.FS.createDirAll (core / helper).parent.get!
  IO.FS.writeFile (core / helper) (← IO.FS.readFile (project / helper))
  check ((← IO.FS.readFile (core / "Eggshell/Handoff.lean")) ==
    (← IO.FS.readFile (original / "Eggshell/Handoff.lean"))) "source reader changed original selection"
  IO.println "Prepared source reader and authenticated local borrow; remote forwarding and source/usage indexes retained"
