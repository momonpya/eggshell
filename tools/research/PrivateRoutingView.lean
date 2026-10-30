module
public import Eggshell.SynapticRoutingStore
public import Eggshell.HashDistinct
@[expose] public section

namespace Eggshell.Synapses.Routing.PrivateView
open Lean DB Store

structure Root where
  query : String
  id : Option Nat
  bytes : Nat
  deriving ToJson, FromJson

structure Value where
  id : Nat
  target : Recommend.Target
  bytes : Nat
  deriving ToJson, FromJson

/-- Only requested private query incidences and their referenced metadata.
No original text, query plaintext, write path, or full private index is sent. -/
structure Capsule where
  manifest : Store.Manifest
  roots : Array Root
  scans : Array (Nat × Store.Scan)
  values : Array Value
  nodes : Array (Nat × String)
  deriving ToJson, FromJson

def capacity : Nat := 8*1024*1024-65536

def distinctKeys [BEq α] [Hashable α] (keys : Array α) :=
  (Std.HashSet.ofArray keys).size == keys.size

/-- Validation grants no authority. This represents only the `.used` lane;
the shared lane independently resolves every returned quoted range. -/
def Capsule.check (capsule : Capsule) : IO Unit := do
  unless capsule.manifest.scope == .usage &&
      distinctKeys (capsule.roots.map (·.query)) && distinctKeys (capsule.scans.map Prod.fst) &&
      distinctKeys (capsule.values.map (·.id)) && distinctKeys (capsule.nodes.map Prod.fst) &&
      (toJson capsule).compress.utf8ByteSize ≤ capacity do
    throw (IO.userError "invalid private routing capsule domain or size")
  let scanned := Std.HashMap.ofArray capsule.scans
  let values := capsule.values.foldl (fun found value => found.insert value.id value)
    ({} : Std.HashMap Nat Value)
  let mut nodes : Std.HashMap Nat Store.Node := {}
  for (id,bytes) in capsule.nodes do
    let node ← Index.decode (α := Store.Node) bytes.toUTF8
    unless node.id == id && id < capsule.manifest.counts.nodes do
      throw (IO.userError "private routing node changed its identity")
    let .quoted source := node.key | throw (IO.userError "private routing descendant is not a shared quote")
    unless source.valid do throw (IO.userError "private routing quote is invalid")
    nodes := nodes.insert id node
  let mut referenced : Std.HashSet Nat := {}
  let mut referencedValues : Std.HashSet Nat := {}
  let mut referencedNodes : Std.HashSet Nat := {}
  for root in capsule.roots do
    unless Synapses.digest root.query do throw (IO.userError "invalid private query digest")
    let some id := root.id | do
      unless root.bytes == 0 do throw (IO.userError "absent private root has bytes")
      continue
    unless id < capsule.manifest.counts.nodes do throw (IO.userError "private routing root outside its snapshot")
    let some scan := scanned[id]? | throw (IO.userError "missing private routing incidence")
    unless scan.complete do throw (IO.userError "incomplete private routing capture")
    referenced := referenced.insert id
    for arc in scan.arcs do
      unless [3,4,5].contains arc.kind && arc.group.isNone && Synapses.digest arc.evidence &&
          arc.targets.size == 1 && arc.next.size == 1 do
        throw (IO.userError "private routing arc is not a usage projection")
      let some value := values[arc.targets[0]!]?
        | throw (IO.userError "missing private routing destination")
      let .range source := value.target | throw (IO.userError "private usage cannot supply an output witness")
      unless source.valid && value.id < capsule.manifest.counts.targets do
        throw (IO.userError "invalid private routing destination")
      let some next := nodes[arc.next[0]!]?
        | throw (IO.userError "missing private routing continuation")
      unless next.key == .quoted source do throw (IO.userError "private usage changed its shared continuation")
      referencedValues := referencedValues.insert value.id
      referencedNodes := referencedNodes.insert next.id
  unless referenced.size == capsule.scans.size && referencedValues.size == capsule.values.size &&
      referencedNodes.size == capsule.nodes.size do
    throw (IO.userError "private capsule contains unrequested metadata")

structure Prepared where
  manifest : Store.Manifest
  roots : Std.HashMap String (Option Nat × Nat)
  scans : Std.HashMap Nat Store.Scan
  values : Std.HashMap Nat (Recommend.Target × Nat)
  nodes : Std.HashMap Nat String

def Capsule.prepare (capsule : Capsule) : IO Prepared := do
  capsule.check
  return {
    manifest := capsule.manifest
    roots := capsule.roots.foldl (fun found root => found.insert root.query (root.id,root.bytes)) {}
    scans := Std.HashMap.ofArray capsule.scans
    values := capsule.values.foldl (fun found value => found.insert value.id (value.target,value.bytes)) {}
    nodes := Std.HashMap.ofArray capsule.nodes}

/-- No source/usage directory is opened by this reader. Inadequate remaining
query budget is explicit incompleteness, never successful empty feedback. -/
def Prepared.readView (prepared : Prepared) : Store.ReadView := {
  manifest := prepared.manifest
  locate := fun key => do
    let .query query := key | throw (IO.userError "private lane accepts only query roots")
    let some root := prepared.roots[query]? | throw (IO.userError "uncaptured private query root")
    pure root
  scan := fun id limit bytes deadline => do
    let some scan := prepared.scans[id]? | throw (IO.userError "uncaptured private incidence")
    if scan.arcs.size > limit || scan.bytes > bytes || (← IO.monoMsNow) ≥ deadline then
      pure {complete := false} else pure scan
  destination := fun id => do
    let some value := prepared.values[id]? | throw (IO.userError "uncaptured private destination")
    pure value
  group := fun _ => throw (IO.userError "private usage has no joint group")
  nodeBytes := fun id => pure (prepared.nodes[id]?.map String.toUTF8)}

theorem Prepared.manifest_preserved (prepared : Prepared) :
    prepared.readView.manifest = prepared.manifest := rfl

/-- Capture only query roots; all descendants return to the shared reader
in the unchanged routing loop. IO and bytes remain bounded per request. -/
def capture (reader : Store.Reader) (queries : Array String) (deadline : Nat) : IO Capsule := do
  unless reader.manifest.scope == .usage do throw (IO.userError "capture requires private usage scope")
  let view := reader.readView
  let mut roots := #[]
  let mut scans := #[]
  let mut values : Std.HashMap Nat Value := {}
  let mut nodes : Std.HashMap Nat String := {}
  let mut scanned : Std.HashSet Nat := {}
  let mut total := 0
  for query in (hashDistinct queries.toList).toArray do
    unless Synapses.digest query && (← IO.monoMsNow) < deadline do
      throw (IO.userError "private capture expired or query invalid")
    let (id,bytes) ← view.locate (.query query)
    total := total+bytes
    roots := roots.push ⟨query,id,bytes⟩
    let some id := id | continue
    if scanned.contains id then continue
    scanned := scanned.insert id
    let scan ← view.scan id ({} : Store.Limits).arcs (capacity-total) deadline
    unless scan.complete do throw (IO.userError "private capture did not finish")
    total := total+scan.bytes
    scans := scans.push (id,scan)
    for arc in scan.arcs do
      for target in arc.targets do
        unless values.contains target do
          let (value,bytes) ← view.destination target
          values := values.insert target ⟨target,value,bytes⟩
          total := total+bytes
      for id in arc.next do
        unless nodes.contains id do
          let some bytes ← view.nodeBytes id | throw (IO.userError "private capture lost its continuation")
          let some text := String.fromUTF8? bytes | throw (IO.userError "private continuation is not UTF-8")
          unless text.toUTF8 == bytes do throw (IO.userError "private continuation changed its bytes")
          nodes := nodes.insert id text
          total := total+bytes.size
      unless total ≤ capacity && (← IO.monoMsNow) < deadline do
        throw (IO.userError "private capture exceeds request budget")
  let result := Capsule.mk reader.manifest roots scans (values.toArray.map Prod.snd) nodes.toArray
  result.check
  return result

structure Request where
  basis : PageMap.Head
  roots : Array (Index.Key × Nat)
  usage : Option Capsule
  deriving ToJson, FromJson

structure Reply where
  basis : PageMap.Head
  walk : Store.Walk
  deriving ToJson, FromJson

/-- The authenticated service supplies only its pinned shared view. The
caller overlay stays request-local and is never opened from a service path. -/
def execute (shared : Store.Reader) (request : Request) (deadline : Nat) : IO Reply := do
  unless shared.snapshot.head == request.basis && shared.manifest.scope == .shared &&
      request.roots.size ≤ ({} : Store.Limits).nodes do
    throw (IO.userError "routing request differs from its prepared shared basis")
  let usage ← request.usage.mapM fun capsule => do
    let expected := Std.HashSet.ofArray (request.roots.filterMap fun (key,_) => match key with
      | .query query => some query | _ => none)
    unless expected.size == capsule.roots.size && capsule.roots.all (fun root => expected.contains root.query) do
      throw (IO.userError "private routing capture differs from requested queries")
    capsule.prepare
  return ⟨request.basis,← Store.walkUsing shared.readView (usage.map Prepared.readView)
    request.roots deadline⟩

end Eggshell.Synapses.Routing.PrivateView
