module
public import Eggshell.PreparedOwners
public import Init.Data.BitVec.Lemmas

@[expose] public section
namespace Eggshell.SourceBitmap
open Lean DB Persistence.Store PreparedOwners

/-- Fixed-size leaves avoid shifting a corpus-sized bignum for a point lookup. -/
abbrev Block := BitVec 256

def contains (bits : Block) (offset : Nat) : Bool := bits.getLsbD offset
def unite (left right : Block) : Block := left ||| right
def cardinality (bits : Block) : Nat := (List.range 256).countP bits.getLsbD

theorem unite_member (left right : Block) (offset : Nat) :
    contains (unite left right) offset = (contains left offset || contains right offset) := by
  simp [contains,unite]

theorem unite_idempotent (bits : Block) : unite bits bits = bits := by
  ext i
  simp [unite]

theorem unite_associative (a b c : Block) : unite (unite a b) c = unite a (unite b c) :=
  BitVec.or_assoc a b c

structure Ref where
  id : Nat
  height : Nat
  count : Nat
  deriving ToJson, FromJson, BEq, Hashable

structure Node where
  bits : Nat := 0
  children : Array (Nat × Ref) := #[]
  deriving ToJson, FromJson

def valid (ref : Ref) (node : Node) : Bool :=
  ref.count > 0 && ref.height ≤ 32 &&
  if ref.height == 0 then node.children.isEmpty && node.bits < 2^256 &&
    cardinality (BitVec.ofNat 256 node.bits) == ref.count
  else node.bits == 0 && !node.children.isEmpty && node.children.size ≤ 16 &&
    node.children.toList == node.children.toList.mergeSort (fun a b => a.1 < b.1) &&
    hashDistinct (node.children.toList.map Prod.fst) == node.children.toList.map Prod.fst &&
    node.children.all (fun (slot,child) => slot < 16 && child.height+1 == ref.height && child.count > 0) &&
    (node.children.foldl (fun total row => total+row.2.count) 0) == ref.count

def readNode (snapshot : PageMap.Snapshot) (read : String → IO (Option ByteArray)) (ref : Ref) : IO Node := do
  let some node ← readJson (α := Node) snapshot read (key "bitmapNode" ref.id) |
    throw (IO.userError "missing immutable bitmap node")
  unless valid ref node do throw (IO.userError "invalid immutable bitmap node")
  return node

def store (writer : PageMap.Writer) (height : Nat) (node : Node) : IO (Option Ref) := do
  let count := if height == 0 then cardinality (BitVec.ofNat 256 node.bits)
    else node.children.foldl (fun total row => total+row.2.count) 0
  if count == 0 then return none
  let id ← getNat writer.get "bitmapAllocated"
  let ref : Ref := ⟨id,height,count⟩
  unless valid ref node do throw (IO.userError "refuse invalid immutable bitmap node")
  writeJson writer (key "bitmapNode" id) node
  putNat writer "bitmapAllocated" (id+1)
  return some ref

def child? (node : Node) (slot : Nat) : Option Ref :=
  (node.children.find? (·.1 == slot)).map Prod.snd

def replaceChild (node : Node) (slot : Nat) (child : Option Ref) : Node :=
  {node with children := ((node.children.filter (·.1 != slot)) ++
    child.toArray.map (slot,·)).qsort (fun a b => a.1 < b.1)}

def setAt (writer : PageMap.Writer) (height : Nat) (old : Option Ref)
    (block : Nat) (bits : Block) : IO (Option Ref) := do
  let snapshot ← writer.snapshot
  if let some ref := old then
    unless ref.height == height do throw (IO.userError "bitmap path height mismatch")
  match height with
  | 0 =>
    unless block == 0 do throw (IO.userError "bitmap block outside leaf")
    if let some ref := old then
      if (← readNode snapshot writer.get ref).bits == bits.toNat then return old
    store writer 0 {bits := bits.toNat}
  | height+1 =>
    let node ← match old with
      | none => pure ({} : Node)
      | some ref => readNode snapshot writer.get ref
    let span := 16^height
    let slot := block/span
    unless slot < 16 do throw (IO.userError "bitmap block outside branch")
    let previous := child? node slot
    let next ← setAt writer height previous (block%span) bits
    if next == previous then return old
    store writer (height+1) (replaceChild node slot next)

def leaf (snapshot : PageMap.Snapshot) (read : String → IO (Option ByteArray))
    (height : Nat) (root : Option Ref) (block : Nat) : IO Block := do
  let some ref := root | return 0
  unless ref.height == height do throw (IO.userError "bitmap lookup height mismatch")
  let node ← readNode snapshot read ref
  match height with
  | 0 => return if block == 0 then BitVec.ofNat 256 node.bits else 0
  | height+1 =>
    let span := 16^height
    if block/span ≥ 16 then return 0
    leaf snapshot read height (child? node (block/span)) (block%span)

def grow (writer : PageMap.Writer) (root : Option Ref) (height : Nat) : IO (Option Ref) := do
  match height with
  | 0 => return root
  | height+1 =>
    let some ref := root | return none
    let next ← store writer (ref.height+1) {children := #[(0,ref)]}
    grow writer next height

def set (writer : PageMap.Writer) (root : Option Ref) (id : Nat) (present : Bool) : IO (Option Ref) := do
  let block := id/256
  let oldHeight := root.map (·.height) |>.getD 0
  let mut height := oldHeight
  let mut span := 16^height
  while block ≥ span do
    height := height+1
    unless height ≤ 32 do throw (IO.userError "owner id exceeds bitmap address limit")
    span := span*16
  let expanded ← grow writer root (height-oldHeight)
  let bits ← leaf (← writer.snapshot) writer.get height expanded block
  let mask : Block := BitVec.ofNat 256 (2^(id%256))
  setAt writer height expanded block (if present then bits ||| mask else bits &&& ~~~mask)

/-- Request-local memo: ids below `boundary` are immutable persisted nodes;
new ids exist only in this arena and are never written during retrieval. -/
structure Reader where
  snapshot : PageMap.Snapshot
  boundary : Nat
  next : IO.Ref Nat
  nodes : IO.Ref (Std.HashMap Nat (Ref × Node))
  joins : IO.Ref (Std.HashMap (Nat × Nat) Ref)
  reads : IO.Ref Nat

def Reader.new (snapshot : PageMap.Snapshot) : IO Reader := do
  let boundary ← getNat snapshot.get "bitmapAllocated"
  return ⟨snapshot,boundary,← IO.mkRef boundary,← IO.mkRef {},← IO.mkRef {},← IO.mkRef 0⟩

def Reader.read (reader : Reader) (ref : Ref) : IO Node := do
  if let some (known,node) := (← reader.nodes.get)[ref.id]? then
    unless ref == known do throw (IO.userError "bitmap reference metadata changed")
    return node
  unless ref.id < reader.boundary do throw (IO.userError "foreign virtual bitmap reference")
  let node ← readNode reader.snapshot reader.snapshot.get ref
  reader.reads.modify (·+1)
  reader.nodes.modify (·.insert ref.id (ref,node))
  return node

def Reader.put (reader : Reader) (height : Nat) (node : Node) : IO Ref := do
  let count := if height == 0 then cardinality (BitVec.ofNat 256 node.bits)
    else node.children.foldl (fun total row => total+row.2.count) 0
  let id ← reader.next.get
  let ref : Ref := ⟨id,height,count⟩
  unless valid ref node do throw (IO.userError "invalid joined bitmap node")
  reader.next.set (id+1)
  reader.nodes.modify (·.insert id (ref,node))
  return ref

def Reader.raise (reader : Reader) (root : Ref) (levels : Nat) : IO Ref := do
  match levels with
  | 0 => return root
  | levels+1 =>
    let next ← reader.put (root.height+1) {children := #[(0,root)]}
    reader.raise next levels

def Reader.mergeAt (reader : Reader) (height : Nat) (left right : Ref) : IO Ref := do
  unless left.height == height && right.height == height do
    throw (IO.userError "unaligned bitmap union")
  if left.id == right.id then
    unless left == right do throw (IO.userError "immutable bitmap id has different metadata")
    return left
  if let some result := (← reader.joins.get)[(left.id,right.id)]? then return result
  let a ← reader.read left
  let b ← reader.read right
  let result ← match height with
    | 0 => do
      let bits := a.bits ||| b.bits
      if bits == a.bits then pure left
      else if bits == b.bits then pure right
      else reader.put 0 {bits}
    | height+1 => do
      let mut children := #[]
      for slot in [:16] do
        let child ← match child? a slot, child? b slot with
          | none,child | child,none => pure child
          | some a,some b => some <$> reader.mergeAt height a b
        if let some child := child then children := children.push (slot,child)
      if children == a.children then pure left
      else if children == b.children then pure right
      else reader.put (height+1) {children}
  reader.joins.modify fun cache => cache.insert (left.id,right.id) result |>.insert (right.id,left.id) result
  return result

def Reader.union (reader : Reader) (left right : Option Ref) : IO (Option Ref) := do
  match left,right with
  | none,right => return right
  | left,none => return left
  | some a,some b =>
    if let some result := (← reader.joins.get)[(a.id,b.id)]? then return some result
    let height := max a.height b.height
    let alignedA ← reader.raise a (height-a.height)
    let alignedB ← reader.raise b (height-b.height)
    let result ← reader.mergeAt height alignedA alignedB
    reader.joins.modify fun cache => cache.insert (a.id,b.id) result |>.insert (b.id,a.id) result
    return some result

def Reader.members (reader : Reader) (height : Nat) (root : Ref) (base : Nat := 0) : IO (List Nat) := do
  unless root.height == height do throw (IO.userError "bitmap enumeration height mismatch")
  let node ← reader.read root
  match height with
  | 0 => return (List.range 256).filterMap fun offset =>
      if (BitVec.ofNat 256 node.bits).getLsbD offset then some (base+offset) else none
  | height+1 =>
    let mut result := []
    for (slot,child) in node.children do
      result := result++(← reader.members height child (base+slot*(256*16^height)))
    return result

end Eggshell.SourceBitmap
