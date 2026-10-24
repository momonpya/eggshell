module
public import Eggshell.GraphStore

@[expose] public section
namespace Eggshell.SourceDelta
open DB Persistence.Store

def linked (parent child : PageMap.Head) : Bool :=
  parent.identity == child.identity && parent.authority == child.authority &&
    parent.revision+1 == child.revision && parent.bytes < child.bytes

inductive Lineage : PageMap.Head → PageMap.Head → Prop where
  | same (head) : Lineage head head
  | step {first parent child} : Lineage first parent → linked parent child = true → Lineage first child

theorem Lineage.same_identity (chain : Lineage first last) : first.identity = last.identity := by
  induction chain with
  | same => rfl
  | step _ link ih =>
    simp only [linked, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at link
    exact ih.trans link.1.1.1

theorem Lineage.revision_le (chain : Lineage first last) : first.revision ≤ last.revision := by
  induction chain with
  | same => omega
  | step _ link ih =>
    simp only [linked, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at link
    omega

structure Delta (first last : PageMap.Head) where
  owners : List Nat
  records : Nat
  bytes : Nat
  lineage : Lineage first last

/-- The pinned target authenticates every publication. Replay follows actual
parent heads back to the exact saved head, not just matching revision numbers.
Bounds apply before decoding each journal payload. Failure is a full-plan
decision, never a claim that there were no source changes. -/
private def walk (source : PageMap.Snapshot) (first current : PageMap.Head)
    (remaining : Nat) (byteBudget : Nat) : IO (Option (Delta first current)) := do
  if same : first = current then return some ⟨[],0,0,by rw [← same]; exact .same first⟩
  match remaining with
  | 0 => return none
  | remaining+1 =>
    if current.revision ≤ first.revision then return none
    let historical := {source with head := current}
    let bytes ← IO.ofExcept (payloadSize (← historical.get (key "change" current.revision)))
    if bytes > byteBudget then return none
    -- Read this record through its own child head. A later revision must not
    -- replace an older journal entry and thereby rewrite the replayed past.
    let publication ← readPublication historical current.revision
    if publication.change.added.length + publication.change.removed.length > 8192 then return none
    if valid : linked publication.parent current = true then
      let some previous ← walk source first publication.parent remaining (byteBudget-bytes) | return none
      let owners := hashDistinct (publication.change.added ++ publication.change.removed ++ previous.owners)
      if owners.length > 4096 then return none
      return some ⟨owners,previous.records+1,previous.bytes+bytes,.step previous.lineage valid⟩
    else return none

opaque read? (source : PageMap.Snapshot) (basis : PageMap.Head) : IO (Option (Delta basis source.head)) := do
  try
    unless basis.identity == source.head.identity && basis.authority == source.head.authority &&
        basis.revision ≤ source.head.revision && basis.bytes ≤ source.head.bytes do return none
    let result ← walk source basis source.head 4096 (8*1024*1024)
    let nodes ← getNat source.get "nodes"
    if result.any (fun delta => !delta.owners.all (· < nodes)) then return none
    return result
  catch _ => return none

/-- Only nominated live candidates are read; no directory of all owners and
no complete candidate-domain payload is opened by this path. -/
def documents (source : PageMap.Snapshot) (owners : List Nat) : IO (List SearchDocument) := do
  let mut rows := []
  for owner in owners do
    let candidate ← source.get (key "candidate" owner)
    if candidate.isNone then continue
    unless (← IO.ofExcept (payloadSize candidate)) == 1 do
      throw (IO.userError "invalid changed search candidate")
    let located ← locateOutcome source owner
    let ordinal ← getNat source.get (key "member" owner)
    unless (← IO.ofExcept (payloadSize (← source.get (key "searchCandidate" ordinal)))) == owner do
      throw (IO.userError "changed search candidate disagrees with its reverse directory")
    let encoded ← readChunks source source.get "searchWindows" owner
    let (windows,tail) ← IO.ofExcept (windowCodec.decode encoded.toList)
    unless tail.isEmpty && !windows.isEmpty &&
        windows.all (fun value => PageMap.validIdentity value) do
      throw (IO.userError "invalid changed window directory")
    rows := ⟨owner,located.header.work,windows,some (Sidecar.Owner.ofSnapshot source)⟩ :: rows
  return rows.reverse

end Eggshell.SourceDelta
