module

public import Eggshell.Install
public import Eggshell.SearchProvider
import Eggshell.ContractAudit
public import tests.PageDBTests
public import tests.SourceEvidenceTests

@[expose] public section

open Eggshell Eggshell.Plugin Eggshell.TestOracle

def check (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

/-- Wait for the independent writer only in deterministic state fixtures. -/
def runHookFixture (input : Lean.Json) : IO String := do
  -- The native entrypoint captures a terminal receipt before dispatch. Keep
  -- this direct-dispatch fixture on that same durable provenance boundary.
  captureTerminal input
  let output ← dispatchHook input
  if let some session := optionalString input "session_id" then
    acknowledge session "direct"
    flushDeferred session ((← IO.monoMsNow) + 3000)
    flushIndexes session ((← IO.monoMsNow) + 3000)
  pure output

def accessMode (path : System.FilePath) : IO String := do
  let bsd ← IO.Process.output { cmd := "stat", args := #["-f", "%Lp", path.toString] }
  if bsd.exitCode == 0 then pure bsd.stdout.trimAscii.copy
  else
    let gnu ← IO.Process.output { cmd := "stat", args := #["-c", "%a", path.toString] }
    if gnu.exitCode == 0 then pure gnu.stdout.trimAscii.copy
    else throw (IO.userError s!"cannot inspect access mode for {path}")

def testRoot : System.FilePath := ".lake" / "eggshell-tests"
def testEgg : System.FilePath := testRoot / "work.egg"
def operationBoundaryEgg : System.FilePath := testRoot / "operation-boundary.egg"
def concurrentEgg : System.FilePath := testRoot / "concurrent.egg"
def unionEgg : System.FilePath := testRoot / "union.egg"
def semanticEgg : System.FilePath := testRoot / "semantic.egg"
def naturalLanguageEgg : System.FilePath := testRoot / "natural-language.egg"
def dagEgg : System.FilePath := testRoot / "dag.egg"
def transportEgg : System.FilePath := testRoot / "transport.egg"

def hookTestRoot : IO System.FilePath := do
  pure (((← IO.currentDir) / testRoot / "hook-e2e").normalize)

def prepareTestProject (root : System.FilePath) : IO Unit := do
  if ← root.pathExists then IO.FS.removeDirAll root
  IO.FS.createDirAll root
  IO.FS.writeFile (root / ".eggshell.toml") r#"default = "work"

[eggs]
project = "work.egg"

[profiles.work]
read = ["project"]
write = "project"
"#

def clean : IO Unit := do
  if ← testRoot.pathExists then IO.FS.removeDirAll testRoot
  IO.FS.createDirAll testRoot

def testProjectInit : IO Unit := do
  let root := testRoot / "project-init"
  if ← root.pathExists then IO.FS.removeDirAll root
  IO.FS.createDirAll root
  let message ← Install.initProject root
  check (message.contains ".eggshell.toml")
    "project initialization did not report its config"
  let config := root / ".eggshell.toml"
  let ignore := root / ".eggs" / ".gitignore"
  check ((← IO.FS.readFile config) = Install.projectConfig)
    "project initialization changed the canonical config"
  check ((← IO.FS.readFile ignore) = "*\n!.gitignore\n")
    "project authority is not ignored by default"
  let parsed ← Config.parseFile config
  let work ← IO.ofExcept (Config.resolve parsed "work")
  check (work.read.length = 1 && work.write.isSome)
    "initialized work profile is not a single writable authority"
  try
    let _ ← Install.initProject root
    throw (IO.userError "project initialization overwrote an existing config")
  catch error =>
    check (toString error |>.contains "already exists")
      "repeated project initialization failed for the wrong reason"
  IO.println "PASS project init creates one ignored local authority"

def testNativeWorkUnits : IO Unit := do
  let atomic : ToolEvent := {
    name := "Bash"
    useId := "compound"
    input := r#"{"command":"sed -n '1,20p' src/a.c; sed -n '30,40p' src/b.c && rg 'a;b' src"}"#
    response := r#"{"output":"observed bundle"}"#
  }
  check (canonicalToolWork atomic =
      "Bash\n" ++ atomic.input)
    "native invocation identity lost canonical JSON structure"
  let batched : ToolEvent := { atomic with
    useId := "line-batch"
    input := r#"{"command":"rg update_vsyscall kernel/time\nsed -n '1,80p' kernel/time/vsyscall.c"}"#
  }
  check (canonicalToolWork batched =
      "Bash\n" ++ batched.input)
    "one native invocation was split into adapter-invented Work"
  let firstRead : ToolEvent := { atomic with
    name := "read_file"
    input := "{\"path\":\"src/a.c\",\"offset\":0,\"limit\":20}"
  }
  let secondRead : ToolEvent := { atomic with
    name := "read_file"
    input := "{\"path\":\"src/a.c\",\"offset\":20,\"limit\":20}"
  }
  check (canonicalToolWork firstRead != canonicalToolWork secondRead)
    "native input numbers disappeared from Work identity"
  let reorderedRead : ToolEvent := { firstRead with
    input := "{\"limit\":20,\"offset\":0,\"path\":\"src/a.c\"}"
  }
  check (canonicalToolWork firstRead = canonicalToolWork reorderedRead)
    "object-key order changed canonical native Work identity"
  let query : ToolEvent := { atomic with input := "{\"query\":\"x\"}" }
  let path : ToolEvent := { atomic with input := "{\"path\":\"x\"}" }
  check (canonicalToolWork query != canonicalToolWork path)
    "JSON object keys disappeared from Work identity"
  check (canonicalJson "{\"result\":{\"value\":\"x\"}}" !=
      canonicalJson "{\"result\":[\"x\"]}")
    "JSON containers disappeared from native identity"
  check (canonicalJson "{\"message\":\"true\"}" !=
      canonicalJson "{\"message\":true}")
    "JSON value types disappeared from native identity"
  check (canonicalJson "{\"output\":\"permission denied\"}" !=
      canonicalJson "{\"error\":\"permission denied\"}")
    "native result keys disappeared from Outcome identity"
  let pending : PendingTurn := {
    sessionId := "segment-session"
    turnId := "segment-turn"
    cwd := "/repo"
    prompt := "inspect both sources"
    profile := "work"
    semanticMatcher := none
    read := []
    write := none
    handoffChars := 120000
    projection := .automatic
    tools := [batched]
  }
  let staged ← IO.ofExcept (stagedGraphValues pending)
  let outcomes := staged.filterMap OutcomeEdge.fromValue?
  let decompositions := staged.filterMap AllEdge.fromValue?
  match outcomes, decompositions with
  | [operation], [decomposition] =>
      check (decomposition.children.head? == some operation.work)
        "turn decomposition lost its observed native invocation"
  | _, _ => throw (IO.userError
      "one native invocation did not compile to one Work Outcome and one turn decomposition")
  IO.println "PASS one native invocation is exactly one observed Work"

def testPersistenceDag : IO Unit := do
  let payload := "DAG_PAYLOAD_7f93a_shared_once"
  let pending : PendingTurn := {
    sessionId := "dag-session"
    turnId := "dag-turn"
    cwd := "/repo"
    prompt := "observe two operations"
    profile := "work"
    semanticMatcher := none
    read := [dagEgg.toString]
    write := some dagEgg.toString
    handoffChars := 120000
    projection := .automatic
    tools := [{
      name := "shell"
      useId := "dag-one"
      input := "{\"command\":\"printf first\"}"
      response := "{\"output\":\"" ++ payload ++ "\"}"
    }, {
      name := "shell"
      useId := "dag-two"
      input := "{\"command\":\"printf second\"}"
      response := "{\"output\":\"" ++ payload ++ "\"}"
    }]
    finalMessage := some "both observations completed"
  }
  let _ ← Persistence.create dagEgg
  let _ ← promote pending dagEgg
  let graph ← Persistence.load dagEgg
  let snapshot ← DB.PageMap.pin dagEgg
  let some first := pending.tools.head? | throw (IO.userError "missing shared atom fixture")
  let shared := Value.text (canonicalJson first.response)
  let ids ← Persistence.Store.getIds snapshot.get ("hash:" ++ toString (hash shared))
  let exact ← ids.filterM fun id => (Persistence.Store.readNode snapshot snapshot.get id).map (· == shared)
  check (exact.length == 1) "the DB duplicated a shared structural node"
  let roundTrip ← IO.ofExcept (Persistence.decode (← IO.ofExcept (Persistence.encode graph)))
  check (roundTrip.authority == graph.authority &&
      roundTrip.revision == graph.revision && roundTrip.values == graph.values &&
      roundTrip.unions.length == graph.unions.length)
    ".egg DAG round-trip changed graph authority"
  IO.println "PASS page DB stores one structural node once and round-trips its graph"

def testPrivateStorage : IO Unit := do
  let eggDirectory := testRoot / "private-authority"
  let egg := eggDirectory / "work.egg"
  let _ ← Persistence.create egg
  check ((← accessMode eggDirectory) = "700")
    ".egg directory is not private"
  check ((← accessMode egg) = "700")
    ".egg authority is not private"
  IO.setAccessRights egg {
    user := { read := true, write := true, execution := true }
    group := { read := true }
    other := { read := true }
  }
  let _ ← Persistence.load egg
  check ((← accessMode egg) = "700")
    "existing .egg authority was not hardened on load"
  let stateDirectory := testRoot / "private-state"
  let state := stateDirectory / "state.json"
  let pending := stateDirectory / "pending.json"
  writeJson state ({ profile := "work" } : ThreadState)
  writeJson pending ({
    sessionId := "private-session"
    turnId := "private-turn"
    cwd := "/repo"
    prompt := "private prompt"
    profile := "work"
    semanticMatcher := none
    read := []
    write := none
    handoffChars := 120000
    projection := .automatic
  } : PendingTurn)
  check ((← accessMode stateDirectory) = "700")
    "Plugin state directory is not private"
  check ((← accessMode state) = "600" && (← accessMode pending) = "600")
    "Plugin state or pending turn is not private"
  IO.println "PASS .egg and staged Plugin state use private access modes"

def testAuthorityPathBoundaries : IO Unit := do
  let root := testRoot / "authority-boundaries"
  IO.FS.createDirAll root
  let missing := root / "missing-read.egg"
  let composite ← Persistence.loadComposite [missing]
  check (composite.values.isEmpty && !(← missing.pathExists))
    "reading a missing authority created it"
  let executable := root / "not-an-egg"
  IO.FS.writeFile executable "not an Eggshell graph"
  IO.setAccessRights executable {
    user := { read := true, write := true, execution := true }
    group := { read := true, execution := true }
    other := { read := true, execution := true }
  }
  let malformedRejected ← try
      let _ ← Persistence.load executable
      pure false
    catch _ => pure true
  check malformedRejected "malformed authority was accepted"
  check ((← accessMode executable) = "755")
    "a malformed file was chmodded before it decoded as an authority"
  let directory := root / "not-a-file"
  IO.FS.createDirAll directory
  IO.setAccessRights directory {
    user := { read := true, write := true, execution := true }
    group := { read := true, execution := true }
    other := { read := true, execution := true }
  }
  let directoryRejected ← try
      let _ ← Persistence.load directory
      pure false
    catch _ => pure true
  check directoryRejected "directory was accepted as an authority"
  check ((← accessMode directory) = "755")
    "a directory was chmodded while probing an authority"
  let linked := root / "linked.egg"
  let link ← IO.Process.output {
    cmd := "ln"
    args := #["-s", executable.toString, linked.toString]
  }
  check (link.exitCode == 0) "test could not create an authority symlink"
  let linkRejected ← try
      let _ ← Persistence.load linked
      pure false
    catch _ => pure true
  check linkRejected "symbolic-link authority was accepted"
  check ((← accessMode executable) = "755")
    "authority loading followed a symbolic link and changed its target"
  let outside := root / "outside"
  IO.FS.createDirAll outside
  let linkedDirectory := root / "linked-directory"
  let directoryLink ← IO.Process.output {
    cmd := "ln"
    args := #["-s", outside.toString, linkedDirectory.toString]
  }
  check (directoryLink.exitCode == 0)
    "test could not create a parent-directory symlink"
  let escaped := linkedDirectory / "escaped.egg"
  let escapeRejected ← try
      let _ ← Persistence.loadComposite [escaped]
      pure false
    catch _ => pure true
  check (escapeRejected && !(← (outside / "escaped.egg").pathExists))
    "authority loading escaped through a symbolic-link parent"
  IO.println "PASS authority reads never create, follow links, or harden invalid paths"

def onlyWork (tool : ToolEvent) : IO String :=
  pure (canonicalToolWork tool)

def seed : PendingTurn := {
  sessionId := "seed-session"
  turnId := "seed-turn"
  cwd := "/linux"
  prompt := "Trace pvclock into Linux wallclock interfaces"
  profile := "work"
  semanticMatcher := none
  read := [testEgg.toString]
  write := some testEgg.toString
  handoffChars := 120000
  projection := .automatic
  tools := [{
    name := "shell"
    useId := "tool-1"
    input := "{\"command\":\"rg update_vsyscall kernel/time\"}"
    response := "{\"output\":\"opaque-before-marker\\nobserved native bytes\\nopaque-after-marker\"}"
  }, {
    name := "shell"
    useId := "tool-2"
    input := "{\"command\":\"rg pvclock_clocksource_read arch/x86/kernel/pvclock.c\"}"
    response := "{\"output\":\"opaque-before-marker\\nobserved native bytes\\nopaque-after-marker\"}"
  }]
  finalMessage := some "pvclock reaches generic timekeeping and the vDSO"
}

def testLocalUnion : IO Unit := do
  check (!Matcher.Corpus.identifyingUnit "rg" &&
      !Matcher.Corpus.identifyingUnit "nl" &&
      Matcher.Corpus.identifyingUnit "x86" &&
      Matcher.Corpus.identifyingUnit "時計")
    "transport scaffolding became an independent identity anchor"
  let _ ← Persistence.create testEgg
  let promotion ← promote seed testEgg
  check (promotion.outcomeRelations.length = 3)
    "turn compiler did not persist native invocation and parent Outcomes"
  let graph ← Persistence.load testEgg
  let workGraph := WorkGraph.fromValues graph.values
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer workGraph
  let candidateWorks := corpus.candidates.map (·.edge.work)
  check (candidateWorks.length == 3 && candidateWorks.contains (.text seed.prompt) &&
      seed.tools.all fun tool => candidateWorks.contains (.text (canonicalToolWork tool)))
    "the candidate universe hid an Outcome owner based on its All position"
  check (corpus.candidates.length == seed.tools.length + 1 &&
      workGraph.subworks.length == seed.tools.length + 1)
    "the unified Outcome corpus lost the structural All boundary"
  check (graph.revision = 1) "promotion did not advance the .egg revision"
  check (graph.values.length = 5)
    "turn compiler duplicated structural closure instead of storing relation roots"
  let nodes := graph.values.flatMap Value.nodes
  let some firstTool := seed.tools.head? |
    throw (IO.userError "seed lost its first native operation")
  check (nodes.contains (.text (canonicalToolWork firstTool)) &&
      nodes.contains (.text firstTool.useId) &&
      !nodes.contains (.text "{\"command\":\"rg update_vsyscall kernel/time\"}"))
    "native occurrence did not keep one semantic Work plus compact exact identity"
  let selection : Config.Selection := {
    label := "work"
    semanticMatcher := none
    read := [{ name := "work", path := testEgg }]
    write := some { name := "work", path := testEgg }
    handoffChars := 120000
  }
  let query ← onlyWork {
    name := "shell"
    useId := "tool-2"
    input := "{\"command\":\"rg update_vsyscall ./kernel/time\"}"
    response := ""
  }
  let some handoff ← automaticHandoff selection query [] true |
    throw (IO.userError "stored operation was not selected")
  check (handoff.localUnions > 0 && handoff.completed > 0 &&
      handoff.blocksCurrent &&
      !handoff.coveredFragments.isEmpty &&
      handoff.text.contains "opaque-before-marker")
    "structural Outcome ownership did not replan a complete historical Operation"
  let retrievalOnly ← automaticHandoff selection query [] false
    (some "new observed native result") [] true false
  check (!retrievalOnly.any fun candidate =>
      candidate.localUnions != 0 || candidate.completed != 0 ||
        candidate.blocksCurrent)
    "retrieval-only control performed equality or work erasure"
  let hidden ← automaticHandoff { selection with handoffChars := 1 } query [] true
  check hidden.isNone
    "an Outcome hidden by the transport budget still erased current work"
  let repeated ← automaticHandoff selection query handoff.deliveredGraphs true
  check repeated.isNone
    "an unchanged Outcome subtree interrupted the same operation twice"
  let rewritten ← onlyWork {
    name := "shell"
    useId := "tool-rewritten"
    input := "{\"command\":\"rg -n update_vsyscall kernel/time\"}"
    response := ""
  }
  let repeatedRewrite ← automaticHandoff selection rewritten
    handoff.deliveredGraphs true
  check repeatedRewrite.isNone
    "a surface rewrite re-delivered the same prior fragment and Outcome owner"
  let repeatedContext ← automaticHandoff selection query handoff.deliveredGraphs false
  check repeatedContext.isNone
    "an already delivered Outcome subtree was retransmitted as context"
  let nativeHistory := promotion.outcomeRelations.map nativeHistoryKey
  let ownContext ← automaticHandoff selection query nativeHistory false
  check ownContext.isNone
    "a promoted Outcome already present in native history was echoed through a projection"
  let ownRewrite ← automaticHandoff selection rewritten nativeHistory false
  check ownRewrite.isNone
    "a reworded projection echoed an Outcome already present in native history"
  check (handoff.deliveredGraphs.all fun key =>
      key.startsWith "g:" || key.startsWith "d:")
    "delivery state did not distinguish graph transport from graph control"
  let compound : ToolEvent := {
    name := "shell"
    useId := "tool-3"
    input := "{\"command\":\"rg update_vsyscall ./kernel/time; inspect new tsc calibration\"}"
    response := ""
  }
  let some partialHandoff ← automaticHandoff selection (canonicalToolWork compound) [] true |
    throw (IO.userError "contained prior work was not projected into a compound operation")
  check (partialHandoff.completed > 0 && partialHandoff.blocksCurrent &&
      partialHandoff.text.contains "opaque-before-marker")
    "a compound operation did not preserve and reuse its completed fragment"
  let stagedTool : ToolEvent := {
    name := "shell"
    useId := "staged-tool"
    input := "{\"command\":\"rg stage_unique_only\"}"
    response := "{\"output\":\"stage_unique_only.c\"}"
  }
  let stagedPending : PendingTurn := {
    seed with
    sessionId := "active-session"
    turnId := "active-turn"
    tools := [stagedTool]
    finalMessage := none
  }
  let staged ← IO.ofExcept (stagedGraphValues stagedPending)
  let beforeStageProbe ← Persistence.load testEgg
  let some activeHandoff ← automaticHandoff selection
      (← onlyWork {
        stagedTool with
        useId := "proposed-tool"
        input := "{\"command\":\"rg stage_unique_only\"}"
        response := ""
      })
      [] true none staged |
    throw (IO.userError "current-turn graph control lost a staged Outcome")
  check (activeHandoff.blocksCurrent && activeHandoff.text = "" &&
      !activeHandoff.text.contains "GRAPH DELTA")
    "current-chat staged Outcome was retransmitted instead of only stopping duplicate Work"
  let some restoredStage ← automaticHandoff selection
      (← onlyWork {
        stagedTool with
        useId := "post-compaction-tool"
        input := "{\"command\":\"rg stage_unique_only\"}"
        response := ""
      }) [] true none staged false |
    throw (IO.userError "compaction did not restore a staged Outcome graph")
  check (restoredStage.text.contains (canonicalJson stagedTool.response) &&
      !restoredStage.text.contains "already visible earlier")
    "compaction restoration lost the staged Outcome graph"
  let afterStageProbe ← Persistence.load testEgg
  check (afterStageProbe.revision = beforeStageProbe.revision)
    "run-local staged Work mutated persistent .egg authority"
  IO.println "PASS batched native Work -> Local Union -> resaturation -> one graph delta"

def testSemanticProviderTransport : IO Unit := do
  let _ ← Persistence.create semanticEgg
  let priorTool : ToolEvent := {
    name := "shell"
    useId := "semantic-tool"
    input := r#"{"command":"trace the vDSO clock_gettime realtime path"}"#
    response := r#"{"output":"時刻保持層から利用者APIへ接続した"}"#
  }
  let prior : PendingTurn := {
    seed with
    sessionId := "semantic-seed"
    turnId := "semantic-turn"
    prompt := "inspect the Linux realtime fast path"
    read := [semanticEgg.toString]
    write := some semanticEgg.toString
    tools := [priorTool]
    finalMessage := some "壁時計経路を確認した"
  }
  let _ ← promote prior semanticEgg
  let base : Config.Selection := {
    label := "semantic"
    semanticMatcher := none
    read := [{ name := "semantic", path := semanticEgg }]
    write := some { name := "semantic", path := semanticEgg }
    handoffChars := 120000
  }
  let current := "利用者空間から現在時刻を高速取得する仕組みを調査"
  let surface ← automaticHandoff base current [] false
  check surface.isNone
    "surface-only matching unexpectedly bridged disjoint languages"
  let executable ← IO.appPath
  let persisted ← Persistence.load semanticEgg
  let indexed := SemanticMatcher.outcomeWorkItems persisted.values
  check (indexed.length == 2 && indexed.head?.map (·.text) =
      some (prior.prompt ++ "\n" ++ prior.finalMessage.getD "") &&
      indexed.any (·.text == canonicalToolWork priorTool ++ "\n" ++
        canonicalJson priorTool.response))
    "a completed parent must retain summary priority and searchable child evidence"
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer
    (WorkGraph.fromValues persisted.values)
  let eligible := SemanticMatcher.eligibleCandidates corpus
  let childNominations := SemanticMatcher.nominations eligible { related := [1, 1, 9999] }
  check (childNominations.related.length == 1 &&
      childNominations.related.all fun relation => corpus.candidates.any fun candidate =>
        candidate.edge.relation == relation &&
          candidate.edge.work == .text (canonicalToolWork priorTool))
    "duplicate or invalid provider indexes changed evidence authority"
  let retrievalCommand := [executable.toString, "semantic-provider-fixture", "retrieval"]
  let _ ← SemanticMatcher.indexWorks retrievalCommand [SemanticMatcher.item (.text prior.prompt) prior.prompt]
  let retrieval ← automaticHandoff {
    base with semanticMatcher := some retrievalCommand
  } current [] false
  let some retrieval := retrieval |
    throw (IO.userError "configured provider nominated no prior Work")
  check (retrieval.localUnions = 0 && retrieval.completed = 0 &&
      retrieval.advisory > 0 && !retrieval.blocksCurrent &&
      retrieval.text.contains "壁時計経路を確認した" &&
      retrieval.text.contains "時刻保持層から利用者APIへ接続した" &&
      retrieval.text.contains "SUPPORT OUTCOME" &&
      !(retrieval.text.splitOn "END SELECTED WORK GRAPH" |>.headD "").contains (canonicalToolWork priorTool) &&
      retrieval.sourceCheckpoints.isEmpty && retrieval.coveredFragments.isEmpty)
    "semantic parent did not deliver child evidence separately from current Work demands"
  let childCommand := [executable.toString, "semantic-provider-fixture", "child"]
  let _ ← SemanticMatcher.indexWorks childCommand [SemanticMatcher.item (.text prior.prompt) prior.prompt]
  let some childRetrieval ← automaticHandoff {
      base with semanticMatcher := some childCommand
    } current [] false |
    throw (IO.userError "a completed parent's child evidence was not retrievable")
  check (childRetrieval.localUnions = 0 && childRetrieval.completed = 0 &&
      childRetrieval.advisory > 0 && !childRetrieval.blocksCurrent &&
      childRetrieval.text.contains "時刻保持層から利用者APIへ接続した" &&
      !childRetrieval.deliveredGraphs.any (·.startsWith "d:"))
    "retrieving child evidence incorrectly completed or blocked the current work"
  let some operation ← automaticHandoff base
      (canonicalToolWork { priorTool with useId := "semantic-proposal" })
      retrieval.deliveredGraphs true |
    throw (IO.userError "a demanded child Operation did not reconnect its Outcome")
  check (operation.completed > 0 && operation.blocksCurrent &&
      operation.text.contains "EGGSHELL GRAPH DELTA" &&
      !operation.text.contains "時刻保持層から利用者APIへ接続した" &&
      !operation.deliveredGraphs.any (·.startsWith "g:") &&
      operation.deliveredGraphs.any (·.startsWith "d:"))
    s!"a demanded child did not transport and control its own completed Outcome: completed={operation.completed} blocks={operation.blocksCurrent} delta={operation.text.contains "EGGSHELL GRAPH DELTA"} repeated-body={operation.text.contains "時刻保持層から利用者APIへ接続した"} new-graph={operation.deliveredGraphs.any (·.startsWith "g:")} checkpoint={operation.deliveredGraphs.any (·.startsWith "d:")} reason={operation.reason}"
  let repeated ← automaticHandoff base
      (canonicalToolWork { priorTool with useId := "semantic-retry" })
      (retrieval.deliveredGraphs ++ operation.deliveredGraphs) true
  check repeated.isNone
    "a directly demanded child Operation interrupted the same context epoch twice"
  IO.println "PASS semantic parent stays advisory until a child Operation is demanded"

def testNaturalLanguageSessionTransport : IO Unit := do
  let _ ← Persistence.create naturalLanguageEgg
  let priorPrompt :=
    "読書支援アプリの方針を決める。登録を必須にせず、行動追跡をせず、連続記録で利用者を急かさない。"
  let priorResult :=
    "方針はローカル優先、アカウント任意、行動分析なし、連続日数やランキングなしとする。"
  let executable ← IO.appPath
  let command := [executable.toString, "semantic-provider-fixture", "retrieval"]
  let prior : PendingTurn := {
    seed with
    sessionId := "natural-language-seed"
    turnId := "natural-language-turn"
    prompt := priorPrompt
    semanticMatcher := some command
    read := [naturalLanguageEgg.toString]
    write := some naturalLanguageEgg.toString
    tools := []
    finalMessage := none
  }
  withSession prior.sessionId fun files => do
    writeJson files.state ({ profile := "natural-language" } : ThreadState)
    writeJson files.pending prior
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "Stop"), ("session_id", prior.sessionId),
    ("turn_id", prior.turnId), ("last_assistant_message", priorResult)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionEnd"), ("session_id", prior.sessionId)])
  let persisted ← Persistence.load naturalLanguageEgg
  let indexed := SemanticMatcher.outcomeWorkItems persisted.values
  check (indexed.length == 1 && indexed.head?.map (·.text) =
      some (priorPrompt ++ "\n" ++ priorResult))
    "a tool-free turn's conclusions were not searchable"
  let selection : Config.Selection := {
    label := "natural-language"
    semanticMatcher := some command
    read := [{ name := "natural-language", path := naturalLanguageEgg }]
    write := some { name := "natural-language", path := naturalLanguageEgg }
    handoffChars := 120000
  }
  let current :=
    "以前決めた読書支援アプリのプライバシー方針に沿ってオンボーディングを設計する。"
  let some first ← automaticHandoff selection current [] false |
    throw (IO.userError "an independent session received no prior natural-language turn")
  check (first.completed = 0 && first.advisory > 0 && !first.blocksCurrent &&
      first.text.contains priorPrompt &&
      first.text.contains priorResult)
    "natural-language input and outcome were not transported as advisory graph"
  check (first.text.contains evidenceGapGuidance &&
      first.text.contains "uncovered requirement of the current request" &&
      first.text.contains "mark the conclusion UNRESOLVED, and stop" &&
      first.text.contains "Failed or unavailable checks are not passing checks")
    "advisory handoff omitted honest evidence-exhaustion and resumption conditions"
  let repeated ← automaticHandoff selection current first.deliveredGraphs false
  check repeated.isNone
    "one session received the same natural-language graph twice before compaction"
  let some independent ← automaticHandoff selection current [] false |
    throw (IO.userError "a second independent session could not receive the shared graph")
  check (independent.text.contains priorPrompt && independent.text.contains priorResult)
    "independent-session delivery lost the prior input or outcome"
  IO.println "PASS tool-free Japanese turn crosses independent sessions once per context epoch"

def testGroundedOutcomeTransport : IO Unit := do
  let irrelevant := String.ofList (List.replicate 20000 'x')
  let relevant := "generic timekeeping vdso clock_gettime syscall."
  let result := irrelevant ++ "\n" ++ relevant ++ "\n" ++ irrelevant
  let tool : ToolEvent := {
    name := "Bash"
    useId := "projection-tool"
    input := r#"{"command":"generic timekeeping vdso clock_gettime syscall"}"#
    response := Lean.Json.mkObj [("output", .str result)] |>.compress
  }
  let prior : PendingTurn := {
    seed with
    sessionId := "projection-seed"
    turnId := "projection-turn"
    prompt := "inspect one native result"
    read := [transportEgg.toString]
    write := some transportEgg.toString
    tools := [tool]
    finalMessage := some "native result recorded"
  }
  let _ ← Persistence.create transportEgg
  let _ ← promote prior transportEgg
  let persisted ← Persistence.load transportEgg
  let encoded ← IO.ofExcept (Persistence.encode persisted)
  check (encoded.contains irrelevant)
    "the durable .egg owner lost unprojected Outcome source"
  let owner ← match (WorkGraph.fromValues persisted.values).outcomes.find?
      (fun edge => edge.work == .text (canonicalToolWork tool)) with
    | some edge => pure edge
    | none => throw (IO.userError "Outcome owner was not persisted")
  let selection : Config.Selection := {
    label := "projection"
    semanticMatcher := none
    read := [{ name := "transport", path := transportEgg }]
    write := some { name := "transport", path := transportEgg }
    handoffChars := 120000
  }
  let some handoff ← automaticHandoff selection
      (canonicalToolWork tool) [] true |
    throw (IO.userError "grounded parent graph was not selected")
  check (handoff.text.contains relevant && handoff.text.contains irrelevant &&
      handoff.text.contains (relationKey owner.relation))
    "complete Work identity did not transport its complete Outcome"
  let advisoryTool : ToolEvent := {
    tool with
    useId := "projection-advisory"
    input := r#"{"command":"generic timekeeping vdso"}"#
    response := ""
  }
  let some advisory ← automaticHandoff selection
      (canonicalToolWork advisoryTool) [] true |
    throw (IO.userError "grounded advisory fragment was not selected")
  check (advisory.blocksCurrent && advisory.completed > 0 &&
      advisory.text.contains relevant &&
      !advisory.text.contains irrelevant &&
      advisory.text.contains "GROUNDED OUTCOME" &&
      advisory.text.contains (relationKey owner.relation))
    "a relevant fragment did not transport its provenance-bearing projection"
  IO.println "PASS matched fragments transport grounded Outcome projections"

def testOperationBoundaryLookup : IO Unit := do
  let _ ← Persistence.create operationBoundaryEgg
  let prior : PendingTurn := {
    seed with
    sessionId := "boundary-seed"
    turnId := "boundary-turn"
    read := [operationBoundaryEgg.toString]
    write := some operationBoundaryEgg.toString
    tools := [{
      name := "Bash"
      useId := "prior-read"
      input := r#"{"command":"sed -n '1,180p' arch/x86/kernel/kvm.c; rg clocksource_select kernel/time"}"#
      response := r#"{"output":"arch/x86/kernel/kvm.c lines 1-180 contain kvm_guest_init and kvmclock_init\nkernel/time contains clocksource_select"}"#
    }]
  }
  let _ ← promote prior operationBoundaryEgg
  let persisted ← Persistence.load operationBoundaryEgg
  check ((WorkGraph.fromValues persisted.values).outcomes.length = 2)
    "one observed native invocation did not become one persistent Work outcome"
  let selection : Config.Selection := {
    label := "work"
    semanticMatcher := none
    read := [{ name := "work", path := operationBoundaryEgg }]
    write := some { name := "work", path := operationBoundaryEgg }
    handoffChars := 120000
  }
  let proposed : ToolEvent := {
    name := "Bash"
    useId := "proposed-read"
    input := r#"{"command":"sed -n '840,1030p' arch/x86/kernel/kvm.c; sed -n '1,180p' arch/x86/include/asm/kvm_para.h; sed -n '1,180p' arch/x86/include/asm/hypervisor.h"}"#
    response := ""
  }
  let some handoff ← automaticHandoff selection
      (canonicalToolWork proposed) [] true |
    throw (IO.userError "a related prior observation was not delivered as advice")
  check (!handoff.blocksCurrent && handoff.completed = 0 &&
      handoff.advisory > 0 &&
      handoff.text.contains "OUTCOME")
    "a new advisory Local Union did not remain visible without erasing Work"
  let retry ← automaticHandoff selection (canonicalToolWork proposed)
    handoff.deliveredGraphs true
  check retry.isNone
    "the same advisory Outcome subtree was delivered more than once"
  let connectedPartial : ToolEvent := {
    name := "Bash"
    useId := "connected-partial"
    input := r#"{"command":"rg -n clocksource_select kernel/time; inspect new acpi_pm work"}"#
    response := ""
  }
  let some partialAdvice ← automaticHandoff selection
      (canonicalToolWork connectedPartial) [] true |
    throw (IO.userError "a distinctively anchored prior fragment was not delivered")
  check (partialAdvice.completed > 0 && partialAdvice.advisory = 0 &&
      partialAdvice.blocksCurrent && !partialAdvice.coveredFragments.isEmpty)
    "a complete grounded native clause did not erase only its matching Work"
  let repeatedPartial ← automaticHandoff selection
    (canonicalToolWork connectedPartial) partialAdvice.deliveredGraphs true
  check repeatedPartial.isNone
    "one advisory Outcome owner was delivered twice in one context epoch"
  let equivalent : ToolEvent := {
    name := "Bash"
    useId := "equivalent-read"
    input := r#"{"command":"rg clocksource_select ./kernel/time; sed -n '1,180p' ./arch/x86/kernel/kvm.c"}"#
    response := ""
  }
  let equivalentHandoff ← automaticHandoff selection
    (canonicalToolWork equivalent) [] true
  check (equivalentHandoff.any (·.blocksCurrent))
    "equivalent native invocation spelling did not reuse the prior Outcome"
  let differentRange ← onlyWork {
    name := "Bash"
    useId := "different-range"
    input := r#"{"command":"sed -n '181,260p' arch/x86/kernel/kvm.c"}"#
    response := ""
  }
  /-
  A different grounded result projection from the same durable owner is new
  graph progress. Advisory evidence is transported once but cannot checkpoint
  native Work.
  -/
  let some rangeAdvice ← automaticHandoff selection differentRange
    partialAdvice.deliveredGraphs true
    | throw (IO.userError "new grounded evidence from one owner was suppressed")
  check (!rangeAdvice.blocksCurrent &&
      rangeAdvice.text.contains "GROUNDED OUTCOME")
    "a new advisory Outcome projection was not transported without erasing Work"
  let repeatedRange ← automaticHandoff selection differentRange
    (partialAdvice.deliveredGraphs ++ rangeAdvice.deliveredGraphs) true
  check repeatedRange.isNone
    "the same grounded Outcome projection was transported twice"
  let sequencedClause ← onlyWork {
    name := "Bash"
    useId := "sequence-clause"
    input := r#"{"command":"kernel/time clocksource_select rg"}"#
    response := ""
  }
  let sequenceHandoff ← automaticHandoff selection sequencedClause [] false
    (some "new observed native result")
  check (sequenceHandoff.any (fun handoff =>
      !handoff.blocksCurrent && handoff.completed > 0 &&
        handoff.localUnions > 0 && handoff.text.contains "OUTCOME"))
    "an orderless equivalent Work failed to saturate without controlling a completed call"
  IO.println "PASS run-local fragments reuse one persistent native Work"

def testFlexibleContextAllocation : IO Unit := do
  let source := String.ofList ((List.range 16000).map fun i => Char.ofNat (97 + i % 26))
  let work := String.ofList (List.replicate 233 'w')
  let owner := OutcomeEdge.make (.text work) (.text source) [] (by simp) (by simp)
  -- Independent coordinate oracle: serialize complete prefixes, rather than
  -- adding the cached character widths used by the production layout.
  let scalar := String.ofList ((List.range 32).map Char.ofNat) ++ "plain\\\"\n日本語🐣"
  let encodedScalar := (Lean.Json.str scalar).compress
  let some decodedScalar := decodedToolText? encodedScalar |
    throw (IO.userError "canonical scalar fixture did not decode")
  let layout := DecodedLayout.make decodedScalar
  let characters := scalar.toList
  let oracle := characters.zipIdx.map fun (_, index) =>
    let first := (Lean.Json.str (String.ofList (characters.take index))).compress.length - 1
    let last := (Lean.Json.str (String.ofList (characters.take (index + 1)))).compress.length - 1
    (index, first, last)
  for first in [:encodedScalar.length] do
    for width in [1, 2, 3, 7, 19, 31, 128] do
      let last := min encodedScalar.length (first + width)
      if valid : first < last ∧ last ≤ encodedScalar.length ∧ last - first ≤ 2048 then
        let requested : EvidenceRange encodedScalar := ⟨first, last, valid.1, valid.2.1, valid.2.2⟩
        let contained := oracle.filter fun (_, start, stop) => first ≤ start && stop ≤ last
        let expected := do
          let (start, rawStart, _) ← contained.head?
          let (stop, _, rawStop) ← contained.getLast?
          some (start, stop + 1, rawStart, rawStop)
        let observed := (decodedEvidenceUsing? layout requested).map fun view =>
          (view.content.start, view.content.stop, view.original.start, view.original.stop)
        check (observed == expected)
          "prepared scalar layout lost an encoded character, changed an occurrence, or admitted a partial escape"
  -- The real scattered-window pattern which formerly spent two wide ranges
  -- in the middle/end and omitted the first input-type evidence.
  let windows := [36, 21, 35, 37, 43, 1, 6, 40, 10, 32, 39, 5, 11, 27, 25, 2]
  let offered := contextRanges source (work.length + 1) windows 4096
  let selected := offered.foldl (fun selected range =>
    selected.offer owner [] (.original range))
    (ContextSelection.empty : ContextSelection source 4096)
  check (selected.views.length > 3 && selected.used ≤ 4096 &&
      selected.used == (selected.views.map fun v => v.range.stop - v.range.start).sum)
    "flexible allocation retained the obsolete range-count cap or exceeded the source budget"
  for point in [506, 920, 13846] do
    check (selected.views.any fun view => decide (view.range.covers point))
      "scattered context allocation omitted a high-priority independent source clue"
  let groups := meaningContextGroups source (work.length + 1) windows
  check (groups.map (·.priority) == (groups.map (·.priority)).mergeSort (· ≤ ·))
    "coalescing changed the best numerical meaning priority"
  for indices in [windows, windows.reverse, List.range 32, [1, 1, 2, 3], [0, 8, 9, 25, 26]] do
    let cues := indices.zipIdx.filterMap fun (index, rank) =>
      meaningContext? source (work.length + 1) index rank
    let groups := meaningContextGroups source (work.length + 1) indices
    let segments := groups.flatMap (·.span.ranges)
    -- Independent pointwise oracle for the whole source, including gaps,
    -- boundary adjacency, unsorted/duplicate nominations and >2048 clusters.
    for point in [:source.length + 1] do
      check ((cues.any fun cue => decide (cue.span.covers point)) ==
          (segments.any fun range => decide (range.covers point)))
        "source coalescing/splitting invented a gap or lost a nominated source position"
    for left in segments do
      check (left.text.length ≤ 2048 && left.text.toList ==
          (source.toList.drop left.start).take (left.stop - left.start))
        "a segmented context is not exact bounded original data"
      for right in segments do
        if left.start != right.start then
          check (left.stop ≤ right.start || right.stop ≤ left.start)
            "coalesced segments duplicate original source bytes"
  let dense := meaningContextGroups source (work.length + 1) (List.range 32)
  check (dense.length == 1 && (dense.flatMap (·.span.ranges)).length > 3)
    "a dense interval was truncated instead of split at transport boundaries"
  -- The transport segment size is not an owner/cue allowance. A single
  -- related source can use its actual available share, including >6144 chars.
  let expanded := contextRanges source (work.length + 1) [18] 8192
  check ((expanded.map fun range => range.stop - range.start).sum == 8192 &&
      expanded.length ≥ 4 && expanded.head?.any (fun range => decide (range.covers 6934)) &&
      expanded.any (fun range => decide (range.covers 3900)))
    "an isolated meaning cue still has a fixed 2048/6144-character context cap"
  -- Independent pointwise oracle for overlapping expansions. Increasing the
  -- allowance must not revert colliding cues to their original narrow spans.
  let overlapping := [8, 11]
  let overlapGroups := meaningContextGroups source (work.length + 1) overlapping
  let overlapRanges := contextRanges source (work.length + 1) overlapping 8000
  for point in [:source.length + 1] do
    let expected := overlapGroups.any fun group =>
      decide ((group.span.widen (8000 / overlapGroups.length)).covers point)
    check ((overlapRanges.any fun range => decide (range.covers point)) == expected)
      "overlapping context growth shrank a meaning cue, lost original bytes or invented unrelated gaps"
  for allowance in [512, 1024, 2048, 8000, 16000] do
    let central := coreContextRanges source (work.length + 1) overlapping
    check (((contextRanges source (work.length + 1) overlapping allowance).take central.length).map
      (fun range => (range.start, range.stop)) == central.map (fun range => (range.start, range.stop)))
      "increasing context allocation displaced the original ranked cues behind peripheral data"
  check (overlapRanges.any (fun range => decide (range.covers 1500)) &&
      (overlapRanges.map fun range => range.stop - range.start).sum < 8000)
    "context expansion reverted to narrow cues or charged overlapping source bytes twice"
  for left in overlapRanges do
    for right in overlapRanges do
      if left.start != right.start then
        check (left.stop ≤ right.start || right.stop ≤ left.start)
          "overlapping expansions duplicated original source positions"
  let slice : TransportSlice := {members := [], visibleKeys := [], keys := [], text := source}
  let some (keys, text) := contextualOwnerData [] windows owner "  ORIGINAL ALL LINK" [] slice 4096 |
    throw (IO.userError "flexible production renderer omitted the original owner")
  check (keys.length > 3 && text.contains work && text.contains "ORIGINAL ALL LINK" && !text.contains source)
    "flexible production contexts lost graph binding or expanded a whole body"
  -- Extra nominations may still be undispatched after the first budgeted
  -- packet. Sending new ranges is allowed; repeating accepted ranges is not.
  if let some (nextKeys, _) := contextualOwnerData keys windows owner "  ORIGINAL ALL LINK" [] slice 4096 then
    check (!(nextKeys.any keys.contains)) "flexible production contexts repeated accepted ranges"
  have sourceLength : source.length = 16000 := by simp [source]
  let original : EvidenceRange source := ⟨0, 1800, by omega, by omega, by omega⟩
  let covered : List (EvidenceRange source) := [
    ⟨100, 300, by omega, by omega, by omega⟩,
    ⟨250, 700, by omega, by omega, by omega⟩,
    ⟨1100, 1500, by omega, by omega, by omega⟩]
  let acknowledged := covered.map (evidenceRangeKey owner)
  let foreign := OutcomeEdge.make (.text "different work") (.text source) [] (by simp) (by simp)
  let parsed := deliveredEvidenceRanges owner source
    (acknowledged ++ covered.map (evidenceRangeKey foreign) ++ ["e:invalid:receipt:0:17000"])
  check (parsed.map (fun range => (range.start, range.stop)) == [(100, 300), (250, 700), (1100, 1500)])
    "foreign or invalid receipts removed original evidence from this owner"
  let novel := original.subtractAll parsed
  for point in [:1801] do
    check ((novel.any fun part => decide (part.covers point)) ==
      (decide (original.covers point) && !(covered.any fun prior => decide (prior.covers point))))
      "flexible packet resizing repeated acknowledged positions or lost new original positions"
  for resizedBudget in [512, 1024, 2048, 9000, 16000] do
    if let some (newKeys, _) := contextualOwnerData keys windows owner "  ORIGINAL ALL LINK" [] slice resizedBudget then
      let fresh := deliveredEvidenceRanges owner source newKeys
      let old := deliveredEvidenceRanges owner source keys
      for part in fresh do
        check (old.all fun prior => part.stop ≤ prior.start || prior.stop ≤ part.start)
          "resizing a real source context retransmitted earlier original positions"
  for budget in [0, 511, 512, 1024, 4096, 6144, 16000] do
    let selected := (contextRanges source (work.length + 1) windows budget).foldl
      (fun selected range => selected.offer owner [] (.original range))
      (ContextSelection.empty : ContextSelection source budget)
    check (selected.used ≤ budget) "actual accepted contexts exceed their flexible budget"
  let allowances := ownerContextAllowances owner windows 9000 16000
  let central := (meaningContextGroups source (work.length + 1) windows).head?.map
    (fun group => group.span.stop - group.span.start) |>.getD source.length
  check (allowances.head? == some central && allowances.getLast? == some 16000 &&
      allowances.contains 9000 && allowances.any (· > 6144) &&
      allowances == allowances.mergeSort (· ≤ ·))
    "context allocation kept a fixed owner cap, lost its original central span, or ignored actual packet share"
  check (adaptivePacketBudget (120000, 128000) (9000, 12000) == (9000, 12000) &&
      adaptivePacketBudget (120000, 128000) (64000, 72000) == (64000, 72000) &&
      adaptivePacketBudget (120000, 128000) (200000, 500000) == (120000, 128000) &&
      contextAllowanceLevels 9000 [512, 1024, 6144, 16000, 48000] == [512, 1024, 6144, 9000] &&
      ownerContextDemand owner [18] == 1024 && ownerContextDemand owner (List.range 32) > 6144)
    "packet demand was pinned to 48000 bytes, filled its ceiling for a small query or ignored a real ceiling"
  let packetCost := fun (items : List String) =>
    (2 + (items.map String.length).sum, 2 + (items.map String.utf8ByteSize).sum)
  let plans := [("a", ["aaa", "aaaaaa"]), ("b", ["bbb", "bbbbbb"]),
    ("c", ["λλc", "cccccc"])]
  let some packet := boundedFlexiblePacketSlices 11 12 packetCost plans (fun _ => 0) (fun _ => 2) |
    throw (IO.userError "data-dependent packet refused its empty shell")
  check (packet.val == ["aaa", "bbb", "c"] &&
      packet.val.map (·.toList.head?) == [some 'a', some 'b', some 'c'])
    "a richer range displaced another owner or the complete UTF-8 packet bound was ignored"
  let some prioritized := boundedFlexiblePacketSlices 4 4 packetCost
      [("neighbor", []), ("a", ["aaaa"]), ("b", ["bbbb"])]
      (fun text => if text == "neighbor" then 1 else 0) |
    throw (IO.userError "entry coverage packet refused its empty shell")
  check (prioritized.val == ["a", "b"] &&
      (boundedFlexiblePacketSlices 1 1 packetCost plans (fun _ => 0)).isNone)
    "surrounding expansion hid a nominated entry or an oversized empty shell was accepted"
  let coherentPlans := [("a", ["aaa", "aaaaaa"]), ("b", ["bbb", "bbbbbb"]), ("nnn", [])]
  check (coherentPacketDemand (12000, 12000) (36000, 38000) == (36000, 38000) &&
      adaptivePacketBudget (120000, 128000)
        (coherentPacketDemand (12000, 12000) (36000, 38000)) == (36000, 38000))
    "minimum-entry cost underpriced the selected original contexts and their non-hit prerequisites"
  let some allCoherent := boundedFlexiblePacketSlices 14 14 packetCost coherentPlans
      (fun text => if text == "nnn" then 1 else 0) (fun text => if text == "nnn" then 0 else 2)
      (fun text => if text == "nnn" then 1 else 0) |
    throw (IO.userError "fully funded coherent entry packet refused its empty shell")
  check (allCoherent.val == ["aaaaaa", "bbbbbb"])
    "a peripheral owner displaced a fully funded original context"
  let some withSupport := boundedFlexiblePacketSlices 17 17 packetCost coherentPlans
      (fun text => if text == "nnn" then 1 else 0) (fun text => if text == "nnn" then 0 else 2) |
    throw (IO.userError "funded graph-support packet refused its empty shell")
  check (withSupport.val == ["aaaaaa", "bbbbbb", "nnn"])
    "a useful non-hit graph context was lost after coherent entry admission"
  let familyPlans := [("old-hit", []), ("current-hit", []), ("current-support", [])]
  let some familyPacket := boundedFlexiblePacketSlices 28 28 packetCost familyPlans
      (fun text => evidenceAdmissionPriority (if text == "old-hit" then 1 else 0)
        (text != "current-support")) |
    throw (IO.userError "source-family packet refused its empty shell")
  check (familyPacket.val == ["current-hit", "current-support"])
    "a later family's search hit displaced the first family's useful non-hit graph evidence"
  let some coherent := boundedFlexiblePacketSlices 8 8 packetCost coherentPlans
      (fun text => if text == "nnn" then 1 else 0) (fun text => if text == "nnn" then 0 else 1)
      (fun text => if text == "nnn" then 1 else 0) |
    throw (IO.userError "coherent entry packet refused its empty shell")
  check (coherent.val == ["aaa", "bbb"])
    "peripheral admission or a later lower level displaced the next important entry context"
  check (markPacketLevel [("owned", 4)] 0 1 == [("owned", 4)])
    "an admitted entry level was silently reduced by later enrichment"
  let some fallback := boundedFlexiblePacketSlices 4 4 packetCost coherentPlans
      (fun text => if text == "nnn" then 1 else 0) (fun _ => 999) |
    throw (IO.userError "coherent fallback refused its empty shell")
  check (fallback.val == ["a", "b"])
    "an oversized preferred context evicted an entry or invented an alternative"
  let some requested := boundedFlexiblePacketSlices 1000 1000 packetCost plans (fun _ => 0)
      (fun _ => 1) |
    throw (IO.userError "requested context packet refused its empty shell")
  check (requested.val == ["aaa", "bbb", "λλc"] &&
      requestedContextLevels 2 1 == [2] && requestedContextLevels 1 1 == [])
    "unused packet capacity silently created demand for lower-ranked original text"
  let some prerequisites := boundedFlexiblePacketSlices 9 9 packetCost
      [("a", ["aaaaaa"]), ("bbb", []), ("old", [])]
      (fun text => if text == "old" then 2 else if text == "bbb" then 1 else 0)
      (fun text => if text == "a" then 1 else 0)
      (fun text => if text == "old" then 1 else 0) |
    throw (IO.userError "source-family prerequisite packet refused its empty shell")
  check (prerequisites.val == ["a", "bbb", "old"])
    "entry enrichment displaced its original non-hit prerequisite"
  check (meaningPacketEntry [owner.relation] owner.relation slice &&
      !meaningPacketEntry [] owner.relation slice)
    "an advisory source owner lost its meaning-entry reservation or an unselected neighbor gained one"
  -- A ranked branch needs its enclosing entry context even when the saved
  -- source is much longer than the packet. Prefix serialization is an
  -- independent oracle for offsets (including tabs, escapes and Unicode).
  let numberedLine := fun number body => s!"{number}\t{body}\n"
  let entry := numberedLine 100 "Result selectOwner(const Target &target) {" ++
    numberedLine 101 "  const auto &cached = owners[target.id()];"
  let padding := "".intercalate ((List.range 80).map fun index =>
    numberedLine (102 + index) "    // context 日本語🐣 literal \\n and \\; more original context without a new function header")
  let beforeBranch := entry ++ padding
  let branch := numberedLine 182 "    if (target.isSpecial()) return use(cached);"
  let originalText := beforeBranch ++ branch ++
    "".intercalate ((List.range 30).map fun index =>
      numberedLine (183 + index) "    // trailing original text")
  let structuredSource := (Lean.Json.str originalText).compress
  let some structuredDecoded := decodedToolText? structuredSource |
    throw (IO.userError "numbered structural fixture did not decode")
  let structuredLayout := DecodedLayout.make structuredDecoded
  let heads := contextStructureHeads structuredSource (some structuredLayout)
  let branchOffset := (Lean.Json.str beforeBranch).compress.length - 1
  let structuredWindows := [(work.length + 1 + branchOffset) / 384]
  let structural := structureContextRanges structuredSource (work.length + 1) structuredWindows heads
  check (structural.head?.any fun head => head.2.start == 1)
    "a ranked branch lost its original enclosing function entry or miscounted JSON escape positions"
  let structuredOwner := OutcomeEdge.make (.text work) (.text structuredSource) [] (by simp) (by simp)
  let structuredSlice : TransportSlice := {members := [], visibleKeys := [], keys := [], text := structuredSource}
  let some (structuredKeys, structuredText) := contextualOwnerData [] structuredWindows structuredOwner
      "  ORIGINAL ALL LINK" [] structuredSlice 1536 |
    throw (IO.userError "structured production context did not render")
  check (structuredText.contains "owners[target.id()]" && structuredText.contains "target.isSpecial()" &&
      structuredText.contains "日本語🐣" && !structuredText.contains originalText)
    "bounded branch delivery omitted the entry prerequisite, altered Unicode, or expanded the whole source"
  let structuredRanges := deliveredEvidenceRanges structuredOwner structuredSource structuredKeys
  let demand := ownerContextDemand structuredOwner structuredWindows
  let some (demandKeys, _) := contextualOwnerData [] structuredWindows structuredOwner
      "  ORIGINAL ALL LINK" [] structuredSlice demand |
    throw (IO.userError "coherent entry demand did not render")
  let demandRanges := deliveredEvidenceRanges structuredOwner structuredSource demandKeys
  let required := coreContextRanges structuredSource (work.length + 1) structuredWindows ++ structural.map Prod.snd
  for range in required do
    let some view := decodedEvidenceUsing? structuredLayout range |
      throw (IO.userError "required structural fixture range did not decode")
    for point in [view.original.start, view.original.stop - 1] do
      check (demandRanges.any fun delivered => decide (delivered.covers point))
        "source-driven demand omitted the structural prerequisite or a meaning-nominated original cue"
  for range in structuredRanges do
    for other in structuredRanges do
      if range.start != other.start then
        check (range.stop ≤ other.start || other.stop ≤ range.start)
          "structural context retransmitted an accepted source position"
  -- A disjoint numbered read must not inherit the previous file/range's
  -- entry, even if its text looks like another branch in the same function.
  let gapPrefix := entry ++ numberedLine 500 "    // new disjoint read"
  let gapText := gapPrefix ++ "".intercalate ((List.range 100).map fun index =>
    numberedLine (501 + index) "    // independent source context")
  let gapSource := (Lean.Json.str gapText).compress
  let some gapDecoded := decodedToolText? gapSource |
    throw (IO.userError "disjoint structural fixture did not decode")
  let gapHeads := contextStructureHeads gapSource (some (DecodedLayout.make gapDecoded))
  let gapOffset := (Lean.Json.str gapPrefix).compress.length - 1
  check (((gapHeads.takeWhile (fun row => row.1 ≤ gapOffset)).getLast?).any (fun row => row.2.isNone) &&
      (structureContextRanges gapSource (work.length + 1) [8] gapHeads).isEmpty)
    "a numbered gap borrowed an unrelated earlier source header"
  -- The same production path must preserve ordinary MCP prose, without a
  -- function, Markdown heading, numbered lines, path suffix or query word.
  let proseStart := "別案件にのみ適用する記録。\n\n" ++
    "本記録の観測範囲は顧客ごとに独立しており、別の顧客には適用しません。\n"
  let prosePrefix := proseStart ++ "".intercalate ((List.range 220).map fun _ =>
    "同じ記録に含まれる経緯と観測結果の説明です。\n")
  let prose := prosePrefix ++ "今回の確認では再送しても請求は一回だけでした。\n" ++
    "".intercalate ((List.range 50).map fun _ => "この観測は記録時点の条件に限られます。\n")
  let proseSource := (Lean.Json.str prose).compress
  let proseWork := "mcp__records__read\n{\"record\":\"42\"}"
  let proseOwner := OutcomeEdge.make (.text proseWork) (.text proseSource) [] (by simp) (by simp)
  let proseSlice : TransportSlice := {members := [], visibleKeys := [], keys := [], text := proseSource}
  let proseOffset := (Lean.Json.str prosePrefix).compress.length - 1
  let proseWindows := [(proseWork.length + 1 + proseOffset) / 384]
  let some (_, proseContext) := contextualOwnerData [] proseWindows proseOwner "  ORIGINAL ALL LINK"
      [{workspace := "customer-records", files := [], uris := ["https://example.com/records/42"],
        complete := false}] proseSlice
      (ownerContextDemand proseOwner proseWindows) |
    throw (IO.userError "ordinary MCP prose context did not render")
  check (proseContext.contains "本記録の観測範囲" && proseContext.contains "請求は一回だけ" &&
      proseContext.contains "https://example.com/records/42" &&
      !proseContext.contains "別案件にのみ適用" && !proseContext.contains prose)
    "generic prose delivery omitted its scope, changed its URI or borrowed an unrelated paragraph"
  -- Overlap is handled against actually accepted ranges, not against
  -- merely planned ranges. The new tail of an overlapping context survives.
  let overlapHeads : List (Nat × EvidenceRange source) := [(0, original)]
  let overlapPlan := contextRangesWithStructure source (work.length + 1) [1] 16000 overlapHeads
  let structuredCore := coreContextRanges source (work.length + 1) [1]
  check ((overlapPlan.take structuredCore.length).map (fun range => (range.start, range.stop)) ==
      structuredCore.map (fun range => (range.start, range.stop)))
    "a heuristic source header displaced an already meaning-nominated original cue"
  let overlapSelected := overlapPlan.foldl (fun accepted range =>
    (range.subtractAll (accepted.views.map EvidenceView.range)).foldl
      (fun state novel => state.offer owner [] (.original novel)) accepted)
    (ContextSelection.empty : ContextSelection source 16000)
  for point in [:source.length + 1] do
    check ((overlapSelected.views.any fun view => decide (view.range.covers point)) ==
        (overlapPlan.any fun range => decide (range.covers point)))
      "accepted context subtraction discarded an overlapping range's new original tail"
  IO.println "PASS flexible context allocation: original coverage, priority, dense splitting, scattered clues, budgets, graph binding and non-repetition"

def testSemanticEvidenceDelivery : IO Unit := do
  let path := testRoot / "semantic-body.egg"
  let _ ← Persistence.create path
  let tool : ToolEvent := {
    name := "Bash", useId := "semantic-body-observation"
    input := r#"{"command":"cat src/driver.cc"}"#
    response := r#"{"output":"target\nselectPlatform(Architecture::A);\nforwardArguments(configuration);\nreturn Result::Accepted;"}"#
  }
  let unrelatedTool : ToolEvent := {tool with
    useId := "unrelated-body-observation"
    input := r#"{"command":"target"}"#
    response := r#"{"output":"target UNRELATED-TOOL-CACHE-INVENTORY"}"#}
  let supportingTool : ToolEvent := {tool with
    useId := "supporting-body-observation"
    input := r#"{"command":"cat src/arguments.cc"}"#
    response := r#"{"output":"RELATED-GRAPH-TOOL-DATA\ncheckArguments(configuration);\nobservedDecision(Platform::A);"}"#}
  let queryNeighborTool : ToolEvent := {tool with
    useId := "query-neighbor-observation"
    input := r#"{"command":"cat target"}"#
    response := r#"{"output":"target QUERY-HIT-NEIGHBOR\nrecordedSupportingDecision(configuration);"}"#}
  let prior : PendingTurn := {seed with
    sessionId := "semantic-body", turnId := "semantic-body-turn"
    prompt := "historical investigation", tools := [tool, supportingTool, queryNeighborTool]
    finalMessage := some "The prior investigation established platform selection."
    write := some path.toString, read := [path.toString]}
  let _ ← promote prior path
  let _ ← promote {prior with
    turnId := "unrelated-body-turn", prompt := "cache inventory maintenance"
    tools := [unrelatedTool], finalMessage := some "Separate cache inventory."} path
  let executable ← IO.appPath
  let selection : Config.Selection := {
    label := "semantic-body"
    semanticMatcher := some [executable.toString, "semantic-provider-fixture", "child-after-two-parents"]
    read := [{name := "body", path}], write := none, handoffChars := 24000}
  let some handoff ← automaticHandoff selection "target" [] false |
    throw (IO.userError "semantic child nomination was dropped by lexical matching")
  check (handoff.text.contains (canonicalJson tool.response) &&
    handoff.text.contains "forwardArguments(configuration)" &&
    handoff.completed == 0 && !handoff.blocksCurrent && handoff.coveredFragments.isEmpty &&
    handoff.sourceCheckpoints.isEmpty && handoff.localUnions == 0)
    s!"semantic evidence invalid: full={handoff.text.contains (canonicalJson tool.response)} content={handoff.text.contains "forwardArguments(configuration)"} blocks={handoff.blocksCurrent} completed={handoff.completed} unions={handoff.localUnions} reason={handoff.reason}"
  -- The primary response stays identical while an independently observed
  -- source-focus response changes. A packet memo must see both observations.
  IO.FS.withTempDir fun root => do
    IO.FS.writeFile (root / "primary-query") prior.prompt
    let focused := {selection with semanticMatcher := some [executable.toString,
      "observed-focus-provider", root.toString]}
    let some first ← automaticHandoff focused prior.prompt [] false |
      throw (IO.userError "first observed source focus lost its handoff")
    IO.FS.writeFile (root / "reverse") "reverse only the focus order"
    let some second ← automaticHandoff focused prior.prompt [] false |
      throw (IO.userError "changed source focus lost its handoff")
    let some third ← automaticHandoff focused prior.prompt [] false |
      throw (IO.userError "unchanged source focus could not reuse its handoff")
    check (first.text != second.text && second.text == third.text)
      "packet reuse ignored a changed independent source-focus observation"
    check ((← IO.FS.readFile (root / "focus-query")) == prior.finalMessage.get!)
      "graph focus used generic request wording instead of the original selected answer"
    check ((← IO.FS.readFile (root / "focus-calls")) == "3")
      "packet reuse skipped a fresh focus observation or repeated provider work"
    for result in [first, second, third] do
      check (result.text.contains (canonicalJson supportingTool.response) &&
        result.text.contains (canonicalJson queryNeighborTool.response) &&
        !result.text.contains "UNRELATED-TOOL-CACHE-INVENTORY" &&
        !result.blocksCurrent && result.completed == 0)
        "a focus-order change dropped non-hit graph data, mixed source families or gained control"
  let intrinsic ← automaticHandoff {selection with semanticMatcher := none} "target" [] false
  check (intrinsic.any (·.text.contains "UNRELATED-TOOL-CACHE-INVENTORY"))
    "the unrelated fixture does not reproduce intrinsic overlap transport"
  check (!handoff.text.contains "UNRELATED-TOOL-CACHE-INVENTORY" &&
      !handoff.text.contains (canonicalToolWork unrelatedTool))
    "shared query words admitted an owner in an unrelated source graph"
  check (handoff.text.contains (canonicalJson supportingTool.response) &&
      handoff.text.contains (canonicalToolWork supportingTool) &&
      handoff.text.contains "RELATED SOURCE GRAPH" && handoff.text.contains "STORED ALL" &&
      handoff.text.contains "SHOWN CHILD LINK WORK" && handoff.text.contains "SUPPORT OUTCOME")
    "semantic entry lost surrounding source graph or its complete non-nominated tool data"
  let negative := {selection with
    semanticMatcher := some [executable.toString, "semantic-provider-fixture", "empty"]}
  let some negativeHandoff ← automaticHandoff negative prior.prompt [] false |
    throw (IO.userError "empty semantic nominations vetoed an admitted original Work")
  check (negativeHandoff.text.contains prior.finalMessage.get! &&
      negativeHandoff.text.contains (canonicalJson tool.response) &&
      negativeHandoff.text.contains (canonicalJson supportingTool.response) &&
      negativeHandoff.text.contains (canonicalJson queryNeighborTool.response) &&
      negativeHandoff.text.contains "RELATED SOURCE GRAPH" &&
      !negativeHandoff.text.contains "UNRELATED-TOOL-CACHE-INVENTORY" &&
      !negativeHandoff.blocksCurrent)
    "negative semantic nominations lost intrinsic evidence, its original neighborhood, or source isolation"
  let positive := {selection with
    semanticMatcher := some [executable.toString, "semantic-provider-fixture", "retrieval"]}
  let some answered ← automaticHandoff positive prior.prompt [] false |
    throw (IO.userError "a nominated known answer disappeared in a repeated request")
  check (answered.text.contains prior.finalMessage.get! &&
      answered.text.contains (canonicalJson tool.response) &&
      answered.text.contains "STORED ALL" && !answered.blocksCurrent &&
      answered.sourceCheckpoints.isEmpty)
    "a kernel-unselected nominated answer was excluded from both data lanes or acquired control"
  let graph ← Persistence.load path
  let originalGraph := WorkGraph.fromValues graph.values
  let some queryNeighbor := originalGraph.outcomes.find? (fun owner =>
      owner.work == .text (canonicalToolWork queryNeighborTool)) |
    throw (IO.userError "query-hit neighbor lost its original graph owner")
  check (handoff.text.contains (canonicalJson queryNeighborTool.response) &&
      handoff.text.contains ("SUPPORT OUTCOME " ++ displayKey queryNeighbor.relation) &&
      !handoff.text.contains ("COVERED OUTCOME " ++ displayKey queryNeighbor.relation))
    "incidental query-word overlap bypassed the surrounding evidence lane"
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer originalGraph
  let nominated := corpus.candidates.filter (fun candidate =>
    candidate.edge.work == .text prior.prompt || candidate.edge.work == .text (canonicalToolWork tool))
    |>.map (·.edge.relation) |>.reverse
  let rows := Matcher.findIn LogicalText.logicalNormalizer Quotient.literal corpus
    (.text "target") "target" none {related := nominated} false
  let selected := rows.filter (·.retrieved) |>.map fun matched =>
    ({applicability := matched.applicability, matched} : Selected)
  check (selected.length == 2 && selected.all fun item =>
    item.handoffOutcome == item.matched.edge.outcome && item.applicability == .advisory)
    "meaning-based nominations did not keep both original observed results"
  let ordered := transportOrder false nominated selected
  let allSelected := rows.filter (·.automatic) |>.map fun matched =>
    ({applicability := matched.applicability, matched} : Selected)
  let admitted := transportSelection true nominated allSelected originalGraph.all []
  check (!(rows.any (fun item => item.edge.work == .text (canonicalToolWork supportingTool))) &&
      rows.any (fun item => item.edge.work == .text (canonicalToolWork queryNeighborTool)) &&
      !(admitted.any (fun item => readable item.matched.edge.outcome == canonicalJson unrelatedTool.response)) &&
      selected.all (fun item => admitted.any (fun kept => graphKey kept == graphKey item)) &&
      (transportSelection false nominated allSelected).map graphKey == allSelected.map graphKey)
    "neighbor fixture acquired lexical admission, admitted a disconnected hit, or changed native control"
  check (ordered.head?.map (·.matched.edge.relation) == nominated.head? &&
      (transportOrder true nominated selected).map graphKey == (supportFirst selected).map graphKey)
    "budgeting ignored semantic nomination order or changed native control order"
  let slices := transportSlices [] ordered
  let some first := slices.head? | throw (IO.userError "semantic evidence has no graph slice")
  let fitted := fitWholeSlices first.text.length (·.text) slices
  check (fitted.head?.map (·.text) == some first.text)
    "the first nominated result was dropped although its whole body fit"
  let alternatives := [("ORIGINAL-COMPLETE-BODY", "original-context"), ("next", "n")]
  let entry := Value.text "nominated-entry"
  let neighbor := Value.text "connected-neighbor"
  let other := Value.text "unranked-admitted-owner"
  let choices := [(entry, ("entry-body", "entry-context")),
    (neighbor, ("neighbor-body", "neighbor-context")), (other, ("other-body", "other-context"))]
  check ((rankEvidenceChoices [neighbor, entry] choices).map Prod.fst == [neighbor, entry, other] &&
      (rankEvidenceChoices [entry, neighbor] choices).map Prod.fst == [entry, neighbor, other] &&
      rankEvidenceChoices [] choices == choices)
    "fixed entry/neighbor allocation overrode numerical rank, lost an owner or changed stable unranked order"
  let familyRoots := [Value.text prior.prompt, Value.text "cache inventory maintenance"]
  let supportingWork := Value.text (canonicalToolWork supportingTool)
  let unrelatedWork := Value.text (canonicalToolWork unrelatedTool)
  check (sourceFamilyPriority familyRoots originalGraph.all supportingWork == 0 &&
      sourceFamilyPriority familyRoots originalGraph.all unrelatedWork == 1 &&
      sourceFamilyPriority familyRoots originalGraph.all (.text "never observed") == 2 &&
      (rankEvidenceChoices [other, entry, neighbor] choices
        [(neighbor, 0), (entry, 1), (other, 2)]).map Prod.fst == [neighbor, entry, other] &&
      (rankEvidenceChoices [entry, other, neighbor] choices
        [(entry, 0), (neighbor, 0), (other, 1)]).map Prod.fst == [entry, neighbor, other])
    "an original task's tool evidence lost its family priority or numerical order, or an unrelated owner acquired that priority"
  let framing : Handoff := {pendingSearch with
    sourceUses := [{owner := String.ofList (List.replicate 80 '源'), references := [], completed := false},
      {owner := "v1", references := [], completed := false}]}
  let status := renderOwnerSourceStatus framing {workspace := testRoot, deadline := 0} {} 1024 360
  check (status.text.utf8ByteSize ≤ 360 && status.text.length ≤ 1024 &&
      status.text.contains "GRAPH v1" && !status.text.contains (String.ofList (List.replicate 80 '源')) &&
      (sourceFrame? 32 16 "SOURCE\n日本").any (fun frame => frame.text == "SOURCE\n日本") &&
      (sourceFrame? 32 8 "SOURCE\n日本").isNone)
    "source status framing exceeded the UTF-8 budget, clipped a row, lost the smaller row, or accepted character-only bounds"
  check (fitPreferredSlices 23 id alternatives == ["ORIGINAL-COMPLETE-BODY", "n"] &&
      fitPreferredSlices 16 id alternatives == ["original-context"] &&
      fitPreferredSlices 3 id alternatives == ["n"])
    "complete-owner preference, bounded fallback or continued fitting regressed"
  let some selectedFirst := selected.head? | throw (IO.userError "semantic evidence has no selected owner")
  let association := Selection.residual (.text "target") [selectedFirst.matched.projectedEdge]
  check ((renderSelectionTree association [selectedFirst.matched.projectedEdge.relation]).contains "OPEN target" &&
      (renderSelectionTree association [selectedFirst.matched.projectedEdge.relation] true).contains "RELATED WORK target" &&
      !(renderSelectionTree association [selectedFirst.matched.projectedEdge.relation] true).contains "OPEN target" &&
      handoff.text.contains "Graph Work/All nodes describe associations, not extra requirements" &&
      handoff.text.contains "do not investigate additional examples unless requested" &&
      handoff.text.contains "Unverified does not mean changed" &&
      handoff.text.contains "an evidence gap to report, not a reason to retry")
    "a memory association was presented as another required investigation"
  let ab : UnionEdge := ⟨.text "entry-a", .text "alias-b", .run (.text "request"), by intro _; rfl⟩
  let bc : UnionEdge := ⟨ab.right, .text "support-c", ab.scope, by intro _; rfl⟩
  let cycle := [ab, bc, bc.swap, ab.swap]
  let reached := sourceNeighborhood [ab.left] [] cycle
  check (reached.map (·.work) == [ab.left, ab.right, bc.right] &&
      (sourceNeighborhood [] originalGraph.all cycle).isEmpty &&
      !(reached.any fun row => row.work == .text "disconnected"))
    "source graph walk lost transitive Union support, repeated a cycle, or invented a root"
  for slice in slices do
    for item in slice.members do
      check (slice.text.contains ("OUTCOME " ++ displayKey item.matched.projectedEdge.relation ++
        " -> EVIDENCE " ++ displayKey (transportEvidenceFor item.matched.edge slice.members item)))
        "a selected graph relation did not bind to its delivered evidence body"
  -- The neighborhood must cross original All frames even when neither the
  -- intermediate Work nor the final tool is a lexical/semantic search hit.
  let nestedTool : ToolEvent := {supportingTool with
    useId := "nested-body-observation"
    input := r#"{"command":"cat src/recorded-policy.cc"}"#
    response := r#"{"output":"NESTED-GRAPH-TOOL-DATA\nrecordedPolicy(configuration);\nrecordedDecision(Platform::A);"}"#}
  let bridge := Value.text "recorded source association connector"
  let parent := Value.text (canonicalToolWork supportingTool)
  let leaf := Value.text (canonicalToolWork nestedTool)
  let firstLink ← if valid : [bridge] ≠ [] ∧ parent ∉ [bridge] then
      pure (AllEdge.make parent [bridge] valid.1 valid.2)
    else throw (IO.userError "invalid nested source connector")
  let secondLink ← if valid : [leaf] ≠ [] ∧ bridge ∉ [leaf] then
      pure (AllEdge.make bridge [leaf] valid.1 valid.2)
    else throw (IO.userError "invalid nested source leaf")
  let nestedOwner := OutcomeEdge.make leaf (.text (canonicalJson nestedTool.response)) [] (by simp) (by simp)
  let _ ← DB.PageMap.withWriter (← DB.PageMap.pin path) fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← [firstLink.relation, secondLink.relation, nestedOwner.relation].mapM intern.root
    Persistence.Store.writeChange writer ⟨ids, [], false⟩
  runtimeCache.set {}
  let nestedSelection := {selection with
    semanticMatcher := some [executable.toString, "semantic-provider-fixture", "retrieval"]}
  let some nestedHandoff ← automaticHandoff nestedSelection "target" [] false |
    throw (IO.userError "nested source entry disappeared")
  IO.FS.writeFile (testRoot / "nested-source-handoff.txt") nestedHandoff.text
  check (nestedHandoff.text.contains (canonicalJson nestedTool.response) &&
      nestedHandoff.text.contains (canonicalToolWork nestedTool) &&
      nestedHandoff.text.contains ("SUPPORT OUTCOME " ++ displayKey nestedOwner.relation) &&
      !nestedHandoff.text.contains ("SEARCH ENTRY OUTCOME " ++ displayKey nestedOwner.relation) &&
      nestedHandoff.text.contains ("STORED ALL " ++ displayKey firstLink.relation) &&
      nestedHandoff.text.contains ("STORED ALL " ++ displayKey secondLink.relation) &&
      nestedHandoff.text.contains ("SHOWN CHILD LINK WORK " ++ displayKey bridge) &&
      !nestedHandoff.text.contains "UNRELATED-TOOL-CACHE-INVENTORY" &&
      !nestedHandoff.blocksCurrent)
    "nested graph traversal lost complete original tool data, its path or source isolation"
  IO.println "PASS semantic tool payload, relevance order, whole-owner budget, and graph-to-body bindings"
  IO.println "PASS semantic entry delivers surrounding All graph and original tool evidence, excludes disconnected overlap"

  -- Reproduce the actual failure: a nominated tool is fully saved, but its
  -- complete original output cannot fit the smaller experiment allowance.
  let largePath := testRoot / "semantic-large-body.egg"
  let _ ← Persistence.create largePath
  let output := "target\n" ++ "\n".intercalate ((List.range 800).map fun line =>
    s!"{line}: 選択済み引数とツールチェーンの根拠🐣 selectPlatform(configuration); forwardArguments(configuration);")
  let largeTool : ToolEvent := {tool with
    useId := "semantic-large-observation"
    response := (Lean.Json.mkObj [("output", .str output)]).compress}
  let largeTurn : PendingTurn := {prior with
    sessionId := "semantic-large", turnId := "semantic-large-turn", tools := [largeTool],
    read := [largePath.toString], write := some largePath.toString}
  let _ ← promote largeTurn largePath
  let base := {selection with
    read := [{name := "large", path := largePath}]
    semanticMatcher := some [executable.toString, "semantic-provider-fixture", "child"]}
  let small ← automaticHandoff base "target" [] false
  check (!(small.any fun message => message.text.contains (canonicalJson largeTool.response)))
    "large-body fixture no longer reproduces whole-owner exclusion at 24000 characters"
  let some large ← automaticHandoff {base with handoffChars := 160000} "target" [] false |
    throw (IO.userError "expanded delivery dropped a nominated large tool")
  check (large.text.contains (canonicalToolWork largeTool) &&
    large.text.contains (canonicalJson largeTool.response) &&
    large.text.length ≤ 160000 && large.text.utf8ByteSize > 48000 &&
    large.text.utf8ByteSize ≤ 640000 &&
    !large.blocksCurrent && large.completed == 0 && large.localUnions == 0)
    "expanded delivery truncated tool evidence, exceeded transport bounds, or invented authority"
  check ((← automaticHandoff {base with handoffChars := 160000} "target"
      large.deliveredGraphs false).isNone)
    "a fully delivered large tool was sent again in the same context epoch"
  let contextual := {base with
    handoffChars := 24000
    semanticMatcher := some [executable.toString, "semantic-provider-fixture", "child-context"]}
  let some completeContext ← automaticHandoff {contextual with handoffChars := 160000}
      "target" [] false |
    throw (IO.userError "needed meaning-ranked context was omitted")
  check (!completeContext.text.contains (canonicalJson largeTool.response) &&
      completeContext.text.contains (canonicalToolWork largeTool) &&
      completeContext.deliveredGraphs.countP (·.startsWith "e:") ≥ 3 &&
      !completeContext.blocksCurrent && completeContext.completed == 0 &&
      (← automaticHandoff {contextual with handoffChars := 160000} "target"
        completeContext.deliveredGraphs false).isNone)
    "spare capacity expanded needed contexts to a whole body, gained authority, or redelivered evidence"
  let some context ← automaticHandoff contextual "target" [] false |
    throw (IO.userError "meaning-ranked result context was omitted")
  let stored := canonicalJson largeTool.response
  let workChars := (canonicalToolWork largeTool).length + 1
  let originalOwner := OutcomeEdge.make (.text (canonicalToolWork largeTool)) (.text stored)
    [nativeOccurrence (.text largeTurn.sessionId) (.text largeTurn.turnId) largeTool]
    (by simp) (by simp [maxOutcomeObservations])
  let ranges := deliveredEvidenceRanges originalOwner stored context.deliveredGraphs
  check (!ranges.isEmpty) "context receipts have no exact original source owner"
  for index in [3, 13, 27] do
    let center := index * 384 + 256 - workChars
    for point in [center - 128, center, center + 128] do
      check (ranges.any fun range => decide (range.covers point))
        "flexible context omitted the middle of an original nominated meaning cue"
  check (context.text.contains "forwardArguments(configuration)" &&
      context.text.contains (canonicalToolWork largeTool) &&
      context.text.contains "ORIGINAL CHARS" &&
      context.text.contains "-> EVIDENCE")
    "partial contexts lost source neighbors, the command or the graph binding"
  check (context.text.contains largeTurn.finalMessage.get!)
    "a nominated answer was shortened by tool-context rendering"
  check (
      !context.text.contains stored &&
      context.text.length ≤ contextual.handoffChars)
    "partial contexts included an entire oversized original result"
  check (!context.blocksCurrent && context.completed == 0 && context.localUnions == 0)
    "partial tool contexts invented native completion or Union authority"
  check (context.deliveredGraphs.countP (·.startsWith "e:") ≥ 3)
    "partial contexts lost distinct source-range receipts"
  -- A flexible subsequent packet may fit another original interval. It must
  -- add fresh positions and retain its advisory status, never repeat bytes.
  if let some next ← automaticHandoff contextual "target" context.deliveredGraphs false then
    let fresh := deliveredEvidenceRanges originalOwner stored next.deliveredGraphs
    check (!fresh.isEmpty && !next.blocksCurrent && next.completed == 0 && next.localUnions == 0 &&
      next.text.length ≤ contextual.handoffChars)
      "another flexible packet had no original progress, exceeded its bound or gained authority"
    for part in fresh do
      check (ranges.all fun prior => part.stop ≤ prior.start || prior.stop ≤ part.start)
        "a flexible subsequent packet repeated previously delivered source positions"
  -- Every returned position must have a typed owner in this request. A bad
  -- final response is rejected even when it never asked to read source bytes.
  let document : Persistence.Store.SearchDocument := {
    owner := 3, work := 2, windows := ["zero", "one"]}
  let valid := SemanticMatcher.indexedNominations [document]
    {related := [0], ranked := [0], evidence := [⟨0, [1, 0]⟩]}
  check (valid.toOption.any fun choices => choices.map (·.indices) == [[1, 0]])
    "typed nomination reordered meaning-ranked positions"
  for indices in [[2], [0, 0], List.range 33] do
    check ((SemanticMatcher.indexedNominations [document]
      {related := [0], ranked := [0], evidence := [⟨0, indices⟩]}).toOption.isNone)
      "foreign, repeated or unbounded evidence positions acquired a graph owner"
  let directory := [document, {document with owner := 4}, {document with owner := 5}]
  check ((SemanticMatcher.IndexedOrder.check? directory [2, 0, 1]).isSome)
    "a complete numerical neighborhood order was rejected"
  for indices in [[0, 1], [0, 1, 3], [0, 0, 2], [0, 1, 2, 2]] do
    check ((SemanticMatcher.IndexedOrder.check? directory indices).isNone)
      "a missing, foreign, repeated or oversized ranking acquired corpus ownership"
  check ((Persistence.Store.rankSupportDocuments directory [5, 3, 4]).map (·.owner) == [5, 3, 4])
    "neighbor bodies were read in save order instead of the current evidence order"
  let prior : IndexedSemanticNominations := {durable := [3], durableRanking := [3, 4, 5]}
  check (prior.memoIdentity != {prior with durableRanking := [3, 5, 4]}.memoIdentity)
    "changed peripheral ranking reused an old handoff dependency identity"
  IO.println "PASS typed meaning-ranked original contexts, adjacent evidence, graph ownership and non-repetition"
  let manifest ← IO.ofExcept (Lean.Json.parse Eggshell.Install.hooksManifest)
  let hooks := manifest.getObjValD "hooks"
  for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse"] do
    let entries ← IO.ofExcept (Lean.fromJson? (hooks.getObjValD event) : Except String (List Lean.Json))
    for entry in entries do
      let commands ← IO.ofExcept (entry.getObjValAs? (List Lean.Json) "hooks")
      for command in commands do
        check (command.getObjValD "additionalContextLimit" == Lean.toJson Config.nativeHandoffBytes)
          "installed hook limit differs from the public transport bound"
  check (({name := "default"} : Config.Profile).handoffChars == 120000)
    "default handoff budget differs from the public configuration"
  check (Config.nativeHandoffBytes == 128000)
    "native fitting budget differs from the installed transport limit"
  let some byteLimited ← automaticHandoff
      {contextual with handoffChars := 120000, handoffBytes := some Config.nativeHandoffBytes}
      "target" [] false |
    throw (IO.userError "UTF-8 transport fitting discarded all owned contexts")
  check (byteLimited.text.utf8ByteSize ≤ Config.nativeHandoffBytes &&
      byteLimited.text.contains (canonicalToolWork largeTool) &&
      byteLimited.text.contains "ORIGINAL CHARS" &&
      byteLimited.deliveredGraphs.any (·.startsWith "e:") &&
      !byteLimited.blocksCurrent && byteLimited.completed == 0)
    "native byte fitting truncated an original tool, lost its ownership or invented authority"
  check ((byteLimited.text.splitOn "ORIGINAL CHARS [").length ≥ 4 &&
      !byteLimited.text.contains (canonicalJson largeTool.response))
    "flexible native allowance lost a nominated context or expanded to the whole original tool body"
  let peripheral := {contextual with
    handoffChars := 160000
    semanticMatcher := some [executable.toString, "semantic-provider-fixture", "parent-context"]}
  let some peripheralContext ← automaticHandoff peripheral "target" [] false |
    throw (IO.userError "a non-entry source owner lost its needed context")
  check (peripheralContext.text.contains "SUPPORT OUTCOME" &&
      peripheralContext.text.contains (canonicalToolWork largeTool) &&
      peripheralContext.text.contains "STORED ALL" &&
      peripheralContext.text.contains "ORIGINAL CHARS" &&
      peripheralContext.deliveredGraphs.countP (·.startsWith "e:") ≥ 3 &&
      !peripheralContext.text.contains (canonicalJson largeTool.response) &&
      !peripheralContext.blocksCurrent && peripheralContext.completed == 0 &&
      peripheralContext.sourceCheckpoints.isEmpty &&
      (← automaticHandoff peripheral "target" peripheralContext.deliveredGraphs false).isNone)
    "surrounding context lost original graph paths, expanded to a whole body, gained authority or repeated"
  let some peripheralExpanded ← automaticHandoff {peripheral with handoffChars := 320000}
      "target" [] false | throw (IO.userError "expanded graph context vanished")
  let expandedRanges := deliveredEvidenceRanges originalOwner stored peripheralExpanded.deliveredGraphs
  for index in [3, 13, 27] do
    let center := index * 384 + 256 - workChars
    check (expandedRanges.any fun range => decide (range.covers center))
      "a larger graph-neighbor allowance lost an original meaning-selected cue"
  check (!peripheralExpanded.text.contains stored && !peripheralExpanded.blocksCurrent &&
      peripheralExpanded.completed == 0 && peripheralExpanded.sourceCheckpoints.isEmpty)
    "expanding a neighbor's context included the whole body or changed advisory evidence into control"
  IO.println "PASS public delivery limits, Unicode tool data, advisory authority, and non-repetition"

  let plain := "target\n" ++ "\n".intercalate ((List.range 350).map fun index =>
    s!"{index}\tconst char *s = \"\\n literal, 日本語🐣\"; forwardArguments(configuration);")
  let encoded := (Lean.Json.str plain).compress
  let some decoded := decodedToolText? encoded |
    throw (IO.userError "canonical native string could not be decoded")
  check (decoded.text == plain && (Lean.Json.str decoded.text).compress == encoded &&
      (decodedToolText? r#""\u0061""#).isNone &&
      (decodedToolText? largeTool.response).isNone)
    "string display accepted a changed encoding or erased object fields"
  for center in [0, 1030, 6147, 16385, encoded.length] do
    let some requested := EvidenceRange.around? encoded center |
      throw (IO.userError "readable evidence fixture has no original range")
    let .decoded evidence := EvidenceView.fromRange (some decoded) requested |
      throw (IO.userError "canonical JSON token boundaries failed context decoding")
    check (requested.start ≤ evidence.original.start && evidence.original.stop ≤ requested.stop &&
        evidence.content.text.contains "\\n literal" && evidence.content.text.contains "日本語🐣" &&
        evidence.content.text.contains "\n" &&
        encodedTextBody evidence.content.text == evidence.original.text)
      "readable context changed literal escapes, Unicode, source bytes, or selected range"
  let readablePath := testRoot / "semantic-readable-body.egg"
  let _ ← Persistence.create readablePath
  let readableTurn := {largeTurn with
    sessionId := "semantic-readable", turnId := "semantic-readable-turn"
    write := some readablePath.toString, read := [readablePath.toString]
    tools := [{tool with response := encoded, useId := "readable-body-observation"}]}
  let _ ← promote readableTurn readablePath
  let readableSelection := {contextual with read := [{name := "readable", path := readablePath}]}
  let some readableContext ← automaticHandoff readableSelection "target" [] false |
    throw (IO.userError "readable tool context was omitted")
  let readableAgain ← automaticHandoff readableSelection "target" readableContext.deliveredGraphs false
  check (readableContext.text.contains "DECODED JSON STRING DATA" &&
      readableContext.text.contains "\\n literal" &&
      readableContext.text.contains "日本語🐣" &&
      readableContext.deliveredGraphs.countP (·.startsWith "e:") ≥ 3 &&
      readableAgain.isNone)
    s!"decoded context lost data, claimed whole delivery, or was redelivered: decoded={readableContext.text.contains "DECODED JSON STRING DATA"} literal={readableContext.text.contains "\\n literal"} unicode={readableContext.text.contains "日本語🐣"} ranges={readableContext.deliveredGraphs.countP (·.startsWith "e:")}"
  let some readableFull ← automaticHandoff
      {readableSelection with
        handoffChars := 160000
        semanticMatcher := base.semanticMatcher} "target" [] false |
    throw (IO.userError "readable complete tool was omitted")
  check (readableFull.text.contains plain && !readableFull.text.contains encoded &&
      !readableFull.blocksCurrent && readableFull.completed == 0)
    "a full native string retained JSON escapes or gained completion authority"
  IO.println "PASS decoded original tool data, exact reencoding, occurrence ownership and non-repetition"

def testWholeSliceBudget : IO Unit := do
  testSemanticEvidenceDelivery
  let manualPath := testRoot / "manual-evidence-gap.egg"
  let _ ← Persistence.create manualPath
  let _ ← promote seed manualPath
  let question := "Determine the deployed incident setting; the production evidence is unavailable."
  let remainder := HandoffRemainder.value question
  check (HandoffRemainder.marker.contains "mark the conclusion UNRESOLVED, and stop" &&
    HandoffRemainder.marker.contains "Resume only after new evidence" &&
    HandoffRemainder.marker.contains "Do not reread evidence for line numbers or citation formatting" &&
    !HandoffRemainder.marker.contains "missing required evidence")
    "the stored open Work instructed repeated checks solely because evidence was missing"
  let openTree := renderSelectionTree (.residual remainder []) []
  check (HandoffRemainder.isValue remainder && openTree.contains question &&
    !openTree.contains "missing required evidence" && !openTree.contains "recheck only")
    "an open leaf repeated obsolete recheck guidance or hid the unresolved request"
  check (treeWork (.text question) == treeWork remainder)
    "remainder display invented different work instead of showing the request"
  let manual ← manualHandoff {
    label := "manual-evidence-gap"
    semanticMatcher := none
    read := [{ name := "work", path := manualPath }]
    write := none
    handoffChars := 120000
  } question [valueKey (.text seed.prompt)]
  check (manual.any fun handoff => handoff.text.contains evidenceGapGuidance &&
    handoff.text.contains "OPEN means unresolved, not an instruction to retry unavailable evidence" &&
    handoff.text.contains "recorded source without line numbers when they are unavailable" &&
    handoff.completed == 0 && !handoff.blocksCurrent)
    "manual handoff omitted the stopping rule or treated selected data as completed evidence"
  let slices := ["slice-too-large", "ok"]
  let fitted := fitWholeSlices 2 id slices
  check (fitted = ["ok"])
    "handoff budget truncated a semantic slice instead of omitting it whole"
    let empty ← automaticHandoff {
      label := "off"
      semanticMatcher := none
      read := []
      write := none
      handoffChars := 120000
    } "unmatched prompt" [] false
  check empty.isNone
    "an empty authority set produced invented handoff context"
  IO.println "PASS handoff preserves whole graph slices and invents no empty context"

def concurrentSeed (name command : String) : PendingTurn := {
  seed with
  sessionId := "session-" ++ name
  turnId := "turn-" ++ name
  prompt := "parallel work " ++ name
  tools := [{
    name := "shell"
    useId := "tool-" ++ name
    input := Lean.Json.mkObj [("command", command)] |>.compress
    response := Lean.Json.mkObj [("output", name)] |>.compress
  }]
  finalMessage := some ("finished " ++ name)
}

def waitPromotion (task : Task (Except IO.Error CommittedPromotion)) : IO Unit := do
  match ← IO.wait task with
  | .ok _ => pure ()
  | .error error => throw error

def testConcurrentPromotion : IO Unit := do
  let _ ← Persistence.create concurrentEgg
  let first ← IO.asTask (promote (concurrentSeed "alpha" "rg alpha") concurrentEgg)
    .dedicated
  let second ← IO.asTask (promote (concurrentSeed "beta" "rg beta") concurrentEgg)
    .dedicated
  waitPromotion first
  waitPromotion second
  let graph ← Persistence.load concurrentEgg
  let nodes := graph.values.flatMap Value.nodes
  check (graph.revision = 2) "concurrent sessions lost an atomic promotion"
  check (nodes.contains (.text "parallel work alpha"))
    "first concurrent session disappeared"
  check (nodes.contains (.text "parallel work beta"))
    "second concurrent session disappeared"
  IO.println "PASS concurrent sessions serialize one .egg without lost work"

def testUnionSuppression : IO Unit := do
  let _ ← Persistence.create unionEgg
  let left := Value.text "inspect wallclock"
  let right := Value.text "inspect realtime"
  let _ ← Plugin.persistUnion unionEgg left right
  let first ← Persistence.load unionEgg
  let _ ← Plugin.persistUnion unionEgg right left
  let second ← Persistence.load unionEgg
  check (first.unions.length = 1) "first persistent Union was not stored"
  check (second.unions.length = 1) "redundant persistent Union was stored"
  check (second.revision = first.revision) "redundant Union advanced authority revision"
  let persistent ← match second.unions with
    | [persistent] => pure persistent
    | _ => throw (IO.userError "expected one persistent Union")
  let key := Plugin.unionKey persistent.edge
  let removed ← Plugin.splitPersistentUnion unionEgg key
  let split ← Persistence.load unionEgg
  check (removed.samePair left right) "split removed the wrong Union"
  check split.unions.isEmpty "split retained its named Union"
  check (split.values = second.values) "split changed graph data"
  check (split.revision = second.revision + 1) "split did not advance authority revision"
  IO.println "PASS persistent Union suppresses duplicates and supports exact correction"

def testUnionDeltaIO : IO Unit := do
  let root := testRoot / "union-delta.egg"
  let _ ← Persistence.create root
  let unrelated := Value.atom ((String.ofList (List.replicate (512 * 1024) 'z')).toUTF8)
  let _ ← Persistence.appendPrepared root fun graph =>
    pure ((Transaction.begin graph).stageValue unrelated (Relation.atom_wellFormed _), ())
  let initial ← DB.PageMap.pin root
  let (_, _, _) ← DB.PageMap.withWriter initial fun writer =>
    Persistence.Store.putNat writer "unions" 1000000000
  let left := Value.text "inspect wallclock"
  let right := Value.text "inspect realtime"
  let otherLeft := Value.text "inspect parser"
  let otherRight := Value.text "inspect syntax"
  let target ← Plugin.persistUnion root left right
  let retained ← Plugin.persistUnion root otherLeft otherRight
  let before ← DB.PageMap.pin root
  let graph ← Persistence.load root
  check (graph.values = [unrelated] && graph.unions.length = 2)
    "delta Union addition changed unrelated stored roots"
  let directories ← Persistence.Store.unionDirectory before
  check (directories.map Prod.fst = [1000000000, 1000000001])
    "sparse Union directory lost allocation order"
  let _ ← Plugin.persistUnion root right left
  check ((← DB.PageMap.pin root).head = before.head)
    "reverse-pair replay republished a Union or locator"

  -- An unrelated bad payload makes a full materialization fail. Editing an
  -- existing Union must still read only its own certified endpoints/indexes.
  let ids ← Persistence.Store.getIds before.get ("hash:" ++ toString (hash unrelated))
  let id ← match ids with
    | [id] => pure id
    | _ => throw (IO.userError "opaque owner fixture has an ambiguous digest")
  let bodyKey := Persistence.Store.key (Persistence.Store.key "body" id) 0
  let some descriptor ← before.get bodyKey |
    throw (IO.userError "opaque owner lost its body descriptor")
  let blob ← IO.ofExcept (DB.PageMap.decodeBlob descriptor)
  let broken := { blob with checksum := DB.PageMap.digest "injected corruption".toUTF8 }
  let (_, _, _) ← DB.PageMap.withWriter before fun writer =>
    writer.put bodyKey (some (DB.PageMap.blobCodec.encode broken).toByteArray)
  let failed ← try let _ ← Persistence.load root; pure false catch _ => pure true
  check failed "unrelated payload corruption did not make the full-read oracle fail"
  let corrupted ← DB.PageMap.pin root
  let some located ← Persistence.Store.locateUnion? corrupted (Plugin.unionKey target) |
    throw (IO.userError "indexed Union disappeared behind unrelated corrupt data")
  let readBytes ← corrupted.readBytes.get
  check (located.edge.samePair left right && readBytes < 128 * 1024)
    "a Union locator hydrated unrelated root payloads"
  let started ← IO.monoNanosNow
  let removed ← Plugin.splitPersistentUnion root (Plugin.unionKey target)
  let splitNs := (← IO.monoNanosNow) - started
  let split ← DB.PageMap.pin root
  let splitBytes := split.head.bytes - corrupted.head.bytes
  check (removed.samePair left right && splitBytes < 64 * 1024)
    "Union correction rewrote unrelated body or metadata"
  check ((← Persistence.Store.unionPairs split).length = 1 &&
    (← Persistence.Store.locateUnion? split (Plugin.unionKey target)).isNone &&
    (← Persistence.Store.locateUnion? split (Plugin.unionKey retained)).isSome)
    "Union correction lost another relation or retained its named locator"
  let change ← Persistence.Store.readChange split split.head.revision
  check (change.added.isEmpty && change.removed.isEmpty && change.unionsChanged)
    "Union correction journal changed roots or concealed changed equality"
  let failed ← try
    let _ ← Plugin.splitPersistentUnion root (Plugin.unionKey target)
    pure false
    catch _ => pure true
  check (failed && (← DB.PageMap.pin root).head = split.head)
    "repeated Union correction mutated a retired relation"
  check ((← Persistence.Store.unionPairs before).length = 2)
    "a pinned Union read mixed newer relation deletion"
  let (_, _, _) ← DB.PageMap.withWriter split fun writer =>
    writer.put bodyKey (some descriptor)
  let restored ← Persistence.load root
  check (restored.values = graph.values && restored.unions.length = 1 &&
    restored.unions.head?.any (·.edge.samePair otherLeft otherRight))
    "selective Union correction changed a root or the remaining equality"

  -- The actual correction publication replays to the full inspection oracle;
  -- no retired pair survives the change stream into Matcher/saturation.
  let _ ← Plugin.persistUnion root left right
  let checkpoint ← DB.PageMap.pin root
  let previous ← Persistence.load root
  let some earlierRetained ← Persistence.Store.locateUnion? checkpoint (Plugin.unionKey retained) |
    throw (IO.userError "retained Union was not locatable before a new publication")
  let _ ← Plugin.splitPersistentUnion root (Plugin.unionKey target)
  let current ← DB.PageMap.pin root
  let rejected ← try
    let _ ← DB.PageMap.withWriter current fun writer =>
      Persistence.Store.removeUnion writer earlierRetained
    pure false
    catch _ => pure true
  check (rejected && (← DB.PageMap.pin root).head = current.head &&
    (← Persistence.Store.locateUnion? current (Plugin.unionKey retained)).isSome)
    "a stale publication capability changed an otherwise still-live Union"
  let replayed ← Persistence.Store.revise current checkpoint.head previous
  let full ← Persistence.load root
  check (replayed.values = full.values && replayed.unions.map (·.edge) = full.unions.map (·.edge))
    "selective Union retraction disagreed with the full graph oracle"
  IO.println ((Lean.Json.mkObj [("kind", .str "union_delta"),
    ("unrelated_body_bytes", Lean.toJson (512 * 1024 : Nat)),
    ("historical_union_allocation", Lean.toJson (1000000000 : Nat)),
    ("locator_read_bytes", Lean.toJson readBytes), ("split_write_bytes", Lean.toJson splitBytes),
    ("split_ns", Lean.toJson splitNs)]).compress)
  IO.println "PASS selective Union add/correction, sparse directory, no unrelated hydration, old snapshot and full replay oracle"

def testConfig : IO Unit := do
  let parsed ← Config.parse (testRoot / "config.toml") r#"
default = "work"
semantic_matcher = ["cpu-matcher", "--model", "tiny"]
[eggs]
project = "memory#shared.egg" # comment outside the quoted path
[profiles.work]
read = ["project",]
write = "project"
local_union = false
"#
  check parsed.defaultWasSet "explicit default profile was lost"
  check (parsed.semanticMatcher = some ["cpu-matcher", "--model", "tiny"])
    "configured semantic matcher command was not preserved"
  check parsed.semanticMatcherWasSet
    "explicit semantic matcher was mistaken for the built-in default"
  check (match Config.admitProject parsed with | .error _ => true | .ok _ => false)
    "project config was allowed to execute a custom semantic matcher"
  let work ← IO.ofExcept (Config.resolve parsed "work")
  check (!work.localUnion)
    "retrieval-only profile did not disable run-local equality"
  check (parsed.eggs.head?.map (·.path.toString.endsWith "memory#shared.egg") = some true)
    "quoted # was parsed as a TOML comment"
  let base : Config.Config := {
    source := "global.toml"
    defaultProfile := "research"
    defaultWasSet := true
  }
  let overlay : Config.Config := {
    source := "project.toml"
    defaultProfile := "work"
    defaultWasSet := true
  }
  check ((Config.merge base overlay).defaultProfile = "work")
    "explicit project default=work did not override global default"
  let automatic ← Config.parse (testRoot / "automatic.toml") r#"
[eggs]
project = "project.egg"
[profiles.work]
read = ["project"]
"#
  check (!automatic.semanticMatcherWasSet && automatic.semanticMatcher.isNone)
    "omitted semantic matcher did not retain built-in-default intent"
  let disabled ← Config.parse (testRoot / "disabled.toml") r#"
semantic_matcher = false
[eggs]
project = "project.egg"
[profiles.work]
read = ["project"]
"#
  check (disabled.semanticMatcherWasSet && disabled.semanticMatcher.isNone)
    "explicit semantic matcher opt-out was not preserved"
  check (match Config.admitProject disabled with | .ok _ => true | .error _ => false)
    "project config could not safely disable semantic retrieval"
  let escaped ← Config.parse (testRoot / "project-boundary" / ".eggshell.toml") r#"
[eggs]
project = "../outside.egg"
[profiles.work]
read = ["project"]
write = "project"
"#
  check (match Config.admitProject escaped with | .error _ => true | .ok _ => false)
    "project config could escape its repository authority root"
  let borrowed ← Config.parse (testRoot / "project-borrow" / ".eggshell.toml") r#"
[profiles.work]
read = ["global"]
"#
  check (match Config.admitProject borrowed with | .error _ => true | .ok _ => false)
    "project profile could select a globally declared authority"
  let foreignDefault ← Config.parse
      (testRoot / "project-default" / ".eggshell.toml") r#"
default = "global"
[profiles.work]
read = []
"#
  check (match Config.admitProject foreignDefault with
    | .error _ => true | .ok _ => false)
    "project default could select a globally declared profile"
  let inherited := Config.merge parsed automatic
  check (inherited.semanticMatcher = parsed.semanticMatcher &&
      inherited.semanticMatcherWasSet)
    "project omission erased a configured global semantic matcher"
  let optedOut := Config.merge parsed disabled
  check (optedOut.semanticMatcher.isNone && optedOut.semanticMatcherWasSet)
    "project opt-out did not override a configured global semantic matcher"
  let hook := Lean.Json.mkObj [("cwd", "/project")]
  let attached := Plugin.Daemon.attachClientConfig hook (some "/project/explicit.toml")
  check (Plugin.optionalString attached "_eggshell_config" =
      some "/project/explicit.toml")
    "hook client did not carry its per-session authority configuration"
  check (Plugin.Daemon.attachClientConfig hook none == hook)
    "hook client mutated requests without an explicit configuration"
  let projectRoot := testRoot / "project-matcher-rejection"
  IO.FS.createDirAll projectRoot
  IO.FS.writeFile (projectRoot / ".eggshell.toml") r#"
semantic_matcher = ["sh", "-c", "touch should-never-run"]
[eggs]
project = "work.egg"
[profiles.work]
read = ["project"]
"#
  try
    let _ ← Config.loadWith projectRoot none
    throw (IO.userError "auto-discovered project matcher command was admitted")
  catch error =>
    check (toString error |>.contains "cannot execute semantic_matcher")
      "auto-discovered project matcher failed for the wrong reason"
  IO.println "PASS profile merge, TOML comments, and per-session daemon config"

def testMiniLMDefault : IO Unit := do
  let home := testRoot / "minilm-home"
  let pluginData := testRoot / "minilm-plugin-data"
  let paths := MiniLM.layout home pluginData
  let python := MiniLM.unixPython paths
  if let some parent := python.parent then IO.FS.createDirAll parent
  IO.FS.writeFile python ""
  let some command ← MiniLM.command home pluginData |
    throw (IO.userError "installed MiniLM runtime was not selected by default")
  check (command.head? = some (← IO.appPath).toString &&
      command.contains "search-provider" &&
      command.contains paths.vectors.toString &&
      command.contains MiniLM.model)
    "default MiniLM command escaped its private runtime or Plugin cache"
  let absent ← MiniLM.command (testRoot / "absent-home") pluginData
  check absent.isNone "missing MiniLM runtime fabricated a provider command"
  IO.println "PASS installed MiniLM is the zero-config semantic default"

def testMatcherScale : IO Unit := do
  let some raw ← IO.getEnv "EGGSHELL_TEST_SCALE" | return
  let some count := raw.toNat? | throw (IO.userError "invalid EGGSHELL_TEST_SCALE")
  let values := (List.range count).map fun ordinal =>
    let work := Value.text s!"inspect unique-{ordinal} alpha beta gamma"
    let outcome := Value.text s!"observed unique-{ordinal}"
    (OutcomeEdge.make work outcome [] (by simp)
      (by simp [maxOutcomeObservations])).relation
  let current := s!"inspect unique-{count - 1} alpha beta gamma"
  let started ← IO.monoNanosNow
  let graph := WorkGraph.fromValues values
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer graph
  let prepared ← IO.monoNanosNow
  let quotient := QuotientBuilder.build? ((.text current) :: values) [] []
  check quotient.isSome "scaled quotient failed to certify"
  let quotientReady ← IO.monoNanosNow
  let hits := quotient.toList.flatMap fun quotient =>
    Matcher.findIn LogicalText.logicalNormalizer quotient corpus
      (.text current) current
  check (!hits.isEmpty) "scaled corpus failed to nominate the matching Outcome"
  let matched ← IO.monoNanosNow
  let discovery := Matcher.discoverIn? LogicalText.logicalNormalizer
    (.text current) values [] graph corpus current
  check discovery.isSome "scaled matcher failed to saturate"
  let elapsed ← IO.monoNanosNow
  IO.println (s!"PASS {count} Outcome prepare={(prepared - started) / 1000000}ms " ++
    s!"quotient={(quotientReady - prepared) / 1000000}ms " ++
    s!"match={(matched - quotientReady) / 1000000}ms " ++
    s!"fixpoint={(elapsed - matched) / 1000000}ms")

def hookJson (text : String) : IO Lean.Json :=
  match Lean.Json.parse text with
  | .ok json => pure json
  | .error message => throw (IO.userError message)

def testPluginBundle : IO Unit := do
  let manifest ← IO.FS.readFile "plugins/eggshell/.codex-plugin/plugin.json"
  let hooks ← IO.FS.readFile "plugins/eggshell/hooks/hooks.json"
  let manifestJson ← hookJson manifest
  let hooksJson ← hookJson hooks
  let embeddedManifest ← hookJson Eggshell.Install.pluginManifest
  let embeddedHooks ← hookJson Eggshell.Install.hooksManifest
  check (manifestJson == embeddedManifest) "installed and checked-in plugin manifests diverged"
  check (hooksJson == embeddedHooks) "installed and checked-in hook manifests diverged"
  check (manifestJson.getObjValD "name" == "eggshell") "plugin name is invalid"
  check (hooksJson.getObjValD "hooks" != Lean.Json.null) "plugin has no hooks"
  IO.println "PASS checked-in and installed Plugin bundle are one definition"

def testInstallerOwnership : IO Unit := do
  let foreignRoot := testRoot / "foreign-plugin"
  let foreignLauncher := testRoot / "foreign-egg"
  IO.FS.createDirAll foreignRoot
  IO.FS.writeFile (foreignRoot / "user-data") "keep"
  try
    Install.validateManagedPaths foreignRoot foreignLauncher
    throw (IO.userError "installer admitted an unowned Plugin directory")
  catch error =>
    check (toString error |>.contains "unowned Plugin directory")
      "unowned Plugin directory failed for the wrong reason"
  check (← (foreignRoot / "user-data").pathExists)
    "installer ownership check deleted foreign data"

  let ownedRoot := testRoot / "owned-plugin"
  let ownedLauncher := testRoot / "owned-egg"
  IO.FS.createDirAll (ownedRoot / ".codex-plugin")
  IO.FS.createDirAll (ownedRoot / "bin")
  IO.FS.writeFile (ownedRoot / ".codex-plugin" / "plugin.json") Install.pluginManifest
  IO.FS.writeFile (ownedRoot / "bin" / "egg") (Install.pluginLauncher testRoot)
  IO.FS.writeFile ownedLauncher Install.commandLauncher
  Install.validateManagedPaths ownedRoot ownedLauncher
  IO.FS.writeFile (ownedRoot / ".codex-plugin" / "plugin.json")
    (Install.pluginManifest.replace "https://github.com/momonpya/eggshell"
      "https://github.com/o8vm/eggshell")
  Install.validateManagedPaths ownedRoot ownedLauncher
  IO.FS.writeFile (ownedRoot / ".codex-plugin" / "plugin.json")
    (Install.pluginManifest.replace "https://github.com/momonpya/eggshell"
      "https://github.com/unrelated/eggshell")
  check (!(← Install.ownedPluginRoot ownedRoot))
    "installer admitted an unrelated repository with the same Plugin name"
  IO.FS.writeFile (ownedRoot / Install.ownerMarkerName) "o8vm/eggshell\n"
  Install.validateManagedPaths ownedRoot ownedLauncher
  IO.FS.writeBinFile ownedLauncher "foreign-binary".toUTF8
  try
    Install.validateManagedPaths ownedRoot ownedLauncher
    throw (IO.userError "installer admitted an unowned launcher")
  catch error =>
    check (toString error |>.contains "unowned launcher")
      "unowned launcher failed for the wrong reason"

  let installRoot := ((← IO.currentDir) / testRoot / "relocatable prefix's").normalize
  let layout := Install.Layout.at installRoot
  check (layout.executable == installRoot / "libexec" / "eggshell" &&
      layout.launcher == installRoot / "bin" / "egg" &&
      layout.plugin == installRoot / "plugins" / "eggshell" &&
      layout.marketplace == installRoot / ".agents" / "plugins" / "marketplace.json" &&
      MiniLM.supportRoot installRoot == installRoot / "share" / "eggshell" / "minilm")
    "installation layout escaped its configured prefix"
  check (Install.commandLauncher.contains "EGGSHELL_PREFIX" &&
      (Install.pluginLauncher installRoot).contains "EGGSHELL_PREFIX=" &&
      !(Install.pluginLauncher installRoot).contains "HOME" &&
      Install.commandLauncher.contains " egg \"$@\"" &&
      (Install.pluginLauncher installRoot).contains "codex-hook|codex-daemon|codex-worker|codex-rpc")
    "installed launchers did not carry the relocatable prefix"
  Install.writeExecutable layout.executable r#"#!/bin/sh
printf '%s|%s\n' "$EGGSHELL_PREFIX" "$*"
"#
  Install.writeExecutable layout.launcher Install.commandLauncher
  IO.FS.createDirAll (layout.plugin / "bin")
  Install.writeExecutable (layout.plugin / "bin" / "egg")
    (Install.pluginLauncher installRoot)
  Install.writeExecutable (layout.plugin / "bin" / "eggshelld")
    (Install.pluginLauncher installRoot)
  for launcher in [layout.launcher, layout.plugin / "bin" / "egg"] do
    let output ← IO.Process.output { cmd := launcher.toString }
    check (output.exitCode == 0 &&
        output.stdout.trimAscii == installRoot.toString ++ "|egg")
      "a user launcher did not restore its prefix and egg subcommand"
  let control ← IO.Process.output {
    cmd := (layout.plugin / "bin" / "egg").toString
    args := #["inspect"]
  }
  check (control.exitCode == 0 &&
      control.stdout.trimAscii == installRoot.toString ++ "|egg inspect")
    "the Plugin launcher lost a user control argument"
  let hook ← IO.Process.output {
    cmd := (layout.plugin / "bin" / "egg").toString
    args := #["codex-hook"]
  }
  check (hook.exitCode == 0 &&
      hook.stdout.trimAscii == installRoot.toString ++ "|codex-hook")
    "the Plugin launcher rewrote the internal hook command"
  let daemon ← IO.Process.output {
    cmd := (layout.plugin / "bin" / "eggshelld").toString
    args := #["codex-daemon"]
  }
  check (daemon.exitCode == 0 &&
      daemon.stdout.trimAscii == installRoot.toString ++ "|codex-daemon")
    "the relocatable daemon launcher lost its internal command"

  let marketplace := testRoot / "marketplace.json"
  let foreignEntry := Lean.Json.mkObj [
    ("name", "eggshell"),
    ("source", Lean.Json.mkObj [("source", "github"), ("repo", "someone/else")])
  ]
  let foreignDocument := Lean.Json.mkObj [
    ("name", "personal"),
    ("plugins", .arr #[foreignEntry])
  ]
  IO.FS.writeFile marketplace foreignDocument.pretty
  let before ← IO.FS.readFile marketplace
  try
    let _ ← Install.updateMarketplace marketplace true
    throw (IO.userError "installer replaced an unowned marketplace entry")
  catch error =>
    check (toString error |>.contains "unowned marketplace entry")
      "unowned marketplace entry failed for the wrong reason"
  check ((← IO.FS.readFile marketplace) = before)
    "marketplace collision modified user data"
  let other := Lean.Json.mkObj [("name", "other")]
  IO.FS.writeFile marketplace (Lean.Json.mkObj [
    ("name", "personal"),
    ("plugins", .arr #[other, Install.marketplaceEntry])
  ]).pretty
  let _ ← Install.updateMarketplace marketplace false
  let cleaned ← hookJson (← IO.FS.readFile marketplace)
  check (Install.marketplacePlugins cleaned == [other])
    "uninstall removed a marketplace entry it did not own"
  IO.println "PASS installer replaces only owned paths and marketplace entries"

def testHooks : IO Unit := do
  let root ← dataRoot
  if ← root.pathExists then IO.FS.removeDirAll root
  let hookRoot ← hookTestRoot
  prepareTestProject hookRoot
  let launcher := hookRoot / "egg"
  let some buildBin := (← IO.appPath).parent |
    throw (IO.userError "native hook fixture has no executable directory")
  let source := buildBin / "eggshell"
  if System.Platform.isOSX then
    let cloned ← IO.Process.output { cmd := "/bin/cp", args := #["-c", source.toString, launcher.toString] }
    check (cloned.exitCode == 0) "native hook fixture could not clone its executable"
  else Install.copyExecutable source launcher
  let cli ← IO.Process.output {
    cmd := launcher.toString
    cwd := some hookRoot
    env := #[("CODEX_THREAD_ID", some "egg-entrypoint-test")]
  }
  check (cli.exitCode == 0 &&
      cli.stdout.startsWith "egg on work [project] → project pending:none")
    "installed egg executable did not enter the control CLI"
  let help ← IO.Process.output { cmd := launcher.toString, args := #["--help"] }
  check (help.exitCode == 0 && help.stdout.startsWith "usage: egg ")
    "installed egg executable did not expose standalone help"
  let hookEgg := hookRoot / "work.egg"
  let cwd := hookRoot.toString

  /- The persistent switch must stop both staging and graph transport until it
     is explicitly enabled again. -/
  let toggleSession := "toggle-session"
  let off ← IO.Process.output {
    cmd := launcher.toString
    args := #["off"]
    cwd := some hookRoot
    env := #[("CODEX_THREAD_ID", some toggleSession)]
  }
  check (off.exitCode == 0 && off.stdout.contains "egg off")
    "!egg off did not disable the persistent memory switch"
  let offPrompt ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", toggleSession),
    ("turn_id", "toggle-turn"), ("cwd", cwd),
    ("prompt", "This work must not be staged while memory is off")])
  check (offPrompt == emptyHook)
    "a disabled Eggshell session injected context into a prompt"
  let toggleFiles ← sessionFiles toggleSession
  check (!(← toggleFiles.pending.pathExists))
    "a disabled Eggshell session staged a pending turn"
  let offState ← (readJson? toggleFiles.state : IO (Option ThreadState))
  check (offState.map (·.enabled) == some false)
    "!egg off did not persist the disabled state"
  let offTool ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"toggle-session\",\"turn_id\":\"toggle-turn\",\"tool_name\":\"shell\",\"tool_use_id\":\"toggle-tool\",\"tool_input\":{\"command\":\"printf toggle\"}}")
  check (offTool == emptyHook && !(← toggleFiles.pending.pathExists))
    "a disabled Eggshell session recorded native tool work"
  let offGraph ← IO.Process.output {
    cmd := launcher.toString
    args := #["graph"]
    cwd := some hookRoot
    env := #[("CODEX_THREAD_ID", some toggleSession)]
  }
  check (offGraph.exitCode == 0 && offGraph.stdout.contains "no graph was sent")
    "!egg graph exposed a handoff while memory was off"
  let on ← IO.Process.output {
    cmd := launcher.toString
    args := #["on"]
    cwd := some hookRoot
    env := #[("CODEX_THREAD_ID", some toggleSession)]
  }
  check (on.exitCode == 0 && on.stdout.contains "egg on")
    "!egg on did not re-enable the persistent memory switch"
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", toggleSession),
    ("turn_id", "toggle-turn-on"), ("cwd", cwd),
    ("prompt", "This work may be staged after memory is enabled")])
  check (← toggleFiles.pending.pathExists)
    "!egg on did not resume pending-turn staging"
  removeIfExists toggleFiles.pending

  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", "session-one"), ("cwd", cwd)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", "session-one"),
    ("turn_id", "turn-one"), ("cwd", cwd), ("prompt", "Trace pvclock into wallclock")])
  let parentFiles ← sessionFiles "session-one"
  let some parentPending ← readPending? parentFiles |
    throw (IO.userError "hook did not stage the parent-project turn")
  check (parentPending.write == some hookEgg.toString)
    "the parent session did not snapshot its project-local .egg"
  let cliPending ← IO.Process.output {
    cmd := launcher.toString
    cwd := some hookRoot
    env := #[
      ("CODEX_THREAD_ID", some "session-one"),
      ("PLUGIN_DATA", some (hookRoot / "host-only-plugin-data").toString)
    ]
  }
  check (cliPending.exitCode == 0 && cliPending.stdout.contains "pending:active:turn-one")
    "hook-only PLUGIN_DATA split staged state from the !egg CLI"

  let nestedRoot := hookRoot / "nested-project"
  prepareTestProject nestedRoot
  let nestedCwd := nestedRoot.toString
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", "session-nested"),
    ("cwd", nestedCwd)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", "session-nested"),
    ("turn_id", "turn-nested"), ("cwd", nestedCwd),
    ("prompt", "Inspect the nested project")])
  let nestedFiles ← sessionFiles "session-nested"
  let some nestedPending ← readPending? nestedFiles |
    throw (IO.userError "hook did not stage the nested-project turn")
  let nestedEgg := nestedRoot / "work.egg"
  check (nestedPending.write == some nestedEgg.toString &&
      nestedPending.write != parentPending.write)
    "shared control state collapsed distinct nested-project .egg selections"
  removeIfExists nestedFiles.pending
  check (!(← hookEgg.pathExists))
    "a read path was created before the first staged turn was promoted"
  IO.FS.createDirAll (hookRoot / "kernel/time")
  IO.FS.writeFile (hookRoot / "kernel/time/vsyscall.c") "update_vsyscall: pvclock joins generic timekeeping\n"
  let _ ← runHookFixture (← hookJson r#"{"hook_event_name":"PreToolUse","session_id":"session-one","turn_id":"turn-one","tool_name":"shell","tool_use_id":"tool-one","tool_input":{"command":"rg update_vsyscall kernel/time/vsyscall.c"}}"#)
  let _ ← runHookFixture (← hookJson "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"session-one\",\"turn_id\":\"turn-one\",\"tool_name\":\"shell\",\"tool_use_id\":\"tool-one\",\"tool_input\":{\"command\":\"rg update_vsyscall kernel/time/vsyscall.c\"},\"tool_response\":{\"output\":\"kernel/time/vsyscall.c update_vsyscall\"}}")
  let _ ← runHookFixture (← hookJson "{\"hook_event_name\":\"Stop\",\"session_id\":\"session-one\",\"turn_id\":\"turn-one\",\"last_assistant_message\":\"pvclock joins generic timekeeping\"}")
  let _ ← runHookFixture (← hookJson "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"session-one\"}")
  check (← hookEgg.pathExists)
    "the first kept turn did not create its write authority"
  let some stateOne ← (readJson? parentFiles.state : IO (Option ThreadState)) |
    throw (IO.userError "promotion lost the first session's delivery state")
  check (stateOne.deliveredGraphs.any (·.startsWith "h:") &&
      stateOne.deliveredGraphs.all (fun key => key.startsWith "h:" || (SourceEvidence.deliveryScope? key).isSome))
    "promotion did not mark its complete Outcome owners as native history"
  let ownFollowup ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", "session-one"),
    ("turn_id", "turn-one-followup"), ("cwd", cwd),
    ("prompt", "Trace pvclock into wallclock")])
  check (!ownFollowup.contains "WORK GRAPH" && !ownFollowup.contains "GROUNDED OUTCOME" &&
      !ownFollowup.contains "permissionDecision")
    ("the same session echoed its newly promoted graph before compaction: " ++ ownFollowup)
  removeIfExists parentFiles.pending
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", "session-two"), ("cwd", cwd)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", "session-two"),
    ("turn_id", "turn-two"), ("cwd", cwd), ("prompt", "Trace TSC into wallclock")])
  let preTool ← hookJson "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"session-two\",\"turn_id\":\"turn-two\",\"tool_name\":\"shell\",\"tool_use_id\":\"tool-two\",\"tool_input\":{\"command\":\"rg update_vsyscall ./kernel/time/vsyscall.c\"}}"
  let first ← runHookFixture preTool
  check (first.contains "permissionDecision")
    "independent session did not receive completed prior operation"
  check (first.contains "Replan the call" && first.contains "completed prior native Work")
    "one-shot operation replanning was not explained to the agent"
  let firstJson ← hookJson first
  let firstOutput := firstJson.getObjVal? "hookSpecificOutput" >>= fun output =>
    output.getObjValAs? String "permissionDecisionReason"
  check (firstOutput.toOption.any (·.contains evidenceGapGuidance))
    "completed-work replanning omitted the evidence-gap stopping condition"
  let second ← runHookFixture preTool
  check (!second.contains "permissionDecision")
    "an unchanged Outcome subtree triggered twice before compaction"
  let _ ← runHookFixture (← hookJson "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"session-two\"}")
  let restored ← runHookFixture preTool
  check (restored.contains "additionalContext" && !restored.contains "permissionDecision")
    "compaction did not restore unchanged evidence without another checkpoint"

  -- A new native occurrence supplies a distinct Outcome owner. The earlier
  -- checkpoint for this operation must not suppress reuse of that new evidence.
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"session-two\",\"turn_id\":\"turn-two\",\"tool_name\":\"shell\",\"tool_use_id\":\"tool-two\",\"tool_input\":{\"command\":\"rg update_vsyscall ./kernel/time/vsyscall.c\"},\"tool_response\":{\"output\":\"kernel/time/vsyscall.c update_vsyscall\"}}")
  let _ ← runHookFixture (← hookJson "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"session-two\"}")
  let newEvidence ← runHookFixture preTool
  check (newEvidence.contains "kernel/time/vsyscall.c update_vsyscall" &&
      newEvidence.contains "permissionDecision")
    "an earlier operation checkpoint suppressed new observed evidence after compaction"
  let unchangedEvidence ← runHookFixture preTool
  check (!unchangedEvidence.contains "permissionDecision")
    "an unchanged new Outcome triggered another checkpoint"
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", "session-three"), ("cwd", cwd)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", "session-three"),
    ("turn_id", "turn-three"), ("cwd", cwd), ("prompt", "Inspect an unrelated clock")])
  let postTool ← hookJson "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"session-three\",\"turn_id\":\"turn-three\",\"tool_name\":\"shell\",\"tool_use_id\":\"tool-three\",\"tool_input\":{\"command\":\"rg update_vsyscall ./kernel/time/vsyscall.c\"},\"tool_response\":{\"output\":\"kernel/time/vsyscall.c update_vsyscall\"}}"
  let progressed ← runHookFixture postTool
  check (progressed.contains "additionalContext" &&
      !progressed.contains "permissionDecision")
    "PostToolUse did not deliver newly connected graph data as context"
  let sessionThree ← sessionFiles "session-three"
  let some stateThree ← (readJson? sessionThree.state : IO (Option ThreadState)) |
    throw (IO.userError "PostToolUse did not persist delivery progress")
  check (stateThree.lastReason.contains "blocks-current=false")
    "PostToolUse was recorded as a PreTool operation erasure"
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", "session-four"), ("cwd", cwd)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", "session-four"),
    ("turn_id", "turn-four"), ("cwd", cwd), ("prompt", "Inspect an unrelated clock")])
  let completedAfterAdvisoryBudget ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"session-four\",\"turn_id\":\"turn-four\",\"tool_name\":\"shell\",\"tool_use_id\":\"tool-four\",\"tool_input\":{\"command\":\"rg update_vsyscall ./kernel/time/vsyscall.c\"}}")
  check (completedAfterAdvisoryBudget.contains "permissionDecision")
    "an earlier delta incorrectly consumed the later graph transport budget"
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", "session-five"), ("cwd", cwd)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", "session-five"),
    ("turn_id", "turn-five"), ("cwd", cwd), ("prompt", "Inspect a unique parallel probe")])
  let firstParallel ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"session-five\",\"turn_id\":\"turn-five\",\"tool_name\":\"shell\",\"tool_use_id\":\"parallel-one\",\"tool_input\":{\"command\":\"printf eggshell_unique_parallel_probe_7f9a\"}}")
  check (!firstParallel.contains "permissionDecision")
    "a new native Work was rejected before execution"
  let duplicateParallel ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"session-five\",\"turn_id\":\"turn-five\",\"tool_name\":\"shell\",\"tool_use_id\":\"parallel-two\",\"tool_input\":{\"command\":\"printf eggshell_unique_parallel_probe_7f9a\"}}")
  check (!duplicateParallel.contains "permissionDecision")
    "an unclosed native occurrence incorrectly blocked a later proposal"
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"session-five\",\"turn_id\":\"turn-five\",\"tool_name\":\"shell\",\"tool_use_id\":\"parallel-one\",\"tool_input\":{\"command\":\"printf eggshell_unique_parallel_probe_7f9a\"},\"tool_response\":{\"output\":\"eggshell_unique_parallel_probe_7f9a\"}}")
  let sessionFive ← sessionFiles "session-five"
  let some pendingFive ← readPending? sessionFive |
    throw (IO.userError "parallel test lost its staged turn")
  check (pendingFive.inFlight.length = 1 && pendingFive.tools.length = 1)
    "PostToolUse did not close exactly its observed native occurrence"
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"Stop\",\"session_id\":\"session-five\",\"turn_id\":\"turn-five\",\"last_assistant_message\":\"one occurrence completed and one lacked a terminal hook\"}")
  let some sealedFive ← readPending? sessionFive |
    throw (IO.userError "Stop lost the staged turn with a missing terminal hook")
  check (sealedFive.inFlight.isEmpty && sealedFive.tools.length = 1)
    "Stop did not discard the unobserved occurrence"
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", "session-six"), ("cwd", cwd)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", "session-six"),
    ("turn_id", "turn-six"), ("cwd", cwd),
    ("prompt", "Inspect two hook-delivery probes")])
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"session-six\",\"turn_id\":\"turn-six\",\"tool_name\":\"shell\",\"tool_use_id\":\"observed-six\",\"tool_input\":{\"command\":\"printf observed_hook_result_3a72\"}}")
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"session-six\",\"turn_id\":\"turn-six\",\"tool_name\":\"shell\",\"tool_use_id\":\"missing-six\",\"tool_input\":{\"command\":\"printf unobserved_hook_result_91ce\"}}")
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"session-six\",\"turn_id\":\"turn-six\",\"tool_name\":\"shell\",\"tool_use_id\":\"observed-six\",\"tool_input\":{\"command\":\"printf observed_hook_result_3a72\"},\"tool_response\":{\"output\":\"observed_hook_result_3a72\"}}")
  /- Codex Stop may omit `turn_id`; the session's sole staged turn is unambiguous. -/
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"Stop\",\"session_id\":\"session-six\",\"last_assistant_message\":\"completed with one observed native result\"}")
  let sessionSix ← sessionFiles "session-six"
  let some sealedSix ← readPending? sessionSix |
    throw (IO.userError "Stop discarded the fail-soft staged turn")
  check (sealedSix.inFlight.isEmpty && sealedSix.tools.length = 1 &&
      sealedSix.finalMessage.isSome)
    "Stop did not discard only the unresolved reservation"
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"session-six\"}")
  check (!( ← sessionSix.pending.pathExists))
    "fail-soft turn did not promote its observed work"
  let failSoftGraph ← Persistence.load hookEgg
  let failSoftNodes := failSoftGraph.values.flatMap Value.nodes
  let observedTool : ToolEvent := {
    name := "shell"
    useId := "observed-six"
    input := r#"{"command":"printf observed_hook_result_3a72"}"#
    response := r#"{"output":"observed_hook_result_3a72"}"#
  }
  check (failSoftNodes.contains
        (.text (canonicalToolWork observedTool)) &&
      failSoftNodes.contains (.text (canonicalJson observedTool.response)) &&
      failSoftNodes.contains (.text "completed with one observed native result"))
    "promotion lost observed Work, Outcome, or parent result"
  check (!failSoftNodes.contains (.text "printf unobserved_hook_result_91ce"))
    "an unresolved PreToolUse reservation fabricated persistent Work"

  /-
  A lost connection can omit both Stop and SessionEnd. The next distinct turn
  must preserve terminal tool outcomes without fabricating a parent result or
  asking the user to clean up Eggshell's staging state.
  -/
  let interruptedSession := "session-interrupted"
  let interruptedTurn := "turn-interrupted"
  let interruptedPrompt := "Inspect the interrupted probe"
  let interruptedTool : ToolEvent := {
    name := "shell"
    useId := "interrupted-observed"
    input := r#"{"command":"printf interrupted_observed_62d1"}"#
    response := r#"{"output":"interrupted_observed_62d1"}"#
  }
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", interruptedSession),
    ("cwd", cwd)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", interruptedSession),
    ("turn_id", interruptedTurn), ("cwd", cwd), ("prompt", interruptedPrompt)])
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"session-interrupted\",\"turn_id\":\"turn-interrupted\",\"tool_name\":\"shell\",\"tool_use_id\":\"interrupted-observed\",\"tool_input\":{\"command\":\"printf interrupted_observed_62d1\"},\"tool_response\":{\"output\":\"interrupted_observed_62d1\"}}")
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"session-interrupted\",\"turn_id\":\"turn-interrupted\",\"tool_name\":\"shell\",\"tool_use_id\":\"interrupted-unobserved\",\"tool_input\":{\"command\":\"printf interrupted_unobserved_b87e\"}}")
  let interruptedFiles ← sessionFiles interruptedSession
  let reconnect ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", interruptedSession),
    ("cwd", cwd)])
  check (!reconnect.contains "drop")
    "connection recovery required manual deletion of staged work"
  let replay ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", interruptedSession),
    ("turn_id", interruptedTurn), ("cwd", cwd), ("prompt", interruptedPrompt)])
  check (replay == emptyHook)
    "a repeated hook for the active turn was not idempotent"
  let some replayedPending ←
      readPending? interruptedFiles |
    throw (IO.userError "same-turn reconnect lost its staged observations")
  check (replayedPending.tools.length = 1 && replayedPending.inFlight.length = 1)
    "same-turn reconnect changed staged native occurrences"
  let continued ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", interruptedSession),
    ("turn_id", "turn-after-interruption"), ("cwd", cwd),
    ("prompt", "Continue from the interrupted probe")])
  check (!continued.contains "\"decision\":\"block\"")
    "a recovered partial turn blocked subsequent work"
  let some continuedPending ←
      readPending? interruptedFiles |
    throw (IO.userError "recovery did not start the next staged turn")
  check (continuedPending.turnId = "turn-after-interruption")
    "recovery did not replace the interrupted stage with the next turn"
  let recoveredGraph ← Persistence.load hookEgg
  let recoveredOutcomes := recoveredGraph.values.filterMap OutcomeEdge.fromValue?
  let recoveredWork := Value.text (canonicalToolWork interruptedTool)
  let recoveredResult := Value.text (canonicalJson interruptedTool.response)
  check (recoveredOutcomes.any fun edge =>
      edge.work == recoveredWork && edge.outcome == recoveredResult)
    "connection recovery lost an observed native Outcome"
  check (!recoveredOutcomes.any fun edge => edge.work == .text interruptedPrompt)
    "connection recovery fabricated a final parent Outcome"
  let recoveredAll := recoveredGraph.values.filterMap AllEdge.fromValue?
  check (recoveredAll.any fun edge =>
      edge.parent == .text interruptedPrompt &&
      edge.children.contains recoveredWork &&
      edge.children.contains (HandoffRemainder.value interruptedPrompt))
    "connection recovery did not leave the interrupted parent Work open"
  check (!(recoveredGraph.values.flatMap Value.nodes).contains
      (.text "printf interrupted_unobserved_b87e"))
    "connection recovery promoted an operation without a terminal result"

  /- Closing a chat retains observed work even if Stop never arrived. -/
  let closedSession := "session-closed-interruption"
  let closedFiles ← sessionFiles closedSession
  let closedPending : PendingTurn := {
    replayedPending with
    sessionId := closedSession
    turnId := "closed-turn"
    prompt := "Closed investigation"
    tools := [interruptedTool]
  }
  writeJson closedFiles.state ({ profile := "work" } : ThreadState)
  writeJson closedFiles.pending closedPending
  let closeEvent := Lean.Json.mkObj [
    ("hook_event_name", "SessionEnd"), ("session_id", closedSession)]
  let _ ← runHookFixture closeEvent
  check (!(← closedFiles.pending.pathExists)) "closed turn remained staged after promotion"
  let closedGraph ← Persistence.load hookEgg
  let closedOutcomes := closedGraph.values.filterMap OutcomeEdge.fromValue?
  check (closedOutcomes.any fun edge =>
      edge.work == recoveredWork && edge.outcome == recoveredResult)
    "SessionEnd discarded a terminal tool outcome"
  check (!(closedOutcomes.any fun edge => edge.work == .text closedPending.prompt))
    "SessionEnd fabricated a final answer"
  let searchable := SemanticMatcher.outcomeWorkItems closedGraph.values
  check (searchable.any fun item => item.text.contains "interrupted_observed_62d1")
    "interrupted observations became invisible to semantic search"
  check ((closedGraph.values.filterMap AllEdge.fromValue?).any fun edge =>
      edge.parent == .text closedPending.prompt && edge.children.contains recoveredWork &&
        edge.children.contains (HandoffRemainder.value closedPending.prompt))
    "SessionEnd lost the open remainder"
  let _ ← runHookFixture closeEvent
  check ((← Persistence.load hookEgg).revision == closedGraph.revision)
    "repeated SessionEnd promoted the same turn twice"
  /- Terminal hooks may arrive in either order, even after the writer consumed
     the deferred job. The answer belongs to that old turn, not the next one. -/
  let lateAnswer := "Closed investigation final answer d9e462"
  let lateStop := Lean.Json.mkObj [
    ("hook_event_name", "Stop"), ("session_id", closedSession),
    ("turn_id", closedPending.turnId), ("last_assistant_message", lateAnswer)]
  let _ ← runHookFixture lateStop
  let lateGraph ← Persistence.load hookEgg
  check ((lateGraph.values.filterMap OutcomeEdge.fromValue?).any fun edge =>
      edge.work == .text closedPending.prompt && edge.outcome == .text lateAnswer)
    "SessionEnd before Stop discarded the final answer"
  check ((lateGraph.values.filterMap OutcomeEdge.fromValue?).any fun edge =>
      edge.work == recoveredWork && edge.outcome == recoveredResult)
    "late Stop discarded an already saved observation"
  let _ ← runHookFixture lateStop
  check ((← Persistence.load hookEgg).revision == lateGraph.revision)
    "repeated late Stop changed the committed graph"
  let nextClosedPending := { closedPending with
    turnId := "next-closed-turn", prompt := "Next investigation", tools := [] }
  writeJson closedFiles.pending nextClosedPending
  let beforeLateState ← readState? closedFiles
  let _ ← runHookFixture lateStop
  check ((← readPendingBase? closedFiles).map Lean.toJson == some (Lean.toJson nextClosedPending))
    "late Stop sealed the next turn"
  check ((← readState? closedFiles).map Lean.toJson == beforeLateState.map Lean.toJson)
    "late Stop invalidated the next turn's search context"
  let lateTool := { interruptedTool with
    useId := "late-terminal-observation", response := r#"{"output":"late_observed_381a"}"# }
  let lateInput ← IO.ofExcept (Lean.Json.parse lateTool.input)
  let lateResponse ← IO.ofExcept (Lean.Json.parse lateTool.response)
  let latePost := Lean.Json.mkObj [
    ("hook_event_name", "PostToolUse"), ("session_id", closedSession),
    ("turn_id", closedPending.turnId), ("tool_name", lateTool.name),
    ("tool_use_id", lateTool.useId), ("tool_input", lateInput),
    ("tool_response", lateResponse)]
  captureTerminal latePost
  let _ ← runHookFixture latePost
  let latePostGraph ← Persistence.load hookEgg
  check ((latePostGraph.values.filterMap OutcomeEdge.fromValue?).any fun edge =>
      edge.work == .text (canonicalToolWork lateTool) &&
      edge.outcome == .text (canonicalJson lateTool.response))
    "an old turn's late terminal result was lost after the deferred queue drained"
  check ((← readPendingBase? closedFiles).map Lean.toJson == some (Lean.toJson nextClosedPending))
    "an old turn's late result mutated the next turn"
  check ((latePostGraph.values.filterMap OutcomeEdge.fromValue?).any fun edge =>
      edge.work == .text closedPending.prompt && edge.outcome == .text lateAnswer)
    "late observation erased the final answer"
  let freshSelection : Config.Selection := {
    label := "recovered", semanticMatcher := none
    read := [{ name := "work", path := hookEgg }], write := none, handoffChars := 120000
  }
  let restored ← automaticHandoff freshSelection (canonicalToolWork interruptedTool) [] true
  check (restored.any fun handoff => handoff.text.contains "interrupted_observed_62d1")
    "a new chat could not reuse the closed chat's observed work"

  /- Failed persistence must not erase the only copy of an interrupted turn. -/
  let badTarget := closedFiles.directory / "not-an-egg"
  Persistence.privateDirectory badTarget
  writeJson closedFiles.pending { closedPending with write := some badTarget.toString }
  let failed ← try
    let _ ← runHookFixture closeEvent
    pure false
    catch _ => pure true
  check (!failed && (← (closedFiles.directory / "deferred").pathExists))
    "failed persistence blocked the hook or erased the retry queue"
  let afterFailure := Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", closedSession),
    ("turn_id", "after-save-failure"), ("cwd", cwd), ("prompt", "Continue ordinary work")]
  let reply ← runHookFixture afterFailure
  check (!reply.contains "drop" && !reply.contains "\"decision\":\"block\"")
    "saving failed and Eggshell required the user to drop work"
  let some newPending ← readPending? closedFiles |
    throw (IO.userError "save failure prevented the next turn from being observed")
  check (newPending.turnId == "after-save-failure") "new turn reused the failed pending slot"
  let deferred := closedFiles.directory / "deferred" /
    (SemanticMatcher.contentKey (.text closedPending.turnId) ++ ".json")
  let some saved ← (readJson? deferred : IO (Option PendingTurn)) |
    throw (IO.userError "save failure lost the deferred turn")
  check (saved.tools.length == 1 && saved.inFlight.length == 1)
    "deferral changed the interrupted observations"
  IO.FS.removeDir badTarget
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", closedSession),
    ("turn_id", "after-repair"), ("cwd", cwd), ("prompt", "Continue after repair")])
  check (!(← deferred.pathExists)) "deferred save was not retried automatically"
  let retried := (← Persistence.load badTarget).values.filterMap OutcomeEdge.fromValue?
  check (retried.any fun edge => edge.work == recoveredWork && edge.outcome == recoveredResult)
    "automatic retry did not restore the terminal observation"

  /- A turn interrupted before any terminal tool result has no work to retain. -/
  let emptyRecoverySession := "session-empty-interruption"
  let beforeEmptyRecovery ← Persistence.load hookEgg
  let beforeEmptySnapshot ← DB.PageMap.pin hookEgg
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"), ("session_id", emptyRecoverySession),
    ("cwd", cwd)])
  let _ ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", emptyRecoverySession),
    ("turn_id", "empty-interrupted"), ("cwd", cwd),
    ("prompt", "Start but do not finish a probe")])
  let _ ← runHookFixture (← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"session-empty-interruption\",\"turn_id\":\"empty-interrupted\",\"tool_name\":\"shell\",\"tool_use_id\":\"empty-unobserved\",\"tool_input\":{\"command\":\"printf empty_unobserved_41ca\"}}")
  let resumedEmpty ← runHookFixture (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"), ("session_id", emptyRecoverySession),
    ("turn_id", "after-empty-interruption"), ("cwd", cwd),
    ("prompt", "Continue without prior observations")])
  check (!resumedEmpty.contains "\"decision\":\"block\"")
    "an empty interrupted turn blocked subsequent work"
  -- A completed search may publish derived memo rows. A physical page-root
  -- revision therefore does not identify new observed work. Keep the complete
  -- authority, roots and Union meaning unchanged, and reject any nonneutral
  -- publication in the intervening writer chain.
  let afterEmptyRecovery ← Persistence.load hookEgg
  let afterEmptySnapshot ← DB.PageMap.pin hookEgg
  check (afterEmptyRecovery.authority == beforeEmptyRecovery.authority &&
      afterEmptyRecovery.values == beforeEmptyRecovery.values &&
      decide (afterEmptyRecovery.unions.map (·.edge) = beforeEmptyRecovery.unions.map (·.edge)) &&
      (← DemandMemo.agree afterEmptySnapshot beforeEmptySnapshot.head))
    "an interrupted turn without observed outcomes changed authority, roots, Unions or published a nonneutral delta"
  IO.println "PASS native history delta, independent session handoff, compaction restore"

def waitHook (task : Task (Except IO.Error String)) : IO String := do
  match ← IO.wait task with
  | .ok output => pure output
  | .error error => throw error

def testDaemonConcurrency : IO Unit := do
  let endpointFile ← Plugin.Daemon.endpointPath "daemon-parallel"
  if ← endpointFile.pathExists then IO.FS.removeFile endpointFile
  let daemon ← IO.asTask (Plugin.Daemon.run "daemon-parallel") .dedicated
  let endpoint ← Plugin.Daemon.awaitEndpoint "daemon-parallel" Plugin.Daemon.startupAttempts
  let cwd := (← hookTestRoot).toString
  let send (input : Lean.Json) := Plugin.Daemon.exchange endpoint "hook" input
  let _ ← send (Lean.Json.mkObj [
    ("hook_event_name", "SessionStart"),
    ("session_id", "daemon-parallel"), ("cwd", cwd)])
  let _ ← send (Lean.Json.mkObj [
    ("hook_event_name", "UserPromptSubmit"),
    ("session_id", "daemon-parallel"), ("turn_id", "daemon-turn"),
    ("cwd", cwd), ("prompt", "Inspect two independent probes")])
  let preOne ← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"daemon-parallel\",\"turn_id\":\"daemon-turn\",\"tool_name\":\"shell\",\"tool_use_id\":\"daemon-one\",\"tool_input\":{\"command\":\"printf daemon_probe_alpha_91b3\"}}"
  let preTwo ← hookJson
    "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"daemon-parallel\",\"turn_id\":\"daemon-turn\",\"tool_name\":\"shell\",\"tool_use_id\":\"daemon-two\",\"tool_input\":{\"command\":\"printf daemon_probe_beta_4c72\"}}"
  let firstPre ← IO.asTask (send preOne) .dedicated
  let secondPre ← IO.asTask (send preTwo) .dedicated
  let _ ← waitHook firstPre
  let _ ← waitHook secondPre
  let files ← sessionFiles "daemon-parallel"
  let some reserved ← readPending? files |
    throw (IO.userError "daemon lost the concurrent staged turn")
  check (reserved.inFlight.length = 2)
    "daemon did not linearize two concurrent native Work reservations"
  let postOne ← hookJson
    "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"daemon-parallel\",\"turn_id\":\"daemon-turn\",\"tool_name\":\"shell\",\"tool_use_id\":\"daemon-one\",\"tool_input\":{\"command\":\"printf daemon_probe_alpha_91b3\"},\"tool_response\":{\"output\":\"daemon_probe_alpha_91b3\"}}"
  let postTwo ← hookJson
    "{\"hook_event_name\":\"PostToolUse\",\"session_id\":\"daemon-parallel\",\"turn_id\":\"daemon-turn\",\"tool_name\":\"shell\",\"tool_use_id\":\"daemon-two\",\"tool_input\":{\"command\":\"printf daemon_probe_beta_4c72\"},\"tool_response\":{\"output\":\"daemon_probe_beta_4c72\"}}"
  let firstPost ← IO.asTask (send postOne) .dedicated
  let secondPost ← IO.asTask (send postTwo) .dedicated
  let _ ← waitHook firstPost
  let _ ← waitHook secondPost
  let some completed ← readPending? files |
    throw (IO.userError "daemon lost concurrent native results")
  check (completed.inFlight.isEmpty && completed.tools.length = 2)
    "daemon did not close both concurrent native Work occurrences"
  let _ ← send (← hookJson
    "{\"hook_event_name\":\"Stop\",\"session_id\":\"daemon-parallel\",\"turn_id\":\"daemon-turn\",\"last_assistant_message\":\"both probes completed\"}")
  let _ ← send (← hookJson
    "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"daemon-parallel\"}")
  flushDeferred "daemon-parallel" ((← IO.monoMsNow) + 3000)
  let _ ← Plugin.Daemon.exchange endpoint "shutdown"
  match ← IO.wait daemon with
  | .ok 0 => pure ()
  | .ok code => throw (IO.userError s!"eggshelld exited with {code}")
  | .error error => throw error
  check (!(← files.pending.pathExists))
    "concurrent daemon turn was not promoted atomically"
  IO.println "PASS concurrent daemon clients preserve one staged turn"

def testLifecycle : IO Unit := do
  let session := "lifecycle-fencing"
  let files ← sessionFiles session
  let pending := { seed with sessionId := session, turnId := "current", finalMessage := none }
  let initial : ThreadState := { profile := "work", epoch := 8, deliveredGraphs := ["g:old"] }
  let now ← IO.monoMsNow
  let offer : DeliveryOffer := {
    id := "receipt", stamp := { turn := "current", epoch := 8, deadline := now + 10000 },
    graphs := ["g:new"], text := "evidence", reason := "observed" }
  withSession session fun files => do
    writeJson files.pending pending
    writeJson files.state { initial with offers := [offer] }
  acknowledge session "missing"
  let some noReceipt ← readState? files | throw (IO.userError "missing state")
  check (noReceipt.deliveredGraphs == initial.deliveredGraphs)
    "an unacknowledged result was treated as delivered"
  for stamp in [
      { offer.stamp with turn := "old" },
      { offer.stamp with epoch := 7 },
      { offer.stamp with deadline := now }] do
    withSession session fun files =>
      writeJson files.state { initial with offers := [{ offer with stamp }] }
    acknowledge session "receipt"
    let some rejected ← readState? files | throw (IO.userError "missing state")
    check (rejected.deliveredGraphs == initial.deliveredGraphs && rejected.lastHandoff == "")
      "a stale or expired receipt published evidence"
  withSession session fun files => writeJson files.state { initial with offers := [offer] }
  acknowledge session "receipt"
  let some accepted ← readState? files | throw (IO.userError "missing state")
  check (accepted.deliveredGraphs.contains "g:new" && accepted.lastHandoff == "evidence")
    "a current acknowledged result was not published"
  let compacted := compactState { accepted with deliveredGraphs := ["g:new", "h:old", "d:once"] }
  check (compacted.deliveredGraphs == ["d:once"] && compacted.offers.isEmpty)
    "compaction re-armed a checkpoint or retained an old delivery offer"

  let target := testRoot / "incremental.egg"
  let partialTurn := { seed with finalMessage := none, tools := seed.tools.take 1 }
  let _ ← promoteObservations partialTurn target
  let first ← Persistence.load target
  let expected ← IO.ofExcept (stagedGraphValues partialTurn)
  check (first.values == expected.eraseDups)
    "an incremental save fabricated a parent completion or unfinished invocation"
  let _ ← promoteObservations partialTurn target
  let replayed ← Persistence.load target
  check (replayed.values == first.values && replayed.revision == first.revision)
    "replaying a committed observation changed the authority"
  let _ ← promote seed target
  let final ← Persistence.load target
  check (expected.all final.values.contains)
    "final promotion lost an already saved intermediate observation"

  -- A journal can supply a new parent edge for an already committed Outcome.
  -- Deduplicating its bytes must not discard the child's new graph membership.
  let overlapTarget := testRoot / "incremental-overlap.egg"
  let _ ← Persistence.appendPrepared overlapTarget fun graph => do
    let some tx := (Transaction.begin graph).stageValues? (observedRoots partialTurn) |
      throw "invalid observation fixture"
    pure (tx, ())
  let selection : Config.Selection := {
    label := "overlap", semanticMatcher := none, write := none,
    read := [{ name := "overlap", path := overlapTarget }], handoffChars := 120000 }
  let some tool := partialTurn.tools.head? | throw (IO.userError "empty observation fixture")
  let overlapping ← automaticHandoff selection (canonicalToolWork tool) [] true none expected
  check (overlapping.any (·.blocksCurrent))
    "deduplicating a saved Outcome lost its staged parent edge"

  withSession session fun files => IO.FS.writeFile files.state "tr"
  let _ ← dispatchHook (Lean.Json.mkObj [
    ("hook_event_name", "PostCompact"), ("session_id", session)])
  let some repaired ← readState? files | throw (IO.userError "corrupt state was not replaced")
  check (!repaired.enabled) "corrupt state repeatedly poisoned the hook lifecycle"
  let quarantined := (← files.directory.readDir).any (·.fileName.startsWith "state.json.corrupt-")
  check quarantined "corrupt state was destroyed instead of retained"
  IO.println "PASS delivery fencing, incremental observations, idempotent replay, corrupt state recovery"

def testBackgroundIndexRecovery : IO Unit := do
  let session := "index-recovery"
  let files ← sessionFiles session
  let target := ((← IO.currentDir) / testRoot / "indexed.egg").normalize
  let executable ← IO.appPath
  let marker := files.directory / "rejected-index-ack"
  if ← marker.pathExists then IO.FS.removeFile marker
  let tool : ToolEvent := {
    name := "shell", useId := "indexed-observation"
    input := r#"{"command":"printf index_unique_observation"}"#
    response := r#"{"output":"index_unique_observation"}"# }
  let pending : PendingTurn := { seed with
    sessionId := session, turnId := "index-recovery-turn"
    prompt := "record observed evidence"
    semanticMatcher := some [executable.toString, "semantic-provider-fixture",
      "retry-index", marker.toString]
    write := some target.toString, tools := [tool] }
  queueCheckpoint files pending
  let entries ← (files.directory / "checkpoints").readDir
  let some queued := entries.find? (·.fileName.endsWith ".json") |
    throw (IO.userError "missing index recovery queue")
  let payload := Lean.Json.mkObj [
    ("session", .str session), ("path", .str queued.path.toString)]
  let published ← Worker.exchange session "save" payload ((← IO.monoMsNow) + 3000)
  check (published.any fun json => json.getArr?.isOk)
    "indexing failure prevented durable publication"
  check (!(← queued.path.pathExists) && !(← marker.pathExists))
    "writer waited for or started the semantic indexer"
  let tickets ← (files.directory / "indexes").readDir
  check (tickets.size == 1) "publication did not retain one index ticket"
  let some ticketEntry := tickets[0]? | throw (IO.userError "missing index ticket")
  let ticketPath := ticketEntry.path
  let ticketText ← IO.FS.readFile ticketPath
  let some ticket ← (readJson? ticketPath : IO (Option IndexTicket)) |
    throw (IO.userError "missing ticket fixture")
  check (ticketText.length < 1024 && !ticketText.contains "index_unique_observation")
    "index queue copied the observed body instead of referencing it"
  let indexPayload := Lean.Json.mkObj [("paths", Lean.toJson [ticketPath.toString])]
  let first ← Worker.exchange session "index" indexPayload ((← IO.monoMsNow) + 3000)
  check (first.any fun json => (json.getObjValAs? String "error").isOk)
    "an invalid index acknowledgement was accepted"
  check (← ticketPath.pathExists)
    "index failure erased its only replayable queue entry"
  let saved ← Persistence.load target
  check ((observedRoots pending).all saved.values.contains)
    "index failure lost an already committed tool observation"
  check ((committedPromotion? saved { outcomeRelations := [.text "invented owner"] }).isNone)
    "an index batch accepted an owner absent from the committed snapshot"
  let bytes ← IO.FS.readFile (target / "head")
  let second ← Worker.exchange session "index" indexPayload ((← IO.monoMsNow) + 3000)
  check (second.any fun json => (Lean.fromJson? json : Except String Nat).toOption == some 1)
    "unchanged durable queue could not resume after index failure"
  check (!(← ticketPath.pathExists))
    "successful index acknowledgement left the committed queue entry"
  check ((← IO.FS.readFile (target / "head")) == bytes &&
      (← Persistence.load target).revision == saved.revision)
    "retrying indexing rewrote or duplicated the already committed graph"
  let invalid := { ticket with roots := [indexOwnerKey (.text "invented owner")] }
  writeJson ticketPath invalid
  let rejected ← Worker.exchange session "index" indexPayload ((← IO.monoMsNow) + 3000)
  check (rejected.any fun json => (json.getObjValAs? String "error").isOk)
    "index worker warmed an owner absent from its authority"
  check (← ticketPath.pathExists) "unresolved index owner consumed its ticket"
  removeIfExists ticketPath
  IO.println "PASS independent index failure retains tickets and never republishes the graph"

def semanticProviderFixture (index : Nat := 0)
    (retryMarker : Option System.FilePath := none)
    (batchLog : Option System.FilePath := none)
    (contextWindows : List Nat := []) (nominate : Bool := true)
    (entries : Option (List Nat) := none) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let json ← IO.ofExcept (Lean.Json.parse line)
    if let .ok items := json.getObjValAs? (Array Lean.Json) "index" then
      let ids ← IO.ofExcept (items.toList.mapM (·.getObjValAs? String "id"))
      if let some log := batchLog then
        let handle ← IO.FS.Handle.mk log .append
        handle.putStrLn (toString ids.length)
        handle.flush
      let ids ← match retryMarker with
        | some marker =>
            if ← marker.pathExists then pure ids
            else
              IO.FS.writeFile marker "first acknowledgement intentionally invalid"
              pure ["invented-index-id"]
        | none => pure ids
      output.putStr ((Lean.Json.mkObj [("indexed", Lean.toJson ids)]).compress ++ "\n")
    else
      -- The real provider persists its acceleration cache across processes.
      -- This fixture tests nomination authority, independently of that cache.
      let evidence : List SemanticMatcher.WindowChoice :=
        if contextWindows.isEmpty then [] else [⟨index, contextWindows⟩]
      let related := entries.getD (if !nominate then [] else if contextWindows.isEmpty then [index] else [0, index])
      let documents ← IO.ofExcept (match json.getObjValAs? (Array Lean.Json) "documents" with
        | .ok documents => .ok documents
        | .error _ => json.getObjValAs? (Array Lean.Json) "candidates")
      output.putStr ((Lean.Json.mkObj [("related", Lean.toJson related),
        ("ranked", Lean.toJson (List.range documents.size)),
        ("evidence", Lean.toJson evidence)]).compress ++ "\n")
    output.flush
  pure 0

/-- A separate executable entry exercises untrusted interactive pulls. The
fixture rejects text-protocol fallback and checks the exact returned windows. -/
def indexedPullProviderFixture (mode : String) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  let request ← IO.ofExcept (Lean.Json.parse (← input.getLine))
  let documents ← IO.ofExcept (request.getObjValAs? (List Lean.Json) "documents")
  check (documents.length == 1 && !(request.getObjVal? "candidates").isOk)
    "independent provider received full candidate payloads"
  let (document, indices) : Nat × List Nat := match mode with
    | "empty" => (0, [])
    | "too-many" => (0, List.range 33)
    | "duplicate" => (0, [0, 0])
    | "foreign-document" => (1, [0])
    | "foreign-window" => (0, [0, 34])
    | _ => (0, [0, 33])
  let need := (Lean.Json.mkObj [("need_windows", Lean.Json.mkObj [
    ("document", Lean.toJson document), ("indices", Lean.toJson indices)])]).compress
  output.putStrLn need
  output.flush
  let line ← input.getLine
  if line.isEmpty then return 0
  let response ← IO.ofExcept (Lean.Json.parse line)
  let windows ← IO.ofExcept (response.getObjValAs? (List String) "windows")
  check (windows == ["source:0", "source:33"])
    "independent pull received another source or reordered windows"
  if mode == "repeat" then
    output.putStrLn need
    output.flush
    let _ ← input.getLine
  else
    output.putStrLn "{\"related\":[0,0,9999],\"ranked\":[0],\"evidence\":[]}"
    output.flush
  pure 0

def testIndependentProviderBoundary : IO Unit := do
  let executable ← IO.appPath
  let document : Persistence.Store.SearchDocument := {
    owner := 17, work := 5, windows := (List.range 34).map fun index => s!"window:{index}" }
  for mode in ["valid", "empty", "too-many", "duplicate", "foreign-document",
      "foreign-window", "repeat"] do
    let reads ← IO.mkRef ([] : List Nat)
    let response ← SemanticMatcher.nominateIndexed
      [executable.toString, "indexed-pull-provider-fixture", mode]
      "independent request" [document] [] [] fun source index => do
        check (source.owner == document.owner) "pull crossed its source authority"
        reads.modify (· ++ [index.val])
        pure s!"source:{index.val}"
    if mode == "valid" then
      check (response.map (·.related.map (·.document.owner)) == some [document.owner] && (← reads.get) == [0, 33])
        "independent nomination changed duplicate/foreign filtering or bounded pulls"
    else
      check (response.isNone && (← reads.get) == (if mode == "repeat" then [0, 33] else []))
        "invalid pull touched source bytes or repeated a previously supplied window"
  IO.println "PASS independent indexed provider, typed bounded pulls and rejection before source reads"

def semanticLaneHolder (lane : SemanticMatcher.Lane)
    (ready release : System.FilePath) : IO UInt32 := do
  let result ← SemanticMatcher.withLane lane do
    IO.FS.writeFile ready "locked"
    let deadline := (← IO.monoMsNow) + 10000
    while !(← release.pathExists) do
      if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "lane fixture expired")
      IO.sleep 5
  if result.isNone then return 1
  pure 0

def testSaveWhileIndexBusy : IO Unit := IO.FS.withTempDir fun attempt => do
  let some name := attempt.fileName | throw (IO.userError "index fixture has no isolated name")
  let session := "independent-index-" ++ Blake3.hex name.toUTF8
  let files ← sessionFiles session
  Persistence.privateDirectory files.directory
  let target := ((← IO.currentDir) / testRoot / (session ++ ".egg")).normalize
  let executable ← IO.appPath
  let ready := files.directory / "index-lane-ready"
  let release := files.directory / "index-lane-release"
  let batchLog := files.directory / "index-batches"
  let command := [executable.toString, "semantic-provider-fixture", "batch-index", batchLog.toString]
  let body := String.ofList (List.replicate 4096 'x')
  let pendingFor (index : Nat) : PendingTurn := { seed with
    sessionId := session, turnId := "independent-index-turn"
    prompt := "retain progress while the model is unavailable"
    semanticMatcher := some command, write := some target.toString, finalMessage := none
    tools := [{
      name := "Bash"
      useId := s!"independent-{index}"
      input := s!"inspect file-{index}"
      response := s!"observed-{index}:" ++ body }] }
  let save (pending : PendingTurn) : IO Nat := do
    queueCheckpoint files pending
    let entries ← (files.directory / "checkpoints").readDir
    let some queued := entries.find? (·.fileName.endsWith ".json") |
      throw (IO.userError "save fixture has no checkpoint")
    let started ← IO.monoMsNow
    let result ← Worker.exchange session "save" (Lean.Json.mkObj [
      ("session", session), ("path", queued.path.toString)]) (started + 3000)
    let elapsed := (← IO.monoMsNow) - started
    check (result.any fun json => json.getArr?.isOk) "independent writer failed"
    pure elapsed
  let holder ← IO.Process.spawn {
    cmd := executable.toString
    args := #["semantic-lane-holder", "index", ready.toString, release.toString]
    stdin := .null, stdout := .null, stderr := .inherit, setsid := true }
  let holderReaped ← IO.mkRef false
  try
    let deadline := (← IO.monoMsNow) + 3000
    while !(← ready.pathExists) do
      if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "index holder did not start")
      IO.sleep 5
    let firstMs ← save (pendingFor 0)
    let firstTickets ← (files.directory / "indexes").readDir
    check (firstTickets.size == 1 && !(← batchLog.pathExists))
      "saving started the unavailable indexer"
    let some firstTicket := firstTickets[0]? | throw (IO.userError "missing first index ticket")
    let indexing ← IO.asTask (Worker.exchange session "index" (Lean.Json.mkObj [
      ("paths", Lean.toJson [firstTicket.path.toString])])
      ((← IO.monoMsNow) + 3000)) .dedicated
    let slot ← Worker.slotFor session "index"
    while (← slot.gate.tryAtomically (pure ())).isSome do
      if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "index task did not enter its lane")
      IO.sleep 5
    let secondMs ← save (pendingFor 1)
    check (firstMs < 2000 && secondMs < 2000 && !(← IO.hasFinished indexing))
      "an occupied index lane delayed the independent writer"
    let graph ← Persistence.load target
    check ((observedRoots (pendingFor 0) ++ observedRoots (pendingFor 1)).all graph.values.contains)
      "a slow indexer prevented subsequent tool progress from being saved"
    check ((← (files.directory / "indexes").readDir).size == 2)
      "unfinished index batch consumed publication tickets"
    IO.FS.writeFile release "continue"
    let _ ← holder.wait
    holderReaped.set true
    let .ok indexed ← IO.wait indexing | throw (IO.userError "index worker failed after lease release")
    check (indexed.any fun json => (Lean.fromJson? json : Except String Nat).toOption == some 1)
      "released indexer did not acknowledge its original batch"
    for index in List.range 7 do
      let _ ← save (pendingFor (index + 2))
    let entries ← (files.directory / "indexes").readDir
    check (entries.size == 8) "independent publications lost an indexing ticket"
    let before ← IO.FS.readFile (target / "head")
    let result ← Worker.exchange session "index" (Lean.Json.mkObj [
      ("paths", Lean.toJson (entries.toList.map (·.path.toString)))])
      ((← IO.monoMsNow) + 3000)
    check (result.any fun json => (Lean.fromJson? json : Except String Nat).toOption == some 8)
      "compatible tickets were not indexed as one acknowledged batch"
    check ((← IO.FS.readFile batchLog).trimAscii.toString == "1\n8" &&
        (← IO.FS.readFile (target / "head")) == before &&
        (← (files.directory / "indexes").readDir).isEmpty)
      "index batching republished the graph, repeated a model batch, or left acknowledged tickets"
    IO.println s!"PASS blocked indexer leaves saving independent ({firstMs}ms/{secondMs}ms), batches eight tickets without graph writes"
  finally
    if !(← holderReaped.get) then
      try holder.kill catch _ => pure ()
      let _ ← holder.wait
      pure ()
    Worker.cancel session "index"
    Worker.cancel session "save"

def testSemanticResourceLanes : IO Unit := do
  let executable ← IO.appPath
  let ready := ((← IO.currentDir) / testRoot / "lane-ready").normalize
  let release := ((← IO.currentDir) / testRoot / "lane-release").normalize
  let holder ← IO.Process.spawn {
    cmd := executable.toString
    args := #["semantic-lane-holder", "search", ready.toString, release.toString]
    stdin := .null, stdout := .null, stderr := .inherit, setsid := true }
  try
    let deadline := (← IO.monoMsNow) + 3000
    while !(← ready.pathExists) do
      if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "lane holder did not start")
      IO.sleep 5
    let started ← IO.monoMsNow
    let busy ← SemanticMatcher.withLane .search (pure true)
    check (busy.isNone && (← IO.monoMsNow) - started < 500)
      "a second search waited behind the device-wide search lane"
    let independent ← SemanticMatcher.withLane .index (pure true)
    check (independent == some true)
      "a busy search blocked the independent indexing lane"
    let selection : Config.Selection := {
      label := "busy-search", read := [{ name := "memory", path := semanticEgg }]
      write := none, handoffChars := 24000, semanticMatcher := some [executable.toString,
        "semantic-provider-fixture", "retrieval"] }
    let some handoff ← automaticHandoff selection "different inquiry" [] false |
      throw (IO.userError "an unrelated provider guard blocked independent search")
    check (handoff.reason != "search-incomplete")
      "cached/provider search still waits for a whole-search exclusive guard"
  finally
    holder.kill
    let _ ← holder.wait
    pure ()
  let released ← SemanticMatcher.withLane .search (pure true)
  check (released == some true)
    "a killed lane owner left a stale logical lock"
  -- Exercise the real numerical boundary before any heavy model import.
  let layout := MiniLM.layout (← Paths.installRoot) (← Paths.dataRoot)
  let some python ← MiniLM.runtimePython? layout |
    throw (IO.userError "numerical lane regression requires the installed MiniLM runtime")
  let reservation ← SemanticMatcher.lanePath .search
  let lease := reservation.withFileName ("model-" ++ reservation.fileName.getD "lane.guard")
  let handle ← IO.FS.Handle.mk lease .append
  handle.lock
  try
    let child ← IO.Process.spawn {
      cmd := python.toString
      args := #["-c", MiniLM.embeddingSource, MiniLM.model, layout.models.toString,
        "4", lease.toString, "search"]
      stdin := .piped, stdout := .piped, stderr := .inherit }
    try
      child.stdin.putStrLn "{\"queries\":[[1.0]],\"candidates\":[[[1.0]]]}"
      child.stdin.flush
      let scored ← IO.asTask child.stdout.getLine .dedicated
      let some output ← Worker.awaitUntil scored ((← IO.monoMsNow) + 3000) |
        throw (IO.userError "cached numerical scoring waited behind model inference")
      let scores ← IO.ofExcept <| (← IO.ofExcept (Lean.Json.parse output)).getObjVal? "scores"
      let values ← IO.ofExcept scores.getArr?
      check (values.size == 1 && (SearchProvider.number values[0]!).toOption == some 1.0)
        "concurrent cached numerical scoring changed its result"
      child.stdin.putStrLn "{\"texts\":[\"must wait for inference\"]}"
      child.stdin.flush
      let waiting ← IO.asTask child.stdout.getLine .dedicated
      let blocked ← Worker.awaitUntil waiting ((← IO.monoMsNow) + 100)
      check (blocked.isNone)
        "a second numerical process inferred without owning its model resource lease"
      child.kill
      let _ ← IO.wait waiting
      pure ()
    finally
      try child.kill catch _ => pure ()
      let _ ← child.wait
      pure ()
  finally
    handle.unlock
  IO.println "PASS model lifetime leases, independent cached scoring, waiting inference and killed-owner recovery"

def testParallelSearchAdmission : IO Unit := do
  let pool : Worker.ReadPool := {
    left := { gate := ← Std.Mutex.new (), child := ← Std.Mutex.new none }
    right := { gate := ← Std.Mutex.new (), child := ← Std.Mutex.new none } }
  let active ← Std.Mutex.new ([] : List Nat)
  let releaseLeft ← IO.Promise.new (α := Unit)
  let releaseRight ← IO.Promise.new (α := Unit)
  let expiredStarted ← IO.mkRef false
  let deadline := (← IO.monoMsNow) + 3000
  let first ← IO.asTask (Worker.withReadPoolWithin pool deadline fun admission => do
    active.atomically (modify (admission.lane.val :: ·))
    let _ ← IO.wait releaseLeft.result?
    pure (11 : Nat)) .dedicated
  let second ← IO.asTask (Worker.withReadPoolWithin pool deadline fun admission => do
    active.atomically (modify (admission.lane.val :: ·))
    let _ ← IO.wait releaseRight.result?
    pure (22 : Nat)) .dedicated
  try
    while (← active.atomically get).length < 2 do
      if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "two independent reads did not overlap")
      IO.sleep 5
    check ((← active.atomically get).eraseDups.length == 2)
      "overlapping readers owned the same reply pipe"
    let expired ← Worker.withReadPoolWithin pool ((← IO.monoMsNow) + 50) fun _ => do
      expiredStarted.set true
      pure (33 : Nat)
    check (expired.isNone && !(← expiredStarted.get) &&
      !(← IO.hasFinished first) && !(← IO.hasFinished second))
      "an expired queued search started or interrupted another reader"
    releaseLeft.resolve ()
    check ((← IO.ofExcept (← IO.wait first)) == some 11) "first read received another response"
    let third ← Worker.withReadPoolWithin pool ((← IO.monoMsNow) + 1000)
      (fun _ => pure (33 : Nat))
    check (third == some 33 && !(← IO.hasFinished second))
      "an independent read could not reuse the idle pipe while the other read stayed active"
    releaseRight.resolve ()
    check ((← IO.ofExcept (← IO.wait second)) == some 22) "second read received another response"
    let ended ← Worker.withReadPoolWithin pool ((← IO.monoMsNow) - 1) fun _ => do
      expiredStarted.set true
      pure (44 : Nat)
    check (ended.isNone && !(← expiredStarted.get)) "closed read admission started work"
  finally
    releaseLeft.resolve ()
    releaseRight.resolve ()
    let _ ← IO.wait first
    let _ ← IO.wait second
    pure ()
  IO.println "PASS two overlapping read lanes, isolated responses, queued expiry and free-lane reuse"

/-- Independent observations deliberately return the same primary order
but a changing source-focus order. No model or encoder is used by this fixture. -/
def observedFocusProvider (root : System.FilePath) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  let request ← IO.ofExcept (Lean.Json.parse (← input.getLine))
  let query ← IO.ofExcept ((request.getObjValD "query").getObjValAs? String "text")
  let documents ← IO.ofExcept (request.getObjValAs? (Array Lean.Json) "documents")
  let primary := query == (← IO.FS.readFile (root / "primary-query"))
  unless primary do
    IO.FS.writeFile (root / "focus-query") query
    let count ← if ← (root / "focus-calls").pathExists then do
        let previous ← IO.FS.readFile (root / "focus-calls")
        pure (previous.toNat?.getD 0)
      else pure 0
    IO.FS.writeFile (root / "focus-calls") (toString (count + 1))
  let order := List.range documents.size
  let order := if !primary && (← (root / "reverse").pathExists) then order.reverse else order
  let evidence := order.map (fun index =>
    ({document := index, indices := [0]} : SemanticMatcher.WindowChoice))
  output.putStrLn (Lean.Json.mkObj [("related", Lean.toJson ([0] : List Nat)),
    ("ranked", Lean.toJson order), ("evidence", Lean.toJson evidence)]).compress
  output.flush
  pure 0

/-- Hold an actual provider pipe open until its search worker is cancelled. -/
def stalledPipePeer (ready : System.FilePath) : IO UInt32 := do
  let line ← (← IO.getStdin).getLine
  if line.isEmpty then return 1
  IO.FS.writeFile ready (toString (← IO.Process.getPID))
  IO.sleep 30000
  pure 0

/-- Each real provider writes its own PID, then waits for its query's release.
The test observes overlapping processes and cancellation without model calls. -/
def controlledSearchProvider (root : System.FilePath) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  let request ← IO.ofExcept (Lean.Json.parse (← input.getLine))
  let query ← IO.ofExcept <| (← IO.ofExcept (request.getObjVal? "query")).getObjValAs? String "text"
  let key := Sha256.hex query.toUTF8
  IO.FS.writeFile (root / (key ++ ".pid")) (toString (← IO.Process.getPID))
  let deadline := (← IO.monoMsNow) + 10000
  while !(← (root / (key ++ ".release")).pathExists) do
    if (← IO.monoMsNow) ≥ deadline then return 1
    IO.sleep 5
  let documents ← IO.ofExcept (request.getObjValAs? (Array Lean.Json) "documents")
  output.putStrLn (Lean.Json.mkObj [("related", Lean.toJson ([0] : List Nat)),
    ("ranked", Lean.toJson (List.range documents.size)), ("evidence", Lean.toJson ([] : List SemanticMatcher.WindowChoice))]).compress
  output.flush
  pure 0

/-- A real provider process whose external answer can change without a DB
publication or a configuration change. Used to test observation-bound reuse. -/
def observedSearchProvider (root : System.FilePath) : IO UInt32 := do
  let input ← IO.getStdin
  let output ← IO.getStdout
  let request ← input.getLine
  let _ ← IO.ofExcept (Lean.Json.parse request)
  IO.FS.writeFile (root / "request.json") request
  let count ← if ← (root / "calls").pathExists then do
      let text ← IO.FS.readFile (root / "calls")
      pure (text.trimAscii.toString.toNat?.getD 0)
    else pure 0
  IO.FS.writeFile (root / "calls") (toString (count + 1))
  output.putStrLn (← IO.FS.readFile (root / "response.json"))
  output.flush
  pure 0

def testParallelSearchPipes : IO Unit := IO.FS.withTempDir fun root => do
  let session := "parallel-search-pipes"
  let files ← sessionFiles session
  -- PID/release markers belong to this provider generation. A previous run's
  -- marker must not certify readiness or release the current provider.
  let executable ← IO.appPath
  let pending : PendingTurn := {seed with
    sessionId := session, turnId := "parallel-read-turn", finalMessage := none,
    tools := [], inFlight := [], closed := false, read := [semanticEgg.toString],
    semanticMatcher := some [executable.toString, "controlled-search-provider", root.toString] }
  let state : ThreadState := { profile := "work" }
  writeJson files.state state
  writeJson files.pending pending
  let query := fun work => Lean.toJson ({ pending, state, work, enforce := false } : Worker.Search)
  let leftText := "first parallel evidence request"
  let rightText := "second parallel evidence request"
  let path := fun text suffix => root / (Sha256.hex text.toUTF8 ++ suffix)
  let started ← IO.monoMsNow
  let first ← IO.asTask (Worker.exchange session "search" (query leftText) (started + 1500)) .dedicated
  let second ← IO.asTask (Worker.exchange session "search" (query rightText) (started + 5000)) .dedicated
  try
    while !(← (path leftText ".pid").pathExists) || !(← (path rightText ".pid").pathExists) do
      if (← IO.monoMsNow) ≥ started + 1400 then
        throw (IO.userError "two production search pipes did not enter their providers concurrently")
      IO.sleep 5
    let leftPid := (← IO.FS.readFile (path leftText ".pid")).trimAscii.copy
    let rightPid := (← IO.FS.readFile (path rightText ".pid")).trimAscii.copy
    check (leftPid != rightPid) "two searches used the same provider process"
    let expired ← Worker.exchange session "search" (query "queued third request")
      ((← IO.monoMsNow) + 50)
    check (expired.isNone && !(← (path "queued third request" ".pid").pathExists))
      "an expired queued request wrote to another search's pipe"
    let leftAlive ← IO.Process.output { cmd := "/bin/kill", args := #["-0", leftPid] }
    let rightAlive ← IO.Process.output { cmd := "/bin/kill", args := #["-0", rightPid] }
    check (leftAlive.exitCode == 0 && rightAlive.exitCode == 0)
      "queued expiry killed an active reader"
    let ended ← IO.ofExcept (← IO.wait first)
    check (ended.isNone) "timed-out production search produced a successful response"
    let leftGone ← IO.Process.output { cmd := "/bin/kill", args := #["-0", leftPid] }
    let rightStillAlive ← IO.Process.output { cmd := "/bin/kill", args := #["-0", rightPid] }
    check (leftGone.exitCode != 0 && rightStillAlive.exitCode == 0 &&
        !(← IO.hasFinished second))
      "one search's deadline killed another reader or leaked its own provider"
    IO.FS.writeFile (path rightText ".release") "continue"
    let response ← IO.ofExcept (← IO.wait second)
    let some json := response | throw (IO.userError "unrelated read lost its result")
    let handoff ← IO.ofExcept (Lean.fromJson? json : Except String (Option Handoff))
    check (handoff.any fun result => result.reason != "search-incomplete" &&
      result.text.contains rightText)
      "the surviving search received a wrong or incomplete handoff"
    let rightGone ← IO.Process.output { cmd := "/bin/kill", args := #["-0", rightPid] }
    check (rightGone.exitCode != 0) "finished read retained its provider child"
    IO.println s!"PASS overlapping production search pipes, queued expiry, isolated {((← IO.monoMsNow) - started)}ms timeout and surviving handoff"
  finally
    Worker.cancel session "search"
    let _ ← IO.wait first
    let _ ← IO.wait second
    pure ()

def testSearchAdmission : IO Unit := do
  let gate ← Std.Mutex.new ()
  let entered ← IO.Promise.new (α := Unit)
  let release ← IO.Promise.new (α := Unit)
  let started ← IO.mkRef false
  let expiredStarted ← IO.mkRef false
  let now ← IO.monoMsNow
  let holder ← IO.asTask (Worker.withGateWithin gate (now + 3000) fun _ => do
    entered.resolve ()
    let _ ← IO.wait release.result?
    pure (900 : Nat)) .dedicated
  let _ ← IO.wait entered.result?
  try
    let deadline := (← IO.monoMsNow) + 3000
    let waiting ← (List.range 4).mapM fun request =>
      IO.asTask (Worker.withGateWithin gate deadline fun _ => do
        started.set true
        IO.sleep 5
        pure request) .dedicated
    let shortDeadline := (← IO.monoMsNow) + 50
    let short ← Worker.withGateWithin gate shortDeadline fun _ => do
      expiredStarted.set true
      pure (901 : Nat)
    check (short.isNone && !(← expiredStarted.get) && !(← started.get))
      "an expired contended request started or bypassed the active worker"
    check (!(← IO.hasFinished holder))
      "a waiting request's deadline cancelled another request's worker"
    release.resolve ()
    let kept ← IO.ofExcept (← IO.wait holder)
    check (kept == some 900) "waiter expiry lost the active request's result"
    for (request, task) in (List.range 4).zip waiting do
      let result ← IO.ofExcept (← IO.wait task)
      check (result == some request)
        "a contended request was dropped or received another request's response"
    let closed := (← IO.monoMsNow) - 1
    let expired ← Worker.withGateWithin gate closed fun _ => do
      expiredStarted.set true
      pure (902 : Nat)
    check (expired.isNone && !(← expiredStarted.get))
      "a deadline-expired request started after the worker became idle"
    let empty ← Worker.withGateWithin gate ((← IO.monoMsNow) + 1000)
      (fun _ => pure (none : Option Nat))
    check (empty == some none)
      "a completed empty action was confused with contention or expiry"
    let oldState : ThreadState := { profile := "work", deliveredGraphs := [] }
    let request : Worker.Search := {
      pending := {seed with closed := false, finalMessage := none}, state := oldState,
      work := "queued demand", enforce := false }
    let currentState := {oldState with deliveredGraphs := ["acknowledged-while-waiting"]}
    let refreshed := Worker.currentSearch? request currentState request.pending
    check (refreshed.any (·.state.deliveredGraphs == currentState.deliveredGraphs))
      "a waiting request retained its pre-wait delivery receipts"
    check ((Worker.currentSearch? request {currentState with epoch := currentState.epoch + 1}
      request.pending).isNone &&
      (Worker.currentSearch? request currentState {request.pending with turnId := "replaced"}).isNone &&
      (Worker.currentSearch? request {currentState with enabled := false} request.pending).isNone &&
      (Worker.currentSearch? request currentState {request.pending with closed := true}).isNone)
      "an expired context, replaced turn, disabled memory or closed turn admitted queued search"
  finally
    release.resolve ()
  IO.println "PASS bounded search admission, four contended requests, response ownership and independent waiter expiry"

def testIncompleteSearchDelivery : IO Unit := do
  let stamp : RequestStamp := { turn := "active", epoch := 3, deadline := 100 }
  let absent := Worker.SearchDelivery.ofReply stamp "active" 3 99 24000 none
  let empty := Worker.SearchDelivery.ofReply stamp "active" 3 99 24000 (some Lean.Json.null)
  check (absent.handoff.any (·.text == pendingSearch.text) && empty.handoff.isNone)
    "missing worker response was conflated with a completed empty search"
  let overflowText := String.ofList (List.replicate (Config.nativeHandoffBytes / 3 + 1) '界')
  let unicode := {pendingSearch with text := overflowText}
  let oversized := Worker.SearchDelivery.ofReply stamp "active" 3 99 120000 (some (Lean.toJson (some unicode)))
  check (unicode.text.length < 120000 && unicode.text.utf8ByteSize > Config.nativeHandoffBytes &&
      oversized.handoff.any (fun h => h.text == pendingSearch.text && h.completed == 0 &&
        !h.blocksCurrent && h.deliveredGraphs.isEmpty))
    "a character-fitting Unicode response crossed the native byte bound"
  let boundaryText := String.ofList (List.replicate (Config.nativeHandoffBytes / 3) '界') ++
    String.ofList (List.replicate (Config.nativeHandoffBytes % 3) 'a')
  let atBoundary := {pendingSearch with text := boundaryText}
  let accepted := Worker.SearchDelivery.ofReply stamp "active" 3 99 120000
    (some (Lean.toJson (some atBoundary)))
  check (atBoundary.text.utf8ByteSize == Config.nativeHandoffBytes &&
      accepted.handoff.any (·.text == atBoundary.text))
    "the native byte ceiling rejected a complete valid UTF-8 packet at its exact boundary"
  for raw in [none, some (Lean.Json.mkObj [("error", .str "reader failed")]),
      some (Lean.Json.str "invalid search payload")] do
    let result := Worker.SearchDelivery.ofReply stamp "active" 3 99 24000 raw
    check (result.handoff.any fun h => h.completed == 0 && !h.blocksCurrent &&
        h.deliveredGraphs.isEmpty && h.coveredFragments.isEmpty)
      "incomplete worker response certified or suppressed native work"
  let expired := Worker.SearchDelivery.ofReply stamp "active" 3 100 24000 (some Lean.Json.null)
  check (expired.handoff.any (·.text == pendingSearch.text))
    "deadline expiry hid the search status"
  check ((Worker.SearchDelivery.ofReply stamp "new-turn" 3 99 24000 none).handoff.isNone &&
      (Worker.SearchDelivery.ofReply stamp "active" 4 99 24000 none).handoff.isNone)
    "an obsolete search delivered a notice into a different context"
  for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse"] do
    for raw in [none, some (Lean.Json.mkObj [("error", .str "RPC failed")]),
        some (Lean.Json.mkObj [("output", .str "true")]),
        some (Lean.Json.mkObj [("output", .str "not-json")])] do
      let reply := Plugin.Daemon.decodeHookReply raw
      let output ← IO.ofExcept (Lean.Json.parse (reply.output event))
      check (!reply.isComplete &&
          (output.getObjVal? "hookSpecificOutput").toOption.any (fun o =>
            (optionalString o "additionalContext") == some pendingSearch.text &&
            (optionalString o "permissionDecision").isNone))
        "an incomplete native hook became empty, authoritative or a tool denial"
    let normal := hookContext event "unchanged prior evidence"
    let reply := Plugin.Daemon.decodeHookReply
      (some (Lean.Json.mkObj [("output", .str normal)]))
    check (reply.isComplete && reply.output event == normal)
      "native reply validation changed successful handoff bytes"
  let completedEmpty := Plugin.Daemon.decodeHookReply
    (some (Lean.Json.mkObj [("output", .str emptyHook)]))
  check (completedEmpty.isComplete && completedEmpty.output "UserPromptSubmit" == emptyHook)
    "a valid empty native hook was misreported as incomplete"

  -- Search failure must not discard the already journaled native observation.
  let root := ((← IO.currentDir) / testRoot / "incomplete-search").normalize
  IO.FS.createDirAll root
  let corrupt := root / "corrupt.egg"
  let saved := root / "saved.egg"
  IO.FS.writeFile corrupt "not an Eggshell graph"
  let session := "incomplete-search"
  let files ← sessionFiles session
  let pending : PendingTurn := { seed with
    sessionId := session, turnId := "observed", read := [corrupt.toString]
    write := some saved.toString, semanticMatcher := none, finalMessage := none
    tools := [], inFlight := [], closed := false, handoffChars := 24000 }
  writeJson files.state ({ profile := "work" } : ThreadState)
  writeJson files.pending pending
  let post := Lean.Json.mkObj [
    ("hook_event_name", .str "PostToolUse"), ("session_id", .str session),
    ("turn_id", .str pending.turnId), ("tool_name", .str "shell"),
    ("tool_use_id", .str "durable-result"),
    ("tool_input", Lean.Json.mkObj [("command", .str "inspect durable evidence")]),
    ("tool_response", Lean.Json.mkObj [("output", .str "preserved-evidence-917c")])]
  captureTerminal post
  let failed ← postToolUse post
  check (failed == hookContext "PostToolUse" pendingSearch.text)
    "a real storage-reader error silently omitted its handoff"
  let some state ← readState? files | throw (IO.userError "failure lost state")
  check (state.offers.isEmpty)
    "incomplete search created a completion offer"
  let some journal ← readPending? files | throw (IO.userError "failure lost pending turn")
  check (journal.tools.length == 1 &&
      journal.tools.head?.any (·.response.contains "preserved-evidence-917c"))
    "search failure discarded the journaled native result"
  flushDeferred session ((← IO.monoMsNow) + 3000)
  let persisted ← Persistence.load saved
  check ((observedRoots journal).all persisted.values.contains)
    "search failure prevented independent durable saving"
  let noMatches : PendingTurn := { pending with read := [(root / "absent.egg").toString] }
  writeJson files.pending noMatches
  check (← (deliverForWork (Lean.Json.mkObj []) noMatches "unrelated query" false).map
      (·.isNone))
    "a finished search of empty memory was incorrectly reported as failed"

  -- The production pipe deadline cancels a live provider, not just a model of
  -- a timeout. Its process-group child must be gone before returning.
  let executable ← IO.appPath
  let ready := root / "provider.pid"
  let stalled : PendingTurn := { pending with
    read := [semanticEgg.toString]
    semanticMatcher := some [executable.toString, "stalled-semantic-provider", ready.toString] }
  writeJson files.pending stalled
  let before ← IO.FS.readFile (saved / "head")
  let start ← IO.monoMsNow
  let input := Lean.Json.mkObj [("_eggshell_deadline", Lean.toJson (start + 1000))]
  let notice ← deliverForWork input stalled "different evidence inquiry" false
  let elapsed := (← IO.monoMsNow) - start
  check (notice.any (·.text == pendingSearch.text) && elapsed < 2000 &&
      (← ready.pathExists))
    s!"live search timeout: elapsed={elapsed}ms notice={notice.map (·.reason)} ready={← ready.pathExists}"
  let pid := (← IO.FS.readFile ready).trimAscii.copy
  let alive ← IO.Process.output { cmd := "/bin/kill", args := #["-0", pid] }
  check (alive.exitCode != 0)
    "search timeout left its numerical/provider child alive"
  check ((← IO.FS.readFile (saved / "head")) == before &&
      (← readPending? files).any (fun p => p.tools.length == 1))
    "search cancellation mutated durable memory or lost its journal"
  let some state ← readState? files | throw (IO.userError "timeout lost state")
  check (state.offers.isEmpty)
    "expired search reserved a checkpoint or delivery offer"
  let rpcReady := root / "rpc.pid"
  let rpcStart ← IO.monoMsNow
  let rpc ← Plugin.Daemon.boundedRpc ("stalled-rpc:" ++ rpcReady.toString)
    (Lean.Json.mkObj []) (rpcStart + 1000)
  let rpcElapsed := (← IO.monoMsNow) - rpcStart
  check (rpc.isNone && rpcElapsed < 2000 && (← rpcReady.pathExists) &&
      (Plugin.Daemon.decodeHookReply none).output "PreToolUse" ==
        hookContext "PreToolUse" pendingSearch.text)
    "a live native RPC timeout hid its incomplete status"
  let rpcPid := (← IO.FS.readFile rpcReady).trimAscii.copy
  let rpcAlive ← IO.Process.output { cmd := "/bin/kill", args := #["-0", rpcPid] }
  check (rpcAlive.exitCode != 0)
    "RPC timeout left its supervised child alive"
  let nativeWithInput ← IO.Process.spawn {
    cmd := executable.toString, args := #["codex-hook"]
    stdin := .piped, stdout := .piped, stderr := .null }
  let native ← do
    let (stdin, native) ← nativeWithInput.takeStdin
    stdin.putStr ((Lean.Json.mkObj [("hook_event_name", .str "PreToolUse"),
      ("session_id", Lean.toJson (42 : Nat))]).compress ++ "\n")
    stdin.flush
    pure native
  let nativeOutput ← native.stdout.readToEnd
  let code ← native.wait
  check (code == 0 && nativeOutput.trimAscii.copy ==
      hookContext "PreToolUse" pendingSearch.text)
    "a real RPC error was emitted by codex-hook as a completed empty response"
  IO.println s!"PASS incomplete search/RPC states, live {elapsed}ms/{rpcElapsed}ms timeouts and durable saving"

def testIncrementalSearch : IO Unit := do
  let owner := OutcomeEdge.make (.text "alpha common") (.text "answer one") [] (by simp) (by simp)
  let added := OutcomeEdge.make (.text "beta common") (.text "answer two") [] (by simp) (by simp)
  let corrected := OutcomeEdge.make owner.work (.text "answer new") [] (by simp) (by simp)
  let graph : WorkGraph := { outcomes := [owner] }
  let prepared := TestOracle.CorpusCache.prepare LogicalText.logicalNormalizer {} graph
  let repeated := TestOracle.CorpusCache.prepare LogicalText.logicalNormalizer prepared.index graph
  check (prepared.freshCompiles == 1 && repeated.freshCompiles == 0)
    "unchanged owners were recompiled"
  let grown : WorkGraph := { outcomes := [owner, added] }
  let next := TestOracle.CorpusCache.prepare LogicalText.logicalNormalizer prepared.index grown
  check (next.freshCompiles == 1 && next.corpus.frequency "common" == 2)
    "new matches or global frequency changes were missed"
  let reordered := TestOracle.CorpusCache.prepare LogicalText.logicalNormalizer next.index
    { outcomes := [added, owner] }
  check (reordered.freshCompiles == 0 &&
      reordered.corpus.candidates.map (·.edge.relation) == [added.relation, owner.relation])
    "incremental corpus changed the reference candidate order"
  let replaced := TestOracle.CorpusCache.prepare LogicalText.logicalNormalizer next.index
    { outcomes := [corrected, added] }
  check (replaced.freshCompiles == 1 && replaced.index.entries[owner.relation]?.isNone)
    "a corrected owner retained stale compilation"
  let removed := TestOracle.CorpusCache.prepare LogicalText.logicalNormalizer next.index graph
  check (removed.freshCompiles == 0 && removed.corpus.frequency "common" == 1 &&
      removed.index.entries[added.relation]?.isNone)
    "removed owners survived in the corpus or frequency index"
  let input : SearchMemo.Input := {
    sources := ["source-a"], authorities := [], origins := [], unionOrigins := []
    values := [owner.relation], unions := [], graph, current := "alpha common"
    evidence := none, semantic := {}, localUnion := true, native := false }
  let (_, cache) := SearchMemo.get none input prepared
  check (SearchMemo.lookup cache input |>.isSome)
    "identical semantic request did not reuse discovery and extraction"
  for changed in [
      {input with sources := ["source-b"]},
      {input with authorities := [.text "new authority"]},
      {input with values := [owner.relation, added.relation], graph := grown},
      {input with values := [corrected.relation], graph := {outcomes := [corrected]}},
      {input with current := "different demand"},
      {input with semantic := {related := [added.relation]}},
      {input with evidence := some "new evidence"},
      {input with localUnion := false}, {input with native := true}] do
    check (SearchMemo.lookup cache changed |>.isNone)
      "changed semantic dependency reused an old result"
  let edge : UnionEdge := ⟨.text "alpha", .text "beta", .run (.text "request"), by intro _; rfl⟩
  let more : UnionEdge := ⟨.text "beta", .text "gamma", edge.scope, by intro _; rfl⟩
  let index := QuotientBuilder.AtomQuotient.Index.empty.append [edge] (by
    intro item member; simp only [List.mem_singleton] at member; subst item; rfl)
  let extended := index.append [more, edge] (by
    intro item member; simp at member
    rcases member with rfl | rfl <;> rfl)
  check (extended.partition == QuotientBuilder.mergeExplicit [] [edge, more, edge])
    "incremental transitive/duplicate Union differs from a fresh fold"
  let correctedIndex := QuotientBuilder.AtomQuotient.prepare [more]
  check (correctedIndex.any fun corrected =>
      !QuotientBuilder.same corrected.partition edge.left edge.right)
    "replacement retained a retracted Union"
  IO.println "PASS incremental owners, frequency/order/correction/removal, complete memo invalidation and delta Union"

def testSignatureDependencies : IO Unit := do
  let a := Value.text "alpha"
  let b := Value.text "beta"
  let c := Value.text "corrected"
  let leaves := [a, b, c]
  let references := [Refs.nil, .semantic a .nil, .exact a .nil,
    .semantic a (.exact b .nil), .exact a (.semantic b .nil),
    .semantic a (.semantic a .nil), .semantic b (.exact c (.semantic a .nil))]
  let values := leaves ++ Operator.allValues.flatMap fun operator =>
    references.map (Value.apply operator)
  let indexes : List QuotientBuilder.Representatives := [{},
    Std.HashMap.ofList [(a, b)], Std.HashMap.ofList [(a, c), (b, c)],
    Std.HashMap.ofList [(a, a), (b, b), (c, c)], Std.HashMap.ofList [(a, b), (b, a)]]
  let mut comparisons := 0
  for index in indexes do
    -- Includes valid former signatures, unrelated values and changed
    -- operator/authority/length. Current classes decide every reuse.
    let observations := values ++ values.map (QuotientBuilder.signature index)
    for source in values do
      let expected := QuotientBuilder.signature index source
      let cold := QuotientBuilder.CongruenceMemo.prepareSignature none index source
      check (cold.key.value == expected && !cold.reused)
        "cold signature dependency compilation changed the canonical signature"
      for observed in observations do
        let key := QuotientBuilder.CongruenceMemo.Key.make observed
        let prepared := QuotientBuilder.CongruenceMemo.prepareSignature (some key) index source
        check (prepared.key.value == expected && prepared.reused == (observed == expected))
          "current signature dependency check accepted stale classes or missed a valid key"
        comparisons := comparisons + 1
  let a2 := Value.text "other alpha"
  let b2 := Value.text "other beta"
  let apply := fun value => Value.applyList .inquiry [Ref.semantic value]
  let pinned := fun value => Value.applyList .receipt [Ref.exact value]
  let index : QuotientBuilder.Representatives := Std.HashMap.ofList [(a2, a), (b2, b)]
  let originals := [apply a, apply b, apply a2, apply b2, pinned a, pinned b]
  let originalRows := QuotientBuilder.CongruenceMemo.prepareRows [] index originals
  let script := QuotientBuilder.CongruenceMemo.Script.make {} originalRows.rows
  for first in [apply c, apply a2] do
    let updated := first :: originals.tail
    let rows := QuotientBuilder.CongruenceMemo.prepareRows (originalRows.rows.map Prod.fst) index updated
    let repaired := script.repair {} originalRows.rows rows.rows
    check (repaired.instructions == QuotientBuilder.CongruenceMemo.instructions {} rows.rows &&
      repaired.reused == 4 && repaired.computed == 2)
      "one corrected signature rebuilt unrelated keys or retained the withdrawn first source"
  for updated in [originals.tail, originals.reverse, originals ++ [apply c],
      [pinned a, apply b, apply a2, apply b2, pinned a, pinned b], []] do
    let rows := QuotientBuilder.CongruenceMemo.prepareRows (originalRows.rows.map Prod.fst) index updated
    let repaired := script.repair {} originalRows.rows rows.rows
    check (repaired.instructions == QuotientBuilder.CongruenceMemo.instructions {} rows.rows &&
      repaired.reused + repaired.computed == rows.rows.length)
      "sparse join dependencies missed deletion, reordering, new negative/positive keys or authority correction"
  IO.println ((Lean.Json.mkObj [("kind", .str "signature_dependencies"),
    ("complete_signature_comparisons", Lean.toJson comparisons),
    ("operators", Lean.toJson Operator.allValues.length)]).compress)
  IO.println "PASS exact current signature dependencies: every operator, Semantic/Exact, missing/extra references, changed/split representatives, arbitrary old keys, sparse correction across unaffected joins and canonical cold repair"

namespace SignatureBefore
open QuotientBuilder CongruenceMemo

/-- Frozen predecessor, test-only. It constructs every replacement before
checking whether the old key was actually unchanged. -/
def prepare (previous : Option Key) (value : Value) : Prepared value :=
  match previous with
  | some key =>
      if same : key.value = value then ⟨key, same, true⟩
      else ⟨Key.make value, rfl, false⟩
  | none => ⟨Key.make value, rfl, false⟩

def rows (previous : List Key) (index : Representatives) :
    (values : List Value) → Rows index values
  | [] => ⟨[], rfl, 0, 0⟩
  | .atom _ :: values =>
      let rest := rows previous index values
      ⟨rest.rows, rest.exact, rest.reused, rest.computed⟩
  | .apply operator arguments :: values =>
      let value := Value.apply operator arguments
      let prepared := prepare previous.head? (signature index value)
      let rest := rows previous.tail index values
      ⟨(prepared.key, value) :: rest.rows,
        by simp only [CongruenceMemo.rows, List.filterMap_cons]; rw [prepared.canonical, rest.exact]; rfl,
        rest.reused + if prepared.reused then 1 else 0,
        rest.computed + if prepared.reused then 0 else 1⟩

end SignatureBefore

def testSignatureDependencyPerformance : IO Unit := do
  let payload := Value.atom (.mk (Array.replicate (1024 * 1024) (255 : UInt8)))
  let mut samples : List Lean.Json := []
  for run in List.range 4 do
    let values := (List.range 48).map fun index =>
      Value.applyList .receipt [Ref.semantic (.text s!"signature-{run}-{index}"), Ref.exact payload]
    let index : QuotientBuilder.Representatives := {}
    let cold := QuotientBuilder.CongruenceMemo.prepareRows [] index values
    let previous := cold.rows.map Prod.fst
    let old := do
      let start ← IO.monoNanosNow
      let result := SignatureBefore.rows previous index values
      check (result.reused == values.length && result.computed == 0)
        "signature predecessor fixture failed to retain every unchanged key"
      pure (result.rows, (← IO.monoNanosNow) - start)
    let current := do
      let start ← IO.monoNanosNow
      let result := QuotientBuilder.CongruenceMemo.prepareRows previous index values
      check (result.reused == values.length && result.computed == 0)
        "current signature dependencies recomputed an unchanged key"
      pure (result.rows, (← IO.monoNanosNow) - start)
    let (before, after) ← if run % 2 == 0 then do
        let before ← old
        let after ← current
        pure (before, after)
      else do
        let after ← current
        let before ← old
        pure (before, after)
    check (decide (before.1 = after.1) && before.1.map (fun row => row.1.value) ==
      values.map (QuotientBuilder.signature index))
      "signature dependency timing changed a complete ordered row or its cached hash"
    samples := samples ++ [Lean.Json.mkObj [("run", Lean.toJson run),
      ("before_ns", Lean.toJson before.2), ("current_ns", Lean.toJson after.2)]]
  IO.println ((Lean.Json.mkObj [("kind", .str "signature_dependency_phase"),
    ("applications", Lean.toJson (48 : Nat)), ("shared_exact_bytes", Lean.toJson (1024 * 1024 : Nat)),
    ("samples", Lean.toJson samples)]).compress)

def testGeneralCongruenceMemo : IO Unit := do
  let a := Value.text "source alpha"
  let b := Value.text "source beta"
  let c := Value.text "source corrected"
  let unary := fun value => Value.applyList .inquiry [Ref.semantic value]
  let outer := fun value => Value.applyList .receipt [Ref.semantic value]
  let pinned := fun value => Value.applyList .inquiry [Ref.exact value]
  let fa := unary a
  let fb := unary b
  let ga := outer fa
  let gb := outer fb
  let ea := pinned a
  let eb := pinned b
  let values := [a, b, c, fa, fb, ga, gb, ea, eb]
  let ab : UnionEdge := ⟨a, b, .run (.text "demand"), by intro _; rfl⟩
  let bc : UnionEdge := ⟨b, c, ab.scope, by intro _; rfl⟩
  let initial := QuotientBuilder.mergeExplicit (QuotientBuilder.initial values) [ab]
  let first := QuotientBuilder.CongruenceMemo.pass [] values initial
  let second := QuotientBuilder.CongruenceMemo.pass first.keys values first.partition
  let third := QuotientBuilder.CongruenceMemo.pass second.keys values second.partition
  let warm := QuotientBuilder.CongruenceMemo.pass third.keys values third.partition
  let replay := QuotientBuilder.CongruenceMemo.pass warm.keys values warm.partition (some warm.plan)
  check (replay.partition == warm.partition && replay.plan.script.computed == 0 &&
      replay.plan.script.reused == warm.keys.length)
    "unchanged complete dependencies rediscovered congruence joins"
  let extended := QuotientBuilder.CongruenceMemo.pass warm.keys
    (values ++ [unary c]) warm.partition (some warm.plan)
  check (extended.plan.script.reused == warm.keys.length && extended.plan.script.computed == 1 &&
      extended.partition == QuotientBuilder.referenceCongruencePass (values ++ [unary c]) warm.partition)
    "an appended dependency rebuilt the unchanged prefix or missed a new matching application"
  let invalid := QuotientBuilder.CongruenceMemo.Script.check? {}
    warm.plan.rows (warm.plan.script.instructions ++ [some a])
  check invalid.isNone "a malformed persisted join script obtained a producer certificate"
  check (first.computed == 6 && warm.computed == 0 && warm.reused == 6)
    "unchanged application signatures were recomputed or retained Atom keys"
  check (QuotientBuilder.same warm.partition fa fb &&
      QuotientBuilder.same warm.partition ga gb &&
      !QuotientBuilder.same warm.partition ea eb)
    "general congruence missed a nested union or substituted Exact authority"
  -- The old keys survive each edit deliberately. Their ordinals nominate a
  -- calculation; only the complete current signature authorizes its reuse.
  for (changed, edges) in [
      (values, [ab]), (values, [ab, bc]), (values, [bc]), (values, []),
      ([a, b, c, unary c, fb, outer (unary c), gb, ea, eb], [bc]),
      ([a, b, c, fb, gb, eb], [ab]),
      (values.reverse, [ab]), (values ++ [unary c, outer (unary c)], [ab, bc]),
      (values ++ [fa, fa], [ab, ab])] do
    let partition := QuotientBuilder.mergeExplicit (QuotientBuilder.initial changed) edges
    let pass := QuotientBuilder.CongruenceMemo.pass warm.keys changed partition (some warm.plan)
    check (pass.partition == QuotientBuilder.referenceCongruencePass changed partition)
      "a correction, deletion, reorder or new match retained stale congruence"
    let actual := QuotientBuilder.memoSaturateCongruence changed warm.keys changed.length partition
    let repaired := QuotientBuilder.plannedSaturateCongruence changed warm.keys
      (some warm.plan) changed.length partition
    let reference := QuotientBuilder.referenceSaturateCongruence changed changed.length partition
    check (actual == reference && repaired.partition == reference)
      "memoized general saturation changed the exact ordered full-scan partition"
    let actual := QuotientBuilder.build? changed [] edges
    let reference := QuotientBuilder.referenceBuild? changed [] edges
    check (actual.isSome == reference.isSome)
      "production general quotient changed the reference acceptance decision"
    if let (some actual, some reference) := (actual, reference) then
      check (changed.all fun value => actual.canonical value == reference.canonical value)
        "production general quotient changed a representative after mutation"
  let split := QuotientBuilder.CongruenceMemo.pass warm.keys values
    (QuotientBuilder.initial values)
  check (split.computed > 0 && !QuotientBuilder.same split.partition fa fb)
    "removing an equality retained its derived application equality"
  IO.println "PASS general congruence: certified join-prefix repair, new keys, nested Semantic, Exact, additions/corrections/deletions/reorders and exact ordered full-scan equality"

def testGeneratedCongruence : IO Unit := do
  let a := Value.text "current alpha"
  let b := Value.text "current beta"
  let c := Value.text "replacement gamma"
  let apply := fun value => Value.applyList .inquiry [Ref.semantic value]
  let outer := fun value => Value.applyList .receipt [Ref.semantic value]
  let exact := fun value => Value.applyList .inquiry [Ref.exact value]
  let makeEdge := fun left right => do
    if safe : Value.sameExactFootprint left right then
      pure (⟨left, right, .run (.text "current provenance"),
        Value.sameExactFootprint_sound safe⟩ : UnionEdge)
    else throw (IO.userError "invalid generated-equality fixture")
  let ab ← makeEdge a b
  let bc ← makeEdge b c
  let mixed ← makeEdge a (apply b)
  let recursive ← makeEdge a (apply a)
  let structured ← makeEdge (apply a) (apply b)
  let replacedStructured ← makeEdge (apply a) (apply c)
  let roots := [a, b, c, apply a, apply b, apply c, outer (apply a),
    outer (apply b), outer (apply c), apply (apply b), exact a, exact b]
  let topology ← if valid : [a] ≠ [] ∧ apply a ∉ [a] then
    pure (AllEdge.make (apply a) [a] valid.1 valid.2)
    else throw (IO.userError "invalid generated structured topology")
  let graph : WorkGraph := {all := [topology]}
  let payload := Value.text (String.ofList (List.replicate (64 * 1024) 'x'))
  let owner := OutcomeEdge.make a payload [] (by simp) (by simp)
  let fullRoots := roots ++ [owner.relation, outer (apply (apply c))]
  let fragments := [a, b, c, Value.text "new fragment outside both catalogues"]
  -- Both Atoms have an empty Exact footprint: the old safety certificate
  -- alone accepts this unsupported class. The generated producer must not.
  let some arbitrary := QuotientBuilder.certify [[a, b]] |
    throw (IO.userError "authority-only witness unexpectedly failed")
  check (arbitrary.toEquality.same a b)
    "unsupported witness did not exercise the distinction between safety and derivation"
  let mut retained : Plugin.SaturationMemo.Saved := []
  let mut plan : Option QuotientBuilder.CongruenceMemo.Entry := none
  let history := [[ab], [ab, bc], [bc], [], [structured], [ab, structured],
    [replacedStructured], [], [mixed], [recursive], [], [ab, ab], [bc, ab]]
  for edges in history do
    let planned := QuotientBuilder.plannedBuild? roots edges [] plan
    let some checked := QuotientBuilder.CongruenceSound.attach roots edges [] planned.quotient planned.exact |
      throw (IO.userError "current generated build failed")
    let provider := Plugin.SaturationMemo.viewProvider retained
    let atomIndex := QuotientBuilder.AtomQuotient.prepare edges |>.map (·.beginRun)
    check (atomIndex.isSome == !(edges == [mixed] || edges == [recursive]))
      "constructor-preserving Union index rejected structured-only edges or accepted mixed constructors"
    let some accelerated := (provider graph roots edges [] atomIndex).val |
      throw (IO.userError "current persisted generated view failed")
    let some ordinary := RunView.make? graph roots edges [] |
      throw (IO.userError "current full reference view failed")
    let some full := QuotientBuilder.referenceBuild? fullRoots edges [] |
      throw (IO.userError "unpruned full-source reference failed")
    let producedExtended := provider graph fullRoots edges [] atomIndex
    let some extended := producedExtended.val |
      throw (IO.userError "extended persisted generated view failed")
    for left in roots do
      for right in roots do
        check (checked.quotient.toEquality.same left right == ordinary.quotient.toEquality.same left right &&
          accelerated.quotient.toEquality.same left right == ordinary.quotient.toEquality.same left right)
          "typed current-edge provenance changed an equality or reused a retired derivation"
        check (accelerated.quotient.toEquality.same left right == full.toEquality.same left right &&
          extended.quotient.toEquality.same left right == full.toEquality.same left right)
          "pruning original Outcome bodies changed required Work equality"
    for left in fragments do
      for right in fragments do
        check (accelerated.quotient.toEquality.same left right == full.toEquality.same left right)
          "an unmentioned text fragment acquired a false alias after source pruning"
    if let some index := atomIndex then
      let some fast := (provider {} roots edges [] (some index)).val |
        throw (IO.userError "current Atom extension view failed")
      check ([a, b, c].all fun left => roots.all fun right =>
        fast.quotient.toEquality.same left right == ordinary.quotient.toEquality.same left right)
        "typed current-edge provenance changed the Atom extension lane"
    check (!accelerated.quotient.toEquality.same (exact a) (exact b))
      "generated semantic congruence substituted an Exact reference"
    if edges.isEmpty then
      check (!accelerated.quotient.toEquality.same a b &&
        !accelerated.quotient.toEquality.same (apply a) (apply b))
        "all-edge retraction retained an authority-safe but unsupported equality"
    if edges == [recursive] then
      check (accelerated.quotient.toEquality.same a (apply a) &&
        accelerated.quotient.toEquality.same a (outer (apply a)) == false)
        "recursive explicit equality was dropped or crossed a different operator"
    if edges == [ab, bc] then
      check (accelerated.quotient.toEquality.same (apply a) (apply c))
        "current transitive Semantic congruence was omitted"
    let values := Plugin.SaturationMemo.kernelValues roots edges
    let partition := QuotientBuilder.kernelPartition roots edges
    check (QuotientBuilder.referenceCongruencePass values partition == partition)
      "current producer exhausted its fuel before reaching congruence closure"
    let fullValues := Plugin.SaturationMemo.kernelValues fullRoots edges
    let basis := Plugin.SaturationMemo.Basis.make fullValues
    retained := producedExtended.plan.map (Plugin.SaturationMemo.capturePlan basis) |>.getD []
    plan := planned.plan
  -- Structured comparisons require their Work terms to be included. Merely
  -- retaining Atom endpoints is not a complete producer for unasked Applys.
  let some unasked := QuotientBuilder.build? [a, b] [ab] [] |
    throw (IO.userError "unasked structured fixture failed")
  let some asked := QuotientBuilder.build? [apply a, apply b] [ab] [] |
    throw (IO.userError "asked structured fixture failed")
  check (!unasked.toEquality.same (apply a) (apply b) &&
    asked.toEquality.same (apply a) (apply b))
    "required structured Work membership ceased to distinguish a complete query domain"
  let workRoots := Plugin.quotientWorkRoots [] [owner] []
  let workValues := QuotientBuilder.kernelValues workRoots []
  check (workValues.contains owner.work && !workValues.contains payload &&
    !workValues.contains owner.relation && owner.outcome == payload)
    "production Work roots retained unrelated result bytes or altered the original owner"
  let payloadEdge ← makeEdge payload b
  check ((QuotientBuilder.kernelValues workRoots [payloadEdge]).contains payload &&
    (QuotientBuilder.kernelValues (Plugin.quotientWorkRoots [topology] [owner] []) []).contains topology.relation &&
    (QuotientBuilder.kernelValues (Plugin.quotientWorkRoots [] [owner] [owner.relation]) []).contains payload)
    "Work pruning omitted an explicit endpoint, topology or staged dependency"
  let nest := fun depth value => (List.range depth).foldl (fun current _ => apply current) value
  let deep := [nest 8 a, nest 8 b]
  let values := QuotientBuilder.kernelValues deep [ab]
  let explicit := QuotientBuilder.mergeExplicit (QuotientBuilder.initial values) [ab]
  let insufficient := QuotientBuilder.saturateCongruence values 1 explicit
  check (QuotientBuilder.congruencePass values insufficient != insufficient)
    "nested fixture does not expose premature iteration cutoff"
  let complete := QuotientBuilder.kernelPartition deep [ab]
  let minimal := QuotientBuilder.saturateCongruence values explicit.length explicit
  check (QuotientBuilder.same complete (nest 8 a) (nest 8 b) &&
    QuotientBuilder.referenceCongruencePass values complete == complete && minimal == complete)
    "remaining-class fuel failed to close nested Semantic congruence"
  IO.println "PASS typed generated equality and complete demanded-domain saturation, pruned/full source equality, unseen fragments, required structured Work, original 64-KiB Outcome retention outside equality, explicit/staged dependencies, unsupported authority-only partition, insufficient-fuel counterexample, depth-eight completion, retained hints/plans, mixed/recursive edges, duplicate/reorder, deletion/correction and Exact"

def testGeneralCongruencePerformance : IO Unit := do
  let payload := Value.text (String.ofList (List.replicate (256 * 1024) 'x'))
  let mut samples : List Lean.Json := []
  for run in List.range 5 do
    -- A new corpus for each sample prevents the compiler hoisting one pure
    -- full scan out of the measurement loop. Each arm gets the same corpus.
    let values := (List.range 12).map fun index =>
      Value.applyList .receipt [Ref.semantic (.text s!"job-{run}-{index}"), Ref.exact payload]
    let partition := QuotientBuilder.initial values
    let warm := QuotientBuilder.CongruenceMemo.pass [] values partition
    let full := do
      let start ← IO.monoNanosNow
      let result := QuotientBuilder.congruencePass values partition
      check (result == partition) "performance reference unexpectedly changed its partition"
      pure (result, (← IO.monoNanosNow) - start)
    let delta := do
      let start ← IO.monoNanosNow
      let result := QuotientBuilder.CongruenceMemo.pass warm.keys values partition
      check (result.partition == partition && result.reused == values.length && result.computed == 0)
        "performance memo changed output or rehashed an unchanged signature"
      pure (result.partition, (← IO.monoNanosNow) - start)
    let measured ← if run % 2 == 0 then do
        let f ← full
        let d ← delta
        pure (f, d)
      else do
        let d ← delta
        let f ← full
        pure (f, d)
    let ((fullResult, fullNs), (deltaResult, deltaNs)) := measured
    check (fullResult == deltaResult) "timing arms returned different general partitions"
    samples := samples ++ [Lean.Json.mkObj [("run", Lean.toJson run),
      ("full_ns", Lean.toJson fullNs), ("memo_ns", Lean.toJson deltaNs)]]
  IO.println ((Lean.Json.mkObj [("kind", .str "general_congruence_signature_memo"),
    ("applications", Lean.toJson (12 : Nat)), ("exact_payload_bytes", Lean.toJson (256 * 1024 : Nat)),
    ("samples", Lean.toJson samples)]).compress)

def testFrequencyDelta : IO Unit := do
  let normalizer := LogicalText.logicalNormalizer
  let owner := OutcomeEdge.make (.text "alpha common") (.text "answer old") [] (by simp) (by simp)
  let added := OutcomeEdge.make (.text "beta common") (.text "answer new") [] (by simp) (by simp)
  let corrected := OutcomeEdge.make owner.work (.text "replacement result") [] (by simp) (by simp)
  let nonText := OutcomeEdge.make (.apply .all .nil) (.text "opaque outcome") [] (by simp) (by simp)
  let first := TestOracle.CorpusCache.prepare normalizer {} {outcomes := [owner]}
  let same := TestOracle.CorpusCache.prepare normalizer first.index {outcomes := [owner]}
  check (same.frequencyTouches == 0 && same.freshCompiles == 0)
    "an unchanged corpus visited term rows or recompiled owners"
  let appended := TestOracle.CorpusCache.prepare normalizer first.index {outcomes := [owner, added]}
  let prepended := TestOracle.CorpusCache.prepare normalizer first.index {outcomes := [added, owner]}
  let addedTerms := ((Matcher.Corpus.compileCandidate normalizer added).toList.map
    Matcher.Corpus.candidateTerms).flatten
  check (appended.frequencyTouches == addedTerms.length &&
    prepended.frequencyTouches == addedTerms.length)
    "an append or prepend rescanned terms of a retained owner"
  let changed := TestOracle.CorpusCache.prepare normalizer appended.index
    {outcomes := [corrected, added]}
  let oldTerms := first.index.rows.flatten
  let changedTerms := ((Matcher.Corpus.compileCandidate normalizer corrected).toList.map
    Matcher.Corpus.candidateTerms).flatten
  check (changed.frequencyTouches == oldTerms.length + changedTerms.length)
    "a correction rescanned the unchanged suffix's terms"
  let deleted := TestOracle.CorpusCache.prepare normalizer appended.index {outcomes := [added]}
  check (deleted.frequencyTouches == oldTerms.length)
    "deleting the first owner rescanned the unchanged suffix"
  let erased := TestOracle.CorpusCache.prepare normalizer appended.index {}
  check (erased.index.frequencies.counts.isEmpty)
    "zero-frequency terms leaked into the retained map"

  let mut previous := first.index
  let mut memo : SearchMemo.Cache := none
  for owners in [[owner, added], [added, owner], [corrected, added], [added],
      [added, added], [nonText, added], [nonText], [], [owner, nonText, added],
      [corrected, nonText, owner, added], [owner, added], [owner, added]] do
    let graph : WorkGraph := {outcomes := owners}
    let prepared := TestOracle.CorpusCache.prepare normalizer previous graph
    let reference := Matcher.Corpus.build normalizer graph
    let terms := (prepared.index.rows.flatten ++ ["absent"]).eraseDups
    check (prepared.corpus.candidates.map (·.edge.relation) ==
      reference.candidates.map (·.edge.relation) && terms.all fun term =>
        prepared.corpus.frequency term == reference.frequency term &&
        prepared.corpus.unitWeight term == reference.unitWeight term)
      "frequency delta changed candidate order, a document count or its ranking weight"
    check (prepared.index.frequencies.counts.toList.all (fun (_, count) => count > 0))
      "a completed frequency update retained a negative or zero count"
    let input : SearchMemo.Input := {
      sources := ["same-source"], authorities := [], origins := [], unionOrigins := []
      values := owners.map (·.relation), unions := [], graph, current := "alpha common"
      evidence := none, semantic := {}, localUnion := true, native := false }
    let render := fun (result : Option SearchMemo.PreparedDiscovery) => result.bind fun found =>
      renderAutomatic [] 24000 input.current [] false true found.discovery
        ⟨found.extraction, found.exact⟩
    let (found, updated) := SearchMemo.get memo input prepared
    let actual := render found.result
    let fresh := render (SearchMemo.reference input)
    check ((Lean.toJson actual).compress == (Lean.toJson fresh).compress)
      "an updated frequency index changed the full search/selection/handoff"
    previous := prepared.index
    memo := updated
  IO.println "PASS delta frequencies and weights: no-op/append/prepend/correction/deletion/duplicates/reorder/opaque owners, zero-key reclamation and full handoff oracle"

def testLexicalFrequencyDelta : IO Unit := do
  let versions : List (List String) := [
    ["alpha alpha /lib/a.cc", "beta /lib/b.cc", "STRASSE 日本語", ""],
    ["alpha alpha /lib/a.cc", "alpha beta /lib/b.cc", "STRASSE 日本語", ""],
    ["alpha beta /lib/b.cc", "STRASSE 日本語", ""],
    ["alpha beta /lib/b.cc", "STRASSE 日本語", "", "unseen delta /lib/new.cc"],
    ["", "STRASSE 日本語", "unseen delta /lib/new.cc", "alpha beta /lib/b.cc"],
    ["beta", "beta", "alpha"], [], ["restored beta /lib/new.cc"]]
  let previous ← IO.mkRef (none : Option SearchProvider.RetainedCorpus)
  let options : SearchProvider.Options := {
    cache := ".lake/lexical-frequency-test", models := ".lake/unused-models", mode := "lexical" }
  for documents in versions do
    let cold := SearchRank.Corpus.build documents
    let repaired := match ← previous.get with
      | some retained => retained.corpus.revise documents
      | none => cold
    check (repaired.documents == cold.documents) "a corrected lexical corpus retained old terms"
    for term in (documents.flatMap SearchRank.terms ++ ["absent", "retired"]).eraseDups do
      check ((repaired.frequencies.counts.getD term 0).toNat ==
        ((documents.map SearchRank.terms).filter (·.contains term)).length)
        "delta document frequency differs from complete membership counting"
    for query in ["alpha beta", "/lib/a.cc /lib/new.cc", "unseen", "STRASSE 日本語", "absent", ""] do
      let full := SearchRank.referenceLexical query documents
      let anchor := SearchRank.referenceLexical query documents true
      check (repaired.rank query == full && repaired.rank query true == anchor)
        "signed frequency repair changed a lexical or anchor rank"
      let request := Lean.Json.mkObj [
        ("query", Lean.Json.mkObj [("text", .str query)]),
        ("candidates", .arr (documents.toArray.map fun text =>
          Lean.Json.mkObj [("id", .str text), ("text", .str text)]))]
      let some response ← SearchProvider.handle options none previous request |
        throw (IO.userError "lexical provider returned no result")
      let selected ← IO.ofExcept (response.getObjValAs? (List Nat) "related")
      check (selected == SearchRank.select documents.length options.topK
        (anchor.take options.anchorK) full)
        "the production provider changed nominations during a correction, deletion or new match"
    let some retained ← previous.get | throw (IO.userError "small corpus was not retained")
    check (retained.texts == documents) "the provider retained another candidate sequence"
  IO.println "PASS production lexical/anchor frequency delta, correction/deletion, new/negative matches, duplicates, order, Unicode and full-ranking equivalence"

def testIndexedNumericalWindows : IO Unit := do
  let root := ((← IO.currentDir) / testRoot / "indexed-numerical").normalize
  if ← root.pathExists then IO.FS.removeDirAll root
  Persistence.privateDirectory root
  let query := "needle /path/42"
  let texts := ["", (String.ofList (List.replicate 40000 'a')) ++ " needle",
    "opposite", "needle /path/42", "unrelated"]
  let parts := ((texts ++ [query]).flatMap SearchRank.windows).eraseDups
  let base : SearchProvider.Options := {
    cache := root, models := root / "unused-models", model := "synthetic-cache-test-only" }
  -- Synthetic finite two-dimensional vectors isolate numerical batching from
  -- model variation. Every query/window is prefilled: no inference is needed.
  for part in parts do
    let vector : Lean.Json ← IO.ofExcept (Lean.Json.parse
      (if part.contains "needle" then "[1,0]" else if part.contains "opposite" then "[-1,0]" else "[0,1]"))
    SearchProvider.saveVector base part vector
  check ((SearchRank.windows texts[1]!).length > 32)
    "numerical fixture did not cross a window batch boundary"
  for mode in ["semantic", "hybrid", "lexical"] do
    let options := { base with
      mode := mode
      trace := some (root / (mode ++ "-trace.jsonl")) }
    let child ← if mode == "lexical" then pure none else some <$> SearchProvider.encoder options
    try
      let candidates := texts.zipIdx.map fun (text, id) => Lean.Json.mkObj [
        ("id", Lean.toJson id), ("text", .str text)]
      let documents := texts.zipIdx.map fun (text, id) => Lean.Json.mkObj [
        ("id", Lean.toJson id), ("windows", Lean.toJson ((SearchRank.windows text).map Persistence.Store.windowKey))]
      let referenceRequest := Lean.Json.mkObj [
        ("query", Lean.Json.mkObj [("text", .str query)]), ("candidates", Lean.toJson candidates)]
      let indexedRequest := Lean.Json.mkObj [
        ("query", Lean.Json.mkObj [("text", .str query)]), ("documents", Lean.toJson documents),
        ("lexical", Lean.toJson (SearchRank.referenceLexical query texts)),
        ("anchors", Lean.toJson (SearchRank.referenceLexical query texts true))]
      let previous ← IO.mkRef (none : Option SearchProvider.RetainedCorpus)
      let some expected ← SearchProvider.handle options child previous referenceRequest |
        throw (IO.userError "reference provider returned no response")
      let actual ← SearchProvider.handleIndexed options child query indexedRequest
      let ranked ← IO.ofExcept (actual.getObjValAs? (List Nat) "ranked")
      check ((SemanticMatcher.IndexedOrder.check? ((List.range texts.length).map fun index =>
        ({owner := index, work := index, windows := ["window"]} : Persistence.Store.SearchDocument)) ranked).isSome)
        "numerical peripheral evidence order omitted, duplicated or invented a document"
      check (actual.getObjValD "ranked" == expected.getObjValD "ranked")
        "indexed surrounding evidence order differs from the complete numerical reference"
      check (actual.getObjValD "related" == expected.getObjValD "related")
        "streamed numerical windows changed complete semantic/hybrid/lexical nominations"
      let lines := (← IO.FS.readFile (root / (mode ++ "-trace.jsonl"))).splitOn "\n" |>.filter (!·.isEmpty)
      check (lines.length == 3 && lines[0]? == lines[1]?)
        "streamed numerical windows changed complete ranks, stable ties, or selection"
      let choices ← IO.ofExcept (actual.getObjValAs? (List SemanticMatcher.WindowChoice) "evidence")
      for choice in choices do
        let some text := texts[choice.document]? | throw (IO.userError "foreign evidence document")
        check (choice.indices.length ≤ 16 && choice.indices.eraseDups == choice.indices &&
            choice.indices.all (fun index => index < (SearchRank.windows text).length))
          "ranked evidence hints were unbounded, repeated or foreign to the original document"
      if mode != "lexical" then
        let source := (SearchRank.windows texts[1]!).getLast!
        let path := options.cache / "vectors" / (SearchProvider.cacheKey options.model source ++ ".json")
        removeIfExists path
        let repairs ← IO.mkRef ([] : List (Nat × List (Nat × String)))
        let repair : SearchProvider.RepairWindows := fun document windows => do
          check (windows.length ≤ 32) "repair batch exceeded its window budget"
          repairs.modify (· ++ [(document, windows)])
          let some text := texts[document]? | throw (IO.userError "foreign repair document")
          windows.mapM fun (index, digest) => do
            let some part := (SearchRank.windows text)[index]? |
              throw (IO.userError "foreign repair window")
            check (Persistence.Store.windowKey part == digest) "repair selected another source"
            let vector ← IO.ofExcept (Lean.Json.parse
              (if part.contains "needle" then "[1,0]" else if part.contains "opposite" then "[-1,0]" else "[0,1]"))
            SearchProvider.saveVector options part vector
            pure part
        let recovered ← SearchProvider.handleIndexed options child query indexedRequest repair
        check (recovered == actual && !(← repairs.get).isEmpty)
          "cache loss was not repaired from exact bounded windows without changing nominations"
        removeIfExists path
        let rejected ← try
            let _ ← SearchProvider.handleIndexed options child query indexedRequest
              (fun _ windows => pure (windows.map fun _ => "invented substitute"))
            pure false
          catch _ => pure true
        check rejected "a substituted repair body was accepted under another source window"
        let _ ← SearchProvider.handleIndexed options child query indexedRequest repair
        let broken := indexedRequest.setObjVal! "documents" (Lean.toJson [Lean.Json.mkObj [
          ("id", Lean.toJson (0 : Nat)), ("windows", Lean.toJson [String.ofList (List.replicate 64 '0')])]])
        let rejected ← try
            let _ ← SearchProvider.handleIndexed options child query broken
            pure false
          catch _ => pure true
        check rejected "a missing indexed vector was omitted instead of failing explicitly"
    finally
      if let some child := child then
        child.kill
        let _ ← child.wait
        pure ()
  let oversized := root / "oversized-vector.json"
  IO.FS.writeFile oversized (String.ofList (List.replicate (1048576 + 1) 'x'))
  let rejected ← try
      let _ ← SearchProvider.loadVector oversized
      pure false
    catch _ => pure true
  check rejected "an oversized optional numerical cache record was allocated/decoded without a bound"
  let bad := root / "nonfinite-vector.json"
  IO.FS.writeFile bad "{\"model\":\"synthetic-cache-test-only\",\"text\":\"needle\",\"vector\":[1e999]}"
  let rejected ← try
      let _ ← SearchProvider.loadVector bad
      pure false
    catch _ => pure true
  check rejected "a nonfinite cached vector reached numerical scoring"
  let rejected ← try
      let vector ← IO.ofExcept (Lean.Json.parse "[1e999]")
      SearchProvider.saveVector base "needle" vector
      pure false
    catch _ => pure true
  check rejected "the indexer acknowledged a nonfinite vector that search would reject"
  let dimension := root / "full-dimension-vector.json"
  let vector ← IO.ofExcept (Lean.Json.parse
    ("[" ++ String.intercalate "," (List.replicate 384 "0.12345678901234567") ++ "]"))
  let cached : SearchProvider.CachedVector := {model := base.model, text := "needle", vector}
  let encoded := (Lean.toJson cached).compress
  check (encoded.utf8ByteSize > 4096) "384-dimensional vector did not exceed one page"
  IO.FS.writeFile dimension encoded
  let observed ← SearchProvider.loadVector dimension
  check (observed.vector == vector && observed.text == cached.text)
    "a valid multi-page numerical cache record was rejected or truncated"
  IO.println "PASS bounded numerical window batches preserve complete semantic/hybrid/lexical ranks and reject missing indexed vectors"

/-- Read-only phase timing for a recorded source. This does not run an LLM
or stand in for the actual hook/token acceptance experiment. -/
def indexedQueryTiming (path cache input : System.FilePath) : IO Unit := do
  let event ← IO.ofExcept (Lean.Json.parse (← IO.FS.readFile input))
  let query ← IO.ofExcept (event.getObjValAs? String "prompt")
  let layout := MiniLM.layout (← Paths.installRoot) cache
  let command := [(← IO.appPath).toString, "search-provider", "--cache", cache.toString,
    "--model-cache", layout.models.toString, "--mode", "hybrid", "--top-k", "8", "--threshold", "0.38"]
  let selection : Config.Selection := {
    label := "timing"
    read := [⟨"work", path⟩]
    write := none
    semanticMatcher := some command
    handoffChars := 24000
  }
  let source ← DB.PageMap.pin path
  let started ← IO.monoNanosNow
  let some topology ← Persistence.Store.atomTopology? source | throw (IO.userError "non-Atom timing source")
  let some nominated ← indexedSemanticOwners source topology command query |
    throw (IO.userError "incomplete semantic timing source")
  let nominateNs := (← IO.monoNanosNow) - started
  let mut rows : List Lean.Json := [Lean.Json.mkObj [
    ("phase", .str "catalogue-and-numerical-nominations"), ("elapsed_ns", Lean.toJson nominateNs),
    ("nominated", Lean.toJson nominated.length), ("db_read_bytes", Lean.toJson (← source.readBytes.get)),
    ("db_page_reads", Lean.toJson (← source.reads.get))]]
  let mut expected : Option String := none
  for full in [false, true] do
    runtimeCache.set {}
    let source ← DB.PageMap.pin path
    let started ← IO.monoNanosNow
    let result ← if full then computeGeneralAutomaticHandoff selection [some source] query [] false
      else computeAutomaticHandoff selection [some source] query [] false
    let ns := (← IO.monoNanosNow) - started
    let encoded := (Lean.toJson result).compress
    if let some previous := expected then check (previous == encoded) "timing changed the complete handoff"
    expected := some encoded
    rows := rows ++ [Lean.Json.mkObj [
      ("phase", .str (if full then "full-discovery" else "indexed-discovery")),
      ("elapsed_ns", Lean.toJson ns), ("db_read_bytes", Lean.toJson (← source.readBytes.get)),
      ("db_page_reads", Lean.toJson (← source.reads.get))]]
  IO.println ((Lean.Json.mkObj [("generative_calls", Lean.toJson (0 : Nat)),
    ("exact_handoff_equal", Lean.toJson true), ("samples", Lean.toJson rows)]).compress)

def testRankingDelta : IO Unit := do
  let normalizer := LogicalText.logicalNormalizer
  let owner := OutcomeEdge.make (.text "alpha common target") (.text "saved response") [] (by simp) (by simp)
  let another := OutcomeEdge.make (.text "unrelated delta") (.text "other response") [] (by simp) (by simp)
  let graph : WorkGraph := {outcomes := [owner, another]}
  let corpus := Matcher.Corpus.build normalizer graph
  let requests := Matcher.GeometryMemo.inputs normalizer corpus "alpha common other" {} false
  check (!requests.isEmpty) "ranking fixture produced no demanded comparisons"
  let first := Matcher.GeometryMemo.prepare {} requests
  let repeated := Matcher.GeometryMemo.prepare first.cache requests
  check (first.computed == requests.length && repeated.computed == 0 &&
      repeated.reused == requests.length)
    "unchanged ranking inputs were recomputed"
  let changed := requests.map fun input => {input with novelty := input.novelty + 1}
  let updated := Matcher.GeometryMemo.prepare repeated.cache changed
  check (updated.computed == changed.length && updated.reused == 0)
    "a changed document count reused stale rankings"
  for change in [
      fun (input : Matcher.GeometryMemo.Input) => {input with pastWeights := input.pastWeights.map (· + 1)},
      fun input => {input with currentWeights := input.currentWeights.map (· + 1)},
      fun input => {input with past := LogicalText.logical "different original positions"},
      fun input => {input with current := LogicalText.logical "different current work"}] do
    let newInputs := requests.map change
    let revised := Matcher.GeometryMemo.prepare repeated.cache newInputs
    check (revised.computed == newInputs.length && revised.reused == 0)
      "changed term weights, text or spans reused old ranking"
  let negative : Matcher.GeometryMemo.Input := {
    past := LogicalText.logical "never previous", current := LogicalText.logical "future absent"
    pastWeights := [1, 1], currentWeights := [1, 1], novelty := 2 }
  let saved := Matcher.GeometryMemo.prepare {} [negative]
  let empty := Matcher.GeometryMemo.prepare saved.cache [negative]
  check ((Matcher.GeometryMemo.get empty.cache negative).result.isEmpty &&
      empty.reused == 1 && empty.computed == 0)
    "completed negative geometry was not reusable"
  let pruned := Matcher.GeometryMemo.prepare repeated.cache []
  check (pruned.cache.isEmpty) "unused ranking demands were retained or refreshed"
  let query := Matcher.compile normalizer "alpha common other"
  let direct := Matcher.findIn normalizer Quotient.literal corpus (.text "alpha common other")
    "alpha common other"
  let cached := Matcher.findInUsing normalizer (Matcher.CompiledDemand.make normalizer)
    (Matcher.GeometryMemo.provider repeated.cache)
    Quotient.literal corpus (.text "alpha common other") "alpha common other"
  check (cached.map (·.projectionWork) == direct.map (·.projectionWork) &&
      cached.map (·.work.priorInDemand) == direct.map (·.work.priorInDemand) &&
      cached.map (·.work.demandInPrior) == direct.map (·.work.demandInPrior) &&
      (Matcher.GeometryMemo.provider repeated.cache query query [1, 1, 1] [1, 1, 1] 3) ==
      (Matcher.pairedCoverages query query [1, 1, 1] [1, 1, 1] 3))
    "memoized ranking changed actual Match coverage or projection"
  IO.println "PASS demanded ranking reuse, weights/count/text/span invalidation, negative results, pruning and production Match oracle"

/-- Compare the previous full frequency fold with the connected incremental
prepare, using the same compiled-owner cache and alternating timing order.
This measures corpus preparation, not model tokens or end-to-end hook time. -/
def testFrequencyPerformance : IO Unit := do
  let normalize := LogicalText.logicalNormalizer
  let shared := String.intercalate " " ((List.range 24).map fun n => s!"shared{n}")
  let makeOwner := fun n => OutcomeEdge.make (.text s!"inspect record{n} {shared}")
    (.text s!"observed result{n}") [] (by simp) (by simp)
  let retained := (List.range 128).map makeOwner
  let mut previous := (TestOracle.CorpusCache.prepare normalize {} {outcomes := retained}).index
  let mut samples : List Lean.Json := []
  for run in List.range 20 do
    let owners := retained ++ [makeOwner (128 + run)]
    let graph : WorkGraph := {outcomes := owners}
    let full := do
      let started ← IO.monoNanosNow
      let batch := TestOracle.CorpusCache.prepareOwners normalize previous owners
      let reference := Matcher.Corpus.fromCandidates batch.candidates graph.subworks graph.all
      let observed := reference.frequency "shared1" + reference.frequency s!"record{128 + run}"
      check (observed == 130) "full frequency baseline did not execute the same update"
      pure ((← IO.monoNanosNow) - started)
    let delta := do
      let started ← IO.monoNanosNow
      let prepared := TestOracle.CorpusCache.prepare normalize previous graph
      let observed := prepared.corpus.frequency "shared1" + prepared.corpus.frequency s!"record{128 + run}"
      check (observed == 130 && prepared.freshCompiles == 1)
        "incremental timing did not execute the same owner update"
      pure (prepared, (← IO.monoNanosNow) - started)
    let measured : TestOracle.CorpusCache.Prepared normalize graph × Nat × Nat ←
      if run % 2 == 0 then do
      let fullNs ← full
      let (prepared, deltaNs) ← delta
      pure (prepared, fullNs, deltaNs)
      else do
      let (prepared, deltaNs) ← delta
      let fullNs ← full
      pure (prepared, fullNs, deltaNs)
    let (prepared, fullNs, deltaNs) := measured
    check (prepared.frequencyTouches ≤ 64)
      "an update revisited terms of the 128 retained owners"
    samples := samples ++ [Lean.Json.mkObj [
      ("run", Lean.toJson run), ("full_ns", Lean.toJson fullNs),
      ("delta_ns", Lean.toJson deltaNs), ("frequency_touches", Lean.toJson prepared.frequencyTouches)]]
    previous := prepared.index
  IO.println ((Lean.Json.mkObj [
    ("kind", .str "compiled_owner_corpus_preparation"),
    ("retained_owners", Lean.toJson (128 : Nat)), ("samples", Lean.toJson samples)]).compress)

/-- Compare the complete pure discovery+saturation+extraction path under
result corrections. Includes demanded ranking preparation in the delta arm.
Both arms use the same already compiled corpus and alternate execution order. -/
def testRankingPerformance : IO Unit := do
  let normalize := LogicalText.logicalNormalizer
  let makeOwner := fun n revision => OutcomeEdge.make
    (.text s!"inspect shared{n} symbol{n} source{n} common evidence")
    (.text s!"shared{n} symbol{n} source{n} saved evidence revision{revision}")
    [] (by simp) (by simp)
  let owners := (List.range 16).map (makeOwner · (0 : Nat))
  let initial : WorkGraph := {outcomes := owners}
  let mut index := (TestOracle.CorpusCache.prepare normalize {} initial).index
  let mut cache : SearchMemo.Cache := none
  let mut samples : List Lean.Json := []
  for run in List.range 20 do
    let owners := owners.dropLast ++ [makeOwner 15 run]
    let graph : WorkGraph := {outcomes := owners}
    let prepared := TestOracle.CorpusCache.prepare normalize index graph
    let input : SearchMemo.Input := {
      sources := ["ranking-performance"], authorities := [], origins := [], unionOrigins := []
      values := owners.map (·.relation), unions := [], graph
      current := "inspect shared0 symbol0 source0 common evidence"
      evidence := none, semantic := {}, localUnion := true, native := false }
    let full := do
      let start ← IO.monoNanosNow
      let result := SearchMemo.evaluate input prepared
      let size := result.map (·.discovery.hits.length) |>.getD 0
      check (size > 0) "performance reference had no actual discovery"
      let elapsed := (← IO.monoNanosNow) - start
      pure (result, elapsed)
    let delta := do
      let start ← IO.monoNanosNow
      let found := SearchMemo.get cache input prepared
      let size := found.1.result.map (·.discovery.hits.length) |>.getD 0
      check (size > 0) "performance delta had no actual discovery"
      let elapsed := (← IO.monoNanosNow) - start
      pure (found, elapsed)
    let measured : (Option SearchMemo.PreparedDiscovery × Nat) ×
        ((SearchMemo.Result input × SearchMemo.Cache) × Nat) ←
      if run % 2 == 0 then do
        let reference ← full
        let actual ← delta
        pure (reference, actual)
      else do
        let actual ← delta
        let reference ← full
        pure (reference, actual)
    let ((reference, fullNs), ((actual, updated), deltaNs)) := measured
    let render := fun (result : Option SearchMemo.PreparedDiscovery) => result.bind fun found =>
      renderAutomatic [] 24000 input.current [] false true found.discovery
        ⟨found.extraction, found.exact⟩
    check ((Lean.toJson (render reference)).compress ==
        (Lean.toJson (render actual.result)).compress)
      "ranking performance changed full rendered handoff after a correction"
    samples := samples ++ [Lean.Json.mkObj [
      ("run", Lean.toJson run), ("full_ns", Lean.toJson fullNs), ("delta_ns", Lean.toJson deltaNs)]]
    index := prepared.index
    cache := updated
  IO.println ((Lean.Json.mkObj [("kind", .str "discovery_saturation_extraction"),
    ("owners", Lean.toJson (16 : Nat)), ("samples", Lean.toJson samples)]).compress)

structure ContextQueryFixture (text : String) where
  demand : Matcher.CompiledDemand LogicalText.logicalNormalizer text false
  candidate : Matcher.Candidate
  work : Matcher.WorkAlignment

def contextQueryFixture (text : String) : IO (ContextQueryFixture text) := do
  let normalize := LogicalText.logicalNormalizer
  let owner := OutcomeEdge.make (.text text) (.text "stored original evidence") [] (by simp) (by simp)
  let some candidate := Matcher.Corpus.compileCandidate normalize owner |
    throw (IO.userError "context query fixture lost its textual owner")
  let corpus := Matcher.Corpus.fromCandidates [candidate] []
  let demand := Matcher.CompiledDemand.make normalize text false
  let some (work, _) := (candidate.preparedWorks Matcher.pairedCoverages Quotient.literal corpus
      (.text text) demand.pattern demand.workPatterns {} false).head? |
    throw (IO.userError "context query fixture did not produce an actual Work alignment")
  pure {demand, candidate, work}

/-- Test-only observation of evaluations; production normalizers stay pure.
The implementation returns exactly the supplied normalizer's pieces. -/
unsafe def observedNormalizerImpl (trace : IO.Ref (List String))
    (normalize : LogicalText.Normalizer) (text : String) : List LogicalText.Piece :=
  match unsafeIO (do
      trace.modify (text :: ·)
      pure (normalize text)) with
  | .ok pieces => pieces
  | .error error => panic! toString error

@[implemented_by observedNormalizerImpl]
def observedNormalizer (_trace : IO.Ref (List String))
    (normalize : LogicalText.Normalizer) (text : String) : List LogicalText.Piece :=
  normalize text

def checkFullPattern (actual expected : Matcher.Pattern) : IO Unit := do
  check (actual.logical == expected.logical && actual.locator == expected.locator &&
      actual.surface.toList == expected.surface.toList &&
      actual.surfaces.toList == expected.surfaces.toList &&
      actual.contextSurface.toList == expected.contextSurface.toList)
    "lazy normalization changed canonical text, positions, ordered anchors, context or locator"

def testLazyNormalization : IO Unit := do
  let huge := String.intercalate "\n" ((List.range 32768).map fun i => s!"unused_evidence_{i}")
  let whole : LogicalText.Normalizer := fun text =>
    [{text, source := {start := 0, stop := text.utf8ByteSize}}]
  let mut comparisons := 0
  for normalizer in [LogicalText.logicalNormalizer, whole] do
    for text in ["", "alpha alpha beta", "αβ 日本語 🥚",
        "./src/old.cc https://example.invalid/v1/file.cc symbol_name",
        "{\"text\":\"alpha\\nbeta\"}"] do
      let trace ← IO.mkRef ([] : List String)
      let source ← IO.mkRef text
      let compiled ← IO.mkRef (Matcher.compile (observedNormalizer trace normalizer) (← source.get))
      check ((← trace.get).isEmpty) "Pattern construction eagerly normalized its source"
      let control ← IO.mkRef (Matcher.makePattern
        (LogicalText.build (observedNormalizer trace normalizer) (← source.get)))
      check ((← trace.get) == [text]) "eager negative control did not observe normalization"
      trace.set []
      let actual ← compiled.get
      let expected ← control.get
      for _ in [:3] do
        checkFullPattern actual expected
      check ((← trace.get) == [text]) "canonical fields normalized the same source more than once"
      comparisons := comparisons + 1
  -- This is the actual complete compiler and matcher, not only Thunk.get.
  -- Construction and a rejected Work match must leave the giant body unused.
  let trace ← IO.mkRef ([] : List String)
  let normalize := observedNormalizer trace LogicalText.logicalNormalizer
  let source ← IO.mkRef huge
  let body ← source.get
  let edge := OutcomeEdge.make (.text "inspect alpha parser") (.text body) [] (by simp) (by simp)
  let some candidate := Matcher.Corpus.compileCandidate normalize edge |
    throw (IO.userError "lazy compilation lost a textual owner")
  let retained ← IO.mkRef candidate
  check ((← trace.get).isEmpty) "complete candidate compiler eagerly normalized Work or Outcome"
  let currentText := "unrelated omega zeta"
  let current := Value.text currentText
  let demand := Matcher.CompiledDemand.make normalize currentText false
  let corpus : Matcher.Corpus := {candidates := [candidate], frequency := fun _ => 0, subworks := []}
  check ((candidate.findMatches normalize Matcher.pairedCoverages Quotient.literal corpus current
      currentText false demand none {}).isEmpty) "disjoint Work unexpectedly matched"
  check (!((← trace.get).contains body)) "rejected Work normalized an unused giant Outcome"
  let some outcome := (← retained.get).outcome |
    throw (IO.userError "lazy compiler lost its original textual Outcome")
  -- Logical units force one evaluation; later fields and repeated reads use it.
  check (outcome.logical.units.length == 32768) "forced giant body has incomplete units"
  check (outcome.locator == hash outcome.logical) "lazy locator diverged from complete logical text"
  check (outcome.logical.original == body) "lazy Outcome replaced its original evidence"
  check (((← trace.get).filter (· == body)).length == 1)
    "unused/forced giant Outcome was normalized repeatedly"
  trace.set []
  let some work := Matcher.Corpus.compileWorkCandidate normalize edge |
    throw (IO.userError "Work phase lost its owner")
  let finished ← IO.mkRef (Matcher.Corpus.finishCandidate normalize work)
  check ((← trace.get).isEmpty) "phase completion eagerly normalized its Outcome"
  let memo := Matcher.Corpus.OutcomeMemo.prepare ({} : Matcher.Corpus.OutcomeMemo.Cache normalize)
    edge.outcome
  let memoRef ← IO.mkRef memo
  check ((← trace.get).isEmpty) "Outcome memo preparation eagerly normalized its body"
  let prepared ← memoRef.get
  let reused := Matcher.Corpus.OutcomeMemo.prepare prepared.cache edge.outcome
  check reused.reused "equal original body did not retain its canonical memo"
  let some cached := reused.compiled.pattern | throw (IO.userError "memo lost the textual Outcome")
  check (cached.logical == outcome.logical) "memo normalization differs from complete candidate"
  let some finishedPattern := (← finished.get).outcome | throw (IO.userError "finish lost its Outcome")
  check (finishedPattern.logical == outcome.logical) "phase completion changed complete normalization"
  check (((← trace.get).filter (· == body)).length == 2)
    "independent finish/memo normalized before demand or memo reuse recomputed its body"
  trace.set []
  for result in [Value.atom (ByteArray.mk #[255]), Value.applyList .all [.semantic (.text body)]] do
    let owner := OutcomeEdge.make (.text "inspect alpha parser") result [] (by simp) (by simp)
    let some compiled := Matcher.Corpus.compileCandidate normalize owner |
      throw (IO.userError "nontextual Outcome lost its Work owner")
    check compiled.outcome.isNone "nontextual Outcome acquired a text Pattern"
  check ((← trace.get).isEmpty) "nontextual/invalid UTF-8 Outcome invoked the normalizer"
  IO.println s!"PASS lazy canonical normalization: {comparisons} complete eager comparisons; construction/rejected Work/phase completion/memo reuse, 32768-unit unused body, exact-once demand and nontextual Outcomes"

/-- Frozen pre-reuse factory for a phase comparison, not another search lane. -/
def contextRowBeforeReuse (text : String) (candidate : Matcher.Candidate) (work : Matcher.WorkAlignment) :
    Matcher.PreparedMatch LogicalText.logicalNormalizer (.text text) text := {
  candidate, work, retrieved := false
  contextQuery := candidate.outcome.map (fun _ => Matcher.contextPattern LogicalText.logicalNormalizer
    (.text text) text work)
  contextExact := rfl }

def contextTermsBeforeStreaming (rows : List (Matcher.PreparedMatch normalize current text))
    (reverse : Bool) : List String :=
  hashDistinct (rows.flatMap fun row =>
    (row.contextQuery.toList ++ if reverse then row.candidate.outcome.toList else []).flatMap
      fun pattern => pattern.logical.units.map (·.text))

def testContextQueryReuse : IO Unit := do
  let mut comparisons := 0
  for text in ["inspect alpha parser", "inspect ./src/旧版.cc https://example.invalid/path",
      "共有 日本語 αβγ", "shell\n{\"command\":\"read alpha_parser\"}"] do
    let fixture ← contextQueryFixture text
    let current := Value.text text
    for child in [false, true] do
      for fragment in [text, "alpha parser", "共有 日本語"] do
        let work := {fixture.work with subwork := child, currentFragment := .text fragment}
        let cached := Matcher.reusedContextPattern fixture.demand current work
        let expected := Matcher.contextPattern LogicalText.logicalNormalizer current text work
        check (cached.val.logical == expected.logical && cached.val.locator == expected.locator &&
            cached.val.surface.toList == expected.surface.toList &&
            cached.val.surfaces.toList == expected.surfaces.toList)
          "query sharing changed source bytes, logical units, spans, surfaces or locator"
        let actual := Matcher.PreparedMatch.make LogicalText.logicalNormalizer current text fixture.demand
          fixture.candidate work false
        let before := contextRowBeforeReuse text fixture.candidate work
        for reverse in [false, true] do
          let rows := List.replicate 32 actual
          check (Matcher.contextTerms rows reverse == contextTermsBeforeStreaming
              (List.replicate 32 before) reverse)
            "streamed frequency terms changed repeated query order or reverse Outcome requirements"
        comparisons := comparisons + 1
  IO.println s!"PASS context query reuse: {comparisons} complete pattern comparisons, byte-equal parent/current, distinct derived child, Unicode/path/URI/native text and streamed forward/reverse domains"

def testContextUnitIndex : IO Unit := do
  for text in ["", "abc", "αβ 日本語 🥚", "{\"text\":\"alpha\\nbeta\"}"] do
    let prepared := LogicalText.ByteSource.make text
    for start in [:text.utf8ByteSize + 2] do
      for stop in [:text.utf8ByteSize + 2] do
        let span : LogicalText.ByteSpan := {start, stop}
        check (prepared.slice? span == LogicalText.byteSlice? text span)
          "prepared bytes changed empty, reversed, out-of-bounds or split UTF-8 slice"
  let normalizeWhole : LogicalText.Normalizer := fun text =>
    [{text, source := {start := 0, stop := text.utf8ByteSize}}]
  let mut comparisons := 0
  for normalize in [LogicalText.logicalNormalizer, normalizeWhole] do
    for source in ["", "alpha alpha alpha", "alpha beta alpha\nbeta αβ 日本語",
        "./src/old.cc https://example.invalid/v1/file.cc symbol_name",
        "{\"text\":\"alpha\\nbeta\\nalpha\"}",
        String.intercalate " " (List.replicate 128 (String.ofList (List.replicate 128 'a')))] do
      let target := Matcher.compile normalize source
      for key in target.surfaces.toList ++ ["missing", "alpha", "alpha alpha"] do
        check (target.contextSurface.getD key [] ==
            (target.surface.getD key []).filter LogicalText.singleUnit)
          "unit context directory changed repeated occurrence order or byte positions"
      for text in ["", "alpha", "alpha alpha alpha alpha", "alpha beta", "日本語 αβ",
          "./src/old.cc", "missing"] do
        let query := Matcher.compile normalize text
        for reverse in [false, true] do
          let (query, target) := if reverse then (target, query) else (query, target)
          let requested := Std.HashSet.ofList (query.logical.units.map (·.text))
          let directory := target.contextDemand query
          for key in requested.toList do
            check (directory.getD key [] == target.contextSurface.getD key [])
              "demanded context lost a repeated, negative or ordered unit lookup"
          check (directory.toList.all (fun entry => requested.contains entry.1))
            "demanded context retained an unrequested unit key"
          for validWeights in [false, true] do
            let weights := List.replicate
              (query.logical.units.length + if validWeights then 0 else 1) 7
            let actual := Matcher.surfaceContextCover query target weights 9
            let expected := Matcher.surfaceContextCoverWith target.surface query target weights 9
            check (decide (actual = expected))
              "unit-only context changed complete coverage, misses, weights or source spans"
            for native in [false, true] do
              let actualFragment := actual.bind fun coverage =>
                Matcher.materializeContext target.logical coverage.targetSpans native
              let expectedFragment := expected.bind fun coverage =>
                Matcher.materializeContext target.logical coverage.targetSpans native
              check (actualFragment == expectedFragment)
                "unit-only context changed authoritative source projection"
            comparisons := comparisons + 1
  let malformed : LogicalText.T := {original := "abc", text := "abc", units := [
    {logical := {start := 0, stop := 2}, source := {start := 0, stop := 1}, text := "different"},
    {logical := {start := 2, stop := 1}, source := {start := 8, stop := 9}, text := "backwards"},
    {logical := {start := 0, stop := 9}, source := {start := 0, stop := 3}, text := "out-of-bounds"}]}
  let pattern := Matcher.makePattern malformed
  for key in pattern.surfaces.toList ++ ["different", "backwards", "out-of-bounds"] do
    check (pattern.contextSurface.getD key [] ==
      (pattern.surface.getD key []).filter LogicalText.singleUnit)
      "unit directory assumed valid or disjoint arbitrary normalizer spans"
    let query := Matcher.compile LogicalText.logicalNormalizer key
    check (decide (Matcher.surfaceContextCover query pattern [7] 9 =
      Matcher.surfaceContextCoverWith pattern.contextSurface query pattern [7] 9))
      "demanded context assumed unit.text equals an arbitrary logical byte slice"
  IO.println s!"PASS prepared byte slices and context unit index: {comparisons} complete forward/reverse coverages, source fragments, repeats, Unicode/path/URI/native JSON, invalid weights and arbitrary spans"

/-- Controlled old eager/full versus demanded unit preparation. Only this
phase is timed; complete native hook comparisons are recorded separately. -/
def contextColdProcess (mode : String) (path : System.FilePath) : IO UInt32 := do
  check (mode == "write" || mode == "read") "context cold process expects write/read"
  let path ← DB.PageMap.absolute path
  let snapshot ← if mode == "write" then do
      if ← path.pathExists then IO.FS.removeDirAll path
      DB.PageMap.create path (Persistence.valueToJson (.text "cold-context-process")).compress
    else DB.PageMap.pin path
  let normalize := LogicalText.logicalNormalizer
  let query := Matcher.compile normalize (String.intercalate " " (List.replicate 32 "alpha") ++ " missing")
  let outcome := Matcher.compile normalize (String.intercalate " " (List.replicate 64 "alpha"))
  let corpus : Matcher.Corpus := {
    candidates := [], subworks := []
    population := if mode == "write" then 8 else 64,
    frequency := fun _ => if mode == "write" then 1 else 33}
  let reader ← Matcher.RankMemo.Reader.new snapshot .context
  let (actual, state) ← Matcher.GeometryMemo.Context.groundPatternsM normalize corpus false false none
    outcome query (some reader) {}
  let signature := fun (context : Option Matcher.ContextAlignment) =>
    context.map fun value => (value.demandInOutcome, value.outcomeFragment, value.alreadyVisible)
  check (signature actual.val == signature (Matcher.groundContextPatterns normalize corpus false false none outcome query))
    "independent process context differs from the complete reference"
  check (state.saved.length == 1 && (if mode == "write" then state.repaired == 1 && state.reused == 0
    else state.repaired == 0 && state.reused == 1)) "independent process failed to produce/replay its durable plan"
  Matcher.RankMemo.publish path state.saved .context
  let final ← DB.PageMap.pin path
  if mode == "read" then check (final.head == snapshot.head) "cold rescore rewrote identical context bytes"
  IO.println ((Lean.Json.mkObj [
    ("kind", .str "independent_context_process"), ("mode", .str mode),
    ("replayed", Lean.toJson state.reused), ("repaired", Lean.toJson state.repaired),
    ("charged", Lean.toJson state.charged), ("read_bytes", Lean.toJson (← snapshot.readBytes.get)),
    ("appended_bytes", Lean.toJson (final.head.bytes - snapshot.head.bytes)),
    ("covered_weight", Lean.toJson (actual.val.map (·.demandInOutcome.coveredWeight)))]).compress)
  IO.println s!"PASS separate process context {mode} with current frequency score and exact original coverage"
  pure 0

def contextReplayTiming : IO UInt32 := do
  let normalize := LogicalText.logicalNormalizer
  let query := Matcher.compile normalize (String.intercalate " " (List.replicate 512 "alpha"))
  let target := Matcher.compile normalize (String.intercalate " " (List.replicate 65536 "alpha"))
  let state ← Matcher.GeometryMemo.Context.Prepared.addM {} none query target
  let fixture ← IO.mkRef (query, target)
  let observed ← IO.mkRef (none : Option Matcher.Coverage)
  let mut samples : List Lean.Json := []
  for run in [:3] do
    let weights := List.replicate 512 (run + 3)
    let measure := fun current => do
      let (query, target) ← fixture.get
      let begin ← IO.monoNanosNow
      observed.set (if current then Matcher.GeometryMemo.Context.provider state.cache query target weights 100
        else Matcher.surfaceContextCover query target weights 100)
      let elapsed := (← IO.monoNanosNow) - begin
      return (← observed.get, elapsed)
    let (current, full) ← if run % 2 == 0 then do
      let full ← measure false
      let current ← measure true
      pure (current, full)
    else do
      let current ← measure true
      let full ← measure false
      pure (current, full)
    check (decide (current.1 = full.1) && current.1.any (fun c =>
      c.coveredUnits.length == 512 && c.coveredWeight == 512 * (run + 3)))
      "warm geometry timing changed complete coverage under new frequency scores"
    samples := samples ++ [Lean.Json.mkObj [("run", Lean.toJson run),
      ("current_ns", Lean.toJson current.2), ("directory_ns", Lean.toJson full.2)]]
  IO.println ((Lean.Json.mkObj [("kind", .str "context_frequency_rescore"),
    ("query_units", Lean.toJson (512 : Nat)), ("target_units", Lean.toJson (65536 : Nat)),
    ("samples", Lean.toJson samples), ("generative_calls", Lean.toJson (0 : Nat)),
    ("scope", .str "Warm certified context geometry plus complete fresh scoring after canonical normalization. Both lanes use identical current weights and complete Coverage comparison. Directory is rebuilt only in the current uncached reference. No whole-hook, storage or token claim.")]).compress)
  pure 0

def testContextReplay : IO Unit := do
  let normalize := LogicalText.logicalNormalizer
  let signature := fun (context : Option Matcher.ContextAlignment) =>
    context.map fun value => (value.demandInOutcome, value.outcomeFragment, value.alreadyVisible)
  let mut checks := 0
  for queryText in ["", "alpha alpha beta missing", "./src/old.cc 日本語 λ",
      String.intercalate " " (List.replicate 40 "alpha")] do
    let query := Matcher.compile normalize queryText
    for targetText in ["", "alpha alpha beta", "beta alpha alpha", "prefix alpha beta missing",
        "./src/old.cc 日本語 λ", String.intercalate " " (List.replicate 80 "alpha")] do
      let target := Matcher.compile normalize targetText
      let input : Matcher.GeometryMemo.Context.Input :=
        ⟨query.logical, target.logical, query.locator, target.locator⟩
      let original := Matcher.GeometryMemo.Context.obtain none input
      let encoded := Matcher.ContextPlan.encode original.1.instructions
      check (Matcher.ContextPlan.decode encoded == some original.1.instructions)
        "canonical context instruction codec changed a negative or original span"
      let replay := Matcher.GeometryMemo.Context.obtain (some encoded) input
      check replay.2 "a complete producer context plan did not certify"
      for hint in [encoded, [], encoded.tail, encoded.reverse, encoded ++ [0],
          encoded.map (· + 1), [1], [1, 1000000000], List.replicate 40 0] do
        let entry := (Matcher.GeometryMemo.Context.obtain (some hint) input).1
        let cache := ({} : Matcher.GeometryMemo.Context.Cache).insert input.locator entry
        for weights in [[], query.logical.units.map (fun _ => 3),
            query.logical.units.zipIdx.map (fun (_, n) => n + 1)] do
          for ceiling in [1, 8, 100] do
            check (decide (Matcher.GeometryMemo.Context.provider cache query target weights ceiling =
              Matcher.surfaceContextCover query target weights ceiling))
              "corrupt/truncated/negative context plan changed complete coverage or today's score"
            checks := checks + 1
      let changed := Matcher.compile normalize (targetText ++ " newly_matched")
      let changedInput := {input with target := changed.logical}
      let collision := ({} : Matcher.GeometryMemo.Context.Cache).insert changedInput.locator original.1
      check (Matcher.GeometryMemo.Context.lookup collision changedInput |>.isNone)
        "full source geometry was bypassed by a forced locator collision"
  let root ← DB.PageMap.absolute ".lake/context-replay"
  if ← root.pathExists then IO.FS.removeDirAll root
  let snapshot ← DB.PageMap.create root (Persistence.valueToJson (.text "context-replay")).compress
  let reader ← Matcher.RankMemo.Reader.new snapshot .context
  let queryText := String.intercalate " " (List.replicate 32 "alpha") ++ " missing"
  let query := Matcher.compile normalize queryText
  let outcomeText := String.intercalate " " (List.replicate 64 "alpha")
  let outcome := Matcher.compile normalize outcomeText
  let firstCorpus : Matcher.Corpus := {candidates := [], subworks := [], population := 8, frequency := fun _ => 1}
  let (first, state) ← Matcher.GeometryMemo.Context.groundPatternsM normalize firstCorpus false false
    (some "unused reverse evidence") outcome query (some reader) {}
  check (signature first.val == signature (Matcher.groundContextPatterns normalize firstCorpus false false
      (some "unused reverse evidence") outcome query) && state.repaired == 1 && state.reused == 0 &&
      state.saved.length == 1 && (← reader.loads.get) == 1)
    "actual forward grounding prepared an unused reverse demand or changed the original fragment"
  Matcher.RankMemo.publish root state.saved .context
  let published ← DB.PageMap.pin root
  let cold ← Matcher.RankMemo.Reader.new published .context
  let revised : Matcher.Corpus := {candidates := [], subworks := [], population := 64, frequency := fun _ => 33}
  let (second, repeated) ← Matcher.GeometryMemo.Context.groundPatternsM normalize revised true true
    none outcome query (some cold) {}
  check (repeated.reused == 1 && repeated.repaired == 0 &&
    signature second.val == signature (Matcher.groundContextPatterns normalize revised true true none outcome query) &&
    (second.val.map (·.demandInOutcome.coveredWeight)) != (first.val.map (·.demandInOutcome.coveredWeight)))
    "cold persisted geometry did not reuse the plan and reconstruct changed frequency/population/native scores"
  let (_, inMemory) ← Matcher.GeometryMemo.Context.groundPatternsM normalize firstCorpus false false
    none outcome query (some cold) repeated
  check (inMemory.memoryReused == 1 && inMemory.repaired == 0 && (← cold.loads.get) == 1)
    "unchanged source geometry was reloaded or recomputed for a new frequency demand"
  Matcher.RankMemo.publish root repeated.saved .context
  check ((← DB.PageMap.pin root).head == published.head)
    "frequency-only changes rewrote the identical durable geometric plan"
  check ((← Matcher.RankMemo.read published).isEmpty &&
      (← Matcher.RankMemo.read published .selection).isEmpty)
    "context plans entered the rank or selection namespace"
  -- Exercise the production PreparedMatch caller. The old plan must remain
  -- reachable after the source body changes, without copying it manually to
  -- the new body's hash. Every result is still checked against fresh grounding.
  let fixture ← contextQueryFixture queryText
  let makeRow := fun body => do
    let owner := OutcomeEdge.make (.text queryText) (.text body) [] (by simp) (by simp)
    let some candidate := Matcher.Corpus.compileCandidate normalize owner |
      throw (IO.userError "operation-bound context lost its candidate")
    return Matcher.PreparedMatch.make normalize (.text queryText) queryText fixture.demand
      candidate fixture.work false
  let originalRow ← makeRow outcomeText
  let (_, produced) ← Matcher.GeometryMemo.Context.groundRowM originalRow firstCorpus false none
    (some (← Matcher.RankMemo.Reader.new (← DB.PageMap.pin root) .context)) {}
  check (produced.saved.length == 1 && produced.saved.head!.1 ==
      Matcher.GeometryMemo.Context.hintKey query originalRow.candidate.work.locator)
    "production context used the changing body locator instead of the stable operation hint"
  Matcher.RankMemo.publish root produced.saved .context
  for (body, unchanged) in [(outcomeText ++ " unrequested_new_fact", true),
      (outcomeText ++ " missing", false), ("prefix " ++ outcomeText, false),
      (String.intercalate " " (List.replicate 31 "alpha"), false)] do
    let row ← makeRow body
    let reader ← Matcher.RankMemo.Reader.new (← DB.PageMap.pin root) .context
    let (actual, repaired) ← Matcher.GeometryMemo.Context.groundRowM row revised false none
      (some reader) {}
    let wanted := row.ground revised false none
    check (actual.val.demand == wanted.demand && actual.val.edge.relation == wanted.edge.relation &&
        actual.val.retrieved == wanted.retrieved && signature actual.val.context == signature wanted.context &&
        repaired.saved.head!.1 == produced.saved.head!.1 &&
        (← reader.loads.get) == 1 &&
        (if unchanged then repaired.reused == 1 && repaired.repaired == 0
          else repaired.reused == 0 && repaired.repaired == 1))
      "changed production body missed stable operation advice or diverged from full current grounding"
  -- Retain the old locator deliberately: actual input certification, rather
  -- than its address, must decide new/removed matches and shifted byte spans.
  for changedText in [outcomeText ++ " missing", "prefix " ++ outcomeText,
      "deleted_result", String.intercalate " " (List.replicate 31 "alpha")] do
    let changed := Matcher.compile normalize changedText
    -- Nominate the stale trace under the new address, so certification is
    -- exercised rather than merely missing the optional slot.
    let oldTrace := state.saved.head!.2
    Matcher.RankMemo.publish root [(Matcher.RankMemo.binding query changed, oldTrace)] .context
    let changedReader ← Matcher.RankMemo.Reader.new (← DB.PageMap.pin root) .context
    let (actual, repaired) ← Matcher.GeometryMemo.Context.groundPatternsM normalize firstCorpus false false
      none changed query (some changedReader) {}
    check (repaired.reused == 0 && repaired.repaired == 1 &&
      signature actual.val == signature (Matcher.groundContextPatterns normalize firstCorpus false false none changed query))
      "a new match, correction, deletion or changed span retained obsolete context"
  let missing := Matcher.compile normalize (String.intercalate " " (List.replicate 32 "absent"))
  let reverseEvidence := some (outcomeText ++ " evidence")
  let (reverse, reverseState) ← Matcher.GeometryMemo.Context.groundPatternsM normalize firstCorpus false false
    reverseEvidence outcome missing (some cold) {}
  check (reverseState.repaired == 2 && reverse.val.any (·.alreadyVisible) &&
    signature reverse.val == signature (Matcher.groundContextPatterns normalize firstCorpus false false
      reverseEvidence outcome missing))
    "failed forward grounding did not execute exactly the original evidence reverse lane"
  let _ ← DB.PageMap.withWriter (← DB.PageMap.pin root) fun writer => do
    for (key, _) in state.saved do
      Persistence.Store.putNat writer (Persistence.Store.key (Matcher.RankMemo.row key .context) 0) (10^12)
    Persistence.Store.writeChange writer ⟨[], [], false⟩
  let damaged ← Matcher.RankMemo.Reader.new (← DB.PageMap.pin root) .context
  let (recovered, repaired) ← Matcher.GeometryMemo.Context.groundPatternsM normalize firstCorpus false false
    none outcome query (some damaged) {}
  check (repaired.repaired == 1 && repaired.reused == 0 &&
    signature recovered.val == signature (Matcher.groundContextPatterns normalize firstCorpus false false none outcome query))
    "an oversized corrupt optional hint changed the authoritative result or prevented recovery"
  IO.println s!"PASS context geometry: {checks} full coverage oracles, canonical wire, cold/current scores, stable operation-bound repair after body changes, negative/new/deleted matches, collisions, corruption, separate DB lanes and unchanged publication"

def testContextQueue : IO Unit := do
  -- Preserve the original rarity interpreter independently of the array
  -- implementation, including invalid ordinals and weight defaults.
  let originalAnchors := fun (query : Matcher.Pattern) (weights : List Nat)
      (ceiling : Nat) (covered : List Nat) =>
    (covered.filterMap fun ordinal =>
      if Matcher.rareAnchor ceiling (weights.getD ordinal 0) then
        match query.logical.units[ordinal]? with
        | some unit => if unit.text.isEmpty then none else some unit.text
        | none => none
      else none).eraseDups.length
  let mut comparisons := 0
  for text in ["", "alpha alpha beta", "./src/old.cc https://example.invalid/v1", "日本語 αβ 🥚"] do
    let query := Matcher.compile LogicalText.logicalNormalizer text
    for weights in [[], List.replicate query.logical.units.length 7,
        (List.range (query.logical.units.length + 3)).map (fun n => n % 11)] do
      for covered in [[], [0, 0, 1, 9, 90000], List.range query.logical.units.length] do
        for ceiling in [0, 1, 3, 9, 10000] do
          check (Matcher.distinctiveAnchorCount query weights ceiling covered ==
              originalAnchors query weights ceiling covered)
            "array-backed rarity changed duplicates, absent weights or source units"
          comparisons := comparisons + 1
  let queryText := String.intercalate " " (List.replicate 8192 "alpha")
  let targetText := String.intercalate " " (List.replicate 16384 "alpha")
  let queries ← IO.mkRef (Matcher.compile LogicalText.logicalNormalizer queryText)
  let targets ← IO.mkRef (Matcher.compile LogicalText.logicalNormalizer targetText)
  let weights := List.replicate 8192 9
  -- Warm only canonical normalization. Both timed lanes construct the same
  -- demanded directory; neither gets an already built occurrence queue.
  check ((← queries.get).logical.units.length == 8192 &&
      (← targets.get).logical.units.length == 16384) "repeated-word fixture did not contain its complete units"
  let observed ← IO.mkRef (none : Option Matcher.Coverage)
  let mut currentTimes : List Nat := []
  let mut referenceTimes : List Nat := []
  let mut signature : Option (Option Matcher.Coverage) := none
  for run in [:3] do
    -- Alternate order; keep pure calls behind dynamic Ref reads and store
    -- their complete result before reading the ending clock.
    for current in (if run % 2 == 0 then [true, false] else [false, true]) do
      let query ← queries.get
      let target ← targets.get
      let begin ← IO.monoNanosNow
      observed.set (if current then Matcher.surfaceContextCover query target weights 9
        else Matcher.surfaceContextCoverWith (target.contextDemand query) query target weights 9)
      let elapsed := (← IO.monoNanosNow) - begin
      let result ← observed.get
      if let some previous := signature then
        check (decide (result = previous)) "queue optimization changed full coverage, positions or score"
      signature := some result
      if current then currentTimes := currentTimes ++ [elapsed]
      else referenceTimes := referenceTimes ++ [elapsed]
  let some (some result) := signature | throw (IO.userError "repeated words produced no complete coverage")
  check (result.coveredUnits == List.range 8192 && result.coveredWeight == 8192 * 9 &&
      result.distinctiveAnchors == 1 && result.querySpans.length == 8192 && result.targetSpans.length == 8192)
    "queue optimization lost repeated occurrences or double-counted a rarity anchor"
  check (currentTimes.all (fun n => n * 2 < referenceTimes.foldl Nat.min (referenceTimes.headD 0)))
    "certified occurrence queues showed no repeatable gain on the quadratic negative control"
  IO.println ((Lean.Json.mkObj [("kind", .str "certified_context_queue"),
    ("query_units", Lean.toJson (8192 : Nat)), ("target_units", Lean.toJson (16384 : Nat)),
    ("anchor_oracle_comparisons", Lean.toJson comparisons), ("current_ns", Lean.toJson currentTimes),
    ("filtered_queue_ns", Lean.toJson referenceTimes), ("complete_coverage_equal", .bool true),
    ("generative_calls", Lean.toJson (0 : Nat)),
    ("scope", .str "Demand directory construction and complete context coverage after canonical normalization. Three alternating measurements with dynamic inputs. Both lanes use current scoring; the reference retains the old repeated filtering. Not whole-hook or token evidence.")]).compress)
  IO.println "PASS certified context queues: complete original coverage, repeated/absent units, arbitrary spans in the unit suite, stale weight/position defaults, rare-anchor oracle and repeated phase gain"

def contextUnitTiming (mode : String) : IO UInt32 := do
  check (mode == "before" || mode == "unit" || mode == "current")
    "context unit timing expects before, unit or current"
  let text := String.intercalate "\n" ((List.range 65536).map fun i => s!"dependency_symbol_{i}")
  let query := Matcher.compile LogicalText.logicalNormalizer
    "dependency_symbol_17 dependency_symbol_4095 dependency_symbol_65535 dependency_symbol_17 missing"
  let weights := List.replicate query.logical.units.length 7
  let mut samples : List Nat := []
  let mut signature : Option String := none
  let mut forcedKeys := 0
  for run in [:4] do
    let begin ← IO.monoNanosNow
    -- Each iteration has distinct bytes. Otherwise pure preparation can be
    -- shared and cached thunks measure only replay after the first sample.
    let target := Matcher.compile LogicalText.logicalNormalizer (text ++ s!"\ntrial_{run}")
    let (coverage, keys) := if mode == "before" then
      (Matcher.surfaceContextCoverWith target.surface query target weights 9, target.surfaces.size)
    else if mode == "unit" then
      (Matcher.surfaceContextCoverWith target.contextSurface query target weights 9, 0)
    else (Matcher.surfaceContextCover query target weights 9, 0)
    let observed := reprStr coverage
    let fingerprint := s!"{keys}: {observed}"
    let elapsed := (← IO.monoNanosNow) - begin
    forcedKeys := forcedKeys + keys
    if let some previous := signature then
      check (fingerprint == previous) "context unit phase changed its complete coverage"
    signature := some fingerprint
    samples := samples ++ [elapsed]
  IO.println ((Lean.Json.mkObj [("kind", .str "context_unit_preparation"),
    ("mode", .str mode), ("source_base_bytes", Lean.toJson text.utf8ByteSize),
    ("source_units", Lean.toJson (65537 : Nat)), ("forced_work_keys", Lean.toJson forcedKeys),
    ("signature", .str (signature.getD "")), ("samples", Lean.toJson samples),
    ("scope", .str "Four distinct fresh texts. Normalizer, canonical Pattern preparation and complete context coverage. Unit uses the full unit directory; current retains only demanded keys. Both use the byte preparation in this binary. Before forces full Work anchors. Includes resident input; no storage, model call or whole-hook claim.")]).compress)
  pure 0

def contextQueryTiming (mode : String) : IO UInt32 := do
  check (mode == "before" || mode == "current") "context query timing expects before or current"
  let text := String.intercalate " " ((List.range 1024).map fun i => s!"dependency_symbol_{i}")
  let fixture ← contextQueryFixture text
  let mut samples : List Nat := []
  let mut signature : Option (Nat × UInt64) := none
  for _ in [:8] do
    let begin ← IO.monoNanosNow
    let rows := (List.range 64).map fun _ =>
      if mode == "before" then contextRowBeforeReuse text fixture.candidate fixture.work else
        Matcher.PreparedMatch.make LogicalText.logicalNormalizer (.text text) text fixture.demand
          fixture.candidate fixture.work false
    let terms := if mode == "before" then contextTermsBeforeStreaming rows false else Matcher.contextTerms rows false
    let digest := rows.foldl (fun digest row => row.contextQuery.toList.foldl (fun digest pattern =>
      mixHash digest (mixHash pattern.locator (mixHash (hash pattern.logical.units.length)
        (mixHash (hash pattern.surface.size) (hash pattern.surfaces.size))))) digest) (0 : UInt64)
    let digest := terms.foldl (fun digest term => mixHash digest (hash term)) digest
    let observed := (terms.length, digest)
    if let some previous := signature then
      check (observed == previous) "context query phase changed its complete fingerprint"
    signature := some observed
    let elapsed := (← IO.monoNanosNow) - begin
    check (elapsed > 0) "context query clock was read before evaluating the result"
    samples := samples ++ [elapsed]
  let some (terms, fingerprint) := signature | throw (IO.userError "missing context query timing signature")
  IO.println ((Lean.Json.mkObj [("kind", .str "repeated_context_query_preparation"),
    ("mode", .str mode), ("query_bytes", Lean.toJson text.utf8ByteSize),
    ("query_units", Lean.toJson fixture.demand.pattern.logical.units.length),
    ("rows", Lean.toJson (64 : Nat)), ("unique_terms", Lean.toJson terms),
    ("fingerprint", Lean.toJson fingerprint.toNat), ("samples", Lean.toJson samples),
    ("scope", .str "Factory and frequency-term collection only, with 64 repetitions of one actual Work alignment. Includes resident fixture; no new model calls or whole hook/storage claim.")]).compress)
  pure 0

def testDemandFrequencies : IO Unit := do
  let known : Std.HashMap String Nat := ({} : Std.HashMap String Nat).insert "retained" 7
  let requests ← IO.mkRef ([] : List String)
  let read := fun terms => do
    requests.modify (· ++ terms)
    -- An overlapping returned key cannot replace the pinned Work weight.
    pure ((terms.foldl (fun table term => table.insert term 0) ({} : Std.HashMap String Nat)).insert "retained" 99)
  let response ← readDemandFrequencies read known ["retained", "missing_zero"]
  check ((← requests.get) == ["missing_zero"] && response.table.getD "retained" 0 == 7 &&
      response.table.contains "missing_zero" && response.table.getD "missing_zero" 1 == 0)
    "frequency completion overwrote Work weights, reread a known key or lost an explicit zero"
  let rejected ← try
      let _ ← readDemandFrequencies (fun _ => pure {}) known ["omitted"]
      pure false
    catch _ => pure true
  check rejected "an omitted demanded frequency was silently replaced with zero"
  let normalizer := LogicalText.logicalNormalizer
  let owner := OutcomeEdge.make (.text "investigate alpha parser")
    (.text "alpha parser confirmed\nresult_only_word reverse_evidence") [] (by simp) (by simp)
  let other := OutcomeEdge.make (.text "investigate beta parser")
    (.text "beta evidence corrected") [] (by simp) (by simp)
  let corpus := Matcher.Corpus.build normalizer {outcomes := [owner, other]}
  let source := fun terms => pure (terms.foldl
    (fun table term => table.insert term (corpus.frequency term)) ({} : Std.HashMap String Nat))
  let mut comparisons := 0
  for text in ["investigate alpha parser", "alpha parser", "parser", "new missing evidence"] do
    for native in [false, true] do
      for evidence in [none, some "result_only_word reverse_evidence", some "absent external evidence"] do
        for semantic in [{}, ({related := [owner.relation, other.relation]} : Matcher.SemanticNominations)] do
          let query := Matcher.CompiledDemand.make normalizer text native
          let workRead ← readDemandFrequencies source {} (Matcher.Corpus.workTerms corpus.candidates query)
          let workCorpus := {corpus with frequency := fun term => workRead.table.getD term 0}
          let prepared := Matcher.prepareInUsing normalizer Matcher.pairedCoverages Quotient.literal
            workCorpus (.text text) text native query semantic
          let terms := Matcher.contextTerms prepared evidence.isSome
          if evidence.isNone then
            check (!terms.contains "result_only_word")
              "forward context requested an unused Outcome query weight"
          let contextRead ← readDemandFrequencies source workRead.table terms
          let groundedCorpus := {corpus with frequency := fun term => contextRead.table.getD term 0}
          let actual := prepared.map (fun row => row.ground groundedCorpus native evidence)
          let expected := findInUsingBeforeWorkGate normalizer (Matcher.CompiledDemand.make normalizer)
            Matcher.pairedCoverages Quotient.literal corpus (.text text) text evidence semantic native
          let flags := fun (m : Matcher.Match) => [m.work.subwork, m.work.pastWholeWork,
            m.work.wholeWorkIdentity, m.work.fragmentIdentity, m.retrieved]
          let fragments := fun (m : Matcher.Match) => [m.demand, m.edge.relation,
            m.work.pastFragment, m.work.currentFragment]
          let context := fun (m : Matcher.Match) => m.context.map fun c =>
            (c.demandInOutcome, c.outcomeFragment, c.alreadyVisible)
          check (actual.length == expected.length && actual.map flags == expected.map flags &&
              actual.map fragments == expected.map fragments && actual.map context == expected.map context &&
              actual.map (·.work.priorInDemand) == expected.map (·.work.priorInDemand) &&
              actual.map (·.work.demandInPrior) == expected.map (·.work.demandInPrior) &&
              actual.map (fun m => (m.work.pastSpan, m.work.currentSpan)) ==
                expected.map (fun m => (m.work.pastSpan, m.work.currentSpan)))
            "two-phase demanded frequency reads changed the full ordered pre-change Match"
          comparisons := comparisons + 1
  IO.println s!"PASS demanded frequencies: {comparisons} full Match comparisons, forward/reverse, native, semantic, explicit zero, missing-key rejection and pinned-weight preservation"

def testStreamingSourceParts : IO Unit := do
  let sources := ["", "\n", "\\n", "alpha\nbeta\n", "alpha\\nbeta\\n",
    "α😀\n共有\n", "ababacabac", "\\\\n\\nend", "aaaaa", "line\r\nnext\r\n"]
  for source in sources do
    for separator in ["", "\n", "\\n", "aba", "aa", "😀", "\r\n"] do
      for start in [0, 1, source.utf8ByteSize / 2, source.utf8ByteSize,
          source.utf8ByteSize + 1] do
        let spans : List LogicalText.ByteSpan := [{start, stop := start + 2},
          {start := 0, stop := 0}, {start := start + 1, stop := start + 5}]
        check (Matcher.intersectingSourceParts spans separator source =
          sourcePartsBeforeStreaming spans separator source)
          "streamed source projection changed exact bytes, delimiter semantics or line order"
        let consume := fun rows part => rows ++ [part]
        check (TextParts.foldSplitOn consume ([] : List String) source separator = source.splitOn separator)
          "streamed splitter changed an empty, overlapping or multibyte part"
      for spans in [([] : List LogicalText.ByteSpan), [{start := 0, stop := 0}],
          [{start := 9, stop := 3}], [{start := 0, stop := 1}],
          [{start := 4, stop := 7}, {start := 0, stop := 2}],
          [{start := source.utf8ByteSize + 2, stop := source.utf8ByteSize + 4}]] do
        check (Matcher.intersectingSourceParts spans separator source =
          sourcePartsBeforeStreaming spans separator source)
          "demand stopping dropped an empty, reversed, unsorted or out-of-source span"
  let suffix := String.join (List.replicate 32768 "irrelevant trailing source α😀\n")
  for separator in ["\n", "\\n", "aba", "😀", ""] do
    let first := "requested exact evidence"
    let source := first ++ separator ++ suffix
    let spans : List LogicalText.ByteSpan := [{start := 0, stop := 3}]
    check (Matcher.intersectingSourceParts spans separator source =
      sourcePartsBeforeStreaming spans separator source)
      "demand projection changed exact evidence preceding a large irrelevant suffix"
  let giantLine := String.join (List.replicate 32768 "selected evidence ")
  check (Matcher.intersectingSourceParts [{start := 0, stop := 1}] "\n" giantLine = [giantLine])
    "demand stopping truncated a required complete source line"
  let text := String.join (List.replicate 2048 "alpha 😀\nbeta\\ngamma\n")
  let spans : List LogicalText.ByteSpan := [{start := 0, stop := text.utf8ByteSize}]
  check (Matcher.intersectingSourceParts spans "\n" text = sourcePartsBeforeStreaming spans "\n" text)
    "streamed projection changed a complete multi-line selection"
  for native in [false, true] do
    let logical := LogicalText.logical text
    let spans := logical.units.take 12 |>.map (·.logical)
    check (decide (Matcher.materializeContext logical spans native =
      materializeContextBeforeStreaming logical spans native))
      "streamed source parts changed native grounding or synthesis projection"
  IO.println "PASS demanded source-part fold, full delimiter/Unicode/empty/overlap oracle, irrelevant suffix exclusion and whole required native projections"

/-- Timing the connected projection phase only. Per-run source bytes differ
to prevent repeated pure evaluation from becoming a shared-result benchmark.
Both controls are full earlier implementations, not a fabricated slow path. -/
def sourcePartDemandTiming (mode : String) : IO UInt32 := do
  let select ← match mode with
    | "list" => pure sourcePartsBeforeStreaming
    | "whole-stream" => pure (fun spans separator source =>
        (TextParts.foldSplitOn (Matcher.sourcePartStep spans separator) (0, []) source separator).2.reverse)
    | "demand" => pure Matcher.intersectingSourceParts
    | _ => throw (IO.userError "source part demand timing expects list, whole-stream or demand")
  let firstLine := "src/test.cc:42 requested exact evidence 😀\n"
  let spans : List LogicalText.ByteSpan := [{start := 0, stop := 5}]
  let mut samples : List Lean.Json := []
  for n in [:5] do
    let line := s!"unrelated tail {n} α😀\n"
    let text := firstLine ++ String.join (List.replicate 262144 line)
    let started ← IO.monoNanosNow
    let selected := select spans "\n" text
    check (selected == [firstLine.dropEnd 1 |>.copy]) "source demand timing changed exact evidence"
    let fingerprint := hash selected
    let elapsed := (← IO.monoNanosNow) - started
    samples := samples ++ [Lean.Json.mkObj [
      ("run", Lean.toJson n), ("input_bytes", Lean.toJson text.utf8ByteSize),
      ("selected_parts", Lean.toJson selected.length),
      ("fingerprint", Lean.toJson fingerprint.toNat), ("elapsed_ns", Lean.toJson elapsed)]]
  IO.println ((Lean.Json.mkObj [("kind", .str "source_part_demand_projection"),
    ("mode", .str mode), ("samples", Lean.toJson samples)]).compress)
  pure 0

def sourcePartsTiming (mode : String) : IO UInt32 := do
  let line := "src/test.cc:42 alpha beta gamma 😀\n"
  let text := String.join (List.replicate 262144 line)
  let spans : List LogicalText.ByteSpan := (List.range 8).map fun n =>
    {start := n * 32768 * line.utf8ByteSize, stop := n * 32768 * line.utf8ByteSize + 5}
  let select ← match mode with
    | "list" => pure sourcePartsBeforeStreaming
    | "stream" => pure Matcher.intersectingSourceParts
    | _ => throw (IO.userError "source parts timing mode must be list or stream")
  let mut samples : List Nat := []
  let mut signature : Option (Nat × UInt64) := none
  for _ in [:8] do
    let start ← IO.monoNanosNow
    let selected := select spans "\n" text
    let actual := (selected.length, hash selected)
    check (actual.1 == 8) "source-parts timing failed to project eight exact source lines"
    if let some prior := signature then check (actual == prior) "source-parts timing changed selected bytes"
    let elapsed := (← IO.monoNanosNow) - start
    signature := some actual
    samples := elapsed :: samples
  let some (parts, fingerprint) := signature | throw (IO.userError "source parts timing did not run")
  IO.println ((Lean.Json.mkObj [("kind", .str "source_part_projection"), ("mode", .str mode),
    ("input_bytes", Lean.toJson text.utf8ByteSize), ("source_parts", Lean.toJson (262145 : Nat)),
    ("selected_parts", Lean.toJson parts), ("fingerprint", Lean.toJson fingerprint.toNat),
    ("samples", Lean.toJson samples.reverse)]).compress)
  pure 0

def testRootReachTraversal : IO Unit := do
  let empty : Value := .atom ByteArray.empty
  let unicode := Value.text "共有 α 😀 ./src/test.cc"
  let observed := Value.applyList .occurrence [.semantic unicode, .exact empty]
  let shared := Value.applyList .occurrence [.semantic observed, .exact observed]
  let exactOnly := Value.applyList .occurrence [.semantic (Value.text "private"), .exact unicode]
  for width in [:12] do
    let refs := List.replicate width (.semantic, shared) ++
      [(.exact, exactOnly), (.semantic, unicode), (.exact, empty)]
    let root := Value.applyList .occurrence refs
    let actual := Persistence.Store.RootReach.compile root
    check (decide (actual = rootReachBeforeFold root))
      "streamed reach changed first-occurrence order or Semantic/Exact membership"
    check (root.foldNodes (fun seen node => node :: seen) ([] : List Value) = root.nodes.reverse)
      "direct structural traversal changed complete preorder"
    check (root.foldSemanticNodes (fun seen node => node :: seen) ([] : List Value) =
      root.semanticNodes.reverse)
      "direct semantic traversal crossed an Exact reference or changed order"
  IO.println "PASS direct save-time root traversal equals frozen compiler: duplicate subtrees, empty/Unicode Atoms, first occurrence, mixed roles and Exact-only descendants"

def rootReachTiming (mode : String) : IO UInt32 := do
  let compile ← match mode with
    | "fold" => pure Persistence.Store.RootReach.compile
    | "list" => pure rootReachBeforeFold
    | _ => throw (IO.userError "root reach timing expects fold or list")
  let mut shared := Value.text "original evidence"
  for _ in [:5] do
    shared := Value.applyList .occurrence [.semantic shared, .exact shared]
  let root := Value.applyList .all
    (.semantic (Value.text "parent") :: List.replicate 16384 (.semantic, shared))
  let structural := root.foldNodes (fun count _ => count + 1) (0 : Nat)
  let semantic := root.foldSemanticNodes (fun count _ => count + 1) (0 : Nat)
  let mut samples : List Lean.Json := []
  let mut signature : Option (Nat × UInt64) := none
  for run in [:8] do
    let started ← IO.monoNanosNow
    let rows := compile root
    let fingerprint := rows.foldl (fun digest row => mixHash digest
      (mixHash (hash row.1) (hash row.2))) (0 : UInt64)
    let current := (rows.length, fingerprint)
    if let some previous := signature then
      check (current == previous) "root reach changed between identical evaluations"
    signature := some current
    samples := samples ++ [Lean.Json.mkObj [
      ("run", Lean.toJson run), ("elapsed_ns", Lean.toJson ((← IO.monoNanosNow) - started))]]
  let some (rows, fingerprint) := signature | throw (IO.userError "root reach timing did not run")
  IO.println ((Lean.Json.mkObj [("kind", .str "root_reach_traversal"), ("mode", .str mode),
    ("structural_occurrences", Lean.toJson structural), ("semantic_occurrences", Lean.toJson semantic),
    ("unique_rows", Lean.toJson rows), ("fingerprint", Lean.toJson fingerprint.toNat),
    ("samples", Lean.toJson samples)]).compress)
  pure 0

def testStreamingNormalizer : IO Unit := do
  for text in ["", "Alpha_beta ./src/old.cc. ../src/new.cc...",
      "日本語 Ελληνικά STRASSE Straße İ é 👩‍💻\n\t",
      "./ ./... a/b.cc... a.b .. /tmp/root\\file", "\x00a\r\nb",
      String.intercalate "" (List.replicate 256 "path/子.cc.\nα β 😀 "),
      String.intercalate "" (List.replicate 4096 "a"),
      String.intercalate "" (List.replicate 4096 ".")] do
    let actual := LogicalText.logicalNormalizer text
    let expected := logicalNormalizerBeforeStreaming text
    check (decide (actual = expected))
      "UTF-8 iteration changed normalization or exact source positions"
    check (LogicalText.build LogicalText.logicalNormalizer text ==
      LogicalText.build logicalNormalizerBeforeStreaming text)
      "direct character iteration changed units or their original-byte spans"
  IO.println "PASS direct UTF-8 normalization equals frozen list scanner: Unicode, paths, exact spans, empty text, control characters and long compounds"

def normalizerTiming (mode : String) : IO UInt32 := do
  let normalize ← match mode with
    | "stream" => pure LogicalText.logicalNormalizer
    | "list" => pure logicalNormalizerBeforeStreaming
    | _ => throw (IO.userError "normalizer timing expects stream or list")
  let text := String.intercalate "" (List.replicate 65536 "Alpha_beta ./src/old.cc. 日本語.\n")
  let mut samples : List Lean.Json := []
  let mut signature : Option (Nat × UInt64) := none
  for run in [:8] do
    let started ← IO.monoNanosNow
    let pieces := normalize text
    let fingerprint := pieces.foldl (fun digest piece => mixHash digest
      (mixHash (hash piece.text) (hash piece.source))) (0 : UInt64)
    let current := (pieces.length, fingerprint)
    if let some previous := signature then
      check (current == previous) "normalization changed between identical evaluations"
    signature := some current
    samples := samples ++ [Lean.Json.mkObj [
      ("run", Lean.toJson run), ("elapsed_ns", Lean.toJson ((← IO.monoNanosNow) - started))]]
  let some (pieces, fingerprint) := signature | throw (IO.userError "normalization timing did not run")
  IO.println ((Lean.Json.mkObj [("kind", .str "utf8_normalization"), ("mode", .str mode),
    ("input_bytes", Lean.toJson text.utf8ByteSize), ("pieces", Lean.toJson pieces),
    ("fingerprint", Lean.toJson fingerprint.toNat), ("samples", Lean.toJson samples)]).compress)
  pure 0

def runTests (semanticOnly : Bool := false) : IO UInt32 := do
  try
    let some dataRoot ← IO.getEnv "EGGSHELL_DATA_ROOT" |
      throw (IO.userError "tests require an isolated EGGSHELL_DATA_ROOT")
    let home := (← IO.getEnv "HOME").getD ""
    let root := System.FilePath.mk dataRoot
    check (root.isAbsolute)
      "tests require an absolute EGGSHELL_DATA_ROOT"
    check (root.normalize != System.FilePath.mk home /
        ".local" / "share" / "eggshell" / "plugin")
      "tests refuse to use the default Eggshell data directory"
    clean
    if semanticOnly then
      testIndependentProviderBoundary
      testSemanticProviderTransport
      testSemanticResourceLanes
      testSearchAdmission
      testParallelSearchAdmission
      testParallelSearchPipes
      testIncompleteSearchDelivery
      testNaturalLanguageSessionTransport
      testGroundedOutcomeTransport
      testWholeSliceBudget
      testBackgroundIndexRecovery
      testSaveWhileIndexBusy
      Worker.shutdown
      return 0
    testStreamingNormalizer
    Eggshell.SourceEvidenceTests.run
    testRootReachTraversal
    testStreamingSourceParts
    testDemandFrequencies
    testContextQueryReuse
    testContextUnitIndex
    testNativeWorkUnits
    testIncrementalSearch
    testSignatureDependencies
    testGeneralCongruenceMemo
    testGeneratedCongruence
    testFrequencyDelta
    testLexicalFrequencyDelta
    testIndexedNumericalWindows
    testIndependentProviderBoundary
    testRankingDelta
    testPersistenceDag
    testPrivateStorage
    testAuthorityPathBoundaries
    testLocalUnion
    testSemanticProviderTransport
    testSemanticResourceLanes
    testSearchAdmission
    testParallelSearchAdmission
    testParallelSearchPipes
    testParallelSearchPipes
    testIncompleteSearchDelivery
    testBackgroundIndexRecovery
    testSaveWhileIndexBusy
    testSaveWhileIndexBusy
    testNaturalLanguageSessionTransport
    testGroundedOutcomeTransport
    testOperationBoundaryLookup
    testWholeSliceBudget
    testConcurrentPromotion
    testUnionSuppression
    testUnionDeltaIO
    testConfig
    testProjectInit
    testMiniLMDefault
    testMatcherScale
    testPluginBundle
    testInstallerOwnership
    testHooks
    testDaemonConcurrency
    testLifecycle
    Worker.shutdown
    pure 0
  catch error =>
    Worker.shutdown
    IO.eprintln s!"FAIL {error}"
    pure 1

def main (arguments : List String) : IO UInt32 :=
  match arguments with
  | ["source-evidence-tests"] => do
      Eggshell.SourceEvidenceTests.run
      pure 0
  | ["normalizer-tests"] => do
      testStreamingNormalizer
      pure 0
  | ["normalizer-timing", mode] => normalizerTiming mode
  | ["root-reach-tests"] => do
      testRootReachTraversal
      pure 0
  | ["root-reach-timing", mode] => rootReachTiming mode
  | ["source-parts-tests"] => do
      testStreamingSourceParts
      pure 0
  | ["demand-frequency-tests"] => do
      testDemandFrequencies
      Eggshell.PageDBTests.workFirst
      pure 0
  | ["context-query-tests"] => do
      testContextQueryReuse
      testDemandFrequencies
      pure 0
  | ["lazy-normalization-tests"] => do
      testLazyNormalization
      pure 0
  | ["context-query-timing", mode] => contextQueryTiming mode
  | ["context-unit-tests"] => do
      testContextUnitIndex
      pure 0
  | ["context-cold-process", mode, path] => contextColdProcess mode path
  | ["context-replay-timing"] => contextReplayTiming
  | ["context-replay-tests"] => do
      testContextReplay
      pure 0
  | ["context-queue-tests"] => do
      testContextQueue
      pure 0
  | ["context-unit-timing", mode] => contextUnitTiming mode
  | ["source-parts-timing", mode] => sourcePartsTiming mode
  | ["source-part-demand-timing", mode] => sourcePartDemandTiming mode
  | "search-provider" :: args => SearchProvider.run args
  | "independent-search-provider" :: args => SearchProvider.run args
  | ["indexed-pull-provider-fixture", mode] => indexedPullProviderFixture mode
  | ["codex-worker", role] => Worker.run role
  | ["codex-daemon", session] => Plugin.Daemon.run session
  | ["codex-rpc", kind] =>
      if kind.startsWith "stalled-rpc:" then
        stalledPipePeer (.mk (kind.drop "stalled-rpc:".length).copy)
      else Plugin.Daemon.rpcClient kind
  | ["codex-hook"] => Plugin.Daemon.hookClient
  | ["semantic-provider-fixture", "retrieval"] => semanticProviderFixture
  | ["semantic-provider-fixture", "empty"] => semanticProviderFixture 0 none none [] false
  | ["semantic-provider-fixture", "child"] => semanticProviderFixture 1
  | ["semantic-provider-fixture", "child-after-two-parents"] => semanticProviderFixture 2
  | ["semantic-provider-fixture", "child-context"] => semanticProviderFixture 1 none none [3, 13, 27]
  | ["semantic-provider-fixture", "parent-context"] => semanticProviderFixture 1 none none [3, 13, 27] true (some [0])
  | ["semantic-provider-fixture", "retry-index", marker] =>
      semanticProviderFixture 0 (some (.mk marker))
  | ["semantic-provider-fixture", "batch-index", log] =>
      semanticProviderFixture 0 none (some (.mk log))
  | ["semantic-lane-holder", "search", ready, release] =>
      semanticLaneHolder .search (.mk ready) (.mk release)
  | ["semantic-lane-holder", "index", ready, release] =>
      semanticLaneHolder .index (.mk ready) (.mk release)
  | ["semantic-transport-tests"] => runTests true
  | ["handoff-delivery-tests"] => do
      clean
      testSemanticEvidenceDelivery
      Worker.shutdown
      pure 0
  | ["flexible-context-tests"] => do
      testFlexibleContextAllocation
      pure 0
  | ["search-admission-tests"] => do
      testSearchAdmission
      testParallelSearchAdmission
      pure 0
  | ["page-db-tests"] => do
      Eggshell.PageDBTests.outcomeCompilation
      Eggshell.PageDBTests.pinnedNodeReader
      Eggshell.PageDBTests.topologyNodeReader
      Eggshell.PageDBTests.indexedSelection
      Eggshell.PageDBTests.rows
      Eggshell.PageDBTests.directories
      Eggshell.PageDBTests.frames
      Eggshell.PageDBTests.terms
      Eggshell.PageDBTests.workSurfaces
      Eggshell.PageDBTests.workFirst
      Eggshell.PageDBTests.indexedGeneral
      Eggshell.PageDBTests.semanticCatalogue
      Eggshell.PageDBTests.federatedSearch
      Eggshell.PageDBTests.canonicalFederation
      Eggshell.PageDBTests.rankDirectory
      Eggshell.PageDBTests.selectionReplay
      Eggshell.PageDBTests.rankMemo
      Eggshell.PageDBTests.saturationMemo
      Eggshell.PageDBTests.demandMemo
      Eggshell.PageDBTests.semanticDemandMemo
      Eggshell.PageDBTests.readDependencies
      Eggshell.PageDBTests.publicationSeal
      Eggshell.PageDBTests.chunkDelta
      Eggshell.PageDBTests.retractions
      pure 0
  | ["pinned-node-reader-tests"] => do
      Eggshell.PageDBTests.pinnedNodeReader
      pure 0
  | ["rank-directory-tests"] => do
      Eggshell.PageDBTests.rankDirectory
      pure 0
  | ["selection-replay-tests"] => do
      Eggshell.PageDBTests.selectionReplay
      pure 0
  | ["topology-reader-tests"] => do
      Eggshell.PageDBTests.topologyNodeReader
      pure 0
  | ["outcome-compilation-tests"] => do
      Eggshell.PageDBTests.outcomeCompilation
      pure 0
  | ["outcome-compilation-timing", mode] => Eggshell.PageDBTests.outcomeCompileTiming mode
  | ["indexed-selection-tests"] => do
      Eggshell.PageDBTests.indexedSelection
      pure 0
  | ["semantic-catalogue-tests"] => do
      Eggshell.PageDBTests.semanticCatalogue
      pure 0
  | ["federated-search-tests"] => do
      Eggshell.PageDBTests.federatedSearch
      pure 0
  | ["canonical-federation-tests"] => do
      Eggshell.PageDBTests.canonicalFederation
      pure 0
  | ["saturation-memo-tests"] => do
      Eggshell.PageDBTests.saturationMemo
      pure 0
  | ["discovery-checkpoint-tests"] => do
      Eggshell.PageDBTests.discoveryCheckpoint
      pure 0
  | ["indexed-numerical-tests"] => do
      testIndexedNumericalWindows
      pure 0
  | ["independent-provider-tests"] => do
      testIndependentProviderBoundary
      Eggshell.PageDBTests.semanticCatalogue
      pure 0
  | ["indexed-query-timing", path, cache, input] => do
      indexedQueryTiming (.mk path) (.mk cache) (.mk input)
      pure 0
  | ["hook-lifecycle-tests"] => do
      testHooks
      testDaemonConcurrency
      testLifecycle
      pure 0
  | ["work-first-tests"] => do
      Eggshell.PageDBTests.workFirst
      pure 0
  | ["work-surface-tests"] => do
      Eggshell.PageDBTests.workSurfaces
      pure 0
  | ["support-work-index-tests"] => do
      Eggshell.PageDBTests.supportWorkIndex
      pure 0
  | ["all-parent-index-tests"] => do
      Eggshell.PageDBTests.allParentIndex
      pure 0
  | ["quotient-child-role-tests"] => do
      Eggshell.PageDBTests.quotientChildRole
      pure 0
  | ["demand-topology-tests"] => do
      Eggshell.PageDBTests.demandTopology
      pure 0
  | ["indexed-general-tests"] => do
      Eggshell.PageDBTests.indexedGeneral
      pure 0
  | ["read-dependency-tests"] => do
      Eggshell.PageDBTests.readDependencies
      pure 0
  | ["payload-dependency-tests"] => do
      Eggshell.PageDBTests.payloadDependencies
      pure 0
  | ["body-prefix-tests"] => do
      Eggshell.PageDBTests.bodyPrefixDependencies
      pure 0
  | ["read-trace-index-tests"] => do
      Eggshell.PageDBTests.readTraceIndex
      IO.println "PASS indexed complete dependency capture, collisions, corrections, negative ranges and permanent overflow"
      pure 0
  | ["immutable-dependency-tests"] => do
      Eggshell.PageDBTests.immutableDependencies
      IO.println "PASS compact persisted body dependencies, foreign identity, append/recovery, corruption and truncation"
      pure 0
  | ["semantic-demand-tests"] => do
      Eggshell.PageDBTests.semanticDemandMemo
      pure 0
  | ["llvm-db-tests", seed, target] => do
      Eggshell.PageDBTests.llvm (.mk seed) (.mk target)
      pure 0
  | ["frequency-delta-tests"] => do
      testFrequencyDelta
      testLexicalFrequencyDelta
      testRankingDelta
      pure 0
  | ["general-congruence-tests"] => do
      testSignatureDependencies
      testGeneralCongruenceMemo
      testGeneratedCongruence
      testGeneralCongruencePerformance
      pure 0
  | ["signature-dependency-tests"] => do
      testSignatureDependencies
      testGeneralCongruenceMemo
      pure 0
  | ["signature-dependency-timing"] => do
      testSignatureDependencyPerformance
      pure 0
  | ["generated-congruence-tests"] => do
      testGeneratedCongruence
      pure 0
  | ["frequency-performance"] => do
      testFrequencyPerformance
      pure 0
  | ["ranking-performance"] => do
      testRankingPerformance
      pure 0
  | ["adaptive-ranking-performance"] => do
      Eggshell.PageDBTests.rankPerformance
      pure 0
  | ["stalled-semantic-provider", ready] => stalledPipePeer (.mk ready)
  | ["controlled-search-provider", root] => controlledSearchProvider (.mk root)
  | ["observed-search-provider", root] => observedSearchProvider (.mk root)
  | ["observed-focus-provider", root] => observedFocusProvider (.mk root)
  | _ => runTests
