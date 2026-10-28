module
public import Eggshell.CanonicalSourceDelivery
public import tools.SharedCoverage
@[expose] public section

/- Isolated recommendation experiment. These lexical shapes are not language
bindings or semantic necessities. No Work, Match, Union or IO is produced. -/
namespace Eggshell.Research.ReferenceRequirements
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource

structure Token (size : Nat) where
  text : String
  name : Bool
  row : Fin size
  run : Nat

def lex (raw : Array (Char × Fin size)) (run : Nat) : Array (Token size) := Id.run do
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

structure Block (size : Nat) where
  name : String
  nameToken : Nat
  first : Fin size
  last : Fin size

def blocks (tokens : Array (Token size)) : Array (Block size) := Id.run do
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

structure Graph (rows : Array StoredRow) where
  direct : Std.HashMap (Fin rows.size) (List (Fin rows.size))
  blockCount : Nat
  callCount : Nat

/-- Caller supplies one permission-filtered, canonical original basis. Missing
rows split lexical runs; unknown and ambiguous shapes add no requirement. -/
def prepareGraph (rows : Array StoredRow) : Graph rows := Id.run do
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
  let mut direct : Std.HashMap (Fin rows.size) (List (Fin rows.size)) := {}
  let mut callCount := 0
  for position in List.finRange tokens.size do
    let token := tokens[position]
    if !token.name || definitionTokens.contains position.val then continue
    let some next := tokens[position.val+1]? | continue
    if next.text != "(" || token.run != next.run then continue
    callCount := callCount+1
    let candidates := byName[(rows[token.row].key.file,token.text)]?.getD #[]
    if candidates.size == 1 then
      if let some target := candidates[0]? then
        direct := direct.insert token.row (hashDistinct ((direct[token.row]?.getD []) ++ bodyRows target))
  return ⟨direct,definitions.size,callCount⟩

def Graph.closure (graph : Graph rows) (start : Fin rows.size) : List (Fin rows.size) := Id.run do
  let mut seen := ({} : Std.HashSet (Fin rows.size)).insert start
  let mut queue := #[start]
  let mut offset := 0
  while offset < queue.size do
    let some current := queue[offset]? | break
    offset := offset+1
    for index in graph.direct[current]?.getD [] do
      if seen.contains index then continue
      seen := seen.insert index
      queue := queue.push index
  return queue.toList

structure Prepared (p : SharedCoverage.Problem) where
  sourceRows : Array (StoredRow × Fin p.costs.size)
  dependencies : Std.HashMap (Fin p.costs.size) (List (Fin p.costs.size))
  blocks : Nat
  calls : Nat

/-- Reconstruct the existing original payload basis and reject any mismatch.
The parser does not invent payloads or change the existing wire costs. -/
def prepare (familyCount : Nat) (rows : Array StoredRow) (p : SharedCoverage.Problem) : Option (Prepared p) := do
  let mut fileAtoms : Std.HashMap File (Fin p.costs.size) := {}
  let mut rowAtoms : Std.HashMap (Fin rows.size) (Fin p.costs.size × Fin p.costs.size) := {}
  let mut sourceRows := #[]
  let mut cursor := familyCount
  let checkedAtom (index : Nat) (text : String) : Option (Fin p.costs.size) := do
    unless p.costs[index]? == some (text.length,text.utf8ByteSize) do none
    if h : index < p.costs.size then some ⟨index,h⟩ else none
  for index in List.finRange rows.size do
    let row := rows[index]
    unless fileAtoms.contains row.key.file do
      let frame := Packet.fileFrame row.key.file (rows.filter (·.key.file == row.key.file))
      let atom ← checkedAtom cursor (frame.leading ++ frame.trailing)
      fileAtoms := fileAtoms.insert row.key.file atom
      cursor := cursor+1
    let file ← fileAtoms[row.key.file]?
    let atom ← checkedAtom cursor (Packet.rowText row)
    rowAtoms := rowAtoms.insert index (file,atom)
    sourceRows := sourceRows.push (row,atom)
    cursor := cursor+1
  let graph := prepareGraph rows
  let mut dependencies : Std.HashMap (Fin p.costs.size) (List (Fin p.costs.size)) := {}
  for start in graph.direct.keys do
    let (_,atom) ← rowAtoms[start]?
    let mut required := []
    for index in graph.closure start do
      let (frame,payload) ← rowAtoms[index]?
      required := frame :: payload :: required
    dependencies := dependencies.insert atom (hashDistinct required)
  return ⟨sourceRows,dependencies,graph.blockCount,graph.callCount⟩

def Prepared.offers (prepared : Prepared p) (offers : Array (SharedCoverage.Offer p.costs.size cues)) :=
  offers.map fun offer => {offer with closure := hashDistinct (offer.closure ++
    offer.closure.flatMap (fun atom => prepared.dependencies[atom]?.getD []))}

theorem Prepared.offers_size (prepared : Prepared p) (offers : Array (SharedCoverage.Offer p.costs.size cues)) :
    (prepared.offers offers).size = offers.size := by simp [Prepared.offers]

theorem Prepared.keeps_cues (prepared : Prepared p) (offers : Array (SharedCoverage.Offer p.costs.size cues))
    (index : Fin offers.size) : ((prepared.offers offers)[index.val]'(by simp [Prepared.offers])).covers =
      offers[index].covers := by simp [Prepared.offers]

theorem Prepared.keeps_payload (prepared : Prepared p) (offers : Array (SharedCoverage.Offer p.costs.size cues))
    (index : Fin offers.size) (atom : Fin p.costs.size) (present : atom ∈ offers[index].closure) :
    atom ∈ ((prepared.offers offers)[index.val]'(by simp [Prepared.offers])).closure := by
  simp only [Prepared.offers,Array.getElem_map]
  rw [HashDistinct.reference]
  exact List.mem_eraseDups.mpr (List.mem_append_left _ present)

def Prepared.selectedRows (prepared : Prepared p) (nodes : List Nat) : Array StoredRow :=
  let selected := Std.HashSet.ofList nodes
  prepared.sourceRows.filterMap fun (row,atom) => if selected.contains atom.val then some row else none

theorem Prepared.selected_original (prepared : Prepared p) (nodes : List Nat) (row : StoredRow)
    (present : row ∈ prepared.selectedRows nodes) : ∃ atom, (row,atom) ∈ prepared.sourceRows := by
  simp only [Prepared.selectedRows,Array.mem_filterMap] at present
  obtain ⟨⟨original,atom⟩,member,accepted⟩ := present
  split at accepted
  · cases Option.some.inj accepted
    exact ⟨atom,member⟩
  · contradiction

end Eggshell.Research.ReferenceRequirements
