module
public import Eggshell.DB.PageMap
public import tools.research.PreparedPagePoints

@[expose] public section
namespace PreparedPagePointsBench
open Lean Eggshell.DB.PageMap

def require (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

structure Input where
  databases : Array String
  leavesPerDatabase : Nat := 64
  rounds : Nat := 16
  output : String
  deriving FromJson

structure Leaf where
  rows : List Row
  points : Std.HashMap String (Option ByteArray)
  deriving Inhabited

def gather (snapshot : Snapshot) (ref : Ref) (limit : Nat) (found : Array (List Row)) :
    IO (Array (List Row)) := do
  if found.size ≥ limit then return found
  let loaded ← snapshot.load ref
  match loaded.page with
  | .leaf rows => return found.push rows
  | .branch children =>
    let mut found := found
    for child in children do
      if found.size ≥ limit then break
      if _smaller : child.height < ref.height then
        found ← gather snapshot child limit found
      else throw (IO.userError "decoded directory height did not decrease")
    return found
termination_by ref.height

@[noinline] def linear (leaf : Leaf) (key : String) : Option ByteArray :=
  (leaf.rows.find? (fun row => row.1 == key)).bind Prod.snd

@[noinline] def indexed (leaf : Leaf) (key : String) : Option ByteArray :=
  PreparedPagePoints.read leaf.points key

def time (leaves : Array Leaf) (queries : Array (Nat × String)) (rounds : Nat)
    (useIndex : Bool) : IO Json := do
  let started ← IO.monoNanosNow
  let mut checksum := 0
  for _ in [:rounds] do
    for (position,key) in queries do
      let leaf := leaves[position]!
      let answer := if useIndex then indexed leaf key else linear leaf key
      checksum := checksum+answer.elim 1 (fun bytes => bytes.size+2)
  let elapsed := (← IO.monoNanosNow)-started
  return Json.mkObj [("indexed",toJson useIndex),("elapsedNs",toJson elapsed),
    ("lookups",toJson (queries.size*rounds)),("checksum",toJson checksum)]

def controls : IO Nat := do
  let rows : List Row := [("same",some "first".toUTF8),("x",none),
    ("same",some "last".toUTF8),("x",some "revived".toUTF8),("é/カーネル",some ByteArray.empty)]
  let leaf : Leaf := ⟨rows,PreparedPagePoints.compile rows⟩
  let keys := #["same","x","absent","é/カーネル",""]
  for key in keys do
    require (linear leaf key == indexed leaf key) "duplicate/tombstone/unicode control changed"
  require (indexed leaf "same" == some "first".toUTF8 && indexed leaf "x" == none)
    "first occurrence control failed"
  return keys.size+2

def run (path : System.FilePath) : IO Unit := do
  let input ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson? (α := Input))
  require (!input.databases.isEmpty && input.databases.size ≤ 16 &&
    input.leavesPerDatabase ≤ 64 && input.rounds == 16) "bounded native component required"
  let controlCount ← controls
  let mut rows := #[]
  let mut databases := #[]
  for database in input.databases do
    let snapshot ← pin (.mk database)
    let started ← IO.monoNanosNow
    let leaves ← match snapshot.head.root with
      | none => pure #[]
      | some root => gather snapshot root input.leavesPerDatabase #[]
    rows := rows++leaves
    databases := databases.push (Json.mkObj [("path",toJson database),
      ("head",toJson snapshot.head),("leaves",toJson leaves.size),
      ("loadNs",toJson ((← IO.monoNanosNow)-started)),
      ("physicalPages",toJson (← snapshot.reads.get)),("physicalBytes",toJson (← snapshot.readBytes.get))])
  let prepareStarted ← IO.monoNanosNow
  let leaves := rows.map fun rows => Leaf.mk rows (PreparedPagePoints.compile rows)
  -- Force all prepared tables before starting either timed arm.
  let entries := leaves.foldl (fun count leaf => count+leaf.points.size) 0
  let prepareNs := (← IO.monoNanosNow)-prepareStarted
  let mut queries := #[]
  for index in [:leaves.size] do
    for row in leaves[index]!.rows do
      queries := queries.push (index,row.1)
    for key in ["",leaves[index]!.rows.head!.1++"/missing",leaves[index]!.rows.getLast!.1++"/missing"] do
      queries := queries.push (index,key)
  for (position,key) in queries do
    require (linear leaves[position]! key == indexed leaves[position]! key)
      "prepared actual-page result differs from the current linear lookup"
  let mut trials := #[]
  for useIndex in [false,true,true,false] do
    trials := trials.push (← time leaves queries input.rounds useIndex)
  let checksums := trials.map (·.getObjValD "checksum")
  require (checksums.all (· == checksums[0]!)) "timed arms differ"
  let result := Json.mkObj [("controlChecks",toJson controlCount),("databases",toJson databases),
    ("leaves",toJson leaves.size),("retainedIndexEntries",toJson entries),
    ("prepareNs",toJson prepareNs),("queries",toJson queries.size),
    ("allActualPageQueriesEqual",toJson true),("trials",toJson trials),
    ("fullRuntimeChanged",toJson false),("actualHookTrace",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (.mk input.output) result.compress
  IO.println (Json.mkObj [("leaves",toJson leaves.size),("queries",toJson queries.size),
    ("prepareNs",toJson prepareNs),("trials",toJson trials)]).compress

end PreparedPagePointsBench

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "PreparedPagePointsBench INPUT")
  PreparedPagePointsBench.run (.mk path)
