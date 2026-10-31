module
public import Eggshell.SynapseBundles
@[expose] public section

namespace Eggshell.Synapses.AdvisoryBundles
open Lean

/-- The selector consumes original coordinates as recommendation hints.
No Match, native Outcome, Union or completion certificate crosses this wire. -/
structure Choice where
  owner : String
  spans : List (Nat × Nat)
  deriving BEq,ToJson,FromJson

structure Member where
  source : Range
  choices : Array Choice
  deriving BEq,ToJson,FromJson

structure Bundle where
  members : Array Member
  deriving BEq,ToJson,FromJson

def ofProjected (projected : Bundles.Projected) : Bundle :=
  ⟨projected.members.map fun member =>
    ⟨member.source,member.choices.map fun choice => ⟨choice.owner,choice.spans⟩⟩⟩

theorem sources_unchanged (projected : Bundles.Projected) :
    (ofProjected projected).members.map (·.source) = projected.members.map (·.source) := by
  simp [ofProjected,Array.map_map]

theorem choices_unchanged (projected : Bundles.Projected) (index : Fin projected.members.size) :
    ((ofProjected projected).members[index.val]?).map (·.choices) =
      some (projected.members[index].choices.map (fun choice => (⟨choice.owner,choice.spans⟩ : Choice))) := by
  simp [ofProjected,index.isLt]

end Eggshell.Synapses.AdvisoryBundles
