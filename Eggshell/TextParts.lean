module

public import Std
import all Init.Data.String.Legacy

@[expose] public section

namespace Eggshell.TextParts

/-- Consume separator-delimited parts as they are found. Unlike `splitOn`,
this retains no list of every copied part of the original source. Delimiter
matching is precisely the legacy splitter, including partial/overlapping
matches and UTF-8 positions. -/
def foldSplitOnAux {α : Type} (step : α → String → α) (s sep : String)
    (b i j : String.Pos.Raw) (state : α) : α :=
  if i.atEnd s then step state (b.extract s i)
  else
    if i.get s == j.get sep then
      let i := i.next s
      let j := j.next sep
      if j.atEnd sep then
        foldSplitOnAux step s sep i i 0 (step state (b.extract s (i.unoffsetBy j)))
      else foldSplitOnAux step s sep b i j state
    else foldSplitOnAux step s sep b ((i.unoffsetBy j).next s) 0 state
termination_by (s.rawEndPos.1 - (j.byteDistance i), sep.rawEndPos.1 - j.1)
decreasing_by
  focus
    rename_i h _ _
    left; exact Nat.sub_lt_sub_left
      (Nat.lt_of_le_of_lt (Nat.sub_le ..) (Nat.gt_of_not_le (mt decide_eq_true h)))
      (Nat.lt_of_le_of_lt (Nat.sub_le ..) (String.Pos.Raw.lt_next s _))
  focus
    rename_i i₀ j₀ _ eq h'
    rw [show (j₀.next sep).byteDistance (i₀.next s) = j₀.byteDistance i₀ by
      change (_ + Char.utf8Size _) - (_ + Char.utf8Size _) = _
      rw [(beq_iff_eq ..).1 eq, Nat.add_sub_add_right]; rfl]
    right; exact Nat.sub_lt_sub_left
      (Nat.lt_of_le_of_lt (Nat.le_add_right ..) (Nat.gt_of_not_le (mt decide_eq_true h')))
      (String.Pos.Raw.lt_next sep _)
  focus
    rename_i h _
    left; exact Nat.sub_lt_sub_left
      (Nat.lt_of_le_of_lt (Nat.sub_le ..) (Nat.gt_of_not_le (mt decide_eq_true h)))
      (String.Pos.Raw.lt_next s (i.unoffsetBy j))

/-- Empty separators preserve the complete source as one part. -/
def foldSplitOn {α : Type} (step : α → String → α) (state : α)
    (source separator : String) : α :=
  if separator == "" then step state source
  else foldSplitOnAux step source separator 0 0 0 state

theorem foldSplitOnAux_exact {α : Type} (step : α → String → α)
    (s sep : String) (b i j : String.Pos.Raw) (state : α) :
    ∀ (r : List String) (initial : α), state = r.reverse.foldl step initial →
      foldSplitOnAux step s sep b i j state =
        (String.splitOnAux s sep b i j r).foldl step initial := by
  fun_induction foldSplitOnAux step s sep b i j state with
  | case1 b i j state ended =>
      intro r initial sameState
      rw [String.splitOnAux]
      simp only [ended, ↓reduceIte, List.reverse_cons, List.foldl_append,
        List.foldl_cons, List.foldl_nil, sameState]
  | case2 b i j state notEnded same nextI nextJ ended ih =>
      intro r initial sameState
      dsimp only [nextI, nextJ] at ended
      rw [String.splitOnAux]
      simpa only [notEnded, same, ended, Bool.false_eq_true, ↓reduceIte] using
        ih ((b.extract s (nextI.unoffsetBy nextJ)) :: r) initial
          (by simp [List.reverse_cons, List.foldl_append, sameState])
  | case3 b i j state notEnded same nextI nextJ notEndedSep ih =>
      intro r initial sameState
      dsimp only [nextI, nextJ] at notEndedSep
      rw [String.splitOnAux]
      simpa only [notEnded, same, notEndedSep, Bool.false_eq_true, ↓reduceIte] using
        ih r initial sameState
  | case4 b i j state notEnded different ih =>
      intro r initial sameState
      rw [String.splitOnAux]
      simpa only [notEnded, different, Bool.false_eq_true, ↓reduceIte] using ih r initial sameState

/-- Universal equality for the actual streaming splitter, arbitrary source,
separator, accumulator and consumer; not only a fixture or token count. -/
theorem foldSplitOn_exact {α : Type} (step : α → String → α) (state : α)
    (source separator : String) :
    foldSplitOn step state source separator = (source.splitOn separator).foldl step state := by
  unfold foldSplitOn String.splitOn
  split
  · simp
  · simpa using foldSplitOnAux_exact step source separator 0 0 0 state [] state rfl

/-- Stopping is permitted only after every possible suffix preserves the
observable projection. A budget or a heuristic cannot supply this contract. -/
structure Projection (α β : Type) where
  step : α → String → α
  finish : α → β
  done : α → Bool
  stable : ∀ state, done state = true → ∀ rest : List String,
    finish (rest.foldl step state) = finish state

/-- The same delimiter scanner, with a proved demand boundary. Once the
projection is final, neither later characters nor later parts are visited. -/
def foldProjectionAux {α β : Type} (consumer : Projection α β) (s sep : String)
    (b i j : String.Pos.Raw) (state : α) : β :=
  if consumer.done state then consumer.finish state
  else if i.atEnd s then consumer.finish (consumer.step state (b.extract s i))
  else
    if i.get s == j.get sep then
      let i := i.next s
      let j := j.next sep
      if j.atEnd sep then
        foldProjectionAux consumer s sep i i 0
          (consumer.step state (b.extract s (i.unoffsetBy j)))
      else foldProjectionAux consumer s sep b i j state
    else foldProjectionAux consumer s sep b ((i.unoffsetBy j).next s) 0 state
termination_by (s.rawEndPos.1 - (j.byteDistance i), sep.rawEndPos.1 - j.1)
decreasing_by
  focus
    rename_i _ h _ _
    left; exact Nat.sub_lt_sub_left
      (Nat.lt_of_le_of_lt (Nat.sub_le ..) (Nat.gt_of_not_le (mt decide_eq_true h)))
      (Nat.lt_of_le_of_lt (Nat.sub_le ..) (String.Pos.Raw.lt_next s _))
  focus
    rename_i i₀ j₀ _ _ eq h'
    rw [show (j₀.next sep).byteDistance (i₀.next s) = j₀.byteDistance i₀ by
      change (_ + Char.utf8Size _) - (_ + Char.utf8Size _) = _
      rw [(beq_iff_eq ..).1 eq, Nat.add_sub_add_right]; rfl]
    right; exact Nat.sub_lt_sub_left
      (Nat.lt_of_le_of_lt (Nat.le_add_right ..) (Nat.gt_of_not_le (mt decide_eq_true h')))
      (String.Pos.Raw.lt_next sep _)
  focus
    rename_i _ h _
    left; exact Nat.sub_lt_sub_left
      (Nat.lt_of_le_of_lt (Nat.sub_le ..) (Nat.gt_of_not_le (mt decide_eq_true h)))
      (String.Pos.Raw.lt_next s (i.unoffsetBy j))

theorem foldProjectionAux_exact {α β : Type} (consumer : Projection α β)
    (s sep : String) (b i j : String.Pos.Raw) (state : α) :
    foldProjectionAux consumer s sep b i j state =
      consumer.finish (foldSplitOnAux consumer.step s sep b i j state) := by
  fun_induction foldProjectionAux consumer s sep b i j state with
  | case1 b i j state done =>
      rw [foldSplitOnAux_exact consumer.step s sep b i j state [] state rfl]
      exact (consumer.stable state done _).symm
  | case2 b i j state notDone ended =>
      rw [foldSplitOnAux]
      simp only [ended, ↓reduceIte]
  | case3 b i j state notDone notEnded same nextI nextJ ended ih =>
      dsimp only [nextI, nextJ] at ended
      rw [foldSplitOnAux]
      simpa only [notEnded, same, ended, Bool.false_eq_true, ↓reduceIte] using ih
  | case4 b i j state notDone notEnded same nextI nextJ notEndedSep ih =>
      dsimp only [nextI, nextJ] at notEndedSep
      rw [foldSplitOnAux]
      simpa only [notEnded, same, notEndedSep, Bool.false_eq_true, ↓reduceIte] using ih
  | case5 b i j state notDone notEnded different ih =>
      rw [foldSplitOnAux]
      simpa only [notEnded, different, Bool.false_eq_true, ↓reduceIte] using ih

def foldProjection {α β : Type} (consumer : Projection α β) (state : α)
    (source separator : String) : β :=
  if consumer.done state then consumer.finish state
  else if separator == "" then consumer.finish (consumer.step state source)
  else foldProjectionAux consumer source separator 0 0 0 state

/-- Universal equality to the unchanged full splitter. The stopping proof
is erased; the executing caller must still construct it to use the scanner. -/
theorem foldProjection_exact {α β : Type} (consumer : Projection α β) (state : α)
    (source separator : String) :
    foldProjection consumer state source separator =
      consumer.finish ((source.splitOn separator).foldl consumer.step state) := by
  unfold foldProjection
  split
  · exact (consumer.stable state ‹_› _).symm
  · rw [← foldSplitOn_exact]
    unfold foldSplitOn
    split
    · rfl
    · exact foldProjectionAux_exact consumer source separator 0 0 0 state

end Eggshell.TextParts
