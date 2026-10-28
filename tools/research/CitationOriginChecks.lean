import Eggshell.SynapseBundles
import Eggshell.SynapseBuild

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let [answerPath,scopePath,output] := args | throw (IO.userError "ANSWER SCOPE-REPORT NEW-OUTPUT")
  check (!(← System.FilePath.pathExists output)) "preserve previous origin checks"
  let fingerprint := String.ofList (List.replicate 64 'a')
  let file : File := ⟨"src/é x.cpp",fingerprint,4096⟩
  let wanted : Range := ⟨file,5,9⟩
  for (label,destination) in [
      ("é x.cpp:5-9","src/é x.cpp:5"),
      ("é x.cpp:L5-L9","src/é x.cpp:L5"),
      ("é x.cpp:L5–L9","src/%C3%A9%20x.cpp#L5-L9"),
      ("é x.cpp:5—9","<src/é x.cpp:L5-L9>")] do
    check (citation label destination #[file] == some wanted) "valid literal citation dropped"
  for bad in ["0","L0-L9","9-5","L9-L5","LL5","L5-LL9","L5-L9-L12","5-","x5"] do
    check ((parseBounds bad).isNone) "invalid interval accepted"
  check ((citation "é x.cpp:L5-L8" "src/é x.cpp:L5-L9" #[file]).isNone) "inconsistent label accepted"
  check ((citation "é x.cpp:L6-L9" "src/é x.cpp:L5" #[file]).isNone) "inconsistent start accepted"
  let occurrence : Occurrence := ⟨"session","turn","call"⟩
  let a : Read := ⟨occurrence,⟨file,5,5⟩,⟨"db","owner-a","work-a",0,10⟩,#[]⟩
  let b : Read := ⟨occurrence,⟨file,20,20⟩,⟨"db","owner-b","work-b",0,10⟩,#[]⟩
  let original : Original := ⟨"work-mcp",fingerprint,100⟩
  let c : Read := ⟨occurrence,Range.original original 0 10,⟨"db","owner-mcp","work-mcp",0,10⟩,#[]⟩
  check (#[a,b,c].all Read.valid) "invalid checked observation fixture"
  let document : Document := {
    owner := "answer",work := "answer-work",workText := none
    source := some "Use `TOKEN` and `OTHER`.",native := false,occurrences := #[],files := #[file]}
  let literal ← IO.ofExcept (ObservationContext.addQuotedAnswer "db" document
    #[⟨a,"TOKEN",none,none⟩,⟨b,"TOKEN",none,none⟩,⟨c,"OTHER",none,none⟩] .empty)
  let supports := literal.snapshot.filterMap fun fact => match fact with | .supports support => some support | _ => none
  check (supports.size == 3 && supports.all (·.basis == .spelling)) "ambiguous literal sources dropped or relabelled"
  check (literal.snapshot.all fun fact => match fact with | .coquoted .. => false | _ => true)
    "literal matches fabricated joint dependence"
  for support in supports do
    check ((Routing.jointGroup (.supports support)).isNone) "literal support has a joint group"
    let step := Routing.project (.answer "db" "answer") (.supports support)
    check (step.targets == #[.range support.source]) "literal target lost in routing"
    check (step.next.all fun key => match key with | .group _ => false | _ => true)
      "literal support enters a joint group"
  let claim : Claim := ⟨"db","answer",0,22⟩
  let direct ← IO.ofExcept (supportCitations .empty claim #[a.source,b.source] #[a,b])
  let cited := direct.snapshot.filterMap fun fact => match fact with | .supports support => some support | _ => none
  check (cited.size == 2 && cited.all (·.basis == .citation)) "coordinate support lost"
  for support in cited do
    check (Routing.jointGroup (.supports support) == some (.claim claim)) "coordinate dependence group lost"
  let arc : Routing.Store.Arc := ⟨fingerprint,6,none,#[1],#[2]⟩
  check ((← Routing.Store.decode (Routing.Store.encode arc)) == arc) "literal arc codec changed"
  let text ← IO.FS.readFile answerPath
  let scope ← IO.ofExcept (Json.parse (← IO.FS.readFile scopePath))
  let files ← (← IO.ofExcept (scope.getObjValAs? (Array Json) "canonicalFiles")).mapM fun row =>
    IO.ofExcept (row.getObjValAs? File "file")
  let mut links := #[]
  for part in (text.splitOn "](").dropLast.zip ((text.splitOn "](").tail) do
    let some label := (part.1.splitOn "[").getLast? | continue
    let some destination := (part.2.splitOn ")").head? | continue
    let range := citation label destination files
    check range.isSome "saved coordinate citation still rejected"
    links := links.push (Json.mkObj [("label",toJson label),("destination",toJson destination),("range",toJson range)])
  check (links.size == 36) "saved citation population changed"
  IO.FS.writeFile output (Json.mkObj [("allPassed",toJson true),("savedLinks",toJson links),
    ("accepted",toJson links.size),("literalAlternativesRetained",toJson supports.size),
    ("literalJointGroups",toJson (0 : Nat)),("coordinateSupports",toJson cited.size),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
  IO.println s!"Passed citation grammar, 36 saved links, literal alternatives, and direct dependence checks"
