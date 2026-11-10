import tools.research.PreparedRoutingLeaf
import tools.research.PreparedRoutingObserver
open Lean Eggshell DB Synapses
open Synapses.Routing.Store Eggshell.Research.PreparedRoutingLeaf

#print axioms Value.unique
#print axioms select_original
#print axioms Leaf.selected_original
#print axioms Image.charge_bounded
#print axioms Image.foreign_scope

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def save (root : System.FilePath) (name : String) (value : Json) : IO Unit :=
  IO.FS.writeFile (root/name) value.compress

def prepareAt (reader : Reader) (scope : String) (ref : PageMap.Ref)
    (image : Image) (leaves pages deadline : Nat) : IO (Image × Nat × Nat) := do
  check (pages < 1024 && (← IO.monoMsNow) < deadline) "bounded leaf preparation exceeded"
  let loaded ← reader.snapshot.load ref
  let range : PageMap.KeyRange := ⟨"route:arc:","route:arc;"⟩
  match loaded.page with
  | .leaf _ =>
    let some leaf ← Leaf.capture loaded | throw (IO.userError "leaf preparation lost a leaf")
    let image := image.admit ⟨ref,leaf⟩
    check ((image.find reader.snapshot scope ref).isSome) "one compiled leaf exceeds its allowance"
    return (image,leaves+1,pages+1)
  | .branch children =>
    let mut state := (image,leaves,pages+1)
    for child in children do
      if range.overlaps child then
        if _smaller : child.height < ref.height then
          state ← prepareAt reader scope child state.1 state.2.1 state.2.2 deadline
        else throw (IO.userError "prepared routing page height did not decrease")
    return state
termination_by ref.height

/-- Probe only. It requires a complete bounded prepared leaf image and has no
global owner, background publication integration or request-time compilation. -/
def scanPrepared (image : Image) (reader : Reader) (scope : String) (ref : PageMap.Ref)
    (node limit byteLimit deadline : Nat) (initial : Scan) : IO Scan := do
  if !initial.complete then return initial
  if initial.arcs.size ≥ limit || initial.bytes ≥ byteLimit || (← IO.monoMsNow) ≥ deadline then
    return {initial with complete := false}
  let loaded ← reader.snapshot.load ref
  let range : PageMap.KeyRange := ⟨arcPrefix node,s!"route:arc:{node};"⟩
  let mut result := {initial with pages := initial.pages+1}
  match loaded.page with
  | .leaf _ =>
    let some leaf := image.find reader.snapshot scope ref |
      throw (IO.userError "bounded prepared image does not cover this leaf")
    for cell in select range leaf.cells do
      let some payload := cell.payload | continue
      if result.arcs.size ≥ limit || result.bytes+payload.size > byteLimit ||
          (← IO.monoMsNow) ≥ deadline then return {result with complete := false}
      let some arc ← cell.read | throw (IO.userError "prepared live routing row disappeared")
      unless cell.name == arcName node arc.evidence && arc.targets.all (· < reader.manifest.counts.targets) &&
          arc.next.all (· < reader.manifest.counts.nodes) &&
          arc.group.all (· < reader.manifest.counts.nodes) do throw (IO.userError "foreign routing incidence")
      result := {result with arcs := result.arcs.push arc,bytes := result.bytes+payload.size}
    return result
  | .branch children =>
    for child in children do
      if range.overlaps child then
        if _smaller : child.height < ref.height then
          result ← scanPrepared image reader scope child node limit byteLimit deadline result
        else throw (IO.userError "routing page height did not decrease")
        if !result.complete then return result
    return result
termination_by ref.height

def outcome (action : IO (Option Arc)) : IO (Except String (Option Arc)) := do
  try return .ok (← action) catch error => return .error error.toString

def sameOutcome : Except String (Option Arc) → Except String (Option Arc) → Bool
  | .ok left,.ok right => left == right
  | .error left,.error right => left == right
  | _,_ => false

def controls : IO Json := do
  let evidence := String.ofList (List.replicate 64 'a')
  let mut checked := 0
  for kind in [:7] do
    let arc : Arc := ⟨evidence,kind,if kind == 0 || kind == 2 then some 0 else none,#[0,1],#[1,0]⟩
    let payload := encode arc
    let cell ← Cell.capture (arcName 0 evidence,some payload)
    check (sameOutcome (← outcome cell.read) (← outcome (some <$> decode payload))) "valid cached arc changed"
    for candidate in #[payload.extract 0 (payload.size-1),payload.push 0,ByteArray.empty] do
      let cell ← Cell.capture (arcName 0 evidence,some candidate)
      check (sameOutcome (← outcome cell.read) (← outcome (some <$> decode candidate))) "invalid selected arc changed"
      check ((select ⟨"unrelated:","unrelated;"⟩ [cell]).isEmpty) "unrelated invalid row was selected"
      checked := checked+1
    checked := checked+1
  let tombstone ← Cell.capture ("route:arc:0:deleted",none)
  check ((← tombstone.read).isNone) "tombstone became a live arc"
  return Json.mkObj [("validAndMalformedArcs",toJson checked),("tombstonePreserved",toJson true),
    ("invalidUnselectedRowsDoNotThrow",toJson true)]

def run (sourcePath output : String) (full : Bool := false) : IO Unit := do
  let root : System.FilePath := .mk output
  check (!(← root.pathExists)) "fresh probe output required"
  IO.FS.createDirAll root
  save root "controls.json" (← controls)
  let source ← PageMap.pin (.mk sourcePath)
  let some basis ← Index.openShared? source | throw (IO.userError "existing shared index is not prepared")
  let some reader ← Synapses.Routing.Store.open? basis | throw (IO.userError "existing routing projection is not prepared")
  let scope := source.head.identity
  save root "input.json" (Json.mkObj [("source",toJson source.head),("index",toJson reader.snapshot.head),
    ("manifest",toJson reader.manifest),("scope",toJson scope),("adopted",toJson false)])
  let some ref := reader.snapshot.head.root | throw (IO.userError "routing index has no root")
  let began ← IO.monoNanosNow
  let (image,leaves,pages) ← prepareAt reader scope ref (Image.empty reader.snapshot scope) 0 0 ((← IO.monoMsNow)+30000)
  let preparedNs := (← IO.monoNanosNow)-began
  check (leaves > 0) "empty routing leaf diagnostic"
  let some (offset,_) := image.entries.state.recent.index.toArray[0]? |
    throw (IO.userError "prepared image has no retained leaf")
  let some entry := image.entries.find? offset | throw (IO.userError "retained leaf is missing")
  check ((image.find reader.snapshot scope entry.ref).isSome) "positive prepared lookup failed"
  check ((image.find reader.snapshot "foreign-scope" entry.ref).isNone) "foreign scope hit"
  check ((image.find reader.snapshot scope {entry.ref with checksum := "foreign"}).isNone)
    "different full descriptor hit"
  check ((image.find {reader.snapshot with head := {reader.snapshot.head with identity := "foreign"}}
    scope entry.ref).isNone) "different database identity hit"
  let mut rows := #[]
  let count := min (if full then 65536 else 1024) reader.manifest.counts.nodes
  check (count > 0) "empty routing node population"
  let nodes := (Array.range count).map fun i => i*reader.manifest.counts.nodes/count
  let deadline := (← IO.monoMsNow)+120000
  let mut original := #[]
  for node in nodes do original := original.push (← scanAt reader ref node 262144 (32*1024*1024) deadline {})
  for candidateFirst in #[false,true,false] do
    let mut times := #[]
    for candidate in #[candidateFirst,!candidateFirst] do
      let started ← IO.monoNanosNow
      let mut arcs := 0
      let mut bytes := 0
      for position in [:nodes.size] do
        let node := nodes[position]!
        let result ← if candidate then scanPrepared image reader scope ref node 262144 (32*1024*1024) deadline {}
          else scanAt reader ref node 262144 (32*1024*1024) deadline {}
        let some expected := original[position]? | throw (IO.userError "original scan result is absent")
        check (result.arcs == expected.arcs && result.bytes == expected.bytes &&
          result.pages == expected.pages && result.complete == expected.complete) "prepared scan differs from the original"
        check result.complete "routing probe deadline or budget expired"
        arcs := arcs+result.arcs.size
        bytes := bytes+result.bytes
      let elapsed := (← IO.monoNanosNow)-started
      times := times.push (Json.mkObj [("candidate",toJson candidate),("nanos",toJson elapsed),
        ("nodes",toJson nodes.size),("arcs",toJson arcs),("payloadBytes",toJson bytes)])
    rows := rows.push times
    save root "pairs.json" (toJson rows)
  let now ← PageMap.pin (.mk sourcePath)
  check (now.head == source.head) "read-only probe changed its source head"
  save root "report.json" (Json.mkObj [("componentOnly",toJson true),("adopted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("preparationNs",toJson preparedNs),
    ("preparedLeaves",toJson leaves),("visitedPreparationPages",toJson pages),
    ("chargedBytes",toJson image.charged),("allowanceBytes",toJson allowance),("pairs",toJson rows),
    ("allPublishedNodesMeasured",toJson (count == reader.manifest.counts.nodes)),
    ("exactArcsOrderBytesPagesCompletion",toJson true),("sourceHeadUnchanged",toJson true),
    ("globalOrPublicationLifecycleProven",toJson false),("wholeHookSpeedupEstablished",toJson false)])

def main (args : List String) : IO Unit := do
  match args with
  | ["observer-controls",output] => Eggshell.Research.PreparedRoutingObserver.controls output
  | ["observe",input] => Eggshell.Research.PreparedRoutingObserver.run input
  | ["full",source,output] => run source output true
  | [source,output] => run source output
  | _ => throw (IO.userError "[full] source-db fresh-output | observe capacity-input")
