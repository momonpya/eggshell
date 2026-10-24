module

public import Lean.Data.Json.Parser
public import Lean.Data.Json.FromToJson

@[expose] public section

namespace Eggshell.JsonScalars
open Lean

inductive Segment where
  | key (name : String)
  | index (position : Nat)
  deriving DecidableEq, BEq, ToJson, FromJson

def pathJson (path : List Segment) : Json :=
  toJson (path.map fun part => match part with
    | .key name => toJson name | .index position => toJson position)

def resolve (value : Json) : List Segment → Except String Json
  | [] => .ok value
  | .key name :: rest => do resolve (← value.getObjVal? name) rest
  | .index position :: rest => do resolve (← value.getArrVal? position) rest

structure Scalar where
  first : Nat
  limit : Nat
  literal : String
  text : Option String
  offsets : Array Nat
  /-- Reversed paths share their ancestors instead of copying every prefix. -/
  pathRev : List Segment
  contextFirst : Nat

structure Frame where
  object : Bool
  pathRev : List Segment
  next : Nat := 0
  key : Option (String × Nat) := none

def place (frames : Array Frame) (first : Nat) :
    Except String (List Segment × Nat × Array Frame) := do
  let some frame := frames.back? | return ([],first,frames)
  if frame.object then
    let some (key,start) := frame.key | throw "structured object has no pending key"
    return (.key key :: frame.pathRev,start,frames.pop.push {frame with key := none})
  else
    return (.index frame.next :: frame.pathRev,first,
      frames.pop.push {frame with next := frame.next+1})

def primitive : Json → Bool
  | .arr _ | .obj _ => false
  | _ => true

def scalarLiteral (text : String) : Bool :=
  (Json.parse text).toOption.any fun value => primitive value && value.compress == text

/-- One canonical scan records literal coordinates, immediate member starts
and shared ancestor paths. Keys provide context but never become witnesses. -/
def scan (json : Json) (raw : String) : Except String (Array Scalar) := do
  unless json.compress == raw do throw "noncanonical structured observation"
  let chars := raw.toList.toArray
  let mut position := 0
  let mut result := #[]
  let mut frames : Array Frame := #[]
  while position < chars.size do
    let char := chars[position]!
    if char == '{' || char == '[' then
      let (path,_,next) ← place frames position
      frames := next.push {object := char == '{',pathRev := path}
      position := position+1
    else if char == '}' || char == ']' then
      frames := frames.pop
      position := position+1
    else if char.isWhitespace || ",:".contains char then
      position := position+1
    else if char == '"' then
      let first := position
      position := position+1
      let mut escaped := false
      let mut closed := false
      while position < chars.size do
        let char := chars[position]!
        position := position+1
        if escaped then escaped := false
        else if char == '\\' then escaped := true
        else if char == '"' then closed := true; break
      unless closed do throw "unfinished structured string"
      let limit := position
      let mut following := position
      while following < chars.size && chars[following]!.isWhitespace do following := following+1
      let literal := String.ofList (chars.extract first limit).toList
      let text ← Json.parse literal >>= Json.getStr?
      if chars[following]? == some ':' then
        let some frame := frames.back? | throw "structured key has no object"
        unless frame.object && frame.key.isNone do throw "structured key outside an object"
        frames := frames.pop.push {frame with key := some (text,first)}
        continue
      let (path,contextFirst,next) ← place frames first
      frames := next
      let mut offsets := #[]
      let mut original := first+1
      for char in text.toList do
        offsets := offsets.push original
        original := original+(toJson (String.singleton char)).compress.length-2
      offsets := offsets.push original
      unless original+1 == limit do throw "structured scalar coordinates differ"
      result := result.push ⟨first,limit,literal,some text,offsets,path,contextFirst⟩
    else
      let first := position
      while position < chars.size && !chars[position]!.isWhitespace &&
          !("{}[],:".contains chars[position]!) do position := position+1
      let literal := String.ofList (chars.extract first position).toList
      unless scalarLiteral literal do throw "invalid structured scalar"
      let (path,contextFirst,next) ← place frames first
      frames := next
      result := result.push ⟨first,position,literal,none,#[],path,contextFirst⟩
  return result

def values (raw : String) : Except String (Array Scalar) := do scan (← Json.parse raw) raw

def Scalar.prefixExact (scalar : Scalar) (raw : Array Char) : Bool :=
  match scalar.pathRev.head? with
  | some (.key name) =>
      String.ofList (raw.extract scalar.contextFirst scalar.first).toList ==
        (toJson name).compress ++ ":"
  | _ => scalar.contextFirst == scalar.first

/-- A displayed path is independently checked against the parsed original.
Its member prefix and literal still refer to exact original characters. -/
structure Checked (root : Json) (raw : Array Char) where
  scalar : Scalar
  value : Json
  resolved : resolve root scalar.pathRev.reverse = .ok value
  primitive : primitive value = true
  spelling : value.compress = scalar.literal
  bounds : scalar.contextFirst ≤ scalar.first ∧ scalar.first < scalar.limit ∧ scalar.limit ≤ raw.size
  exact : String.ofList (raw.extract scalar.first scalar.limit).toList = scalar.literal
  memberExact : scalar.prefixExact raw = true

def Checked.check? (root : Json) (raw : Array Char) (scalar : Scalar) : Option (Checked root raw) :=
  match resolved : resolve root scalar.pathRev.reverse with
  | .error _ => none
  | .ok value =>
    if primitive : JsonScalars.primitive value = true then
      if spelling : value.compress = scalar.literal then
        if bounds : scalar.contextFirst ≤ scalar.first ∧ scalar.first < scalar.limit ∧ scalar.limit ≤ raw.size then
          if exact : String.ofList (raw.extract scalar.first scalar.limit).toList = scalar.literal then
            if memberExact : scalar.prefixExact raw = true then
              some ⟨scalar,value,resolved,primitive,spelling,bounds,exact,memberExact⟩ else none
          else none
        else none
      else none
    else none

structure Address (raw : String) where
  root : Json
  characters : Array Char
  parsed : Json.parse raw = .ok root
  charactersExact : characters = raw.toList.toArray
  leaf : Checked root characters

def Address.path (address : Address raw) : List Segment := address.leaf.scalar.pathRev.reverse

def Address.label (address : Address raw) : String := (pathJson address.path).compress

theorem address_resolves (address : Address raw) :
    Json.parse raw = .ok address.root ∧ resolve address.root address.path = .ok address.leaf.value :=
  ⟨address.parsed,address.leaf.resolved⟩

theorem address_literal_is_original (address : Address raw) :
    String.ofList (raw.toList.toArray.extract address.leaf.scalar.first address.leaf.scalar.limit).toList =
      address.leaf.value.compress := by
  rw [← address.charactersExact,address.leaf.spelling]
  exact address.leaf.exact

structure Index (raw : String) where
  root : Json
  characters : Array Char
  parsed : Json.parse raw = .ok root
  charactersExact : characters = raw.toList.toArray
  leaves : Array (Checked root characters)

def prepare? (raw : String) : Option (Index raw) := do
  match parsed : Json.parse raw with
  | .error _ => none
  | .ok root =>
    let scalars ← (scan root raw).toOption
    let characters := raw.toList.toArray
    let leaves ← scalars.mapM (Checked.check? root characters)
    return ⟨root,characters,parsed,rfl,leaves⟩

/-- Scalar limits are in original serialization order. Search once by the
last position; ancestors and field names do not require a linear leaf scan. -/
def Index.cover? (index : Index raw) (first limit : Nat) : Option (Address raw) := Id.run do
  let mut lower := 0
  let mut upper := index.leaves.size
  while lower < upper do
    let middle := (lower+upper)/2
    let some leaf := index.leaves[middle]? | return none
    if leaf.scalar.limit < limit then lower := middle+1 else upper := middle
  let some leaf := index.leaves[lower]? | return none
  if leaf.scalar.contextFirst ≤ first && first < limit && limit ≤ leaf.scalar.limit then
    return some ⟨index.root,index.characters,index.parsed,index.charactersExact,leaf⟩
  return none

def Index.witness? (index : Index raw) (first limit : Nat) : Option (Address raw) := do
  let address ← index.cover? first limit
  if address.leaf.scalar.first ≤ first then some address else none

end Eggshell.JsonScalars
