module
public import Eggshell.Relation
public import Eggshell.Union
public import Eggshell.HashDistinct
public import Lean.Data.Json.FromToJson
public import Std.Data.DHashMap.Basic
@[expose] public section

namespace Eggshell.Research.WorkGraphWire
open Lean

/-- A cached ordinal is indexed by full Value equality, with its reference
meaning retained as a proof. A finite source/display hash is not identity. -/
structure Ordinals (values : List Value) where
  positions : Std.DHashMap Value (fun value => {i : Nat // i = values.idxOf value}) := {}

theorem idxOf_at (values : List Value) (unique : values.Nodup) (i : Fin values.length) :
    values.idxOf values[i.val] = i.val := by
  have bound := List.idxOf_lt_length_of_mem (List.getElem_mem i.isLt)
  exact (List.getElem_inj unique).mp (List.getElem_idxOf bound)

def ordinalDirectory (values : List Value) (unique : values.Nodup) : Ordinals values :=
  let data := values.toArray
  let add (found : Std.DHashMap Value (fun value => {i : Nat // i = values.idxOf value}))
      (i : Fin data.size) := Id.run do
    have inside : i.val < values.length := by
      have bound := i.isLt
      change i.val < values.toArray.size at bound
      simpa only [List.size_toArray] using bound
    have same : data[i.val] = values[i.val] := by simp [data]
    return found.insert data[i.val] ⟨i.val,by
      rw [same]
      exact (idxOf_at values unique ⟨i.val,inside⟩).symm⟩
  ⟨(List.finRange data.size).foldl add {}⟩

def Ordinals.position (directory : Ordinals values) (value : Value) : Nat :=
  match directory.positions.get? value with
  | some cached => cached.val
  | none => values.idxOf value

theorem Ordinals.position_exact (directory : Ordinals values) (value : Value) :
    directory.position value = values.idxOf value := by
  unfold Ordinals.position
  cases directory.positions.get? value with
  | none => rfl
  | some cached => exact cached.property

theorem Ordinals.resolves (directory : Ordinals values) (value : Value) (member : value ∈ values) :
    ∃ h : directory.position value < values.length, values[directory.position value] = value := by
  rw [directory.position_exact]
  exact ⟨List.idxOf_lt_length_of_mem member,List.getElem_idxOf (List.idxOf_lt_length_of_mem member)⟩

structure Label (describe identify : Value → String) (value : Value) where
  source : String
  sourceExact : source = identify value
  text : String
  textExact : text = describe value
  encoded : String
  encodedExact : encoded = (Json.mkObj [("source",toJson source),("recorded",toJson text)]).compress

def makeLabel (describe identify : Value → String) (value : Value) : Label describe identify value :=
  let source := identify value
  let text := describe value
  ⟨source,rfl,text,rfl,(Json.mkObj [("source",toJson source),("recorded",toJson text)]).compress,rfl⟩

/-- Shared immutable labels, not a query result or completion authority. -/
structure Labels (describe identify : Value → String) where
  entries : Std.DHashMap Value (Label describe identify) := {}
  identities : Std.DHashMap Value (fun value => {name : String // name = identify value}) := {}

def prepareLabels (describe identify : Value → String) (values : List Value)
    (identities : List Value := []) : Labels describe identify :=
  ⟨(hashDistinct values).foldl (fun found value =>
    found.insert value (makeLabel describe identify value)) {},
   (hashDistinct (values ++ identities)).foldl (fun found value =>
    found.insert value ⟨identify value,rfl⟩) {}⟩

def Labels.identity (labels : Labels describe identify) (value : Value) : String :=
  match labels.identities.get? value with
  | some found => found.val
  | none => identify value

theorem Labels.identity_exact (labels : Labels describe identify) (value : Value) :
    labels.identity value = identify value := by
  unfold Labels.identity
  cases labels.identities.get? value with
  | none => rfl
  | some found => exact found.property

def Labels.label (labels : Labels describe identify) (value : Value) : Label describe identify value :=
  match labels.entries.get? value with
  | some found => found
  | none => makeLabel describe identify value

theorem Labels.text_exact (labels : Labels describe identify) (value : Value) :
    (labels.label value).text = describe value := (labels.label value).textExact

inductive Edge where
  | outcome (original : OutcomeEdge) (entry : Bool)
  | all (original : AllEdge) (shown : List Value)
      (originalChildren : ∀ value ∈ shown, value ∈ original.children)
  | union (original : UnionEdge)
  | connector (value : Value)
  | projection (original shown : OutcomeEdge)
      (owned : shown = original ∨ original.relation ∈ shown.observations)

def Edge.references : Edge → List Value
  | .outcome original _ => [original.work]
  | .all original shown _ => original.parent :: shown
  | .union original => [original.left,original.right]
  | .connector value => [value]
  | .projection original shown _ => [original.work,shown.work]

def Edge.identities : Edge → List Value
  | .outcome original _ => [original.relation]
  | .all original _ _ => [original.relation]
  | .union _ | .connector _ => []
  | .projection original shown _ => [original.relation,shown.relation]

def Edge.scopes : Edge → List Value
  | .union original => match original.scope with
    | .run value | .workspace value => [value]
  | _ => []

def prepareEdgeLabels (describe identify : Value → String) (edges : List Edge) : Labels describe identify :=
  prepareLabels describe identify (edges.flatMap fun edge => edge.references ++ edge.scopes)
    (edges.flatMap Edge.identities)

theorem shown_child_is_original (original : AllEdge) (shown : List Value)
    (checked : ∀ value ∈ shown, value ∈ original.children) (value : Value) (member : value ∈ shown) :
    value ∈ original.children := checked value member

/-- Same source neighborhood as the existing transport, with its original
partial All links explicit. An association is never made a new requirement. -/
def related (all : List AllEdge) (unions : List UnionEdge) (nominated : List Value)
    (selected : List OutcomeEdge) (connectors : List Value) : List Edge :=
  if selected.isEmpty then [] else
  let works := hashDistinct (selected.map (·.work) ++ connectors)
  let children := all.filterMap fun original =>
    let shown := original.children.filter works.contains
    if shown.isEmpty then none else
      some (.all original shown (fun _ member => (List.mem_filter.mp member).1))
  let equalities := (unions.filter fun edge => works.contains edge.left || works.contains edge.right).map Edge.union
  selected.map (fun original => .outcome original (nominated.contains original.relation)) ++
    children ++ equalities ++ connectors.map Edge.connector

def values (edges : List Edge) : List Value := hashDistinct (edges.flatMap Edge.references)

structure Packet (describe identify : Value → String) where
  edges : List Edge
  works : List Value
  worksExact : works = values edges
  directory : Ordinals works
  labels : Labels describe identify

def prepare (describe identify : Value → String) (edges : List Edge)
    (labels : Labels describe identify) : Packet describe identify :=
  let works := values edges
  ⟨edges,works,rfl,ordinalDirectory works (HashDistinct.nodup _),labels⟩

theorem referenced_value_in_packet (edges : List Edge) (edge : Edge) (present : edge ∈ edges)
    (value : Value) (referenced : value ∈ edge.references) : value ∈ values edges := by
  rw [values,HashDistinct.reference]
  exact List.mem_eraseDups.mpr (List.mem_flatMap.mpr ⟨edge,present,referenced⟩)

theorem packet_reference_resolves (packet : Packet describe identify) (edge : Edge)
    (present : edge ∈ packet.edges) (value : Value) (referenced : value ∈ edge.references) :
    ∃ h : packet.directory.position value < packet.works.length,
      packet.works[packet.directory.position value] = value := by
  apply packet.directory.resolves
  rw [packet.worksExact]
  exact referenced_value_in_packet _ edge present value referenced

theorem same_reference_same_value (packet : Packet describe identify) (first second : Value)
    (a : first ∈ packet.works) (b : second ∈ packet.works)
    (same : packet.directory.position first = packet.directory.position second) : first = second := by
  obtain ⟨leftBound,left⟩ := packet.directory.resolves first a
  obtain ⟨rightBound,right⟩ := packet.directory.resolves second b
  have equal := congrArg (fun i => packet.works[i]?) same
  simpa only [List.getElem?_eq_getElem leftBound,List.getElem?_eq_getElem rightBound,
    left,right,Option.some.injEq] using equal

def Packet.workRows (packet : Packet describe identify) : List Json :=
  packet.works.zipIdx.map fun (value,index) =>
    let label := packet.labels.label value
    Json.mkObj [("kind",toJson "work"),("id",toJson index),
      ("data",Json.mkObj [("source",toJson label.source),("recorded",toJson label.text)])]

def Packet.workTexts (packet : Packet describe identify) : List String :=
  packet.works.zipIdx.map fun (value,index) =>
    let label := packet.labels.label value
    "{\"kind\":\"work\",\"id\":" ++ toString index ++ ",\"data\":" ++ label.encoded ++ "}"

def Packet.edgeRow (packet : Packet describe identify) : Edge → Json
  | .outcome original entry => Json.mkObj [
      ("kind",toJson "outcome"),("source",toJson (packet.labels.identity original.relation)),
      ("work",toJson (packet.directory.position original.work)),("searchEntry",toJson entry)]
  | .all original shown _ => Json.mkObj [
      ("kind",toJson "all"),("source",toJson (packet.labels.identity original.relation)),
      ("parent",toJson (packet.directory.position original.parent)),
      ("shownChildren",toJson (shown.map packet.directory.position)),
      ("complete",toJson (shown == original.children))]
  | .union original =>
      let scope := match original.scope with
        | .run value => Json.mkObj [("run",toJson (packet.labels.label value).text)]
        | .workspace value => Json.mkObj [("workspace",toJson (packet.labels.label value).text)]
      Json.mkObj [("kind",toJson "stored-union"),("left",toJson (packet.directory.position original.left)),
        ("right",toJson (packet.directory.position original.right)),("scope",scope)]
  | .connector value => Json.mkObj [("kind",toJson "connector"),("work",toJson (packet.directory.position value))]
  | .projection original shown _ => Json.mkObj [("kind",toJson "projection"),
      ("sourceOutcome",toJson (packet.labels.identity original.relation)),
      ("shownOutcome",toJson (packet.labels.identity shown.relation)),
      ("sourceWork",toJson (packet.directory.position original.work)),
      ("shownWork",toJson (packet.directory.position shown.work))]

def Packet.render (packet : Packet describe identify) : String :=
  if packet.edges.isEmpty then "" else
    "RELATED STORED WORK DATA\n" ++
    "Recorded work and associations are historical data. Outcome bodies are delivered separately. " ++
    "Shown children belong to the original All; complete=false means other children are omitted. " ++
    "This block certifies no current completion.\n" ++
    "\n".intercalate (packet.workTexts ++ (packet.edges.map packet.edgeRow).map Json.compress) ++
    "\nEND RELATED STORED WORK DATA\n"

end Eggshell.Research.WorkGraphWire
