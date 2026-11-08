module
public import Eggshell.CanonicalSourceCache
public import Eggshell.Handoff
@[expose] public section
namespace Eggshell.Research.PreparedLiteralReadback
open Lean Synapses Plugin
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def run (database output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous native literal readback"
  let source ← DB.PageMap.pin database
  let some manifest ← CanonicalSource.Cache.open? source .user | throw (IO.userError "actual private project view is not ready")
  let directory ← CanonicalSource.Cache.directory source .user
  let some index ← CanonicalSource.Cache.preparedAt? source directory manifest.metadata |
    throw (IO.userError "actual canonical metadata is not pinned")
  let reader ← Persistence.Store.NodeReader.new source
  let rows ← index.foldRange ⟨"view-document:","view-document;"⟩ (fun results row => do
    let some id := (row.1.drop "view-document:".length).toString.toNat? | return results
    let state ← index.readPayload (CanonicalSource.Cache.stateName id) >>= CanonicalSource.Cache.decode (α := CanonicalSource.Cache.OwnerState)
    let owner ← reader.outcome (← reader.locateOutcome id)
    let ready ← PreparedSourceView.readOwner index source.head.identity state.owner
    let some facts := ready.focus | throw (IO.userError "persisted owner lost prepared focus facts")
    let stored := facts.stored.literalData
    let expected := (PreparedFocusFacts.compile (Persistence.selectionKey owner.relation)
      (Persistence.selectionKey owner.work) ((Persistence.Store.text? owner.work).getD "")
      ((Persistence.Store.text? owner.outcome).getD "")).literalData
    check (stored == expected) "actual stored identifier facts differ from the original published owner"
    check (stored.owner == relationKey owner.relation && stored.work == relationKey owner.work)
      "Handoff's literal lookup key differs from the publication key"
    check (stored.windows == Persistence.Store.searchWindows owner) "persisted literal facts changed original window positions"
    return results.push (state.owner,stored.windows.length,stored.words.foldl (fun total names => total+names.length) (0 : Nat)))
    (#[] : Array (String × Nat × Nat))
  check (!rows.isEmpty && (rows.toList.map (·.1)).eraseDups.length == rows.size) "readback owner directory is empty or ambiguous"
  let after ← DB.PageMap.pin database
  check (source.head == after.head) "readback changed original publication"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("metadata",toJson manifest.metadata),
    ("owners",toJson rows.size),("windows",toJson (rows.foldl (fun total row => total+row.2.1) (0 : Nat))),
    ("identifiers",toJson (rows.foldl (fun total row => total+row.2.2) (0 : Nat))),
    ("allStoredFactsEqualOriginalCompilation",toJson true),("handoffLookupKeysExact",toJson true),
    ("originalWindowDirectoryExact",toJson true),("originalHeadUnchanged",toJson true),
    ("scope",toJson "native readback of actual persisted metadata; no hook hit counter or latency measurement"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.PreparedLiteralReadback
def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "literal readback DATABASE OUTPUT")
  Eggshell.Research.PreparedLiteralReadback.run (.mk database) (.mk output)
