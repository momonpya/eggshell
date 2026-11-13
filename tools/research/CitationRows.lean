module
public import Eggshell.Synapses
@[expose] public section
open Eggshell.Synapses
namespace CitationRows
/-- File coordinates can repeat within one output. A row also belongs to its
particular original-output interval, not just its occurrence and file line. -/
def sameOriginal (recorded row : Read) : Bool := decide (
  row.occurrence = recorded.occurrence ∧ row.binding.database = recorded.binding.database ∧
  row.binding.owner = recorded.binding.owner ∧ row.binding.work = recorded.binding.work)
def within (recorded row : Read) : Bool := decide (
  recorded.binding.first ≤ row.binding.first ∧ row.binding.limit ≤ recorded.binding.limit)
def accepts (recorded : Read) (source : Range) (row : Read) : Bool :=
  sameOriginal recorded row && within recorded row && source.contains row.source
def forCitation (recorded : Read) (source : Range) (original : Array Read) : Array Read :=
  original.filter (accepts recorded source)
theorem within_bounds (checked : within recorded row = true) :
    recorded.binding.first ≤ row.binding.first ∧ row.binding.limit ≤ recorded.binding.limit :=
  of_decide_eq_true checked
theorem accepts_bounds (checked : accepts recorded source row = true) :
    recorded.binding.first ≤ row.binding.first ∧ row.binding.limit ≤ recorded.binding.limit := by
  simp only [accepts,Bool.and_eq_true] at checked
  exact within_bounds checked.1.2
theorem preserves_contained (bounded : within recorded row = true) :
    accepts recorded source row = (sameOriginal recorded row && source.contains row.source) := by
  simp [accepts,bounded]
end CitationRows
