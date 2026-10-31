module
public import Eggshell.Synapses
public import tools.KeyPostings
@[expose] public section

namespace Eggshell.Research.RecordedNavigation
open Eggshell.Synapses

structure Header where
  database : String
  domain : String
  occurrence : Occurrence
  started : Nat
  finished : Nat
  deriving BEq

def Header.scope (header : Header) : String × String × String × String :=
  (header.database,header.domain,header.occurrence.session,header.occurrence.turn)

def Header.valid (header : Header) : Bool :=
  !header.database.isEmpty && !header.domain.isEmpty && header.occurrence.valid && header.started < header.finished

structure Call where
  header : Header
  ranges : Array Range

def gapEvidence (call : Call) (before after : Range) : Bool :=
  call.header.valid && before.valid && after.valid && call.ranges.contains before && call.ranges.contains after &&
  before.subject == after.subject && before.last+1 < after.first &&
  call.ranges.all (fun source => source.subject != before.subject || source.last ≤ before.last || after.first ≤ source.first)

/-- Only metadata is resident. The original call/rows of the certificate
erase; queries cannot reparse a producer body or rescan its full row array. -/
structure Gap where
  producer : Header
  before : Range
  after : Range
  original : ∃ call : Call, call.header = producer ∧ gapEvidence call before after = true

def gap? (call : Call) (before after : Range) : Option Gap :=
  if checked : gapEvidence call before after = true then
    some ⟨call.header,before,after,⟨call,rfl,checked⟩⟩ else none

def gaps (call : Call) : Array Gap := Id.run do
  let spaces := KeyPostings.prepare (·.subject) call.ranges
  let mut subjects : Std.HashSet Subject := {}
  let mut result := #[]
  for source in call.ranges do
    if subjects.contains source.subject then continue
    subjects := subjects.insert source.subject
    let rows := (spaces.lookup source.subject).qsort fun a b =>
      if a.first == b.first then a.last < b.last else a.first < b.first
    for (before,after) in rows.toList.zip (rows.toList.drop 1) do
      if let some checked := gap? call before after then result := result.push checked
  return result

structure Target where
  consumer : Header
  source : Range
  valid : source.valid = true
  original : ∃ call : Call, call.header = consumer ∧ call.header.valid = true ∧ source ∈ call.ranges

def targets (call : Call) : Array Target :=
  if valid : call.header.valid = true then
    call.ranges.attach.filterMap fun source =>
      if sourceValid : source.val.valid = true then
        some ⟨call.header,source.val,sourceValid,⟨call,rfl,valid,source.property⟩⟩ else none
  else #[]

def compatible (gap : Gap) (target : Target) : Prop :=
  gap.producer.scope = target.consumer.scope ∧
  gap.producer.finished < target.consumer.started ∧
  gap.before.subject = target.source.subject ∧
  gap.before.last < target.source.first ∧ target.source.first < gap.after.first

instance (gap : Gap) (target : Target) : Decidable (compatible gap target) := inferInstanceAs
  (Decidable (_ ∧ _ ∧ _ ∧ _ ∧ _))

structure Link where
  gap : Gap
  target : Target
  checked : compatible gap target

def link? (gap : Gap) (target : Target) : Option Link :=
  if checked : compatible gap target then some ⟨gap,target,checked⟩ else none

theorem Link.before (link : Link) : link.gap.producer.finished < link.target.consumer.started := link.checked.2.1
theorem Link.same_scope (link : Link) : link.gap.producer.scope = link.target.consumer.scope := link.checked.1
theorem Link.same_subject (link : Link) : link.gap.before.subject = link.target.source.subject := link.checked.2.2.1
theorem Link.bounded (link : Link) :
    link.gap.before.last < link.target.source.first ∧ link.target.source.first < link.gap.after.first := link.checked.2.2.2

theorem Link.published_anchor (link : Link) :
    ∃ call : Call, call.header = link.gap.producer ∧ link.gap.before ∈ call.ranges := by
  obtain ⟨call,same,valid⟩ := link.gap.original
  refine ⟨call,same,?_⟩
  have member := valid
  simp only [gapEvidence,Bool.and_eq_true] at member
  exact Array.mem_of_contains_eq_true member.1.1.1.1.2

/-- Newest eligible completion wins. Distinct anchors tied at that same
observed time are ambiguous and yield no link. No distance, name or query
threshold is fitted. This is a navigation hint, not proof of necessity. -/
def latest (candidates : Array Gap) (target : Target) : Option Link := Id.run do
  let mut found : Option Link := none
  let mut ambiguous := false
  for candidate in candidates do
    let some link := link? candidate target | continue
    match found with
    | none => found := some link; ambiguous := false
    | some previous =>
      if previous.gap.producer.finished < candidate.producer.finished then
        found := some link; ambiguous := false
      else if previous.gap.producer.finished == candidate.producer.finished && previous.gap.before != candidate.before then
        ambiguous := true
  return if ambiguous then none else found

def gapKey (gap : Gap) := (gap.producer.scope,gap.before.subject)

structure Prepared where
  targets : Array Target
  links : Array (Option Link)
  targetIndex : KeyPostings.Index (fun row : Target × Nat => row.1.source.subject) targets.zipIdx
  gapCount : Nat

def prepare (calls : Array Call) : Prepared :=
  let gapRows := calls.flatMap gaps
  let index := KeyPostings.prepare gapKey gapRows
  let targetRows := calls.flatMap targets
  ⟨targetRows,targetRows.map (fun target => latest (index.lookup (target.consumer.scope,target.source.subject)) target),
    KeyPostings.prepare (fun row : Target × Nat => row.1.source.subject) targetRows.zipIdx,gapRows.size⟩

structure Enriched where
  ranges : Array Range
  additions : Array Range
  fired : Array Nat

/-- A finite source-address closure. Only recorded targets are inspected,
each at most once after it is covered. It never reads a question or gold. -/
def enrich (prepared : Prepared) (initial : Array Range) : Enriched := Id.run do
  let mut queue := initial
  let mut position := 0
  let mut known := Std.HashSet.ofArray initial
  let mut visited : Std.HashSet Nat := {}
  let mut additions := #[]
  let mut fired := #[]
  while position < queue.size do
    let source := queue[position]!
    position := position+1
    for (target,index) in prepared.targetIndex.lookup source.subject do
      if visited.contains index || !source.contains target.source then continue
      visited := visited.insert index
      let some link := (prepared.links[index]?).join | continue
      fired := fired.push index
      if known.contains link.gap.before then continue
      known := known.insert link.gap.before
      additions := additions.push link.gap.before
      queue := queue.push link.gap.before
  return ⟨queue,additions,fired⟩

end Eggshell.Research.RecordedNavigation
