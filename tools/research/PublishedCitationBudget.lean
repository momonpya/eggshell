module
public import Eggshell.CanonicalSourceCache
@[expose] public section
open Lean Eggshell Eggshell.Synapses Eggshell.Persistence.Store

def fieldsExcept (value : Json) (key : String) : Json := match value with
  | .obj object => Json.mkObj (object.toList.filter (·.1 != key))
  | _ => value

def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "citation-budget DATABASE OUTPUT")
  let target : System.FilePath := .mk output
  unless !(← target.pathExists) do throw (IO.userError "preserve budget attribution")
  let source ← DB.PageMap.pin (.mk database)
  let some canonical ← CanonicalSource.Cache.open? source .user | throw (IO.userError "canonical source not ready")
  let path ← CanonicalSource.Cache.directory source .user
  let some prepared ← CanonicalSource.Cache.preparedAt? source path canonical.metadata |
    throw (IO.userError "canonical root changed")
  let some shared ← Synapses.Index.open? source .user .shared | throw (IO.userError "shared source not ready")
  let reader ← NodeReader.new source
  let rows ← source.foldRange ⟨"candidate:","candidate;"⟩ (fun rows row => do
    let some id := (row.1.drop "candidate:".length).toString.toNat? | return rows
    if (← getNat source.get row.1) != 1 then return rows
    let owner ← reader.outcome (← reader.locateOutcome id)
    let name := Persistence.selectionKey owner.relation
    let metadata ← PreparedSourceView.readOwner prepared source.head.identity name
    let geometry ← ObservedRecordView.geometry? shared.index source.head.identity name ((← IO.monoMsNow)+30000)
    let newJson := toJson geometry
    let oldGeometry := match geometry with
      | none => Json.null
      | some view => (fieldsExcept (toJson view) "citations").setObjVal! "header" (fieldsExcept (toJson view.header) "citations")
    let oldBytes := (Json.arr #[toJson name,oldGeometry]).compress.utf8ByteSize
    let newBytes := (Json.arr #[toJson name,newJson]).compress.utf8ByteSize
    let dataBytes := (geometry.map fun view => (toJson view.citations).compress.utf8ByteSize).getD 0
    return rows.push (Json.mkObj [("id",toJson id),("owner",toJson name),("metadataBytes",toJson metadata.bytes),
      ("oldGeometryBytes",toJson oldBytes),("newGeometryBytes",toJson newBytes),("citationsBytes",toJson dataBytes)])) (#[] : Array Json)
  let total := fun key => rows.foldl (fun total row => total+((row.getObjValAs? Nat key).toOption.getD 0)) 0
  IO.FS.writeFile target (Json.mkObj [("source",toJson source.head),("owners",toJson rows.size),("rows",toJson rows),
    ("metadataBytes",toJson (total "metadataBytes")),("oldGeometryBytes",toJson (total "oldGeometryBytes")),
    ("newGeometryBytes",toJson (total "newGeometryBytes")),("citationBytes",toJson (total "citationsBytes")),
    ("allOwnersNotExactQuerySubset",toJson true),("modelCalls",toJson (0 : Nat))]).compress
