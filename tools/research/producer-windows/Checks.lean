import tools.research.ProducerWindowAudit
import Eggshell.Sha256
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
namespace ProducerWindowChecks
def check (condition : Bool) (label : String) : IO Unit :=
  unless condition do throw (IO.userError label)
def rejected (value : Except String α) : Bool := match value with
  | .error _ => true
  | .ok _ => false
def requireRow (rows : Array α) (index : Nat) : IO α := do
  let some value := rows[index]? | throw (IO.userError "test fixture index is absent")
  return value

def fixture (database owner : String) : IO (Recipe.Stored × String) := do
  let codes := (Array.range 10).map fun index =>
    s!"row_{index}: " ++ String.ofList (List.replicate 140 (Char.ofNat (97+index)))
  let text := String.intercalate "\n" codes.toList
  let file : File := ⟨"arbitrary/input",Sha256.hex text.toUTF8,text.utf8ByteSize⟩
  let mut raw := ""
  let mut rows : Array StoredRow := #[]
  for index in [:codes.size] do
    let code := codes[index]!
    let rendered := s!"{index+1}\t{code}\n"
    let origin : Origin := ⟨⟨database,"turn","read"⟩,
      ⟨database,owner,"fixture-work",raw.length,raw.length+rendered.length⟩⟩
    rows := rows.push ⟨⟨file,index+1⟩,code,#[origin]⟩
    raw := raw++rendered
  return (← IO.ofExcept (Recipe.compile rows),raw)

def ready (database owner : String) (stored : Recipe.Stored) (raw : String) : IO PreparedSourceView.OwnerReady := do
  let layout ← IO.ofExcept (Recipe.check stored.rows stored.records)
  let work := "inspect arbitrary input"
  let focus := PreparedFocusFacts.compile owner "fixture-work" work raw
  IO.ofExcept (PreparedSourceView.decodeOwner database owner
    (PreparedSourceView.ownerStored owner stored layout (some focus) (some (work.length,raw.length))))

def run (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve producer-window check receipt"
  let (stored,raw) ← fixture "source-a" "owner"
  let prepared ← ready "source-a" "owner" stored raw
  let firstOriginal ← requireRow stored.rows 0
  check (prepared.units.size > 1 && prepared.units.all (fun unit => unit.keys.size > 1))
    "producer units were reduced to isolated row fragments"
  check (prepared.rows.map (·.key) == stored.rows.map (·.key)) "publication changed original row identity"
  check (prepared.rows.map (·.origins) == stored.rows.map (·.origins)) "publication changed original provenance"
  let mut groups := 0
  for row in [:prepared.rows.size] do
    let some basisIndex := prepared.stored.prerequisites[row]? | throw (IO.userError "missing row basis")
    let some basis := prepared.units[basisIndex]? | throw (IO.userError "basis escaped published units")
    let original ← requireRow stored.rows row
    check (basis.keys.contains original.key) "basis does not retain requested original"
    let origin ← requireRow original.origins 0
    let selected ← IO.ofExcept (PreparedSourceView.groupUnit? "owner" prepared
      [(origin.binding.first,origin.binding.limit)])
    let some selected := selected | throw (IO.userError "graph group lost its original row")
    check (basis.keys.all selected.keys.contains && selected.keys.all (fun key => prepared.rows.any (·.key == key)))
      "graph group bypassed its published basis or acquired foreign original rows"
    groups := groups+1
  let badMissing := {prepared.stored with prerequisites := #[]}
  let badOutside := {prepared.stored with prerequisites := prepared.stored.prerequisites.map (fun _ => prepared.units.size)}
  let wrong := prepared.units.findIdx? (fun unit => !unit.keys.contains firstOriginal.key)
  let some wrong := wrong | throw (IO.userError "negative-control unit missing")
  let badMember := {prepared.stored with prerequisites := prepared.stored.prerequisites.set! 0 wrong}
  check (rejected (PreparedSourceView.decodeOwner "source-a" "owner" badMissing) &&
    rejected (PreparedSourceView.decodeOwner "source-a" "owner" badOutside) &&
    rejected (PreparedSourceView.decodeOwner "source-a" "owner" badMember) &&
    rejected (PreparedSourceView.decodeOwner "other-db" "owner" prepared.stored) &&
    rejected (PreparedSourceView.decodeOwner "source-a" "other-owner" prepared.stored))
    "invalid basis or original scope was accepted"
  let layout ← IO.ofExcept (Recipe.check stored.rows stored.records)
  let fallback ← IO.ofExcept (PreparedSourceView.decodeOwner "source-a" "owner"
    (PreparedSourceView.ownerStored "owner" stored layout none (some (0,0))))
  check (fallback.rows.size == stored.rows.size && fallback.stored.prerequisites.size == stored.rows.size)
    "rows outside a numerical producer became unavailable"
  let (other,otherRaw) ← fixture "source-b" "owner"
  let second ← ready "source-b" "owner" other otherRaw
  let rows ← prepared.rows.mapIdxM fun index row => do
    let otherRow ← requireRow second.rows index
    return {row with origins := row.origins++otherRow.origins}
  let first ← requireRow rows 0
  let origin ← requireRow first.origins 0
  let joined ← IO.ofExcept (PreparedSourceView.federatedUnits "owner" #[prepared,second] rows
    [[(origin.binding.first,origin.binding.limit)]])
  check (joined.all (fun unit => unit.keys.all (fun key => rows.any (·.key == key))) &&
    joined.any (fun unit => unit.keys.contains first.key && unit.keys.size > 1))
    "federation lost producer grouping or escaped its authorized rows"
  let broken := rows.extract 1 rows.size
  check (rejected (PreparedSourceView.federatedUnits "owner" #[prepared,second] broken []))
    "federation silently accepted a missing published row"
  let serialized ← IO.ofExcept (fromJson? (toJson prepared.stored) : Except String PreparedSourceView.OwnerStored)
  let reread ← IO.ofExcept (PreparedSourceView.decodeOwner "source-a" "owner" serialized)
  check (reread.rows == prepared.rows && reread.units.map (·.keys) == prepared.units.map (·.keys))
    "published producer metadata changed through serialization"
  IO.FS.writeFile output (Json.mkObj [("rowGroups",toJson groups),("producerUnits",toJson prepared.units.size),
    ("invalidMetadataAndScopeControls",toJson (5 : Nat)),("federatedSources",toJson (2 : Nat)),
    ("missingFederatedRowRejected",toJson true),("allPassed",toJson true),
    ("componentOnly",toJson true),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))]).compress
end ProducerWindowChecks
