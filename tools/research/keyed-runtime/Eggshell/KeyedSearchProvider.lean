module
public import Eggshell.KeyedProtocol
public import Eggshell.SearchProvider
public import Eggshell.VectorRoute
public import Eggshell.LexicalReads

@[expose] public section
namespace Eggshell.KeyedSearchProvider
open Lean DB Persistence.Store SearchProvider

structure Lexical where
  ranked : List Nat
  anchors : List Nat

/-- Preserve the original ranked positions. A directory prevents a repeated
linear list walk for every result of a large posting set. -/
def originalOwners (rows positions : List Nat) : List Nat :=
  positions.filterMap (rows[·]?)

def originalOwnersIndexed (rows positions : List Nat) : List Nat :=
  let directory := rows.toArray
  positions.filterMap (directory[·]?)

@[csimp] theorem originalOwners_compiled : originalOwners = originalOwnersIndexed := by
  funext rows positions
  simp [originalOwners,originalOwnersIndexed]

/-- Complete query postings and global population, without any owner body or
candidate catalogue. Only its bounded selected owners are later materialized. -/
def lexical (source : Snapshot) (queryText : String) (receipt : Option String) : IO Lexical := do
  let query ← LexicalReads.coarseQuery source receipt
  let mut postings : Std.HashMap String (Std.HashSet Nat) := {}
  let mut frequency : Std.HashMap String Nat := {}
  let mut owners : Std.HashSet Nat := {}
  for term in SearchRank.terms queryText do
    let (found,count) ← query.posting term
    postings := postings.insert term (Std.HashSet.ofList found)
    frequency := frequency.insert term count
    for owner in found do owners := owners.insert owner
  let ordered ← owners.toList.mapM fun owner => do pure (← query.ordinal owner,owner)
  let rows := (ordered.mergeSort (fun a b => a.1 ≤ b.1)).map Prod.snd
  let population ← getNat source.get "candidates"
  let contains := fun owner term => (postings.getD term {}).contains owner
  let ranked := SearchRank.rankRows queryText rows contains (frequency.getD · 0) false population
  let anchors := SearchRank.rankRows queryText rows contains (frequency.getD · 0) true population
  query.report
  return ⟨originalOwners rows ranked,originalOwners rows anchors⟩

def add (choices : Array KeyedProtocol.Choice) (table : Std.HashMap (Nat × Nat) Nat)
    (source : Nat) (window : String) (row : WindowOwners.Occurrence) :
    IO (Array KeyedProtocol.Choice × Std.HashMap (Nat × Nat) Nat) := do
  let original : KeyedProtocol.Window := ⟨row.position,window⟩
  if let some index := table[(source,row.owner)]? then
    let some known := choices[index]? | throw (IO.userError "invalid keyed owner directory")
    unless known.work == row.work && known.ordinal == row.ordinal do
      throw (IO.userError "keyed postings disagree about original owner")
    if let some previous := known.windows.find? (·.position == row.position) then
      unless previous == original do throw (IO.userError "keyed postings disagree about original window")
      return (choices,table)
    return (choices.set! index {known with windows := known.windows ++ [original]},table)
  else
    return (choices.push ⟨source,row.owner,row.work,row.ordinal,[original]⟩,
      table.insert (source,row.owner) choices.size)

def routed (source : Snapshot) (options : SearchProvider.Options) (queries : Array Json)
    (sourceIndex sourceCount leaves : Nat) : IO VectorRoute.Nomination := do
  let mut available : Option (VectorMatrix.Ready × VectorRoute.Ready) := none
  for storage in [.database,.user] do
    let root := (← Sidecar.locate source storage).semantic
    if let some matrix ← try VectorMatrix.open? root options.model encoderContract catch _ => pure none then
      if let some route ← try VectorRoute.open? root options.model encoderContract matrix catch _ => pure none then
        available := some (matrix,route)
        break
  let some (_,route) := available | throw (IO.userError "source numerical routing is pending warm")
  unless !queries.isEmpty && sourceCount > 0 do throw (IO.userError "empty keyed query scope")
  let mut keys := []
  let mut visitedLeaves := 0
  let mut nodes := 0
  let partitions := sourceCount*queries.size
  for (query,index) in queries.toList.zipIdx do
    let flat := sourceIndex*queries.size+index
    let quota := leaves/partitions + (if flat < leaves%partitions then 1 else 0)
    if quota == 0 then continue
    let hex ← IO.ofExcept query.getStr?
    let point ← IO.ofExcept (VectorRoute.sketch (windowKey hex) (← IO.ofExcept (VectorMatrix.decodeHex hex)))
    let selected ← VectorRoute.nominate route point quota
    keys := selected.val.keys.reverse ++ keys
    visitedLeaves := visitedLeaves+selected.val.visitedLeaves
    nodes := nodes+selected.val.visitedNodes
  return ⟨hashDistinct keys.reverse,visitedLeaves,nodes,route.manifest.points,route.manifest.leaves⟩

/-- Translate score-local positions back to the original source coordinates.
Compacting the score domain must never renumber an original window. -/
def project (choices : Array KeyedProtocol.Choice) (response : SemanticMatcher.IndexedResponse) :
    Except String (List KeyedProtocol.Choice × List Nat) := do
  let mut ranked := []
  let mut positions : Std.HashMap Nat Nat := {}
  for (candidate,rank) in response.ranked.zipIdx do
    let some choice := choices[candidate]? | throw "keyed scorer names a foreign owner"
    let evidence := (response.evidence.find? (·.document == candidate)).map (·.indices) |>.getD []
    let windows ← evidence.mapM fun position => do
      let some window := choice.windows[position]? | throw "keyed scorer names a foreign window"
      return window
    ranked := {choice with windows} :: ranked
    positions := positions.insert candidate rank
  let related ← response.related.mapM fun candidate => do
    let some position := positions[candidate]? | throw "keyed scorer selected an unranked owner"
    return position
  return (ranked.reverse,related)

/-- The wire carries source scopes, not a document catalogue. Vector keys and
postings nominate a bounded score domain; the old full-vector scorer and
selection policy consume only that domain. Coverage remains explicitly advisory. -/
def handle (options : SearchProvider.Options) (child : Option Encoder) (request : KeyedProtocol.Request) : IO Json := do
  unless request.leaves ≤ 128 && request.rows ≤ 8192 && options.topK ≤ 128 && options.anchorK ≤ 128 do
    throw (IO.userError "excess keyed request allowance")
  let sources ← request.sources.mapM KeyedProtocol.Scope.pin
  let queries ← match child with
    | none => pure #[]
    | some child => do
      let privateOptions ← queryOptions options
      store privateOptions child [request.query] true
      IO.ofExcept (← vectors privateOptions request.query).getArr?
  let mut choices : Array KeyedProtocol.Choice := #[]
  let mut table : Std.HashMap (Nat × Nat) Nat := {}
  let mut rankings : List (Nat × Lexical) := []
  let mut coverage := []
  for index in List.finRange sources.size do
    let source := sources[index]
    let population ← getNat source.get "candidates"
    if population == 0 then
      coverage := ⟨index.val,0,0,0,0,0,0,[],0,0,true,0⟩ :: coverage
      continue
    let some reverse ← WindowOwners.openShared? source |
      throw (IO.userError "original window owners are pending warm")
    let ranked ← lexical source request.query request.receipt
    rankings := (index.val,ranked) :: rankings
    let nomination ← if child.isSome then routed source options queries index.val sources.size request.leaves
      else pure ⟨[],0,0,0,0⟩
    let allowance := request.rows/sources.size + (if index.val < request.rows%sources.size then 1 else 0)
    let selected ← WindowOwners.lookup reverse nomination.keys (allowance*3/4)
    let mut remaining := allowance-selected.val.physicalRows
    for (key,row) in selected.val.occurrences do
      let updated ← add choices table index.val key row
      choices := updated.1; table := updated.2
    let wanted := hashDistinct (ranked.ranked.take options.topK ++ ranked.anchors.take options.anchorK)
    let documents ← SourceDelta.documents source wanted
    let mut omitted := 0
    for document in documents do
      let ordinal ← getNat source.get (key "member" document.owner)
      for (key,position) in document.windows.zipIdx do
        if remaining == 0 then
          omitted := omitted+1
          continue
        remaining := remaining-1
        let updated ← add choices table index.val key ⟨document.owner,document.work,ordinal,position⟩
        choices := updated.1; table := updated.2
    coverage := ⟨index.val,population,nomination.totalPoints,nomination.visitedLeaves,
      nomination.totalLeaves,nomination.keys.length,selected.val.physicalRows,
      selected.val.partialKeys,wanted.length,(choices.filter (·.source == index.val)).size,true,omitted⟩ :: coverage
  let candidates ← choices.mapM fun choice => do
    let some scope := request.sources[choice.source]? | throw (IO.userError "foreign keyed score source")
    return Json.mkObj [("id",toJson choice.owner),("cache",toJson scope.owner),
      ("windows",toJson (choice.windows.map (·.key)))]
  let lookup := fun (source : Nat) (owners : List Nat) => owners.filterMap (fun owner => table[(source,owner)]?)
  let lexical := SearchRank.fused (rankings.reverse.map fun (source,ranking) => lookup source ranking.ranked)
  let anchors := SearchRank.fused (rankings.reverse.map fun (source,ranking) => lookup source ranking.anchors)
  let input := Json.mkObj [("documents",toJson candidates),("lexical",toJson lexical),
    ("anchors",toJson anchors),("receipt",toJson request.receipt),("purpose",toJson "keyed-discovery")]
  let result ← handleIndexed options child request.query input
  let response ← IO.ofExcept (fromJson? result : Except String SemanticMatcher.IndexedResponse)
  let (ranked,related) ← IO.ofExcept (project choices response)
  let output : KeyedProtocol.Response := ⟨ranked,related,coverage.reverse⟩
  let _ ← IO.ofExcept (KeyedProtocol.check sources output)
  Receipt.observe request.receipt "keyed-coverage" (toJson output.coverage)
  return toJson output

def run (arguments : List String) : IO UInt32 := IO.FS.withTempDir fun scratch => do
  let layout := MiniLM.layout (← Paths.installRoot)
  let options ← IO.ofExcept (SearchProvider.parse {cache := scratch,models := layout.models} arguments)
  let child ← if options.mode == "lexical" then pure none else some <$> encoder options
  try
    let stdin ← IO.getStdin
    let stdout ← IO.getStdout
    repeat
      let line ← stdin.getLine
      if line.isEmpty then break
      try
        let request ← IO.ofExcept (Json.parse line >>= fromJson? (α := KeyedProtocol.Request))
        stdout.putStrLn (← handle options child request).compress
        stdout.flush
      catch error =>
        stdout.putStrLn (Json.mkObj [("error",toJson error.toString)]).compress
        stdout.flush
    return 0
  finally
    if let some child := child then stopEncoder child

end Eggshell.KeyedSearchProvider
