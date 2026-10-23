import Eggshell.CanonicalSourceRecords
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

private structure Family where
  owner : String
  rows : Array StoredRow
  deriving FromJson
private structure UnitRow where
  family : Nat
  sharedRows : Option (Array Key)
  deriving FromJson
private structure Snapshot where
  families : Array Family
  units : Array UnitRow
  deriving FromJson
private structure Requirement where
  name : String
  path : String
  first : Nat
  last : Nat
  originalOwners : Array String
  deriving FromJson
private structure CaseRow where
  stage : Nat
  required : Array Requirement
  deriving FromJson

private def retained (requirement : Requirement) (keys : Array Key) : Bool :=
  let files := (keys.filter (fun key => key.file.relative == requirement.path)).map (·.file)
  files.any fun file => covered ⟨file,requirement.first,requirement.last⟩
    (keys.map fun key => ⟨key.file,key.line,key.line⟩)

/-- Offline candidate reachability only. No requirements enter the record
builder or runtime, and this is not a hook latency or adoption check. -/
def main (args : List String) : IO Unit := do
  let [specification,probes,destination] := args | throw (IO.userError "CanonicalRecordProbe SPEC PROBES OUTPUT")
  let cases ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk specification)) >>= fromJson? (α := Array CaseRow))
  let mut output := #[]
  for row in cases do
    let path := System.FilePath.mk probes / s!"probe-stage{row.stage}" / "selection.json"
    if !(← path.pathExists) then continue
    let snapshot ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson? (α := Snapshot))
    let mut candidates := #[]
    for familyIndex in List.finRange snapshot.families.size do
      let family := snapshot.families[familyIndex]
      let records := Records.prepare family.rows
      for unit in snapshot.units do
        if unit.family != familyIndex.val then continue
        let some keys := unit.sharedRows | continue
        let requested := (List.finRange family.rows.size).filter fun index => keys.contains family.rows[index].key
        let expanded := Records.close family.rows records requested
        candidates := candidates.push (family.owner,expanded.map (·.key))
    let results := row.required.map fun requirement =>
      let relevant := candidates.filter fun (owner,_) => requirement.originalOwners.contains owner
      let whole := relevant.filter fun (_,keys) => retained requirement keys
      Json.mkObj [("name",toJson requirement.name),("completeCandidates",toJson whole.size),
        ("candidateUnionCoversRange",toJson (retained requirement (relevant.flatMap Prod.snd)))]
    output := output.push (Json.mkObj [("stage",toJson row.stage),("requirements",toJson results)])
  IO.FS.writeFile (.mk destination) (toJson output).compress
  IO.println (toJson output).compress
