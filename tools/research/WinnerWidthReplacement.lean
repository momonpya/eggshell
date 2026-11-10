module
public import tools.WinnerCache
public import tools.research.WinnerWidth
@[expose] public section

namespace SharedCoverage.Deferred.VerifiedWinner
open StableWinnerIndex
variable {p : Problem} {depth : Nat}

/-- Keep the original point-update order and evaluate the tree width once.
No mapped update list, new cache, or scheduling boundary is introduced. -/
def updateManyWidth (_capacity : p.offers.size ≤ 2^depth)
    (cache : Cache (Rating.preference p.offers.size) depth) (indices : List (Fin p.offers.size))
    (replacement : Nat → Option (Rating.Key p.offers.size)) : Cache (Rating.preference p.offers.size) depth :=
  let width := 2^depth
  indices.foldl (fun cache index => Width.updated cache.tree width index.val (replacement index.val)) cache

end SharedCoverage.Deferred.VerifiedWinner
