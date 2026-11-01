import Lean
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("frame/profile anchor changed: " ++ toString (before.take 90))
  return source.replace before after
private def save (path : System.FilePath) (source : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path source

def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "runtime/hooks/audit required")
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/selection-witness/frames"
  let core := root / "selection-frames-core"
  let runtime := root / "selection-frames-runtime-build"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  IO.FS.createDirAll records
  if mode == "runtime" then
    check (!(← core.pathExists)) "preserve prior framed observer"
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "selection-witness-core").toString,core.toString]}
    check (copied.exitCode == 0) "cannot isolate frame/profile observer"
    save (core / "tools/research/SelectionReceipt.lean") (← IO.FS.readFile (project / "tools/research/SelectionReceipt.lean"))
    let handoff := core / "Eggshell/Handoff.lean"
    let mut source ← IO.FS.readFile handoff
    source ← once source "public import Eggshell.Receipt\n" "public import Eggshell.Receipt\npublic import tools.research.SelectionReceipt\n"
    source ← once source "Receipt.observe source.receipt \"selection-plan\"" "Receipt.observeSelection source.receipt captureInput"
    save handoff source
    let service := core / "Eggshell/PublicationService.lean"
    source ← IO.FS.readFile service
    source ← once source "def sourcePlan (server" ("def profile (stage : String) (fields : List (String × Json)) : IO Unit := do\n" ++
      "  if (← IO.getEnv \"EGGSHELL_TRACE_SERVICE_PROFILE\") == some \"1\" then\n" ++
      "    Receipt.observe (some (← Receipt.fresh)) stage (Json.mkObj fields)\n\n" ++ "def sourcePlan (server")
    source ← once source "def sourcePlan (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do\n"
      "def sourcePlan (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do\n  let started ← IO.monoMsNow\n"
    source ← once source "    throw (IO.userError \"invalid prepared selector domain\")\n"
      "    throw (IO.userError \"invalid prepared selector domain\")\n  let validated ← IO.monoMsNow\n"
    source ← once source "    let mut units := #[]\n" "    let acquired ← IO.monoMsNow\n    let mut units := #[]\n"
    source ← once source "    let originals ← IO.ofExcept (PreparedSourceView.join rows headers)\n"
      "    let _ ← (← IO.mkRef (units,pieces,rows,headers)).get\n    let constructed ← IO.monoMsNow\n    let originals ← IO.ofExcept (PreparedSourceView.join rows headers)\n"
    source ← once source "    let some choice := SharedRangeAdapter.selectView query units pieces source |\n"
      "    let source ← (← IO.mkRef source).get\n    let domainReady ← IO.monoMsNow\n    let some choice := SharedRangeAdapter.selectView query units pieces source |\n"
    source ← once source "      throw (IO.userError \"prepared original selector did not produce a valid selection\")\n"
      ("      throw (IO.userError \"prepared original selector did not produce a valid selection\")\n" ++
       "    let choice ← (← IO.mkRef choice).get\n    let selected ← IO.monoMsNow\n" ++
       "    profile \"source-plan-profile\" [(\"validationMs\",toJson (validated-started)),\n" ++
       "      (\"viewMs\",toJson (acquired-validated)),(\"unitsMs\",toJson (constructed-acquired)),\n" ++
       "      (\"domainMs\",toJson (domainReady-constructed)),(\"selectionMs\",toJson (selected-domainReady)),\n" ++
       "      (\"owners\",toJson query.owners.size),(\"units\",toJson units.size),(\"pieces\",toJson pieces.length),\n" ++
       "      (\"incomingRows\",toJson rows.size),(\"sourceRows\",toJson source.rows.size),\n" ++
       "      (\"captureInput\",toJson query.captureInput)]\n")
    source ← once source "def sourceBindings (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do\n"
      "def sourceBindings (server : Server) (secret : String) (payload : Json) (deadline : Nat) : IO Json := do\n  let started ← IO.monoMsNow\n"
    source ← once source "    let result ← BindingPageScan.resolve original wanted (Std.HashSet.ofArray allowed) deadline\n"
      ("    let acquired ← IO.monoMsNow\n" ++
       "    let report ← BindingPageScan.resolveReport original wanted (Std.HashSet.ofArray allowed) deadline\n" ++
       "    let result := report.resolved\n    let scanned ← IO.monoMsNow\n" ++
       "    profile \"source-bindings-profile\" [(\"prepareMs\",toJson (acquired-started)),\n" ++
       "      (\"scanMs\",toJson (scanned-acquired)),(\"targets\",toJson wanted.size),\n" ++
       "      (\"pages\",toJson report.pages),(\"leaves\",toJson report.leaves),\n" ++
       "      (\"bytes\",toJson result.bytes),(\"complete\",toJson result.complete)]\n")
    save service source
    let wire := core / "Eggshell/PublicationWire.lean"
    let changed ← once (← IO.FS.readFile wire) "  (include_str \"Handoff.lean\").toUTF8,\n"
      "  (include_str \"Handoff.lean\").toUTF8,\n  (include_str \"../tools/research/SelectionReceipt.lean\").toUTF8,\n"
    save wire changed
    IO.FS.writeFile (records / "plan.json") (Json.mkObj [
      ("purpose",toJson "Separate service admission, unit construction, domain construction, selection and binding scan; explain the unchanged actual choice using bounded multipart receipts."),
      ("parentRuntimeSha256",toJson "a20a4154d826360e956b60732ef4d77908befce32548ef7a1ac9d84a34af2784"),
      ("priorObserver",toJson "The earlier topic-1 hook completed with the identical body, but no completed selection receipt was saved. Preserve that result; do not reinterpret it as failed delivery."),
      ("schedule",toJson "Reuse the prepared R40 snapshot and private history families, recheck warm. One normal topic-1 hook with small service timings, then instrumented topics 1,2,3, stopping on any body mismatch, incomplete hook or absent multipart manifest."),
      ("limits",toJson "Native frame 8MiB unchanged; multipart assembly 32MiB. Actual hook remains 30 seconds. RSS guard 3.5GiB, disk minimum 2GiB."),
      ("notMeasured",toJson "No model calls, new seed, token improvement, p99 or 80-user validation."),("adopted",toJson false)]).pretty
  else if mode == "hooks" then
    let target := core / "tools/research/SelectionFramesHook.lean"
    check (!(← target.pathExists)) "preserve framed hook"
    let mut source := (← IO.FS.readFile (root / "selection-witness-core/tools/research/SelectionWitnessHook.lean")).replace "selection-witness" "selection-frames"
    source ← once source "docs/candidates/selection-frames/hooks" "docs/candidates/selection-witness/frames/hooks"
    source ← once source "(\"EGGSHELL_TRACE_SELECTION_RANGES\",none)" "(\"EGGSHELL_TRACE_SERVICE_PROFILE\",some \"1\"),(\"EGGSHELL_TRACE_SELECTION_RANGES\",none)"
    source ← once source "        let response ← StudyCommand.run binary.toString" "        let serviceStarted ← IO.monoMsNow\n        let response ← StudyCommand.run binary.toString"
    source ← once source "          let frozenEntries ← IO.ofExcept"
      ("          let mut profiles := #[]\n" ++
       "          for receipt in ← (root / \"data/receipts\").readDir do\n" ++
       "            for stage in [\"source-plan-profile\",\"source-bindings-profile\"] do\n" ++
       "              let path := receipt.path / (stage ++ \".json\")\n" ++
       "              if ← path.pathExists then\n" ++
       "                let row ← read path\n" ++
       "                if ((row.getObjValAs? Nat \"observedMs\").toOption.getD 0) ≥ serviceStarted then profiles := profiles.push row\n" ++
       "          IO.FS.writeFile (destination / \"service-profile.json\") (toJson profiles).pretty\n" ++
       "          let frozenEntries ← IO.ofExcept")
    let [before,tail] := source.splitOn "    let source ← DB.PageMap.pin database\n" | throw (IO.userError "prepared source anchor changed")
    let [_,after] := tail.splitOn "    install arm\n" | throw (IO.userError "prepared installation anchor changed")
    source := before ++ "    let copied ← IO.Process.output {cmd := \"/bin/cp\",args := #[\"-cR\",\n" ++
      "      (study / \"shared-snapshot/selection-witness-trial/candidate/work.egg/derived\").toString,\n" ++
      "      (database / \"derived\").toString]}\n    check (copied.exitCode == 0) \"cannot reuse immutable prepared source\"\n" ++
      "    install arm\n" ++ after
    save target source
  else if mode == "audit" then
    for name in ["SourceDecisionAudit","SelectionReceiptTests"] do
      save (core / s!"tools/research/{name}.lean") (← IO.FS.readFile (project / s!"tools/research/{name}.lean"))
  else throw (IO.userError "unknown frames mode")
  let baseline := if mode == "runtime" then root / "selection-witness-runtime-build"
    else if mode == "audit" then root / "selection-frames-hook-candidate-build" else runtime
  let output := if mode == "runtime" then runtime else if mode == "hooks" then root / "selection-frames-hook-candidate-build"
    else root / "selection-frames-audit-build"
  let settings := root / s!"selection-frames-{mode}.settings.json"
  IO.FS.writeFile settings (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("output",toJson output.toString),
    ("toolchain",toJson toolchain),("objectModules",toJson (baseline / "object-mapping.json").toString),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),
    ("baselineMain",toJson (baseline / (if mode == "audit" then "tools_research_SelectionFramesHook.o" else "Main.o")).toString),
    ("parents",toJson #[baseline.toString]),("force",toJson (#[] : Array String)),
    ("mainModule",toJson (if mode == "runtime" then "Main" else if mode == "audit" then "tools.research.SourceDecisionAudit" else "tools.research.SelectionFramesHook"))]).compress
  let mut jobs := [(mode ++ "-build",#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
    (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]
  if mode == "hooks" then
    jobs := jobs ++ [("describe",#[ (output / "StudyMain").toString,"describe","candidate"]),
      ("prepare",#[(output / "StudyMain").toString,"prepare","candidate"]),
      ("normal-1",#[(output / "StudyMain").toString,"run","candidate","0","1"])]
    for topic in [1,2,3] do jobs := jobs ++ [(s!"topic-{topic}",#[(output / "StudyMain").toString,"audit","candidate","0",toString topic])]
  if mode == "audit" then
    jobs := jobs ++ [("selftest",#["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (root / "selection-frames-selftest").toString,(output / "StudyMain").toString,"selftest"])]
    for topic in [1,2,3] do jobs := jobs ++ [(s!"analyze-{topic}",#[(output / "StudyMain").toString,records.toString,(root / "selection-frames-trial/candidate").toString,toString topic])]
  for (label,command) in jobs do
    IO.FS.writeFile (root / s!"selection-frames-{label}.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (label ++ ".guard.json")).toString),("command",toJson command)]).compress
