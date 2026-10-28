import Eggshell.SynapseSource

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.Extraction

/-- Pure replay of saved answer links against the exact recorded file scope.
Normalization is a diagnostic counterfactual, never a product write or an
assertion that these ranges reached a model. -/
def main (args : List String) : IO Unit := do
  let [answerPath,scopePath,output] := args | throw (IO.userError "ANSWER SCOPE-REPORT NEW-OUTPUT")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve previous citation syntax audit")
  let text ← IO.FS.readFile answerPath
  let scope ← IO.ofExcept (Json.parse (← IO.FS.readFile scopePath))
  let files ← (← IO.ofExcept (scope.getObjValAs? (Array Json) "canonicalFiles")).mapM fun row =>
    IO.ofExcept (row.getObjValAs? File "file")
  let mut links := #[]
  for part in (text.splitOn "](").dropLast.zip ((text.splitOn "](").tail) do
    let some label := (part.1.splitOn "[").getLast? | continue
    let some destination := (part.2.splitOn ")").head? | continue
    let original := citation label destination files
    let normalizedLabel := (label.replace ":L" ":").replace "-L" "-"
    let normalizedDestination := (destination.replace ":L" ":").replace "-L" "-"
    let normalized := citation normalizedLabel normalizedDestination files
    links := links.push (Json.mkObj [("label",toJson label),("destination",toJson destination),
      ("original",toJson original),("afterOptionalLNormalization",toJson normalized)])
  let accepted := links.countP (fun row => row.getObjValD "original" != Json.null)
  let after := links.countP (fun row => row.getObjValD "afterOptionalLNormalization" != Json.null)
  let report := Json.mkObj [("links",toJson links),("originalAccepted",toJson accepted),
    ("normalizedAccepted",toJson after),("sourceBytesUnchanged",toJson ((← IO.FS.readFile answerPath) == text)),
    ("runtimeChanged",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
  IO.println (Json.mkObj [("links",toJson links.size),("originalAccepted",toJson accepted),
    ("normalizedAccepted",toJson after)]).compress
