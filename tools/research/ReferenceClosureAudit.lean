import Eggshell.CanonicalSourceCache
import Eggshell.CanonicalSourceDelivery
import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Lean.Data.Json.Parser

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

private def field [FromJson α] (value : Json) (name : String) : IO α :=
  IO.ofExcept (value.getObjValAs? α name)

private def covers (ranges : List (Nat × Nat)) (first last : Nat) : Bool :=
  last ≤ ((ranges.mergeSort fun a b => a.1 ≤ b.1).foldl
    (fun frontier (a,b) => if a ≤ frontier then max frontier b else frontier) first)

private structure Token (size : Nat) where
  text : String
  name : Bool
  row : Fin size
  run : Nat

/-- A deliberately limited lexical diagnostic. A matching name is not a
C++ binding, a necessary dependency, or an authority to suppress a tool. -/
private def lex (raw : Array (Char × Fin size)) (run : Nat) : Array (Token size) := Id.run do
  let char (position : Nat) := (raw[position]?).map Prod.fst |>.getD '\x00'
  let identifier (c : Char) := c.isAlphanum || c == '_'
  let mut result := #[]
  let mut cursor := 0
  while cursor < raw.size do
    let some (c,row) := raw[cursor]? | break
    if c.isWhitespace then cursor := cursor+1
    else if c == '/' && char (cursor+1) == '/' then
      cursor := cursor+2
      while cursor < raw.size && char cursor != '\n' do cursor := cursor+1
    else if c == '/' && char (cursor+1) == '*' then
      cursor := cursor+2
      while cursor < raw.size && !(char cursor == '*' && char (cursor+1) == '/') do
        cursor := cursor+1
      cursor := min raw.size (cursor+2)
    else if c == '"' || c == '\'' then
      result := result.push ⟨"quoted",false,row,run⟩
      cursor := cursor+1
      while cursor < raw.size && char cursor != c do
        cursor := min raw.size (cursor + if char cursor == '\\' then 2 else 1)
      cursor := min raw.size (cursor+1)
    else if c.isAlpha || c == '_' then
      let first := cursor
      cursor := cursor+1
      while cursor < raw.size && identifier (char cursor) do cursor := cursor+1
      let text := String.ofList ((raw.extract first cursor).toList.map Prod.fst)
      result := result.push ⟨text,true,row,run⟩
    else
      result := result.push ⟨String.singleton c,false,row,run⟩
      cursor := cursor+1
  return result

private structure Block (size : Nat) where
  name : String
  nameToken : Nat
  first : Fin size
  last : Fin size

/-- Recognize only balanced `name (...) { ... }` shapes within an observed
contiguous run. Control statements can have this shape as well. Report this
limitation rather than silently treating this as a language resolver. -/
private def blocks (tokens : Array (Token size)) : Array (Block size) := Id.run do
  let mut result := #[]
  let mut parentheses : List Nat := []
  let mut matching : Std.HashMap Nat Nat := {}
  let mut braces : List (Option (Nat × Token size)) := []
  let mut previousRun : Option Nat := none
  for index in List.finRange tokens.size do
    let token := tokens[index]
    if previousRun != some token.run then
      parentheses := []
      matching := {}
      braces := []
    previousRun := some token.run
    if token.text == "(" then parentheses := index.val :: parentheses
    if token.text == ")" then
      if let opening :: rest := parentheses then
        matching := matching.insert index.val opening
        parentheses := rest
    if token.text == "{" then
      let mut candidate := none
      if 0 < index.val then
        if let some opening := matching[index.val-1]? then
          if 0 < opening then
            if let some name := tokens[opening-1]? then
              if name.name then candidate := some (opening-1,name)
      braces := candidate :: braces
    if token.text == "}" then
      if let opening :: rest := braces then
        braces := rest
        if let some (position,name) := opening then
          result := result.push ⟨name.text,position,name.row,token.row⟩
  return result

private def require (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw (IO.userError message)

private def lexicalChecks : IO Unit := do
  let raw := "bool root() { /* fake() { } */ return leaf(\"}) (\"); }\nbool leaf() { return 1; }"
  let tokens := lex (raw.toList.toArray.map fun c => ((c,⟨0,by decide⟩) : Char × Fin 1)) 0
  let found := blocks tokens
  require (found.map (·.name) == #["root","leaf"]) "comments or literals manufactured a block"
  let before := lex ("bool root() {".toList.toArray.map fun c => ((c,⟨0,by decide⟩) : Char × Fin 1)) 0
  let after := lex ("}".toList.toArray.map fun c => ((c,⟨0,by decide⟩) : Char × Fin 1)) 1
  require ((blocks (before++after)).isEmpty) "an observation gap manufactured a balanced block"
  let control := lex ("if (ready) { emit(); }".toList.toArray.map fun c => ((c,⟨0,by decide⟩) : Char × Fin 1)) 0
  require ((blocks control).map (·.name) == #["if"]) "the diagnostic hid its control-statement ambiguity"

/-- An isolated replay changes only payload requirements. Original costs,
cue weights, cue membership, offer order and both limits remain unchanged. -/
private def shadow (rows : Array StoredRow) (owners : Std.HashMap String (List (Nat × Nat)))
    (data : Json) (outgoing : Std.HashMap (Fin rows.size) (Array (Fin blockCount)))
    (bodyRows : Fin blockCount → List (Fin rows.size)) : IO Json := do
  let mappingStarted ← IO.monoMsNow
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (fromJson? (data.getObjValD "selectorInput"))
  let problem ← IO.ofExcept raw.decode
  let merged ← IO.ofExcept (Delivery.merge (rows.map fun row =>
    {row with origins := row.origins.filter (fun origin => owners.contains origin.binding.owner)}))
  let mut rowIndex : Std.HashMap Key (Fin rows.size) := {}
  for index in List.finRange rows.size do rowIndex := rowIndex.insert rows[index].key index
  let mut fileAtoms : Std.HashMap File (Fin problem.costs.size) := {}
  let mut rowAtoms : Std.HashMap (Fin rows.size) (Fin problem.costs.size × Fin problem.costs.size) := {}
  let mut cursor := owners.size
  let checkedAtom (index : Nat) (text : String) : IO (Fin problem.costs.size) := do
    let expected := (text.length,text.utf8ByteSize)
    require (problem.costs[index]? == some expected) "source atom cost differs from the actual selector input"
    if h : index < problem.costs.size then return ⟨index,h⟩ else throw (IO.userError "source atom out of bounds")
  for row in merged do
    unless fileAtoms.contains row.key.file do
      let frame := Packet.fileFrame row.key.file (merged.filter (·.key.file == row.key.file))
      let atom ← checkedAtom cursor (frame.leading ++ frame.trailing)
      fileAtoms := fileAtoms.insert row.key.file atom
      cursor := cursor+1
    let some file := fileAtoms[row.key.file]? | throw (IO.userError "missing source frame")
    let atom ← checkedAtom cursor (Packet.rowText row)
    let some index := rowIndex[row.key]? | throw (IO.userError "source atom has no canonical row")
    rowAtoms := rowAtoms.insert index (file,atom)
    cursor := cursor+1
  let actual : List Nat ← field data "selected"
  let recorded ← IO.ofExcept (SharedCoverage.Input.checkedIndices problem.offers.size actual)
  let mappingMs := (← IO.monoMsNow)-mappingStarted
  let baselineStarted ← IO.monoMsNow
  let some baseline := SharedCoverage.choose? problem | throw (IO.userError "actual selector replay failed")
  let baselineSelectionMs := (← IO.monoMsNow)-baselineStarted
  let recordedNodes := Std.HashSet.ofList (SharedCoverage.nodes problem recorded)
  let baselineNodes := Std.HashSet.ofList (SharedCoverage.nodes problem baseline.selected)
  require (recordedNodes.size == baselineNodes.size && recordedNodes.toList.all baselineNodes.contains)
    "selector replay differs from the actual recorded payload selection"
  IO.println "Actual selector payload replay matched"
  let dependenciesStarted ← IO.monoMsNow
  let mut dependencies : Std.HashMap (Fin problem.costs.size) (List (Fin problem.costs.size)) := {}
  for start in outgoing.keys do
    let mut seen := ({} : Std.HashSet (Fin rows.size)).insert start
    let mut queue := #[start]
    let mut offset := 0
    while offset < queue.size do
      let some current := queue[offset]? | break
      offset := offset+1
      for target in outgoing[current]?.getD #[] do
        for index in bodyRows target do
          if seen.contains index then continue
          seen := seen.insert index
          queue := queue.push index
    let some (_,atom) := rowAtoms[start]? | throw (IO.userError "reference has no source payload")
    let mut closure := []
    for index in queue do
      let some (frame,payload) := rowAtoms[index]? | throw (IO.userError "dependency has no source payload")
      closure := frame :: payload :: closure
    dependencies := dependencies.insert atom (hashDistinct closure)
  let offers := problem.offers.map fun offer => {offer with
    closure := hashDistinct (offer.closure ++ offer.closure.flatMap (fun atom => dependencies[atom]?.getD []))}
  let conditioned : SharedCoverage.Problem := {
    costs := problem.costs,weights := problem.weights,offers,fixed := problem.fixed,limit := problem.limit}
  let dependencyBuildMs := (← IO.monoMsNow)-dependenciesStarted
  let candidateStarted ← IO.monoMsNow
  let some candidate := SharedCoverage.choose? conditioned | throw (IO.userError "conditional selector replay failed")
  let candidateSelectionMs := (← IO.monoMsNow)-candidateStarted
  let candidateNodes := Std.HashSet.ofList (SharedCoverage.nodes conditioned candidate.selected)
  require (candidateNodes.toList.all fun node => (dependencies[node]?.getD []).all candidateNodes.contains)
    "selected payload leaves a declared reference requirement open"
  let chosenRows := rowAtoms.toList.filterMap fun (index,(_,atom)) =>
    if candidateNodes.contains atom then some rows[index].key else none
  let actualRows := rowAtoms.toList.filterMap fun (index,(_,atom)) =>
    if recordedNodes.contains atom then some rows[index].key else none
  return Json.mkObj [("actualPayloadReplayExact",toJson true),("sourceAtomCostsChecked",toJson merged.size),
    ("mappingMs",toJson mappingMs),("baselineSelectionMs",toJson baselineSelectionMs),
    ("dependencyBuildMs",toJson dependencyBuildMs),("candidateSelectionMs",toJson candidateSelectionMs),
    ("baselineCost",toJson (SharedCoverage.cost problem baseline.selected)),
    ("candidateCost",toJson (SharedCoverage.cost conditioned candidate.selected)),
    ("baselineBenefit",toJson (SharedCoverage.benefit problem baseline.selected)),
    ("candidateBenefit",toJson (SharedCoverage.benefit conditioned candidate.selected)),
    ("declaredDependenciesClosed",toJson true),("originalWeightsAndLimitsUnchanged",toJson true),
    ("actualSourceRows",toJson actualRows),("candidateSourceRows",toJson chosenRows),
    ("bindingOrNecessityProved",toJson false),("actualDeliveryAsserted",toJson false)]

def main (args : List String) : IO Unit := do
  let (database,selectionPath,output,replay) ← match args with
    | [database,selectionPath,output] => pure (database,selectionPath,output,false)
    | [database,selectionPath,output,"shadow"] => pure (database,selectionPath,output,true)
    | _ => throw (IO.userError "DATABASE ACTUAL-SELECTION NEW-OUTPUT [shadow]")
  require (!(← System.FilePath.pathExists output)) "preserve an earlier reference audit"
  lexicalChecks
  let source ← DB.PageMap.pin (.mk database)
  let some ready ← Cache.open? source .database | throw (IO.userError "canonical source is not prepared")
  let selection ← IO.ofExcept (Json.parse (← IO.FS.readFile selectionPath))
  let audit : Array Json ← field (selection.getObjValD "data") "rangeAudit"
  let mut owners : Std.HashMap String (List (Nat × Nat)) := {}
  for row in audit do owners := owners.insert (← field row "owner") (← field row "selectedSharedRanges")
  let rows := ready.registry.store.filter fun row => row.origins.any fun origin => owners.contains origin.binding.owner
  let selected (index : Fin rows.size) := rows[index].origins.any fun origin =>
    (owners[origin.binding.owner]?).any fun ranges => covers ranges origin.binding.first origin.binding.limit
  let order := (List.finRange rows.size).mergeSort fun a b =>
    if rows[a].key.file == rows[b].key.file then rows[a].key.line ≤ rows[b].key.line
    else (toJson rows[a].key.file).compress ≤ (toJson rows[b].key.file).compress
  let mut run : Array (Char × Fin rows.size) := #[]
  let mut previous : Option (Fin rows.size) := none
  let mut tokens := #[]
  let mut runId := 0
  for index in order do
    let row := rows[index]
    if !(previous.any fun prior => rows[prior].key.file == row.key.file && rows[prior].key.line+1 == row.key.line) then
      tokens := tokens ++ lex run runId
      run := #[]
      runId := runId+1
    run := run ++ ((row.code ++ "\n").toList.toArray.map (fun c => (c,index)))
    previous := some index
  tokens := tokens ++ lex run runId
  let definitions := blocks tokens
  let mut byName : Std.HashMap (File × String) (Array (Fin definitions.size)) := {}
  let mut definitionTokens : Std.HashSet Nat := {}
  for index in List.finRange definitions.size do
    let definition := definitions[index]
    let key := (rows[definition.first].key.file,definition.name)
    byName := byName.insert key ((byName[key]?.getD #[]).push index)
    definitionTokens := definitionTokens.insert definition.nameToken
  let bodyRows (block : Fin definitions.size) :=
    let definition := definitions[block]
    (List.finRange rows.size).filter fun index =>
      rows[index].key.file == rows[definition.first].key.file &&
      rows[definition.first].key.line ≤ rows[index].key.line && rows[index].key.line ≤ rows[definition.last].key.line
  let mut outgoing : Std.HashMap (Fin rows.size) (Array (Fin definitions.size)) := {}
  let mut calls := #[]
  for position in List.finRange tokens.size do
    let token := tokens[position]
    if !token.name || definitionTokens.contains position.val then continue
    let some next := tokens[position.val+1]? | continue
    if next.text != "(" || token.run != next.run then continue
    let candidates := byName[(rows[token.row].key.file,token.text)]?.getD #[]
    if candidates.size == 1 then
      if let some target := candidates[0]? then
        outgoing := outgoing.insert token.row ((outgoing[token.row]?.getD #[]).push target)
    calls := calls.push (Json.mkObj [("name",toJson token.text),("source",toJson rows[token.row].key),
      ("initiallySelected",toJson (selected token.row)),("shapeCandidates",toJson (candidates.map Fin.val))])
  let initial := (List.finRange rows.size).filter selected
  let mut reached := Std.HashSet.ofList initial
  let mut pending := initial.toArray
  let mut cursor := 0
  let mut activated : Std.HashSet (Fin definitions.size) := {}
  let mut causes := #[]
  while cursor < pending.size do
    let some row := pending[cursor]? | break
    cursor := cursor+1
    for target in outgoing[row]?.getD #[] do
      if activated.contains target then continue
      activated := activated.insert target
      let missing := (bodyRows target).filter fun index => !reached.contains index
      causes := causes.push (Json.mkObj [("block",toJson target.val),("from",toJson rows[row].key),
        ("initiallySelected",toJson (selected row)),("newRows",toJson missing.length)])
      for index in missing do
        reached := reached.insert index
        pending := pending.push index
  let rendered := (List.finRange definitions.size).map fun index =>
    let definition := definitions[index]
    Json.mkObj [("id",toJson index.val),("name",toJson definition.name),("first",toJson rows[definition.first].key),
      ("last",toJson rows[definition.last].key),("rows",toJson (bodyRows index).length),
      ("initiallyComplete",toJson ((bodyRows index).all selected)),("reached",toJson (activated.contains index))]
  let added := (List.finRange rows.size).filter fun index => reached.contains index && !selected index
  let chars := added.foldl (fun count index => count+rows[index].code.length+1) 0
  let replayResult ← if replay then shadow rows owners (selection.getObjValD "data") outgoing bodyRows else pure Json.null
  IO.FS.writeFile output (Json.mkObj [
    ("source",toJson source.head),("canonical",toJson ready.metadata),("readOnly",toJson true),
    ("domainRows",toJson rows.size),("initialRows",toJson initial.length),("tokens",toJson tokens.size),
    ("blocks",toJson rendered),("calls",toJson calls),("activations",toJson causes),
    ("addedRows",toJson (added.map fun index => rows[index].key)),("addedCodeChars",toJson chars),
    ("lexicalChecks",toJson (3 : Nat)),("bindingOrNecessityProved",toJson false),
    ("exactDeliveryCostComputed",toJson false),("productionAdoption",toJson false),
    ("selectorReplay",replayResult),
    ("answeringModelCalls",toJson (0 : Nat)),("warmCalls",toJson (0 : Nat))]).pretty
  IO.println s!"Audited {calls.size} call-shaped occurrences and {definitions.size} balanced shapes; closure added {added.length} rows"
