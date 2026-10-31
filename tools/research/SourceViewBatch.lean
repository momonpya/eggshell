module
public import Eggshell.CanonicalSourcePrepared
public import tools.research.OwnerPalette
@[expose] public section

namespace Eggshell.Synapses.SourceViewBatch
open Lean CanonicalSource

/-- Capabilities travel only in authenticated transient requests. They are
excluded from identities, receipts, cache keys and persisted query data. -/
structure Request where
  access : Shared.Access
  owners : Array String
  deriving ToJson,FromJson

def key (parts : Array Request) : String :=
  (toJson (parts.map fun part => (part.access.identity,part.owners))).compress

structure Palette where
  identities : Array Json
  lease : String
  owners : Array (Array (String × OwnerPalette.Descriptor))
  reuse : Array Shared.Reuse
  deriving ToJson,FromJson

structure Fetch where
  source : Nat
  requests : Array OwnerPalette.Fetch
  deriving ToJson,FromJson

structure Reply where
  identities : Array Json
  parts : Array (Nat × OwnerPalette.Reply)
  deriving ToJson,FromJson

end Eggshell.Synapses.SourceViewBatch
