module
public import tools.PreparedCueIndex
public import Eggshell.HashDistinct
@[expose] public section
namespace Eggshell.Research.HashedCueKeys
variable {α : Type} {keyOf : α → String} {values : Array α}

/-- Bucket probes retain the same first-occurrence order without repeatedly
comparing every new key against a growing list. Full strings decide equality. -/
def many (prepared : PreparedCueIndex.Prepared keyOf values) (keys : List String)
    (accept : α → Bool) : List α :=
  (prepared.index.select (hashDistinct keys) (fun i => accept values[i.val])).map (fun i => values[i.val])

theorem many_exact : @many = @PreparedCueIndex.Prepared.many := by
  funext α keyOf values prepared keys accept
  simp only [many,PreparedCueIndex.Prepared.many,HashDistinct.reference]

#print axioms many_exact
end Eggshell.Research.HashedCueKeys
