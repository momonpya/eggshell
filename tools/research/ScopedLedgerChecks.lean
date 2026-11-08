module
public import tools.research.ScopedLedgerNames
@[expose] public section

namespace Eggshell.Research.ScopedLedgerChecks
open Lean DB Synapses DeliveryLedger

def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)

def readProjection (path : System.FilePath) : IO (PageMap.Snapshot × Projection) := do
  let snapshot ← PageMap.pin path
  let rows ← snapshot.foldRange ⟨"range:","range;"⟩ (fun rows (name,bytes) => do
    let some bytes := bytes | throw (IO.userError "missing range")
    let some text := String.fromUTF8? bytes | throw (IO.userError "invalid range text")
    let value : Row ← IO.ofExcept (Json.parse text >>= fromJson?)
    check (value.valid && name == rowKey value && (toJson value).compress == text) "unvalidated real ledger range"
    return rows.push value) (#[] : Array Row)
  let bindings ← snapshot.foldRange ⟨"binding:","binding;"⟩ (fun rows (name,bytes) => do
    let some bytes := bytes | throw (IO.userError "missing binding")
    let some text := String.fromUTF8? bytes | throw (IO.userError "invalid binding text")
    let value : Binding ← IO.ofExcept (Json.parse text >>= fromJson?)
    check (value.valid && name == bindingKey value && (toJson value).compress == text) "unvalidated real ledger binding"
    return rows.push value) (#[] : Array Binding)
  let projection : Projection := {rows,bindings,verified := true,complete := false}
  check (projection.confirmable && rows.size ≥ 5000 && !bindings.isEmpty) "real confirmed projection required"
  return (snapshot,projection)

def writeOriginal (writer : PageMap.Writer) (projection : Projection) : IO Unit := do
  for row in projection.rows do
    let bytes := (toJson row).compress.toUTF8
    let prior ← writer.get (rowKey row)
    if prior == some bytes then continue
    if prior.isSome then throw (IO.userError "confirmed range digest collision")
    writer.put (rowKey row) (some bytes)
  for binding in projection.bindings do
    let bytes := (toJson binding).compress.toUTF8
    let prior ← writer.get (bindingKey binding)
    if prior == some bytes then continue
    if prior.isSome then throw (IO.userError "confirmed binding digest collision")
    writer.put (bindingKey binding) (some bytes)

def writeScoped (writer : PageMap.Writer) (projection : Projection) : IO (Nat × Nat) := do
  let mut rowMemo : ScopedLedgerNames.RowMemo := {}
  let mut bindingMemo : ScopedLedgerNames.BindingMemo := {}
  for value in projection.rows do
    let (name,next) := ScopedLedgerNames.row rowMemo value
    rowMemo := next
    let bytes := (toJson value).compress.toUTF8
    let prior ← writer.get name.val
    if prior == some bytes then continue
    if prior.isSome then throw (IO.userError "confirmed range digest collision")
    writer.put name.val (some bytes)
  for value in projection.bindings do
    let (name,next) := ScopedLedgerNames.binding bindingMemo value
    bindingMemo := next
    let bytes := (toJson value).compress.toUTF8
    let prior ← writer.get name.val
    if prior == some bytes then continue
    if prior.isSome then throw (IO.userError "confirmed binding digest collision")
    writer.put name.val (some bytes)
  return (rowMemo.size,bindingMemo.size)

def contents (snapshot : PageMap.Snapshot) : IO (Array PageMap.Row) :=
  snapshot.foldRange ⟨"","~"⟩ (fun rows row => pure (rows.push row)) #[]

def run (state root output : System.FilePath) : IO Unit := do
  check (!(← root.pathExists) && !(← output.pathExists)) "fresh scoped ledger result required"
  IO.FS.createDirAll root
  let saved ← IO.ofExcept (Json.parse (← IO.FS.readFile state))
  let reference : Reference ← IO.ofExcept (saved.getObjVal? "confirmedDelivery" >>= fromJson?)
  let data := state.parent.get!.parent.get!.parent.get!
  let ledger := data/"confirmed-delivery"/reference.context
  let (original,projection) ← readProjection ledger
  check (original.head == reference.head) "measurement must read the exact accepted ACK head"
  let mut results := #[]
  for repetition in [:3] do
    let order := if repetition%2 == 0 then #[false,true] else #[true,false]
    let mut arms := #[]
    for prepared in order do
      let path := root/s!"rep-{repetition}-{prepared}.egg"
      let initial ← PageMap.create path "scoped-ledger-native-control"
      let began ← IO.monoMsNow
      let ((prefixes,bindings),_,written) ← PageMap.withWriter initial fun writer => do
        if prepared then writeScoped writer projection else do writeOriginal writer projection; pure (0,0)
      let elapsed := (← IO.monoMsNow)-began
      let snapshot ← PageMap.pin path
      let data ← contents snapshot
      let noChangeStarted ← IO.monoMsNow
      let (_,_,repeatedBytes) ← PageMap.withWriter snapshot fun writer => do
        if prepared then discard <| writeScoped writer projection else writeOriginal writer projection
      let noChangeMs := (← IO.monoMsNow)-noChangeStarted
      check (repeatedBytes == 0) "reconfirmation rewrote unchanged entries"
      arms := arms.push (data,Json.mkObj [("scoped",toJson prepared),("elapsedMs",toJson elapsed),
        ("unchangedMs",toJson noChangeMs),("writtenBytes",toJson written),("rows",toJson data.size),
        ("subjectPrefixes",toJson prefixes),("bindingPrefixes",toJson bindings)])
    check (arms[0]!.1 == arms[1]!.1) "scoped writer changed any key, original payload or order"
    results := results.push (Json.mkObj [("repetition",toJson repetition),
      ("allIndexedBytesEqual",toJson true),("arms",toJson (arms.map (·.2)))])
  check ((← PageMap.pin ledger).head == original.head) "measurement changed original confirmed ledger"
  IO.FS.writeFile output (Json.mkObj [("source",toJson original.head),("sourcePath",toJson ledger.toString),
    ("ranges",toJson projection.rows.size),("bindings",toJson projection.bindings.size),
    ("results",toJson results),("nativeHookConnected",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty

end Eggshell.Research.ScopedLedgerChecks

#print axioms Eggshell.Research.ScopedLedgerNames.row_exact
#print axioms Eggshell.Research.ScopedLedgerNames.binding_exact

def main (args : List String) : IO Unit := do
  let [ledger,root,output] := args | throw (IO.userError "scoped-ledger LEDGER ROOT OUTPUT")
  Eggshell.Research.ScopedLedgerChecks.run (.mk ledger) (.mk root) (.mk output)
