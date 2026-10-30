module
public import Eggshell.SynapticRoutingStore
@[expose] public section
namespace Eggshell.Synapses.Routing.Store
open Lean DB Recommend
/-- Private usage supplies query roots. Its descendants return to the shared
relation, exactly as the original reader dispatch does for non-query keys. -/
def referenceWalk (shared : Reader) (usage : Option Reader) (roots : Array (Index.Key × Nat))
    (deadline : Nat) (limits : Limits := {}) : IO Walk := do
  if let some usage := usage then
    unless shared.manifest.scope == .shared && usage.manifest.scope == .usage &&
        shared.manifest.source.identity == usage.manifest.source.identity &&
        shared.manifest.source.authority == usage.manifest.source.authority do
      throw (IO.userError "routing overlay has a different source or privacy scope")
  let readerFor := fun (lane : Nat) => if lane == 0 then shared else usage.getD shared
  let locate := fun (key : Index.Key) => do
    let lane := match key with | .query _ => if usage.isSome then 1 else 0 | _ => 0
    let (id,bytes) ← (readerFor lane).locate key
    pure (id.map (lane,·),bytes)
  let roots := roots.qsort fun a b =>
    if a.2 == b.2 then (toJson a.1).compress < (toJson b.1).compress else a.2 < b.2
  let mut seen : Std.HashSet (Nat × Nat) := {}
  let mut result : Walk := {}
  let mut pending : Array RawHint := #[]
  for (key,priority) in roots do
    if (← IO.monoMsNow) ≥ deadline then return {result with complete := false}
    let (root,bytes) ← locate key
    if result.bytes+bytes > limits.bytes then return {result with complete := false}
    result := {result with bytes := result.bytes+bytes}
    let some root := root | continue
    let mut queue := #[root]
    let mut position := 0
    while position < queue.size do
      let (lane,node) := queue[position]!
      position := position+1
      if seen.contains (lane,node) then continue
      if result.nodes ≥ limits.nodes || result.arcs ≥ limits.arcs ||
          result.bytes ≥ limits.bytes || (← IO.monoMsNow) ≥ deadline then
        return {result with complete := false}
      seen := seen.insert (lane,node)
      let reader := readerFor lane
      let scanned ← match reader.snapshot.head.root with
        | none => pure ({} : Scan)
        | some ref => scanAt reader ref node (limits.arcs-result.arcs) (limits.bytes-result.bytes) deadline {}
      result := {result with
        nodes := result.nodes+1
        arcs := result.arcs+scanned.arcs.size
        bytes := result.bytes+scanned.bytes}
      unless scanned.complete do return {result with complete := false}
      for arc in scanned.arcs do
        if pending.size+arc.targets.size > limits.hints || queue.size+arc.next.size > limits.queue then
          return {result with complete := false}
        pending := pending ++ arc.targets.map (fun target => ⟨target,priority,arc.evidence,arc.kind,arc.group,lane⟩)
        if lane == 0 then queue := queue ++ arc.next.map (0,·)
        else
          for next in arc.next do
            let some bytes ← reader.snapshot.get (nodeName next) |
              throw (IO.userError "missing private routing descendant")
            let node ← Index.decode (α := Node) bytes
            unless node.id == next do throw (IO.userError "private routing descendant moved")
            let (destination,cost) ← locate node.key
            if result.bytes+bytes.size+cost > limits.bytes then return {result with complete := false}
            result := {result with bytes := result.bytes+bytes.size+cost}
            if let some destination := destination then queue := queue.push destination
  -- Group by target before materializing, so repeated evidence for one
  -- range does not trigger repeated metadata reads or unbounded caches.
  let ordered := (pending.mapIdx (fun ordinal hint => (ordinal,hint))).qsort fun a b =>
    if a.2.lane == b.2.lane then a.2.target < b.2.target else a.2.lane < b.2.lane
  let mut previous : Option ((Nat × Nat) × Target) := none
  let mut groups : Std.HashMap (Nat × Nat) Group := {}
  let mut displayed : Array (Nat × Hint) := #[]
  for (ordinal,hint) in ordered do
    if (← IO.monoMsNow) ≥ deadline then return {result with complete := false}
    let reader := readerFor hint.lane
    let (target,bytes) ← match previous with
      | some (id,target) => if id == (hint.lane,hint.target) then pure (target,0) else reader.destination hint.target
      | none => reader.destination hint.target
    if result.bytes+bytes > limits.bytes then return {result with complete := false}
    result := {result with bytes := result.bytes+bytes}
    let (group,groupBytes) ← match hint.group with
      | none => pure (none,0)
      | some id =>
        if let some group := groups[(hint.lane,id)]? then pure (some group,0)
        else do
          let (group,bytes) ← reader.group id
          pure (some group,bytes)
    if result.bytes+groupBytes > limits.bytes then return {result with complete := false}
    result := {result with bytes := result.bytes+groupBytes}
    if groupBytes > 0 then
      if let some id := hint.group then
        if let some group := group then groups := groups.insert (hint.lane,id) group
    previous := some ((hint.lane,hint.target),target)
    displayed := displayed.push (ordinal,⟨target,hint.priority,hint.evidence,hint.kind,group⟩)
  return {result with hints := (displayed.qsort (fun a b => a.1 < b.1)).map Prod.snd}


end Eggshell.Synapses.Routing.Store
