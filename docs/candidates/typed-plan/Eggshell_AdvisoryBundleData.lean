module
public import Eggshell.Synapses
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

end Eggshell.Synapses.AdvisoryBundles
