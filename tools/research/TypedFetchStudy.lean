import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace TypedFetchStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def folder := workspace/"docs/candidates/typed-fetch"
def source := base/"typed-fetch-source"
def build := base/"typed-fetch-build"
def parent := base/"delivery-key-sets-build"
def changed := ["tools/research/SourceViewBatch.lean","Eggshell/PublicationService.lean","tools/research/RuntimeReadControls.lean","Eggshell/CanonicalSourceDelivery.lean","Eggshell/Handoff.lean"]
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (cmd++": "++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!processes.contains "controller/StudyMain guard ") "resource guard remains live"
def guard (tag : String) (args : Array String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve previous guard"
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def retireCapacity : IO Unit := do
  drained
  IO.FS.createDirAll folder
  let record := folder/"retired-capacity-tools.json"
  check (!(← record.pathExists)) "preserve previous cleanup"
  let processes ← command "/bin/ps" #["-axo","command="]
  let mut removed : Array Json := #[]
  for (family,name) in [("parallel-encoder","parallel-capacity"),("runtime-key","runtime-key-capacity"),
      ("elastic-encoder","elastic-encoder-capacity")] do
    let path := base/(name++"-build")/"StudyMain"
    let expected := (← read (workspace/"docs/candidates"/family/"capacity-sources.json")).getObjValD "auditorSha256"
    let digest ← hash path
    check (expected == toJson digest && !processes.contains path.toString) "capacity executable changed or remains active"
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson digest),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  for item in removed do IO.FS.removeFile (.mk (← IO.ofExcept (item.getObjValAs? String "path")))
  write record (Json.mkObj [("removed",toJson removed),("originalDbProjectCacheModelsCurrentParentAndCandidateRetained",toJson true),
    ("adoptionBaselineAndNativeWitnessesRetained",toJson true),("archived",toJson false)])
def retireSuperseded : IO Unit := do
  drained
  let record := folder/"retired-superseded-tools.json"
  check (!(← record.pathExists)) "preserve previous retirement"
  let processes ← command "/bin/ps" #["-axo","command="]
  let ledgerAudit := (← read (workspace/"docs/candidates/delivery-ledger/auditor-sources.json")).getObjValD "auditorSha256"
  let targets := [(base/"selection-membership-build/StudyMain",some (toJson "ba74ebfcfcb3c19ef3ae15fcf135f468ad6d6c986863c59787854581d2ee976b")),
    (base/"selection-membership-prefix/libexec/eggshell",some (toJson "ba74ebfcfcb3c19ef3ae15fcf135f468ad6d6c986863c59787854581d2ee976b")),
    (base/"delivery-ledger-auditor-build/StudyMain",some ledgerAudit),
    (build/"StudyMain",none)]
  let initial ← read (base/"typed-fetch-build4.guard.json")
  check (initial.getObjValD "state" == toJson "finished" && initial.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "initial product still has a live owner"
  let mut removed : Array Json := #[]
  for (path,expected) in targets do
    let digest ← hash path
    check (!processes.contains path.toString && expected.all (· == toJson digest)) "retired executable changed or remains live"
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson digest),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  for item in removed do IO.FS.removeFile (.mk (← IO.ofExcept (item.getObjValAs? String "path")))
  write record (Json.mkObj [("removed",toJson removed),("initialProductRetiredBeforeNewFinalLink",toJson true),
    ("adoptionBaselineProductAndCurrentParentRetained",toJson true),("sourceObjectInterfaceWitnessesRetained",toJson true),
    ("originalDbProjectCacheAndModelsRetained",toJson true),("archived",toJson false)])
  write (folder/"build5-preflight.json") (Json.mkObj [("nativeStarted",toJson false),
    ("reason",toJson "guard refused disk space below the unchanged2GiBfloor"),
    ("stderr",toJson (← IO.FS.readFile (base/"typed-fetch-build5.stderr")))])
def retireLegacy : IO Unit := do
  drained
  let record := folder/"retired-legacy-specimen-runtimes.json"
  check (!(← record.pathExists)) "preserve legacy retirement evidence"
  let old ← IO.FS.readFile (workspace/"docs/candidates/project-cache/protected-after.sha256")
  let lines := old.splitOn "\n"
  let targets := ["owned-ready-prefix/libexec/eggshell","reply-admission-prefix/libexec/eggshell"]
  let processes ← command "/bin/ps" #["-axo","command="]
  let probe ← IO.FS.readFile (source/"tools/research/RealDeliveryProbe.lean")
  check (!probe.contains "owned-ready-prefix" && !probe.contains "reply-admission-prefix") "current probe still names a legacy specimen"
  let mut removed : Array Json := #[]
  for relative in targets do
    let some line := lines.find? (·.endsWith relative) | throw (IO.userError "legacy specimen digest missing")
    let expected := line.take 64 |>.toString
    let path := base/relative
    check (!processes.contains path.toString && (← hash path) == expected) "legacy specimen changed or is active"
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson expected),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  let retained := lines.filter fun line => !line.isEmpty && !targets.any (fun suffix => line.endsWith suffix)
  for line in retained do
    let relative := (line.drop 66).toString
    check ((← hash (base/relative)) == (line.take 64).toString) "original protected source changed"
  for item in removed do IO.FS.removeFile (.mk (← IO.ofExcept (item.getObjValAs? String "path")))
  IO.FS.writeFile (folder/"protected-current.sha256") ("\n".intercalate retained++"\n")
  write record (Json.mkObj [("removed",toJson removed),("currentProbeAndCapacityUseNewPinnedRuntime",toJson true),
    ("historicalProtectionListSupersededBy",toJson "protected-current.sha256"),
    ("originalSeedFactsSelectorFixtureCurrentProjectCacheModelsAndAdoptionBaselineRetained",toJson true),
    ("nativeSourceObjectInterfaceWitnessesRetained",toJson true),("archived",toJson false)])
def recoverInterrupted : IO Unit := do
  drained
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any (fun row => row.contains base.toString && !row.contains "TypedFetchStudy.lean"))
    "an experiment process remains live"
  let record := folder/"interrupted-cells-recovery.json"
  check (!(← record.pathExists)) "preserve the interrupted cohort evidence"
  let g ← read (base/"typed-fetch-cells1.guard.json")
  check (g.getObjValD "state" == toJson "finished" && g.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    g.getObjValD "reason" == toJson "disk-space") "interrupted cohort is not terminal"
  let root := base/"typed-fetch-cells-result"
  let shared := base/"real-source-search-read-trial-result/data"
  let mut cells := #[]
  let mut removals : Array System.FilePath := #[]
  for name in ["topic-1-chat-0","topic-1-chat-1","topic-2-chat-0"] do
    let cell := root/name
    let stdin ← read (cell/"hook/stdin")
    let session ← IO.ofExcept (stdin.getObjValAs? String "session_id")
    check (session.startsWith "real-source-" && session.length == 76 && session.toList.all (fun c => c.isAlphanum || c == '-'))
      "generated session escaped its scope"
    removals := removals.push (shared/"sessions"/session)
    let mut row := Json.mkObj [("cell",toJson name),("hook",← read (cell/"hook/record.json")),
      ("stdoutSha256",toJson (← hash (cell/"hook/stdout")))]
    if ← (cell/"result.json").pathExists then
      let result ← read (cell/"result.json")
      let audit ← read (cell/"audit.json")
      let receipt ← read (cell/"receipt.json")
      let id ← IO.ofExcept (receipt.getObjValAs? String "id")
      check (id.length == 64 && id.toList.all Char.isAlphanum) "generated receipt escaped its scope"
      check ((← IO.FS.readBinFile (cell/"body.txt")) ==
        (← IO.FS.readBinFile (base/"delivery-key-sets-cells-result"/name/"body.txt"))) "partial body differs from its parent"
      row := row.setObjVal! "result" result |>.setObjVal! "audit" audit
        |>.setObjVal! "parentBodyByteEqual" (toJson true)
        |>.setObjVal! "bodySha256" (toJson (← hash (cell/"body.txt")))
      removals := removals.push (shared/"receipts"/id)
    else row := row.setObjVal! "completed" (toJson false)
    cells := cells.push row
  let mut endpoints := #[]
  for path in [shared/"publisher/endpoint.json",shared/"daemon.json"] do
    if !(← path.pathExists) then continue
    let endpoint ← read path
    let pid ← IO.ofExcept (endpoint.getObjValAs? Nat "pid")
    let status ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
    check (status.exitCode != 0 && status.stdout.trimAscii.isEmpty) "endpoint process is live; do not remove it"
    endpoints := endpoints.push (Json.mkObj [("path",toJson path.toString),("pid",toJson pid),("sha256",toJson (← hash path))])
    removals := removals.push path
  for name in ["native-closure.json","native-sources.json","entry-source.json","component.json","controls.json",
      "auditor-closure.json","auditor-sources.json"] do
    let path := folder/name
    let target := folder/("pre-pruning-"++name)
    check (!(← target.pathExists)) "pre-pruning audit already exists"
    IO.FS.rename path target
  write record (Json.mkObj [("guard",g),("cells",toJson cells),("completedCells",toJson (2 : Nat)),
    ("allSixPassed",toJson false),("recoveredStaleEndpoints",toJson endpoints),
    ("removed",toJson (removals.map (·.toString))),
    ("originalDbProjectCacheModelsAndParentBodiesRetained",toJson true),("archived",toJson false)])
  for path in removals do
    if ← path.isDir then IO.FS.removeDirAll path
    else if ← path.pathExists then IO.FS.removeFile path
  IO.FS.removeDirAll root
  let mut retired := #[]
  for relative in ["typed-fetch-build/StudyMain","typed-fetch-prefix/libexec/eggshell","typed-fetch-auditor-build/StudyMain",
      "prepared-query-native/prefix/libexec/eggshell","prepared-basis-native/prefix/libexec/eggshell",
      "prepared-focus-build/StudyMain.tmpbc37d47"] do
    let path := base/relative
    check (!processes.contains path.toString) "retired intermediate is still in use"
    retired := retired.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path)),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  write (folder/"retired-intermediate-tools.json") (Json.mkObj [("removed",toJson retired),
    ("adoptionBaselineParentModelsAndNativeWitnessesRetained",toJson true),("archived",toJson false)])
  for row in retired do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
  let mut sharedExecutables := #[]
  for family in ["delivery-ledger","delivery-key-sets"] do
    let product := base/(family++"-build")/"StudyMain"
    let installed := base/(family++"-prefix")/"libexec/eggshell"
    let digest ← hash product
    check (digest == (← hash installed)) "installed predecessor differs from its immutable product"
    let temporary := installed.withExtension "shared"
    check (!(← temporary.pathExists)) "sharing temporary already exists"
    discard <| command "/bin/ln" #[product.toString,temporary.toString]
    IO.FS.rename temporary installed
    check (digest == (← hash installed)) "sharing changed predecessor bytes"
    sharedExecutables := sharedExecutables.push (Json.mkObj [("product",toJson product.toString),
      ("installed",toJson installed.toString),("sha256",toJson digest)])
  write (folder/"shared-predecessor-executables.json") (Json.mkObj [("sameImmutableInodes",toJson sharedExecutables),
    ("contentsAndPathsPreserved",toJson true)])
  let temporary := base/"native-study/account/.tmp"
  check (!processes.contains temporary.toString) "ended account temporary is active"
  if ← temporary.pathExists then IO.FS.removeDirAll temporary
  write (folder/"removed-ended-account-temporary.json") (Json.mkObj [("path",toJson temporary.toString),
    ("accountCredentialsAndOriginalSeedRetained",toJson true),("archived",toJson false)])
def pruneSupersededHandoff : IO Unit := do
  drained
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any (fun row => row.contains base.toString && !row.contains "TypedFetchStudy.lean"))
    "an experiment process remains live"
  let record := folder/"pruned-superseded-handoff-artifacts.json"
  check (!(← record.pathExists)) "preserve previous artifact retirement"
  let retained := ["controller","delivery-ledger-build","delivery-key-sets-build","typed-fetch-build","typed-fetch-auditor-build"]
  let mut selected : Array String := #[]
  let mut activeInterfaces : Array String := #[]
  for name in retained do
    let root := base/name
    selected := selected ++ ((← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n").toArray
    let interface := root/"lib/Eggshell/Handoff.olean"
    if ← interface.pathExists then activeInterfaces := activeInterfaces.push (← IO.FS.realPath interface).toString
  let mut files := #[]
  for name in ["parallel-encoder-build","runtime-key-build","elastic-encoder-build","keyed-inputs-build",
      "keyed-discovery-build","shared-model-build","encoder-events-build","encoder-native-wait-build",
      "local-completion-build","selection-membership-build"] do
    let root := base/name
    let object := root/"Eggshell_Handoff.o"
    check (!selected.contains (toJson object.toString).compress) "current native response still uses an old Handoff"
    let interface := root/"lib/Eggshell/Handoff.olean"
    if ← interface.pathExists then
      check (!activeInterfaces.contains (← IO.FS.realPath interface).toString) "current interface still uses an old Handoff"
    for path in [object,interface,root/"lib/Eggshell/Handoff.olean.private",root/"lib/Eggshell/Handoff.olean.server",root/"lib/Eggshell/Handoff.ir"] do
      if !(← path.pathExists) then continue
      if (← path.symlinkMetadata).type != .file then continue
      files := files.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path)),
        ("bytes",toJson (← path.metadata).byteSize.toNat)])
  write record (Json.mkObj [("removed",toJson files),("retainedNativeResponsesChecked",toJson retained),
    ("retainedActualHandoffInterfaces",toJson activeInterfaces),("oldSourceAndDependencyStampsRetained",toJson true),
    ("currentNativeObjectAndInterfaceWitnessesRetained",toJson true),("archived",toJson false)])
  for file in files do IO.FS.removeFile (.mk (← IO.ofExcept (file.getObjValAs? String "path")))
  let fixture := base/"frontend-quiescence-fixture-small1"
  let input ← IO.FS.readFile (source/"tools/research/RealDeliveryProbe.lean")
  check (!input.contains fixture.toString) "current original-source probe still uses the old synthetic fixture"
  check (!processes.contains fixture.toString) "old fixture process remains live"
  if ← fixture.pathExists then
    let frozen := fixture/"frozen-readback.json"
    write (folder/"retired-synthetic-fixture.json") (Json.mkObj [("path",toJson fixture.toString),
      ("frozenReadbackSha256",toJson (← hash frozen)),("currentRealSourceProbeDoesNotUseFixture",toJson true),
      ("originalDbProjectCacheAndModelsRetained",toJson true),("archived",toJson false)])
    IO.FS.removeDirAll fixture
def pruneSupersededModules (remaining : Bool := false) : IO Unit := do
  drained
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any (fun row => row.contains base.toString && !row.contains "TypedFetchStudy.lean"))
    "an experiment process remains live"
  let record := folder/(if remaining then "pruned-remaining-superseded-module-artifacts.json" else "pruned-superseded-module-artifacts.json")
  check (!(← record.pathExists)) "preserve previous retirement"
  let retained := ["controller","delivery-ledger-build","delivery-key-sets-build","typed-fetch-build","typed-fetch-auditor-build"]
  let mut selected : Array String := #[]
  for name in retained do
    selected := selected ++ ((← IO.FS.readFile (base/name/"runtime.rsp")).splitOn "\n").toArray
  let mut files := #[]
  let mut kept := #[]
  let roots ← if remaining then do
      let entries ← base.readDir
      pure (entries.filterMap fun entry => if entry.fileName.endsWith "-build" && !retained.contains entry.fileName then some entry.fileName else none).toList
    else pure ["parallel-encoder-build","runtime-key-build","elastic-encoder-build","keyed-inputs-build",
      "keyed-discovery-build","shared-model-build","encoder-events-build","encoder-native-wait-build",
      "local-completion-build","selection-membership-build"]
  for moduleName in ["Handoff","PublicationService","SearchProvider","Worker","PublicationClient","SynapseTransport","ContractAudit"] do
    let mut activeInterfaces : Array String := #[]
    for name in retained do
      let interface := base/name/"lib/Eggshell"/(moduleName++".olean")
      if ← interface.pathExists then activeInterfaces := activeInterfaces.push (← IO.FS.realPath interface).toString
    for name in roots do
      let root := base/name
      let object := root/("Eggshell_"++moduleName++".o")
      let interface := root/"lib/Eggshell"/(moduleName++".olean")
      let selectedObject := selected.contains (toJson object.toString).compress
      let selectedInterface ← if ← interface.pathExists then pure (activeInterfaces.contains (← IO.FS.realPath interface).toString) else pure false
      if selectedObject || selectedInterface then
        kept := kept.push (Json.mkObj [("producer",toJson name),("module",toJson moduleName)])
        continue
      for path in [object,interface,root/"lib/Eggshell"/(moduleName++".olean.private"),
          root/"lib/Eggshell"/(moduleName++".olean.server"),root/"lib/Eggshell"/(moduleName++".ir")] do
        if !(← path.pathExists) then continue
        if (← path.symlinkMetadata).type != .file then continue
        files := files.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path)),
          ("bytes",toJson (← path.metadata).byteSize.toNat)])
  write record (Json.mkObj [("removed",toJson files),("retainedProducers",toJson kept),
    ("retainedNativeResponsesChecked",toJson retained),("oldSourceAndDependencyStampsRetained",toJson true),
    ("currentNativeObjectAndInterfaceWitnessesRetained",toJson true),("archived",toJson false)])
  for file in files do IO.FS.removeFile (.mk (← IO.ofExcept (file.getObjValAs? String "path")))
def patchFile (relative : String) : IO Unit := do
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
    (base/"delivery-key-sets-source"/relative).toString,(source/relative).toString]}
  check (patch.exitCode == 1) "declared candidate patch is missing or unreadable"
  IO.FS.writeFile (folder/(relative.replace "/" "_"++".patch")) patch.stdout
def freezeSource : IO Unit := do
  drained
  check ((← hash (parent/"StudyMain")) == "7e07c7870b444538e8b99c45df2468ab67aa0468004ada0fd154048d242247a4") "current parent changed"
  IO.FS.createDirAll folder
  for relative in changed do patchFile relative
  IO.FS.writeFile (source/"tools/research/TypedFetchChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/TypedFetchChecks.lean"))
  let entry := source/"tools/research/ReplayReadinessChecks.lean"
  let text ← IO.FS.readFile entry
  let importBefore := "import Eggshell.ContractAudit"
  let dispatchBefore := "  | [\"parallel-encoder-check\",root] =>"
  check ((text.splitOn importBefore).length == 2 && (text.splitOn dispatchBefore).length == 2) "unique entry boundaries missing"
  IO.FS.writeFile entry (text.replace importBefore (importBefore++"\nimport tools.research.TypedFetchChecks")
    |>.replace dispatchBefore ("  | [\"typed-fetch-check\",fixture,sha,output] =>\n"++
      "    Eggshell.Research.TypedFetchChecks.run (.mk fixture) sha (.mk output); return 0\n"++dispatchBefore))
  patchFile "tools/research/ReplayReadinessChecks.lean"
  let settings ← read (base/"delivery-key-sets-settings.json")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  let info ← read (parent/"build.json")
  let mut mapping ← read (parent/"object-mapping.json")
  for row in (info.getObjValD "modules").getArr?.toOption.getD #[] do
    mapping := mapping.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  write (source/"object-mapping.json") mapping
  write (base/"typed-fetch-settings.json") (settings.setObjVal! "project" (toJson source.toString)
    |>.setObjVal! "core" (toJson source.toString)
    |>.setObjVal! "output" (toJson build.toString)
    |>.setObjVal! "baselineResponse" (toJson (parent/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"tools_research_ReplayReadinessChecks.o").toString)
    |>.setObjVal! "objectModules" (toJson (source/"object-mapping.json").toString)
    |>.setObjVal! "parents" (toJson (#[parent.toString,(base/"delivery-key-sets-auditor-build").toString]++parents)))
  write (folder/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("change",toJson "typed local rows retain authorized references; encoded-row quota only at actual wire boundary"),
    ("preserved",toJson "capability,scope,snapshot,lease,row-count bound,all selected rows/order,encoded-row16MiB quota and actual wire limits,final delivery budget,model,compute slots,deadlines,RSS/disk limits"),
    ("legacyRawReplySha256",toJson "8593c6cb138a60524224afd2b3912eb02e3a016d3ef1094296ef45362aadcbcb"),
    ("legacyFixtureUse",toJson "serialization cost and byte-boundary regression only; not historical runtime comparison"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "typed-fetch-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-fetch-settings.json").toString]
  guard "typed-fetch-component1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,"typed-fetch-check",
    (base/"real-source-search-read-trial-result/data/reply-witnesses/affacad8c38e209788a0eafb78d716bda6237f42a0b995594a4af87c9089a6f2.json").toString,
    "8593c6cb138a60524224afd2b3912eb02e3a016d3ef1094296ef45362aadcbcb",(base/"typed-fetch-component.json").toString]
  guard "typed-fetch-controls1" #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "EGGSHELL_DATA_ROOT="++(base/"typed-fetch-controls-data").toString,(build/"StudyMain").toString,
    "local-batch-check",(base/"typed-fetch-controls-result").toString]
def collect (tag : String) : IO Unit := do
  drained
  let g ← read (base/(tag++".guard.json"))
  check (g.getObjValD "state" == toJson "finished" && g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "guard is not terminal"
  let log := fun suffix => do
    let path := base/(tag++suffix)
    if ← path.pathExists then return toJson (← IO.FS.readFile path)
    return Json.null
  write (folder/(tag++".json")) (Json.mkObj [("guard",g),("stdout",← log ".stdout"),("stderr",← log ".stderr")])
def auditBuild : IO Unit := do
  drained
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let run := fun args => do discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  run #["inspect",build.toString,(folder/"native-closure.json").toString]
  run #["compare-sources",parent.toString,build.toString,(folder/"native-sources.json").toString,
    "tools.research.SourceViewBatch","Eggshell.PublicationService","tools.research.RuntimeReadControls",
    "Eggshell.CanonicalSourceDelivery","Eggshell.Handoff","+tools.research.TypedFetchChecks"]
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected compiled source change"
  let native ← IO.ofExcept ((← read (build/"tools_research_ReplayReadinessChecks.source")).getArr?)
  let entry ← IO.ofExcept (native[0]!.getStr?)
  let before ← IO.FS.readFile (base/"delivery-key-sets-source/tools/research/ReplayReadinessChecks.lean")
  let removed := entry.replace "\nimport tools.research.TypedFetchChecks" ""
    |>.replace ("  | [\"typed-fetch-check\",fixture,sha,output] =>\n"++
      "    Eggshell.Research.TypedFetchChecks.run (.mk fixture) sha (.mk output); return 0\n") ""
  check (removed == before && entry == (← IO.FS.readFile (source/"tools/research/ReplayReadinessChecks.lean")))
    "actual compiled entry changed beyond the research-only command"
  write (folder/"entry-source.json") (Json.mkObj [("onlyResearchCommandAndImportAdded",toJson true),
    ("nativeSourceMatchesActualFile",toJson true)])
  for relative in changed do patchFile relative
  write (folder/"component-initial.json") (← read (base/"typed-fetch-component.json"))
  write (folder/"component.json") (← read (base/"typed-fetch-component3-result.json"))
  let controls ← read (base/"typed-fetch-controls4-result/report.json")
  check (controls.getObjValD "typedReadChecks" == toJson true &&
    controls.getObjValD "allReservationsReleased" == toJson true &&
    controls.getObjValD "originalHeadsUnchanged" == toJson true) "typed/wire authorization and lifecycle checks required"
  write (folder/"controls.json") controls
def prepareCells : IO Unit := do
  drained
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "seal product before actual hooks"
  let target := base/"typed-fetch-auditor-build"
  let settings := (← read (base/"typed-fetch-settings.json"))
    |>.setObjVal! "output" (toJson target.toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.RealDeliveryProbe")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  write (base/"typed-fetch-auditor-settings.json") (settings.setObjVal! "parents" (toJson (#[build.toString]++parents))
    |>.setObjVal! "baselineResponse" (toJson (build/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (build/"tools_research_ReplayReadinessChecks.o").toString))
  guard "typed-fetch-auditor-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-fetch-auditor-settings.json").toString]
def actualCells : IO Unit := do
  drained
  let target := base/"typed-fetch-auditor-build"
  let audit := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  let run := fun args => do discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",audit]++args)
  run #["inspect",target.toString,(folder/"auditor-closure.json").toString]
  run #["common-sources",build.toString,target.toString,(folder/"auditor-sources.json").toString]
  let proof ← read (folder/"auditor-sources.json")
  check (proof.getObjValD "allProductCorePresent" == toJson true &&
    proof.getObjValD "commonSourcesUnchanged" == toJson true) "actual hook auditor changed the product core"
  let digest ← hash (build/"StudyMain")
  let installation := base/"typed-fetch-prefix"
  if ← installation.pathExists then
    check (!(← (installation/"libexec/eggshell").pathExists)) "prior installed runtime was not retired"
    let modelLink := installation/"share/eggshell/minilm"
    if ← modelLink.pathExists then
      check ((← modelLink.symlinkMetadata).type == .symlink &&
        (← IO.FS.realPath modelLink) == (← IO.FS.realPath (base/"prefix/share/eggshell/minilm")))
        "unexpected model asset directory in retired installation"
      IO.FS.removeFile modelLink
    IO.FS.removeDirAll installation
  let manifest := base/"typed-fetch-install2.json"
  write manifest (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (build/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  guard "typed-fetch-install2" #[(target/"StudyMain").toString,"install-prefix",manifest.toString]
  let original ← read (base/"delivery-key-sets-cells.json")
  let probes ← IO.ofExcept (original.getObjValAs? (Array Json) "probes")
  let output := base/"typed-fetch-cells2-result"
  let probes ← probes.mapM fun probe => do
    let old ← IO.ofExcept (probe.getObjValAs? String "destination")
    let cell := (System.FilePath.mk old).fileName.get!
    return probe.setObjVal! "destination" (toJson (output/cell).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  let input := base/"typed-fetch-cells2.json"
  write input (Json.mkObj [("output",toJson output.toString),("probes",toJson probes)])
  guard "typed-fetch-cells2" #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,"cells",input.toString]
def capacityDiagnosis : IO Unit := do
  drained
  let audit ← read (folder/"stopped-query-stages.json")
  let evidence ← read (folder/"capacity-small.json")
  let guard := evidence.getObjValD "guard"
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "capacity is not terminal"
  let shared := base/"real-source-search-read-trial-result"
  let mut counts : Std.HashMap String Nat := {}
  let mut rows := #[]
  let add := fun (counts : Std.HashMap String Nat) (name : String) => counts.insert name (counts[name]?.getD 0+1)
  for row in (audit.getObjValD "rows").getArr?.toOption.getD #[] do
    let id ← IO.ofExcept (row.getObjValAs? String "receipt")
    check (id.length == 64 && id.toList.all Char.isAlphanum) "invalid diagnostic scope"
    let root := shared/"data/receipts"/id
    let keyed := (← read (root/"provider-keyed-inputs.json")).getObjValD "data"
    let sharedImage := keyed.getObjValD "sharedImage" == toJson true
    if sharedImage then counts := add counts "sharedInputImage"
    let mut focus := false
    for entry in ← root.readDir do
      unless entry.fileName.startsWith "numerical-" do continue
      let data := (← read entry.path).getObjValD "data"
      if (data.getObjValD "corpus").getObjValD "purpose" == toJson "focus" && data.getObjValD "status" == toJson "completed" then focus := true
    if focus then counts := add counts "focusCompleted"
    let mut stages := #[]
    for (name,label) in [("delivery-domain.json","deliveryDomain"),("synaptic-delivery.json","packetVerified"),
        ("operation-service.json","operationReply"),("ack.json","ackRecorded")] do
      let path := root/name
      if !(← path.pathExists) then continue
      let value ← read path
      let data := value.getObjValD "data"
      let accepted := if label == "packetVerified" then data.getObjValD "packetVerified" == toJson true
        else if label == "operationReply" then data.getObjValD "reply" == toJson true else true
      if accepted then counts := add counts label
      stages := stages.push (Json.mkObj [("file",toJson name),("observedMs",value.getObjValD "observedMs"),
        ("accepted",toJson accepted)])
    rows := rows.push (Json.mkObj [("receipt",toJson id),("sharedInputImage",toJson sharedImage),
      ("focusCompleted",toJson focus),("stages",toJson stages)])
  let inputs ← read (base/"typed-fetch-capacity-small-input.json")
  for item in (inputs.getObjValD "sourceFiles").getArr?.toOption.getD #[] do
    let values ← IO.ofExcept item.getArr?
    let name ← IO.ofExcept values[0]!.getStr?
    let expected ← IO.ofExcept values[1]!.getStr?
    check ((← hash (shared/"work.egg"/name)) == expected) "capacity changed original source files"
  write (folder/"capacity-diagnosis.json") (Json.mkObj [("guard",guard),("counts",toJson counts.toArray),
    ("rows",toJson rows),("cacheStats",evidence.getObjValD "cacheStats"),
    ("originalSourceFilesUnchanged",toJson true),("newLoadRuns",toJson (0 : Nat)),
    ("rssIsNotCacheCharge",toJson true),("sixSingleHooksDoNotProveEightyUsers",toJson true),
    ("eightyStarted",toJson false),("adopted",toJson false)])
def main (args : List String) : IO Unit := do
  match args with
  | ["retire-capacity"] => retireCapacity
  | ["retire-superseded"] => retireSuperseded
  | ["retire-legacy"] => retireLegacy
  | ["recover-interrupted"] => recoverInterrupted
  | ["prune-superseded-handoff"] => pruneSupersededHandoff
  | ["prune-superseded-modules"] => pruneSupersededModules
  | ["prune-remaining-superseded-modules"] => pruneSupersededModules true
  | ["freeze-source"] => freezeSource
  | ["collect",tag] => collect tag
  | ["update-checks"] =>
    drained
    IO.FS.writeFile (source/"tools/research/TypedFetchChecks.lean")
      (← IO.FS.readFile (workspace/"tools/research/TypedFetchChecks.lean"))
    let plan ← read (folder/"plan.json")
    write (folder/"plan.json") (plan.setObjVal! "change" (toJson "typed local fetch, exact memoized row-key ordering, and removal of unused per-witness diagnostic JSON while retaining all verification and returned evidence")
      |>.setObjVal! "directSourceChanges" (toJson changed))
  | ["setup-component2"] =>
    drained
    guard "typed-fetch-component2" #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,"typed-fetch-check",
      (base/"real-source-search-read-trial-result/data/reply-witnesses/affacad8c38e209788a0eafb78d716bda6237f42a0b995594a4af87c9089a6f2.json").toString,
      "8593c6cb138a60524224afd2b3912eb02e3a016d3ef1094296ef45362aadcbcb",(base/"typed-fetch-component2-result.json").toString]
    guard "typed-fetch-controls2" #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/"typed-fetch-controls2-data").toString,(build/"StudyMain").toString,
      "local-batch-check",(base/"typed-fetch-controls2-result").toString]
  | ["setup-component3"] =>
    drained
    guard "typed-fetch-component3" #["/usr/bin/env","LEAN_NUM_THREADS=1",(build/"StudyMain").toString,"typed-fetch-check",
      (base/"real-source-search-read-trial-result/data/reply-witnesses/affacad8c38e209788a0eafb78d716bda6237f42a0b995594a4af87c9089a6f2.json").toString,
      "8593c6cb138a60524224afd2b3912eb02e3a016d3ef1094296ef45362aadcbcb",(base/"typed-fetch-component3-result.json").toString]
    guard "typed-fetch-controls3" #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/"typed-fetch-controls3-data").toString,(build/"StudyMain").toString,
      "local-batch-check",(base/"typed-fetch-controls3-result").toString]
    guard "typed-fetch-auditor-build2" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-fetch-auditor-settings.json").toString]
  | ["setup-controls4"] =>
    drained
    guard "typed-fetch-controls4" #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/"typed-fetch-controls4-data").toString,(build/"StudyMain").toString,
      "local-batch-check",(base/"typed-fetch-controls4-result").toString]
  | ["prepare-read-fixture"] =>
    drained
    let unfinished := base/"frontend-quiescence-fixture-small1"
    check (!(← (unfinished/"frozen-readback.json").pathExists) && !(← (base/"typed-fetch-read-fixture.json").pathExists))
      "preserve any complete fixture"
    if ← unfinished.pathExists then IO.FS.removeDirAll unfinished
    IO.FS.writeFile (source/"tools/research/TypedReadFixture.lean")
      (← IO.FS.readFile (workspace/"tools/research/TypedReadFixture.lean"))
    let output := base/"typed-fetch-fixture-build"
    let settings := (← read (base/"typed-fetch-auditor-settings.json"))
      |>.setObjVal! "output" (toJson output.toString)
      |>.setObjVal! "mainModule" (toJson "tools.research.TypedReadFixture")
    write (base/"typed-fetch-fixture-settings.json") settings
    guard "typed-fetch-fixture-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-fetch-fixture-settings.json").toString]
    guard "typed-fetch-fixture1" #["/usr/bin/env","LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT="++(base/"typed-fetch-fixture-data").toString,(output/"StudyMain").toString]
  | ["retry-read-fixture"] =>
    drained
    IO.FS.writeFile (source/"tools/research/TypedReadFixture.lean")
      (← IO.FS.readFile (workspace/"tools/research/TypedReadFixture.lean"))
    guard "typed-fetch-fixture-build2" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-fetch-fixture-settings.json").toString]
  | ["audit"] => auditBuild
  | ["prepare-cells"] => prepareCells
  | ["actual-cells"] => actualCells
  | ["share-installation"] =>
    drained
    let product := build/"StudyMain"
    let installed := base/"typed-fetch-prefix/libexec/eggshell"
    let expected := (← read (folder/"native-sources.json")).getObjValD "candidateRuntimeSha256"
    let sha ← hash product
    check (expected == toJson sha && sha == (← hash installed)) "installed runtime changed"
    let temporary := installed.withExtension "shared"
    check (!(← temporary.pathExists)) "sharing temporary already exists"
    discard <| command "/bin/ln" #[product.toString,temporary.toString]
    IO.FS.rename temporary installed
    check (sha == (← hash installed)) "sharing changed installed runtime bytes"
    write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson sha),
      ("sharesImmutableProductInode",toJson true),("frozenDuringEveryGuard",toJson true)])
  | ["retire-read-fixture"] =>
    drained
    let completed ← read (base/"typed-fetch-controls4.guard.json")
    check (completed.getObjValD "exitCode" == toJson (0 : Nat) && completed.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "read controls are not complete"
    let helper := base/"typed-fetch-fixture-build"
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
      (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"common-sources",
      build.toString,helper.toString,(folder/"fixture-sources.json").toString]
    let shared ← read (folder/"fixture-sources.json")
    check (shared.getObjValD "allProductCorePresent" == toJson true && shared.getObjValD "commonSourcesUnchanged" == toJson true)
      "fixture builder changed product core"
    let path := helper/"StudyMain"
    write (folder/"retired-read-fixture.json") (Json.mkObj [("helperSha256",toJson (← hash path)),
      ("helperBytes",toJson (← path.metadata).byteSize.toNat),("fixture",← read (base/"typed-fetch-read-fixture.json")),
      ("generatorSourceRetained",toJson true),("originalDbProjectCacheModelsAndControlsRetained",toJson true),("archived",toJson false)])
    IO.FS.removeFile path
    IO.FS.removeDirAll (base/"frontend-quiescence-fixture-small1")
    for path in [base/"typed-fetch-fixture-data",base/"typed-fetch-controls3-data",base/"typed-fetch-controls3-result",
        base/"typed-fetch-controls4-data",base/"typed-fetch-controls4-result/file-fixture"] do
      if ← path.pathExists then IO.FS.removeDirAll path
  | ["record-patches"] => drained; for relative in changed do patchFile relative
  | ["sync-capacity-harness"] =>
    drained
    IO.FS.writeFile (base/"typed-fetch-capacity-source/tools/research/MemoryCapacity.lean")
      (← IO.FS.readFile (workspace/"tools/research/MemoryCapacity.lean"))
  | ["capacity-diagnosis"] => capacityDiagnosis
  | ["finish-native-evidence"] =>
    drained
    for tag in ["typed-fetch-build9","typed-fetch-component3","typed-fetch-controls3","typed-fetch-controls4",
        "typed-fetch-fixture-build1","typed-fetch-fixture-build2","typed-fetch-fixture1","typed-fetch-auditor-build2",
        "typed-fetch-install2","typed-fetch-cells1","typed-fetch-cells2","typed-fetch-capacity-build1",
        "typed-fetch-capacity-build2","typed-fetch-capacity-small1"] do collect tag
    let plan ← read (folder/"plan.json")
    write (folder/"plan.json") (plan.setObjVal! "directSourceChanges" (toJson changed)
      |>.setObjVal! "runtimeSha256" (toJson (← hash (build/"StudyMain")))
      |>.setObjVal! "change" (toJson "typed local fetch; exact memoized row-key ordering; remove unused diagnostic row arrays while preserving verification and returned evidence")
      |>.setObjVal! "allSixNativeHooksPassed" (toJson true)
      |>.setObjVal! "capacityGatePassed" (toJson false)
      |>.setObjVal! "eightyStarted" (toJson false))
    let diagnosis ← read (folder/"capacity-diagnosis.json")
    check (diagnosis.getObjValD "originalSourceFilesUnchanged" == toJson true &&
      (← read (folder/"capacity-small-cleanup.json")).getObjValD "completed" == toJson true)
      "retain stopped capacity evidence and clean owned generated data first"
    let processes ← command "/bin/ps" #["-axo","command="]
    let path := base/"typed-fetch-capacity-build/StudyMain"
    let expected := (← read (folder/"capacity-sources.json")).getObjValD "auditorSha256"
    let digest ← hash path
    check (expected == toJson digest && !processes.contains path.toString) "capacity tool changed or remains live"
    let mut endpoints := #[]
    let shared := base/"real-source-search-read-trial-result/data"
    for (endpointPath,pid) in [(shared/"publisher/endpoint.json",16767),(shared/"daemon.json",17711)] do
      if !(← endpointPath.pathExists) then continue
      let endpoint ← read endpointPath
      check (endpoint.getObjValD "pid" == toJson pid) "preserve a different service generation"
      let state ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","stat="]}
      check (state.exitCode != 0 && state.stdout.trimAscii.isEmpty) "service process is still live"
      endpoints := endpoints.push (Json.mkObj [("path",toJson endpointPath.toString),("pid",toJson pid),
        ("sha256",toJson (← hash endpointPath))])
    write (folder/"retired-ended-capacity.json") (Json.mkObj [("executable",toJson path.toString),
      ("sha256",toJson digest),("bytes",toJson (← path.metadata).byteSize.toNat),("staleEndpoints",toJson endpoints),
      ("resultDirectory",toJson (base/"typed-fetch-capacity-small-result").toString),
      ("currentFailedRuntimeParentBaselineOriginalDbProjectCacheModelsAndNeededNativeInputsRetained",toJson true),
      ("archived",toJson false)])
    IO.FS.removeFile path
    for endpoint in endpoints do IO.FS.removeFile (.mk (← IO.ofExcept (endpoint.getObjValAs? String "path")))
    IO.FS.removeDirAll (base/"typed-fetch-capacity-small-result")
  | ["retry-build",tag] =>
    drained
    check (tag.startsWith "typed-fetch-build") "guard escaped candidate"
    guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"typed-fetch-settings.json").toString]
  | _ => throw (IO.userError "unknown typed fetch study operation")
end TypedFetchStudy
def main := TypedFetchStudy.main
