import Lean.Data.Json.FromToJson
open Lean
namespace Eggshell.Research.StudyProfile

/-- A sealed arm chooses its own envelope. There is no implicit study default. -/
def checked (chars : Nat) : Except String {value : Nat // 0 < value} :=
  if positive : 0 < chars then .ok ⟨chars,positive⟩ else .error "study handoff budget must be positive"

theorem checked_preserves_value (chars : Nat) (value : {value : Nat // 0 < value})
    (accepted : checked chars = .ok value) : value.val = chars := by
  unfold checked at accepted
  split at accepted
  · cases accepted; rfl
  · contradiction

def render (runtime database : String) (budget : {value : Nat // 0 < value}) (write : Bool := true) : String :=
  "default = \"work\"\nsemantic_matcher = " ++ (toJson #[runtime,"search-provider"]).compress ++
  "\n[eggs]\nwork = " ++ (toJson database).compress ++ "\n[profiles.work]\nread = [\"work\"]\n" ++
  (if write then "write = \"work\"\n" else "") ++ s!"handoff_chars = {budget.val}\n"

end Eggshell.Research.StudyProfile
