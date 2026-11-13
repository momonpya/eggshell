import Eggshell.SynapseSource
import Std.Data.HashMap
import Std.Data.HashSet

open Lean Eggshell
namespace HistoryAccess

structure Document where
  owner : String
  invocation : String
  source : String
  deriving FromJson, ToJson, Inhabited

structure Span where
  document : Nat
  first : Nat
  stop : Nat
  deriving FromJson, ToJson, BEq, Inhabited

/-- Only a slice of a previously returned original can be proposed. This is
advisory evidence; this type has no completion/Union authority. -/
structure CheckedSpan (seen : Span) where
  first : Nat
  stop : Nat
  lower : seen.first ≤ first
  nonempty : first < stop
  upper : stop ≤ seen.stop

def authorize (seen : Span) (first stop : Nat) : Option (CheckedSpan seen) :=
  if h : seen.first ≤ first ∧ first < stop ∧ stop ≤ seen.stop then
    some ⟨first,stop,h.1,h.2.1,h.2.2⟩
  else none

theorem authorized_within_read (value : CheckedSpan seen) :
    seen.first ≤ value.first ∧ value.first < value.stop ∧ value.stop ≤ seen.stop :=
  ⟨value.lower,value.nonempty,value.upper⟩

structure Original where
  document : Document
  text : Array Char
  offsets : Array Nat
  deriving Inhabited

structure Store where
  snapshot : String
  originals : Array Original
  postings : Std.HashMap String (Array (Nat × Nat))
  neighbors : Std.HashMap Nat (Array Json)

def grams (text : String) : Array (String × Nat) := Id.run do
  let chars := text.toLower.toList.toArray
  let mut result := #[]
  for index in [:chars.size-1] do
    if !(chars[index]!.isWhitespace || chars[index+1]!.isWhitespace) then
      result := result.push (String.ofList [chars[index]!,chars[index+1]!],index)
  return result

/-- Preparation is done once for an immutable input, outside the tool loop.
The prototype uses a small fixed snapshot, not a new service for every chat. -/
def prepare (snapshot : String) (documents : Array Document)
    (neighbors : Std.HashMap Nat (Array Json) := {}) : Store := Id.run do
  let mut originals := #[]
  let mut postings : Std.HashMap String (Array (Nat × Nat)) := {}
  for id in [:documents.size] do
    let document := documents[id]!
    let decoded := Synapses.Extraction.layoutView document.source
    originals := originals.push ⟨document,decoded.text.toList.toArray,decoded.offsets⟩
    for (gram,position) in grams decoded.text do
      postings := postings.insert gram ((postings[gram]?.getD #[]).push (id,position))
  return ⟨snapshot,originals,postings,neighbors⟩

def slice (text : Array Char) (first stop : Nat) : String :=
  String.ofList ((text.extract first stop).toList)

def search (store : Store) (query : String) (cursor : Nat) : Json := Id.run do
  let mut counts : Std.HashMap Nat (Nat × Nat) := {}
  let mut used : Std.HashSet String := {}
  for (gram,_) in grams query do
    if used.contains gram then continue
    used := used.insert gram
    for (document,position) in store.postings[gram]?.getD #[] do
      let previous := counts[document]?.getD (0,position)
      counts := counts.insert document (previous.1+1,previous.2)
  let ranked := counts.toArray.qsort fun a b => a.2.1 > b.2.1 || (a.2.1 == b.2.1 && a.1 < b.1)
  let results := (ranked.extract cursor (cursor+6)).map fun (id,(score,position)) =>
    let original := store.originals[id]!
    Json.mkObj [("document",toJson id),("owner",toJson original.document.owner),
      ("score",toJson score),("first",toJson (position-80)),("totalCharacters",toJson original.text.size),
      ("preview",toJson (slice original.text (position-80) (position+180)))]
  return Json.mkObj [("results",toJson results),("total",toJson ranked.size),
    ("next",if cursor+results.size < ranked.size then toJson (cursor+results.size) else Json.null),
    ("snapshot",toJson store.snapshot),("previewIsDeliveryEvidence",toJson false)]

structure Session where
  seen : Array Span := #[]
  selected : Array Span := #[]
  readCharacters : Nat := 0
  deriving Inhabited

def getNat (arguments : Json) (name : String) : Except String Nat := arguments.getObjValAs? Nat name

def execute (store : Store) (session : Session) (name : String) (arguments : Json) :
    Except String (Session × Json × Bool) := do
  match name with
  | "search_history" =>
    let query ← arguments.getObjValAs? String "query"
    if query.length < 2 || query.length > 256 then throw "query must contain 2 to 256 characters"
    return (session,search store query (← getNat arguments "cursor"),false)
  | "list_history" =>
    let cursor ← getNat arguments "cursor"
    let entries := (store.originals.extract cursor (cursor+8)).mapIdx fun offset original =>
      Json.mkObj [("document",toJson (cursor+offset)),("owner",toJson original.document.owner),
        ("totalCharacters",toJson original.text.size),
        ("operation",toJson (String.ofList (original.document.invocation.toList.take 200)))]
    return (session,Json.mkObj [("entries",toJson entries),("total",toJson store.originals.size),
      ("next",if cursor+entries.size < store.originals.size then toJson (cursor+entries.size) else Json.null)],false)
  | "follow_history" =>
    let id ← getNat arguments "document"
    if id ≥ store.originals.size then throw "unknown document"
    let cursor ← getNat arguments "cursor"
    let entries := store.neighbors[id]?.getD #[]
    return (session,Json.mkObj [("edges",toJson (entries.extract cursor (cursor+8))),
      ("total",toJson entries.size),("next",if cursor+8 < entries.size then toJson (cursor+8) else Json.null)],false)
  | "read_history" =>
    let id ← getNat arguments "document"
    let some original := store.originals[id]? | throw "unknown document"
    let first ← getNat arguments "first"
    if first ≥ original.text.size then throw "read cursor is past the original text"
    let stop := min original.text.size (first+2400)
    if session.readCharacters+stop-first > 16000 then throw "session original-read budget exhausted"
    let span : Span := ⟨id,first,stop⟩
    return ({session with seen := session.seen.push span,readCharacters := session.readCharacters+stop-first},
      Json.mkObj [("receipt",toJson session.seen.size),("span",toJson span),
        ("snapshot",toJson store.snapshot),("owner",toJson original.document.owner),
        ("text",toJson (slice original.text first stop)),("totalLength",toJson original.text.size),
        ("next",if stop < original.text.size then toJson stop else Json.null)],false)
  | "select_evidence" =>
    let proposed ← arguments.getObjValAs? (Array Json) "spans"
    if proposed.isEmpty || proposed.size > 32 then throw "select 1 to 32 previously read spans"
    let mut selected : Array Span := #[]
    for item in proposed do
      let receipt ← getNat item "receipt"
      let some seen := session.seen[receipt]? | throw "unknown prior read receipt"
      let first ← getNat item "first"
      let stop ← getNat item "stop"
      let some checked := authorize seen first stop | throw "selected span was not read"
      selected := selected.push ⟨seen.document,checked.first,checked.stop⟩
    -- Duplicate/overlapping selections cannot buy additional capacity.
    let charge : Nat := selected.foldl (fun (count : Nat) (span : Span) => count+(span.stop-span.first)) 0
    if charge > 12000 then throw "selected original payload exceeds prototype budget"
    return ({session with selected},Json.mkObj [("selected",toJson selected),("characters",toJson charge)],true)
  | _ => throw "unknown read-only history tool"

def payload (store : Store) (session : Session) : Json := toJson (session.selected.map fun span =>
  let original := store.originals[span.document]!
  Json.mkObj [("snapshot",toJson store.snapshot),("owner",toJson original.document.owner),
    ("span",toJson span),("text",toJson (slice original.text span.first span.stop)),
    ("originalFirst",toJson original.offsets[span.first]!),
    ("originalStop",toJson original.offsets[span.stop]!)] )

end HistoryAccess
