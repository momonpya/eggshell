module

public import Eggshell.PluginModel

@[expose] public section

namespace Eggshell.Plugin
open Lean

/-- Stable DB identity and its append-only root insertion frontier. This is
publication metadata, never a claim that an omitted body was delivered. -/
structure AdvisoryFrontier where
  identity : String
  nextRoot : Nat
  deriving ToJson, FromJson, BEq

/-- A position checked against the exact pinned source that supplies it. -/
structure AdvisoryPosition where
  frontier : AdvisoryFrontier
  ordinal : Nat
  published : ordinal < frontier.nextRoot

def advisoryFrontierKey (question : String) (frontier : AdvisoryFrontier) : String :=
  "a:" ++ (toJson (question, frontier)).compress

def acceptedAdvisoryFrontier (question identity : String) (receipts : List String) : Option Nat :=
  (receipts.filterMap fun receipt => do
    if !receipt.startsWith "a:" then none else do
      let json ← (Json.parse (receipt.drop 2).toString).toOption
      let (recorded, frontier) ← (fromJson? json : Except String (String × AdvisoryFrontier)).toOption
      if recorded == question && frontier.identity == identity then some frontier.nextRoot else none).head?

/-- Reranking is not a new request. After the first accepted packet, old
advisory owners stay closed. New publications, another question/source and
independently grounded native operations remain eligible. -/
def advisoryPositionAllowed (accepted : Option Nat) (ordinal : Nat) : Bool :=
  accepted.all (fun limit => decide (limit ≤ ordinal))

theorem old_advisory_position_closed (ordinal limit : Nat) (old : ordinal < limit) :
    advisoryPositionAllowed (some limit) ordinal = false := by
  simp [advisoryPositionAllowed, Nat.not_le.mpr old]

theorem new_advisory_position_retained (ordinal limit : Nat) (fresh : limit ≤ ordinal) :
    advisoryPositionAllowed (some limit) ordinal = true := by
  simp [advisoryPositionAllowed, fresh]

theorem unaccepted_advisory_position_retained (ordinal : Nat) :
    advisoryPositionAllowed none ordinal = true := rfl

def advisoryOwnerAllowed (question : String) (receipts : List String)
    (positions : List AdvisoryPosition) : Bool :=
  positions.isEmpty || positions.any (fun position => advisoryPositionAllowed
    (acceptedAdvisoryFrontier question position.frontier.identity receipts) position.ordinal)

def advisoryTransportAllowed (grounded : Bool) (excluded : List Value) (owner : Value) : Bool :=
  grounded || !excluded.contains owner

theorem grounded_transport_retained (excluded : List Value) (owner : Value) :
    advisoryTransportAllowed true excluded owner = true := by
  simp [advisoryTransportAllowed]

theorem excluded_advisory_transport_closed (excluded : List Value) (owner : Value)
    (present : excluded.contains owner = true) :
    advisoryTransportAllowed false excluded owner = false := by
  unfold advisoryTransportAllowed
  rw [present]
  rfl

end Eggshell.Plugin
