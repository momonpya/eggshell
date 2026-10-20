"""Finish checked first-search nominations within the original hook deadline."""
from context_candidate import once

TARGETS = '''
lean_exe ready_delivery_tests where
  root := `tools.ReadyDeliveryTests
'''
HELPERS = ['ReadyDeliveryTests.lean']


def handoff(source):
    source = once(source, '  /-- Queue locators only; observation and indexing belong to the save worker. -/', '''  /-- Scheduling only: complete checked nominations are not a delivered body. -/
  onSemanticReady : IO Unit := pure ()
  /-- Queue locators only; observation and indexing belong to the save worker. -/''')
    source = once(source, 'structure IndexedContext where\n  receipt : Option String := none',
        'structure IndexedContext where\n  receipt : Option String := none\n  onSemanticReady : IO Unit := pure ()')
    source = once(source, '''          let some owners ← source.semantic all command referenceQuery stagedCandidates |
            return some pendingSearch
          if !owners.hasSourcePositions then''', '''          let some owners ← source.semantic all command referenceQuery stagedCandidates |
            return some pendingSearch
          source.onSemanticReady
          if !owners.hasSourcePositions then''')
    # Thread the callback through the existing single/federated entry points.
    for name in ['indexedDiscovery', 'federatedDiscovery', 'computeAutomaticHandoff']:
        start = source.index('def ' + name + ' (')
        end = source.index(' := do', start)
        head = source[start:end]
        head = once(head, '(receipt : Option String := none)',
            '(receipt : Option String := none) (onSemanticReady : IO Unit := pure ())')
        source = source[:start] + head + source[end:]
    for name in ['indexedDiscovery', 'federatedDiscovery']:
        start = source.index('def ' + name + ' (')
        end = source.index('\ndef ', start + 4)
        body = once(source[start:end],
            '  let source : IndexedContext := {\n    receipt\n',
            '  let source : IndexedContext := {\n    receipt, onSemanticReady\n')
        source = source[:start] + body + source[end:]
    source = once(source, 'refreshSources reuseSemantic meaningQuery receipt then return result',
        'refreshSources reuseSemantic meaningQuery receipt onSemanticReady then return result')
    source = once(source, 'refreshSources reuseSemantic meaningQuery receipt\n  catch error',
        'refreshSources reuseSemantic meaningQuery receipt onSemanticReady\n  catch error')
    source = once(source, '    (sourceContext.bind (·.receipt))\n', '''    (sourceContext.bind (·.receipt))
    (sourceContext.map (·.onSemanticReady) |>.getD (pure ()))
''')
    return once(source, 'reuseSemantic meaningQuery (sourceContext.bind (·.receipt))\n', '''reuseSemantic meaningQuery (sourceContext.bind (·.receipt))
      (sourceContext.map (·.onSemanticReady) |>.getD (pure ()))
''')


def worker(source):
    source = once(source, '/-- Execution permission is constructed', '''/-- Every search frame belongs to one native invocation, including its original
deadline. Progress changes scheduling only; it has no Handoff payload. -/
structure SearchIdentity where
  turn : String
  epoch : Nat
  deadline : Nat
  receipt : Option String
  deriving BEq, Repr, ToJson, FromJson

inductive SearchFrame where
  | ready (identity : SearchIdentity)
  | reply (identity : SearchIdentity) (handoff : Option Handoff)
  deriving ToJson, FromJson

structure SearchPolicy where
  identity : SearchIdentity
  finishReady : Bool := false
  onReady : Nat → IO Unit := fun _ => pure ()

def readyDeadline (expected actual : SearchIdentity) (finishReady : Bool)
    (cutoff arrived : Nat) : Nat :=
  min expected.deadline (if finishReady && expected == actual && arrived < cutoff then
    expected.deadline else cutoff)

theorem ready_preserves_upstream (expected actual : SearchIdentity) (finishReady : Bool)
    (cutoff arrived : Nat) :
    readyDeadline expected actual finishReady cutoff arrived ≤ expected.deadline :=
  Nat.min_le_left _ _

theorem unready_preserves_cutoff (expected actual : SearchIdentity) (cutoff arrived : Nat) :
    readyDeadline expected actual false cutoff arrived ≤ cutoff := by
  simpa [readyDeadline] using (Nat.min_le_right expected.deadline cutoff)

theorem late_ready_preserves_cutoff (expected actual : SearchIdentity) (finishReady : Bool)
    (cutoff arrived : Nat) (late : cutoff ≤ arrived) :
    readyDeadline expected actual finishReady cutoff arrived ≤ cutoff := by
  simpa [readyDeadline, Nat.not_lt.mpr late] using (Nat.min_le_right expected.deadline cutoff)

theorem foreign_ready_preserves_cutoff (expected actual : SearchIdentity) (finishReady : Bool)
    (cutoff arrived : Nat) (foreign : (expected == actual) = false) :
    readyDeadline expected actual finishReady cutoff arrived ≤ cutoff := by
  simpa [readyDeadline, foreign] using (Nat.min_le_right expected.deadline cutoff)

/-- One optional ready frame followed by one final reply. Repeated, foreign or
late progress cannot restart or extend the upstream deadline. -/
def readSearchReply (input : IO.FS.Handle) (policy : SearchPolicy)
    (window : Std.Mutex Nat) : IO Json := do
  let readFrame : IO SearchFrame := do
    IO.ofExcept (Json.parse (← input.getLine) >>= fromJson? (α := SearchFrame))
  let frame ← readFrame
  let reply ← match frame with
    | .ready identity => do
        let arrived ← window.atomically do
          let cutoff ← get
          let arrived ← IO.monoMsNow
          unless identity == policy.identity && arrived < cutoff do
            throw (IO.userError "foreign or expired search progress")
          set (readyDeadline policy.identity identity policy.finishReady cutoff arrived)
          pure arrived
        policy.onReady arrived
        readFrame
    | other => pure other
  match reply with
  | .reply identity result =>
      unless identity == policy.identity do throw (IO.userError "foreign search reply")
      unless (← IO.monoMsNow) < (← window.atomically get) do
        throw (IO.userError "expired search reply")
      return toJson result
  | .ready _ => throw (IO.userError "repeated search progress")

partial def awaitSearch (task : Task (Except IO.Error α)) (window : Std.Mutex Nat) : IO (Option α) := do
  if ← IO.hasFinished task then
    match ← IO.wait task with
    | .ok value => return some value
    | .error error => throw error
  if (← IO.monoMsNow) ≥ (← window.atomically get) then return none
  IO.sleep 5
  awaitSearch task window

/-- Execution permission is constructed''')
    source = once(source, 'def exchange (session role : String) (payload : Json) (deadline : Nat) : IO (Option Json) := do',
        '''def exchange (session role : String) (payload : Json) (deadline : Nat)
    (searchPolicy : Option SearchPolicy := none) : IO (Option Json) := do
  let searchPolicy ← if role == "search" then
      match searchPolicy with
      | some policy => pure (some policy)
      | none => do
          let request ← IO.ofExcept (fromJson? payload : Except String Search)
          pure (some {identity := request.identity})
    else pure none
  let deadline := searchPolicy.map (fun policy => min deadline policy.identity.deadline) |>.getD deadline''')
    source = once(source, '    try\n      let task ← IO.asTask (do\n',
        '    try\n      let window ← Std.Mutex.new deadline\n      let task ← IO.asTask (do\n')
    source = once(source, '''        let line ← child.stdout.getLine
        IO.ofExcept (Json.parse line)) .dedicated''', '''        match searchPolicy with
        | some policy => readSearchReply child.stdout policy window
        | none => IO.ofExcept (Json.parse (← child.stdout.getLine))) .dedicated''')
    source = once(source, '        else awaitUntil task deadline', '''        else if searchPolicy.isSome then awaitSearch task window
        else awaitUntil task deadline''')
    source = once(source, 'def search (request : Search) : IO (Option Handoff) := do', '''def Search.identity (request : Search) : SearchIdentity :=
  { turn := request.pending.turnId, epoch := request.state.epoch,
    deadline := request.deadline, receipt := request.receipt }

def search (request : Search) (onSemanticReady : IO Unit := pure ()) : IO (Option Handoff) := do''')
    source = once(source, '          receipt := request.receipt\n',
        '          receipt := request.receipt\n          onSemanticReady\n')
    source = once(source, '        pure (toJson (← search request))', '''        let announced ← IO.mkRef false
        let ready := do
          unless ← announced.get do
            announced.set true
            output.putStrLn (toJson (SearchFrame.ready request.identity)).compress
            output.flush
        pure (toJson (SearchFrame.reply request.identity (← search request ready)))''')
    # The generic exchange also decodes search frames for direct callers.
    start = source.index('structure Search where\n')
    end = source.index('/-- A waiting search', start)
    request = source[start:end]
    source = source[:start] + source[end:]
    start = source.index('def Search.identity (request : Search)')
    end = source.index('def search (request : Search)', start)
    identity = source[start:end]
    source = source[:start] + source[end:]
    source = once(source, '/-- Every search frame belongs', request + '/-- Every search frame belongs')
    return once(source, 'def readyDeadline (', identity + 'def readyDeadline (')


def tests(source):
    source = once(source, '  let query := fun work => Lean.toJson ({ pending, state, work, enforce := false } : Worker.Search)',
        '  let query := fun work deadline => Lean.toJson ({ pending, state, work, enforce := false, deadline } : Worker.Search)')
    for before, after in [
            ('(query leftText)', '(query leftText (started + 1500))'),
            ('(query rightText)', '(query rightText (started + 5000))'),
            ('(query text)', '(query text (started + 5000))'),
            ('(query "queued fifth request")', '(query "queued fifth request" (started + 5000))')]:
        source = once(source, before, after)
    return source


def hooks(source):
    source = once(source, 'def searchIncomplete (reply : Option Json)', '''/-- Once initial nominations are ready, status uses the same overall deadline
as the transport. A later pending result is not a discovery timeout. -/
def configuredSearchDeadline (finishReady ready : Bool) (phaseDeadline deadline : Nat) : Nat :=
  if finishReady && ready then deadline else min phaseDeadline deadline

theorem configured_deadline_preserves_upstream (finishReady ready : Bool)
    (phaseDeadline deadline : Nat) :
    configuredSearchDeadline finishReady ready phaseDeadline deadline ≤ deadline := by
  unfold configuredSearchDeadline
  split
  · exact Nat.le_refl _
  · exact Nat.min_le_right _ _

def searchIncomplete (reply : Option Json)''')
    source = once(source, '  let first ← Worker.exchange session "search" (toJson {query with deadline := firstDeadline}) firstDeadline', '''  let readyAt ← IO.mkRef (none : Option Nat)
  let policy : Worker.SearchPolicy := {
    identity := query.identity
    finishReady := semantic && !initial.searchStarted
    onReady := fun now => do
      if (← readyAt.get).isNone then readyAt.set (some now) }
  let first ← Worker.exchange session "search" (toJson query) firstDeadline (some policy)''')
    source = once(source, '  let observed ← IO.monoMsNow\n  let (result, trace)', '''  let observed ← IO.monoMsNow
  let finishDeadline := configuredSearchDeadline policy.finishReady (← readyAt.get).isSome firstDeadline deadline
  let (result, trace)''')
    source = once(source, 'incompleteSemanticStatus first observed firstDeadline',
        'incompleteSemanticStatus first observed finishDeadline')
    source = once(source, '      let result ← Worker.exchange session "search" (toJson lexical) deadline',
        '      let result ← Worker.exchange session "search" (toJson lexical) deadline\n        (some {identity := lexical.identity})')
    return once(source, '    ("semanticDeadlineMs", toJson firstDeadline), ("searchStartedMs", toJson started),', '''    ("semanticDeadlineMs", toJson firstDeadline), ("searchStartedMs", toJson started),
    ("semanticReadyMs", toJson (← readyAt.get)),
    ("semanticFinishDeadlineMs", toJson finishDeadline),
    ("finishReadyWithinHook", toJson policy.finishReady),''')


def audit(source):
    source = once(source, 'import all Eggshell.GraphStore\n',
        'import all Eggshell.GraphStore\nimport all Eggshell.Worker\n')
    source = once(source, '  for theoremName in #[', '''  for theoremName in #[``Eggshell.Plugin.Worker.ready_preserves_upstream,
      ``Eggshell.Plugin.Worker.unready_preserves_cutoff,
      ``Eggshell.Plugin.Worker.late_ready_preserves_cutoff,
      ``Eggshell.Plugin.Worker.foreign_ready_preserves_cutoff,
      ``Eggshell.Plugin.configured_deadline_preserves_upstream,''')
    return source + '''
run_meta do
  let environment ← getEnv
  for (caller, required) in #[
      (``Eggshell.Plugin.Worker.readSearchReply, ``Eggshell.Plugin.Worker.readyDeadline),
      (``Eggshell.Plugin.Worker.search, ``Eggshell.Plugin.automaticHandoff),
      (``Eggshell.Plugin.indexedDiscoveryUsing, ``Eggshell.Plugin.IndexedContext.onSemanticReady),
      (``Eggshell.Plugin.deliverForWork, ``Eggshell.Plugin.Worker.exchange)] do
    let some declaration := environment.find? caller | throwError "Missing progress caller: {caller}"
    let some body := declaration.value? | throwError "Missing progress body: {caller}"
    unless body.getUsedConstants.contains required do
      throwError "Search progress bypasses its checked boundary: {caller}: {required}"
'''


SOURCES = {'Eggshell/Handoff.lean': handoff, 'Eggshell/Worker.lean': worker,
           'Eggshell/PluginHooks.lean': hooks, 'Eggshell/ContractAudit.lean': audit,
           'TestMain.lean': tests}
