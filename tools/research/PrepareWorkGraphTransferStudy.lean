import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "matched WorkGraph transfer anchor changed"
  return source.replace before after
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/workgraph-transfer"
  check (!(← records.pathExists)) "preserve matched transfer experiment"
  IO.FS.createDirAll records
  let coreMaker := project / "tools/research/PrepareWorkGraphTransferCore.lean"
  check (!(← coreMaker.pathExists)) "preserve transfer core preparation"
  IO.FS.writeFile coreMaker ((← IO.FS.readFile (project / "tools/research/PrepareWorkGraphWire.lean"))
    |>.replace "workgraph-wire-core" "workgraph-transfer-core")
  let target := project / "tools/research/WorkGraphTransferHook.lean"
  check (!(← target.pathExists)) "preserve matched transfer producer"
  let mut helper := (← IO.FS.readFile (project / "tools/research/OwnerBindingsHookArm.lean"))
    |>.replace "owner-bindings" "workgraph-transfer"
  helper ← once helper "import Eggshell.Install\n" "import Eggshell.Install\nimport tools.research.FrozenCanonicalBasis\n"
  helper ← once helper "  let some frozen := frozenEntries[0]?"
    ("  let topic ← if mode == \"run\" then do\n" ++
     "    let [_,value] := rest | throw (IO.userError \"repetition and topic required\")\n" ++
     "    let some topic := value.toNat? | throw (IO.userError \"invalid topic\")\n" ++
     "    check ([1,2,3].contains topic) \"outside the declared three topics\"\n" ++
     "    pure topic\n  else pure 1\n  let some frozen := frozenEntries[topic-1]?")
  helper ← once helper "frozen.getObjValD \"topic\" == toJson (1 : Nat)" "frozen.getObjValD \"topic\" == toJson topic"
  helper ← once helper "let [repetition] := rest" "let [repetition,_topicText] := rest"
  helper ← once helper "let destination := saved / (\"rep-\" ++ repetition)"
    "let destination := saved / (\"rep-\" ++ repetition) / s!\"topic-{topic}\""
  helper ← once helper "study / \"prompts/topic-1.txt\"" "study / s!\"prompts/topic-{topic}.txt\""
  helper ← once helper "\"workgraph-transfer-\" ++ arm ++ \"-\" ++ repetition"
    "\"workgraph-transfer-\" ++ arm ++ \"-\" ++ repetition ++ \"-\" ++ toString topic"
  helper ← once helper "IO.FS.writeFile (destination / \"audit.json\") audit.pretty"
    ("IO.FS.writeFile (destination / \"audit.json\") audit.pretty\n" ++
     "          let (pinned,originalRows) ← FrozenCanonicalBasis.load study (study / \"shared-snapshot\")\n" ++
     "          let nodeReader ← Persistence.Store.NodeReader.new pinned\n" ++
     "          let documents ← (← Build.entries pinned).mapM fun entry => Build.document nodeReader entry.id\n" ++
     "          let aliases : Array Read := originalRows.flatMap fun row => row.origins.map fun origin =>\n" ++
     "            ⟨origin.occurrence,⟨row.key.file,row.key.line,row.key.line⟩,origin.binding,#[]⟩\n" ++
     "          let originals := documents.flatMap fun doc => (Extraction.recordedRows pinned.head.identity doc).toOption.getD #[]\n" ++
     "          let shown := Extraction.presented body documents (aliases ++ originals)\n" ++
     "          let ranges := (Extraction.compactRanges shown.ranges).qsort fun a b => (toJson a).compress < (toJson b).compress\n" ++
     "          let bindings := shown.bindings.toList.eraseDups.toArray.qsort fun a b => (toJson a).compress < (toJson b).compress\n" ++
     "          IO.FS.writeFile (destination / \"original-presentation.json\") (Json.mkObj [\n" ++
     "            (\"ranges\",toJson ranges),(\"bindings\",toJson bindings)]).compress")
  IO.FS.writeFile target helper
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let base := root / "query-cache-baseline-core"
  let runtime := root / "query-cache-baseline-build"
  let build := fun core output objectModules baselineResponse baselineMain mainModule => Json.mkObj [
    ("project",toJson project.toString),("core",toJson core),("baselineCore",toJson base.toString),
    ("output",toJson output),("toolchain",toJson toolchain),("objectModules",toJson objectModules),
    ("baselineResponse",toJson baselineResponse),("baselineMain",toJson baselineMain),
    ("parents",toJson (#[] : Array String)),("force",toJson (#[] : Array String)),("mainModule",toJson mainModule)]
  let candidate := root / "workgraph-transfer-runtime-build"
  IO.FS.writeFile (root / "workgraph-transfer-runtime.settings.json")
    (build (root / "workgraph-transfer-core").toString candidate.toString
      (root / "query-cache-baseline-objects.json").toString (runtime / "runtime.rsp").toString
      (runtime / "Main.o").toString "Main").pretty
  for arm in ["baseline","candidate"] do
    let installed := if arm == "baseline" then runtime else candidate
    let mapping := if arm == "baseline" then root / "query-cache-baseline-objects.json" else candidate / "object-mapping.json"
    let core := if arm == "baseline" then base else root / "workgraph-transfer-core"
    IO.FS.writeFile (root / ("workgraph-transfer-" ++ arm ++ ".settings.json"))
      (build core.toString (root / ("workgraph-transfer-hook-" ++ arm ++ "-build")).toString
        mapping.toString (installed / "runtime.rsp").toString (installed / "Main.o").toString
        "tools.research.WorkGraphTransferHook").pretty
  let guard := Json.mkObj [("cwd",toJson project.toString),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString])]
  for (kind,command) in [("core",#[toolchain ++ "/bin/lean","-M3072","--run",coreMaker.toString])] ++
      (["runtime","baseline","candidate"].map fun name => (name,#["/usr/bin/env","LEAN_NUM_THREADS=1",
        toolchain ++ "/bin/lean","-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,
        (root / ("workgraph-transfer-" ++ name ++ ".settings.json")).toString])) ++
      [("run",#[toolchain ++ "/bin/lean","-M3072","--run",(project / "tools/research/RunWorkGraphTransferStudy.lean").toString])] do
    IO.FS.writeFile (root / ("workgraph-transfer-" ++ kind ++ ".guard.settings.json"))
      ((guard.setObjVal! "command" (toJson command)).setObjVal! "record" (toJson (records / (kind ++ ".guard.json")).toString)).pretty
  IO.println "Prepared unchanged WorkGraph transfer candidate and model-free matched three-topic study"
