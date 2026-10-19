module

public import Eggshell.Handoff
public import tests.FullSearchOracle
public import Eggshell.PluginCli

@[expose] public section
namespace Eggshell.PageDBTests
open Plugin Persistence DB Lean TestOracle

def require (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

abbrev CandidateSignature := Value × LogicalText.T ×
  List (Value × Bool × LogicalText.T) × Option LogicalText.T × Bool

def candidateSignature (candidate : Matcher.Candidate) : CandidateSignature :=
  (candidate.edge.relation, candidate.work.logical,
    candidate.workPatterns.map (fun p => (p.value, p.whole, p.pattern.logical)),
    candidate.outcome.map (·.logical), candidate.native)

def outcomeCompilation : IO Unit := do
  let normalizer := LogicalText.logicalNormalizer
  let text := "Symbol_A ./src/new.cc 日本語.\n" ++
    String.intercalate "" (List.replicate 2048 "source_anchor λ repeated_result\n")
  let body := Value.text text
  let first := Matcher.Corpus.OutcomeMemo.prepare ({} : Matcher.Corpus.OutcomeMemo.Cache normalizer) body
  let again := Matcher.Corpus.OutcomeMemo.prepare first.cache body
  require (!first.reused && again.reused && again.cache.size == 1)
    "equal original result did not reuse exactly one compilation"
  let changed := Value.text (text ++ "changed source evidence")
  let collision := first.cache.insert (hash changed) ⟨body, first.compiled⟩
  let repaired := Matcher.Corpus.OutcomeMemo.prepare collision changed
  require (!repaired.reused) "foreign body in a forced locator collision was reused"
  require (decide (repaired.compiled.pattern.map (·.logical) =
    (Matcher.Corpus.OutcomeMemo.Compiled.make normalizer changed).pattern.map (·.logical)))
    "changed result compilation differs from the complete source compiler"
  let opaqueBody := Value.atom (.mk #[255, 254])
  let noText := Matcher.Corpus.OutcomeMemo.prepare repaired.cache opaqueBody
  require (noText.compiled.pattern.isNone &&
    noText.cache.size == repaired.cache.size && !noText.reused)
    "cheap opaque result allocated a cache entry or changed its negative compilation"
  let work := Value.text "shell\n{\"command\":\"read source_anchor\"}"
  let native := Value.applyList .occurrence [(.semantic, body), (.semantic, work)]
  let owners := [
    OutcomeEdge.make (.text "ordinary requested Work") body [.text "receipt-A"]
      (by simp) (by simp [maxOutcomeObservations]),
    OutcomeEdge.make work body [native] (by simp) (by simp [maxOutcomeObservations]),
    OutcomeEdge.make (.text "opaque requested Work") opaqueBody [.text "receipt-B"]
      (by simp) (by simp [maxOutcomeObservations]),
    OutcomeEdge.make (Value.applyList .all [(.semantic, .text "parent"),
      (.semantic, .text "child")]) body [.text "receipt-C"]
      (by simp) (by simp [maxOutcomeObservations])]
  let reference := owners.filterMap (Matcher.Corpus.compileCandidate normalizer)
  let (actual, _) := Matcher.Corpus.compileCandidatesUsing normalizer {} owners
  require (actual.map candidateSignature == reference.map candidateSignature)
    "memo compilation changed original owner, native orientation, order, spans or negative Work"
  require (actual.length == 3 && (actual.map (·.native)) == [false, true, false])
    "native/source fixture did not exercise both orientations and nontextual rejection"
  IO.println "PASS actual Outcome compilation reuse: complete compiler equality, native/original owner separation, spans, changed body, forced hash collision, opaque negative and nontextual Work"

def outcomeCompileTiming (mode : String) : IO UInt32 := do
  require (mode == "before" || mode == "current") "expected before/current compile mode"
  let base := String.intercalate "" (List.replicate 32768 "Alpha_beta ./src/new.cc 日本語.\n")
  let mut samples : List Json := []
  for run in [:4] do
    -- Distinct runtime inputs exclude the identical-input pure-sharing error
    -- in an older timing fixture. Force the entire canonical result signature.
    let body := Value.text (base ++ s!" source_tail_{run}")
    let owners := (List.range 8).map fun owner =>
      OutcomeEdge.make (.text s!"investigate source_{owner}") body [.text s!"receipt-{owner}"]
        (by simp) (by simp [maxOutcomeObservations])
    let started ← IO.monoNanosNow
    let compiled := if mode == "before" then
      owners.filterMap (Matcher.Corpus.compileCandidate LogicalText.logicalNormalizer)
      else (Matcher.Corpus.compileCandidatesUsing LogicalText.logicalNormalizer {} owners).1
    let signature := compiled.map candidateSignature
    let fingerprint := hash signature
    require (compiled.length == 8 && fingerprint != 0) "incomplete compilation timing result"
    samples := samples ++ [Json.mkObj [
      ("run", toJson run), ("elapsed_ns", toJson ((← IO.monoNanosNow) - started)),
      ("fingerprint", toJson fingerprint.toNat)]]
  IO.println ((Json.mkObj [("kind", .str "shared_outcome_compilation"), ("mode", .str mode),
    ("owners", toJson (8 : Nat)), ("base_body_bytes", toJson base.utf8ByteSize),
    ("scope", .str "Four distinct fresh texts, complete owner/Work/native/span compilation signature. Request-local compilation phase only; no storage, hook or model-token claim."),
    ("samples", toJson samples)]).compress)
  pure 0

/-- Independent negative-domain oracle for the Work-posting regressions. It
is deliberately test-only; production uses the common discovery controller. -/
def indexedNativeMiss (snapshots : List (Option Store.Snapshot)) (current : String) : IO Bool := do
  let mut all : List AllEdge := []
  let mut persistent : List UnionEdge := []
  for snapshot in snapshots.filterMap id do
    let owner ← Store.authority snapshot
    let some unions ← Store.atomUnions? snapshot owner | return false
    let some topology ← Store.atomTopology? snapshot | return false
    all := all ++ topology
    persistent := persistent ++ unions.map (·.edge)
  let some index := QuotientBuilder.AtomQuotient.prepare persistent | return false
  let some quotient := QuotientBuilder.certify index.partition |
    throw (IO.userError "published atom Union index is invalid")
  let graph : WorkGraph := { all := all.eraseDups }
  if !(graph.decompositionsFor quotient.toEquality (.text current)).isEmpty then return false
  let query := Matcher.compile LogicalText.logicalNormalizer current
  for snapshot in snapshots.filterMap id do
    if !(← Store.workSurfaceCandidates snapshot query.surfaces.toList).isEmpty then return false
  pure true

def pinnedNodeReader : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-node-reader-20261007"
  if ← root.pathExists then IO.FS.removeDirAll root
  let path := root / "shared"
  let first ← PageMap.create path (Persistence.valueToJson (.text "shared-body-reader")).compress
  let body := Value.atom (.mk (Array.replicate (1024 * 1024) (255 : UInt8)))
  let owners := (List.range 8).map fun i =>
    OutcomeEdge.make (.text "load_shared_blob") body [.text s!"exact-receipt-{i}"]
      (by simp) (by simp [maxOutcomeObservations])
  let some firstOwner := owners.head? | throw (IO.userError "shared reader fixture is empty")
  let (ids, _, _) ← PageMap.withWriter first fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← owners.mapM (fun owner => intern.root owner.relation)
    Store.writeChange writer ⟨ids, [], false⟩
    pure ids
  let reference ← PageMap.pin path
  let begin ← IO.monoNanosNow
  let expected ← ids.mapM fun id => do
    Store.readLocatedOutcome reference (← Store.locateOutcome reference id)
  let beforeNs := (← IO.monoNanosNow) - begin
  let beforeBytes ← reference.readBytes.get
  let snapshot ← PageMap.pin path
  let reader ← Store.NodeReader.new snapshot
  let begin ← IO.monoNanosNow
  let actual ← ids.mapM fun id => do
    let located ← Store.locateOutcome snapshot id
    let origin ← reader.workOrigin located
    let owner ← reader.outcome located
    require (origin.work == owner.work && origin.native == Matcher.nativeOutcome owner)
      "shared reader changed original Work/native framing"
    pure owner
  let afterNs := (← IO.monoNanosNow) - begin
  let afterBytes ← snapshot.readBytes.get
  require (actual.map (·.relation) == expected.map (·.relation) &&
      actual.map (·.relation) == owners.map (·.relation))
    "request-local reader changed authoritative Semantic/Exact bytes or owner order"
  require (beforeBytes > 8 * 1024 * 1024 && afterBytes < 2 * 1024 * 1024)
    "eight owners reconstructed or reread the same megabyte Atom"
  let repeatBegin ← snapshot.readBytes.get
  let repeated ← ids.mapM fun id => do reader.outcome (← Store.locateOutcome snapshot id)
  require (repeated.map (·.relation) == actual.map (·.relation) &&
      (← snapshot.readBytes.get) - repeatBegin < 64 * 1024)
    "cached owner bypassed verification or reread its body"
  let oldEntry ← Store.locateOutcome snapshot ids[0]!
  let (_, _, _) ← PageMap.withWriter snapshot fun writer =>
    Store.removeRoot writer ids[0]!
  let changed ← PageMap.pin path
  let changedReader ← Store.NodeReader.new changed
  let mut rejected := false
  try
    let _ ← changedReader.outcome oldEntry
  catch _ => rejected := true
  require rejected "cached nomination crossed a changed publication or survived retraction"
  let retained ← reader.outcome oldEntry
  require (retained.relation == firstOwner.relation)
    "a later commit invalidated a fixed historical read snapshot"
  let peerPath := root / "peer"
  let peerFirst ← PageMap.create peerPath (Persistence.valueToJson (.text "other-source")).compress
  let peerOwner := OutcomeEdge.make (.text "load_shared_blob") (.text "different body")
    [.text "different Exact source"] (by simp) (by simp [maxOutcomeObservations])
  let (peerId, _, _) ← PageMap.withWriter peerFirst fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root peerOwner.relation
    Store.writeChange writer ⟨[id], [], false⟩
    pure id
  require (peerId == ids[0]!) "foreign source fixture did not reuse a local node number"
  let peer ← PageMap.pin peerPath
  let sources := #[snapshot, peer]
  let readers ← Store.NodeReaders.new sources
  let left ← (readers.at ⟨0, by simp [sources]⟩).outcome (← Store.locateOutcome snapshot ids[0]!)
  let right ← (readers.at ⟨1, by simp [sources]⟩).outcome (← Store.locateOutcome peer peerId)
  require (left.relation == firstOwner.relation && right.relation == peerOwner.relation &&
      left.relation != right.relation)
    "source-indexed reader family confused equal local node ids"
  IO.println ((Json.mkObj [("kind", .str "pinned_node_reader"),
    ("owners", toJson owners.length), ("shared_body_bytes", toJson (1024 * 1024 : Nat)),
    ("before_read_bytes", toJson beforeBytes), ("current_read_bytes", toJson afterBytes),
    ("before_elapsed_ns", toJson beforeNs), ("current_elapsed_ns", toJson afterNs)]).compress)
  IO.println "PASS pinned request DAG reader: single Atom restoration across eight owners, original authority/order/native framing, verified replay, source-id isolation, changed-head/retraction rejection and fixed historical snapshot"

def topologyNodeReader : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-topology-node-reader"
  if ← root.pathExists then IO.FS.removeDirAll root
  let first ← PageMap.create root (Persistence.valueToJson (.text "topology-reader")).compress
  let body := Value.atom (.mk (Array.replicate (1024 * 1024) (255 : UInt8)))
  let endpoint := fun tag => Value.applyList .occurrence [.semantic (.text tag), .exact body]
  let atomicParent := Value.text "atomic-prefix"
  let atomic ← if valid : [body] ≠ [] ∧ atomicParent ∉ [body] then
      pure (AllEdge.make atomicParent [body] valid.1 valid.2)
    else throw (IO.userError "invalid Atom preflight fixture")
  let mut topology : List AllEdge := [atomic]
  let mut pairs : List (Value × Value) := []
  let authority ← Store.authority first
  let mut joins : List UnionEdge := []
  for n in [:4] do
    let left := endpoint s!"left-{n}"
    let right := endpoint s!"right-{n}"
    let parent := Value.text s!"parent-{n}"
    let children := [left, right]
    let edge ← if valid : children ≠ [] ∧ parent ∉ children then
        pure (AllEdge.make parent children valid.1 valid.2)
      else throw (IO.userError "invalid shared topology fixture")
    topology := topology ++ [edge]
    pairs := pairs ++ [(left, right)]
    if safe : Value.sameExactFootprint left right then
      joins := joins ++ [(PersistentUnion.make authority left right
        (Value.sameExactFootprint_sound safe)).edge]
    else throw (IO.userError "shared topology Union changed Exact footprint")
  let owners := (List.range 8).map fun n =>
    OutcomeEdge.make (.text "read_shared_topology") body [.text s!"receipt-{n}"]
      (by simp) (by simp [maxOutcomeObservations])
  let (ids, _, _) ← PageMap.withWriter first fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let allIds ← topology.mapM fun edge => intern.root edge.relation
    let ids ← owners.mapM fun edge => intern.root edge.relation
    Store.addUnions intern joins
    Store.writeChange writer ⟨allIds ++ ids, [], true⟩
    pure ids
  let probe ← PageMap.pin root
  let probeReader ← Store.NodeReader.new probe
  require ((← probeReader.atomTopology?).isNone && (← probe.readBytes.get) < 128 * 1024)
    "rejected Atom-only probe restored an earlier giant Atom before inspecting later headers"
  let reference ← PageMap.pin root
  let started ← IO.monoNanosNow
  let expectedAll ← Store.topology reference
  -- The predecessor used a new table for every Union endpoint and a
  -- separate shared table for selected owners.
  let expectedPairs ← (← Store.unionPairs reference).mapM fun (left, right) => do
    pure (← Store.readNode reference reference.get left, ← Store.readNode reference reference.get right)
  let oldOwners ← Store.NodeReader.new reference
  let expectedOwners ← ids.mapM fun id => do oldOwners.outcome (← Store.locateOutcome reference id)
  let beforeNs := (← IO.monoNanosNow) - started
  let beforeBytes ← reference.readBytes.get
  let snapshot ← PageMap.pin root
  let reader ← Store.NodeReader.new snapshot
  let started ← IO.monoNanosNow
  let actualAll ← reader.topology
  let actualUnions ← reader.unions authority
  let actualOwners ← ids.mapM fun id => do reader.outcome (← Store.locateOutcome snapshot id)
  let afterNs := (← IO.monoNanosNow) - started
  let afterBytes ← snapshot.readBytes.get
  require (expectedAll.map (·.relation) == topology.map (·.relation) &&
      actualAll.map (·.relation) == expectedAll.map (·.relation) &&
      actualUnions.map (fun edge => (edge.edge.left, edge.edge.right)) == expectedPairs &&
      expectedPairs == pairs && actualOwners.map (·.relation) == expectedOwners.map (·.relation))
    "shared All/Union/Outcome reader changed original Semantic/Exact values or order"
  require (beforeBytes > 9 * 1024 * 1024 && afterBytes < 2 * 1024 * 1024)
    "All/Union/Outcome repeatedly reconstructed the same megabyte payload"
  let repeatBegin ← snapshot.readBytes.get
  let _ ← reader.topology
  let _ ← reader.unions authority
  let _ ← ids.mapM fun id => do reader.outcome (← Store.locateOutcome snapshot id)
  require ((← snapshot.readBytes.get) - repeatBegin < 128 * 1024)
    "repeated topology resolution bypassed the pinned node table"
  let source ← PageMap.pin root
  let catalogue ← Store.Federated.prepare #[source]
  let beginOwners ← source.readBytes.get
  for id in ids do
    let original ← (catalogue.readers.at ⟨0, by simp⟩).outcome (← Store.locateOutcome source id)
    require (owners.any (fun owner => owner.relation == original.relation))
      "federated catalogue reader changed an original Outcome"
  require ((← source.readBytes.get) - beginOwners < 64 * 1024)
    "federated selected owners allocated a second topology reader family"
  IO.println ((Json.mkObj [("kind", .str "topology_node_reader"),
    ("shared_body_bytes", toJson (1024 * 1024 : Nat)), ("all_edges", toJson topology.length),
    ("unions", toJson joins.length), ("owners", toJson owners.length),
    ("before_read_bytes", toJson beforeBytes), ("current_read_bytes", toJson afterBytes),
    ("before_elapsed_ns", toJson beforeNs), ("current_elapsed_ns", toJson afterNs)]).compress)
  IO.println "PASS common pinned All/Union/Outcome reader: header-only rejected probe, original values/order/Exact authority, one shared body, verified repeat and federated reader-family reuse"

def indexedSelection : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-indexed-selection-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let left := root / "left"
  let right := root / "right"
  let small := Value.text "selected alpha_parser evidence"
  let result := Value.text "alpha_parser verified local result"
  let exact := Value.text "original Exact source observation"
  let alpha := OutcomeEdge.make small result [exact] (by simp) (by simp [maxOutcomeObservations])
  let beta := OutcomeEdge.make small (.text "different retained result") [exact] (by simp)
    (by simp [maxOutcomeObservations])
  let archiveBody := Value.atom (.mk (Array.replicate (2 * 1024 * 1024) (255 : UInt8)))
  let archives := (List.range 8).map fun i => (OutcomeEdge.make
    (.text s!"unrelated_archive_{i}") archiveBody [] (by simp) (by simp)).relation
  let receipt := Value.applyList .receipt
    ((List.range 7).map fun i => Ref.exact (.text s!"position-{i}"))
  let values := archives ++ [alpha.relation, beta.relation, receipt]
  for (path, values) in [(left, values), (right, [alpha.relation, receipt])] do
    let graph ← if wellFormed : values.all Relation.wellFormed then
      pure ({Graph.empty (.text path.toString) with
        values := values
        values_wellFormed := fun value member => (List.all_eq_true.mp wellFormed) value member} : Graph)
      else throw (IO.userError "invalid selected source fixture")
    Persistence.saveAtomic path graph
  let first ← PageMap.pin left
  let second ← PageMap.pin right
  let sources := [some first, some second]
  let composite ← pinnedComposite sources
  let selected := [small, result, exact, receipt, .text "position-3", alpha.relation]
  let selection : Config.Selection := {
    label := "indexed-selection", read := [⟨"left", left⟩, ⟨"right", right⟩]
    write := none, semanticMatcher := none, handoffChars := 24000 }
  let before ← runtimeCache.get
  let mut largestBytes := 0
  let mut longestNs := 0
  try
    runtimeCache.set {}
    for value in selected do
      let snapshots := [some (← PageMap.pin left), some (← PageMap.pin right)]
      let expected ← IO.ofExcept (resolveKey composite (valueKey value))
      let started ← IO.monoNanosNow
      let actual ← resolveSelectionAt snapshots (valueKey value)
      longestNs := max longestNs ((← IO.monoNanosNow) - started)
      require (actual == expected) "indexed selection changed complete structural or Exact content"
      let bytes ← snapshots.filterMap id |>.mapM (·.readBytes.get)
      let bytes := bytes.foldl (· + ·) 0
      largestBytes := max largestBytes bytes
      require (bytes < 128 * 1024) "small manual selection restored an unrelated 2MiB Outcome"
    let keys := selected.map valueKey
    let expectedRoots ← keys.mapM fun key => IO.ofExcept (resolveKey composite key)
    let handoff ← manualHandoff selection "unresolved current inquiry" keys
    require ((toJson handoff).compress ==
        (toJson (manualHandoffForRoots selection "unresolved current inquiry" expectedRoots)).compress &&
        (← runtimeCache.get).composites.isEmpty && (← runtimeCache.get).workspaces.isEmpty)
      "manual handoff changed its order, authority, budget or opened the full workspace cache"
    let verifyMembership := fun (snapshot : Store.Snapshot) => do
      let graph ← Store.materialize snapshot
      let nodes := hashDistinct (graph.values.flatMap Value.nodes)
      let semantic := hashDistinct (graph.values.flatMap Value.semanticNodes)
      require ((← Store.getNat snapshot.get "semanticPopulation") == semantic.length)
        "Exact-only selection nodes enlarged the semantic discovery domain"
      for node in nodes do
        let some id ← Store.findNode? snapshot node | throw (IO.userError "live selection node disappeared")
        let membership ← Store.NodeMembership.read snapshot.get id
        require (membership.total == graph.values.countP (fun root => root.nodes.contains node) &&
          membership.semantic == graph.values.countP (fun root => root.semanticNodes.contains node))
          "persisted reach counters differ from full current root membership"
    verifyMembership first
    let some (_, alphaId) ← Store.liveRoot? first alpha.relation |
      throw (IO.userError "selected owner disappeared")
    let some (_, betaId) ← Store.liveRoot? first beta.relation |
      throw (IO.userError "shared selected owner disappeared")
    for (retiring, remains) in [(alphaId, true), (betaId, false)] do
      let snapshot ← PageMap.pin left
      let _ ← PageMap.withWriter snapshot fun writer => do
        Store.removeRoot writer retiring
        Store.writeChange writer ⟨[], [retiring], false⟩
      let current ← PageMap.pin left
      verifyMembership current
      let found ← try let _ ← resolveSelectionAt [some current] (valueKey small); pure true catch _ => pure false
      require (found == remains) "retraction retained dead selection authority or lost a shared node"
      require ((← resolveSelectionAt [some first] (valueKey result)) == result)
        "a newer retraction changed an old selected snapshot"
    let fresh ← PageMap.pin left
    let _ ← PageMap.withWriter fresh fun writer => do
      let id ← (Store.Intern.mk writer (← IO.mkRef {})).root alpha.relation
      Store.writeChange writer ⟨[id], [], false⟩
    verifyMembership (← PageMap.pin left)
    let snapshot ← PageMap.pin left
    let some archive := archives.head? | throw (IO.userError "empty archive fixture")
    let some (_, archiveId) ← Store.liveRoot? snapshot archive |
      throw (IO.userError "unrelated archive disappeared")
    let header ← Store.readOutcomeHeader snapshot archiveId
    let _ ← PageMap.withWriter snapshot fun writer => do
      writer.put (Store.key (Store.key "body" header.outcome) 0) none
      Store.writeChange writer ⟨[], [], true⟩
    let damaged ← PageMap.pin left
    require ((← resolveSelectionAt [some damaged] (valueKey small)) == small)
      "selection touched an unrelated missing body"
    let edge ← Plugin.persistUnion left small result
    let joined ← PageMap.pin left
    require ((← Store.locateUnion? joined (Plugin.unionKey edge)).isSome)
      "direct indexed Union mutation did not persist its exact endpoints"
    let _ ← Plugin.persistUnion left result small
    require ((← PageMap.pin left).head == joined.head)
      "reversed duplicate Union appended another publication"
    let _ ← Plugin.persistUnion left small small
    require ((← PageMap.pin left).head == joined.head)
      "self Union allocated or published data"
    let some (_, liveId) ← Store.liveRoot? joined alpha.relation |
      throw (IO.userError "readded selection owner disappeared")
    let reached ← Store.RootReach.read joined joined.get liveId
    let _ ← PageMap.withWriter joined fun writer => do
      Store.putChunks writer "rootReach" liveId
        (Store.RootReach.codec.encode (reached.rows ++ reached.rows)).toByteArray
      Store.writeChange writer ⟨[], [], true⟩
    let corrupt ← PageMap.pin left
    let rejected ← try
      let _ ← PageMap.withWriter corrupt fun writer => Store.removeRoot writer liveId
      pure false
      catch _ => pure true
    require (rejected && (← PageMap.pin left).head == corrupt.head)
      "duplicate reverse reach decremented twice or published a partial retraction"
    let other := Value.text "different selected data"
    let _ ← PageMap.withWriter corrupt fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let otherId ← intern.root other
      let some smallId ← Store.findNode? corrupt small | throw (IO.userError "selected small node disappeared")
      let digest := (hash small).toNat
      Store.putNat writer (Store.key "nodeHash" otherId) digest
      Store.putIds writer ("hash:" ++ toString digest) [smallId, otherId]
      Store.writeChange writer ⟨[otherId], [], false⟩
    let collision ← PageMap.pin left
    let rejected ← try let _ ← resolveSelectionAt [some collision] (valueKey small); pure false catch _ => pure true
    require rejected "display collision silently chose a different live Value"
    for key in ["v01", "1", "v", "v999999999999999999999999999999999"] do
      let rejected ← try let _ ← resolveSelectionAt [some second] key; pure false catch _ => pure true
      require rejected "invalid or foreign selection key acquired evidence"
  finally runtimeCache.set before
  IO.println ((Json.mkObj [("kind", .str "indexed_manual_selection"),
    ("selected_comparisons", toJson selected.length), ("max_ns", toJson longestNs),
    ("max_read_bytes", toJson largestBytes), ("generative_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS indexed pinned manual selection, full oracle, Exact/shared reach, retraction/readd, collision/corruption rejection and graph-free idempotent Union writes"

def rows : IO Unit := do
  let root := (← PageMap.absolute ".lake/page-db-focused-20261005")
  if ← root.pathExists then IO.FS.removeDirAll root
  let before ← PageMap.create root "fixture"
  let payload := (String.ofList (List.replicate 64 'a')).toUTF8
  let (_, head, initialBytes) ← PageMap.withWriter before fun writer => do
    for i in [:3000] do writer.put s!"key-{10000 + i}" (some payload)
  let first ← PageMap.pin root
  require (first.head == head) "published root differs from disk"
  for i in [:3000] do require ((← first.get s!"key-{10000 + i}") == some payload) "bulk index lost a row"
  let pulling ← first.forkReader
  let emptyCache ← pulling.cache.get
  let controllerCache ← first.cache.get
  require (pulling.head == first.head && emptyCache.recent.size == 0 &&
    emptyCache.previous.size == 0 && controllerCache.recent.size > 0)
    "source pull reused the controller's mutable page cache or changed its publication"
  let beforePull ← first.reads.get
  let task ← IO.asTask (pulling.get "key-12999") .dedicated
  let pulled ← IO.ofExcept (← IO.wait task)
  require (pulled == some payload && (← first.reads.get) > beforePull)
    "isolated source pull lost original bytes or its shared read accounting"
  let ranged ← PageMap.pin root
  let interval : PageMap.KeyRange := ⟨"key-11495", "key-11505"⟩
  let found ← ranged.foldRange interval (fun rows row => pure (row :: rows)) []
  require (found.reverse.map Prod.fst == (List.range 10).map (fun n => s!"key-{11495 + n}"))
    "range read lost, duplicated or reordered boundary rows"
  let rangePages ← ranged.reads.get
  require (rangePages < 10) "a narrow range enumerated the bulk index"
  for interval in [PageMap.KeyRange.mk "key-10000" "key-10001",
      ⟨"key-12999", "key-13000"⟩, ⟨"key-11500", "key-11500"⟩,
      ⟨"key-13000", "key-15000"⟩, ⟨"aaa", "aab"⟩] do
    let actual ← ranged.foldRange interval (fun rows row => pure (row :: rows)) []
    let expected := (List.range 3000).map (fun n => (s!"key-{10000 + n}", some payload))
    require (actual.reverse == interval.select expected)
      "range traversal differs from the full row oracle"
  let large := (String.ofList (List.replicate 4096 'b')).toUTF8
  let (_, changed, changedBytes) ← PageMap.withWriter first fun writer => do
    writer.put "key-10017" none
    writer.put "key-12998" (some large)
    writer.put "key-14000" (some payload)
  let second ← PageMap.pin root
  require ((← second.get "key-10017").isNone) "deleted row reappeared"
  require ((← second.get "key-12998") == some large) "replacement row was lost"
  require ((← second.get "key-14000") == some payload) "new row was lost"
  require ((← first.get "key-10017") == some payload &&
    (← first.get "key-12998") == some payload && (← first.get "key-14000").isNone)
    "pinned read snapshot mixed a newer publication"
  require ((← pulling.get "key-10017") == some payload &&
    (← pulling.get "key-12998") == some payload && (← pulling.get "key-14000").isNone)
    "isolated source pull mixed a newer publication"
  let allRange : PageMap.KeyRange := ⟨"key-10000", "key-15000"⟩
  let oldRows ← first.foldRange allRange (fun rows row =>
    pure (if row.2.isSome then row :: rows else rows)) []
  let newRows ← second.foldRange allRange (fun rows row =>
    pure (if row.2.isSome then row :: rows else rows)) []
  require (oldRows.length == 3000 && newRows.length == 3000 &&
    oldRows.any (fun row => row.1 == "key-10017") &&
    !newRows.any (fun row => row.1 == "key-10017") &&
    newRows.any (fun row => row == ("key-12998", some large)))
    "range traversal mixed publications or resurrected a tombstone"
  -- This edits two distant leaves; it is not the single-4KiB-update gate.
  require (changedBytes < initialBytes) "mixed update copied the entire DB"
  let (_, same, repeatedBytes) ← PageMap.withWriter second fun writer => do
    writer.put "key-10017" none
    writer.put "key-12998" (some large)
    writer.put "key-14000" (some payload)
  require (same == changed && repeatedBytes == 0) "duplicate batch republished or appended pages"
  let (_, single, singleBytes) ← PageMap.withWriter second fun writer =>
    writer.put "key-10015" (some large)
  IO.println ((Json.mkObj [("kind", .str "single_update_gate"),
    ("initial_page_bytes", toJson initialBytes), ("mixed_page_bytes", toJson changedBytes),
    ("single_page_bytes", toJson singleBytes)]).compress)
  require (singleBytes < initialBytes / 4) "single 4KiB update copied most of the DB"
  let second ← PageMap.pin root
  let failed ← try
      let _ : Unit × PageMap.Head × Nat ← PageMap.withWriter second fun writer => do
        writer.put "key-failed" (some large)
        writer.flush
        throw (IO.userError "injected failure after page append, before head publication")
      pure false
    catch _ => pure true
  require failed "fault injection did not stop publication"
  let recovery ← PageMap.pin root
  require (recovery.head == single && (← recovery.get "key-failed").isNone)
    "unacknowledged append became visible"
  let (_, recovered, _) ← PageMap.withWriter recovery fun writer => writer.put "key-recovered" (some payload)
  let recoveredSnapshot ← PageMap.pin root
  require (recoveredSnapshot.head == recovered &&
    (← recoveredSnapshot.get "key-recovered") == some payload &&
    (← recoveredSnapshot.get "key-failed").isNone)
    "tail recovery lost committed data or exposed abandoned data"
  let some checkedRoot := recoveredSnapshot.head.root | throw (IO.userError "missing published root")
  recoveredSnapshot.cache.set {}
  let observed ← recoveredSnapshot.getAt checkedRoot "key-recovered"
  require (observed.visits ≤ checkedRoot.height + 1) "point lookup exceeded tree height"
  let damaged := { recoveredSnapshot with
    head := { recoveredSnapshot.head with
      root := some { checkedRoot with first := "zzzz-corrupt-fence", last := "zzzz-corrupt-fence" } } }
  let rejected ← try
      let _ ← damaged.get "key-recovered"
      pure false
    catch _ => pure true
  require rejected "a corrupt fence was accepted as a completed empty lookup"
  let rejected ← try
      let _ ← damaged.foldRange (PageMap.KeyRange.mk "aaa" "aab")
        (fun (count : Nat) _ => pure (count + 1)) 0
      pure false
    catch _ => pure true
  require rejected "a corrupt fence was accepted as a completed empty range"
  let damagedHead := { recoveredSnapshot.head with root := none }
  FileSystem.atomicBytes (root / "head") (toJson damagedHead).compress.toUTF8
  let rejected ← try
      let _ ← PageMap.pin root
      pure false
    catch _ => pure true
  FileSystem.atomicBytes (root / "head") (toJson recoveredSnapshot.head).compress.toUTF8
  require rejected "a nonempty DB with its root removed was accepted as empty"
  IO.println ((Json.mkObj [("kind", .str "page_map"), ("bulk_rows", toJson (3000 : Nat)),
    ("initial_page_bytes", toJson initialBytes), ("changed_page_bytes", toJson changedBytes),
    ("repeat_page_bytes", toJson repeatedBytes), ("height", toJson checkedRoot.height),
    ("point_page_visits", toJson observed.visits), ("narrow_range_pages", toJson rangePages)]).compress)
  IO.println "PASS page DB bulk split, point/range reads, correction/deletion, old snapshot, no-op and abandoned-tail recovery"

def directories : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-directories-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let first ← PageMap.create root "directory-fixture"
  let (_, _, _) ← PageMap.withWriter first fun writer => do
    -- A high historical ordinal is deliberately sparse. A range reader must
    -- not perform a billion missing point probes before returning live roots.
    Store.putNat writer "roots" 1000000000
    for ordinal in [:1024] do
      Store.putNat writer (Store.key "root" ordinal) (ordinal * 17 + 3)
      Store.putNat writer (Store.key (Store.key "posting" 7) ordinal) (ordinal * 17 + 3)
      Store.putNat writer (Store.key (Store.key "posting" 70) ordinal) 999999
    for ordinal in [1, 10, 997] do
      writer.put (Store.key "root" ordinal) none
      writer.put (Store.key (Store.key "posting" 7) ordinal) none
    Store.putNat writer (Store.key "root" 400000000) 888888
    for name in ["unicode:é", "unicode:日本", "unicode:🙂"] do
      writer.put name (some name.toUTF8)
  let snapshot ← PageMap.pin root
  let started ← IO.monoNanosNow
  let actual ← Store.rootIds snapshot
  let elapsed := (← IO.monoNanosNow) - started
  let expected := ((List.range 1024).filter fun n => ![1, 10, 997].contains n).map
    (fun n => n * 17 + 3) ++ [888888]
  require (actual == expected) "sparse root directory changed numeric order or membership"
  let rootPages ← snapshot.reads.get
  let postings ← Store.directory snapshot (Store.key "posting" 7)
  require (postings.map Prod.snd == expected.dropLast)
    "posting range crossed a neighbouring term id or retained deleted owners"
  let unicode ← snapshot.foldRange (PageMap.KeyRange.mk "unicode:" "unicode;")
    (fun rows row => pure (row :: rows)) []
  require (unicode.reverse.map Prod.fst == ["unicode:é", "unicode:日本", "unicode:🙂"])
    "UTF-8 range boundaries disagree with index ordering"
  let (_, _, _) ← PageMap.withWriter snapshot fun writer =>
    Store.putNat writer (Store.key "root" 1000000000) 123
  let invalid ← PageMap.pin root
  let rejected ← try let _ ← Store.rootIds invalid; pure false catch _ => pure true
  require rejected "an out-of-population root was accepted as authoritative"
  require ((← Store.rootIds snapshot) == expected) "an old directory read mixed a newer root"
  IO.println ((Json.mkObj [("kind", .str "sparse_root_range"),
    ("historical_ordinals", toJson (1000000000 : Nat)), ("live_roots", toJson actual.length),
    ("directory_pages", toJson rootPages), ("elapsed_ns", toJson elapsed)]).compress)
  IO.println "PASS sparse numeric root/posting ranges, term isolation, UTF-8, pinned snapshot and invalid population rejection"

def frames : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-frames-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let initial ← PageMap.create root "frame-fixture"
  let work := Value.text "read the captured evidence"
  let result := Value.atom (String.ofList (List.replicate (1024 * 1024) 'x')).toUTF8
  let observation := Value.applyList .occurrence
    [(.semantic, result), (.semantic, work), (.exact, .text "tool-result-1")]
  let owner := OutcomeEdge.make work result [observation] (by simp)
    (by simp [maxOutcomeObservations])
  let turnObservation := Value.applyList .occurrence
    [(.semantic, work), (.semantic, result), (.exact, .text "turn-result-1")]
  let turnOwner := OutcomeEdge.make work result [turnObservation] (by simp)
    (by simp [maxOutcomeObservations])
  let ((ownerId, turnId), _, _) ← PageMap.withWriter initial fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ownerId ← intern.root owner.relation
    let turnId ← intern.root turnOwner.relation
    pure (ownerId, turnId)
  let snapshot ← PageMap.pin root
  let start ← IO.monoNanosNow
  let located ← Store.locateOutcome snapshot ownerId
  let header := located.header
  let metadataNs := (← IO.monoNanosNow) - start
  let metadataBytes ← snapshot.readBytes.get
  require (header.observations.length == 1 && header.work < ownerId && header.outcome < ownerId)
    "Outcome header lost positional references or the dependency bound"
  require (metadataBytes < 16384) "a shallow owner lookup read its megabyte body"
  let origin ← Store.readLocatedWorkOrigin snapshot located
  let originBytes ← snapshot.readBytes.get
  require (origin.work == work && origin.native && originBytes < 32768)
    "native Work classification read its megabyte result or lost occurrence orientation"
  let turnOrigin ← Store.readLocatedWorkOrigin snapshot (← Store.locateOutcome snapshot turnId)
  require (turnOrigin.work == work && !turnOrigin.native && (← snapshot.readBytes.get) < 49152)
    "a turn-oriented observation was classified as a native operation or read the result"
  require ((← Store.readNode snapshot snapshot.get header.work) == work &&
    (← Store.readLocatedOutcome snapshot located).relation == owner.relation)
    "typed frames changed hydrated graph values"
  -- A query can nominate an owner without fetching its result. Make that
  -- distinction observable: damage just the result descriptor, then metadata
  -- and Work reads must succeed while evidence hydration must reject it.
  let bodyName := Store.key (Store.key "body" header.outcome) 0
  let some encoded ← snapshot.get bodyName | throw (IO.userError "missing body descriptor")
  let blob ← IO.ofExcept (PageMap.decodeBlob encoded)
  let (_, _, _) ← PageMap.withWriter snapshot fun writer => do
    writer.put bodyName (some (PageMap.blobCodec.encode
      { blob with checksum := blob.checksum ++ "0" }).toByteArray)
  let damaged ← PageMap.pin root
  let stale ← try let _ ← Store.readLocatedOutcome damaged located; pure false catch _ => pure true
  require stale "an old Outcome nomination acquired authority at another publication"
  let staleOrigin ← try let _ ← Store.readLocatedWorkOrigin damaged located; pure false catch _ => pure true
  require staleOrigin "an old Work origin acquired a new publication's classification"
  let current ← Store.readOutcomeHeader damaged ownerId
  require (current.work == header.work && current.outcome == header.outcome &&
    current.observations == header.observations)
    "a shallow frame read depended on unrelated result bytes"
  require ((← Store.readNode damaged damaged.get current.work) == work)
    "a selected Work read hydrated its owner's result"
  let damagedOrigin ← Store.readLocatedWorkOrigin damaged (← Store.locateOutcome damaged ownerId)
  require (damagedOrigin.work == work && damagedOrigin.native &&
      (← damaged.readBytes.get) < 32768)
    "native Work classification consulted a corrupt unrelated result descriptor"
  let rejected ← try let _ ← Store.readNode damaged damaged.get ownerId; pure false catch _ => pure true
  require rejected "a damaged result became reusable evidence"
  require ((← Store.readNode snapshot snapshot.get ownerId) == owner.relation)
    "an old body snapshot mixed a newer descriptor"
  let (emptyId, _, _) ← PageMap.withWriter damaged fun writer => do
    -- Restore the descriptor, then remove only the byte count. It must never
    -- silently replace a captured megabyte with an empty result.
    writer.put bodyName (some encoded)
    writer.put (Store.key "body" header.outcome) none
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    intern.value (.atom ByteArray.empty)
  let absent ← PageMap.pin root
  let rejected ← try let _ ← Store.readNode absent absent.get header.outcome; pure false catch _ => pure true
  require rejected "missing body metadata was accepted as an empty result"
  require ((← Store.readNode absent absent.get emptyId) == .atom ByteArray.empty)
    "a canonically stored empty Atom was rejected"
  let (_, _, _) ← PageMap.withWriter absent fun writer =>
    Store.putNat writer (Store.key "body" header.outcome) (1024 * 1024)
  let wrong : Store.NodeFrame := .apply .outcome
    [(.semantic, header.work), (.semantic, header.outcome), (.semantic, header.observations.head!)]
  let some checked := wrong.check ownerId | throw (IO.userError "invalid positional test frame")
  require (Store.OutcomeHeader.fromFrame? checked |>.isNone)
    "a substitutable reference was accepted as Exact provenance"
  for authority in [Authority.semantic, Authority.exact] do
    let frame : Store.NodeFrame := .apply .occurrence [(authority, ownerId)]
    require ((frame.check ownerId).isNone) "a self reference acquired a dependency certificate"
    let currentSnapshot ← PageMap.pin root
    let (_, _, _) ← PageMap.withWriter currentSnapshot fun writer => do
      Store.putChunks writer "node" ownerId frame.toJson.compress.toUTF8
    let invalid ← PageMap.pin root
    let rejected ← try let _ ← Store.readFrame invalid invalid.get ownerId; pure false catch _ => pure true
    require rejected "the production reader followed an unbounded reference"
    -- Restore the good frame at the current head before the next injection.
    let (_, _, _) ← PageMap.withWriter invalid fun writer =>
      Store.putFrame writer ownerId header.checked
  let restored ← PageMap.pin root
  let live ← Store.locateOutcome restored ownerId
  let otherRoot ← PageMap.absolute ".lake/page-db-frames-foreign-20261006"
  if ← otherRoot.pathExists then IO.FS.removeDirAll otherRoot
  let foreign ← PageMap.create otherRoot "another-frame-fixture"
  let rejected ← try let _ ← Store.readLocatedOutcome foreign live; pure false catch _ => pure true
  require rejected "a foreign DB accepted another source's numeric owner id"
  let rejected ← try let _ ← Store.readLocatedWorkOrigin foreign live; pure false catch _ => pure true
  require rejected "a foreign DB accepted another source's Work classification"
  let ordinal ← Store.getNat restored.get (Store.key "outcomeOrdinal" ownerId)
  let (_, _, _) ← PageMap.withWriter restored fun writer =>
    Store.putNat writer (Store.key "outcome" ordinal) header.work
  let wrongDirectory ← PageMap.pin root
  let rejected ← try let _ ← Store.locateOutcome wrongDirectory ownerId; pure false catch _ => pure true
  require rejected "a mismatched live directory nominated an Outcome"
  let (_, _, _) ← PageMap.withWriter wrongDirectory fun writer => do
    Store.putNat writer (Store.key "outcome" ordinal) ownerId
    Store.removeRoot writer ownerId
    Store.writeChange writer ⟨[], [ownerId], false⟩
  let retired ← PageMap.pin root
  let rejected ← try let _ ← Store.locateOutcome retired ownerId; pure false catch _ => pure true
  require rejected "immutable bytes revived a deleted Outcome owner"
  require ((← Store.readLocatedOutcome restored live).relation == owner.relation &&
    (← Store.readNode retired retired.get ownerId) == owner.relation)
    "retraction destroyed old snapshot evidence instead of its live membership"
  IO.println ((Json.mkObj [("kind", .str "shallow_frame"),
    ("body_bytes", toJson (1024 * 1024 : Nat)), ("frame_read_bytes", toJson metadataBytes),
    ("work_origin_read_bytes", toJson originBytes),
    ("frame_read_ns", toJson metadataNs)]).compress)
  IO.println "PASS typed frames, pinned live Outcome lookup, foreign/stale/deleted/mismatched directory rejection, Exact positions, corrupt/missing bodies, valid empty Atoms and acyclic resolution"

def terms : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-terms-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let initial ← PageMap.create root "term-dictionary-fixture"
  let long := String.ofList (List.replicate 10000 'x')
  let ((shortId, longId, otherId), _, _) ← PageMap.withWriter initial fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let shortId ← intern.term "alpha"
    let longId ← intern.term long
    require ((← intern.term "alpha") == shortId && (← intern.term long) == longId)
      "repeated dictionary terms allocated another id"
    -- Force a wrong nomination: equality must reject it even if the locator
    -- bucket contains a valid id belonging to a different word.
    Store.putIds writer (Store.termBucket "different") [shortId]
    let otherId ← intern.term "different"
    require (otherId != shortId) "a hash bucket nomination replaced full spelling identity"
    require ((← writer.get "nodes").isNone) "terms allocated graph nodes"
    pure (shortId, longId, otherId)
  let snapshot ← PageMap.pin root
  for (text, id) in [("alpha", shortId), (long, longId), ("different", otherId)] do
    let some found ← Store.findTerm? snapshot snapshot.get text |
      throw (IO.userError "published dictionary lost a term")
    require (found.id == id && found.spelling == text) "term changed after publication"
  let (_, unchanged, bytes) ← PageMap.withWriter snapshot fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let _ ← intern.term "alpha"
    let _ ← intern.term long
  require (unchanged == snapshot.head && bytes == 0) "repeated term publication appended metadata"
  IO.println "PASS dense term dictionary, chunked long term, collision rejection and zero-append replay"

/-- A real pinned source with a serialized native-only false positive. Its
large textual result must not be normalized for a failed Work comparison.
The same owner must remain usable on a new demand or semantic nomination. -/
def workFirst : IO Unit := do
  let path ← PageMap.absolute ".lake/page-db-work-first-20261006"
  if ← path.pathExists then IO.FS.removeDirAll path
  let initial ← PageMap.create path (Persistence.valueToJson (.text "work-first-fixture")).compress
  let work := Value.text "shell\n{\"command\":\"read zircon_detector\"}"
  let result := Value.text ((String.intercalate "\n"
    (List.replicate 2048 "payload_unrelated_value")) ++ "\nzircon_detector confirmed")
  let observation := Value.applyList .occurrence
    [Ref.semantic result, Ref.semantic work, Ref.exact (.text "native-work-first")]
  let owner := OutcomeEdge.make work result [observation] (by simp)
    (by simp [maxOutcomeObservations])
  let ordinary := OutcomeEdge.make (.text "investigate command")
    (.text "command ordinary evidence") [] (by simp) (by simp)
  let topology ← if valid : [work, ordinary.work] ≠ [] ∧
      (.text "work-first parent") ∉ [work, ordinary.work] then
      pure (AllEdge.make (.text "work-first parent") [work, ordinary.work] valid.1 valid.2)
    else throw (IO.userError "invalid work-first topology")
  let (ids, _, _) ← PageMap.withWriter initial fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← [owner.relation, ordinary.relation, topology.relation].mapM intern.root
    Store.writeChange writer ⟨ids, [], false⟩
    pure ids
  let some ownerId := ids.head? | throw (IO.userError "missing work-first owner")
  let snapshot ← PageMap.pin path
  let owners := [owner, ordinary]
  let graph : WorkGraph := {all := [topology], outcomes := owners}
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer graph
  let some preview := Matcher.Corpus.compileWorkCandidate LogicalText.logicalNormalizer owner |
    throw (IO.userError "native owner lost textual Work")
  let query := Matcher.CompiledDemand.make LogicalText.logicalNormalizer "command" false
  require (Matcher.sharesSurface query.pattern preview.work && preview.native &&
      (preview.workAlignments Matcher.pairedCoverages Quotient.literal corpus (.text "command")
        query.pattern query.workPatterns {} false).isEmpty)
    "fixture failed to nominate a real native serialization false positive"
  let ordinal := fun id => do
    Store.payloadSize (← snapshot.get (Store.key "member" id)) |> IO.ofExcept
  let alias := ownerId + 1000000000
  let resolve := fun id => if id == alias then ownerId else id
  let semanticEnabled ← IO.mkRef false
  let frequencyQueries ← IO.mkRef ([] : List String)
  let ownerReads ← IO.mkRef ([] : List Nat)
  let source : IndexedContext := {
    all := [topology], persistent := [], outcomeCount := 2, population := 2
    semanticPopulation := ← Store.getNat snapshot.get "semanticPopulation"
    live := fun value => (·.isSome) <$> Store.liveRoot? snapshot value
    semanticPresent := fun value => do
      match ← Store.findNode? snapshot value with
      | some id => pure (decide ((← Store.getNat snapshot.get (Store.key "semanticUses" id)) > 0))
      | none => pure false
    semantic := fun _ _ _ _ => do
      let enabled ← semanticEnabled.get
      pure (some {durable := if enabled then [alias, ownerId] else []})
    lexical := fun _ _ => pure {}
    ordinal := fun id => ordinal (resolve id)
    readWork := fun id => do
      Store.readLocatedWorkOrigin snapshot (← Store.locateOutcome snapshot (resolve id))
    readOwner := fun id => do
      ownerReads.modify (· ++ [resolve id])
      Store.readLocatedOutcome snapshot (← Store.locateOutcome snapshot (resolve id))
    surfaces := Store.workSurfaceCandidates snapshot
    frequencies := fun units => do
      frequencyQueries.modify (· ++ units)
      Store.frequencies snapshot units
    liveOwner := fun value => (·.map Prod.snd) <$> Store.liveRoot? snapshot value }
  let selection : Config.Selection := {
    label := "work-first", read := [⟨"work", path⟩],
    write := none, semanticMatcher := none, handoffChars := 24000 }
  let mut comparisons := 0
  let mut samples : List Json := []
  for text in ["command", "zircon_detector", "shell\n{\"command\":\"read zircon_detector\"}",
      "payload_unrelated_value", "fresh_new_gap"] do
    for semantic in [false, true] do
      semanticEnabled.set semantic
      for native in [false, true] do
        for localUnion in [false, true] do
          frequencyQueries.set []
          ownerReads.set []
          let selected := {selection with semanticMatcher := if semantic then some ["test-nominations"] else none}
          let start ← IO.monoNanosNow
          let actual ← indexedDiscoveryUsing source selected text [] native none localUnion
          let elapsed := (← IO.monoNanosNow) - start
          let nominations : Matcher.SemanticNominations := {
            related := if semantic && !native then [owner.relation] else [] }
          let full := Matcher.discoverIn? LogicalText.logicalNormalizer (.text text)
            [owner.relation, ordinary.relation, topology.relation] [] graph corpus text
            none nominations localUnion native
          let expected := full.bind (renderAutomatic [] 24000 text [] native true)
          require ((toJson actual).compress == (toJson expected).compress)
            s!"Work-first complete handoff differs: {text} semantic={semantic} native={native} union={localUnion}"
          if text == "command" && !semantic then
            require (!((← ownerReads.get).contains ownerId))
              "failed native Work comparison hydrated the large Outcome body"
            require (!((← frequencyQueries.get).contains "payload_unrelated_value"))
              "failed native Work comparison evaluated the large Outcome scoring domain"
          if text == "zircon_detector" || (text == "command" && semantic && !native) then
            require ((← ownerReads.get).contains ownerId)
              "a new demand or semantic nomination failed to read its original owner"
            require (!((← frequencyQueries.get).contains "payload_unrelated_value"))
              "hydrating a result demanded unrelated result words for forward context weights"
          comparisons := comparisons + 1
          samples := samples ++ [Json.mkObj [("query", toJson text), ("semantic", toJson semantic),
            ("native", toJson native), ("local_union", toJson localUnion), ("elapsed_ns", toJson elapsed),
            ("frequency_terms_requested", toJson (hashDistinct (← frequencyQueries.get)).length),
            ("large_owner_hydrated", toJson ((← ownerReads.get).contains ownerId))]]
  -- Evidence-present grounding retains the full reverse query domain.
  -- Normal forward grounding above must not ask for these result-only words.
  for text in ["zircon_detector", "command", "payload_unrelated_value"] do
    for evidence in ["payload_unrelated_value", "zircon_detector confirmed"] do
      frequencyQueries.set []
      ownerReads.set []
      let actual ← indexedDiscoveryUsing source selection text [] false (some evidence) true
      let full := Matcher.discoverIn? LogicalText.logicalNormalizer (.text text)
        [owner.relation, ordinary.relation, topology.relation] [] graph corpus text
        (some evidence) {} true true
      let expected := full.bind (renderAutomatic [] 24000 text [] false true)
      require ((toJson actual).compress == (toJson expected).compress)
        "demand-scoped reverse context changed the complete original handoff"
      if (← ownerReads.get).contains ownerId then
        require ((← frequencyQueries.get).contains "payload_unrelated_value")
          "evidence-present reverse context lost a result query weight"
      comparisons := comparisons + 1
  -- The same persisted head is used after failed demands. No negative owner
  -- cache may suppress a later match or canonicalized semantic duplicate.
  require (snapshot.head == (← PageMap.pin path).head)
    "Work preflight changed the authoritative graph"
  -- Damage only the rejected owner's body. Complete production discovery
  -- must still yield the original small-owner answer; a later positive
  -- demand must fail closed rather than inventing an empty result.
  let located ← Store.locateOutcome snapshot ownerId
  let bodyName := Store.key (Store.key "body" located.header.outcome) 0
  let some encoded ← snapshot.get bodyName | throw (IO.userError "missing large Outcome descriptor")
  let descriptor ← IO.ofExcept (PageMap.decodeBlob encoded)
  let (_, _, _) ← PageMap.withWriter snapshot fun writer => do
    writer.put bodyName (some (PageMap.blobCodec.encode
      {descriptor with checksum := descriptor.checksum ++ "0"}).toByteArray)
  let damaged ← PageMap.pin path
  runtimeCache.set {}
  let actual ← computeAutomaticHandoff selection [some damaged] "command" [] false
  let full := Matcher.discoverIn? LogicalText.logicalNormalizer (.text "command")
    [owner.relation, ordinary.relation, topology.relation] [] graph corpus "command" none {} true false
  let expected := full.bind (renderAutomatic [] 24000 "command" [] false true)
  require ((toJson actual).compress == (toJson expected).compress)
    "complete handoff depended on an unrelated corrupt Outcome body"
  runtimeCache.set {}
  let needed ← computeAutomaticHandoff selection [some damaged] "zircon_detector" [] false
  require ((toJson needed).compress == (toJson (some pendingSearch)).compress)
    "a demanded corrupt Outcome body was accepted as reusable evidence"
  let (_, _, _) ← PageMap.withWriter damaged fun writer => writer.put bodyName (some encoded)
  let restored ← PageMap.pin path
  runtimeCache.set {}
  let resumed ← computeAutomaticHandoff selection [some restored] "zircon_detector" [] false
  let full := Matcher.discoverIn? LogicalText.logicalNormalizer (.text "zircon_detector")
    [owner.relation, ordinary.relation, topology.relation] [] graph corpus "zircon_detector" none {} true false
  let expected := full.bind (renderAutomatic [] 24000 "zircon_detector" [] false true)
  require ((toJson resumed).compress == (toJson expected).compress &&
      (toJson resumed).compress != (toJson (some pendingSearch)).compress)
    "restoring original evidence did not recover the production handoff"
  IO.println ((Json.mkObj [("kind", .str "work_first"), ("result_bytes", toJson result.structuralSize),
    ("complete_handoffs", toJson comparisons), ("samples", toJson samples),
    ("generative_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS shallow Work-first complete handoff: rejected Outcome not read, unrelated corrupt body ignored, demanded corruption rejected and restored, later positive demand, semantic/ordinal duplicates, original grounding, local Union and full statistics"

/-- Exercise the production child-role factory with structured congruence,
an unrelated large descendant, source changes and a fresh per-pass cache.
The reference deliberately restores the complete topology independently. -/
def quotientChildRole : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-quotient-child-role"
  if ← root.pathExists then IO.FS.removeDirAll root
  try
    let path := root / "source"
    let first ← PageMap.create path (Persistence.valueToJson (.text "child-role-source")).compress
    let authority ← Store.authority first
    let unary := fun name scope => Value.applyList .occurrence
      [Ref.semantic (.text name), Ref.exact (.text scope)]
    let outer := fun value => Value.applyList .occurrence [Ref.semantic value]
    let alpha := unary "alpha_work" "./src/original.c"
    let beta := unary "beta_work" "./src/original.c"
    let changedScope := unary "beta_work" "./src/another.c"
    let actualChild := outer alpha
    let aliasChild := outer beta
    let exactForeign := outer changedScope
    let direct := Value.text "literal_child"
    let absent := Value.text "absent_child"
    let huge := OutcomeEdge.make (.text "foreign_work")
      (.atom (.mk (Array.replicate (3 * 1024 * 1024) (255 : UInt8)))) [] (by simp) (by simp)
    let makeAll := fun parent children =>
      if nonempty : children ≠ [] then
        if excluded : parent ∉ children then pure (AllEdge.make parent children nonempty excluded)
        else throw (IO.userError "child-role parent appears as its own child")
      else throw (IO.userError "empty child-role fixture")
    let unrelated ← makeAll (.text "foreign_parent") [huge.relation]
    let related ← makeAll (.text "requested_parent") [actualChild, direct]
    let (ids, _, _) ← PageMap.withWriter first fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let ids ← [unrelated.relation, related.relation].mapM intern.root
      Store.writeChange writer ⟨ids, [], false⟩
      pure ids
    let union ← if safe : Value.sameExactFootprint alpha beta then
        pure (PersistentUnion.make authority alpha beta (Value.sameExactFootprint_sound safe)).edge
      else throw (IO.userError "structured child-role Union changes Exact authority")
    let _ ← PageMap.withWriter (← PageMap.pin path) fun writer => do
      Store.addUnions ⟨writer, ← IO.mkRef {}⟩ [union]
      Store.writeChange writer ⟨[], [], true⟩
    let snapshot ← PageMap.pin path
    let graph : WorkGraph := {all := [unrelated, related], outcomes := []}
    let roots := [unrelated.relation, related.relation, aliasChild, exactForeign, absent]
    let some view := RunView.make? graph roots [union] [] |
      throw (IO.userError "structured child-role quotient is invalid")
    let index := Quotient.AliasIndex.prepare view.quotient
    require ((index.aliases aliasChild).contains actualChild &&
      !(index.aliases exactForeign).contains actualChild &&
      index.aliases absent == [absent])
      "inverse quotient lost congruence, crossed Exact authority or lost literal fallback"
    let measured ← PageMap.pin path
    let demand ← Store.DemandTopology.new (← Store.NodeReader.new measured)
    let start ← IO.monoNanosNow
    let lookup ← demand.childLookup view
    let cases := [actualChild, aliasChild, exactForeign, direct, absent, alpha,
      .text "requested_parent", .text "foreign_parent"]
    let mut samples : List Json := []
    for work in cases do
      let expected := graph.subworks.any (view.quotient.toEquality.same work)
      let before ← measured.readBytes.get
      let actual ← lookup work
      let after ← measured.readBytes.get
      require (actual == expected) "indexed child role differs from the original complete quotient"
      require ((← lookup work) == actual && (← measured.readBytes.get) == after)
        "a stable per-pass child lookup repeated its source reads"
      samples := samples ++ [Json.mkObj [("work", Persistence.valueToJson work),
        ("child", toJson actual), ("read_bytes", toJson (after - before))]]
    let elapsed := (← IO.monoNanosNow) - start
    let readBytes ← measured.readBytes.get
    require (readBytes < 192 * 1024 && elapsed < 3000000000)
      "structured child authority restored an unrelated body or missed its deadline"
    let reference ← PageMap.pin path
    let full ← (← Store.NodeReader.new reference).topology
    for work in cases do
      require ((← lookup work) == ({all := full, outcomes := []} : WorkGraph).subworks.any
        (view.quotient.toEquality.same work))
        "indexed child role differs from the independently decoded whole topology"
    require ((← reference.readBytes.get) > 3 * 1024 * 1024)
      "large unrelated child was absent from the full-read negative control"
    -- Retiring equality must create a new quotient and a new negative cache.
    let some located ← Store.locateUnion? snapshot (Store.unionDisplayKey alpha beta) |
      throw (IO.userError "child-role fixture lost its Union")
    let _ ← PageMap.withWriter snapshot fun writer => do
      Store.removeUnion writer located
      Store.writeChange writer ⟨[], [], true⟩
    let retiredUnion ← PageMap.pin path
    let some literalView := RunView.make? graph roots [] [] |
      throw (IO.userError "literal child-role view failed")
    let freshLookup ← (← Store.DemandTopology.new (← Store.NodeReader.new retiredUnion)).childLookup literalView
    require (!(← freshLookup aliasChild) && (← freshLookup actualChild) && (← lookup aliasChild))
      "Union retraction reused a prior positive or changed the old pinned pass"
    -- A new equality must not keep a previous negative answer either.
    let _ ← PageMap.withWriter retiredUnion fun writer => do
      Store.addUnions ⟨writer, ← IO.mkRef {}⟩ [union]
      Store.writeChange writer ⟨[], [], true⟩
    let restoredUnion ← PageMap.pin path
    let restoredLookup ← (← Store.DemandTopology.new (← Store.NodeReader.new restoredUnion)).childLookup view
    require ((← restoredLookup aliasChild) && !(← freshLookup aliasChild))
      "new equality retained an earlier negative child role"
    let _ ← PageMap.withWriter restoredUnion fun writer => do
      Store.removeRoot writer ids[1]!
      Store.writeChange writer ⟨[], [ids[1]!], false⟩
    let retiredAll ← PageMap.pin path
    let retiredLookup ← (← Store.DemandTopology.new (← Store.NodeReader.new retiredAll)).childLookup view
    require (!(← retiredLookup aliasChild) && !(← retiredLookup direct) &&
      (← restoredLookup aliasChild))
      "All retraction resurrected a retired child or mutated a pinned publication"
    let corrected ← makeAll related.parent [exactForeign]
    let _ ← PageMap.withWriter retiredAll fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let id ← intern.root corrected.relation
      Store.writeChange writer ⟨[id], [], false⟩
    let correctedSnapshot ← PageMap.pin path
    let correctedLookup ← (← Store.DemandTopology.new (← Store.NodeReader.new correctedSnapshot)).childLookup view
    require ((← correctedLookup exactForeign) && !(← correctedLookup aliasChild) &&
      !(← retiredLookup exactForeign))
      "All correction retained the previous child or lost the new original child"
    let _ ← PageMap.withWriter correctedSnapshot fun writer =>
      writer.put "indexedAllReferences" none
    let incomplete ← PageMap.pin path
    let badLookup ← (← Store.DemandTopology.new (← Store.NodeReader.new incomplete)).childLookup view
    let rejected ← try
        let _ ← badLookup absent
        pure false
      catch _ => pure true
    require rejected "incomplete saved child index became a completed negative answer"
    IO.println ((Json.mkObj [("read_bytes", toJson readBytes), ("elapsed_ns", toJson elapsed),
      ("reference_read_bytes", toJson (← reference.readBytes.get)), ("cases", toJson samples)]).compress)
    IO.println "PASS certified inverse quotient child lookup: original structured congruence, literal/negative/Exact cases, 3 MiB unrelated body skipped, pinned Union/All retraction/correction, incomplete-index rejection and per-pass memo reset"
  finally
    if ← root.pathExists then IO.FS.removeDirAll root

def allParentIndex : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-all-parent-index-20261007"
  if ← root.pathExists then IO.FS.removeDirAll root
  let path := root / "source"
  let first ← PageMap.create path (Persistence.valueToJson (.text "all-parent-index")).compress
  let body := Value.atom (.mk (Array.replicate (3 * 1024 * 1024) (255 : UInt8)))
  let foreign := OutcomeEdge.make (.text "foreign_work") body [] (by simp) (by simp)
  let parent := Value.text "foreign_parent"
  let all ← if valid : parent ∉ [foreign.relation] then
      pure (AllEdge.make parent [foreign.relation] (by simp) valid)
    else throw (IO.userError "invalid foreign parent fixture")
  let child := OutcomeEdge.make (.text "child_work") (.text "child_work observed") []
    (by simp) (by simp)
  let history := OutcomeEdge.make (.text "independent_work") (.text "independent_work observed") []
    (by simp) (by simp)
  let parentWork := Value.text "parent_request"
  let requestedAll ← if valid : parentWork ∉ [child.work] then
      pure (AllEdge.make parentWork [child.work] (by simp) valid)
    else throw (IO.userError "invalid requested parent fixture")
  let (ids, _, _) ← PageMap.withWriter first fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← [all.relation, foreign.relation, requestedAll.relation, child.relation,
      history.relation].mapM intern.root
    Store.writeChange writer ⟨ids, [], false⟩
    pure ids
  let snapshot ← PageMap.pin path
  require ((← Store.literalAllParents snapshot parentWork) == [ids[2]!] &&
      (← Store.literalAllParents snapshot parent) == [ids[0]!] &&
      (← Store.literalAllParents snapshot child.work).isEmpty)
    "All parent lookup lost its order or confused a child with a parent"
  require ((← Store.literalAllChildren snapshot child.work) == [ids[2]!] &&
      (← Store.literalAllChildren snapshot history.work).isEmpty &&
      (← Store.literalAllChildren snapshot foreign.relation) == [ids[0]!])
    "All child lookup confused structural reachability with actual child position"
  let before := snapshot.head
  let _ ← PageMap.withWriter snapshot fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let _ ← intern.root requestedAll.relation
    pure ()
  let unchanged ← PageMap.pin path
  require (unchanged.head == before && (← Store.getNat unchanged.get "indexedAllReferences") == 2)
    "replayed All root duplicated its parent posting or allocation"
  let selected : Config.Selection := {
    label := "all-parent", semanticMatcher := none, read := [⟨"source", path⟩]
    write := none, handoffChars := 24000 }
  let mut samples : List Json := []
  for trial in [:3] do
    runtimeCache.set {}
    let measured ← PageMap.pin path
    let start ← IO.monoNanosNow
    let result ← computeAutomaticHandoff selected [some measured] "absent_unique_request" [] true
    let elapsed := (← IO.monoNanosNow) - start
    let bytes ← measured.readBytes.get
    require (result.isNone && bytes < 128 * 1024 && elapsed < 3000000000)
      "negative demand restored an unrelated All child body or missed its deadline"
    runtimeCache.set {}
    let reference ← PageMap.pin path
    let expected ← computeGeneralAutomaticHandoff selected [some reference] "absent_unique_request" [] true
    require ((toJson result).compress == (toJson expected).compress &&
        (← reference.readBytes.get) > 3 * 1024 * 1024)
      "sparse negative All lookup changed the full handoff or bypassed its body oracle"
    samples := samples ++ [Json.mkObj [("trial", toJson trial), ("read_bytes", toJson bytes),
      ("elapsed_ns", toJson elapsed), ("reference_read_bytes", toJson (← reference.readBytes.get))]]
  let mut positive : List Json := []
  for text in ["child_work", "independent_work"] do
    for trial in [:3] do
      runtimeCache.set {}
      let measured ← PageMap.pin path
      let start ← IO.monoNanosNow
      let result ← computeAutomaticHandoff selected [some measured] text [] true
      let elapsed := (← IO.monoNanosNow) - start
      let bytes ← measured.readBytes.get
      require (result.isSome && bytes < 128 * 1024 && elapsed < 3000000000)
        "positive terminal demand restored unrelated All children or lost selected evidence"
      runtimeCache.set {}
      let reference ← PageMap.pin path
      let expected ← computeGeneralAutomaticHandoff selected [some reference] text [] true
      require ((toJson result).compress == (toJson expected).compress &&
          (← reference.readBytes.get) > 3 * 1024 * 1024)
        "sparse positive All incidence changed completion authority or the full handoff"
      positive := positive ++ [Json.mkObj [("trial", toJson trial), ("query", toJson text),
        ("read_bytes", toJson bytes), ("elapsed_ns", toJson elapsed),
        ("reference_read_bytes", toJson (← reference.readBytes.get))]]
  require ((← Store.workSurfaceCandidates snapshot
      (LogicalText.surfaceNames "parent_request")).isEmpty)
    "parent fixture unexpectedly had a direct Work admission"
  let routed ← indexedTerminalRoot selected [some (← PageMap.pin path)] "parent_request" [] true none true
  require (routed.isNone) "literal parent was incorrectly accepted as a completed empty demand"
  runtimeCache.set {}
  let actual ← computeAutomaticHandoff selected [some (← PageMap.pin path)] "parent_request" [] true
  runtimeCache.set {}
  let expected ← computeGeneralAutomaticHandoff selected [some (← PageMap.pin path)] "parent_request" [] true
  require ((toJson actual).compress == (toJson expected).compress && actual.isSome)
    "parent index dropped a demanded child or changed the complete handoff"
  let ((), _, _) ← PageMap.withWriter (← PageMap.pin path) fun writer => do
    Store.removeRoot writer ids[2]!
    Store.writeChange writer ⟨[], [ids[2]!], false⟩
  let retired ← PageMap.pin path
  require ((← Store.literalAllParents retired parentWork).isEmpty &&
      (← Store.literalAllParents snapshot parentWork) == [ids[2]!] &&
      (← Store.literalAllChildren retired child.work).isEmpty &&
      (← Store.literalAllChildren snapshot child.work) == [ids[2]!])
    "All parent retirement mixed publications or retained a stale parent"
  runtimeCache.set {}
  let actual ← computeAutomaticHandoff selected [some retired] "child_work" [] true
  runtimeCache.set {}
  let expected ← computeGeneralAutomaticHandoff selected [some (← PageMap.pin path)] "child_work" [] true
  require ((toJson actual).compress == (toJson expected).compress)
    "retiring the last All child retained stale completion authority"
  let _ ← PageMap.withWriter retired fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root requestedAll.relation
    Store.writeChange writer ⟨[id], [], false⟩
  let restored ← PageMap.pin path
  require ((← Store.literalAllParents restored parentWork) == [ids[2]!] &&
      (← Store.literalAllChildren restored child.work) == [ids[2]!] &&
      (← Store.getNat restored.get "indexedAllReferences") == (← Store.getNat restored.get "alls"))
    "readded All lost its stable parent or complete allocation accounting"
  let aliasWork := Value.text "alias_request"
  let union : UnionEdge := ⟨aliasWork, parentWork, .workspace (← Store.authority restored), by
    simp [Value.SameExactFootprint, aliasWork, parentWork, Value.text, Value.exactFootprint]⟩
  let _ ← PageMap.withWriter restored fun writer => do
    Store.addUnions ⟨writer, ← IO.mkRef {}⟩ [union]
    Store.writeChange writer ⟨[], [], true⟩
  let joined ← PageMap.pin path
  require ((← Store.literalAllParents joined aliasWork).isEmpty &&
      (← Store.workSurfaceCandidates joined (LogicalText.surfaceNames "alias_request")).isEmpty)
    "Union fixture unexpectedly used a direct lexical or literal parent nomination"
  require ((← indexedTerminalRoot selected [some joined] "alias_request" [] true none true).isNone)
    "explicit Union was ignored by the negative parent gate"
  runtimeCache.set {}
  let actual ← computeAutomaticHandoff selected [some (← PageMap.pin path)] "alias_request" [] true
  runtimeCache.set {}
  let expected ← computeGeneralAutomaticHandoff selected [some (← PageMap.pin path)] "alias_request" [] true
  require ((toJson actual).compress == (toJson expected).compress && actual.isSome)
    "Union-exposed parent lost a child or changed the complete handoff"
  -- A parent-only producer cannot impersonate the new complete reference
  -- producer. Unsupported prior indexing fails explicitly, without a
  -- compatibility reader or an invented negative child membership.
  let _ ← PageMap.withWriter joined fun writer => do
    Store.putNat writer "indexedAllParents" (← Store.getNat writer.get "alls")
    writer.put "indexedAllReferences" none
  let damaged ← PageMap.pin path
  let rejected ← try
      let _ ← Store.literalAllParents damaged (.text "absent_unique_request")
      pure false
    catch _ => pure true
  require rejected "incomplete All parent index was reported as a completed miss"
  let rejectedChild ← try
      let _ ← Store.literalAllChildren damaged child.work
      pure false
    catch _ => pure true
  require rejectedChild "incomplete All child index was reported as absent completion authority"
  IO.println ((Json.mkObj [("kind", .str "sparse_all_parent_negative"),
    ("generative_calls", toJson (0 : Nat)), ("samples", toJson samples),
    ("positive", toJson positive)]).compress)
  IO.println "PASS save-time All incidence, graph-free negative/positive native handoff, completion authority, child exposure, idempotence, pinned retirement/readd and incomplete-index rejection"

def demandTopology : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-demand-topology-20261007"
  if ← root.pathExists then IO.FS.removeDirAll root
  let path := root / "source"
  let first ← PageMap.create path (Persistence.valueToJson (.text "demand-topology")).compress
  let huge := OutcomeEdge.make (.text "foreign_work")
    (.atom (.mk (Array.replicate (3 * 1024 * 1024) (255 : UInt8)))) [] (by simp) (by simp)
  let makeAll := fun (parent : Value) (children : List Value) => do
    if nonempty : children ≠ [] then
      if apart : parent ∉ children then pure (AllEdge.make parent children nonempty apart)
      else throw (IO.userError "invalid demand test parent")
    else throw (IO.userError "empty demand test children")
  let foreign ← makeAll (.text "foreign_parent") [huge.relation]
  let outer ← makeAll (.text "outer_request") [.text "middle_work", .text "leaf_two"]
  let inner ← makeAll (.text "middle_work") [.text "leaf_one"]
  let side ← makeAll (.text "unrelated_parent") [.text "standalone_work"]
  let outcomes := ["leaf_one", "leaf_two", "standalone_work"].map fun work =>
    OutcomeEdge.make (.text work) (.text (work ++ " observed")) [] (by simp) (by simp)
  let (ids, _, _) ← PageMap.withWriter first fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← ([foreign.relation, outer.relation, inner.relation, side.relation,
      huge.relation] ++ outcomes.map (·.relation)).mapM intern.root
    Store.writeChange writer ⟨ids, [], false⟩
    pure ids
  let snapshot ← PageMap.pin path
  let reader ← Store.NodeReader.new snapshot
  let demand ← Store.DemandTopology.new reader
  require ((← demand.read [] [.text "outer_request"]) == [outer, inner])
    "demand closure lost nested All edges or reordered alternatives"
  require ((← demand.read [] [.text "missing_alias"]).isEmpty)
    "negative demand unexpectedly acquired a parent"
  let surrounding ← Store.DemandTopology.new (← Store.NodeReader.new (← PageMap.pin path))
  require ((← surrounding.neighborhood [] [.text "leaf_two"]) == [outer, inner])
    "a child entry lost the sibling's nested original All relation"
  let alias : UnionEdge := ⟨.text "missing_alias", .text "outer_request",
    .workspace (← Store.authority snapshot), by
      simp [Value.SameExactFootprint, Value.text, Value.exactFootprint]⟩
  require ((← demand.read [alias] [.text "missing_alias"]) == [outer, inner])
    "new Union did not expose a parent after a cached negative query"
  require ((← surrounding.neighborhood [alias, alias.swap] [.text "missing_alias"]) == [outer, inner] &&
      (← surrounding.neighborhood [] [.text "absent_source"]).isEmpty &&
      (← surrounding.neighborhood [] [.text "standalone_work"]) == [side])
    "source-neighborhood traversal lost a Union chain, repeated a cycle or joined a disconnected All"
  let selected : Config.Selection := {
    label := "demand", semanticMatcher := none
    read := [⟨"source", path⟩], write := none, handoffChars := 24000 }
  let mut samples : List Json := []
  for query in ["outer_request", "middle_work", "standalone_work", "leaf_one extra"] do
    runtimeCache.set {}
    let measured ← PageMap.pin path
    let start ← IO.monoNanosNow
    let actual ← computeAutomaticHandoff selected [some measured] query [] true
    let elapsed := (← IO.monoNanosNow) - start
    let bytes ← measured.readBytes.get
    runtimeCache.set {}
    let reference ← PageMap.pin path
    let expected ← computeGeneralAutomaticHandoff selected [some reference] query [] true
    require ((toJson actual).compress == (toJson expected).compress && actual.isSome)
      s!"demand topology changed full handoff for {query}"
    require (bytes < 128 * 1024 && elapsed < 3000000000 &&
        (← reference.readBytes.get) > 3 * 1024 * 1024)
      s!"demand topology restored unrelated body or exceeded deadline for {query}"
    samples := samples ++ [Json.mkObj [("query", toJson query), ("read_bytes", toJson bytes),
      ("elapsed_ns", toJson elapsed), ("reference_read_bytes", toJson (← reference.readBytes.get))]]
  -- A compaction/pending-turn request must use the same sparse saved closure.
  -- The unrelated structured All contains a 3MiB source body, so silently
  -- switching to the full topology is observable even when output is equal.
  let stagedOwner := OutcomeEdge.make (.text "fresh_local_work")
    (.text "fresh local evidence arrived before persistence") [] (by simp) (by simp)
  let stagedAll ← makeAll (.text "staged_outer") [.text "outer_request", stagedOwner.work]
  let some existingOwner := outcomes.head? | throw (IO.userError "empty saved demand fixture")
  let stagedInputs := [[stagedOwner.relation], [existingOwner.relation],
    [stagedAll.relation, stagedOwner.relation], [stagedOwner.relation, stagedOwner.relation]]
  let mut stagedSamples : List Json := []
  for staged in stagedInputs do
    for query in ["outer_request", "staged_outer", "fresh_local_work", "standalone_work"] do
      for native in [false, true] do
        for visible in [false, true] do
          for localUnion in [false, true] do
            runtimeCache.set {}
            let measured ← PageMap.pin path
            let start ← IO.monoNanosNow
            let actual ← computeAutomaticHandoff selected [some measured] query [] native
              none staged visible localUnion
            let elapsed := (← IO.monoNanosNow) - start
            let bytes ← measured.readBytes.get
            runtimeCache.set {}
            let reference ← PageMap.pin path
            let expected ← computeGeneralAutomaticHandoff selected [some reference] query [] native
              none staged visible localUnion
            if (toJson actual).compress != (toJson expected).compress then
              IO.FS.writeFile (root / "staged-demand-mismatch.json")
                (Json.mkObj [("query", toJson query), ("staged", toJson (staged.map Persistence.valueToJson)),
                  ("native", toJson native), ("visible", toJson visible),
                  ("local_union", toJson localUnion), ("actual", toJson actual),
                  ("reference", toJson expected)]).pretty
            require ((toJson actual).compress == (toJson expected).compress)
              s!"pending-turn sparse discovery changed full handoff: {query}, native={native}, visible={visible}, union={localUnion}"
            require (bytes < 192 * 1024 && elapsed < 3000000000 &&
                (← reference.readBytes.get) > 3 * 1024 * 1024)
              s!"pending-turn discovery hydrated unrelated All/source body: {query}"
            stagedSamples := stagedSamples ++ [Json.mkObj [("query", toJson query),
              ("staged_roots", toJson staged.length), ("native", toJson native),
              ("visible", toJson visible), ("local_union", toJson localUnion),
              ("read_bytes", toJson bytes), ("elapsed_ns", toJson elapsed),
              ("reference_read_bytes", toJson (← reference.readBytes.get))]]
  let application := fun work => Value.applyList .occurrence [Ref.semantic work]
  let structuredUnion : UnionEdge := ⟨application (.text "opaque_union_a"),
    application (.text "opaque_union_b"), .workspace (← Store.authority snapshot), by intro _; rfl⟩
  let correctedUnion : UnionEdge := ⟨structuredUnion.left, application (.text "opaque_union_c"),
    structuredUnion.scope, by intro _; rfl⟩
  let _ ← PageMap.withWriter snapshot fun writer => do
    Store.addUnions ⟨writer, ← IO.mkRef {}⟩ [alias, structuredUnion]
    Store.writeChange writer ⟨[], [], true⟩
  let executable ← IO.appPath
  let command := [executable.toString, "independent-search-provider", "--mode", "lexical",
    "--cache", (root / "vectors").toString, "--model-cache", (root / "unused-models").toString]
  let mut homogeneousSamples : List Json := []
  -- An unrelated application Union used to force restoration of the 3MiB
  -- structured All descendant even for a simple Atom Work. Exercise the
  -- actual search, then replace/retract that Union with old snapshots pinned.
  for revision in [:3] do
    if revision > 0 then
      let latest ← PageMap.pin path
      let old := if revision == 1 then structuredUnion else correctedUnion
      let some located ← Store.locateUnion? latest (Store.unionDisplayKey old.left old.right) |
        throw (IO.userError "homogeneous Union disappeared before correction/retraction")
      let _ ← PageMap.withWriter latest fun writer => do
        Store.removeUnion writer located
        if revision == 1 then Store.addUnions ⟨writer, ← IO.mkRef {}⟩ [correctedUnion]
        Store.writeChange writer ⟨[], [], true⟩
      pure ()
    for query in ["missing_alias", "middle_work", "standalone_work", "leaf_one extra"] do
      for native in [false, true] do
        for semantic in [false, true] do
          let configured := {selected with semanticMatcher := if semantic then some command else none}
          runtimeCache.set {}
          let measured ← PageMap.pin path
          let start ← IO.monoNanosNow
          let actual ← computeAutomaticHandoff configured [some measured] query [] native
          let elapsed := (← IO.monoNanosNow) - start
          let bytes ← measured.readBytes.get
          runtimeCache.set {}
          let reference ← PageMap.pin path
          let expected ← computeGeneralAutomaticHandoff configured [some reference] query [] native
          require ((toJson actual).compress == (toJson expected).compress && actual.isSome)
            s!"constructor-preserving Union changed complete handoff: revision={revision} query={query} native={native} semantic={semantic}"
          require (bytes < 192 * 1024 && elapsed < 3000000000 &&
              (← reference.readBytes.get) > 3 * 1024 * 1024)
            s!"application Union restored unrelated source body: revision={revision} query={query}"
          homogeneousSamples := homogeneousSamples ++ [Json.mkObj [
            ("revision", toJson revision), ("query", toJson query), ("native", toJson native),
            ("semantic", toJson semantic), ("read_bytes", toJson bytes),
            ("elapsed_ns", toJson elapsed), ("reference_read_bytes", toJson (← reference.readBytes.get))]]
  runtimeCache.set {}
  let joined ← PageMap.pin path
  let actual ← computeAutomaticHandoff selected [some joined] "missing_alias" [] true
  runtimeCache.set {}
  let expected ← computeGeneralAutomaticHandoff selected [some (← PageMap.pin path)] "missing_alias" [] true
  require ((toJson actual).compress == (toJson expected).compress && actual.isSome &&
      (← joined.readBytes.get) < 128 * 1024)
    "Union-exposed nested demand changed the full handoff or hydrated unrelated body"
  let _ ← PageMap.withWriter joined fun writer => do
    Store.removeRoot writer ids[2]!
    Store.writeChange writer ⟨[], [ids[2]!], false⟩
  let retired ← PageMap.pin path
  let current ← Store.DemandTopology.new (← Store.NodeReader.new retired)
  require ((← current.read [] [.text "outer_request"]) == [outer] &&
      (← demand.read [] [.text "outer_request"]) == [outer, inner])
    "retirement mixed snapshots or restored a stale decomposition"
  let before ← PageMap.pin path
  let demanded ← Store.DemandTopology.new (← Store.NodeReader.new before)
  let full ← demanded.read [] [.text "foreign_parent"]
  require (full.contains foreign && (← before.readBytes.get) > 3 * 1024 * 1024)
    "structured demanded child was silently pruned instead of using the general kernel"
  IO.println ((Json.mkObj [("kind", .str "demand_topology"),
    ("generative_calls", toJson (0 : Nat)), ("samples", toJson samples),
    ("staged_samples", toJson stagedSamples), ("homogeneous_samples", toJson homogeneousSamples)]).compress)
  IO.println "PASS demand-driven All closure including pending turns, nested decomposition, global child authority, new Union after negative lookup, continuation, original order and pinned retirement"

def workSurfaceConflicts : IO Unit := do
  let path ← PageMap.absolute ".lake/page-db-work-posting-conflicts"
  if ← path.pathExists then IO.FS.removeDirAll path
  let first ← PageMap.create path (Persistence.valueToJson (.text "posting-conflicts")).compress
  let owner := OutcomeEdge.make (.text "alpha beta gamma delta") (.text "first result") [] (by simp) (by simp)
  let other := OutcomeEdge.make (.text "alpha beta gamma omega") (.text "second result") [] (by simp) (by simp)
  let (ids, _, _) ← PageMap.withWriter first fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← [owner, other].mapM fun edge => intern.root edge.relation
    Store.writeChange writer ⟨ids, [], false⟩
    pure ids
  let snapshot ← PageMap.pin path
  let mut postings : List (String × Nat × Nat) := []
  for surface in LogicalText.surfaceNames "alpha beta gamma" do
    if let some term ← Store.findTerm? snapshot snapshot.get surface then
      if let some (ordinal, _) := (← Store.directory snapshot (Store.key "workSurface" term.id)).find?
          (fun row => row.2 == ids[0]!) then
        postings := postings ++ [(surface, term.id, ordinal)]
  let some first := postings[0]? | throw (IO.userError "missing first overlapping gram")
  let some second := postings[1]? | throw (IO.userError "missing second overlapping gram")
  let surfaces := [first.1, second.1]
  let expected ← Store.workSurfaceCandidates snapshot surfaces
  require (expected == ids && (← Store.workSurfaceCandidates snapshot (surfaces ++ surfaces)) == ids)
    "overlapping Work postings changed the complete ordered owner set"
  let _ ← PageMap.withWriter snapshot fun writer =>
    Store.putNat writer (Store.key (Store.key "workSurface" second.2.1) second.2.2) ids[1]!
  let damaged ← PageMap.pin path
  for query in [surfaces, surfaces.reverse, [first.1, first.1, second.1]] do
    let rejected ← try let _ ← Store.workSurfaceCandidates damaged query; pure false catch _ => pure true
    require rejected "a conflicting gram reused a previously verified owner's membership"
  require ((← Store.workSurfaceCandidates snapshot surfaces) == expected)
    "a later corrupt posting changed an earlier pinned publication"

def workSurfaces : IO Unit := do
  workSurfaceConflicts
  let path ← PageMap.absolute ".lake/page-db-work-surfaces-20261006"
  if ← path.pathExists then IO.FS.removeDirAll path
  let first ← PageMap.create path (Persistence.valueToJson (.text "surface-fixture")).compress
  let body := Value.atom (.mk (Array.replicate (1024 * 1024) (255 : UInt8)))
  let owners := (List.range 32).map fun i =>
    OutcomeEdge.make (.text s!"previous alpha_identifier_{i}") body [] (by simp) (by simp)
  let related := OutcomeEdge.make (.text "investigate parser alpha_identifier beta_identifier")
    (.text "alpha_identifier beta_identifier parser branch checked in the source") [] (by simp) (by simp)
  let owners := owners ++ [related]
  let children := owners.map (·.work)
  let parent := Value.text "old parent inquiry"
  let topology ← if valid : children ≠ [] ∧ parent ∉ children then
    pure (AllEdge.make parent children valid.1 valid.2)
    else throw (IO.userError "invalid Work surface fixture topology")
  let (ids, _, _) ← PageMap.withWriter first fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let allId ← intern.root topology.relation
    let ids ← owners.mapM (fun owner => intern.root owner.relation)
    Store.writeChange writer ⟨allId :: ids, [], false⟩
    pure ids
  let snapshot ← PageMap.pin path
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer
    { all := [topology], outcomes := owners }
  for query in ["", "fresh_unique_gap", "alpha_identifier_2", "ALPHA_IDENTIFIER_2",
      "previous", "investigate parser", "beta_identifier", "日本語 /different/path"] do
    let pattern := Matcher.compile LogicalText.logicalNormalizer query
    let actual ← Store.workSurfaceCandidates snapshot pattern.surfaces.toList
    let expected := (ids.zip corpus.candidates).filterMap fun (id, candidate) =>
      if Matcher.sharesSurface pattern candidate.work then some id else none
    require (actual == expected)
      "Work postings lost, invented, duplicated or reordered full-kernel admissions"
  let selected : Config.Selection := {
    label := "surface-probe", semanticMatcher := none
    read := [⟨"work", path⟩], write := none, handoffChars := 24000 }
  let mut samples : List Json := []
  for trial in [:3] do
    runtimeCache.set {}
    let measured ← PageMap.pin path
    let start ← IO.monoNanosNow
    let result ← computeAutomaticHandoff selected [some measured] "fresh_unique_gap" [] true
    let elapsed := (← IO.monoNanosNow) - start
    let bytes ← measured.readBytes.get
    require (result.isNone && bytes < 128 * 1024)
      "indexed negative native search read an unrelated megabyte Outcome"
    runtimeCache.set {}
    let reference ← PageMap.pin path
    let expected ← computeGeneralAutomaticHandoff selected [some reference] "fresh_unique_gap" [] true
    require ((toJson result).compress == (toJson expected).compress)
      "indexed native miss changed the full production handoff"
    require ((← reference.readBytes.get) > 1024 * 1024)
      "full reference did not exercise the large unrelated body"
    samples := samples ++ [Json.mkObj [("trial", toJson trial),
      ("read_bytes", toJson bytes), ("elapsed_ns", toJson elapsed),
      ("reference_read_bytes", toJson (← reference.readBytes.get))]]
  runtimeCache.set {}
  let current := Matcher.atomText? related.work |>.getD ""
  require (!(← indexedNativeMiss [some (← PageMap.pin path)] current))
    "a positive native request was dropped before general discovery"
  let positive ← PageMap.pin path
  let positiveStart ← IO.monoNanosNow
  let actual ← computeAutomaticHandoff selected [some positive] current [] true
  let positiveNs := (← IO.monoNanosNow) - positiveStart
  let positiveBytes ← positive.readBytes.get
  require (positiveBytes < 128 * 1024)
    "exact indexed positive root read unrelated megabyte Outcomes"
  runtimeCache.set {}
  let positiveReference ← PageMap.pin path
  let expected ← computeGeneralAutomaticHandoff selected [some positiveReference] current [] true
  require ((toJson actual).compress == (toJson expected).compress && actual.isSome)
    "positive operation handoff or completion changed"
  let positiveReferenceBytes ← positiveReference.readBytes.get
  require (positiveReferenceBytes > 1024 * 1024)
    "positive full reference did not read the large unrelated body"
  let mut positiveSamples := [Json.mkObj [("read_bytes", toJson positiveBytes),
    ("elapsed_ns", toJson positiveNs)]]
  for _ in [:2] do
    runtimeCache.set {}
    let measured ← PageMap.pin path
    let start ← IO.monoNanosNow
    let result ← computeAutomaticHandoff selected [some measured] current [] true
    let elapsed := (← IO.monoNanosNow) - start
    let bytes ← measured.readBytes.get
    require ((toJson result).compress == (toJson expected).compress && bytes < 128 * 1024)
      "a cold indexed positive root differed from full computation or read unrelated bodies"
    positiveSamples := positiveSamples ++ [Json.mkObj [("read_bytes", toJson bytes),
      ("elapsed_ns", toJson elapsed)]]
  for localUnion in [true, false] do
    for enforce in [true, false] do
      let projected ← indexedTerminalRoot selected [some (← PageMap.pin path)] current []
        enforce (some "alpha_identifier observed") localUnion
      runtimeCache.set {}
      let reference ← computeGeneralAutomaticHandoff selected [some (← PageMap.pin path)] current []
        enforce (some "alpha_identifier observed") [] true localUnion
      require (projected.isSome && (toJson (projected.getD none)).compress == (toJson reference).compress)
        "indexed terminal changed evidence visibility, equality mode or completion enforcement"
  let mut missingComparisons := 0
  let mut missingReadMax := 0
  for layout in [[false, true], [true, false], [false, true, false],
      [false, false, true, false]] do
    let paths := layout.zipIdx.map fun (present, index) =>
      if present then path else path / s!"missing-source-{index}"
    let configured := {selected with read := paths.map fun configured =>
      (⟨configured.toString, configured⟩ : Config.Egg)}
    for query in [current, "negative_theta_identifier"] do
      for native in [true, false] do
        for evidence in [none, some "alpha_identifier observed"] do
          for localUnion in [true, false] do
            runtimeCache.set {}
            let referenceSources ← layout.mapM fun present =>
              if present then some <$> PageMap.pin path else pure none
            let reference ← computeGeneralAutomaticHandoff configured referenceSources query []
              native evidence [] true localUnion
            runtimeCache.set {}
            let sources ← layout.mapM fun present =>
              if present then some <$> PageMap.pin path else pure none
            let some single := SingleSource.find? sources |
              throw (IO.userError "one readable source was routed to federation")
            let actual ← computeAutomaticHandoff configured sources query [] native evidence [] true localUnion
            let bytes ← single.snapshot.readBytes.get
            require ((toJson actual).compress == (toJson reference).compress &&
                bytes < 128 * 1024 && (← runtimeCache.get).workspaces.isEmpty)
              "absent-source routing changed complete handoff or read unrelated megabyte bodies"
            missingReadMax := max missingReadMax bytes
            missingComparisons := missingComparisons + 1
    let present ← PageMap.pin path
    require ((SingleSource.find? [none, some present, some present, none]).isNone &&
      (SingleSource.find? [none, none]).isNone)
      "single-source routing discarded another publication or manufactured one for absence"
  IO.println ((Json.mkObj [("kind", .str "readable_source_route"),
    ("complete_handoff_comparisons", toJson missingComparisons),
    ("max_read_bytes", toJson missingReadMax),
    ("unrelated_body_bytes", toJson (1024 * 1024 : Nat))]).compress)
  let broadSnapshot ← PageMap.pin path
  require ((← indexedTerminalRoot selected [some broadSnapshot] "previous different_identifier" [] true none true).isNone &&
      (← broadSnapshot.readBytes.get) < 128 * 1024)
    "non-terminal nomination loaded Outcome bodies before rejecting its Work domain"
  let parentRequest ← indexedTerminalRoot selected [some (← PageMap.pin path)]
    (Matcher.atomText? parent |>.getD "") [] true none true
  require parentRequest.isNone "a decomposable parent bypassed saturation"
  let (_, unchanged, bytes) ← PageMap.withWriter snapshot fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    for owner in owners do let _ ← intern.root owner.relation; pure ()
  require (unchanged == snapshot.head && bytes == 0)
    "duplicate owner rewrote or incremented the Work surface index"
  let retiring := ids[2]!
  let fresh := OutcomeEdge.make (.text "newly_available_evidence") (.text "new observation") [] (by simp) (by simp)
  let (freshId, _, _) ← PageMap.withWriter snapshot fun writer => do
    Store.removeRoot writer retiring
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root fresh.relation
    Store.writeChange writer ⟨[id], [retiring], false⟩
    pure id
  let revised ← PageMap.pin path
  require ((← Store.workSurfaceCandidates revised (LogicalText.surfaceNames "alpha_identifier_2")).isEmpty &&
      (← Store.workSurfaceCandidates revised (LogicalText.surfaceNames "newly_available_evidence")) == [freshId] &&
      (← Store.workSurfaceCandidates snapshot (LogicalText.surfaceNames "alpha_identifier_2")) == [retiring])
    "Work correction/deletion/new match mixed pinned snapshots or kept a stale posting"
  require ((← Store.getNat revised.get "indexedWorks") == owners.length &&
      (← Store.getNat revised.get "candidates") == owners.length)
    "Work surface correction changed the complete candidate population"
  let authority ← Store.authority revised
  let alias : UnionEdge := ⟨.text "fresh_unique_gap", parent, .workspace authority, by intro _; rfl⟩
  let _ ← PageMap.withWriter revised fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    Store.addUnions intern [alias]
    Store.writeChange writer ⟨[], [], true⟩
  let joined ← PageMap.pin path
  require (!(← indexedNativeMiss [some joined] "fresh_unique_gap") &&
      (← indexedNativeMiss [some revised] "fresh_unique_gap"))
    "Union-exposed children were dropped or an old snapshot saw a future Union"
  let some located ← Store.locateUnion? joined (Store.unionDisplayKey alias.left alias.right) |
    throw (IO.userError "Work probe Union fixture disappeared")
  let _ ← PageMap.withWriter joined fun writer => do
    Store.removeUnion writer located
    Store.writeChange writer ⟨[], [], true⟩
  let unjoined ← PageMap.pin path
  require (← indexedNativeMiss [some unjoined] "fresh_unique_gap")
    "a retracted Union still exposed obsolete Work children"
  let frequencyOwner := OutcomeEdge.make (.text "separate unrelated archive")
    (.text "alpha_identifier") [] (by simp) (by simp)
  let _ ← PageMap.withWriter unjoined fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root frequencyOwner.relation
    Store.writeChange writer ⟨[id], [], false⟩
  let changedFrequency ← PageMap.pin path
  require ((← Store.getNat changedFrequency.get "candidates") == owners.length + 1 &&
      (← Store.frequency changedFrequency "alpha_identifier") == 2 &&
      (← Store.frequency changedFrequency "beta_identifier") == 1)
    "unselected new evidence did not change global population and document frequencies"
  runtimeCache.set {}
  let changedExpected ← computeGeneralAutomaticHandoff selected [some changedFrequency] current [] true
  let changedActual ← computeAutomaticHandoff selected [some (← PageMap.pin path)] current [] true
  require ((toJson changedActual).compress == (toJson changedExpected).compress)
    "terminal query ignored unselected population/frequency dependencies"
  let unrelatedHeader ← Store.readOutcomeHeader changedFrequency ids[0]!
  let _ ← PageMap.withWriter changedFrequency fun writer =>
    writer.put (Store.key (Store.key "body" unrelatedHeader.outcome) 0) none
  let damagedUnrelated ← PageMap.pin path
  runtimeCache.set {}
  let avoided ← computeAutomaticHandoff selected [some damagedUnrelated] current [] true
  require ((toJson avoided).compress == (toJson changedExpected).compress)
    "a terminal query followed an irrelevant Outcome body"
  let fullFailed ← try
      let _ ← Store.materialize damagedUnrelated
      pure false
    catch _ => pure true
  require fullFailed "the unrelated missing-body fixture did not reject full hydration"
  let selectedHeader ← Store.readOutcomeHeader damagedUnrelated ids[32]!
  let _ ← PageMap.withWriter damagedUnrelated fun writer =>
    writer.put (Store.key (Store.key "body" selectedHeader.outcome) 0) none
  let damagedSelected ← PageMap.pin path
  let failedOwner ← computeAutomaticHandoff selected [some damagedSelected] current [] true
  require (failedOwner.any (fun handoff => handoff.reason == "search-incomplete" && !handoff.blocksCurrent))
    "missing selected evidence became completion or a successful empty search"
  let _ ← PageMap.withWriter damagedSelected fun writer => Store.putNat writer "indexedWorks" 0
  runtimeCache.set {}
  let incomplete ← computeAutomaticHandoff selected [some (← PageMap.pin path)] "fresh_unique_gap" [] true
  require (incomplete.any (fun handoff => handoff.reason == "search-incomplete" && !handoff.blocksCurrent))
    "an incomplete Work index became a successful empty search or a completion judgment"
  IO.println ((Json.mkObj [("kind", .str "indexed_native_miss"),
    ("body_bytes", toJson (1024 * 1024 : Nat)), ("samples", toJson samples),
    ("positive_read_bytes", toJson positiveBytes),
    ("positive_reference_read_bytes", toJson positiveReferenceBytes),
    ("positive_samples", toJson positiveSamples),
    ("generative_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS persisted Work surfaces, full-kernel order, indexed negative/positive handoff, no-op, correction/deletion/new match, global frequency/population repair, Union exposure/retraction, irrelevant-body exclusion and missing-evidence rejection"

def indexedGeneral : IO Unit := do
  let path ← PageMap.absolute ".lake/page-db-indexed-general-20261006"
  if ← path.pathExists then IO.FS.removeDirAll path
  let first ← PageMap.create path (Persistence.valueToJson (.text "indexed-general-fixture")).compress
  let large := Value.atom (.mk (Array.replicate (1024 * 1024) (255 : UInt8)))
  let archives := (List.range 32).map fun i => OutcomeEdge.make
    (.text s!"archive_storage_{i}") large [] (by simp) (by simp)
  let alpha := OutcomeEdge.make (.text "inspect alpha_parser branch")
    (.text "alpha_parser branch checked: concrete source evidence") [] (by simp) (by simp)
  let beta := OutcomeEdge.make (.text "inspect beta_formatter branch")
    (.text "beta_formatter branch checked: formatting source evidence") [] (by simp) (by simp)
  let combined := OutcomeEdge.make (.text "inspect alpha_parser branch and beta_formatter branch")
    (.text "alpha_parser branch and beta_formatter branch: separate observations") [] (by simp) (by simp)
  let parent := Value.text "resolve parser_formatter inquiry"
  let makeAll := fun (parent : Value) (children : List Value) =>
    if valid : children ≠ [] ∧ parent ∉ children then
      pure (AllEdge.make parent children valid.1 valid.2)
    else throw (IO.userError "invalid indexed general fixture All")
  let firstAll ← makeAll parent [alpha.work, .text "unavailable_remote_log"]
  let secondAll ← makeAll parent [beta.work, alpha.work, .text "unavailable_second_log"]
  let unary := fun value => Value.applyList .occurrence [Ref.semantic value]
  let outer := fun value => Value.applyList .occurrence
    [Ref.semantic value, Ref.semantic (.text "nested context")]
  let structuredParent := Value.text "resolve structured_parser inquiry"
  let structuredAll ← makeAll structuredParent [outer (unary beta.work)]
  let structuredChild ← makeAll (outer (unary alpha.work))
    [alpha.work, .text "unavailable_structured_log"]
  let cycleA := Value.text "cycle_alpha"
  let cycleB := Value.text "cycle_beta"
  let cycleAll ← makeAll cycleA [cycleB]
  let (ids, _, _) ← PageMap.withWriter first fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← (archives ++ [alpha, beta, combined]).mapM fun edge => intern.root edge.relation
    let allIds ← [firstAll, secondAll, cycleAll, structuredAll, structuredChild].mapM fun edge => intern.root edge.relation
    Store.writeChange writer ⟨ids ++ allIds, [], false⟩
    pure ids
  let authority ← Store.authority (← PageMap.pin path)
  let cycleUnion : UnionEdge := ⟨cycleA, cycleB, .workspace authority, by intro _; rfl⟩
  let aliasUnion : UnionEdge := ⟨.text "parser_formatter_alias", parent,
    .workspace authority, by intro _; rfl⟩
  let structuredUnion ← if safe : Value.sameExactFootprint (unary alpha.work) (unary beta.work) then
      pure (PersistentUnion.make authority (unary alpha.work) (unary beta.work)
        (Value.sameExactFootprint_sound safe)).edge
    else throw (IO.userError "invalid structured fixture Union")
  let _ ← PageMap.withWriter (← PageMap.pin path) fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    Store.addUnions intern [cycleUnion, aliasUnion, structuredUnion]
    Store.writeChange writer ⟨[], [], true⟩
  let selection : Config.Selection := {
    label := "indexed-general", semanticMatcher := none
    read := [⟨"work", path⟩], write := none, handoffChars := 24000 }
  let queries := ["resolve parser_formatter inquiry", "parser_formatter_alias", "cycle_alpha",
    "cycle_beta", "inspect alpha_parser branch extra_requirement",
    "inspect alpha_parser branch and beta_formatter branch", "resolve structured_parser inquiry",
    "completely_new_gap"]
  let prior ← runtimeCache.get
  let mut samples : List Json := []
  try
    let verify := fun (snapshot : Store.Snapshot) => do
      let reference ← Store.materialize snapshot
      let full := WorkGraph.fromValues reference.values
      let semanticCount := hashDistinct (reference.values.flatMap Value.semanticNodes) |>.length
      require ((← Store.getNat snapshot.get "semanticPopulation") == semanticCount &&
        (← Store.getNat snapshot.get "liveOutcomes") == full.outcomes.length)
        "differential discovery bounds differ from the live full source domain"
      for value in reference.values do
        require ((← Store.liveRoot? snapshot value).isSome)
          "read-only structural identity lost a live original owner"
      let mut samples : List Json := []
      for query in queries do
        for enforce in [true, false] do
          for localUnion in [true, false] do
            runtimeCache.set {}
            let pinned ← PageMap.pin path
            let start ← IO.monoNanosNow
            let result ← indexedDiscovery selection [some pinned] query [] enforce
              (if enforce then some "alpha_parser branch observed" else none) localUnion
            let elapsed := (← IO.monoNanosNow) - start
            let bytes ← pinned.readBytes.get
            require (result.isSome && bytes < 192 * 1024)
              "general indexed search reconstructed unrelated Outcome bodies or rejected its source domain"
            runtimeCache.set {}
            let expected ← computeGeneralAutomaticHandoff selection [some snapshot] query [] enforce
              (if enforce then some "alpha_parser branch observed" else none) [] true localUnion
            require ((toJson (result.getD none)).compress == (toJson expected).compress)
              s!"general indexed discovery changed ordered extraction, saturation or handoff: {query}"
            runtimeCache.set {}
            let routed ← computeAutomaticHandoff selection [some (← PageMap.pin path)] query [] enforce
              (if enforce then some "alpha_parser branch observed" else none) [] true localUnion
            require ((toJson routed).compress == (toJson expected).compress &&
                (← runtimeCache.get).workspaces.isEmpty)
              "the production caller missed the indexed general route or materialized a full workspace"
            samples := samples ++ [Json.mkObj [("query", toJson query),
              ("native", toJson enforce), ("local_union", toJson localUnion),
              ("read_bytes", toJson bytes), ("elapsed_ns", toJson elapsed)]]
      pure samples
    let snapshot ← PageMap.pin path
    samples := samples ++ (← verify snapshot)
    let localWork := Value.text "unavailable_remote_log"
    let pendingOwner := OutcomeEdge.make localWork
      (.text "unavailable_remote_log: newly available local evidence") [] (by simp) (by simp)
    let stageAll ← makeAll (.text "new_staged_parent") [localWork, alpha.work]
    for staged in [[alpha.relation], [pendingOwner.relation], [pendingOwner.relation, pendingOwner.relation],
        [stageAll.relation, pendingOwner.relation], [.text "unrelated staged observation"]] do
      for query in ["resolve parser_formatter inquiry", "new_staged_parent", "unavailable_remote_log"] do
        for enforce in [false, true] do
          for visible in [false, true] do
            for union in [false, true] do
              runtimeCache.set {}
              let expected ← computeGeneralAutomaticHandoff {selection with write := none}
                [some snapshot] query [] enforce none staged visible union
              runtimeCache.set {}
              let routed ← computeAutomaticHandoff selection [some snapshot]
                query [] enforce none staged visible union
              if (toJson routed).compress != (toJson expected).compress then
                IO.FS.writeFile (path / "staged-handoff-mismatch.json") (Json.mkObj [
                  ("query", toJson query), ("native", toJson enforce), ("visible", toJson visible),
                  ("local_union", toJson union), ("staged", toJson (staged.map Persistence.valueToJson)),
                  ("actual", toJson routed), ("reference", toJson expected)]).pretty
              require ((toJson routed).compress == (toJson expected).compress &&
                (← runtimeCache.get).workspaces.isEmpty)
                "indexed staged owner/frequency/topology/visibility differs from the full source"
    let corrected := OutcomeEdge.make alpha.work
      (.text "alpha_parser branch corrected: new concrete source evidence") [] (by simp) (by simp)
    let (newId, _, _) ← PageMap.withWriter snapshot fun writer => do
      Store.removeRoot writer ids[32]!
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let id ← intern.root corrected.relation
      Store.writeChange writer ⟨[id], [ids[32]!], false⟩
      pure id
    samples := samples ++ (← verify (← PageMap.pin path))
    let changed ← PageMap.pin path
    let _ ← PageMap.withWriter changed fun writer => do
      Store.removeRoot writer newId
      Store.removeRoot writer ids[33]!
      Store.writeChange writer ⟨[], [newId, ids[33]!], false⟩
    samples := samples ++ (← verify (← PageMap.pin path))
    let oldDomain ← Store.materialize snapshot
    require ((← Store.getNat snapshot.get "semanticPopulation") ==
      (hashDistinct (oldDomain.values.flatMap Value.semanticNodes)).length)
      "a retraction changed the old pinned discovery domain"
    let current ← PageMap.pin path
    let header ← Store.readOutcomeHeader current ids[0]!
    let _ ← PageMap.withWriter current fun writer =>
      writer.put (Store.key (Store.key "body" header.outcome) 0) none
    let damaged ← PageMap.pin path
    let avoided ← indexedDiscovery selection [some damaged] "resolve parser_formatter inquiry" [] true none true
    require avoided.isSome "general discovery followed an unrelated missing Outcome body"
  finally runtimeCache.set prior
  IO.println ((Json.mkObj [("kind", .str "indexed_general_discovery"),
    ("samples", toJson samples), ("generative_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS indexed multi-round discovery, authoritative depth, cyclic and alternative All/Union topology, partial Work, ordered general extraction, native/non-native, staged evidence/topology/visibility, global frequencies, correction/deletion and irrelevant-body exclusion"

def llvm (seed target : System.FilePath) : IO Unit := do
  require (!(← target.pathExists)) "never replace a previous LLVM measurement"
  let graph ← IO.ofExcept (Persistence.decode (← IO.FS.readFile seed))
  let importStart ← IO.monoNanosNow
  Persistence.saveAtomic target graph
  let importNs := (← IO.monoNanosNow) - importStart
  let loadStart ← IO.monoNanosNow
  let restored ← Persistence.load target
  let loadNs := (← IO.monoNanosNow) - loadStart
  require (restored.authority == graph.authority && restored.values == graph.values &&
    decide (restored.unions.map (·.edge) = graph.unions.map (·.edge))) "LLVM import changed the authoritative seed"
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer (WorkGraph.fromValues restored.values)
  let snap ← PageMap.pin target
  require ((← Store.getNat snap.get "candidates") == corpus.candidates.length)
    "persistent candidate population differs from Matcher"
  for candidate in corpus.candidates do
    for unit in Matcher.Corpus.candidateTerms candidate do
      let some term ← Store.findTerm? snap snap.get unit |
        throw (IO.userError "persisted frequency term is missing")
      require ((← Store.getNat snap.get (Store.key "frequency" term.id)) == corpus.frequency unit)
        "persistent frequency differs from full Matcher"
  let reference := target.parent.getD "." / "reference.egg"
  IO.FS.writeFile reference (← IO.ofExcept (Persistence.encode restored))
  let mut measurements : List Json := []
  for trial in [:3] do
    let pending : PendingTurn := {
      sessionId := "llvm-db-performance"
      turnId := s!"trial-{trial}"
      cwd := "/llvm"
      prompt := "inspect the saved LLVM evidence"
      profile := "work"
      semanticMatcher := none
      read := [target.toString]
      write := some target.toString
      handoffChars := 24000
      projection := .automatic
      tools := [{
        name := "shell"
        useId := s!"observed-{trial}"
        input := "{\"command\":\"cat relevant-source\"}"
        response := (Json.mkObj [("output", .str (String.ofList (List.replicate 4096 'x')))]).compress }]
      finalMessage := some s!"recorded observation {trial}" }
    let oldSave := do
      let started ← IO.monoNanosNow
      let before ← IO.ofExcept (Persistence.decode (← IO.FS.readFile reference))
      let compiled ← IO.ofExcept (compile before pending target.toString)
      let some committed := Transaction.commitIfCurrent before compiled.transaction |
        throw (IO.userError "reference transaction was rejected")
      let bytes ← IO.ofExcept (Persistence.encode committed)
      IO.FS.writeFile reference bytes
      pure ((← IO.monoNanosNow) - started, bytes.toUTF8.size, committed)
    let newSave := do
      let before ← PageMap.pin target
      let started ← IO.monoNanosNow
      let committed ← promote pending target
      let elapsed := (← IO.monoNanosNow) - started
      let after ← PageMap.pin target
      pure (elapsed, after.head.bytes - before.head.bytes, committed)
    let ((oldNs, oldBytes, expected), (newNs, newBytes, _)) ←
      if trial % 2 == 0 then do let old ← oldSave; let new ← newSave; pure (old, new)
      else do let new ← newSave; let old ← oldSave; pure (old, new)
    let actual ← Persistence.load target
    require (actual.authority == expected.authority && actual.values == expected.values &&
      decide (actual.unions.map (·.edge) = expected.unions.map (·.edge))) "new saving changed graph semantics"
    let headBefore ← PageMap.pin target
    let _ ← promote pending target
    let headAfter ← PageMap.pin target
    require (headBefore.head == headAfter.head) "replaying a turn republished the DB"
    measurements := measurements ++ [Json.mkObj [("trial", toJson trial), ("old_ns", toJson oldNs),
      ("new_ns", toJson newNs), ("old_bytes", toJson oldBytes), ("new_page_bytes", toJson newBytes)]]
  IO.println ((Json.mkObj [("kind", .str "llvm_seed_storage"), ("import_ns", toJson importNs),
    ("whole_inspection_ns", toJson loadNs), ("values", toJson graph.values.length),
    ("trials", toJson measurements), ("model_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS complete LLVM seed, persistent population/frequencies, equivalent turn saves and duplicate replay"

def equalGraph (left right : Graph) : Bool :=
  left.authority == right.authority && left.revision == right.revision &&
    left.values == right.values && decide (left.unions.map (·.edge) = right.unions.map (·.edge))

def verifyFrequencies (snapshot : Store.Snapshot) (graph : Graph) : IO Unit := do
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer (WorkGraph.fromValues graph.values)
  require ((← Store.getNat snapshot.get "candidates") == corpus.candidates.length)
    "retraction changed persistent candidate population"
  for candidate in corpus.candidates do
    for unit in Matcher.Corpus.candidateTerms candidate do
      require ((← Store.frequency snapshot unit) == corpus.frequency unit)
        "retraction changed persistent document frequency"
  let rootIds ← Store.rootIds snapshot
  let idsByValue := graph.values.zip rootIds
  require (idsByValue.length == graph.values.length) "range directory changed root population"
  let units := (corpus.candidates.flatMap Matcher.Corpus.candidateTerms).eraseDups ++
    ["oldmark", "newmark", "term-not-present-in-the-db"]
  for unit in units do
    let expected := idsByValue.filterMap fun (value, id) =>
      if (Store.ownerTerms value).contains unit then some id else none
    require ((← Store.postings snapshot unit) == expected)
      "persistent postings lost a new match, retained a retraction or changed root order"
  require ((← Store.frequency snapshot "term-not-present-in-the-db") == 0)
    "a term miss returned invented frequency"

def retractions : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-retractions-20261005"
  if ← root.pathExists then IO.FS.removeDirAll root
  let _ ← Persistence.create root
  let pending : PendingTurn := {
    sessionId := "page-db-retractions", turnId := "initial", cwd := "/fixture"
    prompt := "inspect alpha and beta", profile := "work", semanticMatcher := none
    read := [root.toString], write := some root.toString, handoffChars := 24000
    projection := .automatic
    tools := [{
      name := "shell"
      useId := "alpha"
      input := "{\"command\":\"cat alpha\"}"
      response := "{\"output\":\"alpha evidence oldmark\"}" }, {
      name := "shell"
      useId := "beta"
      input := "{\"command\":\"cat beta\"}"
      response := "{\"output\":\"beta evidence\"}" }]
    finalMessage := some "inspected alpha and beta" }
  let _ ← promote pending root
  let mut previous ← Persistence.load root
  let mut previousHead := (← PageMap.pin root).head
  let first ← cachedComposite [root]
  require (first.values == previous.values) "initial composite differs from inspection"
  let some oldTool := pending.tools.head? | throw (IO.userError "missing original tool")
  let oldOwner := (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) oldTool).2
  let corrected := { oldTool with
    useId := "alpha-corrected"
    response := "{\"output\":\"alpha evidence corrected newmark\"}" }
  let newOwner := (compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) corrected).2
  -- Delete, add a newly matching result, then correct a non-Atom Union.
  for step in [:3] do
    let filtered := if step == 0 then previous.values.filter (· != oldOwner) else previous.values
    let wanted := if step == 1 then filtered ++ [newOwner] else filtered
    let desired ← if valid : wanted.all Relation.wellFormed then
      pure ({ previous with
        values := wanted
        values_wellFormed := fun value member => (List.all_eq_true.mp valid) value member } : Graph)
      else throw (IO.userError "bad correction fixture")
    let desired ← if step == 2 then do
      let left := Value.applyList .all [.semantic (.text "alpha"), .semantic (.text "beta")]
      let right := Value.applyList .all [.semantic (.text "gamma"), .semantic (.text "beta")]
      if exact : Value.sameExactFootprint left right then
        pure { desired with
          unions := [PersistentUnion.make desired.authority left right (Value.sameExactFootprint_sound exact)] }
      else throw (IO.userError "Apply fixture changes Exact footprint")
      else pure desired
    Persistence.saveAtomic root desired
    let snapshot ← PageMap.pin root
    let replayed ← Store.revise snapshot previousHead previous
    let full ← Persistence.load root
    require (equalGraph replayed full) "delta journal differs from complete snapshot"
    let composite ← cachedComposite [root]
    require (composite.values == full.values &&
      decide (composite.unions = full.unions.map (·.edge))) "production composite reused stale roots or equality"
    verifyFrequencies snapshot full
    if step == 0 then
      let some term ← Store.findTerm? snapshot snapshot.get "oldmark" |
        throw (IO.userError "missing deleted term fixture")
      require ((← Store.getNat snapshot.get (Store.key "frequency" term.id)) == 0)
        "the last removed occurrence kept a nonzero frequency"
    let cached := Matcher.discover? LogicalText.logicalNormalizer (.text "inspect alpha evidence")
      composite.values composite.unions "inspect alpha evidence"
    let oracle := Matcher.discover? LogicalText.logicalNormalizer (.text "inspect alpha evidence")
      full.values (full.unions.map (·.edge)) "inspect alpha evidence"
    require (cached.map (fun d => d.hits.map (·.edge.relation)) ==
      oracle.map (fun d => d.hits.map (·.edge.relation))) "correction changed saturation hit owners"
    previous := full
    previousHead := snapshot.head
  let withoutUnion := { previous with unions := [] }
  Persistence.saveAtomic root withoutUnion
  let snapshot ← PageMap.pin root
  let replayed ← Store.revise snapshot previousHead previous
  let full ← Persistence.load root
  require (equalGraph replayed full && replayed.unions.isEmpty && !replayed.values.contains oldOwner)
    "removed general equality or root reappeared after replay"
  let composite ← cachedComposite [root]
  require (composite.unions.isEmpty && !composite.values.contains oldOwner && composite.values.contains newOwner)
    "production reader failed to consume a general equality retraction"
  let before := snapshot.head
  let damaged := { snapshot with
    head := { snapshot.head with bytes := snapshot.head.bytes + 1 } }
  let rejected ← try
      let _ ← Store.revise damaged snapshot.head full
      pure false
    catch _ => pure true
  require rejected "the delta reader reused a changed root at the same revision"
  Persistence.saveAtomic root full
  require ((← PageMap.pin root).head == before) "identical administrative save published another revision"
  IO.println "PASS live DB deletion, new match, non-Atom Union correction/retraction, exact frequencies and production delta replay"

def supportWorkIndex : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-support-work-index"
  if ← root.pathExists then IO.FS.removeDirAll root
  let base ← PageMap.create root (Persistence.valueToJson (.text "support-work-index")).compress
  let workA := Value.text "read source parser evidence"
  let workB := Value.text "read target selection evidence"
  let make := fun work body => OutcomeEdge.make work (.text body) [] (by simp) (by simp)
  let a := make workA "original parser source"
  let b := make workB "original target source"
  let a2 := make workA "second parser tool result"
  let correction := make workB "corrected target source"
  let unrelated := (List.range 24).map fun n =>
    make (.text s!"unrelated investigation {n}")
      (s!"unrelated body {n}\n" ++ String.intercalate "\n" (List.replicate 48
        (String.ofList (List.replicate 250 'z'))))
  let some firstUnrelated := unrelated.head? | throw (IO.userError "empty unrelated Work fixture")
  let values := [a.relation, firstUnrelated.relation, b.relation, a2.relation] ++
    (unrelated.drop 1).map (·.relation)
  let (ids, _, _) ← PageMap.withWriter base fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    Store.writeChange writer ⟨ids, [], false⟩
    pure ids
  let first ← PageMap.pin root
  let headerA ← Store.readOutcomeHeader first ids[0]!
  let headerB ← Store.readOutcomeHeader first ids[2]!
  let wanted := [headerB.work, headerA.work, headerB.work]
  let signature := fun (rows : List Store.SearchDocument) => rows.map fun row => (row.owner, row.work)
  let expected := fun snapshot works => do
    pure ((← Store.searchDocuments snapshot).filter fun document => works.contains document.work)
  require (signature (← Store.supportDocuments first wanted) ==
      signature (← expected first wanted))
    "sparse Work owners changed complete original candidate order or duplicate Work results"
  let before := first.head
  let _ ← PageMap.withWriter first fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let _ ← intern.root a.relation
    pure ()
  let replayed ← PageMap.pin root
  require (replayed.head == before &&
      (← Store.getNat replayed.get "indexedSearchWorks") == values.length)
    "replayed root duplicated a Work owner posting or published another head"
  let families : Std.HashMap Nat Nat := Std.HashMap.ofList [(headerB.work, 0), (headerA.work, 1)]
  let ranking := [ids[3]!, ids[0]!]
  require (signature (Store.rankSupportDocuments (← Store.supportDocuments first wanted) ranking families) ==
      signature (Store.rankSupportDocuments (← expected first wanted) ranking families))
    "sparse Work owners changed stable meaning/family ranking"
  let reader ← Store.NodeReader.new first
  require ((← reader.supportOwners [workB, workA] [] 48000 ranking [(workB, 0), (workA, 1)]).map (·.relation) ==
      [a2.relation, a.relation, b.relation])
    "production surrounding-graph hydration let family order override current meaning rank"
  let mut samples : List Json := []
  for trial in [:3] do
    let sparse ← PageMap.pin root
    sparse.trace.set (some {})
    let started ← IO.monoNanosNow
    let found ← Store.supportDocuments sparse wanted
    let elapsed := (← IO.monoNanosNow) - started
    let some trace ← sparse.trace.get | throw (IO.userError "missing sparse read trace")
    sparse.trace.set none
    require (trace.complete && trace.operations.all (fun operation => match operation with
      | .point key _ => !key.startsWith "searchWindows:" && !key.startsWith "atom:"
      | .range lower _ _ => lower == (Store.key "searchWork" headerA.work ++ ":") ||
          lower == (Store.key "searchWork" headerB.work ++ ":")
      | .payload _ _ _ => false
      | .blob _ => true))
      "support lookup read unrelated candidate/window directories or a source body"
    require ((trace.operations.filterMap (fun operation => match operation with
      | .range lower _ _ => some lower | _ => none)).length == 2)
      "duplicate demanded Work repeated its bucket traversal"
    let full ← PageMap.pin root
    let reference ← expected full wanted
    let sparseBytes ← sparse.readBytes.get
    let fullBytes ← full.readBytes.get
    require (signature found == signature reference && sparseBytes < fullBytes && elapsed < 3000000000)
      "sparse support read changed the oracle, failed to reduce actual I/O or exceeded the hook deadline"
    samples := samples ++ [Json.mkObj [("trial", toJson trial),
      ("sparse_read_bytes", toJson sparseBytes), ("full_read_bytes", toJson fullBytes),
      ("elapsed_ns", toJson elapsed), ("operations", toJson trace.operations.length)]]
  require ((← Store.supportDocuments first []).isEmpty &&
      (← Store.supportDocuments first [(← Store.getNat first.get "nodes") + 100]).isEmpty)
    "empty or absent Work invented a surrounding owner"
  let _ ← PageMap.withWriter first fun writer => do
    Store.removeRoot writer ids[2]!
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root correction.relation
    Store.writeChange writer ⟨[id], [ids[2]!], false⟩
  let corrected ← PageMap.pin root
  require (signature (← Store.supportDocuments corrected wanted) ==
      signature (← expected corrected wanted) &&
      ((← Store.supportDocuments first wanted).map (·.owner)).contains ids[2]! &&
      !((← Store.supportDocuments corrected wanted).map (·.owner)).contains ids[2]!)
    "correction mixed pinned publications or revived a retired original tool result"
  let _ ← PageMap.withWriter corrected fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root b.relation
    Store.writeChange writer ⟨[id], [], false⟩
  let readded ← PageMap.pin root
  require (signature (← Store.supportDocuments readded wanted) ==
      signature (← expected readded wanted))
    "readded original Outcome lost its new root ordinal or bucket membership"
  let ordinal ← Store.getNat readded.get (Store.key "member" ids[0]!)
  let posting := Store.key (Store.key "searchWork" headerA.work) ordinal
  let rejected := fun (snapshot : Store.Snapshot) => do
    try let _ ← Store.supportDocuments snapshot wanted; pure false
    catch _ => pure true
  let _ ← PageMap.withWriter readded fun writer => Store.putNat writer posting ids[2]!
  require (← rejected (← PageMap.pin root)) "foreign original Work passed the typed bucket check"
  let _ ← PageMap.withWriter (← PageMap.pin root) fun writer => do
    Store.putNat writer posting ids[0]!
    Store.putNat writer (Store.key (Store.key "searchWork" headerA.work) (ordinal + 999)) ids[0]!
  require (← rejected (← PageMap.pin root)) "wrong posting ordinal passed live candidate checks"
  let _ ← PageMap.withWriter (← PageMap.pin root) fun writer => do
    writer.put (Store.key (Store.key "searchWork" headerA.work) (ordinal + 999)) none
    writer.put "indexedSearchWorks" none
  require (← rejected (← PageMap.pin root)) "incomplete Work producer was treated as a complete empty corpus"
  IO.println ((Json.mkObj [("kind", .str "sparse_surrounding_work_owners"),
    ("unrelated_owners", toJson unrelated.length), ("samples", toJson samples),
    ("scope", .str "Original surrounding owner enumeration only; no model-token or whole-hook claim."),
    ("generative_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS sparse original Work owners: full-window oracle, ordering, real surrounding tool delivery, no unrelated reads, duplicates, pinned correction/deletion/readd and corrupt publication rejection"

def semanticCatalogue : IO Unit := do
  let path ← PageMap.absolute ".lake/page-db-semantic-catalogue-20261006"
  if ← path.pathExists then IO.FS.removeDirAll path
  let parent := Value.text "investigate retry_controller42 /login"
  let child := Value.text "read deployment retry_controller42"
  let parentOwner := OutcomeEdge.make parent (.text "retry_controller42 remains unresolved") [] (by simp) (by simp)
  let childOwner := OutcomeEdge.make child (.text "sample enables retry_controller42") [] (by simp) (by simp)
  let other := OutcomeEdge.make (.text "unrelated producer") (.text "upstream gateway") [] (by simp) (by simp)
  let giant := OutcomeEdge.make (.text "opaque unrelated binary")
    (.atom (ByteArray.mk (Array.replicate (1024 * 1024) (255 : UInt8)))) [] (by simp) (by simp)
  let corrected := OutcomeEdge.make child (.text "deployed upstream unverified") [] (by simp) (by simp)
  let unicode := OutcomeEdge.make (.text "source window positions 窓🙂")
    (.text ((String.ofList (List.replicate 1500 '界')) ++ "🙂fin")) [] (by simp) (by simp)
  let decomposition ← if valid : [child] ≠ [] ∧ parent ∉ [child] then
      pure (AllEdge.make parent [child] valid.1 valid.2)
    else throw (IO.userError "invalid semantic catalogue decomposition")
  let initial := [childOwner.relation, parentOwner.relation, other.relation,
    decomposition.relation, giant.relation, unicode.relation]
  let executable ← IO.appPath
  let command := [executable.toString, "search-provider", "--mode", "lexical",
    "--cache", (path / "vectors").toString, "--model-cache", (path / "models").toString]
  let selection : Config.Selection := {
    label := "indexed-semantic-test", read := [⟨"work", path⟩], write := none,
    semanticMatcher := some command, handoffChars := 24000 }
  let independentCommand := executable.toString :: "independent-search-provider" :: command.drop 2
  let mut samples := []
  let mut previousValues : List Value := []
  for (values, revision) in [initial, initial ++ [childOwner.relation],
      initial.filter (· != childOwner.relation) ++ [corrected.relation],
      initial.filter (fun value => value != childOwner.relation && value != parentOwner.relation),
      initial].zipIdx do
    let desired := values.eraseDups
    let values := previousValues.filter desired.contains ++ desired.filter (!previousValues.contains ·)
    previousValues := values
    let graph : Graph ← if valid : values.all Relation.wellFormed then
        pure { (Graph.empty (.text "catalogue fixture")) with
          values := values
          values_wellFormed := fun value member => (List.all_eq_true.mp valid) value member }
      else throw (IO.userError "invalid semantic catalogue fixture")
    Persistence.saveAtomic path graph
    let full ← Persistence.load path
    let graph := WorkGraph.fromValues full.values
    let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer graph
    let expected := SemanticMatcher.eligibleCandidates corpus
    let units := hashDistinct ((corpus.candidates.flatMap Matcher.Corpus.candidateTerms) ++
      ["new_absent_frequency_unit", "retry_controller42", "deployed"])
    let batch ← Store.frequencies (← PageMap.pin path) units
    for unit in units do
      require (batch.getD unit 0 == (← Store.frequency (← PageMap.pin path) unit))
        "batched dictionary/frequency reads changed a positive, negative or corrected count"
    let measured ← PageMap.pin path
    let documents ← indexedSemanticDocuments measured graph.all
    let actual ← documents.mapM fun doc => do
      let located ← Store.locateOutcome measured doc.owner
      pure (← Store.readLocatedOutcome measured located).relation
    require (actual == expected.map (·.edge.relation))
      "indexed semantic catalogue changed summary/child candidate ordering or resurrected a retired owner"
    for (document, candidate) in documents.zip expected do
      require (document.windows == (SearchRank.windows (SemanticMatcher.candidateText candidate)).map Store.windowKey)
        "stored semantic windows differ from the exact reference candidate text"
      for (text, index) in (SearchRank.windows (SemanticMatcher.candidateText candidate)).zipIdx do
        let observed ← Store.readSearchWindow measured document index
        require (observed == text)
          "bounded source repair changed window bytes, Unicode boundaries or overlap positions"
    for query in ["retry_controller42 /login", "upstream gateway", "truly_absent_quartz99"] do
      for unit in SearchRank.terms query do
        let (ids, count) ← Store.searchPosting measured unit
        let wanted := expected.filter (fun candidate => (SearchRank.terms (SemanticMatcher.candidateText candidate)).contains unit)
        require (count == wanted.length && ids.length == count &&
          (documents.filter fun document => ids.contains document.owner).map (·.owner) ==
            (documents.zip expected |>.filter fun row => wanted.any (fun candidate => candidate.edge.relation == row.2.edge.relation)).map (·.1.owner))
          "search term posting/frequency changed after correction, deletion, duplicate, or re-addition"
      runtimeCache.set {}
      let source ← PageMap.pin path
      let start ← IO.monoNanosNow
      let actual ← computeAutomaticHandoff selection [some source] query [] false
      let elapsed := (← IO.monoNanosNow) - start
      let bytes ← source.readBytes.get
      require ((← runtimeCache.get).workspaces.isEmpty && bytes < 128 * 1024)
        "bundled indexed semantic search reconstructed a complete workspace or unrelated megabyte body"
      runtimeCache.set {}
      let expected ← computeGeneralAutomaticHandoff selection [some (← PageMap.pin path)] query [] false
      require ((toJson actual).compress == (toJson expected).compress)
        "bundled indexed semantic handoff differs from the full Matcher oracle"
      runtimeCache.set {}
      let externalSource ← PageMap.pin path
      let external ← computeAutomaticHandoff
        {selection with semanticMatcher := some independentCommand} [some externalSource] query [] false
      require ((toJson external).compress == (toJson expected).compress &&
        (← runtimeCache.get).workspaces.isEmpty && (← externalSource.readBytes.get) < 128 * 1024)
        "independent provider changed the handoff or restored a full workspace/unrelated body"
      if revision == 0 then
        let stagedParent := Value.text "investigate retry_controller42 upstream gateway"
        let parentResult := OutcomeEdge.make stagedParent (.text "new parent sample remains unverified") []
          (by simp) (by simp)
        let crossParent ← if valid : [child] ≠ [] ∧ stagedParent ∉ [child] then
            pure (AllEdge.make stagedParent [child] valid.1 valid.2)
          else throw (IO.userError "invalid staged semantic parent")
        let crossChild := Value.text "read retry_controller42 upstream gateway"
        let childResult := OutcomeEdge.make crossChild (.text "fresh sample without deployed evidence") []
          (by simp) (by simp)
        let crossChildren ← if valid : [crossChild] ≠ [] ∧ parent ∉ [crossChild] then
            pure (AllEdge.make parent [crossChild] valid.1 valid.2)
          else throw (IO.userError "invalid staged semantic child")
        for staged in [[childOwner.relation, corrected.relation],
            [parentResult.relation, crossParent.relation],
            [childResult.relation, crossChildren.relation], [crossParent.relation]] do
          for visible in [false, true] do
            runtimeCache.set {}
            let reference ← computeGeneralAutomaticHandoff selection [some (← PageMap.pin path)]
              query [] false none staged visible
            runtimeCache.set {}
            let actual ← computeAutomaticHandoff selection [some (← PageMap.pin path)]
              query [] false none staged visible
            require ((toJson actual).compress == (toJson reference).compress)
              "staged semantic corpus changed duplicate filtering, global frequency, priority or complete handoff"
            require (← runtimeCache.get).workspaces.isEmpty
              "staged semantic discovery restored the complete source graph"
            runtimeCache.set {}
            let external ← computeAutomaticHandoff
              {selection with semanticMatcher := some independentCommand} [some (← PageMap.pin path)]
              query [] false none staged visible
            require ((toJson external).compress == (toJson reference).compress &&
              (← runtimeCache.get).workspaces.isEmpty)
              "independent provider changed staged provenance, order or visibility"
      samples := Json.mkObj [("revision", toJson revision), ("query", toJson query),
        ("read_bytes", toJson bytes), ("elapsed_ns", toJson elapsed)] :: samples
  let multiple : Config.Selection := {selection with
    read := selection.read ++ selection.read
    semanticMatcher := some [executable.toString, "semantic-provider-fixture", "retrieval"] }
  runtimeCache.set {}
  let reference ← computeGeneralAutomaticHandoff multiple
    [some (← PageMap.pin path), some (← PageMap.pin path)] "absent_user_quartz99" [] false
  runtimeCache.set {}
  let actual ← computeAutomaticHandoff multiple
    [some (← PageMap.pin path), some (← PageMap.pin path)] "absent_user_quartz99" [] false
  require (reference.isSome && (toJson actual).compress == (toJson reference).compress)
    "a multi-source native miss incorrectly suppressed an independent semantic nomination"
  let healthy ← PageMap.pin path
  let some term ← Store.findTerm? healthy healthy.get "retry_controller42" |
    throw (IO.userError "missing corruption fixture term")
  let _ ← PageMap.withWriter healthy fun writer =>
    Store.putNat writer (Store.key "searchFrequency" term.id) 999
  runtimeCache.set {}
  let pending ← computeAutomaticHandoff selection [some (← PageMap.pin path)] "retry_controller42 /login" [] false
  require (pending.any (·.text == pendingSearch.text) && (← runtimeCache.get).workspaces.isEmpty)
    "a corrupt semantic posting silently fell back to full reconstruction or empty success"
  IO.println ((Json.mkObj [("kind", .str "indexed_semantic_catalogue"),
    ("samples", toJson samples.reverse)]).compress)
  IO.println "PASS indexed semantic catalogue, stable priority, differential lexical frequencies and complete production handoff equality"

def federatedSearch : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-federated-search-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let left := root / "left"
  let right := root / "right"
  let parent := Value.text "investigate retry_controller42 /login"
  let child := Value.text "read deployment retry_controller42 /login"
  let shared := OutcomeEdge.make (.text "shared retry_controller42")
    (.text "shared retained finding") [.text "raw exact receipt"] (by simp) (by decide)
  let corrected := OutcomeEdge.make shared.work (.text "corrected deployed result remains unverified")
    [.text "changed exact receipt"] (by simp) (by decide)
  let parentOwner := OutcomeEdge.make parent (.text "parent synthesis includes deployment sample") [] (by simp) (by simp)
  let childOwner := OutcomeEdge.make child (.text "sample enables retry_controller42") [] (by simp) (by simp)
  let other := OutcomeEdge.make (.text "independent upstream gateway") (.text "gateway finding") [] (by simp) (by simp)
  let opaqueOwner := OutcomeEdge.make (.atom (ByteArray.mk #[255])) (.text "opaque Work is unsearchable") [] (by simp) (by simp)
  let giant := OutcomeEdge.make (.text "unrelated opaque binary")
    (.atom (ByteArray.mk (Array.replicate (1024 * 1024) (255 : UInt8)))) [] (by simp) (by simp)
  let structuredWork := Value.applyList .receipt
    ((List.range 7).map fun n => .exact (.text s!"nontext-work-{n}"))
  let structuredOwner := OutcomeEdge.make structuredWork giant.outcome [] (by simp) (by simp)
  let bridge ← if valid : [child] ≠ [] ∧ parent ∉ [child] then
      pure (AllEdge.make parent [child] valid.1 valid.2)
    else throw (IO.userError "invalid federated topology")
  let unary := fun value => Value.applyList .occurrence [Ref.semantic value]
  let outer := fun value => Value.applyList .occurrence [Ref.semantic value]
  let structuredParent := Value.text "resolve structured_shared inquiry"
  let makeAll := fun (parent : Value) (children : List Value) =>
    if valid : children ≠ [] ∧ parent ∉ children then
      pure (AllEdge.make parent children valid.1 valid.2)
    else throw (IO.userError "invalid structured federation fixture")
  let structuredAll ← makeAll structuredParent [outer (unary child)]
  let nestedAll ← makeAll (outer (unary parent)) [child, .text "unavailable_structured_log"]
  for (path, values) in [(left, [childOwner.relation, shared.relation, bridge.relation,
      giant.relation, opaqueOwner.relation, structuredOwner.relation, structuredAll.relation]),
      (right, [other.relation, shared.relation, parentOwner.relation, bridge.relation, nestedAll.relation])] do
    let graph : Graph ← if valid : values.all Relation.wellFormed then
        pure {
          (Graph.empty (.text path.toString)) with
          values
          values_wellFormed := fun value member => (List.all_eq_true.mp valid) value member }
      else throw (IO.userError "invalid federated owners")
    Persistence.saveAtomic path graph
  let structuredUnion ← if safe : Value.sameExactFootprint (unary child) (unary parent) then
      pure (PersistentUnion.make (← Store.authority (← PageMap.pin left))
        (unary child) (unary parent) (Value.sameExactFootprint_sound safe)).edge
    else throw (IO.userError "invalid structured federation Union")
  let _ ← PageMap.withWriter (← PageMap.pin left) fun writer => do
    Store.addUnions ⟨writer, ← IO.mkRef {}⟩ [structuredUnion]
    Store.writeChange writer ⟨[], [], true⟩
  let executable ← IO.appPath
  let command := [executable.toString, "independent-search-provider", "--mode", "lexical",
    "--cache", (root / "vectors").toString, "--model-cache", (root / "unused-models").toString]
  let base : Config.Selection := {
    label := "federated"
    read := [⟨"left", left⟩, ⟨"right", right⟩]
    write := none
    semanticMatcher := none
    handoffChars := 24000 }
  let mut comparisons := 0
  let mut largestRead := 0
  let mut longestNs := 0
  for revision in [:5] do
    if revision > 0 then
      let path := if revision == 1 || revision == 4 then left else right
      let snapshot ← PageMap.pin path
      let _ ← PageMap.withWriter snapshot fun writer => do
        if let some (_, id) ← Store.liveRoot? snapshot shared.relation then Store.removeRoot writer id
        let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
        if revision == 4 then let _ ← intern.root structuredOwner.relation; pure ()
        if revision == 3 then let _ ← intern.root corrected.relation; pure ()
        if revision == 4 then let _ ← intern.root shared.relation; pure ()
        if revision == 3 then
          let authority ← Store.authority snapshot
          let alias : UnionEdge := ⟨.text "alias_retry_request", parent, .workspace authority, by intro _; rfl⟩
          Store.addUnions intern [alias]
        if revision == 4 then Store.addUnions intern [structuredUnion]
      if revision == 2 then
        let snapshot ← PageMap.pin left
        let _ ← PageMap.withWriter snapshot fun writer => do
          let some (_, id) ← Store.liveRoot? snapshot structuredOwner.relation |
            throw (IO.userError "missing structured retraction fixture")
          Store.removeRoot writer id
          let some located ← Store.locateUnion? snapshot
              (Store.unionDisplayKey structuredUnion.left structuredUnion.right) |
            throw (IO.userError "structured federation Union disappeared before retraction")
          Store.removeUnion writer located
        pure ()
    let snapshots := #[← PageMap.pin left, ← PageMap.pin right]
    let catalogue ← Store.Federated.prepare snapshots
    let composite ← pinnedComposite (snapshots.toList.map some)
    let graph := WorkGraph.fromValues composite.values
    let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer graph
    require (catalogue.owners.size == graph.outcomes.length && catalogue.documents.length == corpus.population &&
      catalogue.semanticPopulation == (hashDistinct (composite.values.flatMap Value.semanticNodes)).length &&
      catalogue.all == graph.all)
      "federation changed overlapping roots, opaque population, semantic count or topology order"
    for unit in (corpus.candidates.flatMap Matcher.Corpus.candidateTerms).eraseDups ++ ["negative_quartz99"] do
      require ((← Store.Federated.frequency catalogue unit) == corpus.frequency unit)
        "federated differential frequency counted duplicate or retired owners"
    for paths in [[left], [left, right], [right, left], [left, left, right]] do
      let selection := {base with read := paths.map fun (path : System.FilePath) => ⟨path.toString, path⟩}
      for query in ["retry_controller42 /login", "upstream gateway", "negative_quartz99",
          "alias_retry_request", "resolve structured_shared inquiry"] do
        for semantic in [false, true] do
          for native in [false, true] do
            let selection := {selection with semanticMatcher := if semantic then some command else none}
            runtimeCache.set {}
            let reference ← computeGeneralAutomaticHandoff selection (← paths.mapM fun path => some <$> PageMap.pin path)
              query [] native
            if query == "resolve structured_shared inquiry" && paths.length > 1 then
              if reference.isSome != (revision != 2 && revision != 3) then
                let cache ← runtimeCache.get
                let nominations := cache.query.map (·.input.semantic.related.map relationKey)
                let hitCount := cache.query.map fun entry =>
                  entry.result.map (·.discovery.hits.length)
                IO.FS.writeFile (root / "structured-reference-mismatch.json") (Json.mkObj [
                  ("revision", toJson revision), ("semantic", toJson semantic), ("native", toJson native),
                  ("nominations", toJson nominations), ("hits", toJson hitCount),
                  ("reference_present", toJson reference.isSome)]).pretty
              require (reference.isSome == (revision != 2 && revision != 3))
                "structured federation fixture did not expose and retract its nested congruence dependency"
            runtimeCache.set {}
            let sources ← paths.mapM fun path => some <$> PageMap.pin path
            let started ← IO.monoNanosNow
            let actual ← computeAutomaticHandoff selection sources query [] native
            longestNs := max longestNs ((← IO.monoNanosNow) - started)
            let reads ← sources.filterMap id |>.mapM (·.readBytes.get)
            let bytes := reads.foldl (· + ·) 0
            largestRead := max largestRead bytes
            if (toJson actual).compress != (toJson reference).compress then
              IO.FS.writeFile (root / "handoff-mismatch.json") (Json.mkObj [
                ("revision", toJson revision), ("query", toJson query), ("semantic", toJson semantic),
                ("native", toJson native), ("sources", toJson (paths.map (·.toString))),
                ("actual", toJson actual), ("reference", toJson reference)]).pretty
            require ((toJson actual).compress == (toJson reference).compress)
              s!"federated complete handoff differs from full oracle: revision={revision} query={query} semantic={semantic} native={native}"
            require ((← runtimeCache.get).workspaces.isEmpty && bytes < 384 * 1024)
              "federation restored a full workspace or the unrelated megabyte Outcome"
            comparisons := comparisons + 1
      let staged := [shared.relation, parentOwner.relation,
        (OutcomeEdge.make (.text "fresh retry_controller42 /login") (.text "new current observation") [] (by simp) (by simp)).relation]
      for visible in [false, true] do
        let selection := {selection with semanticMatcher := some command}
        runtimeCache.set {}
        let reference ← computeGeneralAutomaticHandoff selection (← paths.mapM fun path => some <$> PageMap.pin path)
          "retry_controller42 /login" [] false none staged visible
        runtimeCache.set {}
        let actual ← computeAutomaticHandoff selection (← paths.mapM fun path => some <$> PageMap.pin path)
          "retry_controller42 /login" [] false none staged visible
        require ((toJson actual).compress == (toJson reference).compress && (← runtimeCache.get).workspaces.isEmpty)
          "federation changed duplicate staged owners, cross-source parent priority or compaction visibility"
        comparisons := comparisons + 1
  -- Deliberate nomination collisions must still be resolved by the exact
  -- structural/byte comparator, including Exact observations and arity.
  let receipt := Value.applyList .receipt
    ((List.range 7).map fun n => (.exact, Value.text s!"receipt-position-{n}"))
  let longer := Value.applyList .receipt
    ((List.range 8).map fun n => (.exact, Value.text s!"receipt-position-{n}"))
  let reauthorized := Value.applyList .receipt
    ((List.range 7).map fun n => (if n == 3 then .semantic else .exact, Value.text s!"receipt-position-{n}"))
  let reordered := Value.applyList .receipt
    ((List.range 7).reverse.map fun n => (.exact, Value.text s!"receipt-position-{n}"))
  let changedOperator := Value.applyList .occurrence
    ((List.range 7).map fun n => (.exact, Value.text s!"receipt-position-{n}"))
  let mut shapeIds : List (Nat × Value) := []
  for path in [left, right] do
    let snapshot ← PageMap.pin path
    let (ids, _, _) ← PageMap.withWriter snapshot fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let mut ids := []
      for value in [receipt, longer, reauthorized, reordered, changedOperator] do
        let id ← intern.value value
        ids := ids ++ [(id, value)]
      pure ids
    if path == right then shapeIds := ids
  let snapshot ← PageMap.pin left
  let some receiptId ← Store.findNode? snapshot receipt | throw (IO.userError "missing receipt comparator fixture")
  for path in [left, right] do
    let snapshot ← PageMap.pin path
    let count ← Store.getNat snapshot.get "nodes"
    let _ ← PageMap.withWriter snapshot fun writer => do
      for id in [:count] do Store.putNat writer (Store.key "nodeHash" id) 0
      Store.putIds writer "hash:0" (List.range count)
    pure ()
  let leftSnapshot ← PageMap.pin left
  let rightSnapshot ← PageMap.pin right
  let snapshots := #[leftSnapshot, rightSnapshot]
  for (id, value) in shapeIds do
    require ((← Store.nodesEqual leftSnapshot receiptId rightSnapshot id) == decide (receipt = value))
      "equal hashes concealed differing source arity, authority, position or operator"
  let collisionCatalogue ← Store.Federated.prepare snapshots
  let full ← pinnedComposite (snapshots.toList.map some)
  require (collisionCatalogue.owners.size == (WorkGraph.fromValues full.values).outcomes.length &&
    collisionCatalogue.semanticPopulation == (hashDistinct (full.values.flatMap Value.semanticNodes)).length)
    "a portable nomination collision merged foreign bytes, arity, operators or Exact authority"
  IO.println ((Json.mkObj [("kind", .str "federated_indexed_handoff"), ("comparisons", toJson comparisons),
    ("max_read_bytes", toJson largestRead), ("max_ns", toJson longestNs)]).compress)
  IO.println "PASS overlapping pinned sources, correction/retraction, exact collision checks and complete indexed handoffs"

/-- A diamond-shaped persisted DAG with one large opaque Atom. Equal parent
applications must not reread that Atom per parent. Exact-only descendants
remain structurally significant without inflating the semantic population. -/
def canonicalFederation : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-canonical-federation-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let paths := [root / "left", root / "right"]
  let body := Value.atom (ByteArray.mk (Array.replicate (1024 * 1024) (255 : UInt8)))
  let diamond := Value.applyList .receipt [(.semantic, body), (.exact, body)]
  let branches := (List.range 16).map fun n => Value.applyList .receipt
    [(.semantic, diamond), (.semantic, diamond), (.exact, .text s!"branch-{n}")]
  for path in paths do
    let initial ← PageMap.create path (Persistence.valueToJson (.text "canonical-federation")).compress
    let _ ← PageMap.withWriter initial fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      for branch in branches do let _ ← intern.root branch; pure ()
    pure ()
  let some leftPath := paths[0]? | throw (IO.userError "missing left source")
  let some rightPath := paths[1]? | throw (IO.userError "missing right source")
  let summarize := fun (roots : List Nat) (population : Nat) (all : List AllEdge)
      (unions : List UnionEdge) (documents owners : Nat) =>
    (roots.length, population, all, unions, documents, owners)
  let mut samples : List Json := []
  for iteration in [:4] do
    for previous in [iteration % 2 == 0, iteration % 2 != 0] do
      let sources := #[← PageMap.pin leftPath, ← PageMap.pin rightPath]
      let start ← IO.monoNanosNow
      let summary ← if previous then do
          let before ← FederationBeforeCanonical.prepare sources
          pure (summarize before.roots before.identity.nodes.size before.all before.unions
            before.documents.length before.owners.size)
        else do
          let after ← Store.Federated.prepare sources
          require (after.identity.nodes.size > after.semanticPopulation)
            "Exact-only children were omitted or incorrectly counted as semantic population"
          pure (summarize after.roots after.semanticPopulation after.all after.unions
            after.documents.length after.owners.size)
      let elapsed := (← IO.monoNanosNow) - start
      require (summary == (16, 18, [], [], 0, 0))
        "canonical interpretation changed root identity, population or source topology"
      let bytes ← sources.foldlM (fun count snapshot => return count + (← snapshot.readBytes.get)) 0
      let reads ← sources.foldlM (fun count snapshot => return count + (← snapshot.reads.get)) 0
      if !previous then
        require (bytes < 4 * 1024 * 1024)
          "canonical child interning reread the shared megabyte Atom per enclosing application"
      samples := Json.mkObj [("previous", toJson previous), ("elapsed_ns", toJson elapsed),
        ("read_bytes", toJson bytes), ("reads", toJson reads)] :: samples
  let sources := #[← PageMap.pin leftPath, ← PageMap.pin rightPath]
  let after ← Store.Federated.prepare sources
  -- Every canonical alias, including Exact-only children, must reproduce its
  -- original full structural Value. The oracle is not on the production path.
  for source in List.finRange sources.size do
    let count ← Store.getNat sources[source].get "nodes"
    for id in [:count] do
      let canonical ← after.identity.lookup source id
      let some entry := after.identity.nodes[canonical]? |
        throw (IO.userError "missing canonical alias")
      require ((← Store.readNode sources[source] sources[source].get id) ==
        (← Store.readNode entry.original.snapshot entry.original.snapshot.get entry.original.id))
        "canonical alias changed an Exact descendant or original Value"
  require ((Store.Federated.ReboundApplication.make? .receipt
      [(.exact, 0)] [(.semantic, 0)] 1).isNone &&
    (Store.Federated.ReboundApplication.make? .receipt
      [(.exact, 0)] [(.exact, 1)] 1).isNone &&
    (Store.Federated.ReboundApplication.make? .receipt
      [(.exact, 0)] [] 1).isNone)
    "canonical child substitution accepted foreign ids, lost arity or changed authority"
  IO.println ((Json.mkObj [("kind", .str "canonical_federation"),
    ("body_bytes", toJson (1024 * 1024)), ("branches", toJson 16),
    ("samples", toJson samples.reverse)]).compress)
  IO.println "PASS canonical DAG federation, single streamed Atom comparison, Exact-only provenance, complete alias resolution and invalid substitution rejection"

def selectionReplay : IO Unit := do
  let normalizer := LogicalText.logicalNormalizer
  let texts := ["", "alpha alpha beta", "beta alpha alpha", "alpha beta gamma alpha",
    "src/code.cc 日本語 λ", "gamma gamma gamma alpha beta"]
  let mut checks := 0
  for left in texts do
    for right in texts do
      let query := Matcher.compile normalizer left
      let target := Matcher.compile normalizer right
      for offset in [:3] do
        let weights := query.logical.units.zipIdx.map fun (_, n) => n + offset + 1
        let ranked := Matcher.referenceRank weights query target
        let generated := Matcher.SelectionReplay.generate ranked
        require (decide (generated.1.val = Matcher.workSelection ranked))
          "indexed selection changed the complete original ordered evidence"
        let replayed := Matcher.SelectionReplay.obtain ranked (some generated.2)
        require (replayed.2.2 && decide (replayed.1.val = Matcher.workSelection ranked))
          "a complete current selection witness was not replayed"
        for trace in [generated.2.tail, generated.2.reverse, generated.2 ++ generated.2,
            generated.2.map (fun _ => 10^12), []] do
          for current in [ranked, ranked.reverse, ranked.tail] do
            let found := Matcher.SelectionReplay.obtain current (some trace)
            require (decide (found.1.val = Matcher.workSelection current) &&
              decide (Matcher.coverageOf query weights (offset + 10) found.1.val =
                Matcher.workCoverage query weights (offset + 10) current))
              "stale, reordered, duplicate, absent or out-of-range witness changed coverage/spans"
            checks := checks + 1
  let root ← PageMap.absolute ".lake/page-db-selection-replay"
  if ← root.pathExists then IO.FS.removeDirAll root
  let snapshot ← PageMap.create root (Persistence.valueToJson (.text "selection-replay")).compress
  let query := Matcher.compile normalizer (String.intercalate " " (List.replicate 8 "alpha") ++ " beta")
  let target := Matcher.compile normalizer (String.intercalate " " (List.replicate 9 "alpha") ++ " gamma")
  let input : Matcher.GeometryMemo.Input := ⟨query.logical, target.logical,
    query.logical.units.map (fun _ => 3), target.logical.units.map (fun _ => 4), 12,
    query.locator, target.locator⟩
  let reader ← Matcher.RankMemo.Reader.new snapshot .selection
  let initial : Matcher.GeometryMemo.Persistent := {prepared := ⟨{}, 0, 0⟩}
  let first ← Matcher.GeometryMemo.prepareUsingM {} {} (some reader) initial [input]
  require (!first.saved.isEmpty && first.repaired == 2 && first.replayed == 0 &&
    decide ((Matcher.GeometryMemo.get first.prepared.cache input).result = Matcher.GeometryMemo.reference input))
    "the real geometry path did not retain exact forward/reverse selection traces"
  Matcher.RankMemo.publish root first.saved .selection
  let published ← PageMap.pin root
  let cold ← Matcher.RankMemo.Reader.new published .selection
  let repeated ← Matcher.GeometryMemo.prepareUsingM {} {} (some cold) initial [input]
  require (repeated.replayed == 2 && repeated.repaired == 0 &&
    decide ((Matcher.GeometryMemo.get repeated.prepared.cache input).result = Matcher.GeometryMemo.reference input))
    "cold durable selection replay changed complete coverage or recomputed a valid trace"
  -- Deliberately retain the old optional binding while changing valid current
  -- inputs. A length mismatch would exercise only the empty-input guard.
  let added := Matcher.compile normalizer
    (String.intercalate " " (List.replicate 9 "alpha") ++ " beta newly_added")
  let shifted := Matcher.compile normalizer
    ("prefix " ++ String.intercalate " " (List.replicate 9 "alpha") ++ " gamma")
  let deleted := Matcher.compile normalizer "deleted_requirement"
  let addedInput := {input with
    current := added.logical
    currentWeights := added.logical.units.map (fun _ => 4)}
  require (!(Matcher.GeometryMemo.reference addedInput).isEmpty)
    "the new-match fixture must exercise actual nonempty coverage"
  for changed in [
      {input with pastWeights := input.pastWeights.zipIdx.map (fun (_, n) => n + 10), novelty := 100},
      addedInput,
      {input with current := shifted.logical, currentWeights := shifted.logical.units.map (fun _ => 4)},
      {input with past := deleted.logical, pastWeights := deleted.logical.units.map (fun _ => 3)},
      {input with current := (Matcher.compile normalizer "").logical, currentWeights := []},
      -- Invalid inputs remain separately rejected, never reused as evidence.
      {input with current := deleted.logical}] do
    let obtained ← Matcher.GeometryMemo.prepareUsingM {} {} (some cold) initial [changed]
    require (decide ((Matcher.GeometryMemo.get obtained.prepared.cache changed).result =
      Matcher.GeometryMemo.reference changed))
      "frequency/population, correction, deletion or a new match reused obsolete coverage"
  Matcher.RankMemo.publish root first.saved .selection
  require ((← PageMap.pin root).head == published.head) "identical selection hints appended pages"
  require ((← Matcher.RankMemo.read published).isEmpty)
    "selection and ranking lanes shared an optional record namespace"
  let _ ← PageMap.withWriter published fun writer => do
    for (key, _) in first.saved do
      Store.putNat writer (Store.key (Matcher.RankMemo.row key .selection) 0) (10^12)
    Store.writeChange writer ⟨[], [], false⟩
  let damaged ← Matcher.RankMemo.Reader.new (← PageMap.pin root) .selection
  let restored ← Matcher.GeometryMemo.prepareUsingM {} {} (some damaged) initial [input]
  require (restored.repaired == 2 && decide ((Matcher.GeometryMemo.get restored.prepared.cache input).result =
    Matcher.GeometryMemo.reference input)) "corrupt selection metadata escaped as evidence"
  IO.println ((Json.mkObj [("kind", .str "selection_replay"),
    ("complete_selection_checks", toJson checks), ("durable_traces", toJson first.saved.length)]).compress)
  IO.println "PASS indexed selection and durable forward/reverse replay, full coverage/spans, frequency/population changes, new/negative matches, correction/deletion, lane isolation, no-op and corruption"

def rankDirectory : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-rank-directory"
  if ← root.pathExists then IO.FS.removeDirAll root
  let initial ← PageMap.create root (Persistence.valueToJson (.text "rank-directory")).compress
  let query := Matcher.compile LogicalText.logicalNormalizer
    (String.intercalate " " (List.replicate 8 "alpha") ++ " beta")
  let weights := query.logical.units.map fun _ => 3
  let targets := (List.range 100).map fun n => Matcher.compile LogicalText.logicalNormalizer
    (String.intercalate " " (List.replicate 9 "alpha") ++ s!" gamma_{n}")
  let hints := targets.filterMap fun target =>
    (Matcher.RankMemo.obtain [] weights query target).2.1
  let some first := hints.head? | throw (IO.userError "no retained directory fixture")
  let some second := hints.find? (fun hint => Matcher.RankMemo.row hint.1 != Matcher.RankMemo.row first.1) |
    throw (IO.userError "no distinct rank slot")
  Matcher.RankMemo.publish root [first]
  Matcher.RankMemo.publish root [second]
  let snapshot ← PageMap.pin root
  require ((← Matcher.RankMemo.readKey snapshot first.1) == [first] &&
    (← Matcher.RankMemo.readKey snapshot second.1) == [second])
    "another request erased an unused durable rank order"
  snapshot.trace.set (some {})
  let reader ← Matcher.RankMemo.Reader.new snapshot
  require ((← reader.get first.1) == [first] && (← reader.get first.1) == [first] &&
    (← reader.loads.get) == 1)
    "the current request reread its pinned positive advice"
  let some absent := ((List.range 1000).map (fun n => s!"rank-directory-absent-{n}")).find?
    (fun key => Matcher.RankMemo.row key != Matcher.RankMemo.row first.1) |
    throw (IO.userError "missing independent negative slot")
  require ((← reader.get absent).isEmpty && (← reader.get absent).isEmpty &&
    (← reader.loads.get) == 2)
    "the current request reread or invented negative rank advice"
  require ((← snapshot.trace.get).all (fun trace => trace.operations.isEmpty))
    "optional rank reads polluted authoritative semantic dependencies"
  Matcher.RankMemo.publish root [first]
  require ((← PageMap.pin root).head == snapshot.head)
    "replaying one requested key republished unrelated memo rows"
  let beforeBytes ← snapshot.readBytes.get
  let some target := targets.find? (fun target => Matcher.RankMemo.binding query target == first.1) |
    throw (IO.userError "missing directory target")
  let prepared ← ({} : Matcher.RankMemo.Prepared).addM reader weights query target
  require (prepared.reused == 1 && prepared.computed == 0 &&
    Matcher.RankMemo.provider prepared.cache weights query target == Matcher.referenceRank weights query target &&
    (← reader.loads.get) == 2)
    "the demanded IO path did not consume its fully certified pinned order"
  let afterBytes ← snapshot.readBytes.get
  require (afterBytes == beforeBytes) "memo advice lookup repeated after its first load"
  let malformed := (first.1, first.2.tail)
  Matcher.RankMemo.publish root [malformed]
  let fresh ← PageMap.pin root
  require ((← Matcher.RankMemo.readKey fresh first.1) == [malformed] &&
    (← reader.get first.1) == [first]) "new publication changed a pinned request's advice"
  let cold ← Matcher.RankMemo.Reader.new fresh
  let repaired ← ({} : Matcher.RankMemo.Prepared).addM cold weights query target
  require (repaired.computed == 1 &&
    Matcher.RankMemo.provider repaired.cache weights query target == Matcher.referenceRank weights query target)
    "missing source positions escaped the complete current-domain certifier"
  let collision := ((List.range 1000).map (fun n => s!"different-rank-key-{n}")).find?
    (fun key => Matcher.RankMemo.row key == Matcher.RankMemo.row first.1)
  let some collision := collision | throw (IO.userError "missing deliberate rank-slot collision")
  require ((← reader.get collision).isEmpty && (← reader.loads.get) == 2)
    "a colliding request reread a pinned slot or borrowed another key's advice"
  Matcher.RankMemo.publish root [(collision, first.2)]
  let collided ← PageMap.pin root
  require ((← Matcher.RankMemo.readKey collided first.1).isEmpty &&
    (← Matcher.RankMemo.readKey collided second.1) == [second])
    "slot collision gained another request's identity or modified an unrelated slot"
  let _ ← PageMap.withWriter collided fun writer => do
    Store.putNat writer (Store.key (Matcher.RankMemo.row first.1) 0) (10^12)
    Store.writeChange writer ⟨[], [], false⟩
  let corrupt ← Matcher.RankMemo.Reader.new (← PageMap.pin root)
  require ((← corrupt.get first.1).isEmpty && (← corrupt.get first.1).isEmpty &&
    (← corrupt.loads.get) == 1) "corrupt optional advice caused repeated IO or escaped as evidence"
  let emptyQuery := Matcher.compile LogicalText.logicalNormalizer "no_overlap"
  let tiny ← ({} : Matcher.RankMemo.Prepared).addM corrupt [3] emptyQuery target
  require (tiny.saved.isEmpty && (← corrupt.loads.get) == 1)
    "tiny/empty joins read unused durable records"
  IO.println "PASS sparse durable rank directory, independent requests, pinned positive/negative reads, exact current-domain replay, slot collision, corruption and tiny-join bypass"

def rankMemo : IO Unit := do
  let query := Matcher.compile LogicalText.logicalNormalizer
    (String.intercalate " " (List.replicate 8 "alpha") ++ " beta")
  let target := Matcher.compile LogicalText.logicalNormalizer
    (String.intercalate " " (List.replicate 9 "alpha") ++ " gamma")
  let weights := query.logical.units.map fun _ => 3
  let first := Matcher.RankMemo.obtain [] weights query target
  let saved := first.2.1.toList
  require (!saved.isEmpty && !first.2.2) "rank fixture did not retain a demanded order"
  let repeated := Matcher.RankMemo.obtain saved weights query target
  require (repeated.2.2 && repeated.1.val == first.1.val)
    "persisted rank positions were not reused exactly"
  let rankQuery := Matcher.compile LogicalText.logicalNormalizer "alpha beta alpha beta"
  let rankTarget := Matcher.compile LogicalText.logicalNormalizer
    (String.intercalate " " (List.replicate 20 "alpha beta"))
  let oldWeights := [10, 1, 10, 1]
  let newWeights := [1, 10, 1, 10]
  let ordered := Matcher.RankMemo.obtain [] oldWeights rankQuery rankTarget
  let some (_, positions) := ordered.2.1 | throw (IO.userError "repair fixture was not retained")
  let source := Matcher.SurfaceJoin.current rankQuery rankTarget
  require ((Matcher.EvidenceReplay.certifyIndexed newWeights source positions).isNone)
    "frequency correction did not change the order in the repair fixture"
  let repaired := Matcher.RankMemo.obtain ordered.2.1.toList newWeights rankQuery rankTarget
  require (repaired.2.2 && repaired.1.val == Matcher.referenceRank newWeights rankQuery rankTarget)
    "changed-frequency ranking did not repair and reuse its ascending runs"
  for (q, t, w) in [
      (query, target, weights.reverse.map (· + 2)),
      (Matcher.compile LogicalText.logicalNormalizer "beta alpha alpha", target, [3, 3, 3]),
      (query, Matcher.compile LogicalText.logicalNormalizer "gamma alpha", weights),
      (query, Matcher.compile LogicalText.logicalNormalizer "entirely absent", weights)] do
    -- Deliberately nominate an obsolete order even under a colliding binding.
    let colliding := saved.map fun (_, positions) => (Matcher.RankMemo.binding q t, positions)
    let actual := Matcher.RankMemo.obtain colliding w q t
    require (actual.1.val == Matcher.referenceRank w q t)
      "changed frequency, source, position or new/negative match reused stale rank evidence"
  for altered in [saved.map (fun (key, positions) => (key, positions.tail)),
      saved.map (fun (key, positions) => (key, positions.map (fun _ => 999999))),
      saved.map (fun (key, positions) => (key, positions ++ positions))] do
    let actual := Matcher.RankMemo.obtain altered weights query target
    require (actual.1.val == first.1.val) "malformed rank positions changed evidence"
  let root ← PageMap.absolute ".lake/page-db-rank-memo-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let initial ← PageMap.create root (Persistence.valueToJson (.text "rank-memo-fixture")).compress
  -- Establish a canonical graph head before publishing derived metadata.
  let before ← Store.materialize initial
  Matcher.RankMemo.publish root saved
  let published ← PageMap.pin root
  let restored ← Matcher.RankMemo.read published
  require (restored == saved && (Matcher.RankMemo.obtain restored weights query target).2.2)
    "cold read did not restore the certified demanded order"
  let replayed ← Store.revise published initial.head before
  let full ← Store.materialize published
  require (equalGraph replayed full && replayed.values.isEmpty && replayed.unions.isEmpty)
    "derived metadata was not a graph-neutral journal publication"
  Matcher.RankMemo.publish root saved
  require ((← PageMap.pin root).head == published.head)
    "identical rank order appended or republished pages"
  let started ← IO.monoNanosNow
  let (_, unchanged, bytes) ← PageMap.withWriter published fun _ => do
    let rejected ← try Matcher.RankMemo.publish root saved; pure false catch _ => pure true
    require rejected "optional memo waited behind or entered a held writer"
  require (unchanged == published.head && bytes == 0 && (← IO.monoNanosNow) - started < 1000000000)
    "busy optional memo changed the DB or exceeded one second"
  let (_, _, _) ← PageMap.withWriter published fun writer => do
    Store.putNat writer (Store.key (Matcher.RankMemo.row saved.head!.1) 0) (10^12)
    Store.writeChange writer ⟨[], [], false⟩
  let corrupt ← PageMap.pin root
  let started ← IO.monoNanosNow
  let rejected ← try let _ ← Matcher.RankMemo.read corrupt; pure false catch _ => pure true
  require (rejected && (← IO.monoNanosNow) - started < 1000000000)
    "unbounded corrupt payload counter reached chunk hydration"
  Matcher.RankMemo.publish root saved
  require ((← Matcher.RankMemo.read (← PageMap.pin root)) == saved)
    "discarded derived memo could not be rebuilt without trusting its corrupt counter"
  let makeOwner := fun text result => OutcomeEdge.make (.text text) (.text result) [] (by simp) (by simp)
  let old := makeOwner target.logical.original "alpha beta observed evidence"
  let corrected := makeOwner target.logical.original "gamma corrected evidence"
  let fresh := makeOwner "beta alpha gamma" "new alpha evidence"
  let selected : Config.Selection := {
    label := "rank-memo-cache", semanticMatcher := none
    read := [⟨"work", root⟩], write := some ⟨"work", root⟩
    handoffChars := 24000 }
  let authority ← Store.authority (← PageMap.pin root)
  let rootGraph : Graph := { Graph.empty authority with
    values := [old.relation]
    values_wellFormed := by
      intro value member
      have equal : value = old.relation := by simpa using member
      subst value
      rfl }
  Persistence.saveAtomic root rootGraph
  let previousRuntime ← runtimeCache.get
  try
    runtimeCache.set {}
    let initial ← cachedWorkspace selected
    require (initial.prepared.freshCompiles == 1) "cold fixture did not compile its owner"
    -- A graph-neutral DB publication must advance physical stamps while
    -- reusing all current semantic compilation, not scanning owner terms.
    let otherSaved := saved.map fun (key, positions) => (key ++ ":other-demand", positions)
    Matcher.RankMemo.publish root otherSaved
    let reused ← cachedWorkspace selected
    require (reused.stamps != initial.stamps && reused.prepared.freshCompiles == 0 &&
      reused.prepared.frequencyTouches == 0)
      "derived page publication rebuilt the unchanged semantic corpus"
    require (decide (reused.composite = initial.composite) &&
      decide (reused.graph = WorkGraph.fromValues reused.composite.values))
      "retagging changed the authoritative graph"
    let correctedGraph : Graph := { Graph.empty authority with
      values := [corrected.relation]
      values_wellFormed := by
        intro value member
        have equal : value = corrected.relation := by simpa using member
        subst value
        rfl }
    Persistence.saveAtomic root correctedGraph
    let changed ← cachedWorkspace selected
    require (changed.prepared.freshCompiles == 1 && changed.prepared.frequencyTouches > 0 &&
      decide (changed.graph = WorkGraph.fromValues [corrected.relation]))
      "semantic correction reused an obsolete owner compilation"
    Persistence.saveAtomic root (Graph.empty authority)
    let deleted ← cachedWorkspace selected
    require (deleted.graph.outcomes.isEmpty && deleted.prepared.corpus.candidates.isEmpty)
      "owner deletion survived the semantic dependency cache"
  finally runtimeCache.set previousRuntime
  let mut retained : Matcher.RankMemo.Saved := []
  let mut hits := 0
  for owners in [[old], [old], [old, fresh], [corrected, fresh], [fresh], [], [old]] do
    let graph : WorkGraph := {outcomes := owners}
    let prepared := TestOracle.CorpusCache.prepare LogicalText.logicalNormalizer {} graph
    let input : SearchMemo.Input := {
      sources := ["current-source"], authorities := [], origins := [], unionOrigins := []
      values := owners.map (·.relation), unions := [], graph, current := query.logical.original
      evidence := none, semantic := {}, localUnion := true, native := false }
    -- No process cache survives these iterations: only persisted positions
    -- may accelerate the current full source/frequency domain.
    let (actual, updated) := SearchMemo.getUsing none retained input prepared
    let render := fun result => result.bind fun (found : SearchMemo.PreparedDiscovery) =>
      renderAutomatic [] 24000 input.current [] false true found.discovery
        ⟨found.extraction, found.exact⟩
    require ((toJson (render actual.result)).compress ==
      (toJson (render (SearchMemo.reference input))).compress)
      "cold persistent replay changed discovery, saturation, extraction or full handoff"
    if let some entry := updated then
      retained := entry.savedRanks
      hits := hits + entry.rankReused
  require (hits > 0) "production search never consumed a persisted rank certificate"
  -- The actual sparse caller must use the same durable rank frontier. Each
  -- request is cold and has a distinct receipt key, so a whole-result memo
  -- cannot mask a missing rank connection.
  let indexedRoot ← PageMap.absolute ".lake/page-db-indexed-rank-20261006"
  if ← indexedRoot.pathExists then IO.FS.removeDirAll indexedRoot
  let initial ← PageMap.create indexedRoot (Persistence.valueToJson (.text "indexed-rank-fixture")).compress
  let indexedSelection : Config.Selection := { selected with
    read := [⟨"work", indexedRoot⟩], write := some ⟨"work", indexedRoot⟩ }
  let prior ← runtimeCache.get
  try
    let mut snapshot := initial
    let mut ownerIds : List Nat := []
    let mut retainedAny := false
    for (owners, iteration) in [[old], [old], [old, fresh], [corrected, fresh], [fresh], [], [old]].zipIdx do
      let (newIds, _, _) ← PageMap.withWriter snapshot fun writer => do
        for id in ownerIds do Store.removeRoot writer id
        let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
        let ids ← owners.mapM fun owner => intern.root owner.relation
        Store.writeChange writer ⟨ids, ownerIds, false⟩
        pure ids
      ownerIds := newIds
      snapshot ← PageMap.pin indexedRoot
      let receipt := [s!"rank-fixture-previous-receipt-{iteration}"]
      runtimeCache.set {}
      let actual ← automaticHandoff indexedSelection query.logical.original receipt false
      require ((← runtimeCache.get).workspaces.isEmpty)
        "durable rank connection restored a whole graph workspace"
      runtimeCache.set {}
      let expected ← computeGeneralAutomaticHandoff {indexedSelection with write := none}
        [some snapshot] query.logical.original receipt false
      require ((toJson actual).compress == (toJson expected).compress)
        "indexed persisted ranks changed complete handoff after correction/deletion/new match"
      snapshot ← PageMap.pin indexedRoot
      let retainedIndexed ← Matcher.RankMemo.read snapshot
      retainedAny := retainedAny || !retainedIndexed.isEmpty
      -- A damaged optional row must be ignored and rebuilt from the current
      -- indexed source, never turn its source into a failure or a stale hit.
      if iteration == 1 then
        let _ ← PageMap.withWriter snapshot fun writer => do
          Store.putNat writer (Store.key (Matcher.RankMemo.row retainedIndexed.head!.1) 0) (10^12)
          Store.writeChange writer ⟨[], [], false⟩
        snapshot ← PageMap.pin indexedRoot
        runtimeCache.set {}
        let repaired ← automaticHandoff indexedSelection query.logical.original
          ["rank-fixture-corrupt-receipt"] false
        runtimeCache.set {}
        let reference ← computeGeneralAutomaticHandoff {indexedSelection with write := none}
          [some snapshot] query.logical.original ["rank-fixture-corrupt-receipt"] false
        require ((toJson repaired).compress == (toJson reference).compress)
          "malformed persisted rank metadata changed indexed evidence"
        require (!(← Matcher.RankMemo.read (← PageMap.pin indexedRoot)).isEmpty)
          "indexed rank repair did not rebuild its discarded optional row"
        snapshot ← PageMap.pin indexedRoot
    require retainedAny "the indexed production route did not publish its demanded rank frontier"
  finally runtimeCache.set prior
  IO.println "PASS persistent rank replay, full-domain certification, negative/new matches, source/weight changes, malformed positions, graph-neutral journal, no-op, busy writer and bounded corruption rejection"

def demandMemo : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-demand-memo-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let snapshot ← PageMap.create root (Persistence.valueToJson (.text "demand-memo-fixture")).compress
  let owner := OutcomeEdge.make (.text "check alpha beta parser")
    (.text "alpha beta parser: checked source and found the concrete branch") [] (by simp) (by simp)
  let parent := Value.text "resolve alpha beta parser issue"
  let some all := AllEdge.fromValue? (.applyList .all [.semantic parent, .semantic owner.work])
    | throw (IO.userError "invalid demand memo topology fixture")
  let authority ← Store.authority snapshot
  let build := fun (values : List Value) => do
    if valid : values.all Relation.wellFormed then
      pure ({
        authority := authority
        revision := 0
        values := values
        unions := []
        values_wellFormed := fun value member => (List.all_eq_true.mp valid) value member } : Graph)
    else throw (IO.userError "invalid demand memo roots fixture")
  let graph ← build [all.relation, owner.relation]
  Persistence.saveAtomic root graph
  let selected : Config.Selection := {
    label := "demand-memo", semanticMatcher := none
    read := [⟨"work", root⟩], write := some ⟨"work", root⟩, handoffChars := 24000 }
  let priorRuntime ← runtimeCache.get
  try
    runtimeCache.set {}
    let first ← automaticHandoff selected "check alpha beta parser" [] false
    require first.isSome "positive demand memo fixture did not render a handoff"
    let old ← PageMap.pin root
    runtimeCache.set {}
    let repeated ← automaticHandoff selected "check alpha beta parser" [] false
    require ((toJson repeated).compress == (toJson first).compress)
      "persistent reuse changed the rendered handoff"
    let cache ← runtimeCache.get
    require (cache.composites.isEmpty && cache.workspaces.isEmpty && cache.query.isNone)
      "cold process reuse still materialized the graph or executed Matcher"
    require ((← PageMap.pin root).head == old.head)
      "a persistent cache hit appended another publication"
    -- A newly matching owner, even one absent from the previous positive
    -- trace, invalidates the cache. Corrections and deletions do so too.
    let revised := OutcomeEdge.make owner.work (.text "alpha beta parser: corrected evidence") [] (by simp) (by simp)
    let corrected ← build [all.relation, revised.relation]
    Persistence.saveAtomic root corrected
    require (!(← DemandMemo.agree (← PageMap.pin root) old.head))
      "an Outcome correction was accepted as graph-neutral"
    runtimeCache.set {}
    let changed ← automaticHandoff selected "check alpha beta parser" [] false
    let cache ← runtimeCache.get
    require (cache.workspaces.isEmpty && (toJson changed).compress != (toJson first).compress)
      "a corrected source reused its previous response or reconstructed the full workspace"
    let current ← PageMap.pin root
    Persistence.saveAtomic root (Graph.empty graph.authority)
    require (!(← DemandMemo.agree (← PageMap.pin root) current.head))
      "deletion was accepted as graph-neutral"
    runtimeCache.set {}
    require ((← automaticHandoff selected "check alpha beta parser" [] false).isNone)
      "deleted evidence survived a cold search"
    runtimeCache.set {}
    require ((← automaticHandoff selected "check alpha beta parser" [] false).isNone &&
      (← runtimeCache.get).workspaces.isEmpty)
      "a completed negative result was not persistently reused"
    Persistence.saveAtomic root graph
    let readded ← PageMap.pin root
    require (!(← DemandMemo.agree readded current.head))
      "newly matching source membership reused a negative result"
    -- A local-only observation is explicitly different from an external
    -- provider's completed negative nomination.
    let engine ← FileSystem.readVersion (← FileSystem.openRead (← IO.appPath).toString)
    let request := demandRequest engine selected "check alpha beta parser" [] false none [] true true
    let record : DemandMemo.Record := ⟨request, [(root.normalize.toString, some readded.head)], "null", none, none⟩
    DemandMemo.publish readded record
    let neutral ← PageMap.pin root
    require (← DemandMemo.agree neutral readded.head) "an exact neutral publication was not reused"
    let restored ← DemandMemo.read neutral request
    require (restored == some record) "bounded durable record did not round-trip"
    require ((← DemandMemo.readObserved neutral request none).isSome &&
        (← DemandMemo.readObserved neutral request (some [])).isNone)
      "local-only reuse was mistaken for a completed external negative observation"
    require ((← DemandMemo.read neutral (request ++ "changed")).isNone)
      "different complete request bytes reused a nominated slot"
    let fork := { readded.head with root := none }
    require (!(← DemandMemo.agree neutral fork))
      "a different predecessor with the same revision was accepted"
    let started ← IO.monoNanosNow
    let (_, _, _) ← PageMap.withWriter neutral fun _ => do
      let rejected ← try DemandMemo.publish neutral record; pure false catch _ => pure true
      require rejected "the optional demand memo waited behind or entered a held writer"
    require ((← IO.monoNanosNow) - started < 1000000000) "memo lock contention exceeded one second"
    let tag := DemandMemo.row request
    let (_, _, _) ← PageMap.withWriter neutral fun writer => do
      Store.putNat writer (Store.key tag 0) (10^12)
      Store.writeChange writer ⟨[], [], false⟩
    require ((← DemandMemo.read (← PageMap.pin root) request).isNone)
      "a corrupt unbounded chunk counter reached hydration"
    DemandMemo.publish (← PageMap.pin root) record
    let start ← PageMap.pin root
    let mut next := start
    for _ in [:DemandMemo.chainAllowance + 1] do
      let (_, _, _) ← PageMap.withWriter next fun writer => do
        Store.putNat writer "memo:fixture-neutral-counter" next.head.revision
        Store.writeChange writer ⟨[], [], false⟩
      next ← PageMap.pin root
    require (!(← DemandMemo.agree next start.head))
      "an optional dependency walk exceeded its page-work allowance"
    -- Parameters which affect erasure, visibility, provenance or budget
    -- must change the complete cache request, even under a slot collision.
    for changed in [
        demandRequest engine selected "different demand" [] false none [] true true,
        demandRequest engine selected "check alpha beta parser" ["delivered"] false none [] true true,
        demandRequest engine selected "check alpha beta parser" [] true none [] true true,
        demandRequest engine selected "check alpha beta parser" [] false (some "evidence") [] true true,
        demandRequest engine selected "check alpha beta parser" [] false none [owner.relation] true true,
        demandRequest engine selected "check alpha beta parser" [] false none [] false true,
        demandRequest engine selected "check alpha beta parser" [] false none [] true false,
        demandRequest {engine with stamp := engine.stamp ++ "replaced"} selected "check alpha beta parser" [] false none [] true true,
        demandRequest engine {selected with handoffChars := 100} "check alpha beta parser" [] false none [] true true] do
      require (changed != request && !DemandMemo.requestMatches record changed)
        "an output-affecting request dependency was omitted"
    let peer ← PageMap.absolute ".lake/page-db-demand-new-source-20261006"
    if ← peer.pathExists then IO.FS.removeDirAll peer
    let shared := {selected with read := [⟨"peer", peer⟩, ⟨"work", root⟩]}
    let query := "inspect newly_available_zeta"
    runtimeCache.set {}
    require ((← automaticHandoff shared query [] true).isNone)
      "absent peer manufactured matching evidence"
    let request := demandRequest engine shared query [] true none [] true true
    let pinned ← PageMap.pin root
    let some absence ← DemandMemo.read pinned request |
      throw (IO.userError "missing-source negative result was not durably cached")
    require (absence.sources.head? == some (peer.normalize.toString, none))
      "routing omitted the negative source dependency"
    let initial ← PageMap.create peer (Persistence.valueToJson (.text "new-peer-fixture")).compress
    let incoming := OutcomeEdge.make (.text query)
      (.text "newly_available_zeta: verified incoming peer evidence") [] (by simp) (by simp)
    let _ ← PageMap.withWriter initial fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let id ← intern.root incoming.relation
      Store.writeChange writer ⟨[id], [], false⟩
    let sources := [some (← PageMap.pin peer), some (← PageMap.pin root)]
    require (!(← DemandMemo.dependenciesAgree absence [peer, root] sources) &&
        (SingleSource.find? sources).isNone)
      "a newly readable peer reused absence or bypassed federation"
    runtimeCache.set {}
    let reference ← computeGeneralAutomaticHandoff shared sources query [] true
    runtimeCache.set {}
    let actual ← automaticHandoff shared query [] true
    require (actual.any (fun handoff => handoff.text.contains "verified incoming peer evidence") &&
        (toJson actual).compress == (toJson reference).compress)
      "new peer evidence did not replace the cached negative result"
    runtimeCache.set {}
    require ((toJson (← automaticHandoff shared query [] true)).compress == (toJson actual).compress)
      "cold reuse changed a two-source response after peer arrival"
    IO.FS.removeDirAll peer
    runtimeCache.set {}
    require ((← automaticHandoff shared query [] true).isNone)
      "unavailable peer evidence survived its source dependency"
  finally runtimeCache.set priorRuntime
  IO.println "PASS persistent production demand reuse, cold graph-free hit, full predecessor-chain validation, corrected/deleted/new evidence, negative results, all request dependencies, no-op, fork, bounded corruption and nonwaiting writer"

def semanticDemandMemo : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-observed-semantic-demand"
  if ← root.pathExists then IO.FS.removeDirAll root
  let provider := root / "provider"
  IO.FS.createDirAll provider
  let first ← PageMap.create (root / "db")
    (Persistence.valueToJson (.text "observed-semantic-demand")).compress
  let query := "check alpha beta parser"
  let owner := OutcomeEdge.make (.text query)
    (.text "alpha beta parser: original recorded evidence") [] (by simp) (by simp)
  let _ ← PageMap.withWriter first fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root owner.relation
    Store.writeChange writer ⟨[id], [], false⟩
  let selected : Config.Selection := {
    label := "observed-semantic-demand", read := [⟨"work", root / "db"⟩]
    write := some ⟨"work", root / "db"⟩, handoffChars := 24000
    semanticMatcher := some [(← IO.appPath).toString, "observed-search-provider", provider.toString] }
  let engine ← FileSystem.readVersion (← FileSystem.openRead (← IO.appPath).toString)
  let request := fun text => demandRequest engine selected text [] false none [] true true
  let calls := do
    let value ← IO.FS.readFile (provider / "calls")
    pure (value.trimAscii.toString.toNat?.getD 0)
  let answer := fun related => IO.FS.writeFile (provider / "response.json")
    (Json.mkObj [("related", toJson (related : List Nat)),
      ("ranked", toJson ([0] : List Nat)), ("evidence", .arr #[])]).compress
  let run := fun text => do
    runtimeCache.set {}
    automaticHandoff selected text [] false
  let record := fun text => do
    let some record ← DemandMemo.read (← PageMap.pin (root / "db")) (request text) |
      throw (IO.userError "observed semantic search did not publish its dependency record")
    pure record
  let previous ← runtimeCache.get
  try
    answer [0]
    let first ← run query
    require (first.any (fun handoff => handoff.reason != "search-incomplete" &&
      handoff.text.contains "original recorded evidence"))
      "semantic demand fixture did not produce its positive evidence"
    let initial ← record query
    require (initial.nominations.any (!·.isEmpty) && initial.reads.isSome)
      "provider nominations or graph read dependencies were omitted from the production record"
    require (!(initial.reads.getD []).flatten.any fun observation => match observation with
      | .point key _ => key.startsWith "memo:"
      | _ => false)
      "optional memo lookups became graph dependencies and invalidated their own publication"
    let pinned ← PageMap.pin (root / "db")
    let before ← calls
    let mut times : List Nat := []
    for _ in [:3] do
      let start ← IO.monoNanosNow
      let cold ← run query
      times := times ++ [(← IO.monoNanosNow) - start]
      require ((toJson cold).compress == (toJson first).compress)
        "cold observed-semantic reuse changed the complete handoff"
      require ((← PageMap.pin (root / "db")).head == pinned.head &&
          (← runtimeCache.get).workspaces.isEmpty)
        "cold observed-semantic reuse recalculated/republished its completed result"
    require ((← calls) == before + 3)
      "a semantic cache hit skipped the current external provider observation"
    -- Neither an empty result nor its order can be inferred from an old
    -- observation. The executable, query and DB all remain unchanged here.
    answer []
    let changed ← run query
    let negative ← record query
    let negativeIdentity := ({durableRanking :=
      (← Store.searchDocuments (← PageMap.pin (root / "db"))).map (·.owner)} : IndexedSemanticNominations).memoIdentity
    require (negative.nominations == some negativeIdentity &&
        (← PageMap.pin (root / "db")).head != pinned.head)
      "changed external state reused its previous nomination instead of recomputing"
    let source ← PageMap.pin (root / "db")
    runtimeCache.set {}
    let expected ← computeGeneralAutomaticHandoff {selected with write := none}
      [some source] query [] false
    require ((toJson changed).compress == (toJson expected).compress)
      "observation-bound repair changed the full reference handoff"
    let forged := {negative with nominations := some [999999], response := "null"}
    DemandMemo.publish (← PageMap.pin (root / "db")) forged
    require ((← run query).isSome && (← record query).nominations == some negativeIdentity)
      "a differently bound optional record substituted its response for the current provider output"
    let emptyQuery := "truly_absent_observed_quartz99"
    require ((← run emptyQuery).isNone && (← record emptyQuery).nominations == some negativeIdentity)
      "a completed external negative observation was not persisted"
    let negativeHead := (← PageMap.pin (root / "db")).head
    require ((← run emptyQuery).isNone && (← PageMap.pin (root / "db")).head == negativeHead)
      "cold external negative reuse recalculated/republished its completed absence"
    let refreshed ← run query
    let dependencies ← record query
    let mut source ← PageMap.pin (root / "db")
    for i in [:DemandMemo.chainAllowance + 2] do
      let _ ← PageMap.withWriter source fun writer => do
        Store.putNat writer "memo:unrelated-observation-maintenance" i
        Store.writeChange writer ⟨[], [], false⟩
      source ← PageMap.pin (root / "db")
    require ((← DemandMemo.dependenciesAgree dependencies [root / "db"] [some source]) &&
        (toJson (← run query)).compress == (toJson refreshed).compress &&
        (← PageMap.pin (root / "db")).head == source.head)
      "unrelated maintenance invalidated the observed semantic request's actual dependencies"
    let added := OutcomeEdge.make owner.work (.text "alpha beta parser: new independent evidence") []
      (by simp) (by simp)
    let _ ← PageMap.withWriter source fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let id ← intern.root added.relation
      Store.writeChange writer ⟨[id], [], false⟩
    let updated ← PageMap.pin (root / "db")
    require (!(← DemandMemo.dependenciesAgree dependencies [root / "db"] [some updated]))
      "a new candidate/frequency/population reused its old completed semantic result"
    IO.FS.writeFile (provider / "response.json")
      (Json.mkObj [("related", toJson ([] : List Nat)), ("ranked", toJson ([0, 1] : List Nat)), ("evidence", .arr #[])]).compress
    let actual ← run query
    runtimeCache.set {}
    let expected ← computeGeneralAutomaticHandoff {selected with write := none}
      [some (← PageMap.pin (root / "db"))] query [] false
    require ((toJson actual).compress == (toJson expected).compress)
      "same external nominations hid new matching graph evidence"
    let stable ← record query
    IO.FS.writeFile (provider / "response.json")
      (Json.mkObj [("related", toJson ([] : List Nat)), ("ranked", toJson ([1, 0] : List Nat)), ("evidence", .arr #[])]).compress
    let reranked ← run query
    runtimeCache.set {}
    let rerankedReference ← computeGeneralAutomaticHandoff {selected with write := none}
      [some (← PageMap.pin (root / "db"))] query [] false
    let judgment := fun response => (response : Option Handoff).map fun handoff =>
      (handoff.completed, handoff.advisory, handoff.blocksCurrent,
        handoff.coveredFragments, handoff.localUnions)
    require ((← record query).nominations != stable.nominations &&
        (toJson reranked).compress == (toJson rerankedReference).compress &&
        (toJson reranked).compress != (toJson actual).compress &&
        judgment reranked == judgment actual)
      "changed evidence order reused the old observation, differed from the independent oracle or changed matching judgments"
    let stable ← record query
    IO.FS.writeFile (provider / "response.json") "{\"error\":\"fixture unavailable\"}"
    require ((← run query).any (fun h => h.reason == "search-incomplete") &&
        (← record query) == stable)
      "provider failure reused a prior success or persisted a pending response"
    -- These unrelated non-textual All/Union endpoints are actual persisted
    -- Values. Their bodies are necessary for the full reference computation,
    -- but not for ordering the numerical request or validating a demand hit.
    IO.FS.writeFile (provider / "response.json")
      (Json.mkObj [("related", toJson ([0] : List Nat)), ("ranked", toJson ([0, 1] : List Nat)), ("evidence", .arr #[])]).compress
    let largePath := root / "large-db"
    let largeFirst ← PageMap.create largePath
      (Persistence.valueToJson (.text "header-first-large")).compress
    let child := OutcomeEdge.make (.text "alpha beta parser child")
      (.text "alpha beta parser: child source evidence") [] (by simp) (by simp)
    let summary := OutcomeEdge.make (.text "alpha beta parser summary")
      (.text "alpha beta parser: summary source evidence") [] (by simp) (by simp)
    let opaqueLeft := Value.atom (.mk (Array.replicate (512 * 1024) (255 : UInt8)))
    let opaqueRight := Value.atom (.mk (Array.replicate (512 * 1024) (254 : UInt8)))
    let makeAll := fun (parent : Value) (children : List Value) =>
      if valid : children ≠ [] ∧ parent ∉ children then
        pure (AllEdge.make parent children valid.1 valid.2)
      else throw (IO.userError "invalid header-first All fixture")
    let ordered ← makeAll summary.work [child.work]
    let unrelated ← makeAll opaqueLeft [child.work]
    let _ ← PageMap.withWriter largeFirst fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let ids ← [child.relation, summary.relation, ordered.relation, unrelated.relation].mapM
        intern.root
      Store.writeChange writer ⟨ids, [], false⟩
    let largeSource ← PageMap.pin largePath
    let authority ← Store.authority largeSource
    let alias ← if safe : Value.sameExactFootprint opaqueLeft opaqueRight then
        pure (PersistentUnion.make authority opaqueLeft opaqueRight
          (Value.sameExactFootprint_sound safe)).edge
      else throw (IO.userError "invalid header-first opaque Union fixture")
    let _ ← PageMap.withWriter largeSource fun writer => do
      Store.addUnions ⟨writer, ← IO.mkRef {}⟩ [alias]
      Store.writeChange writer ⟨[], [], true⟩
    let largeSelected : Config.Selection := {selected with
      label := "header-first-large"
      read := [⟨"work", largePath⟩], write := some ⟨"work", largePath⟩}
    let nominationSource ← PageMap.pin largePath
    let some fromHeaders ← headerSemanticNominations nominationSource
        (selected.semanticMatcher.getD []) query |
      throw (IO.userError "header nomination fixture returned incomplete search")
    let headerRequest ← IO.FS.readFile (provider / "request.json")
    require ((← nominationSource.readBytes.get) < 128 * 1024)
      "numerical nomination hydrated unrelated All descendants"
    let fullSource ← PageMap.pin largePath
    let fullReader ← Store.NodeReader.new fullSource
    let some fromValues ← indexedSemanticNominations fullSource (← fullReader.topology)
        (selected.semanticMatcher.getD []) query |
      throw (IO.userError "full nomination fixture returned incomplete search")
    require (fromHeaders.durable == fromValues.durable &&
        fromHeaders.staged == fromValues.staged &&
        headerRequest == (← IO.FS.readFile (provider / "request.json")))
      "All headers changed provider corpus order, windows, anchors or nominees"
    runtimeCache.set {}
    let completed ← automaticHandoff largeSelected query [] false
    require (completed.any (fun h => h.reason != "search-incomplete" &&
        h.text.contains "summary source evidence"))
      "header-first fixture did not preserve summary-before-child selection"
    let referenceSource ← PageMap.pin largePath
    runtimeCache.set {}
    let reference ← computeGeneralAutomaticHandoff {largeSelected with write := none}
      [some referenceSource] query [] false
    let referenceBytes ← referenceSource.readBytes.get
    require ((toJson completed).compress == (toJson reference).compress &&
        referenceBytes > 1024 * 1024)
      "header-first result differs from the complete graph oracle or avoids no body reads"
    let largeRequest := demandRequest engine largeSelected query [] false none [] true true
    let stableHead := (← PageMap.pin largePath).head
    let mut hitReads : List Nat := []
    let mut hitTimes : List Nat := []
    let callsBefore ← calls
    for _ in [:3] do
      runtimeCache.set {}
      let snapshot ← PageMap.pin largePath
      let hit ← IO.mkRef false
      let reuse : SemanticReuse := fun nominations => do
        let found ← demandResponse? snapshot largeRequest [largePath] [some snapshot]
          (some nominations.memoIdentity) (fun _ => true)
        hit.set found.isSome
        pure found
      let start ← IO.monoNanosNow
      let actual ← computeAutomaticHandoff largeSelected [some snapshot] query [] false
        (reuseSemantic := reuse)
      let elapsed := (← IO.monoNanosNow) - start
      let bytes ← snapshot.readBytes.get
      require ((← hit.get) && (toJson actual).compress == (toJson completed).compress &&
          bytes < 128 * 1024 && (← PageMap.pin largePath).head == stableHead &&
          (← runtimeCache.get).workspaces.isEmpty)
        "production completed-demand validation restored/recalculated unrelated graph bodies"
      hitReads := hitReads ++ [bytes]
      hitTimes := hitTimes ++ [elapsed]
    require ((← calls) == callsBefore + 3)
      "header-first cold reuse omitted or duplicated the current provider observation"
    IO.println ((Json.mkObj [("kind", .str "header_first_semantic_reuse"),
      ("cold_reuse_ns", toJson hitTimes), ("cold_read_bytes", toJson hitReads),
      ("full_reference_read_bytes", toJson referenceBytes),
      ("unrelated_atom_bytes", toJson (1024 * 1024 : Nat)),
      ("generative_calls", toJson (0 : Nat))]).compress)
    IO.println ((Json.mkObj [("kind", .str "observed_semantic_demand"),
      ("cold_reuse_ns", toJson times), ("provider_calls", toJson (← calls)),
      ("generative_calls", toJson (0 : Nat))]).compress)
  finally runtimeCache.set previous
  IO.println "PASS current external observations, cold result reuse, changed/negative nominations, exact dependencies, new candidates, corrupt binding and pending rejection"

def readTraceIndex : IO Unit := do
  let observed : List PageMap.ReadObservation := [
    .point "absent" none, .point "present" (some "old".toUTF8),
    .point "present" (some "new".toUTF8), .range "a" "z" [],
    .range "a" "z" [("new", some "evidence".toUTF8)],
    .blob ⟨17, 5, PageMap.digest "first".toUTF8⟩,
    .blob ⟨17, 7, PageMap.digest "changed".toUTF8⟩]
  let collisions := PageMap.ObservationIndex.make (fun _ => 0) observed
  for operation in observed ++ [.point "another" none,
      .blob ⟨17, 9, PageMap.digest "different".toUTF8⟩,
      .range "a" "z" [("other", some "evidence".toUTF8)]] do
    require (collisions.contains operation == observed.contains operation)
      "a locator collision invented or lost a dependency"
  let points := (List.range 2048).map fun n =>
    PageMap.ReadObservation.point s!"frequency:{n}" none
  let huge := PageMap.ReadObservation.point "oversize-row" (some
    (String.ofList (List.replicate (PageMap.readTraceAllowance + 1) 'x')).toUTF8)
  for sequence in [observed, observed ++ observed.reverse, points ++ points.reverse ++ points,
      points ++ [huge] ++ observed, huge :: observed] do
    let actual := sequence.foldl PageMap.ReadTrace.add {}
    let expected := sequence.foldl PageMap.ReadSummary.step ([], 0, true)
    require (actual.summary == expected)
      "indexed capture changed complete ordered dependencies, byte accounting or overflow"
    require (actual.encodedBytes ≤ PageMap.readTraceAllowance)
      "indexed capture exceeded the existing dependency allowance"

/-- The body is larger than the dependency allowance. Capture and disk memo
roundtrip retain only its immutable references; verification still reads and
checks each bounded chunk, and rejects a physically damaged chunk. -/
def immutableDependencies : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-immutable-dependencies-20261007"
  let foreign ← PageMap.absolute ".lake/page-db-foreign-dependencies-20261007"
  for path in [root, foreign] do
    if ← path.pathExists then IO.FS.removeDirAll path
  let payload := (String.ofList (List.replicate 4096 'x')).toUTF8
  let append := fun (writer : PageMap.Writer) => do
    if positive : 0 < payload.size then
      if bounded : payload.size ≤ 4096 then writer.appendBlob payload positive bounded
      else throw (IO.userError "fixture chunk exceeds the native read budget")
    else throw (IO.userError "fixture chunk is empty")
  let build := fun (path : System.FilePath) => do
    let initial ← PageMap.create path "immutable-dependency-fixture"
    let (refs, _, _) ← PageMap.withWriter initial fun writer => do
      let mut refs := []
      for n in [:128] do
        let blob ← append writer
        refs := blob :: refs
        writer.put s!"memo:fixture:chunk:{n}" (some (PageMap.blobCodec.encode blob).toByteArray)
      Store.writeChange writer ⟨[], [], false⟩
      pure refs.reverse
    pure (refs, ← PageMap.pin path)
  let (refs, snapshot) ← build root
  snapshot.trace.set (some {})
  for blob in refs do
    require ((← snapshot.readBlob blob) == payload) "immutable dependency fixture read changed"
  let some trace ← snapshot.trace.get | throw (IO.userError "body read trace disappeared")
  snapshot.trace.set none
  require (trace.complete && trace.operations.length == 128 && trace.encodedBytes < 16384)
    "a 512KiB body disabled reuse or was copied into the dependency record"
  let record : DemandMemo.Record := ⟨"large-body-dependencies",
    [(root.normalize.toString, some snapshot.head)], "checked",
    some [trace.operations.reverse], none⟩
  require (DemandMemo.codec.encodedSize record < 16384)
    "the persisted dependency record reintroduced a body copy"
  DemandMemo.publish snapshot record
  let published ← PageMap.pin root
  require ((← DemandMemo.read published record.request) == some record &&
      (← DemandMemo.dependenciesAgree record [root] [some published]))
    "compact body dependencies were not persisted and reused through the production memo"
  let (foreignRefs, foreignSnapshot) ← build foreign
  require (foreignRefs == refs && foreignSnapshot.head.identity != snapshot.head.identity)
    "foreign reference fixture failed to create identical extents with a different identity"
  require ((← foreignSnapshot.verifyReads? snapshot.head trace.operations).isNone)
    "identical bytes and references in a foreign DB were granted the original identity"
  let some first := refs.head? | throw (IO.userError "empty reference fixture")
  let handle ← FileSystem.openAppend (PageMap.dataPath root published.head).toString
  let overwriteRejected ← try
      FileSystem.appendAt handle first.offset.toUInt64 payload
      pure false
    catch _ => pure true
  FileSystem.closeAppend handle
  require overwriteRejected "native append API overwrote a committed body reference"
  let failed ← try
      let _ : Unit × PageMap.Head × Nat ← PageMap.withWriter published fun writer => do
        let _ ← append writer
        throw (IO.userError "injected failure after body append")
      pure false
    catch _ => pure true
  require failed "uncommitted tail injection did not fail"
  let (_, _, _) ← PageMap.withWriter (← PageMap.pin root) fun writer => do
    writer.put "memo:fixture:recovered" (some "ok".toUTF8)
    Store.writeChange writer ⟨[], [], false⟩
  let mut recovered ← PageMap.pin root
  for n in [:DemandMemo.chainAllowance + 1] do
    let (_, _, _) ← PageMap.withWriter recovered fun writer => do
      Store.putNat writer "memo:fixture:unrelated" n
      Store.writeChange writer ⟨[], [], false⟩
    recovered ← PageMap.pin root
  require (!(← DemandMemo.agree recovered snapshot.head))
    "integrity fixture did not exceed the coarse graph-neutral chain"
  require ((← recovered.verifyReads? snapshot.head trace.operations).isSome &&
      (← DemandMemo.dependenciesAgree record [root] [some recovered]))
    "append or abandoned-tail recovery changed committed body dependencies"
  let path := PageMap.dataPath root recovered.head
  let intact ← IO.FS.readBinFile path
  try
    IO.FS.writeBinFile path (intact.set! first.offset 121)
    let corrupted ← try
        let _ ← recovered.verifyReads? snapshot.head trace.operations
        pure false
      catch _ => pure true
    require corrupted "unchanged descriptors concealed physical body corruption"
    let fineDependencyCorrupted ← try
        let _ ← DemandMemo.dependenciesAgree record [root] [some recovered]
        pure false
      catch _ => pure true
    require fineDependencyCorrupted "fine production dependency validation bypassed body corruption checks"
    IO.FS.writeBinFile path (intact.extract 0 first.offset)
    let truncated ← try
        let _ ← recovered.verifyReads? snapshot.head trace.operations
        pure false
      catch _ => pure true
    require truncated "unchanged descriptors concealed a truncated body"
  finally IO.FS.writeBinFile path intact
  require ((← recovered.verifyReads? snapshot.head trace.operations).isSome)
    "restored body no longer matched its immutable dependencies"
  IO.println ((Json.mkObj [("kind", .str "immutable_body_dependencies"),
    ("body_bytes", toJson (128 * 4096 : Nat)), ("chunks", toJson trace.operations.length),
    ("dependency_bytes", toJson trace.encodedBytes),
    ("persisted_record_bytes", toJson (DemandMemo.codec.encodedSize record)),
    ("generative_calls", toJson (0 : Nat))]).compress)

def payloadDependencies : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-payload-dependencies"
  let foreign ← PageMap.absolute ".lake/page-db-foreign-payload-dependencies"
  for path in [root, foreign] do
    if ← path.pathExists then IO.FS.removeDirAll path
  let bytes := ByteArray.mk (Array.replicate (2 * 1024 * 1024) (120 : UInt8))
  let build := fun path => do
    let first ← PageMap.create path "payload-domain-fixture"
    let (id, _, _) ← PageMap.withWriter first fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let id ← intern.root (.atom bytes)
      Store.writeChange writer ⟨[id], [], false⟩
      pure id
    pure (id, ← PageMap.pin path)
  let (id, source) ← build root
  source.trace.set (some {})
  let expected ← Store.readNode source source.get id
  let some expanded ← source.trace.get | throw (IO.userError "expanded payload trace disappeared")
  require (!expanded.complete) "large payload negative control did not exceed the unchanged 64KiB trace allowance"
  source.trace.set (some {})
  let reader ← Store.NodeReader.new source
  let actual ← reader.read id
  let some trace ← source.trace.get | throw (IO.userError "compact payload trace disappeared")
  source.trace.set none
  require (actual == expected && actual == .atom bytes) "grouped read changed complete original Atom bytes"
  require (trace.complete && trace.encodedBytes < 2048 &&
    trace.operations.any (fun observation => observation ==
      .payload (Store.key "body" id) bytes.size ((bytes.size + 4095) / 4096)))
    "production NodeReader enumerated body descriptors or lost its complete payload dependency"
  let record : DemandMemo.Record := ⟨"payload-domain-query",
    [(root.normalize.toString, some source.head)], "checked", some [trace.operations.reverse], none⟩
  require (DemandMemo.codec.encodedSize record < 4096) "payload dependency duplicated its original root/body"
  DemandMemo.publish source record
  let mut current ← PageMap.pin root
  for n in [:DemandMemo.chainAllowance + 1] do
    let _ ← PageMap.withWriter current fun writer => do
      Store.putNat writer "memo:unrelated-payload" n
      Store.writeChange writer ⟨[], [], false⟩
    current ← PageMap.pin root
  let some saved ← DemandMemo.read current record.request |
    throw (IO.userError "persisted whole-payload dependency was not readable from a cold snapshot")
  require (saved == record) "whole-payload dependency changed during durable codec roundtrip"
  let record := saved
  require (!(← DemandMemo.agree current source.head) &&
      (← DemandMemo.dependenciesAgree record [root] [some current]))
    "complete payload dependencies were not reconstructed from the saved root beyond the neutral history"
  let (_, foreignSnapshot) ← build foreign
  require ((← foreignSnapshot.verifyReads? source.head trace.operations).isNone)
    "foreign DB accepted an identical payload read program"
  let sizeKey := Store.key "body" id
  let _ ← PageMap.withWriter current fun writer => do
    Store.putNat writer sizeKey (bytes.size - 1)
    Store.writeChange writer ⟨[], [], true⟩
  current ← PageMap.pin root
  require (!(← DemandMemo.dependenciesAgree record [root] [some current]))
    "changed payload size reused the previous complete read domain"
  let _ ← PageMap.withWriter current fun writer => do
    Store.putNat writer sizeKey bytes.size
    Store.writeChange writer ⟨[], [], true⟩
  current ← PageMap.pin root
  require (← DemandMemo.dependenciesAgree record [root] [some current])
    "restored payload size did not recover its original complete read domain"
  let firstKey := Store.key (Store.key "body" id) 0
  let some encoded ← current.get firstKey | throw (IO.userError "missing first payload descriptor")
  let first ← IO.ofExcept (PageMap.decodeBlob encoded)
  let _ ← PageMap.withWriter current fun writer => do
    writer.put firstKey none
    Store.writeChange writer ⟨[], [], true⟩
  current ← PageMap.pin root
  require (!(← DemandMemo.dependenciesAgree record [root] [some current]))
    "deleted payload descriptor did not invalidate the whole-read program"
  let _ ← PageMap.withWriter current fun writer => do
    writer.put firstKey (some encoded)
    Store.writeChange writer ⟨[], [], true⟩
  current ← PageMap.pin root
  require (← DemandMemo.dependenciesAgree record [root] [some current])
    "restored immutable descriptor did not recover payload reuse"
  let path := PageMap.dataPath root current.head
  let intact ← IO.FS.readBinFile path
  try
    IO.FS.writeBinFile path (intact.set! first.offset 121)
    let rejected ← try
      let _ ← DemandMemo.dependenciesAgree record [root] [some current]
      pure false
      catch _ => pure true
    require rejected "payload grouping concealed physical body corruption"
    IO.FS.writeBinFile path (intact.extract 0 first.offset)
    let rejected ← try
      let _ ← current.verifyReads? source.head trace.operations
      pure false
      catch _ => pure true
    require rejected "payload grouping concealed truncation"
  finally IO.FS.writeBinFile path intact
  require (← DemandMemo.dependenciesAgree record [root] [some current])
    "restored bytes no longer matched the saved payload domain"
  -- Validate each position once and stop immediately at a changed descriptor.
  for stop in [none, some 0, some 17, some 31] do
    let visits ← IO.mkRef ([] : List Nat)
    let accepted ← PageMap.checkPayloadChunks (fun n => do
      visits.modify (n :: ·)
      pure (stop != some n)) 0 32
    let count := stop.map (· + 1) |>.getD 32
    require ((← visits.get).reverse == List.range count && accepted == stop.isNone)
      "streamed payload verification skipped, repeated or continued past a changed chunk"
  IO.println ((Json.mkObj [("kind", .str "complete_payload_dependencies"),
    ("body_bytes", toJson bytes.size), ("dependency_bytes", toJson trace.encodedBytes),
    ("persisted_record_bytes", toJson (DemandMemo.codec.encodedSize record)),
    ("old_trace_complete", toJson expanded.complete), ("generative_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS compact complete payload programs: full Atom equality, unchanged trace allowance, native NodeReader, old root reconstruction, cold persisted reuse, foreign DB, descriptor deletion/restoration, corruption/truncation and complete ordered short-circuit validation"

def bodyPrefixDependencies : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-body-prefix"
  if ← root.pathExists then IO.FS.removeDirAll root
  let bytes := ByteArray.mk (Array.replicate (2 * 1024 * 1024) (120 : UInt8))
  let count := (bytes.size + 4095) / 4096
  let build := fun (path : System.FilePath) (body : ByteArray) => do
    let first ← PageMap.create path "body-prefix-fixture"
    let (id, _, _) ← PageMap.withWriter first fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let id ← intern.root (.atom body)
      Store.writeChange writer ⟨[id], [], false⟩
      pure id
    pure (id, ← PageMap.pin path)
  let leftPath := root / "left"
  let (leftId, left) ← build leftPath bytes
  let mut metrics : List Json := []
  for stop in [none, some 0, some 256, some 511] do
    let name := stop.map toString |>.getD "equal"
    let rightPath := root / name
    let changed := stop.map (fun chunk => bytes.set! (chunk * 4096) 121) |>.getD bytes
    let (rightId, right) ← build rightPath changed
    let checked := stop.map (· + 1) |>.getD count
    left.trace.set (some {})
    right.trace.set (some {})
    left.readBytes.set 0
    right.readBytes.set 0
    let accepted ← Store.bodiesEqual left leftId right rightId
    let some first ← left.trace.get | throw (IO.userError "left comparison trace disappeared")
    let some second ← right.trace.get | throw (IO.userError "right comparison trace disappeared")
    left.trace.set none
    right.trace.set none
    let readBytes := (← left.readBytes.get) + (← right.readBytes.get)
    require (accepted == (bytes == changed)) "streamed comparison differs from full original-byte equality"
    for (trace, id) in [(first, leftId), (second, rightId)] do
      require (trace.complete && trace.encodedBytes < 1024 &&
          trace.operations.contains (.payload (Store.key "body" id) bytes.size checked) &&
          trace.operations.length == 2)
        "comparison dependency grew with body size, omitted its size, or included an unread suffix"
    if checked == 1 then
      require (readBytes < 256 * 1024) "first-chunk mismatch read the large remaining body"
    let record : DemandMemo.Record := ⟨"body-prefix-" ++ name,
      [(leftPath.normalize.toString, some left.head), (rightPath.normalize.toString, some right.head)],
      if accepted then "equal" else "different",
      some [first.operations.reverse, second.operations.reverse], none⟩
    require (DemandMemo.codec.encodedSize record < 2048) "comparison memo duplicated body or descriptors"
    DemandMemo.publish left record
    let mut current ← PageMap.pin leftPath
    for n in [:DemandMemo.chainAllowance + 1] do
      let _ ← PageMap.withWriter current fun writer => do
        Store.putNat writer "memo:prefix-neutral" n
        Store.writeChange writer ⟨[], [], false⟩
      current ← PageMap.pin leftPath
    let some saved ← DemandMemo.read current record.request |
      throw (IO.userError "cold comparison memo was not readable")
    require (saved == record && !(← DemandMemo.agree current left.head) &&
        (← DemandMemo.dependenciesAgree saved [leftPath, rightPath] [some current, some right]))
      "persisted comparison prefix was lost beyond the neutral publication chain"
    require ((← right.verifyReads? left.head first.operations).isNone)
      "foreign DB accepted another comparison source's fixed root"
    require ((← current.verifyReads? left.head
        [.payload (Store.key "body" leftId) bytes.size (count + 1)]).isNone)
      "out-of-body prefix reached descriptor hydration"
    let observedKey := Store.key (Store.key "body" leftId) (checked - 1)
    let some original ← current.get observedKey | throw (IO.userError "missing observed descriptor")
    let originalRef ← IO.ofExcept (PageMap.decodeBlob original)
    let replacement := ByteArray.mk (Array.replicate 4096 (122 : UInt8))
    if checked < count then
      let suffixKey := Store.key (Store.key "body" leftId) (count - 1)
      let some suffix ← current.get suffixKey | throw (IO.userError "missing unread suffix descriptor")
      let _ ← PageMap.withWriter current fun writer => do
        writer.put suffixKey none
        Store.writeChange writer ⟨[], [], true⟩
      current ← PageMap.pin leftPath
      require ((← DemandMemo.dependenciesAgree saved [leftPath, rightPath] [some current, some right]) &&
          !(← Store.bodiesEqual current leftId right rightId))
        "unread suffix invalidated a witnessed earlier mismatch or fresh comparison read that suffix"
      let _ ← PageMap.withWriter current fun writer => do
        writer.put suffixKey (some suffix)
        Store.writeChange writer ⟨[], [], true⟩
      current ← PageMap.pin leftPath
    let _ ← PageMap.withWriter current fun writer => do
      let ref ← if positive : 0 < replacement.size then
        if bounded : replacement.size ≤ 4096 then writer.appendBlob replacement positive bounded
        else throw (IO.userError "oversized test replacement")
        else throw (IO.userError "empty test replacement")
      writer.put observedKey (some (PageMap.blobCodec.encode ref).toByteArray)
      Store.writeChange writer ⟨[], [], true⟩
    current ← PageMap.pin leftPath
    require (!(← DemandMemo.dependenciesAgree saved [leftPath, rightPath] [some current, some right]))
      "changed observed descriptor reused the saved comparison"
    let _ ← PageMap.withWriter current fun writer => do
      writer.put observedKey none
      Store.writeChange writer ⟨[], [], true⟩
    current ← PageMap.pin leftPath
    require (!(← DemandMemo.dependenciesAgree saved [leftPath, rightPath] [some current, some right]))
      "deleted observed descriptor reused the saved comparison"
    let _ ← PageMap.withWriter current fun writer => do
      writer.put observedKey (some original)
      Store.writeChange writer ⟨[], [], true⟩
    current ← PageMap.pin leftPath
    require (← DemandMemo.dependenciesAgree saved [leftPath, rightPath] [some current, some right])
      "restored immutable prefix did not recover durable comparison reuse"
    let path := PageMap.dataPath leftPath current.head
    let intact ← IO.FS.readBinFile path
    try
      IO.FS.writeBinFile path (intact.set! originalRef.offset 123)
      let rejected ← try
        let _ ← DemandMemo.dependenciesAgree saved [leftPath, rightPath] [some current, some right]
        pure false
        catch _ => pure true
      require rejected "prefix capture concealed corruption in a consumed chunk"
      IO.FS.writeBinFile path (intact.extract 0 originalRef.offset)
      let rejected ← try
        let _ ← current.verifyReads? left.head first.operations
        pure false
        catch _ => pure true
      require rejected "prefix capture concealed truncation in a consumed chunk"
    finally IO.FS.writeBinFile path intact
    require (← DemandMemo.dependenciesAgree saved [leftPath, rightPath] [some current, some right])
      "restored physical bytes no longer matched the saved comparison prefix"
    metrics := metrics ++ [Json.mkObj [("mismatch_chunk", toJson stop),
      ("consumed_chunks", toJson checked), ("read_bytes", toJson readBytes),
      ("dependency_bytes", toJson (first.encodedBytes + second.encodedBytes)),
      ("memo_bytes", toJson (DemandMemo.codec.encodedSize saved))]]
  -- Production recursion must remain a scalar tail loop, including large
  -- domains and early rejection. No position/descriptor list is constructed.
  for stop in [none, some 0, some 17, some 31] do
    let visits ← IO.mkRef (0 : Nat)
    let result ← PageMap.checkPrefix (fun position => do
      let visited ← visits.get
      require (position == 5 + visited) "prefix checker skipped or repeated a position"
      visits.modify (· + 1)
      pure (stop != some visited)) 5 500000
    let expected := stop.map (· + 1) |>.getD 500000
    require (result.accepted == stop.isNone && result.checked == expected && (← visits.get) == expected)
      "prefix checker consumed the wrong domain or continued past a rejection"
  let called ← IO.mkRef false
  let empty ← PageMap.checkPrefix (fun _ => do called.set true; pure false) 7 0
  require (empty.accepted && empty.checked == 0 && !(← called.get)) "empty comparison invoked a callback"
  IO.println ((Json.mkObj [("kind", .str "persisted_comparison_prefix"),
    ("body_bytes_per_source", toJson bytes.size), ("cases", toJson metrics),
    ("large_scalar_domain", toJson (500000 : Nat)), ("generative_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS compact consumed comparison prefixes: complete original-byte oracle, cold persisted two-source reuse, first/middle/last mismatch, unread suffix, foreign root, oversized domain, changed/deleted descriptors, corruption/truncation and scalar tail traversal"

def readDependencies : IO Unit := do
  readTraceIndex
  immutableDependencies
  let root ← PageMap.absolute ".lake/page-db-read-dependencies-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let first ← PageMap.create root (Persistence.valueToJson (.text "read-dependencies-fixture")).compress
  first.trace.set (some {})
  let _ ← first.get "memo:missing-term"
  let _ ← first.foldRange ⟨"memo:posting:term:", "memo:posting:term;"⟩
    (fun rows row => pure (row :: rows)) ([] : List PageMap.Row)
  let some negative ← first.trace.get | throw (IO.userError "negative trace was not captured")
  require (negative.complete && negative.operations.length == 2)
    "absent point or complete empty candidate range was omitted"
  first.trace.set none
  require ((← first.verifyReads? first.head negative.operations).isSome) "unchanged absence was rejected"
  let _ ← PageMap.withWriter first fun writer => do
    writer.put "memo:posting:term:1" (some "new owner".toUTF8)
    Store.writeChange writer ⟨[], [], false⟩
  let added ← PageMap.pin root
  require ((← added.verifyReads? first.head negative.operations).isNone)
    "a new match inside a previously empty posting interval reused absence"
  let _ ← PageMap.withWriter added fun writer => do
    writer.put "memo:missing-term" (some "new dictionary member".toUTF8)
    Store.writeChange writer ⟨[], [], false⟩
  require ((← (← PageMap.pin root).verifyReads? first.head [.point "memo:missing-term" none]).isNone)
    "a newly present dictionary key reused a recorded miss"
  let snap ← PageMap.pin root
  snap.trace.set (some {})
  let huge := (String.ofList (List.replicate (PageMap.readTraceAllowance + 1) 'x')).toUTF8
  snap.observe (.point "oversize-row" (some huge))
  snap.observe (.point "small" none)
  let some overflow ← snap.trace.get | throw (IO.userError "overflow trace was lost")
  require (!overflow.complete && overflow.operations.isEmpty && overflow.encodedBytes == 0)
    "an over-budget trace retained memory or regained a reuse certificate"
  snap.trace.set none
  let related := OutcomeEdge.make (.text "check alpha_beta parser")
    (.text "alpha_beta parser checked in the actual source") [] (by simp) (by simp)
  let oversized := OutcomeEdge.make related.work
    (.text ("alpha_beta parser: recorded source dump\n" ++
      String.ofList (List.replicate (96 * 1024) 'z'))) [] (by simp) (by simp)
  let _ ← PageMap.withWriter snap fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← [oversized.relation, related.relation].mapM intern.root
    Store.writeChange writer ⟨ids, [], false⟩
  let selection : Config.Selection := {
    label := "read-dependency", semanticMatcher := none
    read := [⟨"work", root⟩], write := some ⟨"work", root⟩, handoffChars := 24000 }
  let prior ← runtimeCache.get
  try
    runtimeCache.set {}
    let result ← automaticHandoff selection "check alpha_beta parser" [] false
    require result.isSome "read-dependent production search did not return evidence"
    let original ← PageMap.pin root
    let engine ← FileSystem.readVersion (← FileSystem.openRead (← IO.appPath).toString)
    let request := demandRequest engine selection "check alpha_beta parser" [] false none [] true true
    let some record ← DemandMemo.read original request |
      throw (IO.userError "production search did not persist its read dependency record")
    let some reads := record.reads | throw (IO.userError "indexed production search lost its complete read trace")
    require (reads.length == 1 && !reads.flatten.isEmpty)
      "a result without captured source reads was granted fine dependency reuse"
    let bodyBytes := reads.flatten.foldl (fun total observation =>
      match observation with
      | .blob ref => total + ref.bytes
      | .payload _ bytes chunks => total + min bytes (chunks * 4096)
      | _ => total) 0
    require (bodyBytes > PageMap.readTraceAllowance)
      "large automatic-search fixture did not actually capture more than 64KiB of body reads"
    let mut current := original
    for i in [:DemandMemo.chainAllowance + 2] do
      let _ ← PageMap.withWriter current fun writer => do
        Store.putNat writer "memo:unrelated-maintenance" i
        Store.writeChange writer ⟨[], [], false⟩
      current ← PageMap.pin root
    require (!(← DemandMemo.agree current original.head) &&
      (← DemandMemo.dependenciesAgree record [root] [some current]))
      "unchanged actual dependencies still required the entire publication history"
    runtimeCache.set {}
    let reused ← automaticHandoff selection "check alpha_beta parser" [] false
    require ((toJson reused).compress == (toJson result).compress &&
      (← PageMap.pin root).head == current.head)
      "cold dependency reuse recalculated/republished or changed the production result"
    let addedOwner := OutcomeEdge.make related.work
      (.text "alpha_beta parser: newly obtained evidence") [] (by simp) (by simp)
    let _ ← PageMap.withWriter current fun writer => do
      let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
      let id ← intern.root addedOwner.relation
      Store.writeChange writer ⟨[id], [], false⟩
    let changed ← PageMap.pin root
    require (!(← DemandMemo.dependenciesAgree record [root] [some changed]))
      "new candidate membership/population/frequency reused a stale answer"
    runtimeCache.set {}
    let repaired ← automaticHandoff selection "check alpha_beta parser" [] false
    runtimeCache.set {}
    let expected ← computeGeneralAutomaticHandoff selection [some changed] "check alpha_beta parser" [] false
    require ((toJson repaired).compress == (toJson expected).compress)
      "read dependency repair changed full reference handoff"
  finally runtimeCache.set prior
  IO.println "PASS production persisted read domains, cold demand reuse beyond publication history, negative/new candidates, exact interval streaming, payload validation, bounded trace overflow and full reference repair"

def publicationSeal : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-publication-seal-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let first ← PageMap.create root (Persistence.valueToJson (.text "publication-seal-fixture")).compress
  for flushed in [false, true] do
    let rejected ← try
      let _ ← PageMap.withWriter first fun writer => do
        Store.putNat writer "candidates" 999
        Store.putNat writer "memo:attempt" 1
        if flushed then writer.flush
        Store.writeChange writer ⟨[], [], false⟩
      pure false
    catch error => pure ((toString error).contains "empty graph delta")
    require (rejected && (← PageMap.pin root).head == first.head)
      "a false empty delta published authoritative writes, including flushed pages"
  let (_, neutral, _) ← PageMap.withWriter first fun writer => do
    Store.putNat writer "memo:checked" 1
    Store.writeChange writer ⟨[], [], false⟩
    for name in ["candidates", "memo:late", Store.key "change" first.head.revision] do
      let rejected ← try writer.put name (some "invalid".toUTF8); pure false
        catch error => pure ((toString error).contains "journal was sealed")
      require rejected "a late edit changed the already-declared publication"
    let twice ← try Store.writeChange writer ⟨[], [], false⟩; pure false
      catch error => pure ((toString error).contains "already sealed")
    require twice "one batch published two contradictory change declarations"
  let next ← PageMap.pin root
  require (next.head == neutral && (← Store.getNat next.get "candidates") == 0 &&
      (← next.get "memo:late").isNone && (← DemandMemo.agree next first.head))
    "a sealed derived publication changed source data or broke neutral-chain agreement"
  let owner := OutcomeEdge.make (.text "checked work") (.text "recorded evidence") [] (by simp) (by simp)
  let (_, changed, _) ← PageMap.withWriter next fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let id ← intern.root owner.relation
    Store.writeChange writer ⟨[id], [], false⟩
  let changedSnapshot ← PageMap.pin root
  require (changedSnapshot.head == changed && !(← DemandMemo.agree changedSnapshot first.head) &&
      (← Store.materialize changedSnapshot).values == [owner.relation])
    "checked publication rejected a real delta or reused prior negative membership"
  IO.println "PASS actual neutral-write gate, flushed edits, post-seal mutation rejection, one declaration, recovery and real-change invalidation"

def chunkDelta : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-chunk-delta-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let first ← PageMap.create root "chunk-delta-fixture"
  let original := (List.range 20).foldl (fun bytes n => bytes ++
    (String.ofList (List.replicate 4096 (Char.ofNat (97 + n)))).toUTF8) ByteArray.empty
  let (_, initial, initialBytes) ← PageMap.withWriter first fun writer =>
    Store.putChunks writer "payload" 0 original
  let first ← PageMap.pin root
  let (_, same, duplicateBytes) ← PageMap.withWriter first fun writer =>
    Store.putChunks writer "payload" 0 original
  require (same == initial && duplicateBytes == 0)
    "identical chunk publication recopied its immutable extents"
  let changed := original.extract 0 (13 * 4096) ++
    (String.ofList (List.replicate 4096 '!')).toUTF8 ++ original.extract (14 * 4096) original.size
  let nominated : PageMap.Blob := ⟨0, 4096, PageMap.digest (changed.extract 0 4096)⟩
  require ((Store.retainChunk? nominated "different".toUTF8 (changed.extract 0 4096)).isNone)
    "a digest nomination substituted different bytes for a requested chunk"
  let (_, updated, changedBytes) ← PageMap.withWriter first fun writer =>
    Store.putChunks writer "payload" 0 changed
  let second ← PageMap.pin root
  require (second.head == updated && (← Store.readChunks second second.get "payload" 0) == changed &&
    (← Store.readChunks first first.get "payload" 0) == original)
    "chunk delta changed bytes or mixed fixed snapshots"
  require (changedBytes < initialBytes / 4)
    "one changed 4KiB chunk recopied most of an 80KiB body"
  IO.println ((Json.mkObj [("kind", .str "chunk_delta"),
    ("initial_bytes", toJson initialBytes), ("changed_bytes", toJson changedBytes),
    ("duplicate_bytes", toJson duplicateBytes)]).compress)
  IO.println "PASS exact unchanged-chunk reuse, single-chunk update and fixed snapshot isolation"

def saturationMemo : IO Unit := do
  let a := Value.text "alpha dependency"
  let b := Value.text "beta dependency"
  let c := Value.text "corrected dependency"
  let unary := fun value => Value.applyList .occurrence [Ref.semantic value]
  let outer := fun value => Value.applyList .occurrence
    [Ref.semantic value, Ref.semantic (.text "nested context")]
  let payload := Value.text (String.ofList (List.replicate (512 * 1024) 'x'))
  let exact := fun value => Value.applyList .occurrence [Ref.semantic value, Ref.exact payload]
  let values := [a, b, c, unary a, unary b, outer (unary a), outer (unary b), exact a, exact b]
  let edge : UnionEdge := ⟨a, b, .run (.text "demand"), by intro _; rfl⟩
  let built := QuotientBuilder.plannedBuild? values [] [edge] none
  let some quotient := built.quotient | throw (IO.userError "general quotient fixture failed")
  require (quotient.toEquality.same (outer (unary a)) (outer (unary b)))
    "the executed producer did not saturate nested application equality"
  let some plan := built.plan | throw (IO.userError "executed general build did not retain its join generation")
  let basis := SaturationMemo.Basis.make values
  let saved := SaturationMemo.capturePlan basis plan
  require (!saved.isEmpty && SaturationMemo.codec.encodedSize saved < 1024)
    "join checkpoint copied a 512KiB Exact body instead of compact references"
  let some restored := SaturationMemo.restore basis saved |
    throw (IO.userError "current complete join hints could not be certified")
  require (decide (restored.rows = plan.rows) && restored.script.instructions == plan.script.instructions)
    "saving the executed generation changed its ordered dependencies or join instructions"
  let warm := QuotientBuilder.CongruenceMemo.prepareScript (some restored) plan.rows
  require (warm.reused == saved.length && warm.computed == 0)
    "restored unchanged dependencies rediscovered their congruence joins"
  -- A checked view can carry a stale acceleration plan, but the actual
  -- controller must advance it through today's producer before publishing.
  -- Recalling the initial provider for the final view would retain this old
  -- generation and fail the comparison below.
  let staleEdge : UnionEdge := ⟨c, b, .run (.text "old demand"), by intro _; rfl⟩
  let stale := QuotientBuilder.plannedBuild? [unary c, outer (unary c), exact c] [staleEdge] [] none
  let some stalePlan := stale.plan | throw (IO.userError "stale generation fixture failed")
  let firstProvider : IncrementalQuotient.ViewProvider := fun graph roots persistent runLocal index =>
    {val := IncrementalQuotient.make? graph roots persistent runLocal index,
     property := rfl, plan := some stalePlan}
  let structured := OutcomeEdge.make (outer (unary b)) (.text "original structured evidence") []
    (by simp) (by simp)
  let observed ← IO.mkRef (none : Option (List Value × List UnionEdge × QuotientBuilder.CongruenceMemo.Entry))
  let current := "unmatched generation control"
  let advanced ← Matcher.discoverUsingM? () [] (fun _ => [structured])
    (fun _ => values) (fun _ _ => none) (fun state _ _ => pure (state, []))
    (.text current) [edge] current 2 true firstProvider (fun _ _ => pure ())
    (fun roots view plan => observed.set (plan.map fun plan => (roots, view.localUnions, plan)))
  require advanced.isSome "generation propagation changed discovery acceptance"
  let some (finalRoots, finalLocal, finalPlan) ← observed.get |
    throw (IO.userError "the actual controller did not publish its final generation")
  let expected := QuotientBuilder.plannedBuild? finalRoots [edge] finalLocal (some stalePlan)
  let some expectedPlan := expected.plan | throw (IO.userError "advanced generation fixture failed")
  require (decide (finalPlan.rows = expectedPlan.rows) &&
    finalPlan.script.instructions == expectedPlan.script.instructions &&
    decide (finalPlan.rows ≠ stalePlan.rows))
    "the final observer received the stale provider plan instead of today's repaired generation"
  for altered in [saved.map (fun hint => {hint with prior := some 0}),
      saved.map (fun hint => {hint with source := 10^12}),
      saved.map (fun hint => {hint with operator := 99}),
      saved.map (fun hint => {hint with references := [(99, 0)]})] do
    require (SaturationMemo.restore basis altered).isNone
      "malformed join hints acquired a producer certificate"
  for (changed, edges) in [(values, [edge]), (values, []), (values.reverse, [edge]),
      ([a, b, c, unary c, unary b, outer (unary c), outer (unary b), exact c, exact b], [edge]),
      ([a, c, unary a, unary c, outer (unary a), exact a], [edge]),
      (values ++ [unary c], [edge, edge])] do
    let changedBasis := SaturationMemo.Basis.make changed
    let repaired := QuotientBuilder.plannedBuild? changed [] edges
      (SaturationMemo.restore changedBasis saved)
    let full := QuotientBuilder.build? changed [] edges
    require (repaired.quotient.isSome == full.isSome) "restored plan changed acceptance"
    if let (some repaired, some full) := (repaired.quotient, full) then
      require (changed.all fun value => repaired.canonical value == full.canonical value)
        "retraction, correction, order change or new dependency retained old equality"
  let root ← PageMap.absolute ".lake/page-db-saturation-memo-20261006"
  if ← root.pathExists then IO.FS.removeDirAll root
  let _ ← Persistence.create root
  let initial ← PageMap.pin root
  let before ← Store.materialize initial
  SaturationMemo.publish root saved
  let published ← PageMap.pin root
  require ((← SaturationMemo.read published) == saved)
    "cold DB reader did not recover compact join hints"
  let after ← Store.revise published initial.head before
  require (equalGraph after {before with revision := published.head.revision} &&
      equalGraph after (← Store.materialize published))
    "join metadata changed source values, authority or Unions"
  SaturationMemo.publish root saved
  require ((← PageMap.pin root).head == published.head)
    "identical join metadata appended another publication"
  let started ← IO.monoNanosNow
  let (_, unchanged, bytes) ← PageMap.withWriter published fun _ => do
    let rejected ← try SaturationMemo.publish root saved; pure false catch _ => pure true
    require rejected "optional join metadata entered or waited behind a held writer"
  require (unchanged == published.head && bytes == 0 && (← IO.monoNanosNow) - started < 1000000000)
    "busy join metadata changed the graph or waited a second"
  let (_, _, _) ← PageMap.withWriter published fun writer => do
    Store.putNat writer (Store.key SaturationMemo.row 0) (10^12)
    Store.writeChange writer ⟨[], [], false⟩
  let corrupt ← PageMap.pin root
  let rejected ← try let _ ← SaturationMemo.read corrupt; pure false catch _ => pure true
  require rejected "corrupt join payload counter reached unbounded chunk hydration"
  SaturationMemo.publish root saved
  require ((← SaturationMemo.read (← PageMap.pin root)) == saved)
    "optional join metadata did not recover after corrupt counters"
  let query := "inspect alpha verified dependency"
  let makeOwner := fun work result => OutcomeEdge.make work (.text result) [] (by simp) (by simp)
  let nested := makeOwner (outer (unary b)) "nested verified old evidence"
  let corrected := makeOwner (outer (unary b)) "nested corrected current evidence"
  let fresh := makeOwner (outer (unary a)) "new matching source evidence"
  let direct := makeOwner (.text query) "original verified alpha evidence"
  let directCorrected := makeOwner (.text query) "corrected verified alpha evidence"
  let pinned := makeOwner (exact a) "Exact provenance stays separate"
  let authority ← Store.authority (← PageMap.pin root)
  let join := fun left right =>
    if exact : Value.sameExactFootprint left right then
      some (PersistentUnion.make authority left right (Value.sameExactFootprint_sound exact))
    else none
  let ab := (join a b).toList
  let inquiry := (join (.text query) (outer (unary a))).toList
  let selection : Config.Selection := {
    label := "general-saturation", semanticMatcher := none
    read := [⟨"work", root⟩], write := some ⟨"work", root⟩, handoffChars := 24000 }
  let previousRuntime ← runtimeCache.get
  let mut nonempty := 0
  let mut restoredQueries := 0
  let mut comparisons := 0
  let mut deliveries := 0
  let mut previousIds : List Nat := []
  let mut previousEdges : List UnionEdge := []
  try
    for (owners, unions) in [([nested, pinned, direct], ab ++ inquiry),
        ([nested, pinned, direct], ab ++ inquiry), ([nested, pinned, direct], inquiry),
        ([nested, pinned, fresh, direct], inquiry),
        ([corrected, pinned, fresh, directCorrected], ab ++ inquiry),
        ([fresh, pinned, directCorrected], inquiry), ([fresh, pinned], []),
        ([nested, pinned, direct], ab ++ inquiry)] do
      let roots := owners.map (·.relation)
      let desired ← if valid : roots.all Relation.wellFormed then
        pure ({ Graph.empty authority with
          values := roots
          unions := unions
          values_wellFormed := fun value member => (List.all_eq_true.mp valid) value member } : Graph)
        else throw (IO.userError "invalid general saturation roots")
      -- Exercise the normal retract/add commit API. Administrative full
      -- replacement intentionally rejects reordering retained root ordinals.
      let snapshot ← PageMap.pin root
      let retiring ← previousEdges.mapM fun edge => do
        let some located ← Store.locateUnion? snapshot (Store.unionDisplayKey edge.left edge.right) |
          throw (IO.userError "retiring general Union disappeared")
        pure located
      let (nextIds, _, _) ← PageMap.withWriter snapshot fun writer => do
        for id in previousIds do Store.removeRoot writer id
        for edge in retiring do Store.removeUnion writer edge
        let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
        let ids ← desired.values.mapM intern.root
        Store.addUnions intern (desired.unions.map (·.edge))
        Store.writeChange writer ⟨ids, previousIds, true⟩
        pure ids
      previousIds := nextIds
      previousEdges := desired.unions.map (·.edge)
      runtimeCache.set {}
      let expected ← computeGeneralAutomaticHandoff {selection with write := none}
        [some (← PageMap.pin root)] query [] false
      runtimeCache.set {}
      let actual ← automaticHandoff selection query [] false
      if actual.isSome then deliveries := deliveries + 1
      require ((toJson actual).compress == (toJson expected).compress &&
          (← runtimeCache.get).workspaces.isEmpty)
        "cold production general saturation changed complete ordered handoff"
      let persisted ← SaturationMemo.read (← PageMap.pin root)
      if !persisted.isEmpty then nonempty := nonempty + 1
      comparisons := comparisons + 1
      runtimeCache.set {}
      let cold ← computeAutomaticHandoff selection [some (← PageMap.pin root)] query [] false
        none [] true true [] persisted
      require ((toJson cold).compress == (toJson expected).compress &&
          (← runtimeCache.get).workspaces.isEmpty)
        "reopened persisted plan changed the complete handoff"
      if !persisted.isEmpty then restoredQueries := restoredQueries + 1
      comparisons := comparisons + 1
      -- No whole-result memo may hide corrupt hint consumption.
      SaturationMemo.publish root (persisted.map fun hint => {hint with prior := some 0})
      runtimeCache.set {}
      let malformedHints ← SaturationMemo.read (← PageMap.pin root)
      let malformed ← computeAutomaticHandoff selection [some (← PageMap.pin root)] query [] false
        none [] true true [] malformedHints
      require ((toJson malformed).compress == (toJson expected).compress &&
          (← runtimeCache.get).workspaces.isEmpty)
        "corrupt persisted join instructions changed production evidence"
      comparisons := comparisons + 1
    require (nonempty > 0) "general production search never published a join checkpoint"
    require (deliveries > 0 && deliveries < 8)
      "general replay comparisons did not exercise both real deliveries and owner retraction"
    require (restoredQueries > 0) "cold production controller never consumed a restored join plan"
    -- Unpublished run-local evidence must not escape into shared memo rows.
    let old ← SaturationMemo.read (← PageMap.pin root)
    runtimeCache.set {}
    let _ ← computeAutomaticHandoff selection [some (← PageMap.pin root)] query [] false
      none [corrected.relation] true
    require ((← SaturationMemo.read (← PageMap.pin root)) == old)
      "staged owner dependencies were published as shared join evidence"
  finally runtimeCache.set previousRuntime
  IO.println ((Json.mkObj [("kind", .str "persistent_general_saturation"),
    ("checkpoint_bytes", toJson (SaturationMemo.codec.encodedSize saved)),
    ("exact_payload_bytes", toJson payload.structuralSize),
    ("unchanged_join_rows_reused", toJson warm.reused),
    ("unchanged_join_rows_computed", toJson warm.computed),
    ("controller_generation_rows", toJson finalPlan.rows.length),
    ("handoff_comparisons", toJson comparisons), ("generative_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS persistent general saturation: compact certified hints, cold production handoff, corrections/retractions/new matches, corruption, writer contention and staged isolation"

def discoveryCheckpoint : IO Unit := do
  let root ← PageMap.absolute ".lake/page-db-discovery-checkpoint"
  let separate ← PageMap.absolute ".lake/page-db-discovery-separate"
  for path in [root, separate] do
    if ← path.pathExists then IO.FS.removeDirAll path
    let _ ← Persistence.create path
    pure ()
  let unary := fun value => Value.applyList .occurrence [Ref.semantic value]
  let values := [unary (.text "first dependency"), unary (.text "second dependency")]
  let edge : UnionEdge := ⟨.text "first dependency", .text "second dependency",
    .run (.text "checkpoint"), by intro _; rfl⟩
  let built := QuotientBuilder.plannedBuild? values [] [edge] none
  let some plan := built.plan | throw (IO.userError "checkpoint fixture did not use general producer")
  let packet : DiscoveryMemo.Packet := {
    ranks := [("checkpoint-rank", List.range 64)]
    selections := [("checkpoint-selection", [0, 1, 2])]
    contexts := [("checkpoint-context", [0, 1, 4, 0])]
    saturation := some (SaturationMemo.capturePlan (SaturationMemo.Basis.make values) plan) }
  let initial ← PageMap.pin root
  let initialGraph ← Store.materialize initial
  let publisher ← DiscoveryMemo.Publisher.new root
  publisher.checkpoint packet
  let first ← PageMap.pin root
  require (first.head.revision == initial.head.revision + 1)
    "one completed checkpoint did not use one atomic publication"
  require ((← Matcher.RankMemo.readKey first "checkpoint-rank") == packet.ranks &&
      (← Matcher.RankMemo.readKey first "checkpoint-selection" .selection) == packet.selections &&
      (← Matcher.RankMemo.readKey first "checkpoint-context" .context) == packet.contexts &&
      (← SaturationMemo.read first) == packet.saturation.getD [])
    "one checkpoint failed to retain every independent memo lane"
  require (equalGraph (← Store.materialize first) {initialGraph with revision := first.head.revision} &&
      (← Store.readChange first first.head.revision).neutral)
    "a partial calculation acquired source evidence or graph authority"
  publisher.checkpoint packet
  DiscoveryMemo.publish root packet
  require ((← PageMap.pin root).head == first.head)
    "warm or independent unchanged checkpoint appended another generation"
  let separateBefore ← PageMap.pin separate
  Matcher.RankMemo.publish separate packet.ranks
  Matcher.RankMemo.publish separate packet.selections .selection
  Matcher.RankMemo.publish separate packet.contexts .context
  SaturationMemo.publish separate (packet.saturation.getD [])
  let separateAfter ← PageMap.pin separate
  let togetherBytes := first.head.bytes - initial.head.bytes
  let separateBytes := separateAfter.head.bytes - separateBefore.head.bytes
  require (togetherBytes < separateBytes)
    "coalescing the same four lanes did not reduce physical append volume"
  let retry ← DiscoveryMemo.Publisher.new root
  let changed := {packet with contexts := [("checkpoint-context", [0, 1, 5, 0])]}
  let started ← IO.monoNanosNow
  let (_, heldHead, heldBytes) ← PageMap.withWriter first fun _ => do
    retry.checkpoint changed
    require (← retry.acknowledged.get).isNone
      "a busy publisher acknowledged a checkpoint which was not durable"
  require (heldHead == first.head && heldBytes == 0 && (← IO.monoNanosNow) - started < 1000000000)
    "a checkpoint waited behind saving or published while another writer owned the DB"
  retry.checkpoint changed
  require ((← Matcher.RankMemo.readKey (← PageMap.pin root) "checkpoint-context" .context) == changed.contexts)
    "a busy boundary lost the completed calculation rather than retrying at the next boundary"

  -- Interrupt the actual indexed controller after certified context grounding,
  -- before projection-owner lookup and terminal handoff. The callback observes
  -- the real durable checkpoint; no special save path is called by the test.
  let root ← PageMap.absolute ".lake/page-db-discovery-controller"
  if ← root.pathExists then IO.FS.removeDirAll root
  let _ ← Persistence.create root
  let query := String.intercalate " " ((List.range 40).map fun n => "anchor" ++ toString n)
  let owner := OutcomeEdge.make (.text query) (.text (query ++ " verified source result")) []
    (by simp) (by simp)
  let all ← if valid : (.text "checkpoint parent") ∉ [owner.work] then
    pure (AllEdge.make (.text "checkpoint parent") [owner.work] (by simp) valid)
    else throw (IO.userError "invalid checkpoint topology fixture")
  let base ← PageMap.pin root
  let _ ← PageMap.withWriter base fun writer => do
    let intern : Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← [owner.relation, all.relation].mapM intern.root
    Store.writeChange writer ⟨ids, [], false⟩
  let sourceSnapshot ← PageMap.pin root
  let reader ← Store.NodeReader.new sourceSnapshot
  let interrupted ← IO.mkRef false
  let failProjection ← IO.mkRef true
  let source : IndexedContext := {
    all := ← reader.topology, persistent := []
    outcomeCount := ← Store.getNat sourceSnapshot.get "liveOutcomes"
    population := ← Store.getNat sourceSnapshot.get "candidates"
    semanticPopulation := ← Store.getNat sourceSnapshot.get "semanticPopulation"
    live := fun value => (·.isSome) <$> Store.liveRoot? sourceSnapshot value
    semanticPresent := fun value => do
      match ← Store.findNode? sourceSnapshot value with
      | none => pure false
      | some id => pure (decide ((← Store.getNat sourceSnapshot.get (Store.key "semanticUses" id)) > 0))
    semantic := fun _ _ _ _ => pure (some {})
    lexical := fun _ _ => pure {}
    ordinal := fun id => Store.getNat sourceSnapshot.get (Store.key "member" id)
    readWork := fun id => do reader.workOrigin (← Store.locateOutcome sourceSnapshot id)
    readOwner := fun id => do reader.outcome (← Store.locateOutcome sourceSnapshot id)
    surfaces := Store.workSurfaceCandidates sourceSnapshot
    frequencies := Store.frequencies sourceSnapshot
    liveOwner := fun value => do
      if ← failProjection.get then
        let cold ← PageMap.pin root
        require (!(← Matcher.RankMemo.read cold .context).isEmpty)
          "completed context geometry was lost before terminal handoff"
        interrupted.set true
        throw (IO.userError "injected after durable context checkpoint")
      (·.map Prod.snd) <$> Store.liveRoot? sourceSnapshot value }
  let selection : Config.Selection := {
    label := "checkpoint", read := [⟨"work", root⟩], write := some ⟨"work", root⟩
    semanticMatcher := none, handoffChars := 24000 }
  let initialReader ← Matcher.RankMemo.Reader.new sourceSnapshot
  let failed ← try
    let _ ← indexedDiscoveryUsing source selection query [] false none true
      (rankReader := some initialReader)
    pure false
    catch _ => pure true
  require (failed && (← interrupted.get))
    "injection did not interrupt the actual discovery after a durable completed calculation"
  let recovered ← PageMap.pin root
  let durableContexts ← Matcher.RankMemo.read recovered .context
  require (!durableContexts.isEmpty) "a reopened reader lost the interrupted controller's context plan"
  require (equalGraph (← Store.materialize recovered)
      {(← Store.materialize sourceSnapshot) with revision := recovered.head.revision})
    "interrupted discovery checkpoint changed the complete source graph"
  failProjection.set false
  let expected ← indexedDiscoveryUsing source {selection with write := none} query [] false none true
  let actual ← indexedDiscovery selection [some recovered] query [] false none true [] [] true
    (← SaturationMemo.read recovered) (some (← Matcher.RankMemo.Reader.new recovered))
  require ((toJson actual.join).compress == (toJson expected).compress && expected.isSome)
    "restarting with the interrupted checkpoint changed the complete ordered handoff"
  IO.println ((Json.mkObj [("kind", .str "durable_discovery_boundary"),
    ("one_batch_appended_bytes", toJson togetherBytes), ("separate_appended_bytes", toJson separateBytes),
    ("interrupted_context_plans", toJson durableContexts.length),
    ("generative_calls", toJson (0 : Nat))]).compress)
  IO.println "PASS one-publication discovery checkpoints, zero-append replay, fail-fast busy retry, interrupted actual controller and exact cold handoff"

def rankPerformance : IO Unit := do
  let query := Matcher.compile LogicalText.logicalNormalizer "alpha beta alpha beta alpha beta alpha beta"
  let target := Matcher.compile LogicalText.logicalNormalizer
    (String.intercalate " " (List.replicate 120 "alpha beta"))
  let source := Matcher.SurfaceJoin.current query target
  require (32 ≤ source.count && source.count ≤ Matcher.RankMemo.frontierAllowance)
    "adaptive ranking performance fixture is outside the retained frontier"
  let first := Matcher.RankMemo.obtain [] [10, 1, 10, 1, 10, 1, 10, 1] query target
  let mut saved := first.2.1.toList
  let mut samples : List Json := []
  for run in [:30] do
    let weights := if run % 2 == 0 then [1, 10, 1, 10, 1, 10, 1, 10]
      else [10, 1, 10, 1, 10, 1, 10, 1]
    let direct := do
      let start ← IO.monoNanosNow
      let ranked := Matcher.referenceRank weights query target
      require (ranked.length == source.count) "reference ranking lost candidates"
      pure (ranked, (← IO.monoNanosNow) - start)
    let differential := do
      let start ← IO.monoNanosNow
      let found := Matcher.RankMemo.obtain saved weights query target
      require (found.1.val.length == source.count && found.2.2)
        "adaptive ranking did not reuse a corrected complete frontier"
      pure (found, (← IO.monoNanosNow) - start)
    let ((reference, fullNs), (found, deltaNs)) ← if run % 2 == 0 then do
        let full ← direct; let delta ← differential; pure (full, delta)
      else do let delta ← differential; let full ← direct; pure (full, delta)
    require (reference == found.1.val) "adaptive ranking changed the complete stable order"
    samples := samples ++ [Json.mkObj [("run", toJson run),
      ("full_ns", toJson fullNs), ("delta_ns", toJson deltaNs)]]
    saved := found.2.1.toList
  IO.println ((Json.mkObj [("kind", .str "corrected_frequency_rank"),
    ("frontier", toJson source.count), ("samples", toJson samples),
    ("generative_calls", toJson (0 : Nat))]).compress)

end Eggshell.PageDBTests
