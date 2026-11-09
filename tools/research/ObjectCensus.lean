module
public import Eggshell.Receipt
public import Lean.Data.Json.Parser
@[expose] public section
namespace Eggshell.Research.ObjectCensus
open Lean

/-- C is confined to the installed Lean object-layout API. Roots are borrowed
and immutable; mutable refs, closures, external values and tasks are leaves. -/
@[extern "eggshell_research_object_census"]
opaque raw {α : Type} (root : @& α) : IO String

def inspect (root : α) : IO Json := do
  let result ← IO.ofExcept (Json.parse (← raw root))
  unless result.getObjValD "allocationFailed" == toJson false do
    throw (IO.userError "bounded object census could not allocate its private workspace")
  return result

def observe (stage : String) (root : α) : IO Unit := do
  let started ← IO.monoNanosNow
  let result ← inspect root
  let result := result.setObjVal! "elapsedUs" (toJson (((← IO.monoNanosNow)-started)/1000))
    |>.setObjVal! "stage" (toJson stage)
    |>.setObjVal! "notRssOrWholeHeap" (toJson true)
  Receipt.observe (some (← Receipt.fresh)) "object-census" result

end Eggshell.Research.ObjectCensus
