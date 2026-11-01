abbrev TargetTree (rows : Array Target) :=
  Eggshell.Research.CertifiedRangeDirectory.Tree (fun target : Target => target.range.lower)
    (fun target : Target => target.range.upper) rows.toList

structure ReadDirectory where
  rows : Array Target
  tree : TargetTree rows

def ReadDirectory.prepare (rows : Array Target) : ReadDirectory :=
  ⟨rows,(Eggshell.Research.CertifiedRangeDirectory.prepare (fun target : Target => target.range.lower)
    (fun target : Target => target.range.upper) rows.toList).tree⟩

def ReadDirectory.find? (directory : ReadDirectory) (key : String) : Option Target :=
  Eggshell.Research.CertifiedRangeDirectory.Tree.find? _ _ directory.tree key

def ReadDirectory.anyOverlap (directory : ReadDirectory) (ref : PageMap.Ref) : Bool :=
  Eggshell.Research.CertifiedRangeDirectory.Tree.anyOverlap _ _ directory.tree ref.first ref.last

theorem ReadDirectory.find_exact (directory : ReadDirectory) (key : String) :
    directory.find? key = directory.rows.find? (fun target => target.range.contains key) := by
  simpa only [ReadDirectory.find?,PageMap.KeyRange.contains,Array.find?_toList,
    Eggshell.Research.CertifiedRangeDirectory.contains] using
    Eggshell.Research.CertifiedRangeDirectory.Tree.find_exact _ _ directory.tree key

theorem ReadDirectory.overlap_exact (directory : ReadDirectory) (ref : PageMap.Ref) :
    directory.anyOverlap ref = directory.rows.toList.any (fun target => target.range.overlaps ref) := by
  exact Eggshell.Research.CertifiedRangeDirectory.Tree.overlap_exact _ _ directory.tree ref.first ref.last

/-- A leaf key is tested against the complete target tree. Page fences prove
that filtering targets at this page could not change its first match. -/
theorem ReadDirectory.find_after_filter (directory : ReadDirectory) (ref : PageMap.Ref)
    (key : String) (bounded : ref.first ≤ key ∧ key ≤ ref.last) :
    (relevant directory.rows ref).find? (fun target => target.range.contains key) = directory.find? key := by
  rw [ReadDirectory.find_exact]
  simp only [relevant,← Array.find?_toList,Array.toList_filter,List.find?_filter]
  congr 1
  funext target
  by_cases matched : target.range.contains key = true
  · have contained := of_decide_eq_true matched
    have overlap : target.range.overlaps ref = true := by
      simp only [PageMap.KeyRange.overlaps,decide_eq_true_eq]
      exact ⟨String.le_trans contained.1 bounded.2,Std.lt_of_le_of_lt bounded.1 contained.2⟩
    simp [matched,overlap]
  · simp [Bool.eq_false_iff.mpr matched]

theorem ReadDirectory.overlap_after_filter (directory : ReadDirectory) (parent child : PageMap.Ref)
    (bounded : parent.first ≤ child.first ∧ child.last ≤ parent.last) :
    (relevant directory.rows parent).toList.any (fun target => target.range.overlaps child) = directory.anyOverlap child := by
  rw [ReadDirectory.overlap_exact]
  simp only [relevant,Array.toList_filter,List.any_filter]
  congr 1
  funext target
  by_cases matched : target.range.overlaps child = true
  · have contained := of_decide_eq_true matched
    have overlap : target.range.overlaps parent = true := by
      simp only [PageMap.KeyRange.overlaps,decide_eq_true_eq]
      exact ⟨String.le_trans contained.1 bounded.2,Std.lt_of_le_of_lt bounded.1 contained.2⟩
    simp [matched,overlap]
  · simp [Bool.eq_false_iff.mpr matched]
