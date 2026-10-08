module

public import Eggshell.Blake3
public import Eggshell.Matcher
public import Eggshell.Paths
public import Lean.Data.Json.FromToJson

@[expose] public section

namespace Eggshell.SemanticMatcher

open Lean

structure Item where
  id : String
  text : String
  deriving ToJson, BEq

structure Request where
  query : Item
  candidates : List Item
  deriving ToJson

structure IndexRequest where
  index : List Item
  deriving ToJson

structure IndexResponse where
  indexed : List String
  deriving FromJson

/-- Queue consumption requires an acknowledgement for this exact ordered batch. -/
structure IndexReceipt (items : List Item) where
  indexed : List String
  exact_batch : indexed = items.map (·.id)

def indexReceipt? (items : List Item) (response : IndexResponse) :
    Option (IndexReceipt items) :=
  if exact : response.indexed = items.map (·.id) then
    some ⟨response.indexed, exact⟩
  else none

theorem index_receipt_matches_batch (items : List Item) (response : IndexResponse)
    (receipt : IndexReceipt items)
    (_accepted : indexReceipt? items response = some receipt) :
    receipt.indexed = items.map (·.id) := receipt.exact_batch

theorem mismatched_index_acknowledgement_rejected (items : List Item)
    (response : IndexResponse) (different : response.indexed ≠ items.map (·.id)) :
    indexReceipt? items response = none := by
  simp [indexReceipt?, different]

structure WindowChoice where
  document : Nat
  indices : List Nat
  deriving FromJson, ToJson

structure Response where
  related : List Nat
  ranked : List Nat := []
  evidence : List WindowChoice := []
  deriving FromJson

structure IndexedResponse where
  related : List Nat
  ranked : List Nat
  evidence : List WindowChoice := []
  deriving FromJson

/-- A parent synthesis changes priority, never the eligibility of its evidence. -/
def synthesizedChild (corpus : Matcher.Corpus) (candidate : Matcher.Candidate) : Bool :=
  corpus.parents.any fun parent =>
    parent.children.contains candidate.edge.work &&
      corpus.candidates.any fun owner => owner.edge.work == parent.parent

/-- Keep the previous summary-first ordering, then admit every readable observed
    child. Sealing a turn cannot make its tool evidence unsearchable. -/
def eligibleCandidates (corpus : Matcher.Corpus) : List Matcher.Candidate :=
  let readable := corpus.candidates.filter fun candidate =>
    (Matcher.atomText? candidate.edge.work).isSome
  readable.filter (fun candidate => !synthesizedChild corpus candidate) ++
    readable.filter (synthesizedChild corpus)

theorem eligible_iff_readable_owner (corpus : Matcher.Corpus)
    (candidate : Matcher.Candidate) :
    candidate ∈ eligibleCandidates corpus ↔
      candidate ∈ corpus.candidates ∧
        (Matcher.atomText? candidate.edge.work).isSome = true := by
  cases priority : synthesizedChild corpus candidate <;>
    simp [eligibleCandidates, priority]

/-- This includes children of completed parents, independent of parent count,
    graph shape, provider scores, or text length. -/
theorem readable_owner_remains_eligible (corpus : Matcher.Corpus)
    (candidate : Matcher.Candidate) (owner : candidate ∈ corpus.candidates)
    (readable : (Matcher.atomText? candidate.edge.work).isSome = true) :
    candidate ∈ eligibleCandidates corpus :=
  (eligible_iff_readable_owner corpus candidate).mpr ⟨owner, readable⟩

def relations (candidates : List Matcher.Candidate)
    (indices : List Nat) : List Value :=
  indices.eraseDups.filterMap fun index => do
    let candidate ← candidates[index]?
    pure candidate.edge.relation

/-- Invalid or invented indexes resolve to no relation. -/
theorem relations_subset_candidate_owners {candidates : List Matcher.Candidate}
    {indices : List Nat} {relation : Value}
    (member : relation ∈ relations candidates indices) :
    ∃ candidate ∈ candidates, candidate.edge.relation = relation := by
  simp only [relations, List.mem_filterMap] at member
  obtain ⟨index, _, resolved⟩ := member
  change candidates[index]?.bind (fun candidate =>
    some candidate.edge.relation) = some relation at resolved
  rw [Option.bind_eq_some_iff] at resolved
  obtain ⟨candidate, present, equal⟩ := resolved
  simp only [Option.some.injEq] at equal
  exact ⟨candidate, List.mem_of_getElem? present, equal⟩

def processStdio : IO.Process.StdioConfig := {
  stdin := .piped
  stdout := .piped
  stderr := .null
}

abbrev Child := IO.Process.Child processStdio

structure Running where
  child : Child

inductive Lane where
  | index
  | search
  deriving DecidableEq

/-- Shared across installations and chats belonging to the same OS user.
    Never unlink a lease file: every contender must lock the same inode. -/
def lanePath (lane : Lane) : IO System.FilePath := do
  let root := (← Paths.home) / ".cache" / "eggshell" / "resources"
  Persistence.rejectSymlinkAncestors root
  Persistence.privateDirectory root
  pure (root / (match lane with | .index => "index.guard" | .search => "search.guard"))

def withLane (lane : Lane) (action : IO α) : IO (Option α) := do
  let path ← lanePath lane
  Persistence.rejectSymlinkAncestors path
  let handle ← IO.FS.Handle.mk path .append
  Persistence.privateFile path
  match lane with
  | .index => handle.lock
  | .search => if !(← handle.tryLock) then return none
  try
    some <$> action
  finally
    handle.unlock

def start : List String → IO Running
  | [] => throw (IO.userError "semantic_matcher must name an executable")
  | executable :: arguments => do
      let child : Child ← IO.Process.spawn {
        cmd := executable
        args := arguments.toArray
        stdin := .piped
        stdout := .piped
        stderr := .null
        -- Stay in the worker's owned group so worker cancellation also stops
        -- this provider and its numerical child.
      }
      pure { child }

def closeInput (running : Running) : IO (IO.Process.Child {
    stdin := .null, stdout := .piped, stderr := .null }) := do
  let (_, child) ← running.child.takeStdin
  pure child

def reapProvider (child : IO.Process.Child {
    stdin := .null, stdout := .piped, stderr := .null }) : Nat → IO Unit
  | 0 => do
      try child.kill catch _ => pure ()
      let _ ← child.wait
      pure ()
  | steps + 1 => do
      match ← child.tryWait with
      | some _ => pure () -- tryWait has already reaped this child.
      | none =>
          IO.sleep 5
          reapProvider child steps

def stop (running : Running) : IO Unit := do
  let child ← closeInput running
  -- EOF lets the provider reap its numerical child in its own finally block.
  -- A broken provider is terminated; its descendants remain in the worker's
  -- group and the numerical lease prevents another model from overtaking it.
  reapProvider child 200

def withProvider (command : List String) (action : Running → IO α) : IO α := do
  let running ← start command
  try action running finally stop running

def withResponseDeadline (action : IO α) : IO α := do
  let response ← IO.asTask action .dedicated
  let timeout ← IO.asTask (do
    IO.sleep 15000
    throw (IO.userError "semantic matcher timed out")) .dedicated
  match ← IO.waitAny [response, timeout] with
  | .ok line => pure line
  | .error error => throw error

def readLine (running : Running) : IO String :=
  withResponseDeadline running.child.stdout.getLine

def exchange (running : Running) (request : Request) : IO Response := do
  running.child.stdin.putStr ((toJson request).compress ++ "\n")
  running.child.stdin.flush
  let line ← readLine running
  let json ← match Json.parse line with
    | .ok json => pure json
    | .error message => throw (IO.userError s!"semantic matcher: {message}")
  match (fromJson? json : Except String Response) with
  | .ok response => pure response
  | .error message => throw (IO.userError s!"semantic matcher: {message}")

def candidateText (candidate : Matcher.Candidate) : String :=
  (Matcher.atomText? candidate.edge.work |>.getD "") ++ "\n" ++
    (Matcher.atomText? candidate.edge.outcome |>.getD "")

theorem candidate_text_source (candidate : Matcher.Candidate) :
    candidateText candidate = Persistence.Store.searchText candidate.edge := rfl

/-- Stable cache key for rebuildable acceleration; it is never graph authority. -/
def contentKey (value : Value) : String :=
  Blake3.hex <| Blake3.digest "eggshell.semantic.embedding".toUTF8
    [Persistence.valueToJson value |>.compress |>.toUTF8]

def item (value : Value) (text : String) : Item :=
  { id := contentKey value, text }

def outcomeWorkItems (values : List Value) : List Item :=
  (eligibleCandidates (Matcher.Corpus.build LogicalText.logicalNormalizer
    (WorkGraph.fromValues values))).map fun candidate =>
      let text := candidateText candidate
      item (.text text) text

def nominations (candidates : List Matcher.Candidate)
    (response : Response) : Matcher.SemanticNominations := {
  related := relations candidates response.related
}

theorem nomination_has_corpus_owner {corpus : Matcher.Corpus}
    {response : Response} {relation : Value}
    (member : relation ∈
      (nominations (eligibleCandidates corpus) response).related) :
    ∃ candidate ∈ corpus.candidates, candidate.edge.relation = relation := by
  obtain ⟨candidate, eligible, equal⟩ := relations_subset_candidate_owners member
  exact ⟨candidate, ((eligible_iff_readable_owner corpus candidate).mp eligible).1, equal⟩

/-- Run only after durable publication, in the independent writer. Completion
    requires the provider's acknowledgement of this exact batch. There is no
    search deadline here: hook responses do not wait for this writer. -/
def indexWorks (command : List String) (items : List Item) : IO (IndexReceipt items) := do
  if items.isEmpty then return ⟨items.map (·.id), rfl⟩
  let command := match command with
    | executable :: "search-provider" :: arguments =>
        executable :: "search-provider" :: (arguments ++ ["--lane", "index"])
    | command => command
  let some receipt ← withLane .index <| withProvider command fun running => do
      let request : IndexRequest := { index := items }
      running.child.stdin.putStr ((toJson request).compress ++ "\n")
      running.child.stdin.flush
      let json ← IO.ofExcept (Json.parse (← running.child.stdout.getLine))
      let response ← IO.ofExcept (fromJson? json : Except String IndexResponse)
      let some receipt := indexReceipt? items response |
        throw (IO.userError "semantic index acknowledged a different batch")
      pure receipt
    | throw (IO.userError "index lane did not produce an acknowledgement")
  pure receipt

/-- Independent providers can read and score cached vectors concurrently.
The numerical child acquires the model resource lease only when inference is
needed and holds it until exit. The requesting worker owns its cancellation. -/
def nominateWithRanking (command : List String) (query : Value) (queryText : String)
    (corpus : Matcher.Corpus) :
    IO (Matcher.SemanticNominations × (List Value × List (Value × List Nat))) :=
  let candidates := eligibleCandidates corpus
  if candidates.isEmpty then pure ({}, [], []) else do
    try
      withProvider command fun running => do
        let response ← exchange running {
          query := item query queryText
          candidates := candidates.map fun candidate =>
            let text := candidateText candidate
            item (.text text) text
        }
        unless response.ranked.length == candidates.length &&
            response.ranked.mergeSort (· ≤ ·) == List.range candidates.length do
          throw (IO.userError "semantic matcher returned an incomplete evidence ranking")
        let windows ← response.evidence.mapM fun choice => do
          let some candidate := candidates[choice.document]? |
            throw (IO.userError "foreign full-reference evidence owner")
          let count := (SearchRank.windows (candidateText candidate)).length
          unless choice.indices.length ≤ 16 && choice.indices.eraseDups == choice.indices &&
              choice.indices.all (· < count) do
            throw (IO.userError "foreign full-reference evidence window")
          pure (candidate.edge.relation, choice.indices)
        pure (nominations candidates response, relations candidates response.ranked, windows)
    catch error =>
      IO.eprintln s!"eggshell: semantic matcher unavailable: {error}"
      pure ({ pending := true }, [], [])

def nominate (command : List String) (query : Value) (queryText : String)
    (corpus : Matcher.Corpus) : IO Matcher.SemanticNominations := do
  pure (← nominateWithRanking command query queryText corpus).1

/-- An untrusted pull must describe a nonempty, bounded, distinct set of
windows in the nominated document before any source reader is called. -/
structure WindowPull (document : Persistence.Store.SearchDocument) where
  indices : List Nat
  nonempty : indices ≠ []
  bounded : indices.length ≤ 32
  distinct : indices.eraseDups = indices
  within : indices.all (fun index => decide (index < document.windows.length)) = true

def WindowPull.check? (document : Persistence.Store.SearchDocument) (indices : List Nat) :
    Option (WindowPull document) :=
  if valid : indices ≠ [] ∧ indices.length ≤ 32 ∧ indices.eraseDups = indices ∧
      indices.all (fun index => decide (index < document.windows.length)) = true then
    some ⟨indices, valid.1, valid.2.1, valid.2.2.1, valid.2.2.2⟩
  else none

def WindowPull.handles (pull : WindowPull document) : List (Fin document.windows.length) :=
  pull.indices.attach.map fun index => ⟨index.val, by
    have := (List.all_eq_true.mp pull.within) index.val index.property
    exact of_decide_eq_true this⟩

theorem WindowPull.handles_exact (pull : WindowPull document) :
    pull.handles.map Fin.val = pull.indices := by
  simp [handles]

theorem WindowPull.handles_bounded (pull : WindowPull document) :
    pull.handles.length ≤ 32 := by
  simpa [handles] using pull.bounded

/-- Provider positions resolve in the requesting corpus, never to a provider
path or invented text. A nomination retains that ownership certificate. -/
structure IndexedNomination (documents : List Persistence.Store.SearchDocument) where
  document : Persistence.Store.SearchDocument
  owned : document ∈ documents
  windows : List (Fin document.windows.length)
  bounded : windows.length ≤ 32

def IndexedNomination.indices (nomination : IndexedNomination documents) : List Nat :=
  nomination.windows.map Fin.val

theorem IndexedNomination.window_owned (nomination : IndexedNomination documents)
    (index : Nat) (present : index ∈ nomination.indices) :
    index < nomination.document.windows.length := by
  obtain ⟨window, _, equal⟩ := List.mem_map.mp present
  exact equal ▸ window.isLt

/-- A provider may order the closed requesting corpus, but cannot omit,
duplicate or invent a document in the surrounding-evidence order. -/
structure IndexedOrder (documents : List Persistence.Store.SearchDocument) where
  indices : List Nat
  bounded : indices.length = documents.length
  complete : indices.mergeSort (· ≤ ·) = List.range documents.length

def IndexedOrder.check? (documents : List Persistence.Store.SearchDocument) (indices : List Nat) :
    Option (IndexedOrder documents) :=
  if valid : indices.length = documents.length then
    if complete : indices.mergeSort (· ≤ ·) = List.range documents.length then
      some ⟨indices, valid, complete⟩ else none
  else none

theorem IndexedOrder.existing (order : IndexedOrder documents) (index : Nat)
    (present : index ∈ order.indices) : index < documents.length := by
  have sorted : index ∈ order.indices.mergeSort (· ≤ ·) := List.mem_mergeSort.mpr present
  rw [order.complete] at sorted
  exact List.mem_range.mp sorted

theorem IndexedOrder.covers (order : IndexedOrder documents) (index : Nat)
    (within : index < documents.length) : index ∈ order.indices := by
  have sorted : index ∈ order.indices.mergeSort (· ≤ ·) := by
    rw [order.complete]
    exact List.mem_range.mpr within
  exact List.mem_mergeSort.mp sorted

structure IndexedSearch (documents : List Persistence.Store.SearchDocument) where
  related : List (IndexedNomination documents)
  ranking : List (IndexedNomination documents)
  order : IndexedOrder documents

def indexedNominations (documents : List Persistence.Store.SearchDocument)
    (response : IndexedResponse) : Except String (List (IndexedNomination documents)) :=
  response.related.eraseDups.foldlM (fun nominations index => do
    match present : documents[index]? with
    | none => pure nominations
    | some document =>
        let owned := List.mem_of_getElem? present
        let indices := (response.evidence.find? (·.document == index)).map (·.indices) |>.getD []
        if indices.isEmpty then pure (nominations ++ [⟨document, owned, [], by simp⟩]) else
          let some pull := WindowPull.check? document indices |
            throw "semantic evidence window lies outside its document"
          pure (nominations ++ [⟨document, owned, pull.handles, pull.handles_bounded⟩])) []

def documentOwners (documents : List Persistence.Store.SearchDocument)
    (indices : List Nat) : List Nat :=
  indices.eraseDups.filterMap fun index => documents[index]?.map (·.owner)

theorem documentOwners_owned {documents : List Persistence.Store.SearchDocument}
    {indices : List Nat} {owner : Nat} (member : owner ∈ documentOwners documents indices) :
    ∃ document ∈ documents, document.owner = owner := by
  simp only [documentOwners, List.mem_filterMap] at member
  obtain ⟨index, _, resolved⟩ := member
  rw [Option.map_eq_some_iff] at resolved
  obtain ⟨document, present, equal⟩ := resolved
  exact ⟨document, List.mem_of_getElem? present, equal⟩

/-- All providers use the same indexed boundary. Executable identity neither
selects a second protocol nor permits full source reconstruction. -/
def nominateIndexed (command : List String) (queryText : String)
    (documents : List Persistence.Store.SearchDocument) (lexical anchors : List Nat)
    (readWindow : (document : Persistence.Store.SearchDocument) →
      Fin document.windows.length → IO String) :
    IO (Option (IndexedSearch documents)) := do
  if documents.isEmpty then
    let some order := IndexedOrder.check? documents [] |
      throw (IO.userError "empty semantic corpus has a nonempty directory")
    return some ⟨[], [], order⟩
  try
    withProvider command fun running => withResponseDeadline do
      let request := Json.mkObj [("query", toJson (item (.text queryText) queryText)),
        ("documents", toJson (documents.map fun document => Json.mkObj [
          ("id", toJson document.owner), ("windows", toJson document.windows)])),
        ("lexical", toJson lexical), ("anchors", toJson anchors)]
      running.child.stdin.putStrLn request.compress
      running.child.stdin.flush
      let mut json ← IO.ofExcept (Json.parse (← running.child.stdout.getLine))
      let mut repaired : Std.HashSet (Nat × Nat) := {}
      -- One bounded pull per missing batch. The provider supplies no path,
      -- node or snapshot identity: indexes resolve only within this request.
      while let .ok need := json.getObjVal? "need_windows" do
        let documentIndex ← IO.ofExcept (need.getObjValAs? Nat "document")
        let indices ← IO.ofExcept (need.getObjValAs? (List Nat) "indices")
        let some document := documents[documentIndex]? |
          throw (IO.userError "numerical repair names a foreign document")
        let some pull := WindowPull.check? document indices |
          throw (IO.userError "invalid numerical window repair batch")
        for index in pull.indices do
          unless !repaired.contains (documentIndex, index) do
            throw (IO.userError "numerical repair repeated an already supplied window")
          repaired := repaired.insert (documentIndex, index)
        let texts ← pull.handles.mapM (readWindow document)
        running.child.stdin.putStrLn (Json.mkObj [("windows", toJson texts)]).compress
        running.child.stdin.flush
        json ← IO.ofExcept (Json.parse (← running.child.stdout.getLine))
      if let .ok message := json.getObjValAs? String "error" then
        throw (IO.userError ("indexed numerical provider: " ++ message))
      let response ← IO.ofExcept (fromJson? json : Except String IndexedResponse)
      let some order := IndexedOrder.check? documents response.ranked |
        throw (IO.userError "semantic evidence order is not the complete requesting corpus")
      let related ← IO.ofExcept (indexedNominations documents response)
      let ranking ← IO.ofExcept (indexedNominations documents {response with related := order.indices})
      pure (some ⟨related, ranking, order⟩)
  catch error =>
    IO.eprintln s!"eggshell: indexed semantic matcher unavailable: {error}"
    pure none

end Eggshell.SemanticMatcher
