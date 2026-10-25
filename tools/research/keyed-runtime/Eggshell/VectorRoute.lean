module
public import Eggshell.VectorMatrix
public import Init.Data.List.Sort.Lemmas

@[expose] public section
namespace Eggshell.VectorRoute
open Lean DB

def leafLimit : Nat := 32
def axisCount : Nat := 12

/-- Exact original coordinate bits used only to choose a numerical read region.
Neither a sketch nor a region establishes Work equality or source authority. -/
structure Point where
  key : String
  axes : List Nat
  deriving Inhabited

def coordinate (point : Point) (depth : Nat) : Nat := point.axes[depth % axisCount]?.getD 0

def before (depth : Nat) (left right : Point) : Bool :=
  coordinate left depth < coordinate right depth ||
    (coordinate left depth == coordinate right depth && left.key ≤ right.key)

inductive Tree where
  | leaf (points : List Point) (bounded : points.length ≤ leafLimit)
  | branch (depth : Nat) (pivot : Point) (left right : Tree)

def Tree.points : Tree → List Point
  | .leaf values _ => values
  | .branch _ _ left right => left.points ++ right.points

structure Prepared (original : List Point) where
  tree : Tree
  exact : tree.points.Perm original

/-- Rank-balanced splits retain every original key, including tied coordinates.
A skewed vector population cannot make an oversized leaf. -/
def prepare (depth : Nat) (original : List Point) : Prepared original :=
  if small : original.length ≤ leafLimit then
    ⟨.leaf original small, List.Perm.refl _⟩
  else
    let ordered := original.mergeSort (before depth)
    let middle := original.length / 2
    let left := ordered.take middle
    let right := ordered.drop middle
    let a := prepare (depth+1) left
    let b := prepare (depth+1) right
    ⟨.branch depth (right.headD default) a.tree b.tree, by
      change (a.tree.points ++ b.tree.points).Perm original
      have both := a.exact.append b.exact
      rw [List.take_append_drop] at both
      exact both.trans (List.mergeSort_perm original (before depth))⟩
termination_by original.length
decreasing_by
  all_goals simp only [List.length_take,List.length_drop,List.length_mergeSort]
  all_goals have big : 32 < original.length := by simpa [leafLimit] using Nat.lt_of_not_ge small
  all_goals have half : original.length / 2 < original.length := Nat.div_lt_self (by omega) (by omega)
  all_goals omega

theorem prepared_preserves_original (original : List Point) :
    (prepare 0 original).tree.points.Perm original := (prepare 0 original).exact

def Tree.leaves : Tree → Nat
  | .leaf _ _ => 1
  | .branch _ _ left right => left.leaves+right.leaves

/-- Only keys are persisted in a leaf. Full coordinate rows are preparation
state, never restored as a complete query catalogue. -/
inductive Node where
  | leaf (keys : List String)
  | branch (depth coordinate : Nat) (key : String) (left right : Nat)
  deriving BEq

def nodeCodec : Wire.Codec Node :=
  (Wire.sum (Wire.list Wire.text) (Wire.natural.product (Wire.natural.product
    (Wire.text.product (Wire.natural.product Wire.natural))))).iso
    (fun | .leaf keys => .inl keys
         | .branch depth coordinate key left right => .inr (depth,coordinate,key,left,right))
    (fun | .inl keys => .leaf keys
         | .inr (depth,coordinate,key,left,right) => .branch depth coordinate key left right)
    (by intro node; cases node <;> rfl)

theorem node_roundtrip (node : Node) (tail : List UInt8) :
    nodeCodec.decode (nodeCodec.encode node ++ tail) = .ok (node,tail) :=
  nodeCodec.roundtrip node tail

def implementation := Sha256.hex (include_str "VectorRoute.lean").toUTF8

def contract (model encoder : String) := Sha256.hex
  (toJson [model,encoder,implementation,VectorMatrix.contract model encoder]).compress.toUTF8

def authority (model encoder : String) := "eggshell.vector-route:" ++ contract model encoder

def folder (root : System.FilePath) (model encoder : String) := root / "routing" / contract model encoder

structure Manifest where
  matrix : PageMap.Head
  root : Nat
  nodes : Nat
  points : Nat
  leaves : Nat
  deriving ToJson, FromJson

structure Ready where
  snapshot : PageMap.Snapshot
  manifest : Manifest

/-- Open one authenticated header. A changed matrix makes this view unavailable,
not an empty search. Delta compensation is required before relaxing this test. -/
def open? (root : System.FilePath) (model encoder : String) (matrix : VectorMatrix.Ready) :
    IO (Option Ready) := do
  let some snapshot ← PageMap.open? (folder root model encoder) | return none
  unless snapshot.head.authority == authority model encoder do throw (IO.userError "foreign vector route")
  let some bytes ← snapshot.get "ready" | return none
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid route header")
  let manifest : Manifest ← IO.ofExcept (Json.parse text >>= fromJson?)
  unless manifest.matrix == matrix.snapshot.head do return none
  unless 0 < manifest.nodes && manifest.root+1 == manifest.nodes &&
      0 < manifest.leaves && snapshot.head.root.any (·.rows == manifest.nodes+1) do
    throw (IO.userError "route header disagrees with publication")
  return some ⟨snapshot,manifest⟩

def orderedBits (bits : UInt64) : Nat :=
  if bits >>> 63 == 0 then bits.toNat+2^63 else (~~~bits).toNat

/-- No rounding or vector quantization. The score still uses the original
complete vector; this small ordered-bit sketch chooses only its read region. -/
def sketch (key : String) (bytes : ByteArray) : Except String Point := do
  unless Receipt.validId key && 0 < bytes.size && bytes.size % 8 == 0 do
    throw "invalid route input"
  let dimension := bytes.size/8
  let mut values := []
  for axis in [:axisCount] do
    let index := (17+31*axis)%dimension
    let mut bits : UInt64 := 0
    for byte in [:8] do bits := bits ||| (bytes[index*8+byte]!.toUInt64 <<< (8*byte).toUInt64)
    unless bits >>> 52 &&& 2047 != 2047 do throw "nonfinite route coordinate"
    values := orderedBits bits :: values
  return ⟨key,values.reverse⟩

/-- Use the same authenticated original projection chunks and committed-prefix
checks. Source text and observation/Work authority do not enter this index. -/
def readPoint (matrix : VectorMatrix.Ready) (key : String) : IO Point := do
  let some encoded ← matrix.snapshot.get ("row:"++key) | throw (IO.userError "missing route vector")
  let row ← VectorMatrix.decodeRow encoded
  unless (← FileSystem.readVersion matrix.snapshot.handle).bytes ≥ matrix.snapshot.head.bytes do
    throw (IO.userError "truncated route matrix")
  let mut bytes := ByteArray.empty
  for chunk in row.chunks do
    unless chunk.bytes == min 4096 (row.bytes-bytes.size) do throw (IO.userError "invalid route chunk")
    bytes := bytes ++ (← matrix.snapshot.readBlob chunk)
  unless bytes.size == row.bytes &&
      (← FileSystem.readVersion matrix.snapshot.handle).bytes ≥ matrix.snapshot.head.bytes do
    throw (IO.userError "route matrix prefix changed")
  IO.ofExcept (sketch key bytes)

def writeTree (writer : PageMap.Writer) (next : IO.Ref Nat) : Tree → IO Nat
  | .leaf values _ => do
      let id ← next.get
      writer.put ("node:"++toString id) (some (nodeCodec.encode (.leaf (values.map (·.key)))).toByteArray)
      next.set (id+1)
      return id
  | .branch depth pivot left right => do
      let a ← writeTree writer next left
      let b ← writeTree writer next right
      let id ← next.get
      writer.put ("node:"++toString id)
        (some (nodeCodec.encode (.branch depth (coordinate pivot depth) pivot.key a b)).toByteArray)
      next.set (id+1)
      return id

/-- All supplied original keys are retained. This builds one immutable routing
publication; it does not rewrite any matrix payload or change its identity. -/
def create (root : System.FilePath) (model encoder : String) (matrix : VectorMatrix.Ready)
    (keys : List String) : IO Ready := do
  let path := folder root model encoder
  unless !(← path.pathExists) do throw (IO.userError "keep earlier routing publication")
  unless keys.length == matrix.metadata.rows do
    throw (IO.userError "routing input does not cover its complete matrix publication")
  let mut unique : Std.HashSet String := {}
  let mut points := []
  for key in keys do
    unless !unique.contains key do throw (IO.userError "duplicate route key")
    unique := unique.insert key
    points := (← readPoint matrix key) :: points
  let built := prepare 0 points.reverse
  let snapshot ← PageMap.create path (authority model encoder)
  let _ ← PageMap.withWriter snapshot fun writer => do
    let next ← IO.mkRef 0
    let root ← writeTree writer next built.tree
    unless (← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head do
      throw (IO.userError "matrix changed during routing preparation")
    let manifest : Manifest := ⟨matrix.snapshot.head,root,← next.get,keys.length,built.tree.leaves⟩
    writer.put "ready" (some (toJson manifest).compress.toUTF8)
  let some ready ← open? root model encoder matrix | throw (IO.userError "route not ready after publication")
  return ready

structure Refresh where
  mode : String
  points : Nat
  writtenBytes : Nat
  elapsedMs : Nat
  deriving ToJson

/-- Explicit maintenance under the DB index claim. Publish the new complete
tree and its exact matrix basis atomically; pinned old readers retain their
old pages. A changed matrix is unavailable until this replacement finishes. -/
def refresh (root : System.FilePath) (model encoder : String) (matrix : VectorMatrix.Ready) : IO Refresh := do
  let started ← IO.monoMsNow
  if let some ready ← open? root model encoder matrix then
    return ⟨"warm",ready.manifest.points,0,(← IO.monoMsNow)-started⟩
  let keys ← matrix.snapshot.foldRange ⟨"row:","row;"⟩ (fun keys row =>
    pure (if row.2.isSome then String.ofList (row.1.toList.drop 4) :: keys else keys)) []
  unless keys.length == matrix.metadata.rows && (Std.HashSet.ofList keys).size == keys.length do
    throw (IO.userError "route replacement does not cover its matrix")
  let points ← keys.reverse.mapM (readPoint matrix)
  let built := prepare 0 points
  let path := folder root model encoder
  let snapshot ← match ← PageMap.open? path with
    | some snapshot =>
      unless snapshot.head.authority == authority model encoder do throw (IO.userError "foreign routing writer")
      pure snapshot
    | none => PageMap.create path (authority model encoder)
  let (_,_,written) ← PageMap.withWriter snapshot fun writer => do
    -- Replace the derived tree, not the source DB. Old node keys are not
    -- inherited as live rows, including when a later tree is smaller.
    writer.root.set none
    let next ← IO.mkRef 0
    let treeRoot ← writeTree writer next built.tree
    unless (← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head do
      throw (IO.userError "matrix changed during route replacement")
    let manifest : Manifest := ⟨matrix.snapshot.head,treeRoot,← next.get,keys.length,built.tree.leaves⟩
    writer.put "ready" (some (toJson manifest).compress.toUTF8)
  let some ready ← open? root model encoder matrix | throw (IO.userError "route replacement failed to publish")
  return ⟨"replaced",ready.manifest.points,written,(← IO.monoMsNow)-started⟩

structure Nomination where
  keys : List String
  visitedLeaves : Nat
  visitedNodes : Nat
  totalPoints : Nat
  totalLeaves : Nat
  deriving ToJson

def readNode (ready : Ready) (id : Nat) : IO Node := do
  unless id < ready.manifest.nodes do throw (IO.userError "foreign route node")
  let some bytes ← ready.snapshot.get ("node:"++toString id) | throw (IO.userError "missing route node")
  let (node,tail) ← IO.ofExcept (nodeCodec.decode bytes.toList)
  unless tail.isEmpty && (nodeCodec.encode node).toByteArray == bytes do
    throw (IO.userError "noncanonical route node")
  match node with
  | .leaf keys =>
      unless keys.length ≤ leafLimit && keys.all Receipt.validId do throw (IO.userError "invalid route leaf")
  | .branch _ value key left right =>
      unless value < 2^64 && Receipt.validId key && left < id && right < id && left != right do
        throw (IO.userError "invalid route branch")
  return node

/-- Routing is deliberately approximate. The quota bounds vector nominations;
no claim of complete semantic ranking or absent relevant history is made. -/
def nominate (ready : Ready) (query : Point) (leafBudget : Nat) :
    IO { result : Nomination // result.visitedLeaves ≤ leafBudget ∧
      result.keys.length ≤ leafBudget*leafLimit ∧ result.visitedNodes ≤ (leafBudget+1)*128 } := do
  unless leafBudget ≤ 128 do throw (IO.userError "route leaf allowance exceeds request bound")
  let mut frontier := [(ready.manifest.root,0)]
  let mut nodes := 0
  let mut leaves := 0
  let mut keys := []
  while !frontier.isEmpty && leaves < leafBudget do
    let some (id,expectedDepth) := frontier.head? | break
    frontier := frontier.drop 1
    nodes := nodes+1
    unless nodes ≤ (leafBudget+1)*128 do throw (IO.userError "route traversal exceeds request bound")
    match ← readNode ready id with
    | .leaf found =>
        keys := found.reverse ++ keys
        leaves := leaves+1
    | .branch depth value key left right =>
        unless depth == expectedDepth && depth < 64 do throw (IO.userError "route depth disagrees")
        let first := coordinate query depth < value ||
          (coordinate query depth == value && query.key < key)
        frontier := (if first then [(left,depth+1),(right,depth+1)] else
          [(right,depth+1),(left,depth+1)]) ++ frontier
  if bounded : leaves ≤ leafBudget ∧ keys.length ≤ leafBudget*leafLimit ∧ nodes ≤ (leafBudget+1)*128 then
    return ⟨⟨keys.reverse,leaves,nodes,ready.manifest.points,ready.manifest.leaves⟩,
      by simpa only [List.length_reverse] using bounded⟩
  else throw (IO.userError "route nomination exceeds its checked quota")

theorem nomination_keys_bounded (result : { result : Nomination // result.visitedLeaves ≤ budget ∧
    result.keys.length ≤ budget*leafLimit ∧ result.visitedNodes ≤ (budget+1)*128 }) :
    result.val.keys.length ≤ budget*leafLimit := result.property.2.1

end Eggshell.VectorRoute
