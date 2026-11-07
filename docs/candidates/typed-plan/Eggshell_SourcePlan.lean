module
public import Eggshell.CanonicalSource
public import Eggshell.AdvisoryBundleData
@[expose] public section

namespace Eggshell.Plugin.SharedRangeAdapter
open Lean

structure CuePiece where
  family : Nat
  first : Nat
  last : Nat
  weight : Nat
  baseWeight : Nat := weight
  sourceKey : Option Synapses.CanonicalSource.Key := none
  deriving ToJson,FromJson

structure RankedCue where
  priority : Nat
  first : Nat
  last : Nat
  deriving BEq,ToJson,FromJson

/- Native authority stays in the client renderer. These are advisory inputs
and selections over original coordinates, not serialized Selected values. -/
structure GenericUnit where
  family : Nat
  ranges : List (Nat × Nat)
  payloads : List Nat
  contextual : Bool
  deriving ToJson,FromJson

structure FileQuery where
  family : Nat
  owner : String
  baseCues : List RankedCue
  allCues : List RankedCue
  groups : List (List (Nat × Nat))
  deriving ToJson,FromJson

structure ServiceQuery where
  owners : Array String
  works : Array (String × Nat)
  frameCosts : Array (Nat × Nat)
  scale : Nat
  genericCosts : Array (Nat × Nat)
  generic : Array GenericUnit
  pieces : List CuePiece
  files : Array FileQuery
  bundles : Array Synapses.AdvisoryBundles.Bundle
  fixed : Nat × Nat
  ceiling : Nat × Nat
  captureRanges : Bool := false
  captureInput : Bool := false
  deriving ToJson,FromJson

structure ServiceChoice where
  generic : Array Nat
  sourceKeys : Array Synapses.CanonicalSource.Key
  receipt : Json
  selectorInput : Option Json := none
  deriving ToJson,FromJson

end Eggshell.Plugin.SharedRangeAdapter
