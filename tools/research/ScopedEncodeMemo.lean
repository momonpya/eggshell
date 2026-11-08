module
public import Lean.Data.Json.FromToJson
public import Lean.Data.Json.Parser
public import Init.Data.List.Find
@[expose] public section
namespace Eggshell.Research.ScopedEncodeMemo
open Lean

/-- Both the project/permission read domain and the numerical implementation
are part of identity. Original text is compared exactly, not by a digest. -/
structure Key where
  scope : String
  contract : String
  texts : Array String
  deriving DecidableEq

theorem Key.different_scope (left right : Key) (different : left.scope ≠ right.scope) : left ≠ right := by
  intro same
  exact different (congrArg Key.scope same)

theorem Key.different_contract (left right : Key) (different : left.contract ≠ right.contract) : left ≠ right := by
  intro same
  exact different (congrArg Key.contract same)

structure Entry where
  key : Key
  /-- Only vectors and coverage, never another native request's ID/timing. -/
  payload : String

def Entry.charge (entry : Entry) : Nat :=
  entry.key.scope.utf8ByteSize + entry.key.contract.utf8ByteSize + entry.payload.utf8ByteSize +
    entry.key.texts.foldl (fun n text => n+text.utf8ByteSize+64) 128

def weight : List Entry → Nat
  | [] => 0
  | entry :: rest => entry.charge + weight rest

def keep (slots bytes : Nat) (entries : List Entry) : List Entry :=
  match slots,entries with
  | 0,_ | _,[] => []
  | n+1,entry :: rest =>
      if entry.charge ≤ bytes then entry :: keep n (bytes-entry.charge) rest else []

theorem keep_length (slots bytes : Nat) (entries : List Entry) : (keep slots bytes entries).length ≤ slots := by
  induction slots generalizing entries bytes with
  | zero => simp [keep]
  | succ slots ih =>
      cases entries with
      | nil => simp [keep]
      | cons entry rest =>
          simp only [keep]
          split
          · simpa only [List.length_cons,Nat.succ_le_succ_iff] using ih (bytes-entry.charge) rest
          · simp

theorem keep_weight (slots bytes : Nat) (entries : List Entry) : weight (keep slots bytes entries) ≤ bytes := by
  induction slots generalizing entries bytes with
  | zero => simp [keep,weight]
  | succ slots ih =>
      cases entries with
      | nil => simp [keep,weight]
      | cons entry rest =>
          simp only [keep]
          split
          · simp only [weight]
            have bounded := ih (bytes-entry.charge) rest
            omega
          · simp [weight]

theorem keep_member (slots bytes : Nat) (entries : List Entry) (entry : Entry)
    (present : entry ∈ keep slots bytes entries) : entry ∈ entries := by
  induction slots generalizing entries bytes with
  | zero => simp [keep] at present
  | succ slots ih =>
      cases entries with
      | nil => simp [keep] at present
      | cons first rest =>
          simp only [keep] at present
          split at present
          · rcases List.mem_cons.mp present with same | later
            · exact List.mem_cons.mpr (.inl same)
            · exact List.mem_cons.mpr (.inr (ih _ _ later))
          · contradiction

def maxEntries : Nat := 64
def maxBytes : Nat := 4*1024*1024
structure Memo where
  entries : List Entry
  countBound : entries.length ≤ maxEntries
  bytesBound : weight entries ≤ maxBytes

def Memo.empty : Memo := Memo.mk [] (by simp [maxEntries]) (by simp [weight,maxBytes])

def Memo.insert (memo : Memo) (entry : Entry) : Memo :=
  if entry.charge > maxBytes then memo else
    let selected := keep maxEntries maxBytes (entry :: memo.entries.filter (fun old => decide (old.key ≠ entry.key)))
    Memo.mk selected (keep_length _ _ _) (keep_weight _ _ _)

def lookupEntries (entries : List Entry) (key : Key) : Option String :=
  match entries with
  | [] => none
  | entry :: rest => if entry.key = key then some entry.payload else lookupEntries rest key

def Memo.lookup (memo : Memo) (key : Key) : Option String := lookupEntries memo.entries key

/-- The trusted numerical boundary supplies completed entries. This theorem
does not assert a property of neural inference; it proves memo operations
cannot change the key/value relation supplied by that boundary. -/
def Sound (compute : Key → String) (entries : List Entry) : Prop :=
  ∀ entry ∈ entries,entry.payload = compute entry.key

theorem insert_sound (compute : Key → String) (memo : Memo) (sound : Sound compute memo.entries)
    (entry : Entry) (completed : entry.payload = compute entry.key) :
    Sound compute (memo.insert entry).entries := by
  intro selected present
  unfold Memo.insert at present
  split at present
  · exact sound selected present
  · have old := keep_member _ _ _ selected present
    rcases List.mem_cons.mp old with same | old
    · subst selected; exact completed
    · exact sound selected (List.mem_filter.mp old).1

theorem lookup_sound (compute : Key → String) (entries : List Entry) (sound : Sound compute entries)
    (key : Key) (payload : String) (hit : lookupEntries entries key = some payload) : payload = compute key := by
  induction entries with
  | nil => simp [lookupEntries] at hit
  | cons entry rest ih =>
      simp only [lookupEntries] at hit
      split at hit
      · cases hit
        simpa only [‹entry.key = key›] using sound entry (List.mem_cons_self ..)
      · exact ih (fun old present => sound old (List.mem_cons_of_mem _ present)) hit

/-- Runtime state is an immutable bounded snapshot. get/set use Lean's
atomic reference operations. Racing inserts may lose a hit, never create a
foreign result or a snapshot that violates the bounds. No Ref.modify, model
mutex, subscriber queue, CAS retry or IO occurs inside lookup. -/
structure Store where
  snapshot : IO.Ref Memo

def Store.make : IO Store := return ⟨← IO.mkRef Memo.empty⟩
def Store.lookup (store : Store) (key : Key) : IO (Option String) := do
  return (← store.snapshot.get).lookup key
def Store.remember (store : Store) (entry : Entry) : IO Unit := do
  let before ← store.snapshot.get
  store.snapshot.set (before.insert entry)

/-- Failed/native ownership metadata is not memo payload. Wrong row counts
remain on the original error path instead of becoming a completed entry. -/
def completed? (key : Key) (reply : Json) : Option Entry := do
  if (reply.getObjVal? "error").isOk then none else do
    let vectors ← (reply.getObjValAs? (Array Json) "vectors").toOption
    let coverage ← (reply.getObjValAs? (Array Json) "coverage").toOption
    if vectors.size != key.texts.size || coverage.size != key.texts.size then none else
      some ⟨key,(Json.mkObj [("vectors",toJson vectors),("coverage",toJson coverage)]).compress⟩

#print axioms keep_length
#print axioms keep_weight
#print axioms keep_member
#print axioms insert_sound
#print axioms lookup_sound
end Eggshell.Research.ScopedEncodeMemo
