module
public import Eggshell.PublicationWire
@[expose] public section
namespace Eggshell.Plugin.Publication
open Lean DB Synapses
def reference : String := Blake3.hex (Blake3.digest "eggshell.project-service".toUTF8 [
  (include_str "ProjectRead.lean").toUTF8,
  (include_str "ProjectReadSnapshot.lean").toUTF8,
  (include_str "ProjectHookRead.lean").toUTF8,(include_str "Config.lean").toUTF8,
  (include_str "ProjectIngress.lean").toUTF8,(include_str "ProcessGroup.lean").toUTF8,
  (include_str "ProjectReadWire.lean").toUTF8,
  (include_str "SynapseRecommend.lean").toUTF8,
  (include_str "SynapticTransport.lean").toUTF8,
  (include_str "SynapseTransport.lean").toUTF8,
  (include_str "../tools/research/CheckedOriginalRecipe.lean").toUTF8,
  (include_str "Handoff.lean").toUTF8,
  (include_str "BuiltinSearch.lean").toUTF8,(include_str "KeyedSearchClient.lean").toUTF8,
  (include_str "SemanticMatcher.lean").toUTF8,
  (include_str "../tools/research/SelectionReceipt.lean").toUTF8,
  (include_str "../tools/VerifiedWinnerCoverage.lean").toUTF8,
  (include_str "../tools/research/CarriedSelectionValue.lean").toUTF8,
  (include_str "../tools/research/OwnerPalette.lean").toUTF8,
  (include_str "../tools/research/SourceProjectionDictionary.lean").toUTF8,
  (include_str "../tools/research/CompactProvenance.lean").toUTF8,
  (include_str "../tools/research/CompactHandoff.lean").toUTF8,
  (include_str "../tools/research/CompactSearchWire.lean").toUTF8,
  (include_str "../tools/research/ReplyHold.lean").toUTF8,
  (include_str "../tools/research/DeliveryKeys.lean").toUTF8,
  (include_str "../tools/research/OwnerPaletteLease.lean").toUTF8,
  (include_str "../tools/research/PreparedSourceCosts.lean").toUTF8,
  (include_str "../tools/research/AdvisoryBundles.lean").toUTF8,
  (include_str "../tools/research/PreparedFileUnits.lean").toUTF8,
  (include_str "../tools/research/PreparedPlanMetadata.lean").toUTF8,
  (include_str "../tools/research/SharedReadViews.lean").toUTF8,
  (include_str "../tools/research/SourceViewBatch.lean").toUTF8,
  (include_str "SourcePlan.lean").toUTF8,(include_str "AdvisoryBundleData.lean").toUTF8,
  (include_str "../tools/research/BindingPageScan.lean").toUTF8,
  (include_str "../tools/research/BindingValueCodec.lean").toUTF8,
  (include_str "../tools/research/SharedMetadataCache.lean").toUTF8,
  (include_str "PublicationWire.lean").toUTF8,(include_str "PublicationClient.lean").toUTF8,
  (include_str "PublicationStream.lean").toUTF8,
  (include_str "../tools/research/OwnedIngress.lean").toUTF8,
  (include_str "PublicationService.lean").toUTF8,(include_str "NativePublication.lean").toUTF8,
  (include_str "ProjectSources.lean").toUTF8,(include_str "ProjectAccess.lean").toUTF8,
  (include_str "ProjectInputs.lean").toUTF8,
  (include_str "ProjectStore.lean").toUTF8,(include_str "ProjectPublication.lean").toUTF8,
  (include_str "ProjectViews.lean").toUTF8,
  (include_str "../tools/research/PreparedOwnerArena.lean").toUTF8,
  (include_str "CanonicalSourcePrepared.lean").toUTF8,(include_str "DaemonWire.lean").toUTF8,
  (include_str "HookWire.lean").toUTF8,(include_str "HookCommand.lean").toUTF8,
  (include_str "PluginModel.lean").toUTF8,(include_str "DB/PageMap.lean").toUTF8,
  (include_str "DB/Sidecar.lean").toUTF8,
  (include_str "PreparationPlan.lean").toUTF8,(include_str "PreparationRegistry.lean").toUTF8,
  (include_str "PreparationService.lean").toUTF8,(include_str "Worker.lean").toUTF8,
  (include_str "OperationWire.lean").toUTF8,(include_str "OperationPlan.lean").toUTF8,
  (include_str "OperationPool.lean").toUTF8,
  CanonicalSource.Cache.implementation.toUTF8,Index.implementation.toUTF8])

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "reference output path required")
  let actual ← generation
  unless actual == reference do throw (IO.userError "compiled source stamp differs from native reference")
  IO.FS.writeFile (.mk output) (Json.mkObj [("sameAlgorithmAndCurrentSource",toJson true),
    ("actual",toJson actual),("nativeReference",toJson reference),
    ("answeringModelCalls",toJson (0 : Nat))]).compress
end Eggshell.Plugin.Publication
def main := Eggshell.Plugin.Publication.main
