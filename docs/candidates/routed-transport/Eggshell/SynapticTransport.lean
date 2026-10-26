module

public import Eggshell.SynapticRoutingStore

@[expose] public section
namespace Eggshell.Synapses.Routed
open Lean DB Recommend Routing.Store

def graphDeadline (now deadline : Nat) : Nat :=
  min deadline (now+(deadline-now)/4)

theorem graph_deadline_preserves_upstream (now deadline : Nat) :
    graphDeadline now deadline ≤ deadline := Nat.min_le_left _ _

theorem graph_deadline_reserves_binding (now deadline : Nat) :
    graphDeadline now deadline ≤ now+(deadline-now)/4 := Nat.min_le_right _ _

structure Result where
  hints : Array Hint := #[]
  nodes : Nat := 0
  arcs : Nat := 0
  bytes : Nat := 0
  complete : Bool := true
  available : Bool := true
  index : Option PageMap.Head := none
  usage : Option PageMap.Head := none
  routing : Option PageMap.Head := none
  usageRouting : Option PageMap.Head := none
  failure : Option String := none

def Result.admitted (result : Result) : Array Hint :=
  if result.complete && result.available && result.failure.isNone then result.hints else #[]

theorem Result.incomplete_not_admitted (result : Result) (incomplete : result.complete = false) :
    result.admitted = #[] := by simp [Result.admitted,incomplete]

def Result.receipt (result : Result) : Json := Json.mkObj [
  ("available",toJson result.available),("complete",toJson result.complete),
  ("requests",toJson result.nodes),("facts",toJson result.arcs),("bytes",toJson result.bytes),
  ("index",toJson result.index),("usage",toJson result.usage),
  ("routing",toJson result.routing),("usageRouting",toJson result.usageRouting),
  ("failure",toJson result.failure),("offers",toJson (result.admitted.map Hint.json))]

def preferOmissions (hints : Array Hint) : Array Hint := Id.run do
  let missing := hints.foldl (fun sources hint =>
    if hint.kind == 3 || hint.kind == 4 then
      hint.target.source?.map sources.insert |>.getD sources else sources) ({} : Std.HashSet Range)
  return hints.filter fun hint =>
    hint.kind != 5 || hint.target.source?.all (fun source => !missing.contains source)

/-- Views are opened read-only and must match the already pinned original
index. Missing or stale preparation is explicit; a hook never rebuilds it. -/
def collect (prepared : Recommend.Prepared) (answers : Array (String × Nat))
    (query : String) (deadline : Nat) (consumers : Array (Occurrence × Nat)) : IO Result := do
  let initial : Result := {index := prepared.shared.map (·.index.head),usage := prepared.usage.map (·.index.head)}
  if prepared.failure.isSome then return {initial with complete := false,available := false,failure := prepared.failure}
  let some shared := prepared.shared | return {initial with complete := false,available := false,failure := some "source-index-unavailable"}
  try
    let some routing ← Routing.Store.open? shared (shared.index.directory / "routing") |
      return {initial with complete := false,available := false,failure := some "routing-unprepared"}
    let usage ← prepared.usage.mapM fun original => do
      let some view ← Routing.Store.open? original (original.index.directory / "routing") |
        throw (IO.userError "private usage routing is unprepared")
      pure view
    let mut roots := answers.map fun (owner,priority) =>
      (Index.Key.answer shared.manifest.source.identity owner,priority)
    roots := roots ++ consumers.map (fun (consumer,priority) => (Index.Key.consumer consumer,priority))
    if usage.isSome && digest query then roots := roots.push (.query query,0)
    let walked ← Routing.Store.walk routing usage roots deadline
    return {initial with
      hints := preferOmissions walked.hints,nodes := walked.nodes,arcs := walked.arcs,bytes := walked.bytes
      complete := walked.complete,routing := some routing.snapshot.head,usageRouting := usage.map (·.snapshot.head)}
  catch error => return {initial with complete := false,failure := some s!"routing-read: {error}"}

/-- A hint cannot supply coordinates. Original rows independently establish
the range, owner and bytes even if the advisory projection is malformed. -/
structure Located where
  offer : Hint
  source : Range
  target : offer.target = .range source
  row : Read
  within : source.contains row.source = true

def locate (hints : Array Hint) (rows : Array Read) : Array Located := Id.run do
  let mut found := #[]
  for hint in hints do
    let .range source := hint.target | continue
    if target : hint.target = .range source then
      let matching := rows.filter (source.contains ·.source)
      unless covered source (matching.map (·.source)) do continue
      for row in matching do
        if within : source.contains row.source = true then found := found.push ⟨hint,source,target,row,within⟩
  return found

theorem Located.same_subject (located : Located) :
    located.source.subject = located.row.source.subject := by
  have within := located.within
  simp only [Range.contains,Bool.and_eq_true,beq_iff_eq,decide_eq_true_eq] at within
  exact within.1.1

/-- Only arbitrary-output transport needs a full consumption witness. Decode
each such fact once, retain its checked Offer and leave range hints compact. -/
def outputOffers (prepared : Recommend.Prepared) (result : Result) (deadline : Nat) : IO (Array Offer) := do
  let some shared := prepared.shared | return #[]
  let mut facts : Std.HashMap String Fact := {}
  let mut offers := #[]
  for hint in result.admitted do
    let .output _ := hint.target | continue
    if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "output-witness deadline")
    let fact ← match facts[hint.evidence]? with
      | some fact => pure fact
      | none => do
        let some bytes ← shared.index.get ("fact:" ++ hint.evidence) |
          throw (IO.userError "missing original output witness")
        let fact ← Index.decode (α := Fact) bytes
        unless shared.manifest.scope.accepts fact && Index.belongs shared.manifest.source.identity fact do
          throw (IO.userError "foreign original output witness")
        pure fact
    let identity := Index.contentKey fact
    unless identity == hint.evidence do throw (IO.userError "output witness differs from its digest")
    let some offer := Offer.check? hint.target hint.priority fact ⟨identity,rfl⟩ |
      throw (IO.userError "output hint is not supported by its original witness")
    unless offer.kind == Routing.Store.kindName hint.kind do
      throw (IO.userError "output hint changed its relation kind")
    facts := facts.insert hint.evidence fact
    offers := offers.push offer
  return offers

end Eggshell.Synapses.Routed
