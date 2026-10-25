module
public import Eggshell.VectorBlocks
public import Init.Data.FloatArray
public import Init.Data.List.Sort.Lemmas

@[expose] public section
namespace Eggshell.VectorPartition
open Lean DB

def sampleCapacity : Nat := 16384
def sampleLeafCapacity : Nat := 32
def iterations : Nat := 4
def postingCapacity : Nat := 32

def dot (a b : FloatArray) : Float := Id.run do
  let mut value := 0.0
  for i in [:a.size] do value := value + a[i]!*b[i]!
  return value

def zero (width : Nat) : FloatArray := (Array.replicate width (0.0 : Float)).toList.toFloatArray

def add (a b : FloatArray) : FloatArray := Id.run do
  let mut result := a
  for i in [:a.size] do result := result.set! i (a[i]!+b[i]!)
  return result

def subtract (a b : FloatArray) : FloatArray := Id.run do
  let mut result := FloatArray.emptyWithCapacity a.size
  for i in [:a.size] do result := result.push (a[i]!-b[i]!)
  return result

def normalize (a : FloatArray) : FloatArray := Id.run do
  let norm := (dot a a).sqrt
  if norm == 0.0 then return a
  let mut result := FloatArray.emptyWithCapacity a.size
  for i in [:a.size] do result := result.push (a[i]!/norm)
  return result

/-- Routing sees the same float32 values as the unchanged scorer. This view
does not replace the original binary64 bytes or change their score. -/
def decode (raw : ByteArray) : Except String FloatArray := do
  unless 0 < raw.size && raw.size%8 == 0 && raw.size/8 ≤ 4096 do throw "invalid partition dimensions"
  let mut result := FloatArray.emptyWithCapacity (raw.size/8)
  for i in [:raw.size/8] do
    let mut bits : UInt64 := 0
    for j in [:8] do bits := bits ||| (raw[i*8+j]!.toUInt64 <<< (8*j).toUInt64)
    let value := (Float.ofBits bits).toFloat32.toFloat
    unless value.isFinite do throw "nonfinite partition coordinate"
    result := result.push value
  return result

def pack (values : FloatArray) : ByteArray := Id.run do
  let mut result := ByteArray.empty
  for value in values do
    let bits := value.toBits
    for j in [:8] do result := result.push ((bits >>> (8*j).toUInt64).toUInt8)
  return result

/-- Centroids and planes retain binary64 routing arithmetic. They are never
fed back as substitute source projections. -/
def unpack (raw : ByteArray) : Except String FloatArray := do
  unless 0 < raw.size && raw.size%8 == 0 && raw.size/8 ≤ 4096 do throw "invalid routing geometry"
  let mut result := FloatArray.emptyWithCapacity (raw.size/8)
  for i in [:raw.size/8] do
    let mut bits : UInt64 := 0
    for j in [:8] do bits := bits ||| (raw[i*8+j]!.toUInt64 <<< (8*j).toUInt64)
    let value := Float.ofBits bits
    unless value.isFinite do throw "nonfinite routing geometry"
    result := result.push value
  return result

structure Sample where
  key : String
  values : FloatArray
  deriving Inhabited

def center (points : List Sample) : FloatArray :=
  normalize (points.foldl (fun sum point => add sum point.values)
    (zero (points.headD default).values.size))

def furthest (points : List Sample) (origin : FloatArray) : Sample :=
  let fixed := dot origin origin
  points.foldl (fun best point =>
    let distance := fun p : Sample => dot p.values p.values - 2.0*dot p.values origin + fixed
    if distance point > distance best || (distance point == distance best && point.key < best.key)
      then point else best) (points.headD default)

def byProjection (plane : FloatArray) (points : List Sample) : List Sample :=
  ((points.map fun point => (dot point.values plane,point)).mergeSort fun a b =>
    a.1 > b.1 || (a.1 == b.1 && a.2.key ≤ b.2.key)).map Prod.snd

theorem projection_perm (plane : FloatArray) (points : List Sample) :
    (byProjection plane points).Perm points := by
  have h := (List.mergeSort_perm (points.map fun point => (dot point.values plane,point))
    (fun a b => a.1 > b.1 || (a.1 == b.1 && a.2.key ≤ b.2.key))).map Prod.snd
  simpa [byProjection,List.map_map,Function.comp_def] using h

def plane (points : List Sample) : FloatArray := Id.run do
  let seed := furthest points (center points)
  let other := furthest points seed.values
  let mut direction := subtract (normalize seed.values) (normalize other.values)
  for _ in [:iterations] do
    let ordered := byProjection direction points
    let left := ordered.take (points.length/2)
    let right := ordered.drop (points.length/2)
    direction := subtract (center left) (center right)
  return direction

inductive Training where
  | leaf (points : List Sample) (bounded : points.length ≤ sampleLeafCapacity)
  | branch (direction : FloatArray) (cut : Float) (tie : String) (left right : Training)

def Training.points : Training → List Sample
  | .leaf points _ => points
  | .branch _ _ _ a b => a.points ++ b.points

structure Trained (original : List Sample) where
  tree : Training
  exact : tree.points.Perm original

/-- Data-dependent balanced splits retain every sample, even when all vectors
are identical. There is no nearest-neighbor or floating pruning claim here. -/
def train (original : List Sample) : Trained original :=
  if small : original.length ≤ sampleLeafCapacity then
    ⟨.leaf original small,List.Perm.refl _⟩
  else
    let direction := plane original
    let ordered := byProjection direction original
    let middle := original.length/2
    let pivot := (ordered.drop middle).headD default
    let a := train (ordered.take middle)
    let b := train (ordered.drop middle)
    ⟨.branch direction (dot pivot.values direction) pivot.key a.tree b.tree,by
      change (a.tree.points ++ b.tree.points).Perm original
      have both := a.exact.append b.exact
      rw [List.take_append_drop] at both
      exact both.trans (projection_perm direction original)⟩
termination_by original.length
decreasing_by
  all_goals have len := List.Perm.length_eq (projection_perm (plane original) original)
  all_goals simp only [List.length_take,List.length_drop] at *
  all_goals have big : 32 < original.length := by simpa [sampleLeafCapacity] using Nat.lt_of_not_ge small
  all_goals have half : original.length/2 < original.length := Nat.div_lt_self (by omega) (by omega)
  all_goals omega

theorem training_preserves_samples (points : List Sample) : (train points).tree.points.Perm points :=
  (train points).exact

inductive Node where
  | leaf (cell : Nat)
  | branch (direction : ByteArray) (cut : Nat) (tie : String) (left right : Nat)
  deriving Inhabited

def nodeCodec : Wire.Codec Node :=
  (Wire.sum Wire.natural (Wire.byteBlob.product (Wire.natural.product
    (Wire.text.product (Wire.natural.product Wire.natural))))).iso
    (fun | .leaf cell => .inl cell
         | .branch direction cut tie left right => .inr (direction,cut,tie,left,right))
    (fun | .inl cell => .leaf cell
         | .inr (direction,cut,tie,left,right) => .branch direction cut tie left right)
    (by intro node; cases node <;> rfl)

theorem node_roundtrip (node : Node) (tail : List UInt8) :
    nodeCodec.decode (nodeCodec.encode node ++ tail) = .ok (node,tail) := nodeCodec.roundtrip node tail

structure Geometry where
  nodes : Array Node
  root : Nat
  cells : Nat

def compile (tree : Training) : Geometry := Id.run do
  let rec visit (tree : Training) (nodes : Array Node) (next : Nat) : Array Node × Nat × Nat :=
    match tree with
    | .leaf _ _ => (nodes.push (.leaf next),nodes.size,next+1)
    | .branch direction cut tie a b =>
      let (nodes,left,next) := visit a nodes next
      let (nodes,right,next) := visit b nodes next
      (nodes.push (.branch (pack direction) cut.toBits.toNat tie left right),nodes.size,next)
  let (nodes,root,cells) := visit tree #[] 0
  return ⟨nodes,root,cells⟩

inductive RuntimeNode where
  | leaf (cell : Nat)
  | branch (direction : FloatArray) (cut : Float) (tie : String) (left right : Nat)

structure Runtime where
  geometry : Geometry
  nodes : Array RuntimeNode

def restore (geometry : Geometry) (width : Nat) : Except String Runtime := do
  let nodes ← geometry.nodes.mapIdxM fun index node => do
    match node with
    | .leaf cell =>
      unless cell < geometry.cells do throw "foreign assignment cell"
      return RuntimeNode.leaf cell
    | .branch raw cut tie left right =>
      unless left < index && right < index && left != right && cut < 2^64 do throw "invalid assignment branch"
      let direction ← unpack raw
      let threshold := Float.ofBits cut.toUInt64
      unless direction.size == width && threshold.isFinite do throw "invalid assignment geometry"
      return RuntimeNode.branch direction threshold tie left right
  return ⟨geometry,nodes⟩

def assign (runtime : Runtime) (key : String) (values : FloatArray) : Except String Nat := do
  let geometry := runtime.geometry
  let mut index := geometry.root
  for _ in [:64] do
    let some node := runtime.nodes[index]? | throw "foreign assignment node"
    match node with
    | .leaf cell =>
      unless cell < geometry.cells do throw "foreign assignment cell"
      return cell
    | .branch direction cut tie left right =>
      unless direction.size == values.size do throw "assignment dimensions disagree"
      let score := dot values direction
      unless score.isFinite && cut.isFinite do throw "nonfinite assignment"
      index := if score > cut || (score == cut && key < tie) then left else right
  throw "assignment depth exceeded"

structure Basis where
  source : PageMap.Head
  matrix : PageMap.Head
  blocks : PageMap.Head
  eligibility : String
  rows : Nat
  width : Nat
  deriving ToJson, FromJson, BEq

structure Cell where
  center : FloatArray
  keys : Array String
  deriving Inhabited

structure Header where
  basis : Basis
  nodes : Nat
  root : Nat
  cells : Nat
  pages : Nat
  deriving ToJson, FromJson

def implementation := Sha256.hex (include_str "VectorPartition.lean").toUTF8
def authority := "eggshell.vector-partition:"++implementation

def cellCodec := Wire.byteBlob.product (Wire.natural.product Wire.natural)
def keysCodec := Wire.list Wire.text

def publish (path : System.FilePath) (basis : Basis) (geometry : Geometry) (cells : Array Cell) :
    IO PageMap.Snapshot := do
  unless !(← path.pathExists) && cells.size == geometry.cells &&
      0 < cells.size && 0 < geometry.nodes.size && geometry.root+1 == geometry.nodes.size do
    throw (IO.userError "invalid/new partition publication required")
  let _ ← IO.ofExcept (restore geometry basis.width)
  let snapshot ← PageMap.create path authority
  let _ ← PageMap.withWriter snapshot fun writer => do
    let mut rows := 0
    let mut pages := 0
    let mut seen : Std.HashSet String := {}
    for i in [:geometry.nodes.size] do
      writer.put (s!"node:{i}") (some (nodeCodec.encode geometry.nodes[i]!).toByteArray)
    for i in [:cells.size] do
      let cell := cells[i]!
      unless cell.center.size == basis.width do throw (IO.userError "cell dimensions disagree")
      let count := (cell.keys.size+postingCapacity-1)/postingCapacity
      writer.put (s!"cell:{i}")
        (some (cellCodec.encode (pack cell.center,cell.keys.size,count)).toByteArray)
      for page in [:count] do
        let keys := cell.keys.extract (page*postingCapacity) (min cell.keys.size ((page+1)*postingCapacity))
        for key in keys do
          unless Receipt.validId key && !seen.contains key do throw (IO.userError "duplicate/foreign partition key")
          seen := seen.insert key
        writer.put (s!"posting:{i}:{page}") (some (keysCodec.encode keys.toList).toByteArray)
      rows := rows+cell.keys.size
      pages := pages+count
    let eligibility := Sha256.hex (toJson (seen.toList.mergeSort (· ≤ ·))).compress.toUTF8
    unless rows == basis.rows && eligibility == basis.eligibility do
      throw (IO.userError "partition eligibility not covered exactly")
    let header : Header := ⟨basis,geometry.nodes.size,geometry.root,cells.size,pages⟩
    writer.put "ready" (some (toJson header).compress.toUTF8)
  PageMap.pin path

structure Ready where
  snapshot : PageMap.Snapshot
  header : Header

def open? (path : System.FilePath) (basis : Basis) : IO (Option Ready) := do
  let some snapshot ← PageMap.open? path | return none
  unless snapshot.head.authority == authority do throw (IO.userError "foreign partition authority")
  let some raw ← snapshot.get "ready" | return none
  let some text := String.fromUTF8? raw | throw (IO.userError "invalid partition header")
  let header : Header ← IO.ofExcept (Json.parse text >>= fromJson?)
  unless header.basis == basis do return none
  unless 0 < header.cells && header.cells ≤ sampleCapacity && header.root+1 == header.nodes &&
      snapshot.head.root.any (·.rows == header.nodes+header.cells+header.pages+1) do
    throw (IO.userError "partition publication does not cover its header")
  return some ⟨snapshot,header⟩

structure Nominations where
  keys : List String
  visitedCells : Nat
  totalCells : Nat
  totalPoints : Nat
  partialCell : Bool
  deriving ToJson

/-- Global centroid ordering instead of depth-first adjacent leaves. This is
bounded advisory search; no score upper bound or exact stopping is asserted. -/
def nominate (ready : Ready) (queries : Array FloatArray) (quota : Nat) :
    IO {result : Nominations // result.keys.length ≤ quota} := do
  unless quota ≤ 4096 && !queries.isEmpty && queries.all (·.size == ready.header.basis.width) do
    throw (IO.userError "invalid partition query allowance")
  let mut ordered : List (Float × Nat × Nat × Nat) := []
  for i in [:ready.header.cells] do
    let some raw ← ready.snapshot.get (s!"cell:{i}") | throw (IO.userError "missing partition cell")
    let ((encoded,count,pages),tail) ← IO.ofExcept (cellCodec.decode raw.toList)
    unless tail.isEmpty && (cellCodec.encode (encoded,count,pages)).toByteArray == raw &&
        pages == (count+postingCapacity-1)/postingCapacity do throw (IO.userError "invalid partition cell")
    let center ← IO.ofExcept (unpack encoded)
    unless center.size == ready.header.basis.width do throw (IO.userError "invalid cell width")
    let score := queries.foldl (fun best query => max best (dot query center)) (-1.0e30)
    unless score.isFinite do throw (IO.userError "nonfinite centroid score")
    if count > 0 then ordered := (score,i,count,pages)::ordered
  ordered := ordered.mergeSort (fun a b => a.1 > b.1 || (a.1 == b.1 && a.2.1 ≤ b.2.1))
  let mut keys := []
  let mut count := 0
  let mut visited := 0
  let mut partialCell := false
  for (_,cell,cellCount,pages) in ordered do
    if count == quota then break
    visited := visited+1
    let mut taken := 0
    for page in [:pages] do
      if count == quota then break
      let some raw ← ready.snapshot.get (s!"posting:{cell}:{page}") | throw (IO.userError "missing partition posting")
      let (members,tail) ← IO.ofExcept (keysCodec.decode raw.toList)
      unless tail.isEmpty && (keysCodec.encode members).toByteArray == raw &&
          members.length == min postingCapacity (cellCount-page*postingCapacity) &&
          members.all Receipt.validId do throw (IO.userError "invalid partition posting")
      for key in members do
        if count == quota then break
        keys := key::keys
        count := count+1
        taken := taken+1
    if taken < cellCount then partialCell := true
  if bounded : keys.length ≤ quota then
    return ⟨⟨keys.reverse,visited,ready.header.cells,ready.header.basis.rows,partialCell⟩,by simpa using bounded⟩
  else throw (IO.userError "partition nomination exceeds its checked quota")

end Eggshell.VectorPartition
