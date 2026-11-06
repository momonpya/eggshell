module
public import Eggshell.CanonicalSourceLease
@[expose] public section

namespace Eggshell.Synapses.CanonicalSource.Leases.PinnedReads
open Lean DB Shared

structure Request where
  token : String
  scope : String
  source : PageMap.Head
  metadata : Cache.Manifest

/-- Only the immutable descriptor escapes the admission transition. In
particular this value contains neither the lease registry nor a release action.
The original arena's caches remain subject to their own ownership contracts. -/
structure Pin where
  private mk ::
  request : Request
  descriptor : Descriptor
  expires : Nat
  accepted : descriptor.accepts request.scope request.source request.metadata = true

@[no_expose] def Pin.ofCut (request : Request)
    (cut : ReadCut state request.token request.scope request.source request.metadata now deadline) : Pin :=
  ⟨request,cut.descriptor,min cut.held.deadline deadline,by
    have h := cut.accepted
    simp only [Bool.and_eq_true] at h
    exact h.2⟩

theorem Pin.original_source (pin : Pin) : pin.descriptor.source = pin.request.source :=
  Descriptor.same_source _ _ _ _ pin.accepted

theorem Pin.expires_at_original_boundary (request : Request)
    (cut : ReadCut state request.token request.scope request.source request.metadata now deadline) :
    (Pin.ofCut request cut).expires ≤ cut.held.deadline ∧
      (Pin.ofCut request cut).expires ≤ deadline :=
  ⟨Nat.min_le_left _ _,Nat.min_le_right _ _⟩

theorem Pin.live_on_admission (request : Request)
    (cut : ReadCut state request.token request.scope request.source request.metadata now deadline) :
    now < (Pin.ofCut request cut).expires :=
  Nat.lt_min.mpr ⟨cut.live.2.2.1,cut.live.2.2.2⟩

/-- Authorization and lifetime checks accompany the actual selected reference. -/
structure Read (request : Request) (now : Nat) where
  pin : Pin
  sameToken : pin.request.token = request.token
  sameScope : pin.request.scope = request.scope
  accepted : pin.descriptor.accepts request.scope request.source request.metadata = true
  timely : now < pin.expires

def Read.loaded (read : Read request now) : Loaded := read.pin.descriptor.loaded

theorem Read.original_source (read : Read request now) : read.pin.descriptor.source = request.source :=
  Descriptor.same_source _ _ _ _ read.accepted

theorem Read.original_metadata (read : Read request now) :
    (read.loaded.metadata == request.metadata) = true := by
  have accepted := read.accepted
  simp only [Descriptor.accepts,Bool.and_eq_true] at accepted
  exact accepted.2

/-- No shared registry, lookup bookkeeping, wait or IO is available here.
Revocation prevents new admissions; an already admitted reader retains its
reference until its enclosing operation's finalizer. -/
def resolve (pins : List Pin) (request : Request) (now : Nat) : Except String (Read request now) :=
  match found : pins.find? (fun pin => pin.request.token == request.token &&
      pin.request.scope == request.scope && pin.descriptor.accepts request.scope request.source request.metadata) with
  | none => .error "source was not pinned at the operation boundary"
  | some pin =>
    have accepted := List.find?_some found
    have parts : pin.request.token = request.token ∧ pin.request.scope = request.scope ∧
        pin.descriptor.accepts request.scope request.source request.metadata = true := by
      simpa only [Bool.and_eq_true,beq_iff_eq,and_assoc] using accepted
    if timely : now < pin.expires then .ok ⟨pin,parts.1,parts.2.1,parts.2.2,timely⟩
    else .error "pinned source operation expired"

structure Batch (requests : List Request) where
  pins : List Pin
  order : pins.map (·.request) = requests

/-- The whole batch is checked against one registry snapshot, and commits
only when every token succeeds. It never waits for or loads another arena. -/
def acquire (state : State) (now deadline : Nat) : (requests : List Request) →
    Except String (State × Batch requests)
  | [] => .ok (state,⟨[],rfl⟩)
  | request :: rest =>
    match state.readCut request.token request.scope request.source request.metadata now deadline with
    | .error error => .error error
    | .ok cut =>
      match acquire cut.next now deadline rest with
      | .error error => .error error
      | .ok (next,tail) => .ok (next,⟨Pin.ofCut request cut :: tail.pins,by
          simp only [List.map_cons,Pin.ofCut,tail.order]⟩)

theorem acquire_budget (requests : List Request) (state next : State) (batch : Batch requests)
    (ok : acquire state now deadline requests = .ok (next,batch)) : next.budget = state.budget := by
  induction requests generalizing state next with
  | nil => simp [acquire] at ok; rw [← ok.1]
  | cons request rest ih =>
    cases hcut : state.readCut request.token request.scope request.source request.metadata now deadline with
    | error error => simp [acquire,hcut] at ok
    | ok cut =>
      cases hrest : acquire cut.next now deadline rest with
      | error error => simp [acquire,hcut,hrest] at ok
      | ok result =>
        rcases result with ⟨final,tail⟩
        have equal : final = next := by simpa [acquire,hcut,hrest,Except.map] using congrArg (Except.map Prod.fst) ok
        rw [← equal]
        exact (ih _ _ tail hrest).trans cut.budget_unchanged

theorem acquire_descriptors (requests : List Request) (state next : State) (batch : Batch requests)
    (ok : acquire state now deadline requests = .ok (next,batch)) : next.descriptors = state.descriptors := by
  induction requests generalizing state next with
  | nil => simp [acquire] at ok; rw [← ok.1]
  | cons request rest ih =>
    cases hcut : state.readCut request.token request.scope request.source request.metadata now deadline with
    | error error => simp [acquire,hcut] at ok
    | ok cut =>
      cases hrest : acquire cut.next now deadline rest with
      | error error => simp [acquire,hcut,hrest] at ok
      | ok result =>
        rcases result with ⟨final,tail⟩
        have equal : final = next := by simpa [acquire,hcut,hrest,Except.map] using congrArg (Except.map Prod.fst) ok
        rw [← equal]
        exact (ih _ _ tail hrest).trans cut.descriptors_unchanged

/-- Same per-token finalization as the scalar reader, folded under one
boundary transition. Disposal of original-cache borrows happens afterwards. -/
def finish (state : State) (now : Nat) (tokens : List String) : State × Array Descriptor := Id.run do
  let mut state := state
  let mut disposed := #[]
  for token in tokens do
    let some held := state.entries[token]? | continue
    let held := {held with readers := held.readers-1}
    state := {state with entries := state.entries.insert token held}
    if held.readers == 0 && (held.released || held.deadline ≤ now) then
      let (next,retired) := state.retire #[token]
      state := next
      disposed := disposed ++ retired
    else state := {state with nextExpiry := earlier state.nextExpiry held.deadline}
  return (state,disposed)

def withBatch (pool : Pool) (requests : List Request) (deadline : Nat)
    (use : Batch requests → IO α) : IO α := do
  if empty : requests.isEmpty = true then return ← use ⟨[],by cases requests <;> simp_all⟩
  let now ← IO.monoMsNow
  let batch ← pool.state.atomically do
    let (next,batch) ← IO.ofExcept (acquire (← get) now deadline requests)
    set next
    return batch
  try use batch
  finally
    let now ← IO.monoMsNow
    let retired ← pool.state.atomically do
      let (next,retired) := finish (← get) now (requests.map (·.token))
      set next
      return retired
    pool.dispose retired

end Eggshell.Synapses.CanonicalSource.Leases.PinnedReads
