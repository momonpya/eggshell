import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin

namespace Eggshell.Plugin
def legacyFragmentAgreement (next prior : DeliveryFragment) : Prop :=
  let first := max next.first prior.first
  let last := min (next.first+next.original.length) (prior.first+prior.original.length)
  first < last → next.decoded = prior.decoded ∧
    ((next.original.drop (first-next.first)).take (last-first)).copy =
      ((prior.original.drop (first-prior.first)).take (last-first)).copy
instance (next prior : DeliveryFragment) : Decidable (legacyFragmentAgreement next prior) := by
  unfold legacyFragmentAgreement
  infer_instance

theorem fragment_agreement_ignores_display (next prior : DeliveryFragment) (a b : Bool) :
    ({next with decoded := a}.agrees {prior with decoded := b}) = next.agrees prior := rfl

theorem legacy_fragment_agreement_preserved (next prior : DeliveryFragment)
    (accepted : legacyFragmentAgreement next prior) : next.agrees prior := by
  intro overlap
  exact (accepted overlap).2

theorem conflicting_original_rejected (next prior : DeliveryFragment)
    (overlap : max next.first prior.first < min (next.first+next.original.length) (prior.first+prior.original.length))
    (different : ((next.original.drop (max next.first prior.first-next.first)).take
      (min (next.first+next.original.length) (prior.first+prior.original.length)-max next.first prior.first)).copy ≠
      ((prior.original.drop (max next.first prior.first-prior.first)).take
      (min (next.first+next.original.length) (prior.first+prior.original.length)-max next.first prior.first)).copy) :
    ¬next.agrees prior := by
  intro accepted
  exact different (accepted overlap)

#print axioms fragment_agreement_ignores_display
#print axioms legacy_fragment_agreement_preserved
#print axioms conflicting_original_rejected
end Eggshell.Plugin

namespace Eggshell.Research.FragmentSourceIdentityAudit
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def context (source : String) (fragments : List DeliveryFragment) : ContextDelivery := {
  owner := "record-owner",outcome := "immutable-output",sourceChars := 10+source.length,
  leading := "original envelope\n",trailing := "\nend",cues := [],fragments}

def run : IO Unit := do
  let source := "alpha\\nbeta"
  let decoded : DeliveryFragment := ⟨10,source,true,none⟩
  let raw := {decoded with decoded := false}
  check (!decide (legacyFragmentAgreement raw decoded) && decide (raw.agrees decoded))
    "display flag still changes original identity"
  let some joined := checkedContextExtension (context source [decoded]) (context source [raw]) |
    throw (IO.userError "identical raw/decoded originals cannot be joined")
  check (joined.val.fragments.length == 1 && joined.val.keys == (context source [decoded]).keys)
    "identical original was duplicated or acquired another identity"
  for source in ["abc\\ndef","日本語\\n末尾","한글\\n끝","caf\u00e9\\tfin"] do
    let count := max 1 (source.length/2)
    let part : DeliveryFragment := ⟨10,(source.take count).copy,true,none⟩
    let whole : DeliveryFragment := ⟨10,source,false,none⟩
    let some merged := checkedContextExtension (context source [part]) (context source [whole]) |
      throw (IO.userError "mixed display rejected a partial original overlap")
    check (String.ofList (merged.val.fragments.flatMap (·.original.toList)) == source &&
      merged.val.fragments.head?.map toJson == some (toJson part)) "partial merge changed or duplicated raw original characters"
    let some reverse := checkedContextExtension (context source [whole]) (context source [part]) |
      throw (IO.userError "reverse mixed-display merge failed")
    check (reverse.val.fragments.length == 1 && reverse.val.fragments.head?.map toJson == some (toJson whole))
      "reverse merge manufactured another original"
  let conflict := {raw with original := "XXXXX\\nbeta"}
  check ((checkedContextExtension (context source [decoded]) (context source [conflict])).isNone)
    "different original bytes were accepted"
  for foreign in [{(context source [raw]) with owner := "other-owner"},
      {(context source [raw]) with outcome := "other-output"},
      {(context source [raw]) with sourceChars := 1000}] do
    check ((checkedContextExtension (context source [decoded]) foreign).isNone)
      "different original envelope was accepted"
  IO.println "fragment source identity: mixed display, partial overlap, reverse, conflicts and scope checks passed"
end Eggshell.Research.FragmentSourceIdentityAudit
