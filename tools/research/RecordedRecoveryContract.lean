module
import all Eggshell.ContentCapture
import all Eggshell.ContentMetadata
public meta import Lean
open Lean Eggshell

#print axioms ContentCapture.recovery_complete_domain
#print axioms ContentCapture.Supplement.bound_original
#print axioms ContentMetadata.Line.original_projection

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``ContentCapture.recoverSaved,
        #[``ContentCapture.recoveryInputs,``ContentCapture.refineSaved,``ContentCapture.correlate],
        #[``DB.PageMap.withWriter,``ContentMetadata.stage,``ContentMetadata.stageSupplement]),
      (``ContentMetadata.catalogSupplement,
        #[``ContentCapture.recoveryInputs,``ContentMetadata.originalInputs,``ContentMetadata.validAlias],
        #[``ContentCapture.recoverSaved,``ContentCapture.correlate,``DB.PageMap.withWriter]),
      (``ContentMetadata.loadSupplement?,
        #[``ContentMetadata.catalogSupplement,``ContentMetadata.Header.boundTo],
        #[``ContentCapture.recoverSaved,``ContentCapture.refineSaved,``ContentCapture.correlate,``FileSystem.openRead]),
      (``ContentMetadata.publishedCoordinates,#[``ContentMetadata.load?],
        #[``ContentMetadata.loadSupplement?,``ContentCapture.recoverSaved,``ContentCapture.correlate])] do
    let mut pending := [root]
    let mut seen : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if seen.contains name then continue
      seen := seen.insert name
      let some declaration := environment.find? name | throwError "missing recovery boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." || dependency.toString.startsWith "ContentCorrespondence." then
            pending := dependency :: pending
    for name in required do
      unless seen.contains name do throwError "{root} bypasses {name}"
    for name in forbidden do
      if seen.contains name then throwError "{root} reaches forbidden {name}"
    logInfo m!"Audited recorded recovery boundary {root}"
