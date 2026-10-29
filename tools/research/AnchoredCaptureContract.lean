module
import all Eggshell.ContentCapture
import all Eggshell.ContentMetadata
public meta import Lean
open Lean Eggshell

#print axioms ContentRuns.checked_run_original
#print axioms ContentCapture.Supplement.bound_original
#print axioms ContentCapture.Supplement.producer_is_provenance
#print axioms ContentMetadata.Header.bound_original
#print axioms ContentMetadata.Header.producer_is_provenance

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``ContentCapture.finish,
        #[``ContentRuns.checkedRun?,``ContentCorrespondence.anchoredRun?,``ContentCapture.scanUsing],
        #[``DB.PageMap.withWriter,``ContentMetadata.stage]),
      (``ContentCapture.refineSaved,
        #[``ContentCapture.recordedAnchors,``ContentRuns.checkedRun?],
        #[``DB.PageMap.withWriter,``ContentMetadata.stage]),
      (``ContentMetadata.load?,#[``ContentMetadata.Header.boundTo],
        #[``ContentCapture.scan,``ContentCapture.scanUsing,``ContentCapture.refineSaved]),
      (``ContentMetadata.catalogSupplement,
        #[``ContentCapture.Supplement.boundTo,``ContentMetadata.validAlias],
        #[``ContentCapture.scan,``ContentCapture.scanUsing,``ContentCapture.refineSaved,``DB.PageMap.withWriter]),
      (``ContentMetadata.stageSupplement,#[``ContentMetadata.catalogSupplement,``ContentMetadata.supplementStampKey],
        #[``ContentCapture.scan,``ContentCapture.scanUsing,``ContentCapture.refineSaved]),
      (``ContentMetadata.loadSupplement?,#[``ContentMetadata.catalogSupplement],
        #[``ContentCapture.scan,``ContentCapture.scanUsing,``ContentCapture.refineSaved,``DB.PageMap.withWriter])] do
    let mut pending := [root]
    let mut seen : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if seen.contains name then continue
      seen := seen.insert name
      let some declaration := environment.find? name | throwError "missing anchor boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." || dependency.toString.startsWith "ContentCorrespondence." then
            pending := dependency :: pending
    for name in required do
      unless seen.contains name do throwError "{root} bypasses {name}"
    for name in forbidden do
      if seen.contains name then throwError "{root} reaches forbidden {name}"
    logInfo m!"Audited anchored correspondence boundary {root}"
