import Eggshell.DB.PageMap
open Lean Eggshell DB PageMap

#print axioms leaf_fits_bounded_rows
#print axioms leaf_fits_bounded_bytes
#print axioms large_leaf_splits

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)
private def name (i : Nat) : String :=
  let digits := toString i
  "row:" ++ String.ofList (List.replicate (8-digits.length) '0') ++ digits
private def value (i : Nat) : ByteArray := ByteArray.empty.push (i%251).toUInt8
private def rows (population : Nat) : List Row :=
  (List.range population).map fun i => (name i,some (value i))
private def all (snapshot : Snapshot) : IO (List Row) := do
  let found ← snapshot.foldRange ⟨"row:","row;"⟩ (fun found row => pure (found.push row)) #[]
  return found.toList

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "PageEncodingAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "new page encoding trial required"
    IO.FS.createDir root
    let initial ← create (root / "bulk.egg") "bounded-leaf-fixture"
    let started ← IO.monoMsNow
    let _ ← withWriter initial fun writer => do
      for row in rows 8192 do writer.put row.1 row.2
      writer.flush
      check ((← pin initial.directory).head == initial.head) "flush exposed uncommitted bulk root"
      check ((← writer.get (name 8191)) == some (value 8191)) "writer cannot read flushed rows"
    let bulkMs := (← IO.monoMsNow)-started
    let current ← pin initial.directory
    check ((← all current) == rows 8192 && (← all initial).isEmpty) "bulk split changed rows, order or old pin"
    let failed ← try
      let _ ← withWriter (α := Unit) current fun writer => do
        writer.put (name 9000) (some (value 9000))
        writer.flush
        throw (IO.userError "cancel after append")
      pure false
      catch _ => pure true
    check (failed && (← pin initial.directory).head == current.head) "cancelled flushed tail became visible"
    let _ ← withWriter current fun writer => writer.put (name 8192) (some (value 8192))
    check ((← all (← pin initial.directory)) == rows 8193) "recovery after cancelled tail lost a row"
    let legacy ← create (root / "legacy.egg") "legacy-leaf-fixture"
    check ((encode (.leaf (rows 200))).size ≤ 8192 && !leafFits (rows 200)) "legacy fixture is not a larger valid wire page"
    let _ ← withWriter legacy fun writer => do
      let leaf ← writer.appendPage (.leaf (rows 200))
      writer.root.set (some leaf)
    let old ← pin legacy.directory
    check ((← all old) == rows 200) "reader rejected a previously valid larger leaf"
    let _ ← withWriter old fun writer => writer.put (name 200) (some (value 200))
    check ((← all (← pin legacy.directory)) == rows 201 && (← all old) == rows 200)
      "updating a larger old leaf changed its domain or historical pin"
    IO.FS.writeFile (root / "results.json") (Json.mkObj [("bulkRows",toJson (8192 : Nat)),
      ("bulkMs",toJson bulkMs),("exactOrderedRows",toJson true),("flushNotPublished",toJson true),
      ("cancelRecovery",toJson true),("oldLargeLeafReadable",toJson true),("oldPinsPreserved",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
    IO.println "bounded page encoding: ordered rows, atomic flush, recovery and old large leaves passed"
    return 0
  catch error => IO.eprintln error.toString; return 1
