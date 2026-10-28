import Eggshell.CanonicalSourceCache
import Eggshell.CanonicalSourceRecords
import Eggshell.SearchRank
import Lean.Data.Json.Parser

open Lean Eggshell Eggshell.Synapses
open Eggshell.Synapses.CanonicalSource

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun body => IO.ofExcept (Json.parse body)

private def field [FromJson α] (value : Json) (name : String) : IO α :=
  IO.ofExcept (value.getObjValAs? α name)

private def covers (ranges : List (Nat × Nat)) (first last : Nat) : Bool :=
  last ≤ ((ranges.mergeSort fun a b => a.1 ≤ b.1).foldl
    (fun frontier (a,b) => if a ≤ frontier then max frontier b else frontier) first)

private structure Owner where
  name : String
  work : String
  rank : Nat
  prefixChars : Nat
  selected : List (Nat × Nat)
  focus : List Nat

private def strength (owners : Std.HashMap String Owner) (scale : Nat) (row : StoredRow) : Nat :=
  row.origins.foldl (fun value origin =>
    match owners[origin.binding.owner]? with
    | none => value
    | some owner => owner.focus.zipIdx.foldl (fun value (slot,rank) =>
        let first := slot*384-owner.prefixChars
        let last := slot*384+512-owner.prefixChars
        if first < origin.binding.limit && origin.binding.first < last then
          max value (scale/(61+owner.rank)+scale/(61+rank)) else value) value) 0

private def selected (owners : Std.HashMap String Owner) (row : StoredRow) : Bool :=
  row.origins.any fun origin => (owners[origin.binding.owner]?).any fun owner =>
    covers owner.selected origin.binding.first origin.binding.limit

private structure Candidate (rowCount : Nat) where
  file : File
  indices : List (Fin rowCount)
  tokens : List String
  selectedRows : Nat
  key : String

private structure OwnerRecords where
  rows : Array StoredRow
  records : List (Records.Record rows)

private structure Scored (rowCount : Nat) where
  candidate : Candidate rowCount
  numerator : Nat
  denominator : Nat
  bridge : String
  degree : Nat
  novel : Nat

private def greater (a b : Scored rowCount) : Bool :=
  let left := a.numerator*b.denominator
  let right := b.numerator*a.denominator
  if left == right then a.candidate.key < b.candidate.key else right < left

def main (args : List String) : IO Unit := do
  let [database,selectionPath,domainPath,output] := args |
    throw (IO.userError "DATABASE ACTUAL-SELECTION ACTUAL-DOMAIN NEW-OUTPUT")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve earlier signal audit")
  let source ← DB.PageMap.pin (.mk database)
  let some ready ← Cache.open? source .database | throw (IO.userError "canonical source is not prepared")
  let selection := (← read (.mk selectionPath)).getObjValD "data"
  let domain := (← read (.mk domainPath)).getObjValD "data"
  let scale : Nat ← field selection "scale"
  let audit : Array Json ← field selection "rangeAudit"
  let focus : Array (String × List Nat) ← field domain "focusPositions"
  let bindings : Array Json ← field selection "bindingAudit"
  let mut owners : Std.HashMap String Owner := {}
  for row in audit do
    let name : String ← field row "owner"
    owners := owners.insert name {
      name,work := ← field row "work",rank := ← field row "id"
      prefixChars := (← field (α := Nat) row "workChars")+1
      selected := ← field row "selectedSharedRanges"
      focus := (focus.find? (·.1 == name)).map Prod.snd |>.getD []}
  let rows := ready.registry.store.filter fun row => row.origins.any fun origin => owners.contains origin.binding.owner
  let mut rowIndex : Std.HashMap Key (Fin rows.size) := {}
  for index in List.finRange rows.size do rowIndex := rowIndex.insert rows[index].key index
  let delivered := rows.map (selected owners)
  let terms := rows.map fun row => SearchRank.terms row.code
  let mut context : Std.HashMap (File × String) (Std.HashSet String) := {}
  let mut activation : Std.HashMap (File × String) Nat := {}
  for index in List.finRange rows.size do
    if !delivered[index]! then continue
    let weight := strength owners scale rows[index]
    let file := rows[index].key.file
    for term in terms[index]! do
      let key := (file,term)
      activation := activation.insert key (max weight (activation[key]?.getD 0))
      context := context.insert key ((terms[index]!).foldl (·.insert ·) (context[key]?.getD {}))
  let mut byOwner : Std.HashMap String OwnerRecords := {}
  for name in owners.keys do
    let owned := rows.filter fun row => row.origins.any (·.binding.owner == name)
    byOwner := byOwner.insert name ⟨owned,Records.prepare owned⟩
  let mut candidates : Array (Candidate rows.size) := #[]
  let mut seen : Std.HashSet (List (Fin rows.size)) := {}
  for entry in bindings do
    let target : Range ← field entry "source"
    unless target.valid do throw (IO.userError "invalid recorded source witness")
    let names : Array String ← field entry "owners"
    for name in names do
      let some owner := owners[name]? | continue
      let some prepared := byOwner[name]? | continue
      let owned := prepared.rows
      let requested := (List.finRange owned.size).filter fun index =>
        let row := owned[index]
        match target.subject with
        | .file file => row.key.file == file && target.first ≤ row.key.line && row.key.line ≤ target.last
        | .original original => owner.work == original.work && row.origins.any fun origin =>
            origin.binding.owner == name && origin.binding.database == source.head.identity &&
            origin.binding.work == original.work && origin.binding.first < target.last &&
            target.first < origin.binding.limit && origin.binding.limit ≤ original.chars
      if requested.isEmpty then continue
      let closed := Records.closeIndices prepared.records requested
      let files := hashDistinct (closed.map fun index => owned[index].key.file)
      for file in files do
        let indices := (closed.filterMap fun index =>
          if owned[index].key.file == file then rowIndex[owned[index].key]? else none).mergeSort (· ≤ ·)
        if indices.isEmpty || seen.contains indices then continue
        seen := seen.insert indices
        let selectedRows := indices.countP fun index => delivered[index]!
        let tokens := hashDistinct (indices.flatMap fun index => terms[index]!)
        let key := (toJson (indices.map fun index => rows[index].key)).compress
        candidates := candidates.push {file,indices,tokens,selectedRows,key}
  let mut frequency : Std.HashMap (File × String) Nat := {}
  for candidate in candidates do
    for term in candidate.tokens do
      let key := (candidate.file,term)
      frequency := frequency.insert key ((frequency[key]?.getD 0)+1)
  let mut scored : Array (Scored rows.size) := #[]
  for candidate in candidates do
    if candidate.selectedRows == candidate.indices.length then continue
    let mut best : Scored rows.size := {candidate,numerator := 0,denominator := 1,bridge := "",degree := 0,novel := 0}
    for term in candidate.tokens do
      let key := (candidate.file,term)
      let value := activation[key]?.getD 0
      if value == 0 then continue
      let known := context[key]?.getD {}
      let novel := candidate.tokens.countP fun token => !known.contains token
      let degree := frequency[key]?.getD 0
      let denominator := degree*candidate.tokens.length
      if denominator == 0 then continue
      let next : Scored rows.size := {candidate,numerator := value*novel,denominator,bridge := term,degree,novel}
      if greater next best then best := next
    scored := scored.push best
  let ranked := scored.qsort greater
  let result := ranked.mapIdx fun rank score => Json.mkObj [
    ("rank",toJson rank),("file",toJson score.candidate.file),
    ("lines",toJson (score.candidate.indices.map fun index => rows[index].key.line)),
    ("rows",toJson score.candidate.indices.length),("selectedRows",toJson score.candidate.selectedRows),
    ("numerator",toJson score.numerator),("denominator",toJson score.denominator),
    ("bridge",toJson score.bridge),("degree",toJson score.degree),
    ("novelTokens",toJson score.novel),("tokens",toJson score.candidate.tokens.length)]
  IO.FS.writeFile output (Json.mkObj [("readOnly",toJson true),("source",toJson source.head),
    ("canonical",toJson ready.metadata),("domainRows",toJson rows.size),
    ("selectedRows",toJson (delivered.toList.countP id)),("owners",toJson owners.size),
    ("witnesses",toJson bindings.size),("distinctClosedCandidates",toJson candidates.size),
    ("ranked",toJson result),("answeringModelCalls",toJson (0 : Nat)),
    ("warmCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
  IO.println s!"Ranked {result.size} unselected closed witnesses from {bindings.size} recorded sources"
