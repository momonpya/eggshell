import tools.research.HistoryAccess
open Lean HistoryAccess
namespace HistoryWorkspace

def Span.key (span : HistoryAccess.Span) : Nat × Nat × Nat :=
  (span.document,span.first,span.stop)

/-- A page contains only a checked slice of one immutable stored original.
It has no graph equality, Union, completion or filesystem authority. -/
structure Page (store : Store) where
  document : Fin store.originals.size
  first : Nat
  stop : Nat
  nonempty : first < stop
  within : stop ≤ store.originals[document].text.size

def Page.span (page : Page store) : HistoryAccess.Span :=
  ⟨page.document.val,page.first,page.stop⟩

def Page.text (page : Page store) : String :=
  slice store.originals[page.document].text page.first page.stop

theorem Page.original_characters (page : Page store) : page.text.toList =
    (store.originals[page.document].text.extract page.first page.stop).toList := by
  simp [Page.text,slice]

theorem Page.inside_original (page : Page store) :
    page.first < page.stop ∧ page.stop ≤ store.originals[page.document].text.size :=
  ⟨page.nonempty,page.within⟩

def Page.check (store : Store) (span : HistoryAccess.Span) : Except String (Page store) := do
  if document : span.document < store.originals.size then
    if nonempty : span.first < span.stop then
      if within : span.stop ≤ store.originals[span.document].text.size then
        return ⟨⟨span.document,document⟩,span.first,span.stop,nonempty,within⟩
      else throw "receipt exceeds its immutable original"
    else throw "receipt is empty or reversed"
  else throw "receipt names another original domain"

def charge (session : Session) : Nat :=
  session.seen.foldl (fun total span => total+(span.stop-span.first)) 0

def fromRead (seen selected : HistoryAccess.Span) : Bool :=
  seen.document == selected.document && seen.first ≤ selected.first &&
    selected.first < selected.stop && selected.stop ≤ seen.stop

def selectionValid (session : Session) : Bool :=
  session.selected.all fun selected => session.seen.any (fromRead · selected)

def selectedCharge (session : Session) : Nat :=
  session.selected.foldl (fun total span => total+(span.stop-span.first)) 0

/-- The store is shared and immutable; this working state belongs to one
question. A receipt cannot silently move to a different project snapshot. -/
structure State (store : Store) where
  session : Session
  pages : Array (Page store)
  keysExact : pages.map (fun page => Span.key page.span) = session.seen.map Span.key
  unique : (session.seen.toList.map Span.key).Nodup
  charged : session.readCharacters = charge session
  bounded : session.readCharacters ≤ 16000
  pageBound : pages.size ≤ 64
  selectedFromRead : selectionValid session = true
  selectionBound : selectedCharge session ≤ 12000

def check (store : Store) (snapshot : String) (session : Session) : Except String (State store) := do
  unless snapshot == store.snapshot do throw "read state belongs to another snapshot"
  unless session.seen.size ≤ 64 do throw "read receipt directory exceeds decision bound"
  let pages ← session.seen.mapM (Page.check store)
  if keysExact : pages.map (fun page => Span.key page.span) = session.seen.map Span.key then
    if unique : (session.seen.toList.map Span.key).Nodup then
      if charged : session.readCharacters = charge session then
        if bounded : session.readCharacters ≤ 16000 then
          if pageBound : pages.size ≤ 64 then
            if selectedFromRead : selectionValid session = true then
              if selectionBound : selectedCharge session ≤ 12000 then
                return ⟨session,pages,keysExact,unique,charged,bounded,pageBound,selectedFromRead,selectionBound⟩
              else throw "selected original payload exceeds its bound"
            else throw "selected original was never read"
          else throw "visible page directory exceeds decision bound"
        else throw "original-read budget exceeded"
      else throw "read charge differs from its original receipt directory"
    else throw "duplicate receipt directory"
  else throw "visible pages differ from their read receipts"

def empty (store : Store) : Except String (State store) := check store store.snapshot {}

theorem State.visible_domain (state : State store) :
    state.pages.map (fun page => Span.key page.span) = state.session.seen.map Span.key := state.keysExact

theorem State.read_bound (state : State store) : charge state.session ≤ 16000 := by
  rw [← state.charged]
  exact state.bounded

def pageJson (store : Store) (receipt : Nat) (page : Page store) : Json :=
  let original := store.originals[page.document]
  Json.mkObj [("receipt",toJson receipt),("document",toJson page.document.val),
    ("owner",toJson original.document.owner),("first",toJson page.first),("stop",toJson page.stop),
    ("text",toJson page.text),("totalLength",toJson original.text.size)]

/-- Every opened page is present in full, once, in receipt order. Neither
search previews nor prior model output can become a page. -/
def visible (store : Store) (state : State store) : Json := Json.mkObj [
  ("snapshot",toJson store.snapshot),
  ("opened_originals",toJson (state.pages.mapIdx (pageJson store))),
  ("readCharacters",toJson state.session.readCharacters),
  ("readCharacterLimit",toJson (16000 : Nat))]

def reuse (store : Store) (state : State store) (receipt : Fin state.pages.size) :
    State store × Json × Bool :=
  let page := state.pages[receipt]
  let result := pageJson store receipt.val page
  let total := store.originals[page.document].text.size
  (state,result.setObjVal! "span" (toJson page.span)
    |>.setObjVal! "snapshot" (toJson store.snapshot)
    |>.setObjVal! "next" (if page.stop < total then toJson page.stop else Json.null),false)

theorem reuse_preserves_state (store : Store) (state : State store) (receipt : Fin state.pages.size) :
    (reuse store state receipt).1 = state := rfl

def execute (store : Store) (state : State store) (method : String) (arguments : Json) :
    Except String (State store × Json × Bool) := do
  if method == "read_history" then
    let document ← arguments.getObjValAs? Nat "document"
    let first ← arguments.getObjValAs? Nat "first"
    if let some receipt := (List.finRange state.pages.size).find? fun receipt =>
        state.pages[receipt].document.val == document && state.pages[receipt].first == first then
      return reuse store state receipt
  let (session,reply,finished) ← HistoryAccess.execute store state.session method arguments
  return (← check store store.snapshot session,reply,finished)

/-- The full read text is already in visible(). Avoid duplicating it in the
latest result. The actual API response and original text remain in the log. -/
def feedback (method : String) (reply : Json) : Json :=
  if method == "read_history" && !(reply.getObjVal? "error").isOk then
    Json.mkObj (["receipt","span","snapshot","owner","totalLength","next"].map fun field =>
      (field,reply.getObjValD field))
      |>.setObjVal! "textLocation" (toJson "opened_originals in the current workspace")
  else reply

end HistoryWorkspace
