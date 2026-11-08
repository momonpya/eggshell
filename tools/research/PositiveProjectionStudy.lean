import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
namespace PositiveProjectionStudy
def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := project/"docs/candidates/positive-projection"
def parent := base/"support-presence-runtime-build"
def target := base/"positive-projection-runtime-build"
def source := base/"positive-projection-runtime-source"
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some project}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def idle : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.trimAscii.toString.startsWith ((base/"controller/StudyMain").toString++" guard ") ||
    row.trimAscii.toString.startsWith ((base/"resource-budget-guard-build/StudyMain").toString++" "))) "resource guard is live"
def replaceOnce (body anchor replacement : String) : IO String := do
  check ((body.splitOn anchor).length == 2) "actual native consumer changed"
  return body.replace anchor replacement
def materialize (originBuild destination build : System.FilePath) (entry settings : String) : IO Unit := do
  check (!(← destination.pathExists) && !(← build.pathExists)) "fresh isolated build required"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",originBuild.toString,
    destination.toString,build.toString,entry,(base/settings).toString]

def prepare : IO Unit := do
  idle
  check ((← read (project/"docs/candidates/support-presence/runtime.json")).getObjValD "sha256" == toJson (← hash (parent/"StudyMain")))
    "actual normal-product parent changed"
  IO.FS.createDirAll folder
  let proof ← command "/usr/bin/env" #["LEAN_PATH="++(parent/"lib").toString,(compiler/"bin/lean").toString,
    "-j1","-M1536","-DwarningAsError=true",(project/"tools/research/PositiveProjection.lean").toString]
  check (!proof.contains "sorryAx") "admitted positive projection proof"
  write (folder/"proofs.json") (Json.mkObj [("kernelChecked",toJson true),("axioms",toJson proof),
    ("sourceSha256",toJson (← hash (project/"tools/research/PositiveProjection.lean")))])
  materialize parent source target "tools.research.ReplayReadinessChecks" "positive-projection-runtime-settings.json"
  IO.FS.writeFile (source/"tools/research/PositiveProjection.lean")
    (← IO.FS.readFile (project/"tools/research/PositiveProjection.lean"))
  let path := source/"Eggshell/Handoff.lean"
  let original ← IO.FS.readFile path
  let body ← replaceOnce original "public import Eggshell.PacketReceipt\n"
    "public import Eggshell.PacketReceipt\npublic import tools.research.PositiveProjection\n"
  let oldPolicy := "def DeliveryPart.acknowledgmentPolicy (part : DeliveryPart) : Synapses.Read → Bool :=\n"++
    "  if !part.projectionComplete then fun _ => false else\n"++
    "  match part.context with\n"++
    "  | some context => fun read => read.binding.owner == context.owner &&\n"++
    "    context.fragments.any (fun fragment =>\n"++
    "      fragment.first ≤ read.binding.first && read.binding.limit ≤ fragment.first+fragment.original.length)\n"++
    "  | none =>\n"++
    "    let keys := part.shared.toArray.foldl (fun keys shared => shared.rows.foldl (fun keys row =>\n"++
    "      row.origins.foldl (fun keys origin => keys.insert (origin.binding,origin.occurrence,\n"++
    "        (⟨row.key.file,row.key.line,row.key.line⟩ : Synapses.Range))) keys) keys)\n"++
    "      ({} : Std.HashSet (Synapses.Binding × Synapses.Occurrence × Synapses.Range))\n"++
    "    fun read => keys.contains (read.binding,read.occurrence,read.source)\n"
  let newPolicy := "def DeliveryPart.preparedAcknowledgment (part : DeliveryPart) : Research.PositiveProjection.Policy :=\n"++
    "  match part.context with\n"++
    "  | some context =>\n"++
    "    if !part.projectionComplete then .reject else\n"++
    "      .context context.owner (context.fragments.toArray.map fun fragment =>\n"++
    "        (fragment.first,fragment.first+fragment.original.length))\n"++
    "  | none =>\n"++
    "    match part.shared with\n"++
    "    | some shared =>\n"++
    "      if part.text == shared.render && part.keys == shared.keys then\n"++
    "        Research.PositiveProjection.prepareShared shared.rows else .reject\n"++
    "    | none => .reject\n"
  let body ← replaceOnce body oldPolicy newPolicy
  let body ← replaceOnce body
    ("  let accepts := part.acknowledgmentPolicy\n"++
      "  part.evidence.filter fun read => read.valid && accepts read\n")
    "  Research.PositiveProjection.select part.preparedAcknowledgment part.evidence\n"
  let body ← replaceOnce body
    ("  have selected := Array.mem_filter.mp member\n"++
      "  exact ⟨selected.1,(Bool.and_eq_true_iff.mp selected.2).1⟩\n")
    "  exact Research.PositiveProjection.selected_was_prepared _ _ _ member\n"
  let oldProjection := "  | some captured => {\n"++
    "      rows := captured.packet.parts.toArray.flatMap fun part =>\n"++
    "        part.acknowledgedReads.map fun read => ⟨read.binding.database,read.source⟩\n"++
    "      bindings := captured.packet.parts.toArray.flatMap fun part =>\n"++
    "        if !part.projectionComplete then #[] else\n"++
    "        part.context.toArray.flatMap fun context => context.fragments.toArray.flatMap fun fragment =>\n"++
    "          part.nativeOwners.map fun owner =>\n"++
    "            ⟨owner.database,owner.owner,owner.work,fragment.first,fragment.first+fragment.original.length⟩\n"++
    "      complete := captured.packet.parts.all (·.projectionComplete)}\n"
  let newProjection := "  | some captured =>\n"++
    "      let rows := captured.packet.parts.toArray.flatMap fun part =>\n"++
    "        part.acknowledgedReads.map fun read => (⟨read.binding.database,read.source⟩ : Synapses.DeliveryLedger.Row)\n"++
    "      let bindings := captured.packet.parts.toArray.flatMap fun part =>\n"++
    "        if !part.projectionComplete then #[] else\n"++
    "        part.context.toArray.flatMap fun context => context.fragments.toArray.flatMap fun fragment =>\n"++
    "          part.nativeOwners.map fun owner =>\n"++
    "            (⟨owner.database,owner.owner,owner.work,fragment.first,fragment.first+fragment.original.length⟩ : Synapses.Binding)\n"++
    "      Research.PositiveProjection.checked rows bindings\n"
  let body ← replaceOnce body oldProjection newProjection
  IO.FS.writeFile path body
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/Eggshell/Handoff.lean","-L","b/Eggshell/Handoff.lean",
    (base/"support-presence-runtime-source/Eggshell/Handoff.lean").toString,path.toString]}
  check (diff.exitCode == 1) "actual projection consumer patch required"
  IO.FS.writeFile (folder/"handoff.patch") diff.stdout
  write (folder/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"StudyMain"))),
    ("change",toJson "retain only source-verified evidence still represented in the final packet; advisory completeness no longer vetoes unrelated positive evidence"),
    ("sourceByteVerificationUnchanged",toJson true),("authorityAndBodySelectionUnchanged",toJson true),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def setup (mode : String) : IO Unit := do
  idle
  if mode == "cells" then
    check ((← read (folder/"controls.json")).getObjValD "allPassed" == toJson true) "positive and ACK controls required before real hooks"
  let tag := "positive-projection-"++mode++"2"
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve previous stage"
  let args ← match mode with
    | "runtime-build" | "auditor-build" | "ledger-audit-build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/("positive-projection-"++mode.replace "-build" ""++"-settings.json")).toString]
    | "install" | "cells" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"positive-projection-auditor-build/StudyMain").toString,
      (if mode == "install" then "install-prefix" else "cells"),(base/("positive-projection-"++mode++".json")).toString]
    | "controls" | "acks" => do
      let binary := base/"positive-projection-auditor-build/StudyMain"
      check ((← read (folder/"auditor.json")).getObjValD "sha256" == toJson (← hash binary)) "checked auditor required"
      let root := base/("positive-projection-"++mode++"-result")
      let data := base/("positive-projection-"++mode++"-data")
      check (!(← root.pathExists) && !(← data.pathExists)) "fresh control output and data required"
      pure #["/usr/bin/env","LEAN_NUM_THREADS=2","EGGSHELL_DATA_ROOT="++data.toString,binary.toString,
        (if mode == "controls" then "positive-projection-controls" else "session-ack-controls"),root.toString]
    | _ => throw (IO.userError "fixed native build, install or cells stage required")
  write path (Json.mkObj [("command",toJson args),("cwd",toJson project.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def auditRuntime : IO Unit := do
  idle
  let guard ← read (base/"positive-projection-runtime-build2.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "normal candidate has not succeeded and drained"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",target.toString,(folder/"runtime-closure.json").toString],
    #["compare-sources",parent.toString,target.toString,(folder/"runtime-sources.json").toString,
      "Eggshell.Handoff","+tools.research.PositiveProjection"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  check ((← read (folder/"runtime-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected native product changes"
  let native : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (target/"tools_research_PositiveProjection.source")))
  check (native.1 == (← IO.FS.readFile (project/"tools/research/PositiveProjection.lean"))) "actual positive projection source differs"
  write (folder/"runtime.json") (Json.mkObj [("sha256",toJson (← hash (target/"StudyMain"))),
    ("guard",guard),("actualSourcesMatchRepository",toJson true),("adopted",toJson false)])

def hex (text : String) : Option Nat := text.toList.foldlM (fun total char => do
  let digit ← if '0' ≤ char && char ≤ '9' then some (char.toNat-'0'.toNat)
    else if 'a' ≤ char && char ≤ 'f' then some (char.toNat-'a'.toNat+10) else none
  return total*16+digit) 0
def calls (path : System.FilePath) (wanted : String → Bool) : IO (Array (String × String)) := do
  let words := fun (line : String) => (line.replace "\t" " ").splitOn " " |>.filter (! ·.isEmpty)
  let symbols := (((← command "/usr/bin/nm" #["-gU",path.toString]).splitOn "\n").filterMap fun line => do
    let columns := words line
    return (← hex (← columns[0]?),← columns[2]?)).toArray.qsort (fun a b => a.1 < b.1)
  return (((← command "/usr/bin/otool" #["-rv",path.toString]).splitOn "\n").filterMap fun line => do
    let columns := words line
    if !columns.contains "BR26" then none else
      let callee ← columns.getLast?
      if !wanted callee then none else do
      let address ← hex (← columns[0]?)
      let caller := (symbols.filter (·.1 ≤ address)).back?.map Prod.snd |>.getD ""
      return (caller,callee)).toArray

def auditPrepared : IO Unit := do
  idle
  let object := target/"Eggshell_Handoff.o"
  let relevant ← calls object fun callee => callee.contains "PositiveProjection_select" ||
    callee.contains "preparedAcknowledgment" || callee.contains "acknowledgmentPolicy" || callee.contains "PositiveProjection_sharedPolicy"
  let consumers := relevant.filter fun (caller,_) => caller == "_l_Eggshell_Plugin_DeliveryPart_acknowledgedReads"
  check (consumers.any (fun (_,callee) => callee.contains "PositiveProjection_select"))
    "strict policy data is disconnected from actual evidence selection"
  check (!(relevant.any fun (caller,callee) => caller.contains "acknowledgedReads" &&
    (callee.contains "acknowledgmentPolicy" || callee.contains "PositiveProjection_sharedPolicy")))
    "actual evidence filter still reconstructs its per-read policy"
  let helperObject := target/"tools_research_PositiveProjection.o"
  let preparation ← calls helperObject fun callee => callee.contains "prepareShared" || callee.contains "identities" ||
    callee.contains "sharedPolicy" || callee.contains "insertManyIfNewUnit"
  let loops := preparation.filter fun (caller,_) => caller.contains "PositiveProjection_select"
  check loops.isEmpty "strict selection loop reaches index reconstruction"
  write (folder/"native-preparation.json") (Json.mkObj [("runtimeSha256",toJson (← hash (target/"StudyMain"))),
    ("handoffObjectSha256",toJson (← hash object)),("helperObjectSha256",toJson (← hash helperObject)),
    ("actualConsumerCalls",toJson consumers),("perReadIndexReconstructionCalls",toJson loops),
    ("strictPreparedPolicyConnected",toJson true),("adopted",toJson false)])

def recordEagerFailure : IO Unit := do
  idle
  check (!(← (folder/"eager-failure.json").pathExists)) "preserve recorded eager failure"
  let guard ← read (base/"positive-projection-cells1.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (1 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "eager failure has not stopped"
  let object := target/"Eggshell_Handoff.o"
  let handoffCalls := (← calls object (fun callee => callee == "_l_Eggshell_Plugin_DeliveryPart_acknowledgmentPolicy" ||
    callee == "_l_Eggshell_Research_PositiveProjection_sharedPolicy")).filter fun (caller,callee) =>
    (caller.contains "acknowledgedReads" && callee == "_l_Eggshell_Plugin_DeliveryPart_acknowledgmentPolicy") ||
    (caller == "_l_Eggshell_Plugin_DeliveryPart_acknowledgmentPolicy" && callee == "_l_Eggshell_Research_PositiveProjection_sharedPolicy")
  check (handoffCalls.size == 2) "failed compiled filter no longer rebuilds its per-read policy"
  let helperObject := target/"tools_research_PositiveProjection.o"
  let helperCalls := (← calls helperObject (fun callee => callee.contains "flatMapTR" || callee.contains "insertManyIfNewUnit")).filter fun (caller,callee) =>
    caller == "_l_Eggshell_Research_PositiveProjection_sharedPolicy" &&
      (callee.contains "flatMapTR" || callee.contains "insertManyIfNewUnit")
  check (helperCalls.size == 2) "failed native policy no longer reconstructs the origin index"
  let cell := base/"positive-projection-cells-result/topic-1-chat-0"
  let input ← read (cell/"hook/stdin")
  let session ← IO.ofExcept (input.getObjValAs? String "session_id")
  let data := base/"real-source-search-read-trial-result/data"
  let state ← read (data/"sessions"/session/"state.json")
  check (state.getObjValD "confirmedDelivery" == Json.null && state.getObjValD "offers" == toJson (#[] : Array Json) &&
    !(← (data/"confirmed-delivery").pathExists)) "failed probe reached a ledger commit"
  let receipt := "5f02e8c40e5549a9433d30f9a7dd109d6884d04468e34386525db761dfbd41dc"
  let evidence ← read (data/"receipts"/receipt/"synaptic-delivery.json")
  let finished ← read (data/"receipts"/receipt/"operation-42b82cf9f623c132756bd983e634c7ee7809b5b7e1542ceb9bf525cdadba434d-finished.json")
  write (folder/"eager-failure.json") (Json.mkObj [("guard",guard),
    ("runtime",← read (folder/"runtime.json")),("settings",← read (base/"positive-projection-runtime-settings.json")),
    ("progress",← read (base/"positive-projection-cells-result/progress.json")),
    ("hook",← read (cell/"hook/record.json")),("hookStderr",toJson (← IO.FS.readFile (cell/"hook/stderr"))),
    ("shutdownStderr",toJson (← IO.FS.readFile (base/"positive-projection-cells1.stderr"))),
    ("bodySha256",toJson (← hash (cell/"body.txt"))),
    ("handoffObjectSha256",toJson (← hash object)),("handoffCalls",toJson handoffCalls),
    ("helperObjectSha256",toJson (← hash helperObject)),("helperCalls",toJson helperCalls),
    ("operation",finished),("checkedWitnesses",(evidence.getObjValD "data").getObjValD "sharedWitnessesChecked"),
    ("packetVerified",(evidence.getObjValD "data").getObjValD "packetVerified"),
    ("confirmedReference",Json.null),("ledgerCreated",toJson false),("adopted",toJson false),
    ("reachedCells",toJson (1 : Nat)),("completedSixCellStudy",toJson false),
    ("cause",toJson "compiled evidence filter calls acknowledgmentPolicy for every Read; that policy reconstructs the shared keys and origin index"),
    ("unchangedRetry",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  for name in ["runtime.json","runtime-closure.json","runtime-sources.json","auditor.json","auditor-closure.json","auditor-sources.json",
      "controls.json","proofs.json","handoff.patch","plan.json"] do
    IO.FS.rename (folder/name) (folder/("eager-"++name))

def retireEager : IO Unit := do
  idle
  check ((← read (folder/"eager-failure.json")).getObjValD "ledgerCreated" == toJson false)
    "retain the native failure diagnosis before retiring it"
  let cell := base/"positive-projection-cells-result/topic-1-chat-0"
  let session ← IO.ofExcept ((← read (cell/"hook/stdin")).getObjValAs? String "session_id")
  check (session.startsWith "real-source-" && session.length == 76) "failed session escaped generated scope"
  let data := base/"real-source-search-read-trial-result/data"
  let roots := #[target,source,base/"positive-projection-auditor-build",base/"positive-projection-auditor-source",
    base/"positive-projection-prefix"]
  let running := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(running.any fun line => roots.any fun root => line.trimAscii.toString.startsWith (root.toString++"/")))
    "failed native runtime remains live"
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if !roots.contains entry.path && (← response.pathExists) then
      let body ← IO.FS.readFile response
      for root in roots do check (!body.contains (root.toString++"/")) "another runtime depends on the ended failed build"
  let diff ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/tools/research/PositiveProjection.lean",
    "-L","b/tools/research/PositiveProjection.lean",(source/"tools/research/PositiveProjection.lean").toString,
    (project/"tools/research/PositiveProjection.lean").toString]}
  check (diff.exitCode == 1) "the next implementation must change the native per-read preparation"
  IO.FS.writeFile (folder/"strict-policy.patch") diff.stdout
  let body ← IO.FS.readFile (cell/"body.txt")
  check (body.utf8ByteSize ≤ 2048) "unexpected large failed body; retain it explicitly instead"
  let failed ← read (folder/"eager-failure.json")
  write (folder/"eager-failure.json") (failed.setObjVal! "body" (toJson body)
    |>.setObjVal! "harnessInput" (← read (base/"positive-projection-cells.json")))
  let mut paths := roots++#[base/"positive-projection-cells-result",data/"sessions"/session,
    base/"positive-projection-controls-result",base/"positive-projection-controls-data",
    base/"positive-projection-acks-result",base/"positive-projection-acks-data"]
  for entry in ← (data/"receipts").readDir do
    let request := entry.path/"request.json"
    if ← request.pathExists then
      let payload ← read request
      if (payload.getObjValD "data").getObjValD "session" == toJson session then paths := paths.push entry.path
  for path in [data/"daemon.json",data/"publisher/endpoint.json"] do
    if ← path.pathExists then
      let pid ← IO.ofExcept ((← read path).getObjValAs? Nat "pid")
      let alive ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
      check (alive.exitCode != 0) "an endpoint still belongs to a live process"
      paths := paths.push path
  let mut guards := #[]
  for name in ["runtime-build","auditor-build","controls","acks","install","cells"] do
    let tag := "positive-projection-"++name++"1"
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "failed stage still owns a process"
    guards := guards.push (tag,guard)
    for extension in ["stdout","stderr"] do paths := paths.push (base/(tag++"."++extension))
  let mut retained := #[]
  for name in ["support-presence-runtime-build/StudyMain","support-presence-auditor-build/StudyMain",
      "real-source-search-read-trial-result/work.egg/head",
      "real-source-search-read-trial-result/work.egg/2a1ab5766ac89060c477ae3fc9683c9492574ff843d134c01b53d9697a27359e.pages"] do
    let path := base/name
    retained := retained.push (path,← hash path)
  let record := Json.mkObj [("guards",toJson guards),("paths",toJson (paths.map (·.toString))),
    ("retained",toJson (retained.map fun (path,sha) => (path.toString,sha))),
    ("runtimeBuildSettings",← read (base/"positive-projection-runtime-settings.json")),
    ("auditorBuildSettings",← read (base/"positive-projection-auditor-settings.json")),
    ("archived",toJson false),("currentProjectCacheModelsAndComparisonBodiesRetained",toJson true)]
  write (folder/"eager-cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then discard <| command "/bin/rm" #["-rf","--",path.toString]
  for (path,sha) in retained do check ((← hash path) == sha) "parent product or original changed during eager cleanup"
  write (folder/"eager-cleanup.json") (record.setObjVal! "completed" (toJson true))

def prepareAuditor : IO Unit := do
  idle
  check ((← read (folder/"runtime.json")).getObjValD "sha256" == toJson (← hash (target/"StudyMain")))
    "checked normal candidate required"
  check ((← read (folder/"native-preparation.json")).getObjValD "runtimeSha256" == toJson (← hash (target/"StudyMain")))
    "actual strict prepared consumer required"
  let destination := base/"positive-projection-auditor-source"
  materialize (base/"support-presence-auditor-build") destination (base/"positive-projection-auditor-build")
    "tools.research.ScorePrepareControls" "positive-projection-auditor-settings.json"
  for name in ["Eggshell/Handoff.lean","tools/research/PositiveProjection.lean"] do
    IO.FS.writeFile (destination/name) (← IO.FS.readFile (source/name))
  for name in ["PositiveProjectionChecks","SessionAcknowledgmentChecks"] do
    IO.FS.writeFile (destination/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (project/"tools/research"/(name++".lean")))
  let path := destination/"tools/research/ScorePrepareControls.lean"
  let body ← IO.FS.readFile path
  let body ← replaceOnce body "import tools.research.ScopedEncodeControls\n"
    ("import tools.research.ScopedEncodeControls\nimport tools.research.PositiveProjectionChecks\n"++
      "import tools.research.SessionAcknowledgmentChecks\n")
  let body ← replaceOnce body "  | [\"score-prepare-controls\",root] =>"
    ("  | [\"positive-projection-controls\",root] => Eggshell.Research.PositiveProjectionChecks.run (.mk root); return 0\n"++
      "  | [\"session-ack-controls\",output] => Eggshell.Research.SessionAcknowledgmentChecks.run output; return 0\n"++
      "  | [\"score-prepare-controls\",root] =>")
  IO.FS.writeFile path body

def auditAuditor : IO Unit := do
  idle
  let guard ← read (base/"positive-projection-auditor-build2.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "matching auditor has not succeeded and drained"
  let build := base/"positive-projection-auditor-build"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"auditor-closure.json").toString],
    #["common-sources",target.toString,build.toString,(folder/"auditor-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let gate ← read (folder/"auditor-sources.json")
  check (gate.getObjValD "allProductCorePresent" == toJson true && gate.getObjValD "commonSourcesUnchanged" == toJson true)
    "auditor differs from the product core"
  for name in ["PositiveProjectionChecks","SessionAcknowledgmentChecks"] do
    let native : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/("tools_research_"++name++".source"))))
    check (native.1 == (← IO.FS.readFile (project/"tools/research"/(name++".lean")))) "actual controls differ from repository"
  write (folder/"auditor.json") (Json.mkObj [("guard",guard),("sha256",toJson (← hash (build/"StudyMain"))),
    ("actualControlSourcesMatch",toJson true),("adopted",toJson false)])

def prepareDelivery : IO Unit := do
  idle
  let gate ← read (folder/"auditor-sources.json")
  check (gate.getObjValD "allProductCorePresent" == toJson true && gate.getObjValD "commonSourcesUnchanged" == toJson true)
    "matching native auditor required"
  let installation := base/"positive-projection-prefix"
  let digest ← hash (target/"StudyMain")
  check ((← read (folder/"runtime.json")).getObjValD "sha256" == toJson digest) "checked normal runtime required"
  write (base/"positive-projection-install.json") (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (target/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let input ← read (base/"support-presence-cells.json")
  let output := base/"positive-projection-cells2-result"
  check (!(← output.pathExists)) "preserve existing actual hook results"
  let probes ← IO.ofExcept (input.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let some name := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName |
      throw (IO.userError "probe destination has no name")
    return probe.setObjVal! "destination" (toJson (output/name).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"positive-projection-cells.json") (input.setObjVal! "output" (toJson output.toString)|>.setObjVal! "probes" (toJson probes))

def sealInstalled : IO Unit := do
  idle
  let guard ← read (base/"positive-projection-install2.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "installation did not succeed and drain"
  let binary := base/"positive-projection-prefix/libexec/eggshell"
  check ((← hash binary) == (← hash (target/"StudyMain"))) "installed runtime changed"
  let temporary := binary.withExtension "shared"
  check (!(← temporary.pathExists)) "temporary installed link exists"
  discard <| command "/bin/ln" #[(target/"StudyMain").toString,temporary.toString]
  IO.FS.rename temporary binary

def collectControls : IO Unit := do
  idle
  let mut guards := #[]
  for name in ["controls","acks"] do
    let guard ← read (base/("positive-projection-"++name++"2.guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "controls have not succeeded and drained"
    guards := guards.push (name,guard)
  let controls ← read (base/"positive-projection-controls-result/report.json")
  check (controls.getObjValD "allPassed" == toJson true) "positive projection controls did not pass"
  let acknowledgments ← read (base/"positive-projection-acks-result")
  check ((← IO.ofExcept (acknowledgments.getObjValAs? (Array Json) "checks")).size == 9) "all ACK interleavings required"
  write (folder/"controls.json") (Json.mkObj [("guards",toJson guards),("projection",controls),
    ("acknowledgments",acknowledgments),("allPassed",toJson true),("adopted",toJson false)])

def setupLedgerAudit : IO Unit := do
  idle
  check ((← read (folder/"delivery-cells.json")).getObjValD "actualDeliveryAllSixPassed" == toJson true)
    "all six actual hook bodies required before auditing accepted heads"
  let path := base/"positive-projection-ledgers2.guard-settings.json"
  check (!(← path.pathExists) && !(← (folder/"confirmed-ledgers.json").pathExists)) "preserve prior ledger audit"
  let runtime := base/"positive-projection-ledger-audit-build/StudyMain"
  check ((← read (folder/"ledger-auditor-runtime.json")).getObjValD "sha256" == toJson (← hash runtime))
    "checked native ledger reader required"
  write path (Json.mkObj [("command",toJson #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "EGGSHELL_DATA_ROOT="++(base/"real-source-search-read-trial-result/data").toString,
    runtime.toString,
    (base/"positive-projection-cells2-result").toString,(base/"real-source-search-read-trial-result/data").toString,
    (base/"real-source-search-read-trial-result/work.egg").toString,(folder/"confirmed-ledgers.json").toString]),
    ("cwd",toJson project.toString),("record",toJson (base/"positive-projection-ledgers2.guard.json").toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def prepareLedgerAuditor : IO Unit := do
  -- This only copies from the finished immutable product into a fresh
  -- directory; it does not wait for an independent auditor compilation.
  check ((← read (folder/"runtime.json")).getObjValD "sha256" == toJson (← hash (target/"StudyMain")))
    "checked immutable native parent required"
  let destination := base/"positive-projection-ledger-audit-source"
  materialize target destination (base/"positive-projection-ledger-audit-build")
    "tools.research.ConfirmedLedgerAudit" "positive-projection-ledger-audit-settings.json"
  IO.FS.writeFile (destination/"tools/research/ConfirmedLedgerAudit.lean")
    (← IO.FS.readFile (project/"tools/research/ConfirmedLedgerAudit.lean"))

def auditLedgerAuditor : IO Unit := do
  idle
  let guard ← read (base/"positive-projection-ledger-audit-build2.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "native ledger reader has not succeeded and drained"
  let build := base/"positive-projection-ledger-audit-build"
  let tool := (project/"tools/research/StudyBuildClosureAudit.lean").toString
  for args in [#["inspect",build.toString,(folder/"ledger-auditor-closure.json").toString],
    #["component-sources",target.toString,build.toString,(folder/"ledger-auditor-sources.json").toString,
      "Eggshell.DeliveryLedger","Eggshell.DB.PageMap","Eggshell.FileSystem","Eggshell.Blake3"]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool]++args)
  let gate ← read (folder/"ledger-auditor-sources.json")
  check (gate.getObjValD "commonSourcesUnchanged" == toJson true && gate.getObjValD "requiredModulesPresent" == toJson true)
    "ledger reader changed its native core"
  let native : String × Array (String × String) ← IO.ofExcept (fromJson? (← read (build/"tools_research_ConfirmedLedgerAudit.source")))
  check (native.1 == (← IO.FS.readFile (project/"tools/research/ConfirmedLedgerAudit.lean"))) "native ledger reader source differs"
  write (folder/"ledger-auditor-runtime.json") (Json.mkObj [("sha256",toJson (← hash (build/"StudyMain"))),
    ("guard",guard),("actualSourceMatches",toJson true),("adopted",toJson false)])

def collectLedgerAudit : IO Unit := do
  idle
  let guard ← read (base/"positive-projection-ledgers2.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "actual accepted-head inspection did not succeed and drain"
  let report ← read (folder/"confirmed-ledgers.json")
  check (report.getObjValD "allSixConfirmed" == toJson true && report.getObjValD "projectHeadUnchanged" == toJson true)
    "actual ACK heads are not all confirmed"
  write (folder/"confirmed-ledger-run.json") (Json.mkObj [("guard",guard),("reportSha256",toJson (← hash (folder/"confirmed-ledgers.json"))),
    ("readOnlyExactAcceptedHeads",toJson true),("adopted",toJson false)])
  let mut knowledge := #[]
  for item in ← IO.ofExcept (report.getObjValAs? (Array Json) "cells") do
    let session ← IO.ofExcept (item.getObjValAs? String "session")
    let topic ← IO.ofExcept (item.getObjValAs? Nat "topic")
    let repetition ← IO.ofExcept (item.getObjValAs? Nat "repetition")
    let cell := base/"positive-projection-cells2-result"/s!"topic-{topic}-chat-{repetition}"
    let stages ← IO.ofExcept ((← read (cell/"receipt.json")).getObjValAs? (Array Json) "stages")
    let some synaptic := stages.find? (fun row => row.getObjValD "name" == toJson "synaptic-delivery.json") |
      throw (IO.userError "actual source receipt missing")
    let files := base/"real-source-search-read-trial-result/data/sessions"/session
    let state ← read (files/"state.json")
    knowledge := knowledge.push (Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),
      ("unverifiedParts",((synaptic.getObjValD "record").getObjValD "data").getObjValD "unverifiedParts"),
      ("uncertainMarker",toJson (← (files/"unconfirmed-delivery").pathExists)),
      ("pendingOffers",toJson ((state.getObjValD "offers").getArr?.toOption.getD #[]).size),
      ("confirmedReferencePresent",toJson (state.getObjValD "confirmedDelivery" != Json.null))])
  write (folder/"knowledge-observation.json") (Json.mkObj [("cells",toJson knowledge),
    ("scope",toJson "ended SessionStart/UserPromptSubmit controls only; no Pre/Post/Stop or learned usage labels"),
    ("observedIncorrectUsageLabels",Json.null),
    ("remainingContractGap",toJson "positive evidence validation is distinct from complete knowledge of the presented body; preserve unknown coverage before enabling missing labels"),
    ("next",toJson "split trustworthy positive presentation from the complete-knowledge requirement for negative missing labels; uncertain parts must not invalidate verified positives or manufacture negatives"),
    ("liveSourceSha256",toJson (← hash (source/"Eggshell/SynapseLive.lean"))),
    ("journalSourceSha256",toJson (← hash (source/"Eggshell/SynapseJournal.lean"))),
    ("adopted",toJson false)])

def cleanup : IO Unit := do
  idle
  check ((← read (folder/"confirmed-ledger-run.json")).getObjValD "reportSha256" == toJson (← hash (folder/"confirmed-ledgers.json")))
    "retain the completed accepted-head audit first"
  let data := base/"real-source-search-read-trial-result/data"
  let records ← IO.ofExcept ((← read (folder/"confirmed-ledgers.json")).getObjValAs? (Array Json) "cells")
  check (records.size == 6) "all six owned ledger contexts required"
  let mut paths := #[]
  for record in records do
    let session ← IO.ofExcept (record.getObjValAs? String "session")
    let ledgerContext ← IO.ofExcept (record.getObjValAs? String "ledgerContext")
    check (session.startsWith "real-source-" && session.length == 76 && ledgerContext.length == 64 &&
      ledgerContext.toList.all (fun char => char.isDigit || ('a' ≤ char && char ≤ 'f'))) "ledger escaped generated session"
    paths := paths.push (data/"confirmed-delivery"/ledgerContext)
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (project/"tools/research/LocalBatchStudy.lean").toString,"cleanup-cells-for","positive-projection"]
  let helperRoots := #[base/"positive-projection-ledger-audit-build",base/"positive-projection-ledger-audit-source"]
  for entry in ← base.readDir do
    let response := entry.path/"runtime.rsp"
    if !helperRoots.contains entry.path && (← response.pathExists) then
      let body ← IO.FS.readFile response
      for root in helperRoots do check (!body.contains (root.toString++"/")) "another runtime depends on the ended reader"
  paths := paths++helperRoots++#[base/"positive-projection-controls-result",base/"positive-projection-controls-data",
    base/"positive-projection-acks-result",base/"positive-projection-acks-data"]
  let mut guards := #[]
  for name in ["runtime-build","auditor-build","controls","acks","install","cells","ledger-audit-build","ledgers"] do
    let tag := "positive-projection-"++name++"2"
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "candidate stage remains live or failed"
    guards := guards.push (tag,guard)
    for extension in ["stdout","stderr"] do paths := paths.push (base/(tag++"."++extension))
  let mut retained := #[]
  for name in ["support-presence-runtime-build/StudyMain","positive-projection-runtime-build/StudyMain",
      "positive-projection-auditor-build/StudyMain","real-source-search-read-trial-result/work.egg/head",
      "real-source-search-read-trial-result/work.egg/2a1ab5766ac89060c477ae3fc9683c9492574ff843d134c01b53d9697a27359e.pages"] do
    let path := base/name
    retained := retained.push (path,← hash path)
  let record := Json.mkObj [("guards",toJson guards),("paths",toJson (paths.map (·.toString))),
    ("retained",toJson (retained.map fun (path,sha) => (path.toString,sha))),
    ("projectCacheModelsAndComparisonBodiesRetained",toJson true),("archived",toJson false)]
  write (folder/"cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then discard <| command "/bin/rm" #["-rf","--",path.toString]
  for (path,sha) in retained do check ((← hash path) == sha) "current product or original changed during cleanup"
  write (folder/"cleanup.json") (record.setObjVal! "completed" (toJson true))

end PositiveProjectionStudy
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => PositiveProjectionStudy.prepare
  | ["setup",mode] => PositiveProjectionStudy.setup mode
  | ["audit-runtime"] => PositiveProjectionStudy.auditRuntime
  | ["audit-prepared"] => PositiveProjectionStudy.auditPrepared
  | ["record-eager-failure"] => PositiveProjectionStudy.recordEagerFailure
  | ["retire-eager"] => PositiveProjectionStudy.retireEager
  | ["prepare-auditor"] => PositiveProjectionStudy.prepareAuditor
  | ["audit-auditor"] => PositiveProjectionStudy.auditAuditor
  | ["prepare-delivery"] => PositiveProjectionStudy.prepareDelivery
  | ["seal-installed"] => PositiveProjectionStudy.sealInstalled
  | ["collect-controls"] => PositiveProjectionStudy.collectControls
  | ["setup-ledger-audit"] => PositiveProjectionStudy.setupLedgerAudit
  | ["prepare-ledger-auditor"] => PositiveProjectionStudy.prepareLedgerAuditor
  | ["audit-ledger-auditor"] => PositiveProjectionStudy.auditLedgerAuditor
  | ["collect-ledger-audit"] => PositiveProjectionStudy.collectLedgerAudit
  | ["cleanup"] => PositiveProjectionStudy.cleanup
  | _ => throw (IO.userError "positive-projection prepare/setup/audit-runtime required")
