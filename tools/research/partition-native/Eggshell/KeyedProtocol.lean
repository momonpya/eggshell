module
public import Eggshell.WindowOwners

@[expose] public section
namespace Eggshell.KeyedProtocol
open Lean DB Persistence.Store

structure Scope where
  owner : Sidecar.Owner
  head : PageMap.Head
  deriving ToJson, FromJson

def Scope.ofSnapshot (snapshot : Snapshot) : Scope := ⟨Sidecar.Owner.ofSnapshot snapshot,snapshot.head⟩

/-- A concurrent suffix is allowed; every read still uses the caller's exact
pinned original root. A response never supplies a directory or a new scope. -/
def Scope.pin (scope : Scope) : IO Snapshot := do
  let snapshot ← scope.owner.pin
  unless scope.head.identity == snapshot.head.identity && scope.head.authority == snapshot.head.authority &&
      scope.head.revision ≤ snapshot.head.revision && scope.head.bytes ≤ snapshot.head.bytes do
    throw (IO.userError "keyed request belongs to a foreign source publication")
  return {snapshot with head := scope.head}

structure Request where
  query : String
  sources : Array Scope
  keys : Nat := 4096
  rows : Nat := 8192
  receipt : Option String := none
  deriving ToJson, FromJson

structure Window where
  position : Nat
  key : String
  deriving BEq, ToJson, FromJson

structure Choice where
  source : Nat
  owner : Nat
  work : Nat
  ordinal : Nat
  windows : List Window
  deriving BEq, ToJson, FromJson

structure Coverage where
  source : Nat
  population : Nat
  routePoints : Nat
  routeCells : Nat
  totalCells : Nat
  routeKeys : Nat
  physicalRows : Nat
  partialKeys : List String
  lexicalOwners : Nat
  nominatedOwners : Nat
  approximate : Bool := true
  lexicalWindowOmissions : Nat := 0
  unseenVectorKeys : Nat := 0
  partialCell : Bool := false
  deriving ToJson, FromJson

structure Response where
  ranked : List Choice
  related : List Nat
  coverage : List Coverage
  deriving ToJson, FromJson

structure ScopedChoice (sources : Array Snapshot) where
  source : Fin sources.size
  choice : Choice
  exactSource : choice.source = source.val

def checkChoice (sources : Array Snapshot) (choice : Choice) : Except String (ScopedChoice sources) := do
  if valid : choice.source < sources.size then
    unless choice.windows.length ≤ 16 && choice.windows.all (fun window => PageMap.validIdentity window.key) &&
        (Std.HashSet.ofList (choice.windows.map (·.position))).size == choice.windows.length do
      throw "invalid keyed original window positions"
    return ⟨⟨choice.source,valid⟩,choice,rfl⟩
  else throw "keyed response names a foreign source"

theorem scoped_choice_in_original_array (choice : ScopedChoice sources) :
    choice.choice.source < sources.size := by rw [choice.exactSource]; exact choice.source.isLt

structure Checked (sources : Array Snapshot) where
  related : List (ScopedChoice sources)
  ranked : List (ScopedChoice sources)
  coverage : List Coverage

/-- Ranking and coverage are hints. Only closed-source choices can reach the
original resolver, and related indices refer to this response's own order. -/
def check (sources : Array Snapshot) (response : Response) : Except String (Checked sources) := do
  unless response.ranked.length ≤ 8192 && response.related.length ≤ 128 &&
      (Std.HashSet.ofList (response.ranked.map (fun row => (row.source,row.owner)))).size == response.ranked.length &&
      (Std.HashSet.ofList response.related).size == response.related.length &&
      response.coverage.length == sources.size &&
      response.coverage.map (·.source) == List.range sources.size do
    throw "invalid keyed response population or order"
  let ranked ← response.ranked.mapM (checkChoice sources)
  let related ← response.related.mapM fun index => do
    let some row := ranked[index]? | throw "keyed selection names a foreign ranked owner"
    return row
  return ⟨related,ranked,response.coverage⟩

/-- Validate only the owners selected for admission, not every scored hint.
No cache hint creates a Match, Union, source freshness claim or completed work. -/
def validateRelated (sources : Array Snapshot) (checked : Checked sources) : IO Unit := do
  for index in List.finRange sources.size do
    let rows := checked.related.filter (fun row => row.source.val == index.val)
    let occurrences := rows.flatMap fun row => row.choice.windows.map fun window =>
      (window.key,WindowOwners.Occurrence.mk row.choice.owner row.choice.work row.choice.ordinal window.position)
    let _ ← WindowOwners.resolve sources[index] ⟨occurrences,0,0,0,[]⟩
    -- Lexical-only choices may carry no numerical positions, but still need
    -- their original live header, ordinal and Work checked.
    for row in rows do
      let header ← locateOutcome sources[index] row.choice.owner
      unless header.header.work == row.choice.work &&
          (← getNat sources[index].get (key "member" row.choice.owner)) == row.choice.ordinal &&
          (← getNat sources[index].get (key "candidate" row.choice.owner)) == 1 do
        throw (IO.userError "keyed admission disagrees with its original source")

end Eggshell.KeyedProtocol
