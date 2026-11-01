import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin

#print axioms fragment_render_key_exact
#print axioms priced_fragments_mem

namespace Eggshell.Research.PricedFragmentAudit
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def context (source : String) (fragments : List DeliveryFragment) : ContextDelivery := {
  owner := "owner",outcome := "original",sourceChars := source.length+10,
  leading := "header\n",trailing := "\nfooter",cues := [],fragments}
private def charge (fragments : List DeliveryFragment) : Nat × Nat :=
  fragments.foldl (fun total fragment =>
    let text := fragment.render false
    (total.1+text.length+1,total.2+text.utf8ByteSize+1)) (0,0)
private def unit (fragment : DeliveryFragment) : SharedRangeAdapter.UnitPlan :=
  let ctx := context fragment.original [fragment]
  {family := 0,ranges := [(fragment.first,fragment.first+fragment.original.length)],
    slice := {owner := none,keys := ctx.keys,text := ctx.render,context := some ctx,members := [],visibleKeys := []}}

def run : IO Unit := do
  let plain : DeliveryFragment := ⟨10,"42",false,none⟩
  let named := {plain with path := some [.key "count"]}
  check ((plain.first,plain.original,plain.decoded) == (named.first,named.original,named.decoded) &&
      (plain.render false).length < (named.render false).length &&
      plain.renderKey false != named.renderKey false)
    "a display address can still alias a cheaper original fragment"
  let some (costs,_payloads,closures) := LinearOutput.pairLoop (SharedRangeAdapter.LinearNodes.step {} {})
      [unit plain,unit named] #[(0,0)] {} [] |
    throw (IO.userError "priced original preparation failed")
  let some left := closures[0]?.bind (fun row => row[1]?) | throw (IO.userError "missing plain price")
  let some right := closures[1]?.bind (fun row => row[1]?) | throw (IO.userError "missing named price")
  check (left != right && costs[left]? == some (charge [plain]) && costs[right]? == some (charge [named]))
    "the cost table reused a different presentation's price"
  let source := "abcdefghij"
  let tiny : DeliveryFragment := ⟨13,"d",false,none⟩
  let whole : DeliveryFragment := ⟨10,source,false,none⟩
  let before := context source [tiny]
  let offered := context source [whole]
  let some unpriced := checkedContextExtension before offered |
    throw (IO.userError "reference original overlap failed")
  check ((charge unpriced.val.fragments).1 > (charge [tiny,whole]).1)
    "the reference no longer demonstrates unpriced caption creation"
  let some priced := checkedPricedContextAssembly before offered |
    throw (IO.userError "whole priced originals cannot be assembled")
  check (priced.val.fragments.length == 2 && charge priced.val.fragments == charge [whole,tiny])
    "assembly changed an already-priced original piece"
  let some repeated := checkedPricedContextAssembly offered offered |
    throw (IO.userError "duplicate priced original failed")
  check (repeated.val.fragments.length == 1 && charge repeated.val.fragments == charge [whole])
    "identical priced original was charged or rendered twice"
  IO.println "priced fragments: address-price alias and post-price slicing regressions rejected; whole pieces and duplicates checked"
end Eggshell.Research.PricedFragmentAudit
