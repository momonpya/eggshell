import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
import Eggshell.Sha256
open Lean

private def read (p : String) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def str (j : Json) (key : String) : String := (j.getObjValAs? String key).toOption.getD ""
private def arr (j : Json) (key : String) : Array Json := (j.getObjValAs? (Array Json) key).toOption.getD #[]
private def nat (j : Json) (key : String) : Nat := (j.getObjValAs? Nat key).toOption.getD 0
private def key (path : String) (line : Nat) := path ++ ":" ++ toString line

private structure Citation where
  path : String
  first : Nat
  last : Nat
  deriving BEq, ToJson

/-- Exhaust all explicit source citations in the seed answer. This is a
post-hoc diagnostic inventory, never a selector input or a new success gate. -/
private def citations (answer : String) : Array Citation := Id.run do
  let mut found := #[]
  let chars := answer.toList.toArray
  let mut cursor := 0
  while cursor < chars.size do
    if String.ofList (chars.extract cursor (cursor+6)).toList != "clang/" then
      cursor := cursor+1
      continue
    let suffix := String.ofList (chars.extract cursor chars.size).toList
    let path := String.ofList (suffix.toList.takeWhile fun c => c.isAlphanum || "/._-".contains c)
    cursor := cursor+path.length
    let tail := (suffix.drop path.length).toString
    if !tail.startsWith ":" then continue
    let digits := String.ofList ((tail.drop 1).toString.toList.takeWhile Char.isDigit)
    let some first := digits.toNat? | continue
    let rest := (tail.drop (digits.length+1)).toString
    let ending := if rest.startsWith "–" || rest.startsWith "-" then
      String.ofList ((rest.drop 1).toString.toList.takeWhile Char.isDigit) else ""
    let item : Citation := ⟨path,first,ending.toNat?.getD first⟩
    if !found.contains item then found := found.push item
  return found.filter fun item => !(item.first == item.last && found.any fun other =>
    other.path == item.path && other.first == item.first && other.last > item.last)

private def covers (ranges : Array Json) (first limit : Nat) : Bool := Id.run do
  let spans := ranges.filterMap fun row => (fromJson? (α := Nat × Nat) row).toOption
  let mut frontier := first
  for span in spans.qsort (fun a b => a.1 < b.1) do
    if span.1 ≤ frontier then frontier := max frontier span.2
  return limit ≤ frontier

def main (args : List String) : IO Unit := do
  let (exportPath,answerPath,bodyPath,receiptPath,output,actualReceipt,workspace) ← match args with
    | [e,a,b,"-",o,w] => pure (e,a,b,"-",o,none,w)
    | [e,a,b,t,o,r,w] => pure (e,a,b,t,o,some r,w)
    | _ => throw (IO.userError "ORIGINALS SEED-ANSWER ACTUAL-BODY TRACE-RECEIPT-OR-DASH NEW-REPORT [ACTUAL-RECEIPT] WORKSPACE")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve prior report")
  let original ← read exportPath
  let references := citations (← IO.FS.readFile answerPath)
  let rows := arr original "canonicalRows"
  let mut indexed : Std.HashMap String Json := {}
  for row in rows do
    let k := row.getObjValD "key"
    indexed := indexed.insert (key (str (k.getObjValD "file") "relative") (nat k "line")) row
  let mut delivered : Std.HashMap String String := {}
  let body ← IO.FS.readFile bodyPath
  let mut file := ""
  let mut code := false
  for line in body.splitOn "\n" do
    if line.startsWith "SOURCE {" then
      let value ← IO.ofExcept (Json.parse (line.drop 7).toString)
      file := str value "relative"
      code := false
    else if line == "CODE" then code := true
    else if line.startsWith "END " then code := false
    else if code then
      let parts := line.splitOn "\t"
      if let some number := (parts.headD "").toNat? then
        delivered := delivered.insert (key file number) ("\t".intercalate (parts.drop 1))
  let plan ← if receiptPath == "-" then pure Json.null else
    pure ((← read (receiptPath ++ "/selection-plan.json")).getObjValD "data")
  let families := arr plan "rangeAudit"
  let traceKnown := !families.isEmpty
  if let some actual := actualReceipt then
    let ordinary := ((← read (actual ++ "/selection-plan.json")).getObjValD "data")
    unless (["families","candidateUnits","selected","fixedCost","limit","scale","jointBindings","requiredSourceRows"].all
        fun field => plan.getObjValD field == ordinary.getObjValD field) do
      throw (IO.userError "diagnostic selection differs from actual model selection")
    -- This receipt precedes the independently checked freshness prefix.
    let parts := body.splitOn "EGGSHELL PRIOR WORK\n"
    let [_,payload] := parts | throw (IO.userError "one rendered handoff expected")
    let rendered := "EGGSHELL PRIOR WORK\n" ++ payload
    for receipt in #[actual,receiptPath] do
      let packet := ((← read (receipt ++ "/synaptic-delivery.json")).getObjValD "data")
      unless str packet "bodySha256" == Eggshell.Sha256.hex rendered.toUTF8 do
        throw (IO.userError "diagnostic or actual receipt describes a different packet")
  let domain ← if receiptPath == "-" then pure Json.null else
    pure ((← read (receiptPath ++ "/delivery-domain.json")).getObjValD "data")
  let hydrated := arr domain "hydrated"
  let rowCovers := fun (row : Json) (chosen : Bool) => (arr row "origins").any fun origin =>
    let binding := origin.getObjValD "binding"
    families.any fun family => str family "owner" == str binding "owner" &&
      covers ((arr family (if chosen then "selectedSharedRanges" else "candidateSharedRanges")) ++
        (arr family (if chosen then "selectedOriginalRanges" else "candidateOriginalRanges")))
        (nat binding "first") (nat binding "limit")
  let mut results := #[]
  let mut total := 0
  let mut shown := 0
  let mut missing := #[]
  let mut unindexed := #[]
  for citation in references do
    let referenceLines := ((← IO.FS.readFile (System.FilePath.mk workspace / citation.path)).splitOn "\n").toArray
    let mut lineAudit := #[]
    for number in [citation.first:citation.last+1] do
      let some row := indexed[key citation.path number]? | do
        let some reference := referenceLines[number-1]? | throw (IO.userError "citation exceeds source")
        lineAudit := lineAudit.push (Json.mkObj [("line",toJson number),("indexed",toJson false),
          ("nonblank",toJson (!reference.trimAscii.isEmpty)),("code",toJson reference)])
        if !reference.trimAscii.isEmpty then unindexed := unindexed.push (Json.mkObj [
          ("file",toJson citation.path),("line",toJson number),("code",toJson reference)])
        continue
      let sourceCode := str row "code"
      let exact := delivered[key citation.path number]? == some sourceCode
      let reached := (arr row "origins").any fun origin =>
        hydrated.contains (toJson (str (origin.getObjValD "binding") "owner"))
      let candidate := rowCovers row false
      let selected := rowCovers row true
      let reason := if exact then "delivered" else if !traceKnown then "trace-unavailable"
        else if !reached then "before-hydration" else if !candidate then "before-candidate"
        else if !selected then "selection" else "after-selection"
      lineAudit := lineAudit.push (Json.mkObj [("line",toJson number),("indexed",toJson true),
        ("nonblank",toJson (!sourceCode.trimAscii.isEmpty)),("bodyExact",toJson exact),
        ("candidate",if traceKnown then toJson candidate else Json.null),
        ("selected",if traceKnown then toJson selected else Json.null),("firstLoss",toJson reason),
        ("code",toJson sourceCode),("origins",row.getObjValD "origins")])
      if !sourceCode.trimAscii.isEmpty then
        total := total+1
        if exact then shown := shown+1
        else missing := missing.push (Json.mkObj [("file",toJson citation.path),("line",toJson number),
          ("code",toJson sourceCode),("firstLoss",toJson reason)])
    let available := lineAudit.filter fun row => row.getObjValD "indexed" == toJson true && row.getObjValD "nonblank" == toJson true
    results := results.push (Json.mkObj [("citation",toJson citation),
      ("indexedRows",toJson (lineAudit.countP (fun row => row.getObjValD "indexed" == toJson true))),
      ("storedNonblankRows",toJson available.size),
      ("deliveredNonblankRows",toJson (available.countP (fun row => row.getObjValD "bodyExact" == toJson true))),
      ("completeIndexedRange",toJson (lineAudit.all fun row => row.getObjValD "indexed" == toJson true)),
      ("allStoredNonblankDelivered",toJson (!available.isEmpty && available.all fun row => row.getObjValD "bodyExact" == toJson true)),
      ("rows",toJson lineAudit)])
  let result := Json.mkObj [("diagnosticOnly",toJson true),("citations",toJson results),
    ("citationCount",toJson references.size),("indexedNonblankRowsWithCitationOverlap",toJson total),
    ("deliveredNonblankRowsWithCitationOverlap",toJson shown),("missing",toJson missing),
    ("unindexedNonblankRows",toJson unindexed),
    ("allSeedCitationsAudited",toJson true),("traceKnown",toJson traceKnown),
    ("actualModelBodyAndSelectionMatched",toJson actualReceipt.isSome),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output result.pretty
  IO.println (Json.mkObj [("citations",toJson references.size),("indexedNonblank",toJson total),
    ("deliveredNonblank",toJson shown),("missing",toJson missing.size),("traceKnown",toJson traceKnown)]).compress
