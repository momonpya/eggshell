module
public import Std.Data.HashSet.Lemmas

@[expose] public section
namespace Eggshell.AppendUnique

variable {α β : Type} [BEq β] [LawfulBEq β] [Hashable β]

def reference (key : α → β) (base added : List α) : List α :=
  added.foldl (fun current item =>
    if current.any (fun old => key old == key item) then current
    else current ++ [item]) base

def Seen (key : α → β) (known : Std.HashSet β) (items : List α) : Prop :=
  ∀ value, known.contains value = items.any (fun item => key item == value)

/-- Keep original payloads; the set only answers exact membership. -/
def loop (key : α → β) (known : Std.HashSet β) (added reversed : List α) :
    List α :=
  match added with
  | [] => reversed
  | item :: rest =>
      if known.contains (key item) then loop key known rest reversed
      else loop key (known.insert (key item)) rest (item :: reversed)

theorem loop_exact (key : α → β) (base added : List α) (known : Std.HashSet β)
    (reversed : List α) (seen : Seen key known (base ++ reversed.reverse)) :
    base ++ (loop key known added reversed).reverse =
      reference key (base ++ reversed.reverse) added := by
  induction added generalizing known reversed with
  | nil => rfl
  | cons item rest ih =>
      change base ++ (loop key known (item :: rest) reversed).reverse =
        reference key (if (base ++ reversed.reverse).any (fun old => key old == key item)
          then base ++ reversed.reverse else (base ++ reversed.reverse) ++ [item]) rest
      rw [← seen (key item)]
      cases found : known.contains (key item) with
      | true => simpa only [loop, found, ↓reduceIte] using ih known reversed seen
      | false =>
          have next : base ++ (item :: reversed).reverse =
              (base ++ reversed.reverse) ++ [item] := by
            simp only [List.reverse_cons, List.append_assoc]
          have nextSeen : Seen key (known.insert (key item)) (base ++ (item :: reversed).reverse) := by
            intro value
            rw [next, List.any_append, ← seen value]
            simp [Std.HashSet.contains_insert, Bool.or_comm]
          simpa only [loop, found, Bool.false_eq_true, ↓reduceIte, next] using
            ih (known.insert (key item)) (item :: reversed) nextSeen

/-- Existing duplicates stay; unseen additions retain first payload and order.
Both prefix copying and repeated complete membership scans disappear. -/
def merge (key : α → β) (base added : List α) : List α :=
  base ++ (loop key (Std.HashSet.ofList (base.map key)) added []).reverse

theorem merge_exact (key : α → β) (base added : List α) :
    merge key base added = reference key base added := by
  have seen : Seen key (Std.HashSet.ofList (base.map key)) (base ++ [].reverse) := by
    intro value
    simp only [List.reverse_nil, List.append_nil, Std.HashSet.contains_ofList, List.contains_map]
    exact List.any_congr rfl (fun _ => BEq.comm)
  simpa only [merge, List.reverse_nil, List.append_nil] using
    loop_exact key base added (Std.HashSet.ofList (base.map key)) [] seen

end Eggshell.AppendUnique
