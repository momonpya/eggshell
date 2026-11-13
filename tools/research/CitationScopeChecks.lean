import Eggshell.SynapseExtraction
open Lean Eggshell.Synapses Eggshell.Synapses.Extraction
namespace CitationScopeChecks
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def file : File := ⟨"src/example.txt",String.ofList (List.replicate 64 'a'),100⟩
def recorded : Read := ⟨⟨"s","t","u"⟩,⟨.file file,10,12⟩,⟨"db","owner","work",0,40⟩, #[]⟩
def row (first stop : Nat) : Read := {recorded with
  source := ⟨.file file,11,11⟩
  binding := {recorded.binding with first,limit := stop}}
def claim : Claim := ⟨"db","answer",0,10⟩
def run (fixed : Bool) (output : String) : IO Unit := do
  check (!(← (System.FilePath.mk output).pathExists)) "preserve existing scope regression results"
  let correct := row 10 20
  let duplicate := row 60 70
  let foreign := {correct with occurrence := ⟨"other","t","u"⟩}
  let changed := {correct with source := ⟨.file {file with fingerprint := String.ofList (List.replicate 64 'b')},11,11⟩}
  let mut reports := #[]
  for (name,rows,supports,refused) in #[
      ("bounded-row",#[correct],1,false),
      ("repeated-file-line-in-later-output-interval",#[correct,duplicate],if fixed then 1 else 0,!fixed),
      ("duplicate-before-correct-row",#[duplicate,correct],if fixed then 1 else 0,!fixed),
      ("foreign-occurrence",#[foreign],0,false),
      ("changed-file-fingerprint",#[changed],0,false),
      ("only-outside-original-interval",#[duplicate],0,!fixed)] do
    let result := supportCitations .empty claim #[⟨.file file,11,11⟩] #[recorded] rows
    let count := match result with
      | .error _ => 0
      | .ok graph => (graph.snapshot.filter fun fact => match fact with | .supports _ => true | _ => false).size
    check (result.isOk == !refused && count == supports) ("citation scope regression failed: "++name)
    reports := reports.push (Json.mkObj [("name",toJson name),("supports",toJson count),
      ("refused",toJson (!result.isOk)),("expected",toJson true)])
  IO.FS.writeFile output (Json.mkObj [("fixedConsumer",toJson fixed),("cases",toJson reports),
    ("allPassed",toJson true),("claimsTotalTokenImprovement",toJson false)]).compress
end CitationScopeChecks
def main : List String → IO Unit
  | ["old",output] => CitationScopeChecks.run false output
  | ["fixed",output] => CitationScopeChecks.run true output
  | _ => throw (IO.userError "CitationScopeChecks old|fixed OUTPUT")
