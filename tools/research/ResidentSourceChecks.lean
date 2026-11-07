module
public import tools.research.PreparedOwnerArena
public import Eggshell.Sha256
public import Lean
@[expose] public section
namespace Eggshell.Research.ResidentSourceChecks
open Lean Synapses CanonicalSource
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

/-- Independent copy of the parent's resident representation. These three
data fields had no reader in the complete parent native closure. -/
structure ParentReady where
  database : String
  owner : String
  stored : Recipe.Stored
  layout : Recipe.Checked stored.rows
  checked : Recipe.check stored.rows stored.records = .ok layout
  original : ∃ registry, CanonicalSource.load database stored.rows = .ok registry
  scope : stored.rows.all (fun row => row.origins.all (fun origin =>
    origin.binding.database == database && origin.binding.owner == owner)) = true
  palette : OwnerPalette.Ready stored layout
  units : PreparedFileUnits.Ready owner stored.rows layout
  published : PublishedPlanMetadata.Ready owner stored layout

@[noinline,nospecialize] def parentPrepare (database owner : String) (stored : Recipe.Stored) : Except String ParentReady := do
  -- Validation is byte-for-byte unchanged in the candidate. Reuse that core
  -- and independently construct and retain all three parent-only fields.
  let ready ← PreparedOwnerArena.prepare database owner stored
  return ⟨ready.database,ready.owner,ready.stored,ready.layout,ready.checked,ready.original,ready.scope,
    OwnerPalette.prepare ready.stored ready.layout,PreparedFileUnits.prepare ready.owner ready.stored.rows ready.layout,
    PublishedPlanMetadata.prepare ready.owner ready.stored ready.layout⟩

def ParentReady.core (ready : ParentReady) : PreparedOwnerArena.Ready :=
  ⟨ready.database,ready.owner,ready.stored,ready.layout,ready.checked,ready.original,ready.scope⟩

theorem original_core_exact (database owner : String) (stored : Recipe.Stored) :
    (parentPrepare database owner stored).map ParentReady.core = PreparedOwnerArena.prepare database owner stored := by
  unfold parentPrepare
  cases prepared : PreparedOwnerArena.prepare database owner stored <;> rfl

run_elab do
  let environment ← getEnv
  for removed in [`Eggshell.Synapses.PreparedOwnerArena.Ready.palette,
      `Eggshell.Synapses.PreparedOwnerArena.Ready.units,`Eggshell.Synapses.PreparedOwnerArena.Ready.published] do
    if environment.contains removed then throwError "Unused duplicate resident representation returned"
  let some body := (environment.find? ``PreparedOwnerArena.preparePublished).bind (·.value?) |
    throwError "Missing publication check"
  unless body.getUsedConstants.contains ``PublishedPlanMetadata.check do
    throwError "Resident simplification removed the persisted metadata check"

def signature (ready : PreparedOwnerArena.Ready) : Json :=
  toJson (ready.database,ready.owner,ready.stored,ready.layout.catalogue.map (·.map Fin.val))

@[noinline,nospecialize] def timed (action : Unit → Except String α) : IO (α × Nat) := do
  let began ← IO.monoMsNow
  let result ← IO.ofExcept (action ())
  return (result,(← IO.monoMsNow)-began)

def run (fixture : System.FilePath) (expected : String) (output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous resident evidence"
  let bytes ← IO.FS.readBinFile fixture
  check (Sha256.hex bytes == expected) "fixed raw evidence changed"
  let value ← IO.ofExcept (Json.parse (String.fromUTF8! bytes))
  let parts ← IO.ofExcept (((value.getObjValD "handoff").getObjValD "packet").getObjValAs? (Array Json) "parts")
  let mut raw := #[]
  for part in parts do
    let shared := part.getObjValD "shared"
    if shared != Json.null then raw := raw ++ (← IO.ofExcept (shared.getObjValAs? (Array StoredRow) "rows"))
  check (raw.size == 5702) "preserve original row inventory"
  let rows ← IO.ofExcept (Delivery.merge raw)
  let mut groups : Std.HashMap (String × String) (Array StoredRow) := {}
  for row in rows do
    let mut origins : Std.HashMap (String × String) (Array Origin) := {}
    for origin in row.origins do
      let key := (origin.binding.database,origin.binding.owner)
      origins := origins.insert key ((origins[key]?.getD #[]).push origin)
    for (key,kept) in origins.toArray do groups := groups.insert key ((groups[key]?.getD #[]).push {row with origins := kept})
  let sources := groups.toArray
  check (!sources.isEmpty) "source owner inventory is empty"
  let mut trials := #[]
  for repetition in [:3] do
    let old := fun _ => sources.mapM fun ((database,owner),rows) => parentPrepare database owner ⟨rows,[]⟩
    let fresh := fun _ => sources.mapM fun ((database,owner),rows) => PreparedOwnerArena.prepare database owner ⟨rows,[]⟩
    let (before,after) ← if repetition == 1 then do
        let after ← timed fresh
        let before ← timed old
        pure (before,after)
      else do
        let before ← timed old
        let after ← timed fresh
        pure (before,after)
    check (before.1.map (signature ∘ ParentReady.core) == after.1.map signature)
      "resident owner lost original rows, catalogue or scope"
    for ready in after.1 do
      let metadata := (PublishedPlanMetadata.prepare ready.owner ready.stored ready.layout).metadata
      check ((PreparedOwnerArena.preparePublished ready.database ready.owner ready.stored metadata).isOk)
        "published metadata rejected"
      if !metadata.costs.isEmpty then
        check (!(PreparedOwnerArena.preparePublished ready.database ready.owner ready.stored {metadata with costs := #[]}).isOk)
          "tampered published costs accepted"
    trials := trials.push (Json.mkObj [("repetition",toJson repetition),("parentMs",toJson before.2),("candidateMs",toJson after.2),
      ("removedResidentDescriptorWireBytes",toJson (before.1.foldl (fun total ready => total+ready.palette.bytes) 0)),
      ("originalRowsCatalogueAndScopeExact",toJson true)])
  IO.FS.writeFile output (Json.mkObj [("allPassed",toJson true),("rawRows",toJson raw.size),
    ("canonicalRows",toJson rows.size),("owners",toJson sources.size),("trials",toJson trials),
    ("metadataValidationRetained",toJson true),("componentOnly",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.ResidentSourceChecks
