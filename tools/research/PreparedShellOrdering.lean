module
public import tools.research.PreparedPlanMetadata
public import tools.research.PreparedSourceView
@[expose] public section

namespace Eggshell.Research.PreparedShellOrdering
open Lean Synapses CanonicalSource

/-- The existing immutable file headers already carry this exact encoding.
The lookup is advisory metadata, with no original bytes or certification. -/
abbrev Orders := Std.HashMap File PreparedSourceView.FileReady

def text (orders : Orders) (file : File) : String :=
  match orders[file]? with
  | none => (toJson file).compress
  | some ready =>
      if ready.stored.file = file then ready.stored.order else (toJson file).compress

theorem text_exact (orders : Orders) (file : File) :
    text orders file = (toJson file).compress := by
  unfold text
  split
  · rfl
  · rename_i ready _
    split
    · rename_i same
      rw [← same]
      exact ready.ordered
    · rfl

def before (orders : Orders) (a b : Key) : Bool :=
  if a.file == b.file then a.line < b.line else text orders a.file < text orders b.file

theorem before_exact (orders : Orders) : before orders =
    (fun a b : Key => if a.file == b.file then decide (a.line < b.line) else
      decide ((toJson a.file).compress < (toJson b.file).compress)) := by
  funext a b
  simp only [before,text_exact]

def combine (orders : Orders) (shells : Array PreparedPlanMetadata.Shell) : PreparedPlanMetadata.Shell :=
  let keys := (hashDistinct ((shells.flatMap (·.keys)).toList)).toArray.qsort (before orders)
  ⟨keys,hashDistinct (shells.toList.flatMap (·.owners))⟩

theorem combine_exact (orders : Orders) (shells : Array PreparedPlanMetadata.Shell) :
    combine orders shells = PreparedPlanMetadata.combine shells := by
  simp only [combine,before_exact,PreparedPlanMetadata.combine]

def locators (orders : Orders) (shell : PreparedPlanMetadata.Shell) : String := Id.run do
  let ordered := shell.keys.qsort (before orders)
  let mut ranges : Array Range := #[]
  for key in ordered do
    if let some previous := ranges.back? then
      if previous.subject == .file key.file && key.line ≤ previous.last+1 then
        ranges := ranges.pop.push {previous with last := max previous.last key.line}
        continue
    ranges := ranges.push ⟨key.file,key.line,key.line⟩
  if ranges.isEmpty then return ""
  return "\nSAVED SOURCE POSITIONS\nPositions alone are not delivered code; CODE blocks contain the delivered rows.\n" ++
    "\n".intercalate ((Delivery.Locations.pack ranges.toList).map fun group => (toJson group).compress) ++
    "\nEND SAVED SOURCE POSITIONS\n"

theorem locators_exact (orders : Orders) (shell : PreparedPlanMetadata.Shell) :
    locators orders shell = PreparedPlanMetadata.locators shell := by
  unfold locators PreparedPlanMetadata.locators
  rw [before_exact]
  rfl

end Eggshell.Research.PreparedShellOrdering
