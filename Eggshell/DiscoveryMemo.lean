module

public import Eggshell.RankMemo
public import Eggshell.SaturationMemo

@[expose] public section
namespace Eggshell.Plugin.DiscoveryMemo
open Persistence DB Matcher

/-- Only completed unweighted geometry, ranking permutations and certified
join instructions. This is optional advice in the existing DB, never a
partial answer, an Outcome, or serialized source body. -/
structure Packet where
  ranks : RankMemo.Saved := []
  selections : RankMemo.Saved := []
  contexts : RankMemo.Saved := []
  saturation : Option SaturationMemo.Saved := none
  deriving DecidableEq

def Packet.empty (packet : Packet) : Bool :=
  packet.ranks.isEmpty && packet.selections.isEmpty && packet.contexts.isEmpty &&
    packet.saturation.isNone

/-- The observed producer supplies the actual checked join generation.
Ordinal hints are not assumed to retain a proof on disk; the current-domain
certifier checks them again on the next request. -/
def Packet.withPlan (packet : Packet) (roots : List Value) (edges : List UnionEdge)
    (plan : Option QuotientBuilder.CongruenceMemo.Entry) : Packet :=
  {packet with saturation := plan.map (fun plan => SaturationMemo.capturePlan
      (SaturationMemo.Basis.make (SaturationMemo.kernelValues roots edges)) plan)}

theorem captured_producer (packet : Packet) (roots : List Value) (edges : List UnionEdge)
    (plan : QuotientBuilder.CongruenceMemo.Entry) :
    (packet.withPlan roots edges (some plan)).saturation = some
      (SaturationMemo.pack
        (SaturationMemo.Basis.make (SaturationMemo.kernelValues roots edges))
        (SaturationMemo.allowance - 1)
        (plan.rows.zip (QuotientBuilder.CongruenceMemo.instructions {} plan.rows))) := by
  change some (SaturationMemo.capturePlan _ plan) = _
  rw [SaturationMemo.capturePlan_producer]

theorem captured_bounded (packet : Packet) (roots : List Value) (edges : List UnionEdge)
    (plan : QuotientBuilder.CongruenceMemo.Entry) :
    (packet.withPlan roots edges (some plan)).saturation.all
      (fun saved => decide (SaturationMemo.codec.encodedSize saved ≤ SaturationMemo.allowance)) = true := by
  change decide (SaturationMemo.codec.encodedSize (SaturationMemo.capturePlan _ plan) ≤
    SaturationMemo.allowance) = true
  rw [decide_eq_true_eq]
  exact SaturationMemo.capturePlan_bounded _ _

/-- A checkpoint from any earlier boundary is certified against today's
input. Correction, deletion and a different ordinal basis cannot import an
old equality into the actual current quotient producer. -/
theorem captured_restore_exact (packet : Packet) (roots : List Value) (edges : List UnionEdge)
    (plan : QuotientBuilder.CongruenceMemo.Entry) (currentBasis : SaturationMemo.Basis)
    (currentRoots : List Value) (persistent runLocal : List UnionEdge) :
    ((packet.withPlan roots edges (some plan)).saturation.map fun saved =>
      (QuotientBuilder.plannedBuild? currentRoots persistent runLocal
        (SaturationMemo.restore currentBasis saved)).quotient) =
      some (QuotientBuilder.build? currentRoots persistent runLocal) := by
  exact congrArg some (SaturationMemo.restored_build_exact currentBasis
    (SaturationMemo.capturePlan (SaturationMemo.Basis.make
      (SaturationMemo.kernelValues roots edges)) plan) currentRoots persistent runLocal)

/-- One fail-fast writer ownership and one publication for the complete
boundary. Unchanged slots append nothing. The existing writer enforces a
derived-only trace before accepting the empty graph delta. -/
def publish (path : System.FilePath) (packet : Packet) : IO Unit := do
  if packet.empty then return
  let snapshot ← PageMap.pin path
  let _ ← PageMap.withWriter snapshot fun writer => do
    let ranks ← RankMemo.publishUsing writer packet.ranks
    let selections ← RankMemo.publishUsing writer packet.selections .selection
    let contexts ← RankMemo.publishUsing writer packet.contexts .context
    let saturation ← match packet.saturation with
      | none => pure false
      | some saved => SaturationMemo.publishUsing writer saved
    if ranks || selections || contexts || saturation then
      Store.writeChange writer ⟨[], [], false⟩
  pure ()

/-- A busy optional publisher is retried only at another completed boundary,
never in a wait loop. A failed attempt cannot acknowledge lost work. -/
structure Publisher where
  path : System.FilePath
  acknowledged : IO.Ref (Option Packet)

def Publisher.new (path : System.FilePath) : IO Publisher :=
  return ⟨path, ← IO.mkRef none⟩

def Publisher.checkpoint (publisher : Publisher) (packet : Packet) : IO Unit := do
  if (← publisher.acknowledged.get) = some packet then return
  try
    publish publisher.path packet
    publisher.acknowledged.set (some packet)
  catch _ => pure ()

end Eggshell.Plugin.DiscoveryMemo
