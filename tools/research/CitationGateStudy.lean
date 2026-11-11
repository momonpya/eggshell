import tools.research.StudyLocal
open Lean StudyLocal
namespace CitationGateStudy
def build := base/"record-groups/build"
def source := base/"record-groups/source"
def parent := base/"canonical-decoder-runtime"
def root := base/"citation-gate"
def records := project/"docs/candidates/citation-gate"

def setup : IO Unit := do
  idle
  check (!(← root.pathExists)) "preserve citation trial"
  check ((← hash (build/"StudyMain")) == "f3467bb3b61292db2a7becda1388959b5fd077915939ba20fd24517b066f616c")
    "compiler root is not the finished admission candidate"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  let proof ← command "/usr/bin/env" #["LEAN_PATH="++(build/"lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M3072",(project/"tools/research/CitationGate.lean").toString]
  check (!proof.contains "sorryAx" && !proof.contains "warning:") "citation proof did not close cleanly"
  IO.FS.writeFile (records/"proof.txt") proof
  for name in ["CitationGate","CitationGateBench"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let (entry,_) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (parent/"build/tools_research_OwnedSelectionRuntime.source")))
  let seam := "  | [\"owned-selection-hooks\",input]"
  check ((entry.splitOn seam).length == 2) "sealed native entry changed"
  IO.FS.writeFile (source/"tools/research/OwnedSelectionRuntime.lean")
    ("import tools.research.CitationGateBench\n"++entry.replace seam
      ("  | [\"citation-gate-bench\",output] => Eggshell.Research.CitationGateBench.run (.mk output); return 0\n"++seam))
  write (records/"plan.json") (Json.mkObj [("componentOrders",toJson #[#["reference","candidate"],
    #["candidate","reference"],#["reference","candidate"]]),("candidatePreparationIncluded",toJson true),
    ("fullUnitGeometryConstruction",toJson false),("newSharedCacheOrPool",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "citation-gate-component-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-build-settings.json").toString]

def runComponent : IO Unit := do
  idle
  discard <| finished "citation-gate-component-build"
  guard "citation-gate-component" #[(build/"StudyMain").toString,"citation-gate-bench",(root/"component").toString]

def prepareFactored : IO Unit := do
  idle
  let monitor ← finished "citation-gate-component"
  write (records/"component-first.json") (← read (root/"component/report.json"))
  write (records/"component-first-resources.json") monitor
  let auditor := #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]
  discard <| command "/usr/bin/env" (auditor++#["inspect",build.toString,(records/"component-first-native.json").toString])
  discard <| command "/usr/bin/env" (auditor++#["compare-sources",(parent/"build").toString,build.toString,
    (records/"component-first-sources.json").toString,"tools.research.SharedReadViews",
    "+tools.research.CitationGate","+tools.research.CitationGateBench"])
  for name in ["HashedCueKeys","CitationGate","CitationGateBench"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  guard "citation-gate-factored-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-build-settings.json").toString]

def runFactored : IO Unit := do
  idle
  discard <| finished "citation-gate-factored-build"
  guard "citation-gate-factored" #[(build/"StudyMain").toString,"citation-gate-bench",(root/"factored").toString]

def prepareRuntime : IO Unit := do
  idle
  let monitor ← finished "citation-gate-factored"
  write (records/"component.json") (← read (root/"factored/report.json"))
  write (records/"component-resources.json") monitor
  let auditor := #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]
  discard <| command "/usr/bin/env" (auditor++#["inspect",build.toString,(records/"component-native.json").toString])
  discard <| command "/usr/bin/env" (auditor++#["compare-sources",(parent/"build").toString,build.toString,
    (records/"component-sources.json").toString,"tools.research.SharedReadViews",
    "+tools.research.HashedCueKeys","+tools.research.CitationGate","+tools.research.CitationGateBench"])
  let (original,_) : String × Array (String × String) ← IO.ofExcept
    (fromJson? (← read (parent/"build/Eggshell_Handoff.source")))
  check ((← IO.FS.readFile (source/"Eggshell/Handoff.lean")) == original) "parent Handoff was not preserved"
  let proof ← IO.FS.readFile (project/"tools/research/CitationGate.lean")
  let begin := "namespace Eggshell.Plugin.SharedRangeAdapter.CitationGate\n"
  let ending := "end Eggshell.Plugin.SharedRangeAdapter.CitationGate"
  check ((proof.splitOn begin).length == 2 && (proof.splitOn ending).length == 2) "citation proof wrapper changed"
  let body := ((proof.splitOn begin)[1]!.splitOn ending)[0]!
  let seam := "def bundleRecipeIndexed?"
  check ((original.splitOn seam).length == 2 && original.startsWith "module\n") "native citation seam changed"
  let candidate := (original.drop 7 |>.toString).replace seam
    ("namespace CitationGate\n"++body++"end CitationGate\n\n"++
      "@[csimp] theorem bonus_citation_gate_compiled : @bonusPiecesPrepared = @CitationGate.bonusPiecesHashed :=\n"++
      "  CitationGate.bonusPiecesHashed_exact.symm\n\n"++seam)
  IO.FS.writeFile (source/"Eggshell/Handoff.lean")
    ("module\npublic import tools.research.HashedCueKeys\n"++candidate)
  -- The hook comparison has only this Handoff change and its generic helper.
  -- Remove the preceding pool experiment and component-only CLI entry.
  for name in ["SharedReadViews","OwnedSelectionRuntime"] do
    let (original,_) : String × Array (String × String) ← IO.ofExcept
      (fromJson? (← read (parent/"build"/("tools_research_"++name++".source"))))
    IO.FS.writeFile (source/"tools/research"/(name++".lean")) original
  IO.FS.writeFile (root/"ParentHandoff.lean") original
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",(root/"ParentHandoff.lean").toString,
    (source/"Eggshell/Handoff.lean").toString]}
  check (diff.exitCode == 1) "expected isolated native source change"
  IO.FS.writeFile (records/"runtime.diff") diff.stdout
  write (records/"runtime-plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("directProductChanges",toJson #["Eggshell.Handoff"]),("addedModule",toJson "tools.research.HashedCueKeys"),
    ("proofSha256",toJson (← hash (project/"tools/research/CitationGate.lean"))),
    ("helperSha256",toJson (← hash (project/"tools/research/HashedCueKeys.lean"))),
    ("poolChanged",toJson false),("newSharedCache",toJson false),("rankingOrAuthorityChanged",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "citation-gate-runtime-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(base/"record-groups-build-settings.json").toString]

def prepareHooks : IO Unit := do
  idle
  discard <| finished "citation-gate-runtime-build"
  let auditor := #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]
  discard <| command "/usr/bin/env" (auditor++#["inspect",build.toString,(records/"runtime-native.json").toString])
  discard <| command "/usr/bin/env" (auditor++#["compare-sources",(parent/"build").toString,build.toString,
    (records/"runtime-sources.json").toString,"Eggshell.Handoff","+tools.research.HashedCueKeys"])
  IO.FS.createDirAll (root/"prefix/libexec")
  discard <| command "/bin/ln" #["-s",(build/"StudyMain").toString,(root/"prefix/libexec/eggshell").toString]
  discard <| command "/bin/ln" #["-s",(parent/"prefix/share").toString,(root/"prefix/share").toString]
  let output := root/"hooks"
  let runtime := root/"prefix/libexec/eggshell"
  let config := output/"config.toml"
  let reference ← read (parent/"preflight-input.json")
  let environments : Array (String × Option String) ← IO.ofExcept (fromJson? (reference.getObjValD "environment"))
  let environments := environments.map fun (key,value) => (key,
    if key == "EGGSHELL_PREFIX" then some (root/"prefix").toString
    else if key == "PLUGIN_ROOT" then some (root/"prefix/share/eggshell/codex-plugin").toString
    else if key == "EGGSHELL_CONFIG" then some config.toString else value)
  let input := Json.mkObj ((← IO.ofExcept reference.getObj?).toArray.toList.filter (fun row =>
    !["output","runtime","runtimeSha256","plugin","config","environment","counts","diagnostic"].contains row.1)++[
    ("output",toJson output.toString),("runtime",toJson runtime.toString),
    ("runtimeSha256",toJson (← hash runtime)),("plugin",toJson (root/"prefix/share/eggshell/codex-plugin").toString),
    ("config",toJson config.toString),("environment",toJson environments),
    ("counts",toJson (#[(4 : Nat),16])),("diagnostic",toJson false)])
  let path := root/"hooks-input.json"
  check (!(← path.pathExists) && !(← output.pathExists)) "preserve native hook gate"
  write path input
  let unsets := environments.foldl (fun args (key,value) => if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environments.filterMap fun (key,value) => value.map (key++"="++·)
  guard "citation-gate-hooks" (#["/usr/bin/env"]++unsets++assignments++
    #[runtime.toString,"owned-selection-capacity",path.toString])

def collect : IO Unit := do
  idle
  let monitor ← finished "citation-gate-hooks"
  let output := root/"hooks"
  let input ← read (root/"hooks-input.json")
  let report ← read (output/"report.json")
  check (report.getObjValD "allPhasesPassed" == toJson true &&
    report.getObjValD "originalSourceFilesUnchanged" == toJson true) "actual hook gate is incomplete"
  for name in ["frontend-shutdown.json","publisher-shutdown.json"] do
    let stopped ← read (output/name)
    check (stopped.getObjValD "acknowledged" == toJson true &&
      stopped.getObjValD "processExited" == toJson true &&
      stopped.getObjValD "daemonExitCode" == toJson (0 : Nat)) "service did not drain"
  let phases ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  let mut clients := #[]
  let mut verified := 0
  for directory in [output/"prime",output/"phase-4",output/"phase-16"] do
    let rows ← read (if directory == output/"prime" then output/"prime.json" else directory/"clients.json")
    for row in ← IO.ofExcept rows.getArr? do
      let index ← IO.ofExcept (row.getObjValAs? Nat "client")
      let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
      let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
      let receipts := parent/"data/receipts"/receipt
      let stdout := directory/s!"client-{index}/stdout"
      let published := (← read (receipts/"published.json")).getObjValD "data"
      let text ← IO.FS.readFile stdout
      check (published.getObjValD "output" == toJson text &&
        published.getObjValD "sha256" == toJson (← hash stdout) &&
        published.getObjValD "replyComplete" == toJson true) "stdout and publication differ"
      let decoded ← IO.ofExcept (Json.parse text)
      let body ← IO.ofExcept ((decoded.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
      let some reference := topics.find? (fun t => t.getObjValD "topic" == toJson topic) |
        throw (IO.userError "topic has no frozen body")
      let bodyPath ← IO.ofExcept (reference.getObjValAs? String "body")
      check (body == (← IO.FS.readFile (.mk bodyPath))) "actual delivered body differs from the frozen source"
      let search := (← read (receipts/"search.json")).getObjValD "data"
      let synapse := (← read (receipts/"synaptic-delivery.json")).getObjValD "data"
      let ack := (← read (receipts/"ack.json")).getObjValD "data"
      check ((search.getObjValD "trace").getObjValD "route" == toJson "configured" &&
        (search.getObjValD "trace").getObjValD "semantic" == toJson "completed" &&
        synapse.getObjValD "complete" == toJson true && synapse.getObjValD "packetVerified" == toJson true &&
        ack.getObjValD "offerAccepted" == toJson true && row.getObjValD "success" == toJson true)
        "native result lost semantic, synapse or ACK evidence"
      clients := clients.push (Json.mkObj [("phase",toJson directory.fileName),
        ("client",toJson index),("topic",toJson topic),("elapsedMs",row.getObjValD "elapsedMs"),
        ("bodySha256",toJson (← hash (.mk bodyPath))),("stdoutSha256",published.getObjValD "sha256")])
      verified := verified+1
  check (verified == 23) "expected three primes and 4/16 native callers"
  let sources : Array (String × String) ← IO.ofExcept (input.getObjValAs? _ "sourceFiles")
  let sourceRoot ← IO.ofExcept (input.getObjValAs? String "project")
  for (path,digest) in sources do
    check ((← hash (System.FilePath.mk sourceRoot/path)) == digest) "original DB changed after native shutdown"
  write (records/"hooks.json") (Json.mkObj [("report",report),("phases",toJson phases),
    ("primes",← read (output/"prime.json")),("clients",toJson clients),
    ("verifiedPublishedClients",toJson verified),("sameFrozenOriginalSource",toJson true),
    ("cacheStats",← read (output/"cache-stats-phase-16.json")),
    ("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisons",toJson (0 : Nat)),
    ("adopted",toJson false),("singleGateNotRepeatedPerformanceComparison",toJson true)])
  write (records/"hooks-resources.json") monitor

def prepareRetirement : IO Unit := do
  idle
  discard <| finished "citation-gate-hooks"
  check ((← read (records/"hooks.json")).getObjValD "verifiedPublishedClients" == toJson (23 : Nat))
    "collect actual bodies before removing trial state"
  IO.FS.writeFile (records/"runtime-proof.txt")
    ((← IO.FS.readFile (build/"Eggshell_Handoff-lean.stdout"))++
      (← IO.FS.readFile (build/"tools_research_HashedCueKeys-lean.stdout")))
  let calls ← IO.FS.readFile (root/"native-calls.txt")
  let expected := #["_l_Eggshell_Plugin_SharedRangeAdapter_CitationGate_prepare",
    "_l_Eggshell_Research_HashedCueKeys_many___redArg",
    "_l_Eggshell_Plugin_SharedRangeAdapter_CitationGate_bonusPiecesHashed"]
  let branches := calls.splitOn "\n" |>.filter fun row => row.contains "ARM64_RELOC_BRANCH26"
  check (expected.all fun callee => branches.any (·.contains callee)) "native caller bypasses citation preparation or key hashing"
  write (records/"native-calls.json") (Json.mkObj [("objectSha256",toJson (← hash (build/"Eggshell_Handoff.o"))),
    ("disassemblySha256",toJson (← hash (root/"native-calls.txt"))),
    ("selectedFunctions",toJson #["bundleRecipeIndexed?","CitationGate.bonusPiecesHashed"]),
    ("checkedBranchTargets",toJson expected),
    ("matchingRelocations",toJson (branches.filter fun row => expected.any (fun callee => row.contains callee)))])
  let previous ← read (base/"view-admission-retirement-input.json")
  let libraries ← IO.ofExcept (previous.getObjValAs? (Array String) "libraries")
  let protectedFiles ← IO.ofExcept (previous.getObjValAs? (Array String) "protectedFiles")
  let config := previous.setObjVal! "libraries" (toJson (libraries.filter (· != (build/"lib").toString)))
    |>.setObjVal! "builds" (toJson #[(parent/"build").toString])
    |>.setObjVal! "strictBuilds" (toJson #[(parent/"build").toString])
    |>.setObjVal! "protectedFiles" (toJson (protectedFiles.filter (· != (build/"StudyMain").toString)))
    |>.setObjVal! "closedDirectories" (toJson #[
      (base/"record-groups").toString,root.toString,(base/"view-admission").toString,
      (parent/"data/sessions").toString,(parent/"data/receipts").toString,
      (parent/"data/confirmed-delivery").toString])
    |>.setObjVal! "plan" (toJson (base/"citation-gate-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"retirement.json").toString)
  write (base/"citation-gate-retirement-input.json") config

def prepareParentCheck : IO Unit := do
  idle
  check ((← read (records/"retirement.json")).getObjValD "completed" == toJson true) "retirement is incomplete"
  let output := base/"citation-gate-parent-check"
  let reference ← read (parent/"preflight-input.json")
  let config := output/"config.toml"
  let environments : Array (String × Option String) ← IO.ofExcept (fromJson? (reference.getObjValD "environment"))
  let environments := environments.map fun (key,value) =>
    (key,if key == "EGGSHELL_CONFIG" then some config.toString else value)
  let input := reference.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "environment" (toJson environments)
    |>.setObjVal! "counts" (toJson (#[(4 : Nat)]))
    |>.setObjVal! "diagnostic" (toJson true)
  let path := base/"citation-gate-parent-check-input.json"
  check (!(← path.pathExists) && !(← output.pathExists)) "preserve post-retirement validation"
  write path input
  let unsets := environments.foldl (fun args (key,value) => if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environments.filterMap fun (key,value) => value.map (key++"="++·)
  guard "citation-gate-parent-check" (#["/usr/bin/env"]++unsets++assignments++
    #[(parent/"prefix/libexec/eggshell").toString,"owned-selection-capacity",path.toString])

def collectParentCheck : IO Unit := do
  idle
  let monitor ← finished "citation-gate-parent-check"
  let output := base/"citation-gate-parent-check"
  let report ← read (output/"report.json")
  let mut count := 0
  let mut checked := #[]
  for directory in [output/"prime",output/"phase-4"] do
    let rows ← read (if directory == output/"prime" then output/"prime.json" else directory/"clients.json")
    for row in ← IO.ofExcept rows.getArr? do
      let index ← IO.ofExcept (row.getObjValAs? Nat "client")
      let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
      let location := parent/"data/receipts"/receipt
      let published := (← read (location/"published.json")).getObjValD "data"
      let search := (← read (location/"search.json")).getObjValD "data"
      let synapse := (← read (location/"synaptic-delivery.json")).getObjValD "data"
      let ack := (← read (location/"ack.json")).getObjValD "data"
      check (row.getObjValD "success" == toJson true &&
        published.getObjValD "sha256" == toJson (← hash (directory/s!"client-{index}/stdout")) &&
        (search.getObjValD "trace").getObjValD "semantic" == toJson "completed" &&
        synapse.getObjValD "complete" == toJson true && synapse.getObjValD "packetVerified" == toJson true &&
        ack.getObjValD "offerAccepted" == toJson true) "parent validation lost its publication or original route"
      checked := checked.push (Json.mkObj [("phase",toJson directory.fileName),
        ("client",toJson index),("stdoutSha256",published.getObjValD "sha256")])
      count := count+1
  check (count == 7 && report.getObjValD "originalSourceFilesUnchanged" == toJson true) "parent input validation incomplete"
  write (records/"parent-after-retirement.json") (Json.mkObj [("report",report),("guard",monitor),
    ("verifiedPublishedClients",toJson count),("checked",toJson checked),("performanceComparison",toJson false)])
  let previous ← read (base/"citation-gate-retirement-input.json")
  let config := previous.setObjVal! "closedDirectories" (toJson #[output.toString,
      (parent/"data/sessions").toString,(parent/"data/receipts").toString,(parent/"data/confirmed-delivery").toString])
    |>.setObjVal! "plan" (toJson (base/"citation-gate-parent-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"parent-check-retirement.json").toString)
  write (base/"citation-gate-parent-retirement-input.json") config


def main (args : List String) : IO Unit := match args with
  | ["setup"] => setup
  | ["prepare-component"] => runComponent
  | ["prepare-factored"] => prepareFactored
  | ["run-factored"] => runFactored
  | ["prepare-runtime"] => prepareRuntime
  | ["prepare-hooks"] => prepareHooks
  | ["collect"] => collect
  | ["prepare-retirement"] => prepareRetirement
  | ["prepare-parent-check"] => prepareParentCheck
  | ["collect-parent-check"] => collectParentCheck
  | _ => throw (IO.userError "active citation stage required")
end CitationGateStudy
def main := CitationGateStudy.main
