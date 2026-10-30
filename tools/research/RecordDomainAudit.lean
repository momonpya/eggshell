import tools.research.FrozenCanonicalBasis
import tools.research.AvailableDelivery
import Eggshell.CanonicalSourceRecords
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def inspect (rows : Array StoredRow) (records : List (Records.Record rows))
    (receipt : Json) : IO Json := do
  let raw ← IO.ofExcept ((receipt.getObjValD "data").getObjValAs? (Array Json) "sharedRows")
  let mut shown : Std.HashSet Key := {}
  for entry in raw do
    let range : Range ← IO.ofExcept (fromJson? (entry.getObjValD "source"))
    if let some file := range.subject.file? then
      for line in [range.first:range.last+1] do shown := shown.insert ⟨file,line⟩
  let mut split := #[]
  let mut byRow : Std.HashMap Nat (Array Nat) := {}
  let indexed := records.toArray
  for i in [:indexed.size] do
    let some record := indexed[i]? | throw (IO.userError "missing checked record")
    let present := record.indices.filter fun index => shown.contains rows[index].key
    let absent := record.indices.filter fun index => !shown.contains rows[index].key
    if !present.isEmpty && !absent.isEmpty then
      split := split.push (Json.mkObj [
        ("present",toJson (present.map fun index => rows[index].key)),
        ("absent",toJson (absent.map fun index => rows[index].key))])
    for row in record.indices do
      byRow := byRow.insert row.val ((byRow[row.val]?.getD #[]).push i)
  let mut seen : Std.HashSet Nat := {}
  let mut sizes : Array (Nat × Nat) := #[]
  for start in [:rows.size] do
    if seen.contains start then continue
    seen := seen.insert start
    let mut queue := #[start]
    let mut pending := 0
    let mut visitedRecords : Std.HashSet Nat := {}
    let mut chars := 0
    while pending < queue.size do
      let some current := queue[pending]? | throw (IO.userError "invalid finite record queue")
      pending := pending+1
      let some row := rows[current]? | throw (IO.userError "record crossed original row basis")
      chars := chars+(Packet.rowText row).length
      for recordId in byRow[current]?.getD #[] do
        if visitedRecords.contains recordId then continue
        visitedRecords := visitedRecords.insert recordId
        let some record := indexed[recordId]? | throw (IO.userError "record index crossed snapshot")
        for member in record.indices do
          unless seen.contains member.val do
            seen := seen.insert member.val
            queue := queue.push member.val
    sizes := sizes.push (queue.size,chars)
  let sorted := sizes.toList.mergeSort fun a b => b.2 ≤ a.2
  return Json.mkObj [("observedRows",toJson shown.size),("checkedRecordCount",toJson records.length),
    ("splitCheckedRecords",toJson split.size),("splits",toJson split),
    ("physicalComponents",toJson sizes.size),("largestComponents",toJson (sorted.take 10)),
    ("componentsOverPayloadBudget",toJson (sizes.countP fun entry => 120000 < entry.2))]

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh audit destination required")
  let out : System.FilePath := .mk destination
  check (!(← out.pathExists)) "preserve previous domain audit"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let before ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let (_,rows) ← FrozenCanonicalBasis.load study root
  let started ← IO.monoMsNow
  let records := Records.prepare rows
  let prepareMs := (← IO.monoMsNow)-started
  let receipts := root / "group-cue-trial/data/receipts"
  let mut reports := #[]
  for entry in ← receipts.readDir do
    let path := entry.path / "synaptic-delivery.json"
    if !(← path.pathExists) then continue
    let request ← read (entry.path / "request.json")
    let session ← IO.ofExcept ((request.getObjValD "data").getObjValAs? String "session")
    reports := reports.push ((← inspect rows records (← read path)).setObjVal! "session" (toJson session))
  let after ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  check (before.head == after.head) "read-only layout audit changed original source"
  IO.FS.createDirAll out
  IO.FS.writeFile (out / "result.json") (Json.mkObj [("source",toJson before.head),
    ("sourceUnchanged",toJson true),("prepareMs",toJson prepareMs),("reports",toJson reports),
    ("newActualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))]).pretty
  IO.println s!"Checked {records.length} immutable records against {reports.size} actual delivery packets"
