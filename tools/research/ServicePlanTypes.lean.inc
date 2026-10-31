/- Native authority stays in the client renderer. These are advisory inputs
and selections over original coordinates, not serialized Selected values. -/
structure GenericUnit where
  family : Nat
  ranges : List (Nat × Nat)
  payloads : List Nat
  contextual : Bool
  deriving ToJson,FromJson

structure ServiceUnit where
  shape : UnitShape
  sourceKeys : Array Synapses.CanonicalSource.Key := #[]
  generic : Option Nat := none
  contextual : Bool := false

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

structure RenderChoice where
  slices : List TransportSlice
  receipt : Json
  selectorInput : Option Json := none
