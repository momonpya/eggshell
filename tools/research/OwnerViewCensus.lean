import Main
import Eggshell.ContractAudit
import tools.research.StudyRuntime
import tools.research.CensusProducerWindows
open Lean Eggshell Eggshell.DB Eggshell.Research Eggshell.Synapses Eggshell.Synapses.CanonicalSource
namespace OwnerViewCensus
structure Plan where
  source : String
  sourceFiles : Array (String × String)
  owners : Array String
  expectedHead : Json
  output : String
  deriving FromJson
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def bytes [ToJson α] (value : α) := (toJson value).compress.utf8ByteSize
def verify (plan : Plan) : IO Unit := do
  for (name,expected) in plan.sourceFiles do
    check ((← ArtifactHash.hex (.mk plan.source/name)) == expected) "native source file changed"

/-- Read the exact original publication. Do not create a DB, cache, index,
query, model request or source write. Counterfactual metadata is transient. -/
def run (input : String) : IO Unit := do
  let plan ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk input)) >>= fromJson? (α := Plan))
  check (!(← System.FilePath.pathExists plan.output)) "preserve completed owner census"
  verify plan
  let source ← PageMap.pin (.mk plan.source)
  check (toJson source.head == plan.expectedHead) "original publication differs from the recorded query"
  let reader ← Persistence.Store.NodeReader.new source
  let entries ← Build.entries source
  let mut metrics := #[]
  let began ← IO.monoMsNow
  for entry in entries do
    let document ← Build.document reader entry.id
    unless plan.owners.contains document.owner do continue
    let started ← IO.monoMsNow
    let focus := PreparedFocusFacts.compile document.owner document.work
      (document.workText.getD "") (document.source.getD "")
    let original ← if document.native then do
      let (registry,_) ← addPublishedDocument source entry.id document {} {}
      IO.ofExcept (Recipe.compile registry.store)
    else pure (⟨#[],[]⟩ : Recipe.Stored)
    let layout ← IO.ofExcept (Recipe.check original.rows original.records)
    let parent := PreparedSourceView.ownerStored document.owner original layout (some focus)
    let ready ← IO.ofExcept (PreparedSourceView.decodeOwner source.head.identity document.owner parent)
    let groups := ProducerWindows.units document.owner original layout
      (document.workText.getD "").length (document.source.getD "").length focus.originalWindows.length
    let catalogue := groups.toList.map (·.indices)
    let descriptor := {parent.descriptor with catalogue}
    let published := {parent.plan with units := groups}
    let prerequisites := ProducerWindows.prerequisites published.costs published.units
    let windowStored := toJson parent
      |>.setObjVal! "plan" (toJson published)
      |>.setObjVal! "descriptor" (toJson descriptor)
      |>.setObjVal! "prerequisites" (toJson prerequisites)
    let geometry ← match document.source with
      | none => pure none
      | some _ => do
        let view ← IO.ofExcept (ObservedRecordView.make source.head.identity document)
        pure (some ({header := view.header,spans := view.spans,prices := view.prices} : ObservedRecordView.Geometry))
    let geometric := (ObservedRecordView.CachedGeometry.make document.owner geometry).encodedBytes
    let focusBytes := bytes (some focus)
    -- OwnerReady.bytes encodes the optional focus's value, without Option's wrapper.
    let countedFocus := bytes focus
    check (ready.bytes == bytes parent.descriptor+countedFocus) "parent accounting formula changed"
    metrics := metrics.push (Json.mkObj [("owner",toJson document.owner),("native",toJson document.native),
      ("rows",toJson original.rows.size),("windows",toJson focus.originalWindows.length),
      ("records",toJson parent.records.length),("parentUnits",toJson parent.plan.units.size),
      ("producerUnits",toJson groups.size),("parentCountedBytes",toJson ready.bytes),
      ("parentStoredBytes",toJson (bytes parent)),("parentDescriptorBytes",toJson (bytes parent.descriptor)),
      ("focusValueBytes",toJson countedFocus),("optionalFocusBytes",toJson focusBytes),
      ("planBytes",toJson (bytes parent.plan)),("recordBytes",toJson (bytes parent.records)),
      ("scopeBytes",toJson (bytes parent.scopes)),("geometryBytes",toJson geometric),
      ("producerDescriptorBytes",toJson (bytes descriptor)),
      ("producerProjectedBytes",toJson (bytes descriptor+countedFocus)),
      ("producerFullStoredBytes",toJson windowStored.compress.utf8ByteSize),
      ("producerPlanBytes",toJson (bytes published)),("producerPrerequisiteBytes",toJson (bytes prerequisites)),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started))])
  check (metrics.size == plan.owners.size && plan.owners.toList.eraseDups.length == plan.owners.size)
    "census lost a requested owner or contains duplicates"
  let sum (key : String) : IO Nat := metrics.foldlM (fun total row => do
    return total+(← IO.ofExcept (row.getObjValAs? Nat key))) 0
  let geometry ← sum "geometryBytes"
  let parent := (← sum "parentCountedBytes")+geometry
  let producerProjected := (← sum "producerProjectedBytes")+geometry
  let producerFull := (← sum "producerFullStoredBytes")+geometry
  verify plan
  IO.FS.writeFile (.mk plan.output) (Json.mkObj [("sourceHead",toJson source.head),("owners",toJson metrics),
    ("parentCountedBytes",toJson parent),("producerProjectedBytes",toJson producerProjected),
    ("producerFullStoredBytes",toJson producerFull),("geometryBytes",toJson geometry),
    ("parentChargedBeforeLease",toJson (SharedReadViews.charge parent)),
    ("producerProjectedChargedBeforeLease",toJson (SharedReadViews.charge producerProjected)),
    ("producerFullChargedBeforeLease",toJson (SharedReadViews.charge producerFull)),
    ("viewCapacity",toJson SharedReadViews.capacity),("elapsedMs",toJson ((← IO.monoMsNow)-began)),
    ("sourceHashesBeforeAndAfter",toJson true),("productModified",toJson false),
    ("actualQueries",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("counterfactualMetadataNotHookMeasurement",toJson true),("adopted",toJson false)]).compress
end OwnerViewCensus
def main : List String → IO Unit
  | [input] => OwnerViewCensus.run input
  | _ => throw (IO.userError "OwnerViewCensus PLAN")
