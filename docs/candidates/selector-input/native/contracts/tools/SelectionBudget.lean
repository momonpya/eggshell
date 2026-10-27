module
public import tools.SharedCoverage
@[expose] public section

namespace SharedCoverage.Budget

private theorem fold_ge (p : Problem) (items : List (Fin p.costs.size)) (initial : Nat × Nat) :
    initial.1 ≤ (items.foldl (fun total index =>
      (total.1+p.costs[index].1,total.2+p.costs[index].2)) initial).1 ∧
    initial.2 ≤ (items.foldl (fun total index =>
      (total.1+p.costs[index].1,total.2+p.costs[index].2)) initial).2 := by
  induction items generalizing initial with
  | nil => simp
  | cons head tail ih =>
      simp only [List.foldl_cons]
      have next := ih (initial.1+p.costs[head].1,initial.2+p.costs[head].2)
      constructor <;> omega

theorem cost_extension (p : Problem) (selected : List (Fin p.offers.size)) (added : Fin p.offers.size) :
    (cost p selected).1 ≤ (cost p (selected++[added])).1 ∧
    (cost p selected).2 ≤ (cost p (selected++[added])).2 := by
  simp only [cost,nodes_append_one,List.foldl_append]
  exact fold_ge p _ _

theorem cost_swap (p : Problem) (selected : List (Fin p.offers.size)) (a b : Fin p.offers.size) :
    cost p (selected++[a,b]) = cost p (selected++[b,a]) := by
  have same : (nodes p (selected++[a,b])).Perm (nodes p (selected++[b,a])) := by
    apply (List.perm_ext_iff_of_nodup (duplicate_payload_charged_once p _) (duplicate_payload_charged_once p _)).mpr
    intro node
    have swapped : (selected++[a,b]).Perm (selected++[b,a]) :=
      List.Perm.append_left selected (List.Perm.swap b a [])
    simpa only [nodes,List.mem_eraseDups] using
      (List.Perm.flatMap_right (fun index => p.offers[index].closure) swapped).mem_iff (a := node)
  unfold cost
  apply same.foldl_eq'
  intro x _ y _ z
  apply Prod.ext <;> simp [Nat.add_comm,Nat.add_left_comm]

/-- Shared marginal costs can decrease; total union costs cannot. An offer
that already exceeded either budget never becomes feasible after more offers.
This holds for both limits without assuming any byte/character ratio. -/
theorem no_reactivation (p : Problem) (selected : List (Fin p.offers.size))
    (candidate winner : Fin p.offers.size)
    (before : ¬((cost p (selected++[candidate])).1 ≤ p.limit.1 ∧
      (cost p (selected++[candidate])).2 ≤ p.limit.2)) :
    ¬((cost p ((selected++[winner])++[candidate])).1 ≤ p.limit.1 ∧
      (cost p ((selected++[winner])++[candidate])).2 ≤ p.limit.2) := by
  have growth := cost_extension p (selected++[candidate]) winner
  simp only [List.append_assoc,List.cons_append,List.nil_append] at growth ⊢
  rw [cost_swap p selected candidate winner] at growth
  intro after
  apply before
  exact ⟨Nat.le_trans growth.1 after.1,Nat.le_trans growth.2 after.2⟩

end SharedCoverage.Budget

#print axioms SharedCoverage.Budget.cost_extension
#print axioms SharedCoverage.Budget.no_reactivation
