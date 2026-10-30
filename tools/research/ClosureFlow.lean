module
public import Std
@[expose] public section

namespace Eggshell.Research.ClosureFlow

structure Arc where
  first : Nat
  last : Nat
  capacity : Nat
  deriving Inhabited

structure Network where
  vertices : Nat
  source : Nat
  sink : Nat
  arcs : Array Arc

structure Result where
  selected : Array Bool
  value : Nat
  phases : Nat
  augmentations : Nat
  flowCutChecked : Bool

def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

def reverse (edge : Nat) : Nat := if edge%2 == 0 then edge+1 else edge-1

def adjacency (network : Network) : Array (Array Nat) := Id.run do
  let mut result := Array.replicate network.vertices #[]
  for index in [:network.arcs.size] do
    let edge := network.arcs[index]!
    result := result.modify edge.first (·.push (index*2))
    result := result.modify edge.last (·.push (index*2+1))
  return result

def destination (network : Network) (edge : Nat) : Nat :=
  let original := network.arcs[edge/2]!
  if edge%2 == 0 then original.last else original.first

def levels (network : Network) (adjacent : Array (Array Nat))
    (capacities : Array Nat) : Array Nat := Id.run do
  let mut found := (Array.replicate network.vertices network.vertices).set! network.source 0
  let mut queue := #[network.source]
  let mut cursor := 0
  while cursor < queue.size do
    let vertex := queue[cursor]!
    cursor := cursor+1
    for edge in adjacent[vertex]! do
      let next := destination network edge
      if capacities[edge]! > 0 && found[next]! == network.vertices then
        found := found.set! next (found[vertex]!+1)
        queue := queue.push next
  return found

partial def send (network : Network) (adjacent : Array (Array Nat)) (distance : Array Nat)
    (capacities : IO.Ref (Array Nat)) (cursors : IO.Ref (Array Nat))
    (vertex limit : Nat) : IO Nat := do
  if vertex == network.sink then return limit
  let outgoing := adjacent[vertex]!
  repeat
    let cursor ← cursors.get <&> fun values => values[vertex]!
    if cursor ≥ outgoing.size then return 0
    let edge := outgoing[cursor]!
    let next := destination network edge
    let capacity ← capacities.get <&> fun values => values[edge]!
    if capacity > 0 && distance[next]! == distance[vertex]!+1 then
      let sent ← send network adjacent distance capacities cursors next (min limit capacity)
      if sent > 0 then
        capacities.modify fun values =>
          let previous := values[edge]!
          let back := values[reverse edge]!
          (values.set! edge (previous-sent)).set! (reverse edge) (back+sent)
        return sent
    cursors.modify (·.set! vertex (cursor+1))
  return 0

def cutCapacity (network : Network) (selected : Array Bool) : Nat :=
  network.arcs.foldl (fun total edge =>
    if selected[edge.first]! && !selected[edge.last]! then total+edge.capacity else total) 0

/-- Independently check forward/reverse capacities, conservation at every
vertex and equality with the reported cut. This is an executable certificate
check; a universal max-flow/min-cut theorem is not claimed by this module. -/
def certificate (network : Network) (capacities : Array Nat)
    (selected : Array Bool) (value : Nat) : Bool := Id.run do
  if capacities.size != network.arcs.size*2 || selected.size != network.vertices ||
      !selected[network.source]! || selected[network.sink]! then return false
  let mut incoming := Array.replicate network.vertices 0
  let mut outgoing := Array.replicate network.vertices 0
  for index in [:network.arcs.size] do
    let edge := network.arcs[index]!
    if capacities[index*2]! > edge.capacity then return false
    let flow := edge.capacity-capacities[index*2]!
    if capacities[index*2+1]! != flow then return false
    incoming := incoming.modify edge.last (·+flow)
    outgoing := outgoing.modify edge.first (·+flow)
  for vertex in [:network.vertices] do
    if vertex == network.source then
      if outgoing[vertex]! != incoming[vertex]!+value then return false
    else if vertex == network.sink then
      if incoming[vertex]! != outgoing[vertex]!+value then return false
    else if incoming[vertex]! != outgoing[vertex]! then return false
  return cutCapacity network selected == value

def solve (network : Network) (deadline : Nat) : IO Result := do
  check (network.source < network.vertices && network.sink < network.vertices &&
    network.source != network.sink && network.arcs.all (fun edge =>
      edge.first < network.vertices && edge.last < network.vertices)) "invalid closure network"
  let adjacent := adjacency network
  let initial := network.arcs.flatMap fun edge => #[edge.capacity,0]
  let capacities ← IO.mkRef initial
  let cursors ← IO.mkRef (Array.replicate network.vertices 0)
  let infinite := network.arcs.foldl (fun total edge => total+edge.capacity) 1
  let mut value := 0
  let mut phases := 0
  let mut augmentations := 0
  let mut selected := Array.replicate network.vertices false
  repeat
    check ((← IO.monoMsNow) < deadline) "closure-flow diagnostic deadline"
    let distance := levels network adjacent (← capacities.get)
    if distance[network.sink]! == network.vertices then
      selected := distance.map (· < network.vertices)
      break
    phases := phases+1
    cursors.set (Array.replicate network.vertices 0)
    repeat
      check ((← IO.monoMsNow) < deadline) "closure-flow diagnostic deadline"
      let sent ← send network adjacent distance capacities cursors network.source infinite
      if sent == 0 then break
      value := value+sent
      augmentations := augmentations+1
  let accepted := certificate network (← capacities.get) selected value
  check accepted "closure-flow certificate failed"
  return ⟨selected,value,phases,augmentations,accepted⟩

end Eggshell.Research.ClosureFlow
