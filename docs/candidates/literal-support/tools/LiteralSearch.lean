module
public import Std.Data.HashMap
@[expose] public section

/- Multi-pattern literal search. This module knows no tools, files, Work,
freshness, Union or model. Every reported occurrence is checked against both
the requested pattern and actual bounded source characters. -/
namespace LiteralSearch

structure Node where
  next : Std.HashMap Char Nat := {}
  failure : Nat := 0
  terminal : Array Nat := #[]
  exit : Option Nat := none
  deriving Inhabited

structure Index (patterns : Array String) where
  nodes : Array Node

def advance (nodes : Array Node) (start : Nat) (character : Char) : Nat := Id.run do
  let mut state := start
  for _ in [:nodes.size+1] do
    let some node := nodes[state]? | return 0
    if let some target := node.next[character]? then return target
    if state == 0 then return 0
    state := node.failure
  return 0

/-- Aho-Corasick failure/exit links share all prefixes and avoid copying the
outputs of suffix states. Source data is scanned once for all requested
patterns; repeated and overlapping occurrences remain distinct. -/
def prepare (patterns : Array String) : Index patterns := Id.run do
  let mut nodes : Array Node := #[{}]
  for pattern in [:patterns.size] do
    let characters := patterns[pattern]!.toList
    if characters.isEmpty then continue
    let mut state := 0
    for character in characters do
      match nodes[state]!.next[character]? with
      | some target => state := target
      | none =>
        let target := nodes.size
        nodes := nodes.modify state fun node => {node with next := node.next.insert character target}
        nodes := nodes.push {}
        state := target
    nodes := nodes.modify state fun node => {node with terminal := node.terminal.push pattern}
  let mut queue := nodes[0]!.next.toArray.map (·.2)
  let mut position := 0
  while position < queue.size do
    let parent := queue[position]!
    position := position+1
    for (character,child) in nodes[parent]!.next do
      let failure := advance nodes nodes[parent]!.failure character
      let exit := if nodes[failure]!.terminal.isEmpty then nodes[failure]!.exit else some failure
      nodes := nodes.modify child fun node => {node with failure,exit}
      queue := queue.push child
  return ⟨nodes⟩

structure Hit (patterns : Array String) (original : String) where
  pattern : Fin patterns.size
  first : Nat
  limit : Nat
  within : first < limit ∧ limit ≤ original.length
  exact : patterns[pattern] = String.ofList (original.toList.toArray.extract first limit).toList

theorem hit_is_requested_original (hit : Hit patterns original) :
    hit.first < hit.limit ∧ hit.limit ≤ original.length ∧
      patterns[hit.pattern] = String.ofList (original.toList.toArray.extract hit.first hit.limit).toList :=
  ⟨hit.within.1,hit.within.2,hit.exact⟩

def collect (firstOnly : Bool) (index : Index patterns) (original : String) :
    Array (Hit patterns original) := Id.run do
  let characters := original.toList.toArray
  let lengths := patterns.map String.length
  let mut result := #[]
  let mut seen : Std.HashMap Nat Unit := {}
  let mut state := 0
  for position in [:characters.size] do
    state := advance index.nodes state characters[position]!
    let mut output := some state
    for _ in [:index.nodes.size+1] do
      let some nodeIndex := output | break
      let some node := index.nodes[nodeIndex]? | break
      for pattern in node.terminal do
        if firstOnly && seen.contains pattern then continue
        if present : pattern < patterns.size then
          let limit := position+1
          let first := limit-lengths[pattern]!
          if within : first < limit ∧ limit ≤ original.length then
            if exact : patterns[pattern] = String.ofList (characters.extract first limit).toList then
              result := result.push ⟨⟨pattern,present⟩,first,limit,within,exact⟩
              if firstOnly then seen := seen.insert pattern ()
      output := node.exit
  return result

/-- Full occurrences for independent diagnostic comparison. -/
def find (index : Index patterns) (original : String) : Array (Hit patterns original) :=
  collect false index original

/-- Advisory attachment needs presence in each original record, not an array
of every repeated character occurrence. Retain one checked witness per
requested pattern, while scanning the same failure/exit automaton. -/
def first (index : Index patterns) (original : String) : Array (Hit patterns original) :=
  collect true index original

end LiteralSearch
