import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) "complete Work source anchor changed"
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/complete-work"
  let base := root / "query-cache-baseline-core"
  let core := root / "complete-work-core"
  check (!(← core.pathExists)) "preserve previous complete Work core"
  IO.FS.createDirAll records
  let moduleFile := "tools/research/CompleteOriginal.lean"
  let mut view ← IO.FS.readFile (base / "Eggshell/ObservedRecordView.lean")
  view ← once view "public import Eggshell.OriginalStructure\n"
    "public import Eggshell.OriginalStructure\npublic import tools.research.CompleteOriginal\n"
  view ← once view "  recipes : Nat\n" "  recipes : Nat\n  wholeParts : Array Span\n"
  view ← once view "  let characters := raw.toList.toArray\n"
    "  let characters := raw.toList.toArray\n  let whole ← Eggshell.Research.CompleteOriginal.prepare raw\n"
  view ← once view "document.occurrences,characters.size,blocks.size,spans.size⟩,spans,blocks⟩"
    "document.occurrences,characters.size,blocks.size,spans.size,whole.spans⟩,spans,blocks⟩"
  check ((view.splitOn "  let header ← ObservedRecords.decode (α := Header) bytes\n").length > 1)
    "missing original view header readers"
  view := view.replace "  let header ← ObservedRecords.decode (α := Header) bytes\n"
    ("  let header ← ObservedRecords.decode (α := Header) bytes\n" ++
     "  unless (Eggshell.Research.CompleteOriginal.check? header.characters header.wholeParts).isSome do\n" ++
     "    throw (IO.userError \"complete original layout is outside its publication\")\n")
  let mut index ← IO.FS.readFile (base / "Eggshell/SynapseIndex.lean")
  index ← once index "    (include_str \"ObservedRecordView.lean\").toUTF8,"
    "    (include_str \"ObservedRecordView.lean\").toUTF8,\n    (include_str \"../tools/research/CompleteOriginal.lean\").toUTF8,"
  let mut handoff ← IO.FS.readFile (base / "Eggshell/Handoff.lean")
  handoff ← once handoff "  original : Option (Array OriginalStructure.Span) := none\n"
    "  original : Option (Array OriginalStructure.Span) := none\n  completeOriginal : Option (Array OriginalStructure.Span) := none\n"
  handoff ← once handoff "/-- One execution owns both the decision and its explanation."
    ((← IO.FS.readFile (project / "tools/research/CompleteWorkAdapter.lean.inc")) ++
      "/-- One execution owns both the decision and its explanation.")
  handoff ← once handoff "            original := (originalStructures[originalKey]?).map (·.spans)}"
    "            original := (originalStructures[originalKey]?).map (·.spans)\n            completeOriginal := (originalStructures[originalKey]?).map (·.header.wholeParts)}"
  handoff ← once handoff "    let selectionPlan := if meaningSelected && !enforce then\n"
    ("    let wholeWork : Option (SharedRangeAdapter.Fitted (budget,byteBudget.getD (budget*4)) packetCost mandatory) := if meaningSelected && !enforce then\n" ++
     "      SharedRangeAdapter.completeWorkFit (budget,byteBudget.getD (budget*4)) packetCost families mandatory else none\n" ++
     "    let selectionPlan : Option (SharedRangeAdapter.Plan (budget,byteBudget.getD (budget*4)) packetCost mandatory) := if wholeWork.isNone && meaningSelected && !enforce then\n")
  handoff ← once handoff "    let fittedSlices := if meaningSelected && !enforce then\n"
    "    let fittedSlices : List TransportSlice := if let some complete := wholeWork then complete.val else if meaningSelected && !enforce then\n"
  handoff ← once handoff "        selectionPlan := if captureSelection then selectionPlan.map\n"
    ("        selectionPlan := if captureSelection && wholeWork.isSome then some (Json.mkObj [\n" ++
     "          (\"strategy\",toJson \"complete-observed-work\"),(\"families\",toJson families.length),\n" ++
     "          (\"limit\",toJson (budget,byteBudget.getD (budget*4))),\n" ++
     "          (\"nativeControlUnchanged\",toJson true)]) else if captureSelection then selectionPlan.map\n")
  let config ← once (← IO.FS.readFile (base / "Eggshell/Config.lean"))
    "def nativeHandoffBytes : Nat := 128000" "def nativeHandoffBytes : Nat := 1024*1024"
  let wire ← once (← IO.FS.readFile (base / "Eggshell/PublicationWire.lean"))
    "  (include_str \"PublicationWire.lean\").toUTF8,"
    "  (include_str \"Handoff.lean\").toUTF8,(include_str \"Config.lean\").toUTF8,\n  (include_str \"PublicationWire.lean\").toUTF8,"
  let target := project / "tools/research/CompleteWorkHook.lean"
  check (!(← target.pathExists)) "preserve previous complete Work producer"
  let mut helper := (← IO.FS.readFile (project / "tools/research/WorkGraphTransferHook.lean"))
    |>.replace "workgraph-transfer" "complete-work"
  helper ← once helper "import Eggshell.Install\n"
    "import Eggshell.Install\nimport tools.research.CompleteOriginalFixtures\n"
  helper ← once helper "  if mode == \"describe\" then\n"
    "  if mode == \"describe\" then\n    Eggshell.Research.CompleteOriginalFixtures.verify\n"
  helper ← once helper "private def config (binary database : System.FilePath) (write : Bool) : String :="
    "private def config (binary database : System.FilePath) (write : Bool) (handoffChars : Nat) : String :="
  helper ← once helper " ++ \"handoff_chars = 120000\\n\"" " ++ \"handoff_chars = \" ++ toString handoffChars ++ \"\\n\""
  helper ← once helper "(config binary (armPath arm / \"work.egg\") true)"
    "(config binary (armPath arm / \"work.egg\") true (if arm == \"candidate\" then 1024*1024 else 120000))"
  helper ← once helper "(config binary (armPath arm / \"work.egg\") false)"
    "(config binary (armPath arm / \"work.egg\") false (if arm == \"candidate\" then 1024*1024 else 120000))"
  helper ← once helper "  let session := \"complete-work-\" ++ arm ++ \"-\" ++ repetition ++ \"-\" ++ toString topic\n"
    ("  let session := \"complete-work-\" ++ arm ++ \"-\" ++ repetition ++ \"-\" ++ toString topic\n" ++
     "  let receiptRoot := root / \"data/receipts\"\n" ++
     "  let previousReceipts : Array String ← if ← receiptRoot.pathExists then do\n" ++
     "    pure ((← receiptRoot.readDir).map (·.fileName))\n  else pure #[]\n")
  helper ← once helper "          IO.FS.writeFile (destination / \"result.json\")"
    ("          let mut completeReceipts := #[]\n" ++
     "          for entry in ← receiptRoot.readDir do\n" ++
     "            if previousReceipts.contains entry.fileName then continue\n" ++
     "            let plan := entry.path / \"selection-plan.json\"\n" ++
     "            if ← plan.pathExists then\n" ++
     "              let record ← read plan\n" ++
     "              if (record.getObjValD \"data\").getObjValD \"strategy\" == toJson \"complete-observed-work\" then\n" ++
     "                completeReceipts := completeReceipts.push record\n" ++
     "          IO.FS.writeFile (destination / \"complete-plan-receipts.json\") (toJson completeReceipts).pretty\n" ++
     "          IO.FS.writeFile (destination / \"result.json\")")
  helper ← once helper "(\"availableDelivery\",audit.getObjValD \"availableDelivery\"),"
    "(\"availableDelivery\",audit.getObjValD \"availableDelivery\"),(\"completePlanReceipts\",toJson completeReceipts.size),"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",base.toString,core.toString]}
  check (copied.exitCode == 0) "cannot isolate complete Work candidate"
  IO.FS.createDirAll (core / moduleFile).parent.get!
  IO.FS.writeFile (core / moduleFile) (← IO.FS.readFile (project / moduleFile))
  for (name,text) in [("ObservedRecordView",view),("SynapseIndex",index),("Handoff",handoff),
      ("Config",config),("PublicationWire",wire)] do
    IO.FS.writeFile (core / "Eggshell" / (name ++ ".lean")) text
  IO.FS.writeFile target helper
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  let runtime := root / "query-cache-baseline-build"
  let candidate := root / "complete-work-runtime-build"
  let build := fun core output mapping response entry main => Json.mkObj [
    ("project",toJson project.toString),("core",toJson core),("baselineCore",toJson base.toString),
    ("output",toJson output),("toolchain",toJson toolchain),("objectModules",toJson mapping),
    ("baselineResponse",toJson response),("baselineMain",toJson entry),
    ("parents",toJson (#[] : Array String)),("force",toJson (#[] : Array String)),("mainModule",toJson main)]
  IO.FS.writeFile (root / "complete-work-runtime.settings.json") (build core.toString candidate.toString
    (root / "query-cache-baseline-objects.json").toString (runtime / "runtime.rsp").toString
    (runtime / "Main.o").toString "Main").pretty
  IO.FS.writeFile (root / "complete-work-candidate.settings.json") (build core.toString
    (root / "complete-work-hook-candidate-build").toString (candidate / "object-mapping.json").toString
    (candidate / "runtime.rsp").toString (candidate / "Main.o").toString "tools.research.CompleteWorkHook").pretty
  let guard := Json.mkObj [("cwd",toJson project.toString),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson (2097152 : Nat)),("ownedPrefixes",toJson #[root.toString])]
  for name in ["runtime","candidate"] do
    IO.FS.writeFile (root / ("complete-work-" ++ name ++ ".guard.settings.json"))
      ((guard.setObjVal! "command" (toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean",
        "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,
        (root / ("complete-work-" ++ name ++ ".settings.json")).toString])).setObjVal! "record"
        (toJson (records / (name ++ ".guard.json")).toString)).pretty
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [("capacityBytes",toJson (1024*1024 : Nat)),
    ("capacityChars",toJson (1024*1024 : Nat)),("topics",toJson #[1,2,3]),
    ("candidateFreshSessions",toJson (1 : Nat)),("sameFrozenR40",toJson true),
    ("changesCapacityAndSelectionTogether",toJson true),("stopOnFirstMissingEvidenceOrDeadline",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Prepared bounded complete Work candidate; layout prepared at publication, no query-time inference"
