module

public import Eggshell.SemanticMatcher

@[expose] public section
namespace Eggshell.Persistence.Store.Federated

/-- Exact unique owner accounting for the emitted posting stream. The index
and the ordered owner witnesses cannot drift during differential aggregation. -/
structure PostingSet where
  index : Std.HashMap Nat Unit
  owners : List Nat
  seen : HashDistinct.Seen index owners
  unique : owners.Nodup

def PostingSet.empty : PostingSet := ⟨{}, [], by intro id; simp, by simp⟩
instance : EmptyCollection PostingSet := ⟨PostingSet.empty⟩

def PostingSet.add (known : PostingSet) (id : Nat) : PostingSet :=
  if present : known.index.contains id then known else
    ⟨known.index.insert id (), id :: known.owners,
      HashDistinct.seen_insert _ _ known.seen id, by
        refine List.nodup_cons.mpr ⟨?_, known.unique⟩
        intro member
        have contained : known.owners.contains id = true := List.contains_iff_mem.mpr member
        rw [← known.seen id] at contained
        simp [contained] at present⟩

def PostingSet.contains (known : PostingSet) (id : Nat) : Bool := known.index.contains id
def PostingSet.size (known : PostingSet) : Nat := known.owners.length
def PostingSet.toList (known : PostingSet) : List Nat := known.owners.reverse
def PostingSet.raw (known : PostingSet) : Std.HashMap Nat Unit × List Nat := (known.index, known.owners)

theorem PostingSet.raw_add (known : PostingSet) (id : Nat) :
    (known.add id).raw = HashDistinct.step known.raw id := by
  unfold add HashDistinct.step raw
  split <;> rfl

theorem PostingSet.raw_fold (known : PostingSet) (ids : List Nat) :
    (ids.foldl PostingSet.add known).raw = ids.foldl HashDistinct.step known.raw := by
  induction ids generalizing known with
  | nil => rfl
  | cons id rest ih => simpa only [List.foldl_cons, raw_add] using ih (known.add id)

theorem PostingSet.complete_stream (ids : List Nat) :
    (ids.foldl PostingSet.add {}).toList = ids.eraseDups := by
  change (ids.foldl PostingSet.add PostingSet.empty).raw.2.reverse = _
  rw [raw_fold]
  exact HashDistinct.loop_reference ids {} [] (by intro id; simp)

theorem PostingSet.membership (known : PostingSet) (id : Nat) :
    known.contains id = true ↔ id ∈ known.owners := by
  rw [contains, known.seen]
  exact List.contains_iff_mem

/-- A reference is meaningful only in this request's closed snapshot table.
Neither a path supplied by a provider nor a naked foreign node id is accepted. -/
structure Node (sources : Array Snapshot) where
  source : Fin sources.size
  id : Nat

def Node.snapshot (node : Node sources) : Snapshot := sources[node.source]

/-- Structural equality of applications is equality of the operator and the
complete ordered, authority-tagged canonical child sequence. Atom digests
are deliberately absent: only checked byte comparisons assign Atom ids. -/
structure ApplicationKey where
  operator : Operator
  arguments : List (Authority × Nat)
  deriving DecidableEq, BEq, Hashable

def ApplicationKey.denote (key : ApplicationKey) (children : Nat → Value) : Value :=
  Value.applyList key.operator (key.arguments.map fun ref => (ref.1, children ref.2))

/-- Canonical child ids must denote distinct complete Values, including Exact
positions. Under that invariant the executable key is a complete equality
test, not just a hash or a semantic-footprint approximation. -/
theorem ApplicationKey.denote_injective (children : Nat → Value)
    (distinct : Function.Injective children) :
    Function.Injective (fun key : ApplicationKey => key.denote children) := by
  intro first second same
  have applications := Value.apply_injective.mp same
  have references := congrArg Refs.toList applications.2
  simp only [Refs.toList_ofList] at references
  have injective : Function.Injective (fun ref : Authority × Nat => (ref.1, children ref.2)) := by
    intro left right equal
    change (left.1, children left.2) = (right.1, children right.2) at equal
    exact Prod.ext (congrArg (fun pair : Authority × Value => pair.1) equal)
      (distinct (congrArg (fun pair : Authority × Value => pair.2) equal))
  have sameRefs := (List.map_inj_right (fun _ _ same => injective same)).mp references
  cases first
  cases second
  simp_all

def ApplicationKey.rebind (operator : Operator) (references : List (Authority × Nat))
    (canonical : Nat → Nat) : ApplicationKey :=
  ⟨operator, references.map fun ref => (ref.1, canonical ref.2)⟩

/-- The actual child substitution preserves the entire source application.
This is the interpreter contract used by bottom-up canonicalization; a
different arity, reference order, operator or authority cannot be erased. -/
theorem ApplicationKey.rebind_exact (operator : Operator) (references : List (Authority × Nat))
    (canonical : Nat → Nat) (source children : Nat → Value)
    (same : ∀ ref ∈ references, children (canonical ref.2) = source ref.2) :
    (rebind operator references canonical).denote children =
      Value.applyList operator (references.map fun ref => (ref.1, source ref.2)) := by
  unfold rebind denote
  simp only [List.map_map, Function.comp_def]
  congr 1
  apply List.map_congr_left
  intro ref member
  exact Prod.ext rfl (same ref member)

theorem ApplicationKey.equality_exact (first second : ApplicationKey)
    (children : Nat → Value) (distinct : Function.Injective children) :
    first = second ↔ first.denote children = second.denote children :=
  ⟨fun equal => congrArg (fun key => key.denote children) equal,
    fun equal => ApplicationKey.denote_injective children distinct equal⟩

/-- The runtime substitution is paired with its original source frame. In
addition to full position/authority preservation, every canonical child must
already exist before its parent can be registered. -/
structure ReboundApplication (operator : Operator) (source : List (Authority × Nat)) (size : Nat) where
  key : ApplicationKey
  operatorExact : key.operator = operator
  pairs : ReferencePairs source key.arguments
  before : ∀ ref ∈ key.arguments, ref.2 < size

def ReboundApplication.make? (operator : Operator) (source target : List (Authority × Nat))
    (size : Nat) : Option (ReboundApplication operator source size) := do
  let pairs ← ReferencePairs.check? source target
  if before : ∀ ref ∈ target, ref.2 < size then
    pure ⟨⟨operator, target⟩, rfl, pairs, before⟩
  else none

theorem ReboundApplication.resolved (application : ReboundApplication operator references size)
    (source children : Nat → Value)
    (same : ∀ pair ∈ application.pairs.pairs, source pair.1.2 = children pair.2.2) :
    application.key.denote children =
      Value.applyList operator (references.map fun ref => (ref.1, source ref.2)) := by
  unfold ApplicationKey.denote
  rw [application.operatorExact, ← application.pairs.resolved source children same]

theorem ReboundApplication.parent_bound (application : ReboundApplication operator source size)
    (child : Authority × Nat) (present : child ∈ application.key.arguments) : child.2 < size :=
  application.before child present

/-- This table is tied to the request's immutable source tuple. Exact-only
descendants are canonicalized too, but are not semantic population members. -/
structure CanonicalNode (sources : Array Snapshot) where
  original : Node sources
  application : Option ApplicationKey

structure Identity (sources : Array Snapshot) where
  nodes : Array (CanonicalNode sources) := #[]
  aliases : Std.HashMap (Nat × Nat) Nat := {}
  buckets : Std.HashMap Nat (List Nat) := {}
  applications : Std.HashMap ApplicationKey Nat := {}

/-- Interpret each source DAG node once. Atom identity uses complete streamed
bytes; applications use already canonical children, avoiding a fresh walk of
the same giant Atom for every enclosing relation. Checked backward references
give termination independently of body size or guessed traversal fuel. -/
def Identity.add (index : Identity sources) (node : Node sources) : IO (Identity sources × Nat) := do
  let key := (node.source.val, node.id)
  if let some known := index.aliases[key]? then return (index, known)
  let digest ← nodeHash node.snapshot node.id
  let checked ← readFrame node.snapshot node.snapshot.get node.id
  match _shape : checked.frame with
  | .atom =>
      for candidate in index.buckets.getD digest [] do
        let some entry := index.nodes[candidate]? |
          throw (IO.userError "federated Atom bucket exceeds its request table")
        unless entry.application.isNone do
          throw (IO.userError "federated Atom bucket contains an application")
        let original := entry.original
        if original.snapshot.directory == node.snapshot.directory &&
            original.snapshot.head == node.snapshot.head && original.id == node.id then
          return ({index with aliases := index.aliases.insert key candidate}, candidate)
        if ← bodiesEqual original.snapshot original.id node.snapshot node.id then
          return ({index with aliases := index.aliases.insert key candidate}, candidate)
      let id := index.nodes.size
      pure ({index with
        nodes := index.nodes.push ⟨node, none⟩
        aliases := index.aliases.insert key id
        buckets := index.buckets.insert digest (id :: index.buckets.getD digest [])}, id)
  | .apply operator references =>
      let (index, reversed) ← references.attach.foldlM (init := (index, [])) fun (index, previous) reference => do
        let (index, child) ← index.add ⟨node.source, reference.val.2⟩
        pure (index, (reference.val.1, child) :: previous)
      let some rebound := ReboundApplication.make? operator references reversed.reverse index.nodes.size |
        throw (IO.userError "federated child substitution lost a position, authority or prior node")
      let application := rebound.key
      if let some id := index.applications[application]? then
        let some original := index.nodes[id]? |
          throw (IO.userError "federated application key exceeds its request table")
        unless original.application == some application do
          throw (IO.userError "federated application key disagrees with its original node")
        return ({index with aliases := index.aliases.insert key id}, id)
      let id := index.nodes.size
      pure ({index with
        nodes := index.nodes.push ⟨node, some application⟩
        aliases := index.aliases.insert key id
        applications := index.applications.insert application id}, id)
termination_by node.id
decreasing_by
  exact checked.before reference.val (by simpa [_shape, NodeFrame.arguments] using reference.property)

def Identity.lookup (index : Identity sources) (source : Fin sources.size) (id : Nat) : IO Nat := do
  let some canonical := index.aliases[(source.val, id)]? |
    throw (IO.userError "live reference is absent from the federated semantic index")
  pure canonical

structure Document (sources : Array Snapshot) where
  node : Node sources
  original : SearchDocument
  owner : Nat
  work : Nat
  ordinal : Nat

structure Catalogue (sources : Array Snapshot) where
  readers : NodeReaders sources
  identity : Identity sources
  roots : List Nat
  orders : Std.HashMap Nat Nat
  owners : Std.HashMap Nat (Node sources)
  ownerOrigins : Std.HashMap Nat (List (Node sources)) := {}
  documents : List (Document sources)
  all : List AllEdge
  unions : List UnionEdge
  semanticPopulation : Nat

/-- Only numeric membership and node nomination directories are enumerated.
No original body is hydrated to obtain populations, deduplicated source order
or lexical frequencies. Overlapping sources share one structural owner. -/
def prepare (sources : Array Snapshot) : IO (Catalogue sources) := do
  let readers ← NodeReaders.new sources
  let mut identity : Identity sources := {}
  let mut semantic : Std.HashSet Nat := {}
  let mut topology := []
  let mut unions := []
  for source in List.finRange sources.size do
    let snapshot := sources[source]
    let reader := readers.at source
    let edges ← reader.topology
    topology := topology ++ edges
    let edges ← reader.unions (← authority snapshot)
    unions := unions ++ edges.map (·.edge)
    let nodes ← directory snapshot "semanticUses"
    unless nodes.length == (← getNat snapshot.get "semanticPopulation") &&
        nodes.all (fun row => row.2 > 0) do
      throw (IO.userError "federated semantic population is incomplete")
    for (id, _) in nodes do
      let (next, canonical) ← identity.add ⟨source, id⟩
      identity := next
      semantic := semantic.insert canonical
  let mut roots := []
  let mut owners : Std.HashMap Nat (Node sources) := {}
  let mut ownerOrigins : Std.HashMap Nat (List (Node sources)) := {}
  let mut documents : List (Document sources) := []
  let mut known : Std.HashSet Nat := {}
  for source in List.finRange sources.size do
    let snapshot := sources[source]
    for (_, id) in (← rootDirectory snapshot) do
      roots := roots ++ [← identity.lookup source id]
    let rows ← directory snapshot "outcome"
    unless rows.length == (← getNat snapshot.get "liveOutcomes") do
      throw (IO.userError "federated Outcome population is incomplete")
    for (_, id) in rows do
      let _ ← locateOutcome snapshot id
      let canonical ← identity.lookup source id
      ownerOrigins := ownerOrigins.insert canonical (ownerOrigins.getD canonical [] ++ [⟨source, id⟩])
      unless owners.contains canonical do owners := owners.insert canonical ⟨source, id⟩
    for document in (← searchDocuments snapshot) do
      let owner ← identity.lookup source document.owner
      unless owners.contains owner do throw (IO.userError "federated candidate is not an Outcome")
      unless known.contains owner do
        known := known.insert owner
        documents := documents ++ [⟨⟨source, document.owner⟩, document, owner,
          ← identity.lookup source document.work, 0⟩]
  roots := hashDistinct roots
  let orders := Std.HashMap.ofList (roots.zipIdx)
  documents ← documents.mapM fun document => do
    let some ordinal := orders[document.owner]? |
      throw (IO.userError "federated document has no live source root")
    pure {document with ordinal}
  let result : Catalogue sources := {
    readers, identity, roots, orders, owners, ownerOrigins
    documents := documents.mergeSort (fun first second => first.ordinal ≤ second.ordinal)
    all := topology.eraseDups
    unions, semanticPopulation := semantic.size }
  pure result

/-- A complete point/range lookup is done in every source, including negative
membership. Frequencies count canonical owners once, not source copies. -/
def postings (catalogue : Catalogue sources) (unit : String) (semantic : Bool) : IO PostingSet := do
  let mut owners : PostingSet := {}
  for source in List.finRange sources.size do
    let snapshot := sources[source]
    let ids ← if semantic then pure (← searchPosting snapshot unit).1 else do
      let ids ← Store.postings snapshot unit
      unless ids.length == (← frequency snapshot unit) do
        throw (IO.userError "federated term frequency disagrees with its complete posting")
      pure ids
    for id in ids do
      let canonical ← catalogue.identity.lookup source id
      unless catalogue.owners.contains canonical do
        throw (IO.userError "federated posting refers to a foreign Outcome")
      owners := owners.add canonical
  pure owners

def frequency (catalogue : Catalogue sources) (unit : String) : IO Nat :=
  (·.size) <$> postings catalogue unit false

def live? (sources : Array Snapshot) (value : Value) : IO Bool := do
  for snapshot in sources do
    if (← liveRoot? snapshot value).isSome then return true
  pure false

def semanticPresent (sources : Array Snapshot) (value : Value) : IO Bool := do
  for snapshot in sources do
    if let some id ← findNode? snapshot value then
      if (← getNat snapshot.get (key "semanticUses" id)) > 0 then return true
  pure false

def works (catalogue : Catalogue sources) (value : Value) : IO (Std.HashSet Nat) := do
  let mut found : Std.HashSet Nat := {}
  for source in List.finRange sources.size do
    if let some id ← findNode? sources[source] value then
      if let some canonical := catalogue.identity.aliases[(source.val, id)]? then
        found := found.insert canonical
  pure found

end Eggshell.Persistence.Store.Federated
