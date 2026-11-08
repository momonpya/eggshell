import tools.research.StudyLocal
open Lean StudyLocal
namespace DeliveryKnowledgeStudy
def family := "delivery-knowledge"
def folder := project/"docs/candidates"/family
def parent := base/"positive-projection-runtime-build"
def source := base/(family++"-runtime-source")
def target := base/(family++"-runtime-build")
def auditor := family++"-auditor3"
def controls := family++"-controls3"
def controlsRoot := base/(controls++"-result")
def core := #["Eggshell/DeliveryLedger.lean","Eggshell/Handoff.lean","Eggshell/PluginHooks.lean",
  "Eggshell/SynapseJournal.lean","tools/research/PositiveProjection.lean"]
def prepare : IO Unit := do
  idle
  check ((← read (project/"docs/candidates/positive-projection/runtime.json")).getObjValD "sha256" == toJson (← hash (parent/"StudyMain")))
    "actual normal parent changed"
  materialize parent source target "tools.research.ReplayReadinessChecks" (family++"-runtime-settings.json")
  IO.FS.createDirAll folder
  let patch := folder/"core.patch"
  if ← patch.pathExists then
    discard <| command "/usr/bin/git" #["apply","--unidiff-zero",patch.toString] source
  else
    IO.FS.writeFile (source/"tools/research/PositiveProjection.lean")
      (← IO.FS.readFile (project/"tools/research/PositiveProjection.lean"))
  write (folder/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"StudyMain"))),
    ("change",toJson "separate verified positive ACK evidence from complete presentation knowledge; unknown presentation blocks omission labels while confirmed citations remain usable"),
    ("bodyAndAuthorityUnchanged",toJson true),("newLocksQueuesOrCaches",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def sealSource : IO Unit := do
  idle
  let mut patch := ""
  let mut hashes := #[]
  for relative in core do
    let before := base/"positive-projection-runtime-source"/relative
    let after := source/relative
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/"++relative,"-L","b/"++relative,before.toString,after.toString]}
    check (result.exitCode == 1) ("expected source change missing: "++relative)
    patch := patch++result.stdout
    hashes := hashes.push (relative,← hash after)
  check ((← IO.FS.readFile (source/"tools/research/PositiveProjection.lean")) ==
    (← IO.FS.readFile (project/"tools/research/PositiveProjection.lean"))) "isolated positive projection differs from repository"
  IO.FS.writeFile (folder/"core.patch") patch
  write (folder/"source.json") (Json.mkObj [("hashes",toJson hashes),("patchSha256",toJson (← hash (folder/"core.patch"))),
    ("actualSourceOnly",toJson true),("adopted",toJson false)])

def setup (mode : String) : IO Unit := do
  idle
  let args ← match mode with
    | "runtime-build" | "auditor-build" | "ledger-audit-build" => do
      let manifest ← read (folder/"source.json")
      check (manifest.getObjValD "patchSha256" == toJson (← hash (folder/"core.patch"))) "candidate patch changed after sealing"
      for (relative,sha) in ← IO.ofExcept (manifest.getObjValAs? (Array (String × String)) "hashes") do
        check ((← hash (source/relative)) == sha) "isolated source changed after sealing"
      pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (project/"tools/research/StudyBuildMain.lean").toString,
        (base/((if mode == "auditor-build" then auditor
          else family++"-"++mode.replace "-build" "")++"-settings.json")).toString]
    | "controls" => do
      let binary := base/(auditor++"-build/StudyMain")
      check ((← read (folder/"auditor.json")).getObjValD "sha256" == toJson (← hash binary)) "checked auditor required"
      let root := controlsRoot
      check (!(← root.pathExists)) "fresh native controls required"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=2","EGGSHELL_DATA_ROOT="++(root/"data").toString,
        binary.toString,"delivery-knowledge-controls",root.toString]
    | "ledgers" => do
      check ((← read (folder/"delivery-cells.json")).getObjValD "actualDeliveryAllSixPassed" == toJson true)
        "all six actual hooks required before inspecting accepted heads"
      let binary := base/(family++"-ledger-audit-build/StudyMain")
      check ((← read (folder/"ledger-auditor-runtime.json")).getObjValD "sha256" == toJson (← hash binary))
        "checked native accepted-head reader required"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",
        "EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,binary.toString,
        (base/(family++"-cells-result")).toString,(base/"real-source-search-read-trial-result/data").toString,
        (base/"real-source-search-read-trial-result/work.egg").toString,(folder/"confirmed-ledgers.json").toString]
    | "install" | "cells" => do
      if mode == "cells" then
        check ((← read (folder/"controls.json")).getObjValD "allPassed" == toJson true) "all native eligibility controls required before actual hooks"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/(auditor++"-build/StudyMain")).toString,
        (if mode == "install" then "install-prefix" else "cells"),(base/(family++"-"++mode++".json")).toString]
    | _ => throw (IO.userError "fixed build stage required")
  let tag := if mode == "auditor-build" then auditor++"-build1"
    else if mode == "controls" then controls else family++"-"++mode++"1"
  guard tag args

def auditRuntime : IO Unit := do
  idle
  let record ← finished (family++"-runtime-build1")
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  let literal := source/"tools/research/PositiveProjection.lean"
  if ← (folder/"runtime-closure.json").pathExists then
    let prior ← read (folder/"literal-declaration-missing.json")
    check (prior.getObjValD "candidateRuntimeSha256" == toJson (← hash (target/"StudyMain")) &&
      (← read (folder/"runtime-closure.json")).getObjValD "consistent" == toJson true)
      "the earlier passed closure belongs to a different binary"
  else
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"inspect",target.toString,
      (folder/"runtime-closure.json").toString]
  for args in [#["compare-sources",parent.toString,target.toString,(folder/"runtime-sources.json").toString,
      "Eggshell.DeliveryLedger","Eggshell.Handoff","Eggshell.PluginHooks","Eggshell.SynapseJournal","tools.research.PositiveProjection",
      "@"++(← hash literal)++":"++literal.toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  check ((← read (folder/"runtime-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected product sources changed"
  write (folder/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (target/"StudyMain"))),
    ("guard",record),("adopted",toJson false),
    ("passedNativeClosureReusedWithIdenticalBinary",toJson (← (folder/"literal-declaration-missing.json").pathExists))])

def prepareAuditor : IO Unit := do
  idle
  check ((← read (folder/"runtime.json")).getObjValD "sha256" == toJson (← hash (target/"StudyMain"))) "checked product required"
  let failed ← read (base/(family++"-controls1.guard.json"))
  check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    failed.getObjValD "exitCode" == toJson (1 : Nat)) "retain the failed fixture result before rebuilding controls"
  write (folder/"fixture-session-rejected.json") (Json.mkObj [("guard",failed),
    ("error",toJson (← IO.FS.readFile (base/(family++"-controls1.stderr")))),
    ("auditorSha256",toJson (← hash (base/(family++"-auditor-build/StudyMain")))),
    ("cause",toJson "fixture attached an ACK from partial-ack to a later occurrence in another session; Payload.valid correctly rejected it"),
    ("productChanged",toJson false)])
  let citationFailure ← read (base/(family++"-controls2.guard.json"))
  check (citationFailure.getObjValD "state" == toJson "finished" &&
    citationFailure.getObjValD "ownedPids" == toJson (#[] : Array Nat) && citationFailure.getObjValD "exitCode" == toJson (1 : Nat))
    "retain the rejected citation fixture"
  write (folder/"fixture-citation-rejected.json") (Json.mkObj [("guard",citationFailure),
    ("error",toJson (← IO.FS.readFile (base/(family++"-controls2.stderr")))),
    ("auditorSha256",toJson (← hash (base/(family++"-auditor2-build/StudyMain")))),
    ("cause",toJson "fixture used a plain path:line instead of the existing citation extractor's Markdown link syntax"),
    ("productChanged",toJson false)])
  let destination := base/(auditor++"-source")
  let checkedParent := base/(family++"-auditor2-build")
  materialize checkedParent destination (base/(auditor++"-build"))
    "tools.research.ScorePrepareControls" (auditor++"-settings.json")
  copyLocalArtifacts checkedParent (base/(auditor++"-build"))
  for relative in core do IO.FS.writeFile (destination/relative) (← IO.FS.readFile (source/relative))
  for name in ["PositiveProjectionChecks","SessionAcknowledgmentChecks","DeliveryKnowledgeChecks"] do
    IO.FS.writeFile (destination/"tools/research"/(name++".lean")) (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let entry ← IO.FS.readFile (destination/"tools/research/ScorePrepareControls.lean")
  check ((entry.splitOn "import tools.research.DeliveryKnowledgeChecks\n").length == 2 &&
    (entry.splitOn "  | [\"delivery-knowledge-controls\",root] =>").length == 2) "actual auditor entry changed"

def auditAuditor : IO Unit := do
  idle
  let record ← finished (auditor++"-build1")
  let build := base/(auditor++"-build")
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"auditor3-closure.json").toString],
    #["common-sources",target.toString,build.toString,(folder/"auditor3-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let gate ← read (folder/"auditor3-sources.json")
  check (gate.getObjValD "allProductCorePresent" == toJson true && gate.getObjValD "commonSourcesUnchanged" == toJson true)
    "auditor differs from the product core"
  for name in ["PositiveProjectionChecks","SessionAcknowledgmentChecks","DeliveryKnowledgeChecks"] do
    let native : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/("tools_research_"++name++".source"))))
    check (native.1 == (← IO.FS.readFile (project/"tools/research"/(name++".lean")))) "actual control source differs"
  write (folder/"auditor.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
    ("guard",record),("actualControlSourcesMatch",toJson true),("adopted",toJson false)])

def collectControls : IO Unit := do
  idle
  let record ← finished controls
  let root := controlsRoot
  let knowledge ← read (root/"report.json")
  let projection ← read (root/"projection/report.json")
  let acks ← read (root/"acknowledgments.json")
  check (knowledge.getObjValD "allPassed" == toJson true && projection.getObjValD "allPassed" == toJson true &&
    (← IO.ofExcept (acks.getObjValAs? (Array Json) "checks")).size == 9) "all three native control groups required"
  write (folder/"controls.json") (Json.mkObj [("knowledge",knowledge),("projection",projection),
    ("acknowledgments",acks),("guard",record),("allPassed",toJson true),("adopted",toJson false)])

def prepareDelivery : IO Unit := do
  idle
  check ((← read (folder/"controls.json")).getObjValD "allPassed" == toJson true) "native controls required"
  let installation := base/(family++"-prefix")
  let digest ← hash (target/"StudyMain")
  write (base/(family++"-install.json")) (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (target/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let previous ← read (base/"positive-projection-cells.json")
  let output := base/(family++"-cells-result")
  check (!(← output.pathExists)) "preserve previous actual hook results"
  let probes ← IO.ofExcept (previous.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let some name := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName |
      throw (IO.userError "probe destination has no name")
    return probe.setObjVal! "destination" (toJson (output/name).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/(family++"-cells.json")) (previous.setObjVal! "output" (toJson output.toString)|>.setObjVal! "probes" (toJson probes))

def sealInstalled : IO Unit := do
  idle
  discard <| finished (family++"-install1")
  let binary := base/(family++"-prefix/libexec/eggshell")
  check ((← hash binary) == (← hash (target/"StudyMain"))) "installed runtime changed"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary installed link exists"
  discard <| command "/bin/ln" #[(target/"StudyMain").toString,temporary.toString]
  IO.FS.rename temporary binary

def prepareLedgerAuditor : IO Unit := do
  check ((← read (folder/"runtime.json")).getObjValD "sha256" == toJson (← hash (target/"StudyMain")))
    "checked immutable native product required"
  let destination := base/(family++"-ledger-audit-source")
  materialize target destination (base/(family++"-ledger-audit-build"))
    "tools.research.ConfirmedLedgerAudit" (family++"-ledger-audit-settings.json")
  IO.FS.writeFile (destination/"tools/research/ConfirmedLedgerAudit.lean")
    (← IO.FS.readFile (project/"tools/research/ConfirmedLedgerAudit.lean"))

def auditLedgerAuditor : IO Unit := do
  idle
  let record ← finished (family++"-ledger-audit-build1")
  let build := base/(family++"-ledger-audit-build")
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"ledger-auditor-closure.json").toString],
    #["component-sources",target.toString,build.toString,(folder/"ledger-auditor-sources.json").toString,
      "Eggshell.DeliveryLedger","Eggshell.DB.PageMap","Eggshell.FileSystem","Eggshell.Blake3"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let gate ← read (folder/"ledger-auditor-sources.json")
  check (gate.getObjValD "commonSourcesUnchanged" == toJson true && gate.getObjValD "requiredModulesPresent" == toJson true)
    "native ledger reader changed its core"
  let native : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/"tools_research_ConfirmedLedgerAudit.source")))
  check (native.1 == (← IO.FS.readFile (project/"tools/research/ConfirmedLedgerAudit.lean"))) "native reader source differs"
  write (folder/"ledger-auditor-runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
    ("guard",record),("actualSourceMatches",toJson true),("adopted",toJson false)])

def collectLedgers : IO Unit := do
  idle
  let record ← finished (family++"-ledgers1")
  let report ← read (folder/"confirmed-ledgers.json")
  check (report.getObjValD "allSixConfirmed" == toJson true &&
    report.getObjValD "allSixUnknownCoverageMarked" == toJson true && report.getObjValD "projectHeadUnchanged" == toJson true)
    "actual partial ACKs lost confirmed ranges or unknown coverage"
  write (folder/"confirmed-ledger-run.json") (Json.mkObj [("guard",record),
    ("reportSha256",toJson (← hash (folder/"confirmed-ledgers.json"))),
    ("readOnlyExactAcceptedHeads",toJson true),("adopted",toJson false)])

def cleanup : IO Unit := do
  idle
  check ((← read (folder/"confirmed-ledger-run.json")).getObjValD "reportSha256" == toJson (← hash (folder/"confirmed-ledgers.json")))
    "retain the completed exact-head inspection first"
  let data := base/"real-source-search-read-trial-result/data"
  let records ← IO.ofExcept ((← read (folder/"confirmed-ledgers.json")).getObjValAs? (Array Json) "cells")
  check (records.size == 6) "all six owned ledger contexts required"
  let mut paths := #[]
  for record in records do
    let session ← IO.ofExcept (record.getObjValAs? String "session")
    let context ← IO.ofExcept (record.getObjValAs? String "ledgerContext")
    check (session.startsWith "real-source-" && session.length == 76 && context.length == 64 &&
      context.toList.all (fun char => char.isDigit || ('a' ≤ char && char ≤ 'f'))) "ledger escaped generated session"
    paths := paths.push (data/"confirmed-delivery"/context)
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/LocalBatchStudy.lean").toString,"cleanup-cells-for",family]
  let helperRoots := #[base/(family++"-ledger-audit-build"),base/(family++"-ledger-audit-source")]
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if !helperRoots.contains entry.path && (← response.pathExists) then
      let body ← IO.FS.readFile response
      for root in helperRoots do check (!body.contains (root.toString++"/")) "another runtime needs the ended reader"
  paths := paths++helperRoots++#[base/(family++"-controls-result"),base/(family++"-controls2-result"),controlsRoot,
    folder/"delivery-stderr.txt",base/"citation-fixture-check.lean"]
  for extension in ["olean","olean.server","olean.private","ir","ir.sig"] do
    paths := paths.push (base/("StudyLocal."++extension))
  let mut guards := #[]
  for tag in [family++"-runtime-build1",family++"-auditor-build1",family++"-auditor2-build1",auditor++"-build1",controls,
      family++"-install1",family++"-cells1",family++"-ledger-audit-build1",family++"-ledgers1"] do
    guards := guards.push (tag,← finished tag)
    for extension in ["stdout","stderr"] do paths := paths.push (base/(tag++"."++extension))
  for tag in [family++"-controls1",family++"-controls2"] do
    for extension in ["stdout","stderr"] do paths := paths.push (base/(tag++"."++extension))
  let mut retained := #[]
  for path in #[target/"StudyMain",base/(auditor++"-build/StudyMain"),parent/"StudyMain"] do
    retained := retained.push (path,← hash path)
  for database in [base/"native-study/study/seed-1/work.egg",base/"real-source-search-read-trial-result/source.egg",
      base/"real-source-search-read-trial-result/work.egg"] do
    for entry in ← database.readDir do
      if entry.fileName == "head" || entry.path.extension == some "pages" then
        retained := retained.push (entry.path,← hash entry.path)
  let report := Json.mkObj [("guards",toJson guards),("paths",toJson (paths.map (·.toString))),
    ("retained",toJson (retained.map fun (path,sha) => (path.toString,sha))),
    ("currentProjectCacheModelsAndComparisonBodiesRetained",toJson true),("archived",toJson false)]
  write (folder/"cleanup.json") (report.setObjVal! "completed" (toJson false))
  for path in paths do
    check (path.toString.startsWith (base.toString++"/") || path == folder/"delivery-stderr.txt")
      "cleanup escaped candidate artifacts"
    if ← path.pathExists then discard <| command "/bin/rm" #["-rf","--",path.toString]
  for (path,sha) in retained do check ((← hash path) == sha) "current product or original changed during cleanup"
  write (folder/"cleanup.json") (report.setObjVal! "completed" (toJson true))
end DeliveryKnowledgeStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => DeliveryKnowledgeStudy.prepare
  | ["seal-source"] => DeliveryKnowledgeStudy.sealSource
  | ["setup",mode] => DeliveryKnowledgeStudy.setup mode
  | ["audit-runtime"] => DeliveryKnowledgeStudy.auditRuntime
  | ["prepare-auditor"] => DeliveryKnowledgeStudy.prepareAuditor
  | ["audit-auditor"] => DeliveryKnowledgeStudy.auditAuditor
  | ["collect-controls"] => DeliveryKnowledgeStudy.collectControls
  | ["prepare-delivery"] => DeliveryKnowledgeStudy.prepareDelivery
  | ["seal-installed"] => DeliveryKnowledgeStudy.sealInstalled
  | ["prepare-ledger-auditor"] => DeliveryKnowledgeStudy.prepareLedgerAuditor
  | ["audit-ledger-auditor"] => DeliveryKnowledgeStudy.auditLedgerAuditor
  | ["collect-ledgers"] => DeliveryKnowledgeStudy.collectLedgers
  | ["cleanup"] => DeliveryKnowledgeStudy.cleanup
  | _ => throw (IO.userError "delivery-knowledge prepare/seal-source/setup/audit-runtime required")
